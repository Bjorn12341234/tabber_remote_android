package com.tabberspak.app

import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.security.keystore.StrongBoxUnavailableException
import com.tabberspak.remotekit.DeviceSigner
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.PrivateKey
import java.security.Signature
import java.security.spec.ECGenParameterSpec

/**
 * The phone's own key (spec 4.1) in the Android Keystore, as the iPhone keeps its key in the
 * Secure Enclave: ECDSA P-256, made on this phone, and it never leaves it. StrongBox (a separate
 * secure chip) when the phone has one, the Keystore's trusted environment otherwise; the
 * emulator has a software Keystore, which is enough for building and testing.
 */
class KeystoreSigner private constructor(private val key: PrivateKey, override val publicKeyDer: ByteArray) : DeviceSigner {
    override fun sign(message: ByteArray): ByteArray = Signature.getInstance("SHA256withECDSA").run {
        initSign(key)
        update(message)
        sign()
    }

    companion object {
        private const val ALIAS = "tabber-spak-device-key"
        private const val STORE = "AndroidKeyStore"

        fun loadOrCreate(): KeystoreSigner {
            val store = KeyStore.getInstance(STORE).apply { load(null) }
            if (!store.containsAlias(ALIAS)) create()
            val entry = store.getEntry(ALIAS, null) as KeyStore.PrivateKeyEntry
            return KeystoreSigner(entry.privateKey, entry.certificate.publicKey.encoded)
        }

        /** Forget the key: every computer must pair this phone again. */
        fun forget() {
            KeyStore.getInstance(STORE).apply { load(null) }.deleteEntry(ALIAS)
        }

        private fun create() {
            fun spec(strongBox: Boolean) = KeyGenParameterSpec.Builder(ALIAS, KeyProperties.PURPOSE_SIGN)
                .setAlgorithmParameterSpec(ECGenParameterSpec("secp256r1"))
                .setDigests(KeyProperties.DIGEST_SHA256)
                .setIsStrongBoxBacked(strongBox)
                .build()
            val generator = KeyPairGenerator.getInstance(KeyProperties.KEY_ALGORITHM_EC, STORE)
            try {
                generator.initialize(spec(strongBox = true))
                generator.generateKeyPair()
            } catch (_: StrongBoxUnavailableException) {
                generator.initialize(spec(strongBox = false))
                generator.generateKeyPair()
            }
        }
    }
}
