package com.tabberspak.remotekit

import java.security.KeyFactory
import java.security.KeyPair
import java.security.KeyPairGenerator
import java.security.PrivateKey
import java.security.Signature
import java.security.spec.ECGenParameterSpec
import java.security.spec.PKCS8EncodedKeySpec
import java.util.Base64

/** The phone's own key (spec 4.1): it proves this is the phone that paired. */
interface DeviceSigner {
    /** DER SubjectPublicKeyInfo. */
    val publicKeyDer: ByteArray

    /** An ECDSA P-256 SHA-256 signature, DER. */
    fun sign(message: ByteArray): ByteArray

    val deviceId: String get() = RemoteCrypto.deviceId(publicKeyDer)
}

/**
 * A key in memory: tests, and the emulator. On a phone the app keeps its key in the Android
 * Keystore instead, where it never leaves the device (app/.../KeystoreSigner.kt).
 */
class SoftwareSigner(private val privateKey: PrivateKey, override val publicKeyDer: ByteArray) : DeviceSigner {
    override fun sign(message: ByteArray): ByteArray = Signature.getInstance("SHA256withECDSA").run {
        initSign(privateKey)
        update(message)
        sign()
    }

    /** The private key's PKCS#8 encoding, for keeping it with [publicKeyDer] (the JDK may leave the point out). */
    val pkcs8: ByteArray get() = privateKey.encoded

    companion object {
        /** A key kept as its two halves: PKCS#8 and SubjectPublicKeyInfo. */
        fun fromParts(pkcs8: ByteArray, publicKeyDer: ByteArray): SoftwareSigner =
            SoftwareSigner(KeyFactory.getInstance("EC").generatePrivate(PKCS8EncodedKeySpec(pkcs8)), publicKeyDer)

        fun generate(): SoftwareSigner {
            val pair: KeyPair = KeyPairGenerator.getInstance("EC")
                .apply { initialize(ECGenParameterSpec("secp256r1")) }
                .generateKeyPair()
            return SoftwareSigner(pair.private, pair.public.encoded)
        }

        /** A PKCS#8 key ("BEGIN PRIVATE KEY"), as the protocol's test keys are written. */
        fun fromPem(pem: String): SoftwareSigner {
            val body = pem.lines().filterNot { it.startsWith("-----") }.joinToString("").trim()
            return fromPkcs8(Base64.getMimeDecoder().decode(body))
        }

        /** The key's public point comes from the PKCS#8 itself (RFC 5915's publicKey field). */
        fun fromPkcs8(der: ByteArray): SoftwareSigner {
            val private = KeyFactory.getInstance("EC").generatePrivate(PKCS8EncodedKeySpec(der))
            val point = Der.ecPublicPoint(der) ?: throw IllegalArgumentException("the key carries no public point")
            val spki = RemoteCrypto.spkiDer(point) ?: throw IllegalArgumentException("not an uncompressed P-256 point")
            return SoftwareSigner(private, spki)
        }
    }
}

/** Just enough DER to read an EC private key's public point. */
internal object Der {
    private class Tlv(val tag: Int, val start: Int, val end: Int)

    private fun read(bytes: ByteArray, at: Int): Tlv? {
        if (at + 2 > bytes.size) return null
        val tag = bytes[at].toInt() and 0xFF
        var length = bytes[at + 1].toInt() and 0xFF
        var start = at + 2
        if (length and 0x80 != 0) {
            val count = length and 0x7F
            if (count == 0 || count > 3 || start + count > bytes.size) return null
            length = 0
            repeat(count) { length = (length shl 8) or (bytes[start++].toInt() and 0xFF) }
        }
        return if (start + length <= bytes.size) Tlv(tag, start, start + length) else null
    }

    private fun children(bytes: ByteArray, parent: Tlv): List<Tlv> {
        val out = ArrayList<Tlv>()
        var at = parent.start
        while (at < parent.end) {
            val child = read(bytes, at) ?: return out
            out.add(child)
            at = child.end
        }
        return out
    }

    /** PKCS#8 { version, algorithm, OCTET STRING ECPrivateKey { version, key, [0] params, [1] BIT STRING point } }. */
    fun ecPublicPoint(pkcs8: ByteArray): ByteArray? {
        val outer = read(pkcs8, 0)?.takeIf { it.tag == 0x30 } ?: return null
        val wrapped = children(pkcs8, outer).getOrNull(2)?.takeIf { it.tag == 0x04 } ?: return null
        val ecKey = read(pkcs8, wrapped.start)?.takeIf { it.tag == 0x30 } ?: return null
        val tagged = children(pkcs8, ecKey).firstOrNull { it.tag == 0xA1 } ?: return null
        val bits = read(pkcs8, tagged.start)?.takeIf { it.tag == 0x03 && it.end - it.start >= 2 } ?: return null
        if (pkcs8[bits.start].toInt() != 0) return null // unused bits
        return pkcs8.copyOfRange(bits.start + 1, bits.end)
    }
}
