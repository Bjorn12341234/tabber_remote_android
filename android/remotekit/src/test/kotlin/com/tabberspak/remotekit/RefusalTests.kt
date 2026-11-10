package com.tabberspak.remotekit

import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * What the phone says when Tabber Studio refuses (spec 10), as
 * apple/RemoteKit/Tests/RemoteKitTests/RefusalTests.swift. A `host_error` with a `detail` is
 * Studio's own reason, shown in place of the general "Tabber Studio could not do that."
 */
class RefusalTests {
    private val general = "Tabber Studio could not do that."

    private fun hostError(vararg data: Pair<String, Json>): RemoteError =
        RemoteError(1099, general, "host_error", Json.Obj(mapOf(*data)))

    private fun detail(text: String) = "detail" to Json.Str(text)

    @Test fun aHostErrorSaysStudiosReason() {
        assertEquals("The bus was not added.", hostError(detail("The bus was not added.")).sentence)
        assertEquals(
            "That pitch already sounds in this beat, on another string.",
            hostError(detail("That pitch already sounds in this beat, on another string.")).sentence,
        )
    }

    @Test fun withoutAReasonItIsTheGeneralSentence() {
        assertEquals(general, hostError().sentence)
        assertEquals("spaces are no reason", general, hostError(detail(" \n ")).sentence)
        assertEquals(general, hostError(detail("")).sentence)
        assertEquals(general, hostError("detail" to Json.Null).sentence)
        assertEquals("nor is a number", general, hostError("detail" to Json.Num(7.0)).sentence)
    }

    @Test fun aReasonEndsAsASentence() {
        assertEquals(
            "Studio's words, with the full stop they leave off",
            "Insert this instrument on a MIDI/score track.", hostError(detail("Insert this instrument on a MIDI/score track")).sentence,
        )
        assertEquals("Old Delay failed to load.", hostError(detail("  Old Delay failed to load. ")).sentence)
        assertEquals("Is Old Delay installed?", hostError(detail("Is Old Delay installed?")).sentence)
        assertEquals("Old Delay says “No licence.”", hostError(detail("Old Delay says “No licence.”")).sentence)
        assertEquals(
            "Old Delay did not open (it is for an Intel Mac).",
            hostError(detail("Old Delay did not open (it is for an Intel Mac)")).sentence,
        )
    }

    @Test fun aRoutingLoopStillNamesTheLoop() {
        val message = "That route would make a feedback loop."
        val loop = RemoteError(
            1034, message, "routing_loop",
            Json.Obj(mapOf("reason" to Json.Str("routing_loop"), "path" to Json.strings(listOf("Reverb", "Delay", "Reverb")))),
        )
        assertEquals("That route would make a feedback loop. Reverb → Delay → Reverb.", loop.sentence)
        assertEquals(message, RemoteError(1034, message, "routing_loop").sentence)
    }

    @Test fun otherRefusalsSayTheirMessage() {
        val stale = RemoteError(
            1026, "This changed on the computer. The phone now shows the new state.", "stale_target",
            Json.Obj(mapOf("reason" to Json.Str("stale_target"), "detail" to Json.Str("Not a host error."))),
        )
        assertEquals("only a host_error carries a reason in words", stale.message, stale.sentence)
        val busy = RemoteError(1012, "Tabber Studio is busy. Try again in a moment.", "busy")
        assertEquals(busy.message, busy.sentence)
    }

    /** Every host_error in the protocol's vectors, read off the wire as the app reads it. */
    @Test fun theVectorsRefusalsSayWhy() {
        var seen = 0
        for (file in Vectors.exchanges()) {
            for (step in Vectors.json("exchanges/$file")["steps"]?.array.orEmpty()) {
                val error = step["message"]?.get("error") ?: continue
                val failure = RemoteError.from(error) ?: continue
                if (failure.reason != "host_error") continue
                assertEquals(file, general, failure.message)
                assertEquals(file, error["data"]?.get("detail")?.string ?: general, failure.sentence)
                seen += 1
            }
        }
        assertTrue("the plug-in, MIDI tab, take and drum refusals: $seen", seen >= 3)
    }

    /** DemoHost's own host_error refusals, through RemoteSession, as the app gets them. */
    @Test fun theDemosRefusalsSayWhy() = runBlocking<Unit> {
        val demo = DemoHostTests()
        val session = demo.session(DemoHost())
        demo.connected(session)
        val gone = runCatching {
            session.perform("plugins.insert", jsonObject { put("strip_id", "demo-vocals"); put("plugin_id", "pl-gone") })
        }.exceptionOrNull() as? RemoteError ?: throw AssertionError("a plug-in the computer does not have went in")
        assertTrue(gone.reason == "host_error" && gone.message == general)
        assertEquals("That plug-in is not on the computer any more. Open the list again.", gone.sentence)
        val instrument = runCatching {
            session.perform("plugins.insert", jsonObject { put("strip_id", "demo-vocals"); put("plugin_id", "pl-tabber-synth") })
        }.exceptionOrNull() as? RemoteError ?: throw AssertionError("an instrument went in on an audio track")
        assertTrue(instrument.reason == "host_error" && instrument.message == general)
        assertEquals("Insert this instrument on a MIDI/score track.", instrument.sentence)
        session.stop()
    }
}
