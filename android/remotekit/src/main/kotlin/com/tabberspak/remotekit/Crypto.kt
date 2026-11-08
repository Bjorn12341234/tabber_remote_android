package com.tabberspak.remotekit

import java.io.ByteArrayOutputStream
import java.net.URI
import java.security.KeyFactory
import java.security.MessageDigest
import java.security.Signature
import java.security.spec.X509EncodedKeySpec
import java.util.Base64

/** The protocol's cryptography (spec 4), exact to the byte, as apple/RemoteKit's RemoteCrypto. */
object RemoteCrypto {
    val pairContext: ByteArray = "tabber-remote pair v1".toByteArray() + byteArrayOf(0)
    val authContext: ByteArray = "tabber-remote auth v1".toByteArray() + byteArrayOf(0)
    val codeContext: ByteArray = "tabber-remote code v1".toByteArray() + byteArrayOf(0)

    /** DER SubjectPublicKeyInfo prefix for an uncompressed P-256 key. */
    private val p256SpkiPrefix = byteArrayOf(
        0x30, 0x59, 0x30, 0x13, 0x06, 0x07, 0x2A, 0x86.toByte(), 0x48, 0xCE.toByte(), 0x3D, 0x02,
        0x01, 0x06, 0x08, 0x2A, 0x86.toByte(), 0x48, 0xCE.toByte(), 0x3D, 0x03, 0x01, 0x07, 0x03,
        0x42, 0x00,
    )

    fun sha256(data: ByteArray): ByteArray = MessageDigest.getInstance("SHA-256").digest(data)

    /** The pin: b64url(SHA-256(DER SubjectPublicKeyInfo)). */
    fun pin(spkiDer: ByteArray): String = Base64Url.encode(sha256(spkiDer))

    /** SubjectPublicKeyInfo from a raw X9.63 P-256 point. */
    fun spkiDer(x963: ByteArray): ByteArray? =
        if (x963.size == 65 && x963[0] == 0x04.toByte()) p256SpkiPrefix + x963 else null

    fun deviceId(publicKeyDer: ByteArray): String = Base64Url.encode(sha256(publicKeyDer))

    fun signedBytes(context: ByteArray, pinHash: ByteArray, challenge: ByteArray, token: ByteArray = ByteArray(0)): ByteArray =
        context + pinHash + challenge + token

    fun verify(publicKeyDer: ByteArray, signatureDer: ByteArray, message: ByteArray): Boolean = try {
        val key = KeyFactory.getInstance("EC").generatePublic(X509EncodedKeySpec(publicKeyDer))
        Signature.getInstance("SHA256withECDSA").run {
            initVerify(key)
            update(message)
            verify(signatureDer)
        }
    } catch (_: Exception) {
        false
    }

    /** The six digits both screens show (spec 4.4). */
    fun pairingCode(pinHash: ByteArray, deviceIdHash: ByteArray, challenge: ByteArray): String {
        val digest = sha256(codeContext + pinHash + deviceIdHash + challenge)
        var value = 0L
        for (i in 0 until 4) value = (value shl 8) or (digest[i].toLong() and 0xFF)
        return String.format("%06d", value % 1_000_000)
    }
}

object Base64Url {
    fun encode(data: ByteArray): String = Base64.getUrlEncoder().withoutPadding().encodeToString(data)

    /** Null for anything that is not unpadded base64url. */
    fun decode(text: String): ByteArray? {
        if (!text.all { it in 'A'..'Z' || it in 'a'..'z' || it in '0'..'9' || it == '-' || it == '_' }) return null
        if (text.length % 4 == 1) return null
        return try { Base64.getUrlDecoder().decode(text) } catch (_: IllegalArgumentException) { null }
    }
}

/** Where a computer can be reached: `name:port`, `ipv4:port` or `[ipv6]:port`. */
data class Route(val host: String, val port: Int) {
    override fun toString(): String = if (':' in host) "[$host]:$port" else "$host:$port"

    companion object {
        fun parse(text: String): Route? {
            if (text.startsWith("[")) {
                val close = text.indexOf(']')
                if (close < 0 || !text.startsWith(":", close + 1)) return null
                val port = text.substring(close + 2).toPortOrNull() ?: return null
                return Route(text.substring(1, close), port)
            }
            val colon = text.lastIndexOf(':')
            if (colon <= 0) return null
            val port = text.substring(colon + 1).toPortOrNull() ?: return null
            return Route(text.substring(0, colon), port)
        }

        private fun String.toPortOrNull(): Int? =
            if (isNotEmpty() && all { it in '0'..'9' }) toIntOrNull()?.takeIf { it in 0..65535 } else null
    }
}

/** The QR code's link (spec 4.2), as the phone's camera hands it to the app. */
data class PairingLink(
    val versions: List<String>,
    val hostId: String,
    val name: String,
    val pin: String,
    val token: String,
    val routes: List<Route>,
) {
    companion object {
        const val SCHEME = "tabber-remote"

        fun parse(link: String): PairingLink? {
            val uri = try { URI(link) } catch (_: Exception) { return null }
            if (uri.scheme != SCHEME || uri.rawAuthority != "pair") return null
            val fields = HashMap<String, String>()
            for (item in (uri.rawQuery ?: return null).split('&')) {
                if (item.isEmpty()) continue
                val eq = item.indexOf('=')
                val key = percentDecode(if (eq < 0) item else item.substring(0, eq)) ?: return null
                val value = percentDecode(if (eq < 0) "" else item.substring(eq + 1)) ?: return null
                fields[key] = value
            }
            val id = fields["id"] ?: return null
            val pin = fields["spki"] ?: return null
            val token = fields["tok"] ?: return null
            val hosts = fields["hosts"] ?: return null
            if (Base64Url.decode(pin)?.size != 32 || Base64Url.decode(token)?.size != 16) return null
            val routes = hosts.split(',').filter { it.isNotEmpty() }.mapNotNull(Route::parse)
            if (routes.isEmpty()) return null
            return PairingLink(
                versions = (fields["v"] ?: "1").split(',').filter { it.isNotEmpty() },
                hostId = id,
                name = fields["name"] ?: "Tabber Studio",
                pin = pin,
                token = token,
                routes = routes,
            )
        }

        /** RFC 3986 percent-decoding of a query component: `+` stays `+`, as in URLComponents. */
        private fun percentDecode(text: String): String? {
            val out = ByteArrayOutputStream()
            var i = 0
            while (i < text.length) {
                val c = text[i]
                if (c == '%') {
                    if (i + 2 >= text.length) return null
                    val byte = text.substring(i + 1, i + 3).toIntOrNull(16) ?: return null
                    out.write(byte)
                    i += 3
                } else {
                    out.write(c.toString().toByteArray())
                    i++
                }
            }
            return out.toString(Charsets.UTF_8)
        }
    }
}
