package com.tabberspak.remotekit

import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.cancel
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.channels.ReceiveChannel
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeout
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger
import kotlin.time.Duration
import kotlin.time.Duration.Companion.seconds

/** What arrives besides answers: events, heartbeats, the end of the connection. */
sealed interface Incoming {
    data class EventArrived(val event: Event) : Incoming
    data class HeartbeatArrived(val heartbeat: Heartbeat) : Incoming
    data class Closed(val code: Int?) : Incoming
}

/** The app as `hello` names it (spec 6). */
data class AppInfo(val version: String, val build: String, val name: String = "Tabber Spak", val platform: String = "android") {
    fun toJson(): Json = jsonObject { put("name", name); put("version", version); put("build", build); put("platform", platform) }
}

/**
 * One connection to a host, as apple/RemoteKit's RemoteClient: requests matched to answers by id
 * (they may arrive out of order), events in order on [incoming], a heartbeat every two seconds.
 */
class RemoteClient(private val transport: RemoteTransport) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val nextId = AtomicInteger(0)
    private val pending = ConcurrentHashMap<Int, CompletableDeferred<Json>>()
    private val inbox = Channel<Incoming>(capacity = 1024)
    private val closed = AtomicBoolean(false)
    @Volatile private var failure: Throwable? = null
    private var reader: Job? = null

    val incoming: ReceiveChannel<Incoming> get() = inbox

    @Volatile var hello: HelloResult? = null
        private set

    val isClosed: Boolean get() = closed.get()

    /** Start reading, and send a heartbeat every two seconds (spec 6.1). */
    fun start(heartbeat: Duration = 2.seconds) {
        if (reader != null) return
        reader = scope.launch { readLoop() }
        scope.launch {
            while (isActive && !closed.get()) {
                delay(heartbeat)
                if (closed.get()) break
                runCatching { transport.send(HEARTBEAT) }
            }
        }
    }

    private suspend fun readLoop() {
        while (true) {
            val text = try {
                transport.receive()
            } catch (e: Throwable) {
                failure = e
                null
            } ?: break
            handle(text)
        }
        finish()
    }

    private fun finish() {
        if (!closed.compareAndSet(false, true)) return
        val reason = failure ?: TransportFailure.Closed(transport.closeCode)
        pending.values.forEach { it.completeExceptionally(reason) }
        pending.clear()
        inbox.trySend(Incoming.Closed(transport.closeCode))
        inbox.close()
        scope.cancel()
    }

    private fun handle(text: String) {
        val message = runCatching { Json.parse(text) }.getOrNull() ?: return
        val id = message["id"]?.int
        if (id != null) {
            val waiting = pending.remove(id) ?: return
            val error = message["error"]?.let(RemoteError::from)
            if (error != null) waiting.completeExceptionally(error) else waiting.complete(message["result"] ?: Json.Null)
            return
        }
        val method = message["method"]?.string ?: return
        val params = message["params"] ?: return
        when (method) {
            "event" -> {
                val topic = params["topic"]?.string ?: return
                val seq = params["seq"]?.int ?: return
                inbox.trySend(Incoming.EventArrived(Event(topic, seq, params["t"]?.double ?: 0.0, params["data"] ?: Json.Null)))
            }
            "heartbeat" -> runCatching { Heartbeat.from(JsonReader(params)) }.getOrNull()?.let {
                inbox.trySend(Incoming.HeartbeatArrived(it))
            }
        }
    }

    /** Calls a verb. Throws [RemoteError] for a refusal, [TransportFailure] when the line drops. */
    suspend fun call(method: String, params: Json = Json.Obj(emptyMap()), timeout: Duration = 15.seconds): Json {
        if (closed.get()) throw failure ?: TransportFailure.Closed(transport.closeCode)
        val id = nextId.incrementAndGet()
        val answer = CompletableDeferred<Json>()
        pending[id] = answer
        val request = jsonObject { put("jsonrpc", "2.0"); put("id", id); put("method", method); put("params", params) }
        try {
            transport.send(request.encode())
            return withTimeout(timeout) { answer.await() }
        } catch (_: TimeoutCancellationException) {
            throw TransportFailure.Unreachable("no answer to $method")
        } finally {
            pending.remove(id)
        }
    }

    suspend fun <T> call(method: String, params: Json, timeout: Duration = 15.seconds, decode: (JsonReader) -> T): T =
        decode(JsonReader(call(method, params, timeout), method))

    /** The first request on a connection. Its timeout is how long a dead address may hold up a reconnect. */
    suspend fun sayHello(app: AppInfo, timeout: Duration = 15.seconds): HelloResult {
        val params = jsonObject { put("app", app.toJson()); put("protocol_versions", Json.strings(PROTOCOL_VERSIONS)) }
        return call("hello", params, timeout, HelloResult::from).also { hello = it }
    }

    /** Pairs with the QR code's token (spec 4.3). */
    suspend fun pair(token: String, pin: String, device: DeviceSigner, name: String, model: String): PairResult {
        val challenge = hello?.let { Base64Url.decode(it.challenge) } ?: throw TransportFailure.Unreachable("say hello first")
        val pinHash = Base64Url.decode(pin) ?: throw IllegalArgumentException("not a pin")
        val tokenBytes = Base64Url.decode(token) ?: throw IllegalArgumentException("not a token")
        val message = RemoteCrypto.signedBytes(RemoteCrypto.pairContext, pinHash, challenge, tokenBytes)
        val params = jsonObject {
            put("mode", "token")
            put("token", token)
            put("device", jsonObject { put("name", name); put("model", model); put("key", Base64Url.encode(device.publicKeyDer)) })
            put("signature", Base64Url.encode(device.sign(message)))
        }
        return call("pair", params, decode = PairResult::from)
    }

    /**
     * The six digits both screens show for 6-digit pairing (spec 4.4): from the key the computer
     * showed in TLS ([observedPin]), this phone's key and the hello's challenge.
     */
    fun pairingCode(observedPin: String, device: DeviceSigner): String {
        val challenge = hello?.let { Base64Url.decode(it.challenge) } ?: throw TransportFailure.Unreachable("say hello first")
        val pinHash = Base64Url.decode(observedPin) ?: throw IllegalArgumentException("not a pin")
        return RemoteCrypto.pairingCode(pinHash, RemoteCrypto.sha256(device.publicKeyDer), challenge)
    }

    /**
     * Pairs without the QR code (spec 4.4): the computer shows the same six digits as
     * [pairingCode] and answers once someone clicks Allow there, or refuses after 120 seconds
     * (`pairing_timeout`) or at once (`pairing_declined`). Only on a host with `pair.code/1`.
     */
    suspend fun pairWithCode(observedPin: String, device: DeviceSigner, name: String, model: String): PairResult {
        val challenge = hello?.let { Base64Url.decode(it.challenge) } ?: throw TransportFailure.Unreachable("say hello first")
        val pinHash = Base64Url.decode(observedPin) ?: throw IllegalArgumentException("not a pin")
        val message = RemoteCrypto.signedBytes(RemoteCrypto.pairContext, pinHash, challenge)
        val params = jsonObject {
            put("mode", "code")
            put("device", jsonObject { put("name", name); put("model", model); put("key", Base64Url.encode(device.publicKeyDer)) })
            put("signature", Base64Url.encode(device.sign(message)))
        }
        return call("pair", params, timeout = 130.seconds, decode = PairResult::from)
    }

    /** Proves a paired device (spec 4.5). */
    suspend fun authenticate(pin: String, device: DeviceSigner): AuthResult {
        val challenge = hello?.let { Base64Url.decode(it.challenge) } ?: throw TransportFailure.Unreachable("say hello first")
        val pinHash = Base64Url.decode(pin) ?: throw IllegalArgumentException("not a pin")
        val message = RemoteCrypto.signedBytes(RemoteCrypto.authContext, pinHash, challenge)
        val params = jsonObject { put("device_id", device.deviceId); put("signature", Base64Url.encode(device.sign(message))) }
        return call("auth", params, decode = AuthResult::from)
    }

    suspend fun subscribe(topics: List<String>): Snapshot =
        call("session.subscribe", jsonObject { put("topics", Json.strings(topics)) }, decode = Snapshot::from)

    fun close() {
        transport.close()
        finish()
    }

    companion object {
        val PROTOCOL_VERSIONS = listOf("1.11")
        private const val HEARTBEAT = "{\"jsonrpc\":\"2.0\",\"method\":\"heartbeat\",\"params\":{}}"
    }
}
