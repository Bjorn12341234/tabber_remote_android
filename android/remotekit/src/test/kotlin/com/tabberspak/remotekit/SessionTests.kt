package com.tabberspak.remotekit

import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.time.Duration.Companion.milliseconds
import kotlin.time.Duration.Companion.seconds

private val app = AppInfo(version = "1.0", build = "1")

private suspend fun eventually(session: RemoteSession, within: Double = 3.0, check: (SessionState) -> Boolean): SessionState {
    val deadline = System.nanoTime() + (within * 1e9).toLong()
    while (System.nanoTime() < deadline) {
        val state = session.state
        if (check(state)) return state
        delay(10)
    }
    fail("the state never got there: ${session.state.link}, trouble ${session.state.trouble}")
    error("unreachable")
}

private fun isConnected(state: SessionState) = state.link is LinkState.Connected && state.transport != null

/** TR6: finding the computer again, waking up, and saying what is wrong (ReconnectTests.swift). */
class ReconnectTests {
    @Test fun theRouteBookTriesEachAddressThenBonjour() = runBlocking {
        val local = Route("Studio.local", 9474)
        val wifi = Route("192.168.8.20", 9474)
        val moved = Route("192.168.8.31", 50211)
        val book = RouteBook(listOf(local, wifi), "h1") { id -> if (id == "h1") moved else null }
        assertEquals(local, book.route(0))
        assertEquals(wifi, book.route(1))
        assertEquals(moved, book.route(2)) // after a round: where Bonjour says it is now
        assertEquals(local, book.route(3))
        book.route(2)
        // The address that worked goes first; the others follow it to the new port.
        assertEquals(listOf(moved, Route("Studio.local", 50211), Route("192.168.8.20", 50211)), book.connected())
        assertNull(book.connected()) // nothing new to remember
    }

    @Test fun withoutBonjourTheBookFallsBackToTheFirstAddress() = runBlocking {
        val local = Route("Studio.local", 9474)
        val book = RouteBook(listOf(local), "h1") { null }
        assertEquals(local, book.route(1))
        assertNull(book.connected())
    }

    @Test fun versionsSayWhichSideToUpdate() {
        assertEquals(Trouble.UpdateSpak(listOf("2.0")), Trouble.versions(listOf("2.0")))
        assertEquals(Trouble.UpdateStudio(listOf("0.9")), Trouble.versions(listOf("0.9")))
    }

    @Test fun aComputerOfAnotherVersionSaysWhatToUpdate() = runBlocking {
        for ((speaks, trouble) in listOf(listOf("2.0") to Trouble.UpdateSpak(listOf("2.0")), listOf("0.9") to Trouble.UpdateStudio(listOf("0.9")))) {
            val host = DemoHost(speaks = speaks)
            val session = RemoteSession(RemoteSession.Credentials.Demo, app) { host.connect() }
            session.start()
            val state = eventually(session) { it.link is LinkState.Failed }
            assertEquals(LinkState.Failed("unsupported_version"), state.link)
            assertEquals(trouble, state.trouble)
            session.stop()
            session.close()
        }
    }

    @Test fun anUnreachableComputerIsNamedAfterThePatienceRunsOut() = runBlocking {
        val session = RemoteSession(RemoteSession.Credentials.Demo, app) { throw TransportFailure.Unreachable("nobody listens") }
        session.start()
        delay(1.seconds)
        assertNull("a short drop is not trouble yet", session.state.trouble)
        val state = eventually(session, within = 6.0) { it.trouble == Trouble.Unreachable }
        assertEquals(LinkState.Reconnecting, state.link)
        session.stop()
        session.close()
    }

    @Test fun aDeniedLocalNetworkIsNamedAtOnce() = runBlocking {
        val session = RemoteSession(RemoteSession.Credentials.Demo, app) { throw TransportFailure.LocalNetworkDenied }
        session.start()
        val state = eventually(session, within = 1.0) { it.trouble == Trouble.LocalNetworkDenied }
        assertEquals("it keeps trying: it may be allowed in Settings", LinkState.Reconnecting, state.link)
        session.stop()
        session.close()
    }

    @Test fun wakeTriesAtOnceInsteadOfWaitingOutTheBackoff() = runBlocking {
        val host = DemoHost()
        val open = AtomicBoolean(false)
        val session = RemoteSession(RemoteSession.Credentials.Demo, app) {
            if (!open.get()) throw TransportFailure.Unreachable("away")
            host.connect()
        }
        session.start()
        delay(2200.milliseconds) // four failures: the backoff is now 2 s
        open.set(true)
        delay(50)
        val woken = System.nanoTime()
        session.wake()
        eventually(session, within = 1.5, check = ::isConnected)
        assertTrue("connected ${(System.nanoTime() - woken) / 1_000_000} ms after waking", System.nanoTime() - woken < 500_000_000)
        assertNull(session.state.trouble)
        session.stop()
        session.close()
    }

    @Test fun wakeRemakesAConnectionThatWentQuiet() = runBlocking {
        val host = DemoHost()
        val session = RemoteSession(RemoteSession.Credentials.Demo, app) { host.connect() }
        session.start()
        eventually(session, check = ::isConnected)
        host.goSilent() // the phone was away; its socket is dead
        delay(2800.milliseconds)
        val woken = System.nanoTime()
        session.wake()
        delay(20)
        eventually(session, within = 2.0, check = ::isConnected)
        assertTrue("TR6's target: back within a second", System.nanoTime() - woken < 1_000_000_000)
        assertEquals(2, host.connectionsMade())
        session.stop()
        session.close()
    }
}

/** Every address at once: away from the Wi-Fi the phone must not wait out the dead ones (RaceTests.swift). */
class RaceTests {
    private val local = Route("192.168.0.69", 9474)
    private val tailscale = Route("100.114.215.101", 9474)

    /** An address that fails at once, as the phone reports it. */
    private class Failing(private val failure: TransportFailure) : RemoteTransport {
        override suspend fun send(text: String) = throw failure
        override suspend fun receive(): String? = throw failure
        override fun close() {}
        override val closeCode: Int? = null
    }

    @Test fun theFirstAddressToAnswerIsTheConnection() = runBlocking {
        val live = DemoHost().connect()
        val (dead, _) = MemoryTransport.pair() // nobody answers there
        var winner: Route? = null
        val race = RacingTransport(listOf(local, tailscale), { if (it == local) dead else live }, { winner = it })
        val client = RemoteClient(race).apply { start() }
        val hello = client.sayHello(app, timeout = 2.seconds)
        assertEquals("the demo answers", RemoteClient.PROTOCOL_VERSIONS.first(), hello.protocolVersion)
        assertEquals("the address that answered is remembered", tailscale, winner)
        client.close()
    }

    @Test fun aWrongKeyAtOneAddressDoesNotStopAnother() = runBlocking {
        val live = DemoHost().connect()
        val race = RacingTransport(listOf(local, tailscale), { if (it == local) Failing(TransportFailure.WrongKey) else live })
        val client = RemoteClient(race).apply { start() }
        val hello = client.sayHello(app, timeout = 2.seconds)
        assertEquals(RemoteClient.PROTOCOL_VERSIONS.first(), hello.protocolVersion)
        client.close()
    }

    @Test fun whenEveryAddressFailsTheMostTellingFailureIsReported() = runBlocking {
        val race = RacingTransport(listOf(local, tailscale), {
            if (it == local) Failing(TransportFailure.WrongKey) else Failing(TransportFailure.LocalNetworkDenied)
        })
        race.send("{}")
        assertEquals(TransportFailure.LocalNetworkDenied, runCatching { race.receive() }.exceptionOrNull())
        assertEquals(
            "a wrong key is reported only when nothing else failed",
            TransportFailure.Unreachable("x"), RacingTransport.telling(listOf(TransportFailure.WrongKey, TransportFailure.Unreachable("x"))),
        )
        assertTrue(runCatching { RacingTransport(emptyList(), { Failing(TransportFailure.WrongKey) }).receive() }.exceptionOrNull() is TransportFailure)
    }

    @Test fun aSessionConnectsThroughADeadAddress() = runBlocking {
        val host = DemoHost()
        val session = RemoteSession(RemoteSession.Credentials.Demo, app) {
            val (dead, _) = MemoryTransport.pair()
            val live = host.connect()
            RacingTransport(listOf(local, tailscale), { if (it == local) dead else live })
        }
        session.start()
        val started = System.nanoTime()
        eventually(session, within = 2.0) { it.link is LinkState.Connected }
        // Waiting out the dead address would take the hello's whole timeout.
        assertTrue("without waiting out the dead address", (System.nanoTime() - started) < RemoteSession.CONNECT_TIMEOUT.inWholeNanoseconds)
        session.stop()
        session.close()
    }
}

/** TR7's gate measured on the phone: how long the computer takes to answer a tap (ResponseTimesTests.swift). */
class ResponseTimesTests {
    @Test fun nearestRankPercentiles() {
        var times = ResponseTimes()
        assertNull(times.median)
        assertNull(times.p95)
        for (ms in 1..20) times = times.adding(ms.milliseconds)
        assertEquals(10.milliseconds, times.median)
        assertEquals(19.milliseconds, times.p95)
        times = times.adding(400.milliseconds)
        assertEquals("one slow answer in 21 is not the 95th percentile", 20.milliseconds, times.p95)
        val one = ResponseTimes().adding(7.milliseconds)
        assertEquals(7.milliseconds, one.median)
        assertEquals(7.milliseconds, one.p95)
    }

    @Test fun onlyTheNewestAreKept() {
        var times = ResponseTimes()
        for (ms in 1..(ResponseTimes.KEPT + 10)) times = times.adding(ms.milliseconds)
        assertEquals(ResponseTimes.KEPT, times.count)
        assertEquals(11.milliseconds, times.samples.first())
    }

    @Test fun changesAreTimedButNotReadsOrTheChat() = runBlocking {
        val host = DemoHost()
        val session = RemoteSession(RemoteSession.Credentials.Demo, app) { host.connect() }
        session.start()
        eventually(session, check = ::isConnected)
        assertEquals("connecting is not a tap", 0, session.responseTimes.count)
        session.perform("transport.set_click", jsonObject { put("enabled", true) })
        session.perform("transport.play")
        session.perform("mixer.state")
        session.perform("chat.send", jsonObject { put("text", "mute the drums") })
        val times = session.responseTimes
        assertEquals("the click and play; not the read or the chat", 2, times.count)
        assertTrue(times.samples.all { it > 0.milliseconds && it < 2.seconds })
        session.resetResponseTimes()
        assertEquals(0, session.responseTimes.count)
        session.stop()
        session.close()
    }
}
