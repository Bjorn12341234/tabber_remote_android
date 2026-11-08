package com.tabberspak.remotekit

import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.channels.ClosedReceiveChannelException
import okhttp3.ConnectionSpec
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.TlsVersion
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import java.security.cert.CertificateException
import java.security.cert.X509Certificate
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference
import javax.net.ssl.SSLContext
import javax.net.ssl.SSLHandshakeException
import javax.net.ssl.X509TrustManager

/** One connection's text frames, whatever carries them (OkHttp here, a script in tests). */
interface RemoteTransport {
    suspend fun send(text: String)

    /** The next text frame, or null once the connection is closed. */
    suspend fun receive(): String?

    fun close()

    /** The WebSocket close code, once closed by the other side. */
    val closeCode: Int?
}

sealed class TransportFailure(message: String) : Exception(message) {
    /** The computer's key does not match the pin: never talk to it. */
    data object WrongKey : TransportFailure("the computer's key does not match")
    data class Closed(val code: Int?) : TransportFailure("the connection closed${code?.let { " ($it)" } ?: ""}")
    data class Unreachable(val why: String) : TransportFailure(why)
    /** The phone keeps the app off the local network (Android 17's permission). */
    data object LocalNetworkDenied : TransportFailure("the local network is not allowed")
}

/**
 * Checks the computer's key against the pin (spec 2, Trust): the SHA-256 of the leaf
 * certificate's DER SubjectPublicKeyInfo. No certificate authority, host name or expiry is
 * involved. With no pin yet (6-digit pairing) it accepts the key and remembers it.
 */
class PinTrust(val expected: String?) : X509TrustManager {
    private val seen = AtomicReference<String?>(null)

    val observed: String? get() = seen.get()

    override fun checkServerTrusted(chain: Array<out X509Certificate>?, authType: String?) {
        val leaf = chain?.firstOrNull() ?: throw CertificateException("no certificate")
        val pin = RemoteCrypto.pin(leaf.publicKey.encoded)
        seen.set(pin)
        if (expected != null && expected != pin) throw CertificateException("the computer's key does not match")
    }

    override fun checkClientTrusted(chain: Array<out X509Certificate>?, authType: String?) =
        throw CertificateException("not a server")

    override fun getAcceptedIssuers(): Array<X509Certificate> = emptyArray()
}

/** WebSocket over TLS 1.3 with OkHttp, pinned to the computer's key (spec 2). */
class OkHttpTransport(route: Route, pin: String?, base: OkHttpClient = shared) : RemoteTransport {
    private val trust = PinTrust(pin)
    private val frames = Channel<String>(capacity = Channel.UNLIMITED)
    private val failure = AtomicReference<Throwable?>(null)
    @Volatile override var closeCode: Int? = null
        private set
    private val socket: WebSocket

    /** The pin of the key the computer showed; for 6-digit pairing, read after `hello`. */
    val observedPin: String? get() = trust.observed

    init {
        val tls = SSLContext.getInstance("TLS").apply { init(null, arrayOf(trust), null) }
        val client = base.newBuilder()
            .sslSocketFactory(tls.socketFactory, trust)
            .hostnameVerifier { _, _ -> true } // the pin is the identity; names do not matter
            .connectionSpecs(listOf(ConnectionSpec.Builder(ConnectionSpec.RESTRICTED_TLS).tlsVersions(TlsVersion.TLS_1_3).build()))
            .build()
        val request = Request.Builder()
            .url(url(route))
            .header("Sec-WebSocket-Protocol", SUBPROTOCOL)
            .build()
        socket = client.newWebSocket(request, object : WebSocketListener() {
            override fun onMessage(webSocket: WebSocket, text: String) {
                if (text.toByteArray().size > MAX_FRAME_BYTES) {
                    webSocket.close(1009, "too big")
                    return
                }
                frames.trySend(text)
            }

            override fun onClosing(webSocket: WebSocket, code: Int, reason: String) {
                closeCode = code
                webSocket.close(code, null)
                frames.close()
            }

            override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
                closeCode = code
                frames.close()
            }

            override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                val wrongKey = pin != null && trust.observed != null && trust.observed != pin
                failure.compareAndSet(null, if (wrongKey || t.isWrongKey()) TransportFailure.WrongKey else TransportFailure.Unreachable(t.message ?: t.javaClass.simpleName))
                frames.close(failure.get())
            }
        })
    }

    override suspend fun send(text: String) {
        failure.get()?.let { throw it }
        if (!socket.send(text)) throw failure.get() ?: TransportFailure.Closed(closeCode)
    }

    override suspend fun receive(): String? = try {
        frames.receive()
    } catch (_: ClosedReceiveChannelException) {
        null
    }

    /** Sends a close frame if the connection is up, without waiting for it. */
    override fun close() {
        if (!socket.close(1000, null)) socket.cancel()
        frames.close()
    }

    private fun Throwable.isWrongKey(): Boolean {
        var cause: Throwable? = this
        while (cause != null) {
            if (cause is CertificateException && cause.message == "the computer's key does not match") return true
            if (cause is SSLHandshakeException && cause.cause is CertificateException) return cause.cause?.message == "the computer's key does not match"
            cause = cause.cause
        }
        return false
    }

    companion object {
        const val SUBPROTOCOL = "tabber-remote.v1"
        const val MAX_FRAME_BYTES = 65_536

        /** One client for every connection: its threads and connection pool are shared. */
        val shared: OkHttpClient by lazy {
            OkHttpClient.Builder()
                .connectTimeout(5, TimeUnit.SECONDS)
                .readTimeout(0, TimeUnit.SECONDS) // the protocol's own heartbeats watch the line
                .pingInterval(0, TimeUnit.SECONDS)
                .build()
        }

        /** `wss://host:port/`; an IPv6 host is bracketed and its zone written `%25`. */
        fun url(route: Route): String {
            val host = if (':' in route.host) "[${route.host.replace("%", "%25")}]" else route.host
            return "wss://$host:${route.port}/"
        }
    }
}
