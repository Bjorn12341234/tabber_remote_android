package com.tabberspak.remotekit

import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.UUID

/** The app's whole take loop against DemoHost, through RemoteSession, as apple/RemoteKit/Tests/RemoteKitTests/DemoHostTests.swift. */
class DemoHostTests {
    private val app = AppInfo(version = "1.0", build = "1")

    private fun session(host: DemoHost) =
        RemoteSession(credentials = RemoteSession.Credentials.Demo, app = app) { host.connect() }

    private suspend fun connected(session: RemoteSession): SessionState {
        session.start()
        repeat(200) {
            val state = session.state
            if (state.link is LinkState.Connected && state.transport != null) return state
            delay(10)
        }
        throw AssertionError("never connected")
    }

    private suspend fun eventually(session: RemoteSession, check: (SessionState) -> Boolean): SessionState {
        repeat(300) {
            val state = session.state
            if (check(state)) return state
            delay(10)
        }
        throw AssertionError("the state never got there")
    }

    /** What Swift's `#require` does: the value, or the test stops. */
    private fun <T : Any> required(value: T?, what: String = "a required value is missing"): T = value ?: throw AssertionError(what)

    /** What Swift's `#expect(throws: RemoteError.self)` does: the call must be refused. */
    private suspend fun refused(why: String = "the computer did it", call: suspend () -> Unit): RemoteError {
        try {
            call()
        } catch (failure: RemoteError) {
            return failure
        }
        throw AssertionError(why)
    }

    private fun armedIds(vararg ids: String) = jsonObject { put("armed_track_ids", Json.strings(ids.toList())) }

    @Test fun theSnapshotArrives() = runBlocking<Unit> {
        val state = connected(session(DemoHost()))
        assertEquals(listOf("Guitar", "Bass", "Drums", "Lead guitar", "Vocals"), state.tracks.map { it.name })
        assertTrue(state.capabilities.containsAll(listOf("mixer/1", "tab/1")))
        assertEquals(listOf("Guitar", "Bass", "Drums", "Lead guitar", "Vocals", "Reverb", "Master"), state.mixer?.strips?.map { it.name })
        assertTrue(state.tab?.trackId == "demo-guitar" && state.tab?.strings == 6)
        assertEquals(listOf("Intro", "Verse", "Chorus", "Solo"), state.markers.map { it.name })
        assertTrue(state.capabilities.contains("takes.go_again/1"))
        assertEquals(PlayState.STOPPED, state.transport?.state)
    }

    @Test fun S1FiveTakesOfTheChorus() = runBlocking<Unit> {
        val host = DemoHost()
        val session = session(host)
        val start = connected(session)
        val vocals = start.tracks[0].id
        session.perform("tracks.arm", jsonObject { put("track_id", vocals); put("armed", true) })
        session.perform("markers.go", jsonObject { put("marker_id", "demo-chorus") })
        val counted = session.perform("transport.set_count_in", jsonObject { put("bars", 0) })
        assertEquals(0, counted["transport"]?.get("count_in_bars")?.int)
        val keptTakes = mutableListOf<String>()
        for (number in 1..5) {
            session.perform("transport.record", armedIds(vocals))
            val recording = eventually(session) { it.record.recording }
            assertEquals(25, recording.record.started?.position?.bar)
            delay(30)
            val stopped = session.perform("transport.stop")
            val take = required(stopped["take"]?.let { runCatching { Take.from(JsonReader(it)) }.getOrNull() })
            assertTrue(take.start.bar == 25 && take.trackId == vocals)
            if (number % 2 == 0) {
                val discarded = session.perform("takes.discard", jsonObject { put("take_id", take.id) })
                assertEquals(false, discarded["takes"]?.array?.any { it["id"]?.string == take.id })
            } else {
                keptTakes.add(take.id)
            }
            session.perform("markers.go", jsonObject { put("marker_id", "demo-chorus") })
        }
        val after = eventually(session) { it.takes.size == 3 }
        assertEquals(keptTakes.toSet(), after.takes.map { it.id }.toSet())
        val undoStep = required(after.undo.undo)
        assertEquals("Record take", undoStep.label)
    }

    @Test fun discardThenUndoBringsTheTakeBack() = runBlocking<Unit> {
        val host = DemoHost()
        val session = session(host)
        val start = connected(session)
        session.perform("tracks.arm", jsonObject { put("track_id", start.tracks[0].id); put("armed", true) })
        session.perform("transport.record", armedIds(start.tracks[0].id))
        val stopped = session.perform("transport.stop")
        val takeId = required(stopped["take"]?.get("id")?.string)
        val discarded = session.perform("takes.discard", jsonObject { put("take_id", takeId) })
        val step = required(discarded["undo"]?.get("undo")?.get("id")?.string)
        session.perform("edit.undo", jsonObject { put("expect", step) })
        val back = eventually(session) { state -> state.takes.any { it.id == takeId } }
        assertEquals("Discard take", back.undo.redo?.label)
        refused { session.perform("edit.undo", jsonObject { put("expect", "not-this-one") }) }
        val again = session.perform("takes.go_again", jsonObject { put("take_id", takeId) })
        assertEquals(true, again["record"]?.get("recording")?.bool)
    }

    @Test fun aPassOverAnEarlierOnePlaysInsteadOfIt() = runBlocking<Unit> {
        val host = DemoHost()
        val session = session(host)
        val start = connected(session)
        val track = start.tracks[0].id
        session.perform("tracks.arm", jsonObject { put("track_id", track); put("armed", true) })
        session.perform("markers.go", jsonObject { put("marker_id", "demo-chorus") })
        session.perform("transport.set_count_in", jsonObject { put("bars", 0) })
        session.perform("transport.record", armedIds(track))
        delay(30)
        val firstStop = session.perform("transport.stop")
        val first = required(firstStop["take"]?.get("id")?.string)
        session.perform("takes.go_again", jsonObject { put("take_id", first) })
        delay(150) // longer, so it covers the first
        val secondStop = session.perform("transport.stop")
        val second = required(secondStop["take"]?.get("id")?.string)
        val lanes = eventually(session) { it.takes.size == 2 }
        assertEquals("newest first", listOf(second, first), lanes.takes.map { it.id })
        assertEquals("the newer pass plays, the earlier one waits", listOf(true, false), lanes.takes.map { it.active })
        val discarded = session.perform("takes.discard", jsonObject { put("take_id", second) })
        assertEquals("the earlier take plays again", true, discarded["takes"]?.array?.firstOrNull()?.get("active")?.bool)
        val step = required(discarded["undo"]?.get("undo")?.get("id")?.string)
        session.perform("edit.undo", jsonObject { put("expect", step) })
        val back = eventually(session) { it.takes.size == 2 }
        assertEquals(listOf(true, false), back.takes.map { it.active })
    }

    @Test fun routingMovesOutputsAndSendsAsTabberStudioDoes() = runBlocking<Unit> {
        val session = session(DemoHost())
        connected(session)
        val start = eventually(session) { it.routing != null }
        val routing = required(start.routing)
        assertEquals(listOf("Guitar", "Bass", "Drums", "Lead guitar", "Vocals", "Reverb"), routing.sources.map { it.name })
        assertTrue("every output is the master at first", routing.sources.all { it.output == RoutingState.MASTER })
        assertEquals(listOf("-12.0 dB", "-6.0 dB"), routing.sends.map { it.levelLabel })

        val moved = session.perform("routing.set_output", jsonObject { put("strip_id", "demo-vocals"); put("output", "demo-bus-reverb") })
        assertEquals("Routing change", moved["undo"]?.get("undo")?.get("label")?.string)
        val added = session.perform("routing.set_send", jsonObject { put("strip_id", "demo-guitar"); put("bus_id", "demo-bus-reverb") })
        assertEquals("Add send → Reverb", added["undo"]?.get("undo")?.get("label")?.string)
        val quieter = session.perform(
            "routing.set_send",
            jsonObject { put("strip_id", "demo-guitar"); put("bus_id", "demo-bus-reverb"); put("level", 0.25) },
        )
        assertEquals("a level is no undo step", "Add send → Reverb", quieter["undo"]?.get("undo")?.get("label")?.string)
        val state = eventually(session) { it.routing?.sendsFrom("demo-guitar")?.firstOrNull()?.levelLabel == "-12.0 dB" }
        assertEquals(listOf("Vocals"), state.routing?.feeding("demo-bus-reverb")?.first?.map { it.name })
        assertEquals(
            listOf("demo-guitar", "demo-lead", "demo-vocals"),
            state.routing?.feeding("demo-bus-reverb")?.second?.map { it.stripId },
        )

        val loop = refused("a bus fed itself") {
            session.perform("routing.set_output", jsonObject { put("strip_id", "demo-bus-reverb"); put("output", "demo-bus-reverb") })
        }
        assertEquals("routing_loop", loop.reason)
        assertEquals(listOf("Reverb", "Reverb"), loop.data["path"]?.array?.mapNotNull { it.string })
        val wrong = refused("a bus sent") {
            session.perform("routing.set_send", jsonObject { put("strip_id", "demo-bus-reverb"); put("bus_id", "demo-bus-reverb") })
        }
        assertEquals("wrong_kind", wrong.reason)

        val removed = session.perform(
            "routing.remove_send",
            jsonObject { put("strip_id", "demo-guitar"); put("bus_id", "demo-bus-reverb") },
        )
        val step = required(removed["undo"]?.get("undo")?.get("id")?.string)
        assertEquals("Remove send → Reverb", removed["undo"]?.get("undo")?.get("label")?.string)
        session.perform("edit.undo", jsonObject { put("expect", step) })
        val back = eventually(session) { it.routing?.sendsFrom("demo-guitar")?.size == 1 }
        assertEquals("Undo brings it back as it was", "-12.0 dB", back.routing?.sendsFrom("demo-guitar")?.firstOrNull()?.levelLabel)
    }

    @Test fun theChatPlansThenExecuteIsOneUndoStep() = runBlocking<Unit> {
        val session = session(DemoHost())
        connected(session)
        val start = eventually(session) { it.chat != null }
        assertTrue(start.chat?.available == true && start.chat?.state == "idle")
        val sent = session.perform("chat.send", jsonObject { put("text", "Mute the drums") })
        assertEquals("thinking", sent["chat"]?.get("state")?.string)
        val busy = refused("a second request while the first works") {
            session.perform("chat.send", jsonObject { put("text", "And the bass") })
        }
        assertEquals("chat_busy", busy.reason)
        val waiting = eventually(session) { it.chat?.state == "waiting" }
        val plan = required(waiting.chat?.plan)
        assertEquals(listOf("Mute track: Drums"), plan.steps.map { it.text })
        assertEquals("nothing runs before Execute", false, waiting.mixer?.strips?.firstOrNull { it.name == "Drums" }?.muted)
        val done = session.perform("chat.confirm", jsonObject { put("plan_id", plan.id) })
        assertEquals("Muted the Drums track.", done["chat"]?.get("messages")?.array?.lastOrNull()?.get("text")?.string)
        val after = eventually(session) { it.undo.undo?.label == "AI: Mute the drums" }
        assertEquals("idle", after.chat?.state)
        val gone = refused("a gone plan ran") { session.perform("chat.confirm", jsonObject { put("plan_id", plan.id) }) }
        assertEquals("unknown_plan", gone.reason)
        session.perform("chat.send", jsonObject { put("text", "What is the API key?") })
        val refusal = eventually(session) { it.chat?.state == "idle" && it.chat?.messages?.lastOrNull()?.kind == "refusal" }
        assertEquals(true, refusal.chat?.messages?.lastOrNull()?.text?.contains("settings, key and tools"))
    }

    @Test fun theViewButtonsSwitchWhatTheComputerShows() = runBlocking<Unit> {
        val session = session(DemoHost())
        connected(session)
        val start = eventually(session) { it.view != null }
        assertEquals(ViewState(editor = "tab", split = false), start.view)
        session.perform("view.set", jsonObject { put("editor", "arrange") })
        session.perform("view.set", jsonObject { put("split", true) })
        val split = eventually(session) { it.view?.split == true }
        assertEquals("Split shows an editor beside Arrange", ViewState(editor = "tab", split = true), split.view)
        session.perform("view.set", jsonObject { put("split", false) })
        val back = eventually(session) { it.view?.split == false }
        assertEquals("Split off goes back to the editor before", "arrange", back.view?.editor)
    }

    @Test fun aHeldStepWalksTheBeatsWrittenAndAddsNone() {
        val beat = TabBeat(NoteValue(4), rest = true, notes = emptyList())
        val four = TimeSignature(4, 4)
        var tab = TabState(
            trackId = "t", revision = 1, tuning = listOf(64, 59, 55, 50, 45, 40), drum = false,
            cursor = TabCursor(1, 2, 1), duration = NoteValue(4), barCount = 2,
            bars = listOf(TabBar(1, four, listOf(beat, beat)), TabBar(2, four, listOf(beat, beat, beat))),
        )
        assertEquals("past a bar's last beat, the next bar", TabCursor(2, 1, 1), tab.neighbour(1))
        assertEquals(TabCursor(1, 1, 1), tab.neighbour(-1))
        tab = tab.copy(cursor = TabCursor(2, 3, 1))
        assertNull("the song's last beat: nothing is added", tab.neighbour(1))
        assertTrue(tab.barStep(1) == null && tab.barStep(-1) == TabCursor(1, 1, 1))
        tab = tab.copy(cursor = TabCursor(2, 1, 1))
        assertEquals("back into the bar before, at its last beat", TabCursor(1, 2, 1), tab.neighbour(-1))
    }

    @Test fun aLoopIsNamedFromTheSourceBackToIt() {
        val routing = RoutingState(
            sources = listOf(
                RoutingSource("t", "track", "Vocals", "bus-a"),
                RoutingSource("bus-a", "bus", "Reverb", "bus-b"),
                RoutingSource("bus-b", "bus", "Delay", "master"),
                RoutingSource("bus-c", "bus", "Echo", "bus-a"),
            ),
            sends = emptyList(),
        )
        assertEquals(listOf("Delay", "Reverb", "Delay"), routing.wouldLoop("bus-b", "bus-a"))
        assertEquals(listOf("Delay", "Echo", "Reverb", "Delay"), routing.wouldLoop("bus-b", "bus-c"))
        assertEquals(listOf("Reverb", "Reverb"), routing.wouldLoop("bus-a", "bus-a"))
        assertNull("Delay goes to the master", routing.wouldLoop("bus-c", "bus-b"))
        assertNull(routing.wouldLoop("bus-a", "master"))
        assertEquals("Reverb", routing.outputName(of = routing.sources[0]))
    }

    @Test fun aResendAfterADropRecordsOnce() = runBlocking<Unit> {
        val host = DemoHost()
        val session = session(host)
        val start = connected(session)
        session.perform("tracks.arm", jsonObject { put("track_id", start.tracks[0].id); put("armed", true) })
        host.setDropBeforeNextAnswer(true) // the Wi-Fi drops right after Record
        val answer = session.perform("transport.record", armedIds(start.tracks[0].id))
        assertEquals(true, answer["record"]?.get("recording")?.bool)
        assertEquals(1, host.recordingsStarted())
        val state = eventually(session) { it.link is LinkState.Connected && it.record.recording }
        assertTrue(state.record.recording)
    }

    @Test fun aStaleTargetIsRefusedWithTheTruth() = runBlocking<Unit> {
        val session = session(DemoHost())
        val start = connected(session)
        val failure = refused("recorded on a track that is not armed") {
            session.perform("transport.record", armedIds(start.tracks[1].id))
        }
        assertEquals("stale_target", failure.reason)
        assertEquals(5, failure.data["tracks"]?.array?.size)
    }

    @Test fun eventsComeInOrderWithoutGaps() = runBlocking<Unit> {
        val host = DemoHost()
        val transport = host.connect()
        val client = RemoteClient(transport)
        client.start()
        client.sayHello(app)
        client.pair(
            token = Base64Url.encode(ByteArray(16)), pin = Base64Url.encode(ByteArray(32)),
            device = SoftwareSigner.generate(), name = "Test", model = "test",
        )
        client.subscribe(listOf("transport", "tracks", "position"))
        client.call("transport.play", jsonObject { put("key", UUID.randomUUID().toString().lowercase()) })
        val seqs = mutableListOf<Int>()
        for (message in client.incoming) {
            if (message is Incoming.EventArrived) seqs.add(message.event.seq)
            if (seqs.size == 8) break
        }
        assertEquals((1..8).toList(), seqs)
        client.close()
    }

    @Test fun soloAndMuteAreUndoStepsAndFadersAreNot() = runBlocking<Unit> {
        val session = session(DemoHost())
        connected(session)
        val lead = "demo-lead"
        session.perform("mixer.set_solo", jsonObject { put("strip_id", lead); put("soloed", true) })
        val soloed = eventually(session) { state -> state.mixer?.strips?.firstOrNull { it.id == lead }?.soloed == true }
        val step = required(soloed.undo.undo)
        assertEquals("Solo Lead guitar", step.label)
        val moved = session.perform("mixer.set_volume", jsonObject { put("strip_id", lead); put("volume", 0.442) })
        assertEquals(-12.0, moved["strip"]?.get("volume_db")?.double)
        val after = eventually(session) { state -> state.mixer?.strips?.firstOrNull { it.id == lead }?.volume == 0.442 }
        assertEquals(step.id, after.undo.undo?.id)
        session.perform("edit.undo", jsonObject { put("expect", step.id) })
        val undone = eventually(session) { state -> state.mixer?.strips?.firstOrNull { it.id == lead }?.soloed == false }
        assertEquals(0.442, undone.mixer?.strips?.firstOrNull { it.id == lead }?.volume)
    }

    @Test fun aFretboardTapWritesAtTheCursorAndUndoTakesItBack() = runBlocking<Unit> {
        val session = session(DemoHost())
        val start = connected(session)
        assertEquals(16, start.tab?.barCount)
        session.perform("tab.set_cursor", jsonObject { put("bar", 9); put("beat", 1); put("string", 1) })
        session.perform("tab.set_duration", jsonObject { put("value", 8) })
        val tap = session.perform("tab.put", jsonObject { put("string", 2); put("fret", 3) })
        val one = TabState.from(JsonReader(tap["tab"]!!))
        assertEquals(listOf(TabNote(2, 3)), one.cursorBeat?.notes)
        assertEquals(NoteValue(8), one.cursorBeat?.duration)
        assertEquals(2, one.cursor.string)
        val key = session.perform("tab.put_pitch", jsonObject { put("pitch", 64) })
        val chord = TabState.from(JsonReader(key["tab"]!!))
        assertEquals(listOf(TabNote(1, 0), TabNote(2, 3)), chord.cursorBeat?.notes)
        val again = session.perform("tab.put", jsonObject { put("string", 1); put("fret", 0) })
        assertEquals(listOf(TabNote(2, 3)), TabState.from(JsonReader(again["tab"]!!)).cursorBeat?.notes)
        val next = session.perform("tab.move", jsonObject { put("by", 1) })
        val moved = TabState.from(JsonReader(next["tab"]!!))
        assertTrue(moved.cursor.bar == 9 && moved.cursor.beat == 2 && moved.cursorBeat?.rest == true)
        val inserted = required(eventually(session) { it.undo.undo?.label == "Insert beat" }.undo.undo)
        session.perform("edit.undo", jsonObject { put("expect", inserted.id) })
        val back = eventually(session) { state -> state.tab?.bars?.firstOrNull { it.bar == 9 }?.beats?.size == 1 }
        assertEquals(listOf(TabNote(2, 3)), back.tab?.bars?.firstOrNull { it.bar == 9 }?.beats?.firstOrNull()?.notes)
    }

    @Test fun anAudioTrackHasNoTab() = runBlocking<Unit> {
        val session = session(DemoHost())
        connected(session)
        session.perform("tracks.select", jsonObject { put("track_id", "demo-vocals") })
        eventually(session) { state -> state.tracks.firstOrNull { it.selected }?.id == "demo-vocals" && state.tab == null }
        refused { session.perform("tab.put", jsonObject { put("string", 1); put("fret", 0) }) }
    }

    /** S6 on the demo computer: Loop first, then the trainer steps up each time the loop comes round, and Loop off turns it off. */
    @Test fun theSpeedTrainerStepsUpEachTimeTheLoopComesRound() = runBlocking<Unit> {
        val session = session(DemoHost())
        val start = connected(session)
        assertEquals(TrainerState(), start.trainer)
        refused { session.perform("trainer.set", jsonObject { put("enabled", true); put("start", 150) }) }
        session.perform(
            "transport.set_loop",
            jsonObject {
                put("enabled", true)
                put("start", jsonObject { put("bar", 1); put("beat", 1) })
                put("end", jsonObject { put("bar", 1); put("beat", 2) })
            },
        )
        val on = session.perform("trainer.set", jsonObject { put("enabled", true); put("start", 150); put("step", 10); put("target", 170) })
        assertEquals(
            TrainerState(enabled = true, start = 150, step = 10, target = 170, speed = 150),
            TrainerState.from(JsonReader(on["trainer"]!!)),
        )
        session.perform("transport.play")
        val faster = eventually(session) { it.trainer?.speed == 170 }
        assertEquals("two loops on, at the target", 1.7, faster.transport?.tempoScale)
        val again = session.perform("trainer.set", jsonObject { put("target", 160) })
        assertEquals("a changed field starts the ramp again", 150, TrainerState.from(JsonReader(again["trainer"]!!)).speed)
        session.perform("transport.set_loop", jsonObject { put("enabled", false) })
        val off = eventually(session) { it.trainer?.enabled == false }
        assertTrue(off.trainer?.speed == 100 && off.transport?.tempoScale == 1.0)
        session.perform("transport.stop")
        session.stop()
    }

    /**
     * TR36 on the demo computer: each kind as Tabber Studio's "+ Add Track" makes it, in its place
     * in the list, one undo step that Undo takes back.
     */
    @Test fun addingATrackOfEachKindIsOneUndoStep() = runBlocking<Unit> {
        val session = session(DemoHost())
        connected(session)
        val tab = session.perform("tracks.add", jsonObject { put("kind", "tab") })
        val track = Track.from(JsonReader(tab["track"]!!))
        assertTrue(track.name == "Track 4" && track.hasTab && track.selected)
        val added = eventually(session) { it.tab?.trackId == track.id }
        assertEquals(
            "after the last tab or MIDI track, before the audio",
            listOf("Guitar", "Bass", "Drums", "Track 4", "Lead guitar", "Vocals"), added.tracks.map { it.name },
        )
        assertEquals("it spans the song, and the Tab screen writes on it at once", 16, added.tab?.barCount)
        assertEquals("Add track: Track 4", added.undo.undo?.label)

        val midi = Track.from(JsonReader(session.perform("tracks.add", jsonObject { put("kind", "midi") })["track"]!!))
        assertTrue(midi.name == "MIDI Track 5" && !midi.hasTab && midi.instrument == "Acoustic Grand Piano")
        val audio = session.perform("tracks.add", jsonObject { put("kind", "audio") })
        assertEquals("Audio 3", Track.from(JsonReader(audio["track"]!!)).name)
        val shown = eventually(session) { it.view?.editor == "arrange" }
        assertEquals("an audio track goes last, and the computer shows Arrange", "Audio 3", shown.tracks.lastOrNull()?.name)

        val step = required(shown.undo.undo)
        assertEquals("Add audio track: Audio 3", step.label)
        session.perform("edit.undo", jsonObject { put("expect", step.id) })
        val back = eventually(session) { state -> state.tracks.none { it.name == "Audio 3" } }
        assertTrue(back.tracks.size == 7 && back.undo.redo?.label == "Add audio track: Audio 3")
        refused { session.perform("tracks.add", jsonObject { put("kind", "bass") }) }
        session.perform("tracks.arm", jsonObject { put("track_id", "demo-vocals"); put("armed", true) })
        session.perform("transport.record", armedIds("demo-vocals"))
        refused("not while recording: it would end the take") { session.perform("tracks.add", jsonObject { put("kind", "audio") }) }
        session.perform("transport.stop")
        session.stop()
    }

    /**
     * TR39 on the demo computer: a MIDI track chosen in the Tab editor waits on Tabber Studio's
     * "MIDI part" card until the phone answers it; drums offer only notation, and a card that is
     * gone is refused.
     */
    @Test fun theMidiPartCardWaitsForTheChoice() = runBlocking<Unit> {
        val session = session(DemoHost())
        val start = connected(session)
        assertNull("Guitar has tab: no part", start.view?.part)
        val added = Track.from(JsonReader(session.perform("tracks.add", jsonObject { put("kind", "midi") })["track"]!!))
        val card = eventually(session) { it.view?.part?.trackId == added.id }
        assertEquals(ViewPart(added.id, "card", midiTab = true), card.view?.part)
        val shown = session.perform("view.show_part", jsonObject { put("track_id", added.id); put("as", "midi_tab") })
        assertEquals("midi_tab", ViewState.from(JsonReader(shown["view"]!!)).part?.shows)
        refused("the card is gone") {
            session.perform("view.show_part", jsonObject { put("track_id", added.id); put("as", "notation") })
        }
        session.perform("tracks.select", jsonObject { put("track_id", "demo-drums") })
        val drums = eventually(session) { it.view?.part?.trackId == "demo-drums" }
        assertEquals(false, drums.view?.part?.midiTab)
        refused("drums cannot show MIDI tab") {
            session.perform("view.show_part", jsonObject { put("track_id", "demo-drums"); put("as", "midi_tab") })
        }
        session.perform("view.show_part", jsonObject { put("track_id", "demo-drums"); put("as", "notation") })
        session.perform("view.set", jsonObject { put("editor", "arrange") })
        val arrange = eventually(session) { it.view?.editor == "arrange" }
        assertNull("Arrange shows no card", arrange.view?.part)
        session.stop()
    }

    /** TR40 on the demo computer: a MIDI track shown as MIDI tab is written as tab, while the Tab editor shows it. */
    @Test fun aMidiTracksMidiTabIsWrittenWhileTheTabEditorShowsIt() = runBlocking<Unit> {
        val session = session(DemoHost())
        connected(session)
        val added = Track.from(JsonReader(session.perform("tracks.add", jsonObject { put("kind", "midi") })["track"]!!))
        assertNull("the card first: no tab yet", eventually(session) { it.view?.part?.trackId == added.id }.tab)
        session.perform("view.show_part", jsonObject { put("track_id", added.id); put("as", "midi_tab") })
        val shown = eventually(session) { it.tab?.trackId == added.id }
        assertTrue(shown.tab?.isMidiTab == true && shown.tab?.tuning == DemoTab.STANDARD)
        val tap = session.perform("tab.put", jsonObject { put("string", 2); put("fret", 3) })
        val tab = TabState.from(JsonReader(tap["tab"]!!))
        assertEquals(listOf(TabNote(2, 3)), tab.cursorBar?.beats?.firstOrNull()?.notes)
        session.perform("view.set", jsonObject { put("editor", "arrange") })
        val off = eventually(session) { it.view?.editor == "arrange" && it.tab == null }
        assertNull("no MIDI tab off the Tab editor", off.tab)
        refused { session.perform("tab.put", jsonObject { put("string", 1); put("fret", 0) }) }
        session.stop()
    }

    /** TR41 on the demo computer: + Bus named as typed, before the master, in the mixer and the routing, and no undo step. */
    @Test fun addBusIsNamedAsTypedAndNoUndoStep() = runBlocking<Unit> {
        val session = session(DemoHost())
        val start = connected(session)
        val added = session.perform("mixer.add_bus", jsonObject { put("name", " Delay ") })
        val strip = Strip.from(JsonReader(added["strip"]!!))
        assertTrue(strip.name == "Delay" && strip.isBus)
        val after = eventually(session) { state -> state.mixer?.strips?.any { it.id == strip.id } == true }
        assertEquals("the new bus comes before the master", true, after.mixer?.strips?.lastOrNull()?.isMaster)
        assertEquals("no undo step", start.undo, after.undo)
        session.perform("routing.state")
        val routed = eventually(session) { state -> state.routing?.sources?.any { it.stripId == strip.id } == true }
        assertNotNull(routed.routing)
        refused { session.perform("mixer.add_bus", jsonObject { put("name", "   ") }) }
        session.stop()
    }

    /**
     * TR44 on the demo computer: the browser's rows, an effect at the end of a strip's chain,
     * bypassed and removed; an instrument becomes a MIDI track's sound source and is refused on an
     * audio track; no undo steps.
     */
    @Test fun pluginsAreInsertedBypassedAndRemoved() = runBlocking<Unit> {
        val session = session(DemoHost())
        val start = connected(session)
        val page = PluginPage.from(JsonReader(session.perform("plugins.catalog")))
        assertTrue(page.total == page.plugins.size && page.plugins.first().name == "Tabber Amp")
        assertEquals("Tabber's own first", page.plugins.filter { it.tabber }.size, page.plugins.takeWhile { it.tabber }.size)
        val second = PluginPage.from(JsonReader(session.perform("plugins.catalog", jsonObject { put("offset", 2); put("limit", 2) })))
        assertTrue(second.offset == 2 && second.plugins.map { it.id } == page.plugins.drop(2).take(2).map { it.id })
        session.perform("mixer.state")
        val mixer = required(eventually(session) { it.mixer != null }.mixer)
        assertEquals(listOf("Tabber Amp"), mixer.strips.first { it.id == "demo-guitar" }.inserts.map { it.name })
        val compressor = page.plugins.first { it.name == "Tabber Compressor" }
        val added = session.perform("plugins.insert", jsonObject { put("strip_id", "demo-vocals"); put("plugin_id", compressor.id) })
        val vocals = Strip.from(JsonReader(required(added["strip"])))
        assertTrue(vocals.inserts.map { it.name } == listOf("Tabber Compressor") && added["sound_source"]?.bool == false)
        val insert = vocals.inserts[0]
        val off = session.perform("plugins.bypass", jsonObject { put("strip_id", "demo-vocals"); put("insert_id", insert.id); put("bypassed", true) })
        assertEquals(true, Strip.from(JsonReader(required(off["strip"]))).inserts.firstOrNull()?.bypassed)
        assertEquals(Json.Obj(emptyMap()), session.perform("plugins.open", jsonObject { put("strip_id", "demo-vocals"); put("insert_id", insert.id) }))
        session.perform("plugins.remove", jsonObject { put("strip_id", "demo-vocals"); put("insert_id", insert.id) })
        val after = eventually(session) { s -> s.mixer?.strips?.firstOrNull { it.id == "demo-vocals" }?.inserts?.isEmpty() == true }
        assertEquals("plug-ins are no undo steps", start.undo, after.undo)
        val gone = refused { session.perform("plugins.remove", jsonObject { put("strip_id", "demo-vocals"); put("insert_id", insert.id) }) }
        assertEquals("stale_target", gone.reason)
        val synth = page.plugins.first { it.isInstrument }
        val source = session.perform("plugins.insert", jsonObject { put("strip_id", "demo-guitar"); put("plugin_id", synth.id) })
        assertEquals("an instrument becomes the MIDI track's sound source", true, source["sound_source"]?.bool)
        refused { session.perform("plugins.insert", jsonObject { put("strip_id", "demo-vocals"); put("plugin_id", synth.id) }) }
        session.stop()
    }

    /**
     * Spec 8.2: an event the phone already holds is ignored. Asking for a new snapshot for it, as
     * the phone did, could loop while events stream (found porting the app to Android).
     */
    @Test fun anEventAlreadyHeldAsksForNoSnapshot() = runBlocking<Unit> {
        val host = DemoHost()
        val session = session(host)
        connected(session)
        session.perform("transport.set_click", jsonObject { put("enabled", true) })
        eventually(session) { it.transport?.click == true }
        val before = host.snapshotsServed()
        repeat(5) {
            host.resendLastEvent()
            delay(40)
        }
        delay(300)
        assertEquals("no snapshot for an event already held", before, host.snapshotsServed())
        session.perform("transport.set_click", jsonObject { put("enabled", false) })
        val after = eventually(session) { it.transport?.click == false }
        assertEquals("and the phone still follows the computer", LinkState.Connected(busy = false), after.link)
        session.stop()
    }
}
