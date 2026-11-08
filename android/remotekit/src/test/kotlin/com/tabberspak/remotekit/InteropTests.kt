package com.tabberspak.remotekit

import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Before
import org.junit.Test
import java.util.UUID
import kotlin.time.Duration.Companion.seconds

/**
 * RemoteKit's OkHttp client against Tabber Studio's real host, over TLS 1.3 with the pin, as
 * apple/RemoteKit's InteropTests. Runs when `REMOTE_INTEROP` holds the JSON line
 * `tools/interop_host.py` prints (android/scripts/interop.sh does both).
 */
class InteropTests {
    private lateinit var route: Route
    private lateinit var pin: String
    private lateinit var token: String
    private lateinit var hostId: String

    @Before fun host() {
        val line = System.getenv("REMOTE_INTEROP")
        assumeTrue("no interop host (android/scripts/interop.sh)", line != null)
        val json = Json.parse(line!!)
        route = Route("127.0.0.1", json["port"]!!.int!!)
        pin = json["pin"]!!.string!!
        token = json["token"]!!.string!!
        hostId = json["host_id"]!!.string!!
    }

    private val app = AppInfo(version = "1.0", build = "1")

    @Test fun pairThenAuthenticateOverPinnedTls() = runBlocking {
        val signer = SoftwareSigner.generate()
        val first = RemoteClient(OkHttpTransport(route, pin)).apply { start() }
        val hello = first.sayHello(app)
        assertEquals(hostId, hello.host.id)
        assertEquals(RemoteClient.PROTOCOL_VERSIONS.first(), hello.protocolVersion) // the version this client offers
        assertTrue(hello.capabilities.contains("takes.discard/1"))
        val paired = first.pair(token, pin, signer, name = "Interop Android", model = "test")
        assertEquals(signer.deviceId, paired.deviceId)
        try {
            first.call("transport.play", jsonObject { put("key", UUID.randomUUID().toString()) })
        } catch (failure: RemoteError) {
            assertEquals("host_error", failure.reason) // the interop host has no song window
        }
        try {
            first.call("system.quit")
            throw AssertionError("a raw Control API method got through")
        } catch (failure: RemoteError) {
            assertEquals("method_not_found", failure.reason)
        }
        first.close()

        val second = RemoteClient(OkHttpTransport(route, pin)).apply { start() }
        second.sayHello(app)
        val auth = second.authenticate(pin, signer)
        assertEquals(signer.deviceId, auth.device.id)
        assertEquals("Interop Android", auth.device.name)
        second.close()
    }

    @Test fun aWrongPinNeverTalksToTheHost() = runBlocking {
        val wrong = Base64Url.encode(ByteArray(32) { 7 })
        val client = RemoteClient(OkHttpTransport(route, wrong)).apply { start() }
        val outcome = runCatching { client.sayHello(app, timeout = 5.seconds) }
        assertTrue("hello got through with a wrong pin", outcome.isFailure)
        assertEquals(TransportFailure.WrongKey, outcome.exceptionOrNull())
        client.close()
    }

    @Test fun noPinYetSeesTheHostsKey() = runBlocking {
        val transport = OkHttpTransport(route, pin = null)
        val client = RemoteClient(transport).apply { start() }
        client.sayHello(app)
        assertEquals(pin, transport.observedPin)
        client.close()
    }
}
