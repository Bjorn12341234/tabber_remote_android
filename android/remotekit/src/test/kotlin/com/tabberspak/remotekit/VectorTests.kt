package com.tabberspak.remotekit

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import org.junit.runner.RunWith
import org.junit.runners.Parameterized
import java.io.File

/** The protocol's vectors (spec 13), in Kotlin, as apple/RemoteKit/Tests/RemoteKitTests/VectorTests.swift. */
object Vectors {
    val root: File = File(
        System.getProperty("tabber.vectors") ?: error("run through Gradle: the tabber.vectors property names protocol/vectors"),
    )

    fun json(path: String): Json = Json.parse(root.resolve(path).readText())

    fun exchanges(): List<String> = root.resolve("exchanges").list()!!.filter { it.endsWith(".json") }.sorted()

    fun key(name: String): SoftwareSigner = SoftwareSigner.fromPem(root.resolve("keys/${name}_test_key.pem").readText())
}

fun hex(text: String): ByteArray = ByteArray(text.length / 2) { text.substring(it * 2, it * 2 + 2).toInt(16).toByte() }

class CryptoVectorTests {
    private val identity = Vectors.json("crypto/identity.json")

    @Test fun pinsAndDeviceIds() {
        val host = Vectors.key("host").publicKeyDer
        assertEquals(identity["host"]!!["spki_der_b64url"]!!.string, Base64Url.encode(host))
        assertEquals(identity["host"]!!["pin"]!!.string, RemoteCrypto.pin(host))
        val device = Vectors.key("device").publicKeyDer
        assertEquals(identity["device"]!!["key"]!!.string, Base64Url.encode(device))
        assertEquals(identity["device"]!!["device_id"]!!.string, RemoteCrypto.deviceId(device))
        assertEquals(identity["device"]!!["device_id"]!!.string, Vectors.key("device").deviceId)
        val other = Vectors.key("other_device").publicKeyDer
        assertEquals(identity["other_device"]!!["device_id"]!!.string, RemoteCrypto.deviceId(other))
    }

    @Test fun theSpkiPrefixMatchesTheJdk() {
        val spki = Vectors.key("host").publicKeyDer
        assertTrue(RemoteCrypto.spkiDer(spki.copyOfRange(spki.size - 65, spki.size))!!.contentEquals(spki))
        assertEquals(null, RemoteCrypto.spkiDer(ByteArray(64)))
    }

    @Test fun signedBytesAndSignatures() {
        val vectors = Vectors.json("crypto/signatures.json")
        val pinHash = Base64Url.decode(vectors["host_pin"]!!.string!!)!!
        for (item in vectors["cases"]!!.array!!) {
            val name = item["name"]!!.string!!
            val message = hex(item["signed_bytes_hex"]!!.string!!)
            val key = Base64Url.decode(item["device_key"]!!.string!!)!!
            val signature = Base64Url.decode(item["signature"]!!.string!!)!!
            val verifies = item["verifies"]!!.bool!!
            assertEquals(name, verifies, RemoteCrypto.verify(key, signature, message))
            if (verifies) {
                val context = item["context"]!!.string!!.toByteArray() + byteArrayOf(0)
                val token = item["token"]?.string?.let { Base64Url.decode(it)!! } ?: ByteArray(0)
                val challenge = Base64Url.decode(item["challenge"]!!.string!!)!!
                assertTrue(name, RemoteCrypto.signedBytes(context, pinHash, challenge, token).contentEquals(message))
            }
        }
    }

    @Test fun aSignatureMadeHereVerifiesThere() {
        for (signer in listOf(Vectors.key("device"), SoftwareSigner.generate())) {
            val message = "tabber".toByteArray()
            assertTrue(RemoteCrypto.verify(signer.publicKeyDer, signer.sign(message), message))
            assertFalse(RemoteCrypto.verify(signer.publicKeyDer, signer.sign(message), "other".toByteArray()))
        }
    }

    @Test fun aKeptSoftwareKeyIsTheSameKey() {
        val signer = SoftwareSigner.generate()
        val kept = SoftwareSigner.fromParts(signer.pkcs8, signer.publicKeyDer)
        assertEquals(signer.deviceId, kept.deviceId)
        val message = "kept".toByteArray()
        assertTrue(RemoteCrypto.verify(signer.publicKeyDer, kept.sign(message), message))
    }

    @Test fun pairingCodes() {
        for (item in Vectors.json("crypto/pairing_code.json")["cases"]!!.array!!) {
            val code = RemoteCrypto.pairingCode(
                Base64Url.decode(item["host_pin"]!!.string!!)!!,
                Base64Url.decode(item["device_id"]!!.string!!)!!,
                Base64Url.decode(item["challenge"]!!.string!!)!!,
            )
            assertEquals(item["code"]!!.string, code)
        }
    }

    @Test fun theQrLink() {
        val vector = Vectors.json("crypto/qr_link.json")
        val link = PairingLink.parse(vector["link"]!!.string!!)
        assertNotNull(link)
        link!!
        assertEquals(identity["host"]!!["id"]!!.string, link.hostId)
        assertEquals(identity["host"]!!["pin"]!!.string, link.pin)
        assertEquals(identity["token"]!!.string, link.token)
        assertEquals("Studio Mac", link.name)
        assertEquals(listOf("1"), link.versions)
        assertEquals(vector["routes"]!!.array!!.map { it.string }, link.routes.map(Route::toString))
        assertEquals(Route("fd12:3456:789a::20", 9474), link.routes.last())
    }

    @Test fun aLinkThatIsNotOursIsRefused() {
        val good = Vectors.json("crypto/qr_link.json")["link"]!!.string!!
        assertEquals(null, PairingLink.parse(good.replace("tabber-remote://", "https://")))
        assertEquals(null, PairingLink.parse(good.replace("://pair?", "://other?")))
        assertEquals(null, PairingLink.parse(good.replace(Regex("tok=[^&]*"), "tok=short")))
        assertEquals(null, PairingLink.parse(good.replace(Regex("hosts=[^&]*"), "hosts=")))
    }

    @Test fun base64UrlIsStrict() {
        assertEquals(null, Base64Url.decode("abc="))
        assertEquals(null, Base64Url.decode("ab+c"))
        assertEquals(null, Base64Url.decode("a"))
        assertTrue(Base64Url.decode("AQID")!!.contentEquals(byteArrayOf(1, 2, 3)))
    }
}

/** Every message the app reads decodes into its model and encodes back to the same JSON. */
@RunWith(Parameterized::class)
class ExchangeVectorTests(private val file: String) {
    companion object {
        @JvmStatic
        @Parameterized.Parameters(name = "{0}")
        fun files(): List<String> = Vectors.exchanges()
    }

    @Test fun everyHostMessageDecodes() {
        val vector = Vectors.json("exchanges/$file")
        val methods = HashMap<Int, String>()
        var checked = 0
        for (step in vector["steps"]!!.array!!) {
            val message = step["message"] ?: continue
            if (step["from"]?.string == "remote") {
                message["id"]?.int?.let { id -> methods[id] = message["method"]!!.string!! }
                continue
            }
            val result = message["result"]
            val method = message["id"]?.int?.let(methods::get)
            when {
                result != null && method != null -> check(method, result)
                message["error"] != null -> {
                    val failure = RemoteError.from(message["error"]!!)
                    assertNotNull("$file: an error without code and message", failure)
                    assertTrue("$file: an error without a reason", failure!!.reason.isNotEmpty())
                }
                message["method"]?.string == "event" -> {
                    val params = message["params"]!!
                    checkTopic(params["topic"]!!.string!!, params["data"]!!)
                }
                message["method"]?.string == "heartbeat" -> roundTrip(message["params"]!!) { Heartbeat.from(it).toJson() }
                else -> continue
            }
            checked++
        }
        assertTrue("$file: no host message was checked", checked > 0 || methods.isNotEmpty())
    }

    private fun roundTrip(value: Json, decodeEncode: (JsonReader) -> Json) {
        assertEquals("$file: does not round-trip", value, decodeEncode(JsonReader(value)))
    }

    private fun roundTripList(value: Json, decodeEncode: (JsonReader) -> Json) {
        val items = value.array ?: fail("$file: expected a list") as Nothing
        assertEquals("$file: a list does not round-trip", value, Json.Arr(items.map { decodeEncode(JsonReader(it)) }))
    }

    private fun check(method: String, result: Json) {
        when (method) {
            "hello" -> roundTrip(result) { HelloResult.from(it).toJson() }
            "pair" -> roundTrip(result) { PairResult.from(it).toJson() }
            "auth" -> roundTrip(result) { AuthResult.from(it).toJson() }
            "session.subscribe", "session.snapshot" -> roundTrip(result) { Snapshot.from(it).toJson() }
            else -> for ((key, value) in result.obj ?: emptyMap()) {
                when (key) {
                    "transport" -> roundTrip(value) { TransportState.from(it).toJson() }
                    "record" -> roundTrip(value) { RecordState.from(it).toJson() }
                    "tracks" -> roundTripList(value) { Track.from(it).toJson() }
                    "track" -> roundTrip(value) { Track.from(it).toJson() }
                    "markers" -> roundTripList(value) { Marker.from(it).toJson() }
                    "marker" -> roundTrip(value) { Marker.from(it).toJson() }
                    "takes" -> roundTripList(value) { Take.from(it).toJson() }
                    "take" -> if (value != Json.Null) roundTrip(value) { Take.from(it).toJson() }
                    "undo" -> roundTrip(value) { UndoState.from(it).toJson() }
                    "project" -> roundTrip(value) { ProjectState.from(it).toJson() }
                    "topics" -> assertTrue("$file: topics", value.array!!.all { it.string != null })
                    "mixer" -> roundTrip(value) { MixerState.from(it).toJson() }
                    "strip" -> roundTrip(value) { Strip.from(it).toJson() }
                    "tab" -> if (value != Json.Null) roundTrip(value) { TabState.from(it).toJson() }
                    "routing" -> roundTrip(value) { RoutingState.from(it).toJson() }
                    "chat" -> roundTrip(value) { ChatState.from(it).toJson() }
                    "view" -> roundTrip(value) { ViewState.from(it).toJson() }
                    "trainer" -> roundTrip(value) { TrainerState.from(it).toJson() }
                    else -> fail("$file: unknown result field $key of $method")
                }
            }
        }
    }

    private fun checkTopic(topic: String, data: Json) {
        when (topic) {
            "transport" -> roundTrip(data) { TransportState.from(it).toJson() }
            "record" -> roundTrip(data) { RecordState.from(it).toJson() }
            "tracks" -> roundTripList(data["tracks"]!!) { Track.from(it).toJson() }
            "markers" -> roundTripList(data["markers"]!!) { Marker.from(it).toJson() }
            "takes" -> roundTripList(data["takes"]!!) { Take.from(it).toJson() }
            "undo" -> roundTrip(data) { UndoState.from(it).toJson() }
            "project" -> roundTrip(data) { ProjectState.from(it).toJson() }
            "position" -> roundTrip(data["position"]!!) { Position.from(it).toJson() }
            "meters" -> roundTripList(data["levels"]!!) { MeterLevel.from(it).toJson() }
            "mixer" -> roundTrip(data) { MixerState.from(it).toJson() }
            "mixer_meters" -> roundTripList(data["levels"]!!) { StripLevel.from(it).toJson() }
            "tab" -> if (data["tab"] != Json.Null) roundTrip(data["tab"]!!) { TabState.from(it).toJson() }
            "routing" -> roundTrip(data) { RoutingState.from(it).toJson() }
            "chat" -> roundTrip(data) { ChatState.from(it).toJson() }
            "view" -> roundTrip(data) { ViewState.from(it).toJson() }
            "trainer" -> roundTrip(data) { TrainerState.from(it).toJson() }
            else -> fail("$file: unknown topic $topic")
        }
    }
}

class JsonTests {
    @Test fun numbersAreValuesNotSpellings() {
        assertEquals(Json.parse("{\"a\":8120}"), Json.parse("{\"a\": 8120.0}"))
        assertEquals("{\"a\":8120,\"b\":0.5,\"c\":null}", Json.parse("{\"c\":null,\"b\":0.5,\"a\":8120.0}").encode())
    }

    @Test fun stringsSurviveEscapes() {
        val text = "Say \"hi\"\n\ttab \u00e5\u00e4\u00f6 \uD83C\uDFB8 \\ /"
        assertEquals(text, Json.parse(Json.Str(text).encode()).string)
        assertEquals("\u00e5", Json.parse("\"\\u00e5\"").string)
    }

    @Test fun strictParsing() {
        for (bad in listOf("", "{", "[1,]", "{\"a\":1,}", "01", "1 2", "'a'", "\"\u0001\"", "tru", "nul")) {
            try {
                Json.parse(bad)
                fail("parsed: $bad")
            } catch (_: JsonShapeException) {
            }
        }
    }

    @Test fun readersNameThePathOfAMiss() {
        try {
            Track.from(JsonReader(Json.parse("{\"id\":\"t\",\"name\":\"x\",\"kind\":\"audio\"}")))
            fail("decoded a track with no armed")
        } catch (e: JsonShapeException) {
            assertEquals("$.armed: missing", e.message)
        }
    }
}
