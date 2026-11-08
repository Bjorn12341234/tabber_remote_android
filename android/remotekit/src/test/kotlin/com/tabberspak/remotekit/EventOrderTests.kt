package com.tabberspak.remotekit

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * Spec 8.2: events up to the snapshot's seq are already in it and are ignored; only a real gap
 * asks for a new snapshot. Found on the emulator against Tabber Studio 0.3.27 (2026-11-08): once a
 * track was armed, meters came 20 times a second, and every event that arrived while a snapshot
 * was being read was taken for a gap, so the phone asked for snapshot after snapshot (and the six
 * reads after each) and lost the computer. The iPhone's RemoteSession has the same rule.
 */
class EventOrderTests {
    private val app = AppInfo(version = "1.0", build = "1")

    /** A host that answers hello, pair, subscribe and snapshot from a script, and sends what a test tells it to. */
    private class ScriptedHost(private val host: MemoryTransport) {
        var seq = 0
        var snapshots = 0
        private val snapshot = Vectors.json("exchanges/connect_pair_token.json")["host_state"]!!["snapshot"]!!

        suspend fun serve() {
            while (true) {
                val text = host.receive() ?: return
                val message = Json.parse(text)
                val id = message["id"] ?: continue
                val result: Json = when (message["method"]!!.string) {
                    "hello" -> jsonObject {
                        put("host", jsonObject { put("id", "h"); put("name", "Scripted"); put("app_version", "test") })
                        put("protocol_version", "1.9"); put("capabilities", Json.strings(listOf("transport/1", "meters/1")))
                        put("limits", jsonObject {
                            put("max_frame_bytes", 65536); put("requests_per_second", 20); put("burst", 40)
                            put("heartbeat_ms", 2000); put("heartbeat_misses", 3); put("connections_per_device", 2)
                        })
                        put("challenge", Base64Url.encode(ByteArray(32)))
                    }
                    "pair" -> jsonObject { put("device_id", "d"); put("host", jsonObject { put("id", "h"); put("name", "Scripted") }) }
                    "session.subscribe", "session.snapshot" -> {
                        snapshots += 1
                        Json.Obj(snapshot.obj!! + ("seq" to Json.Num(seq.toDouble())))
                    }
                    else -> Json.Obj(emptyMap())
                }
                host.sendNow(jsonObject { put("jsonrpc", "2.0"); put("id", id); put("result", result) }.encode())
            }
        }

        fun event(seq: Int) {
            host.sendNow(jsonObject {
                put("jsonrpc", "2.0"); put("method", "event")
                put("params", jsonObject {
                    put("topic", "meters"); put("seq", seq); put("t", 1.0)
                    put("data", jsonObject { put("levels", Json.of(listOf(jsonObject { put("track_id", "trk-vocals"); put("peak", Json.doubles(listOf(0.5, 0.5))) }))) })
                })
            }.encode())
        }
    }

    @Test fun eventsTheSnapshotAlreadyHoldsAreIgnored() = runBlocking {
        val (phone, hostEnd) = MemoryTransport.pair()
        val host = ScriptedHost(hostEnd).apply { seq = 5 }
        val session = RemoteSession(RemoteSession.Credentials.Demo, app) { phone }
        val serving = launch(Dispatchers.IO) { host.serve() }
        session.start()
        while (session.state.link !is LinkState.Connected) delay(10)
        assertEquals(5, session.state.seq)
        // Sent before the snapshot was answered: already in it.
        host.event(4); host.event(5)
        // Then the next ones, in order.
        host.event(6); host.event(7)
        delay(300)
        assertEquals(7, session.state.seq)
        assertEquals("no snapshot was read again", 0, session.resnapshots)
        assertEquals(1, host.snapshots)
        // A real gap still asks once.
        host.seq = 9
        host.event(9)
        delay(300)
        assertEquals(1, session.resnapshots)
        assertEquals(9, session.state.seq)
        session.stop(); session.close(); serving.cancel()
    }
}
