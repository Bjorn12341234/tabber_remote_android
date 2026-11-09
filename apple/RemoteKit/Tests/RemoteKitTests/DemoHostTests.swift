import Foundation
import Testing
@testable import RemoteKit

/// The app's whole take loop against DemoHost, through RemoteSession.
@Suite("DemoHost sessions")
struct DemoHostTests {
    static let app = AppInfo(version: "1.0", build: "1")

    func session(_ host: DemoHost) -> RemoteSession {
        RemoteSession(credentials: .demo, app: Self.app) { _ in await host.connect() }
    }

    func connected(_ session: RemoteSession) async throws -> SessionState {
        await session.start()
        for _ in 0..<200 {
            let state = await session.state
            if case .connected = state.link, state.transport != nil { return state }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("never connected")
        return await session.state
    }

    func eventually(_ session: RemoteSession, _ check: (SessionState) -> Bool) async throws -> SessionState {
        for _ in 0..<300 {
            let state = await session.state
            if check(state) { return state }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("the state never got there")
        return await session.state
    }

    @Test func theSnapshotArrives() async throws {
        let state = try await connected(session(DemoHost()))
        #expect(state.tracks.map(\.name) == ["Guitar", "Bass", "Drums", "Lead guitar", "Vocals"])
        #expect(state.capabilities.isSuperset(of: ["mixer/1", "tab/1"]))
        #expect(state.mixer?.strips.map(\.name) == ["Guitar", "Bass", "Drums", "Lead guitar", "Vocals", "Reverb", "Master"])
        #expect(state.tab?.trackID == "demo-guitar" && state.tab?.strings == 6)
        #expect(state.markers.map(\.name) == ["Intro", "Verse", "Chorus", "Solo"])
        #expect(state.capabilities.contains("takes.go_again/1"))
        #expect(state.transport?.state == .stopped)
    }

    @Test func S1FiveTakesOfTheChorus() async throws {
        let host = DemoHost()
        let session = session(host)
        let start = try await connected(session)
        let vocals = start.tracks[0].id
        _ = try await session.perform("tracks.arm", ["track_id": .string(vocals), "armed": true])
        _ = try await session.perform("markers.go", ["marker_id": "demo-chorus"])
        let counted = try await session.perform("transport.set_count_in", ["bars": 0])
        #expect(counted["transport"]?["count_in_bars"]?.intValue == 0)
        var keptTakes: [String] = []
        for number in 1...5 {
            _ = try await session.perform("transport.record", ["armed_track_ids": [.string(vocals)]])
            let recording = try await eventually(session) { $0.record.recording }
            #expect(recording.record.started?.position.bar == 25)
            try await Task.sleep(for: .milliseconds(30))
            let stopped = try await session.perform("transport.stop")
            let take = try #require(stopped["take"].flatMap { try? JSONCoding.decode(Take.self, from: $0) })
            #expect(take.start.bar == 25 && take.trackID == vocals)
            if number.isMultiple(of: 2) {
                let discarded = try await session.perform("takes.discard", ["take_id": .string(take.id)])
                #expect(discarded["takes"]?.arrayValue?.contains { $0["id"]?.stringValue == take.id } == false)
            } else {
                keptTakes.append(take.id)
            }
            _ = try await session.perform("markers.go", ["marker_id": "demo-chorus"])
        }
        let after = try await eventually(session) { $0.takes.count == 3 }
        #expect(Set(after.takes.map(\.id)) == Set(keptTakes))
        let undoStep = try #require(after.undo.undo)
        #expect(undoStep.label == "Record take")
    }

    @Test func discardThenUndoBringsTheTakeBack() async throws {
        let host = DemoHost()
        let session = session(host)
        let start = try await connected(session)
        _ = try await session.perform("tracks.arm", ["track_id": .string(start.tracks[0].id), "armed": true])
        _ = try await session.perform("transport.record", ["armed_track_ids": [.string(start.tracks[0].id)]])
        let stopped = try await session.perform("transport.stop")
        let takeID = try #require(stopped["take"]?["id"]?.stringValue)
        let discarded = try await session.perform("takes.discard", ["take_id": .string(takeID)])
        let step = try #require(discarded["undo"]?["undo"]?["id"]?.stringValue)
        _ = try await session.perform("edit.undo", ["expect": .string(step)])
        let back = try await eventually(session) { $0.takes.contains { $0.id == takeID } }
        #expect(back.undo.redo?.label == "Discard take")
        await #expect(throws: RemoteError.self) {
            try await session.perform("edit.undo", ["expect": "not-this-one"])
        }
        let again = try await session.perform("takes.go_again", ["take_id": .string(takeID)])
        #expect(again["record"]?["recording"]?.boolValue == true)
    }

    @Test func aPassOverAnEarlierOnePlaysInsteadOfIt() async throws {
        let host = DemoHost()
        let session = session(host)
        let start = try await connected(session)
        let track = start.tracks[0].id
        _ = try await session.perform("tracks.arm", ["track_id": .string(track), "armed": true])
        _ = try await session.perform("markers.go", ["marker_id": "demo-chorus"])
        _ = try await session.perform("transport.set_count_in", ["bars": 0])
        _ = try await session.perform("transport.record", ["armed_track_ids": [.string(track)]])
        try await Task.sleep(for: .milliseconds(30))
        let firstStop = try await session.perform("transport.stop")
        let first = try #require(firstStop["take"]?["id"]?.stringValue)
        _ = try await session.perform("takes.go_again", ["take_id": .string(first)])
        try await Task.sleep(for: .milliseconds(150))              // longer, so it covers the first
        let secondStop = try await session.perform("transport.stop")
        let second = try #require(secondStop["take"]?["id"]?.stringValue)
        let lanes = try await eventually(session) { $0.takes.count == 2 }
        #expect(lanes.takes.map(\.id) == [second, first], "newest first")
        #expect(lanes.takes.map(\.active) == [true, false], "the newer pass plays, the earlier one waits")
        let discarded = try await session.perform("takes.discard", ["take_id": .string(second)])
        #expect(discarded["takes"]?.arrayValue?.first?["active"]?.boolValue == true, "the earlier take plays again")
        let step = try #require(discarded["undo"]?["undo"]?["id"]?.stringValue)
        _ = try await session.perform("edit.undo", ["expect": .string(step)])
        let back = try await eventually(session) { $0.takes.count == 2 }
        #expect(back.takes.map(\.active) == [true, false])
    }

    @Test func routingMovesOutputsAndSendsAsTabberStudioDoes() async throws {
        let session = session(DemoHost())
        _ = try await connected(session)
        let start = try await eventually(session) { $0.routing != nil }
        let routing = try #require(start.routing)
        #expect(routing.sources.map(\.name) == ["Guitar", "Bass", "Drums", "Lead guitar", "Vocals", "Reverb"])
        #expect(routing.sources.allSatisfy { $0.output == RoutingState.master }, "every output is the master at first")
        #expect(routing.sends.map(\.levelLabel) == ["-12.0 dB", "-6.0 dB"])

        let moved = try await session.perform("routing.set_output", ["strip_id": "demo-vocals", "output": "demo-bus-reverb"])
        #expect(moved["undo"]?["undo"]?["label"]?.stringValue == "Routing change")
        let added = try await session.perform("routing.set_send", ["strip_id": "demo-guitar", "bus_id": "demo-bus-reverb"])
        #expect(added["undo"]?["undo"]?["label"]?.stringValue == "Add send → Reverb")
        let quieter = try await session.perform("routing.set_send",
                                                ["strip_id": "demo-guitar", "bus_id": "demo-bus-reverb", "level": 0.25])
        #expect(quieter["undo"]?["undo"]?["label"]?.stringValue == "Add send → Reverb", "a level is no undo step")
        let state = try await eventually(session) { $0.routing?.sends(from: "demo-guitar").first?.levelLabel == "-12.0 dB" }
        #expect(state.routing?.feeding("demo-bus-reverb").outputs.map(\.name) == ["Vocals"])
        #expect(state.routing?.feeding("demo-bus-reverb").sends.map(\.stripID) == ["demo-guitar", "demo-lead", "demo-vocals"])

        do {
            _ = try await session.perform("routing.set_output", ["strip_id": "demo-bus-reverb", "output": "demo-bus-reverb"])
            Issue.record("a bus fed itself")
        } catch let failure as RemoteError {
            #expect(failure.reason == "routing_loop")
            #expect(failure.data["path"]?.arrayValue?.compactMap(\.stringValue) == ["Reverb", "Reverb"])
        }
        do {
            _ = try await session.perform("routing.set_send", ["strip_id": "demo-bus-reverb", "bus_id": "demo-bus-reverb"])
            Issue.record("a bus sent")
        } catch let failure as RemoteError {
            #expect(failure.reason == "wrong_kind")
        }

        let removed = try await session.perform("routing.remove_send", ["strip_id": "demo-guitar", "bus_id": "demo-bus-reverb"])
        let step = try #require(removed["undo"]?["undo"]?["id"]?.stringValue)
        #expect(removed["undo"]?["undo"]?["label"]?.stringValue == "Remove send → Reverb")
        _ = try await session.perform("edit.undo", ["expect": .string(step)])
        let back = try await eventually(session) { $0.routing?.sends(from: "demo-guitar").count == 1 }
        #expect(back.routing?.sends(from: "demo-guitar").first?.levelLabel == "-12.0 dB", "Undo brings it back as it was")
    }

    @Test func theChatPlansThenExecuteIsOneUndoStep() async throws {
        let session = session(DemoHost())
        _ = try await connected(session)
        let start = try await eventually(session) { $0.chat != nil }
        #expect(start.chat?.available == true && start.chat?.state == "idle")
        let sent = try await session.perform("chat.send", ["text": "Mute the drums"])
        #expect(sent["chat"]?["state"]?.stringValue == "thinking")
        do {
            _ = try await session.perform("chat.send", ["text": "And the bass"])
            Issue.record("a second request while the first works")
        } catch let failure as RemoteError {
            #expect(failure.reason == "chat_busy")
        }
        let waiting = try await eventually(session) { $0.chat?.state == "waiting" }
        let plan = try #require(waiting.chat?.plan)
        #expect(plan.steps.map(\.text) == ["Mute track: Drums"])
        #expect(waiting.mixer?.strips.first { $0.name == "Drums" }?.muted == false, "nothing runs before Execute")
        let done = try await session.perform("chat.confirm", ["plan_id": .string(plan.id)])
        #expect(done["chat"]?["messages"]?.arrayValue?.last?["text"]?.stringValue == "Muted the Drums track.")
        let after = try await eventually(session) { $0.undo.undo?.label == "AI: Mute the drums" }
        #expect(after.chat?.state == "idle")
        do {
            _ = try await session.perform("chat.confirm", ["plan_id": .string(plan.id)])
            Issue.record("a gone plan ran")
        } catch let failure as RemoteError {
            #expect(failure.reason == "unknown_plan")
        }
        _ = try await session.perform("chat.send", ["text": "What is the API key?"])
        let refused = try await eventually(session) { $0.chat?.state == "idle" && $0.chat?.messages.last?.kind == "refusal" }
        #expect(refused.chat?.messages.last?.text.contains("settings, key and tools") == true)
    }

    @Test func theViewButtonsSwitchWhatTheComputerShows() async throws {
        let session = session(DemoHost())
        _ = try await connected(session)
        let start = try await eventually(session) { $0.view != nil }
        #expect(start.view == ViewState(editor: "tab", split: false))
        _ = try await session.perform("view.set", ["editor": "arrange"])
        _ = try await session.perform("view.set", ["split": true])
        let split = try await eventually(session) { $0.view?.split == true }
        #expect(split.view == ViewState(editor: "tab", split: true), "Split shows an editor beside Arrange")
        _ = try await session.perform("view.set", ["split": false])
        let back = try await eventually(session) { $0.view?.split == false }
        #expect(back.view?.editor == "arrange", "Split off goes back to the editor before")
    }

    @Test func aHeldStepWalksTheBeatsWrittenAndAddsNone() {
        let beat = TabBeat(duration: NoteValue(value: 4), rest: true, notes: [])
        let four = TimeSignature(beats: 4, unit: 4)
        var tab = TabState(trackID: "t", revision: 1, tuning: [64, 59, 55, 50, 45, 40], drum: false,
                           cursor: TabCursor(bar: 1, beat: 2, string: 1), duration: NoteValue(value: 4), barCount: 2,
                           bars: [TabBar(bar: 1, timeSignature: four, beats: [beat, beat]),
                                  TabBar(bar: 2, timeSignature: four, beats: [beat, beat, beat])])
        #expect(tab.neighbour(1) == TabCursor(bar: 2, beat: 1, string: 1), "past a bar's last beat, the next bar")
        #expect(tab.neighbour(-1) == TabCursor(bar: 1, beat: 1, string: 1))
        tab.cursor = TabCursor(bar: 2, beat: 3, string: 1)
        #expect(tab.neighbour(1) == nil, "the song's last beat: nothing is added")
        #expect(tab.barStep(1) == nil && tab.barStep(-1) == TabCursor(bar: 1, beat: 1, string: 1))
        tab.cursor = TabCursor(bar: 2, beat: 1, string: 1)
        #expect(tab.neighbour(-1) == TabCursor(bar: 1, beat: 2, string: 1), "back into the bar before, at its last beat")
    }

    @Test func aLoopIsNamedFromTheSourceBackToIt() {
        let routing = RoutingState(sources: [
            RoutingSource(stripID: "t", kind: "track", name: "Vocals", output: "bus-a"),
            RoutingSource(stripID: "bus-a", kind: "bus", name: "Reverb", output: "bus-b"),
            RoutingSource(stripID: "bus-b", kind: "bus", name: "Delay", output: "master"),
            RoutingSource(stripID: "bus-c", kind: "bus", name: "Echo", output: "bus-a"),
        ], sends: [])
        #expect(routing.wouldLoop("bus-b", into: "bus-a") == ["Delay", "Reverb", "Delay"])
        #expect(routing.wouldLoop("bus-b", into: "bus-c") == ["Delay", "Echo", "Reverb", "Delay"])
        #expect(routing.wouldLoop("bus-a", into: "bus-a") == ["Reverb", "Reverb"])
        #expect(routing.wouldLoop("bus-c", into: "bus-b") == nil, "Delay goes to the master")
        #expect(routing.wouldLoop("bus-a", into: "master") == nil)
        #expect(routing.outputName(of: routing.sources[0]) == "Reverb")
    }

    @Test func aResendAfterADropRecordsOnce() async throws {
        let host = DemoHost()
        let session = session(host)
        let start = try await connected(session)
        _ = try await session.perform("tracks.arm", ["track_id": .string(start.tracks[0].id), "armed": true])
        await host.setDropBeforeNextAnswer(true)        // the Wi-Fi drops right after Record
        let answer = try await session.perform("transport.record", ["armed_track_ids": [.string(start.tracks[0].id)]])
        #expect(answer["record"]?["recording"]?.boolValue == true)
        #expect(await host.recordingsStarted == 1)
        let state = try await eventually(session) { if case .connected = $0.link { return $0.record.recording }; return false }
        #expect(state.record.recording)
    }

    @Test func aStaleTargetIsRefusedWithTheTruth() async throws {
        let session = session(DemoHost())
        let start = try await connected(session)
        do {
            _ = try await session.perform("transport.record", ["armed_track_ids": [.string(start.tracks[1].id)]])
            Issue.record("recorded on a track that is not armed")
        } catch let failure as RemoteError {
            #expect(failure.reason == "stale_target")
            #expect(failure.data["tracks"]?.arrayValue?.count == 5)
        }
    }

    @Test func eventsComeInOrderWithoutGaps() async throws {
        let host = DemoHost()
        let transport = await host.connect()
        let client = RemoteClient(transport: transport)
        await client.start()
        _ = try await client.sayHello(app: Self.app)
        _ = try await client.pair(token: Base64URL.encode(Data(count: 16)), pin: Base64URL.encode(Data(count: 32)),
                                  device: SoftwareSigner(), name: "Test", model: "test")
        _ = try await client.subscribe(["transport", "tracks", "position"])
        _ = try await client.call("transport.play", ["key": .string(UUID().uuidString.lowercased())])
        var seqs: [Int] = []
        for await message in client.incoming {
            if case .event(let event) = message { seqs.append(event.seq) }
            if seqs.count == 8 { break }
        }
        #expect(seqs == Array(1...8))
        await client.close()
    }

    @Test func soloAndMuteAreUndoStepsAndFadersAreNot() async throws {
        let session = session(DemoHost())
        _ = try await connected(session)
        let lead = "demo-lead"
        _ = try await session.perform("mixer.set_solo", ["strip_id": .string(lead), "soloed": true])
        let soloed = try await eventually(session) { $0.mixer?.strips.first { $0.id == lead }?.soloed == true }
        let step = try #require(soloed.undo.undo)
        #expect(step.label == "Solo Lead guitar")
        let moved = try await session.perform("mixer.set_volume", ["strip_id": .string(lead), "volume": 0.442])
        #expect(moved["strip"]?["volume_db"]?.doubleValue == -12)
        let after = try await eventually(session) { $0.mixer?.strips.first { $0.id == lead }?.volume == 0.442 }
        #expect(after.undo.undo?.id == step.id)
        _ = try await session.perform("edit.undo", ["expect": .string(step.id)])
        let undone = try await eventually(session) { $0.mixer?.strips.first { $0.id == lead }?.soloed == false }
        #expect(undone.mixer?.strips.first { $0.id == lead }?.volume == 0.442)
    }

    @Test func aFretboardTapWritesAtTheCursorAndUndoTakesItBack() async throws {
        let session = session(DemoHost())
        let start = try await connected(session)
        #expect(start.tab?.barCount == 16)
        _ = try await session.perform("tab.set_cursor", ["bar": 9, "beat": 1, "string": 1])
        _ = try await session.perform("tab.set_duration", ["value": 8])
        let put = try await session.perform("tab.put", ["string": 2, "fret": 3])
        let one = try JSONCoding.decode(TabState.self, from: put["tab"]!)
        #expect(one.cursorBeat?.notes == [TabNote(string: 2, fret: 3)])
        #expect(one.cursorBeat?.duration == NoteValue(value: 8))
        #expect(one.cursor.string == 2)
        let key = try await session.perform("tab.put_pitch", ["pitch": 64])
        let chord = try JSONCoding.decode(TabState.self, from: key["tab"]!)
        #expect(chord.cursorBeat?.notes == [TabNote(string: 1, fret: 0), TabNote(string: 2, fret: 3)])
        let again = try await session.perform("tab.put", ["string": 1, "fret": 0])
        #expect(try JSONCoding.decode(TabState.self, from: again["tab"]!).cursorBeat?.notes == [TabNote(string: 2, fret: 3)])
        let next = try await session.perform("tab.move", ["by": 1])
        let moved = try JSONCoding.decode(TabState.self, from: next["tab"]!)
        #expect(moved.cursor.bar == 9 && moved.cursor.beat == 2 && moved.cursorBeat?.rest == true)
        let inserted = try #require(try await eventually(session) { $0.undo.undo?.label == "Insert beat" }.undo.undo)
        _ = try await session.perform("edit.undo", ["expect": .string(inserted.id)])
        let back = try await eventually(session) { $0.tab?.bars.first { $0.bar == 9 }?.beats.count == 1 }
        #expect(back.tab?.bars.first { $0.bar == 9 }?.beats.first?.notes == [TabNote(string: 2, fret: 3)])
    }

    @Test func anAudioTrackHasNoTab() async throws {
        let session = session(DemoHost())
        _ = try await connected(session)
        _ = try await session.perform("tracks.select", ["track_id": "demo-vocals"])
        _ = try await eventually(session) { $0.tracks.first(where: \.selected)?.id == "demo-vocals" && $0.tab == nil }
        await #expect(throws: RemoteError.self) { try await session.perform("tab.put", ["string": 1, "fret": 0]) }
    }

    /// S6 on the demo computer: Loop first, then the trainer steps up each
    /// time the loop comes round, and Loop off turns it off.
    @Test func theSpeedTrainerStepsUpEachTimeTheLoopComesRound() async throws {
        let session = session(DemoHost())
        let start = try await connected(session)
        #expect(start.trainer == TrainerState())
        await #expect(throws: RemoteError.self) {
            try await session.perform("trainer.set", ["enabled": true, "start": 150])
        }
        _ = try await session.perform("transport.set_loop", ["enabled": true, "start": ["bar": 1, "beat": 1],
                                                             "end": ["bar": 1, "beat": 2]])
        let on = try await session.perform("trainer.set", ["enabled": true, "start": 150, "step": 10, "target": 170])
        #expect(try JSONCoding.decode(TrainerState.self, from: on["trainer"]!)
                == TrainerState(enabled: true, start: 150, step: 10, target: 170, speed: 150))
        _ = try await session.perform("transport.play")
        let faster = try await eventually(session) { $0.trainer?.speed == 170 }
        #expect(faster.transport?.tempoScale == 1.7, "two loops on, at the target")
        let again = try await session.perform("trainer.set", ["target": 160])
        #expect(try JSONCoding.decode(TrainerState.self, from: again["trainer"]!).speed == 150,
                "a changed field starts the ramp again")
        _ = try await session.perform("transport.set_loop", ["enabled": false])
        let off = try await eventually(session) { $0.trainer?.enabled == false }
        #expect(off.trainer?.speed == 100 && off.transport?.tempoScale == 1.0)
        _ = try await session.perform("transport.stop")
        await session.stop()
    }

    /// TR36 on the demo computer: each kind as Tabber Studio's "+ Add Track"
    /// makes it, in its place in the list, one undo step that Undo takes back.
    @Test func addingATrackOfEachKindIsOneUndoStep() async throws {
        let session = session(DemoHost())
        _ = try await connected(session)
        let tab = try await session.perform("tracks.add", ["kind": "tab"])
        let track = try JSONCoding.decode(Track.self, from: tab["track"]!)
        #expect(track.name == "Track 4" && track.hasTab && track.selected)
        let added = try await eventually(session) { $0.tab?.trackID == track.id }
        #expect(added.tracks.map(\.name) == ["Guitar", "Bass", "Drums", "Track 4", "Lead guitar", "Vocals"],
                "after the last tab or MIDI track, before the audio")
        #expect(added.tab?.barCount == 16, "it spans the song, and the Tab screen writes on it at once")
        #expect(added.undo.undo?.label == "Add track: Track 4")

        let midi = try JSONCoding.decode(Track.self, from: try await session.perform("tracks.add", ["kind": "midi"])["track"]!)
        #expect(midi.name == "MIDI Track 5" && !midi.hasTab && midi.instrument == "Acoustic Grand Piano")
        let audio = try await session.perform("tracks.add", ["kind": "audio"])
        #expect(try JSONCoding.decode(Track.self, from: audio["track"]!).name == "Audio 3")
        let shown = try await eventually(session) { $0.view?.editor == "arrange" }
        #expect(shown.tracks.last?.name == "Audio 3", "an audio track goes last, and the computer shows Arrange")

        let step = try #require(shown.undo.undo)
        #expect(step.label == "Add audio track: Audio 3")
        _ = try await session.perform("edit.undo", ["expect": .string(step.id)])
        let back = try await eventually(session) { !$0.tracks.contains { $0.name == "Audio 3" } }
        #expect(back.tracks.count == 7 && back.undo.redo?.label == "Add audio track: Audio 3")
        await #expect(throws: RemoteError.self) { try await session.perform("tracks.add", ["kind": "bass"]) }
        _ = try await session.perform("tracks.arm", ["track_id": "demo-vocals", "armed": true])
        _ = try await session.perform("transport.record", ["armed_track_ids": ["demo-vocals"]])
        await #expect(throws: RemoteError.self, "not while recording: it would end the take") {
            try await session.perform("tracks.add", ["kind": "audio"])
        }
        _ = try await session.perform("transport.stop")
        await session.stop()
    }

    /// TR39 on the demo computer: a MIDI track chosen in the Tab editor waits
    /// on Tabber Studio's "MIDI part" card until the phone answers it; drums
    /// offer only notation, and a card that is gone is refused.
    @Test func theMidiPartCardWaitsForTheChoice() async throws {
        let session = session(DemoHost())
        let start = try await connected(session)
        #expect(start.view?.part == nil, "Guitar has tab: no part")
        let added = try JSONCoding.decode(Track.self, from: try await session.perform("tracks.add", ["kind": "midi"])["track"]!)
        let card = try await eventually(session) { $0.view?.part?.trackID == added.id }
        #expect(card.view?.part == ViewPart(trackID: added.id, shows: "card", midiTab: true))
        let shown = try await session.perform("view.show_part", ["track_id": .string(added.id), "as": "midi_tab"])
        #expect(try JSONCoding.decode(ViewState.self, from: shown["view"]!).part?.shows == "midi_tab")
        await #expect(throws: RemoteError.self, "the card is gone") {
            try await session.perform("view.show_part", ["track_id": .string(added.id), "as": "notation"])
        }
        _ = try await session.perform("tracks.select", ["track_id": "demo-drums"])
        let drums = try await eventually(session) { $0.view?.part?.trackID == "demo-drums" }
        #expect(drums.view?.part?.midiTab == false)
        await #expect(throws: RemoteError.self, "drums cannot show MIDI tab") {
            try await session.perform("view.show_part", ["track_id": "demo-drums", "as": "midi_tab"])
        }
        _ = try await session.perform("view.show_part", ["track_id": "demo-drums", "as": "notation"])
        _ = try await session.perform("view.set", ["editor": "arrange"])
        let arrange = try await eventually(session) { $0.view?.editor == "arrange" }
        #expect(arrange.view?.part == nil, "Arrange shows no card")
        await session.stop()
    }

    /// TR40 on the demo computer: a MIDI track shown as MIDI tab is written as
    /// tab, while the Tab editor shows it.
    @Test func aMidiTracksMidiTabIsWrittenWhileTheTabEditorShowsIt() async throws {
        let session = session(DemoHost())
        _ = try await connected(session)
        let added = try JSONCoding.decode(Track.self, from: try await session.perform("tracks.add", ["kind": "midi"])["track"]!)
        #expect(try await eventually(session) { $0.view?.part?.trackID == added.id }.tab == nil, "the card first: no tab yet")
        _ = try await session.perform("view.show_part", ["track_id": .string(added.id), "as": "midi_tab"])
        let shown = try await eventually(session) { $0.tab?.trackID == added.id }
        #expect(shown.tab?.isMidiTab == true && shown.tab?.tuning == DemoTab.standard)
        let put = try await session.perform("tab.put", ["string": 2, "fret": 3])
        let tab = try JSONCoding.decode(TabState.self, from: put["tab"]!)
        #expect(tab.cursorBar?.beats.first?.notes == [TabNote(string: 2, fret: 3)])
        _ = try await session.perform("view.set", ["editor": "arrange"])
        let off = try await eventually(session) { $0.view?.editor == "arrange" && $0.tab == nil }
        #expect(off.tab == nil, "no MIDI tab off the Tab editor")
        await #expect(throws: RemoteError.self) { try await session.perform("tab.put", ["string": 1, "fret": 0]) }
        await session.stop()
    }

    /// TR41 on the demo computer: + Bus named as typed, before the master, in
    /// the mixer and the routing, and no undo step.
    @Test func addBusIsNamedAsTypedAndNoUndoStep() async throws {
        let session = session(DemoHost())
        let start = try await connected(session)
        let added = try await session.perform("mixer.add_bus", ["name": " Delay "])
        let strip = try JSONCoding.decode(Strip.self, from: added["strip"]!)
        #expect(strip.name == "Delay" && strip.isBus)
        let after = try await eventually(session) { $0.mixer?.strips.contains { $0.id == strip.id } == true }
        #expect(after.mixer?.strips.last?.isMaster == true, "the new bus comes before the master")
        #expect(after.undo == start.undo, "no undo step")
        _ = try await session.perform("routing.state")
        let routed = try await eventually(session) { $0.routing?.sources.contains { $0.stripID == strip.id } == true }
        #expect(routed.routing != nil)
        await #expect(throws: RemoteError.self) { try await session.perform("mixer.add_bus", ["name": "   "]) }
        await session.stop()
    }

    /// TR44 on the demo computer: the browser's rows, an effect at the end of
    /// a strip's chain, bypassed and removed; an instrument becomes a MIDI
    /// track's sound source and is refused on an audio track; no undo steps.
    @Test func pluginsAreInsertedBypassedAndRemoved() async throws {
        let session = session(DemoHost())
        let start = try await connected(session)
        let page = try JSONCoding.decode(PluginPage.self, from: try await session.perform("plugins.catalog"))
        #expect(page.total == page.plugins.count && page.plugins.first?.name == "Tabber Amp")
        #expect(page.plugins.prefix { $0.tabber }.count == page.plugins.filter(\.tabber).count, "Tabber's own first")
        let second = try JSONCoding.decode(PluginPage.self, from: try await session.perform("plugins.catalog",
                                                                                          ["offset": 2, "limit": 2]))
        #expect(second.offset == 2 && second.plugins.map(\.id) == page.plugins.dropFirst(2).prefix(2).map(\.id))

        _ = try await session.perform("mixer.state")
        let mixer = try await eventually(session) { $0.mixer != nil }.mixer!
        #expect(mixer.strips.first { $0.id == "demo-guitar" }?.inserts.map(\.name) == ["Tabber Amp"])
        let compressor = page.plugins.first { $0.name == "Tabber Compressor" }!
        let added = try await session.perform("plugins.insert", ["strip_id": "demo-vocals", "plugin_id": .string(compressor.id)])
        let vocals = try JSONCoding.decode(Strip.self, from: added["strip"]!)
        #expect(vocals.inserts.map(\.name) == ["Tabber Compressor"] && added["sound_source"]?.boolValue == false)
        let insert = vocals.inserts[0]
        let off = try await session.perform("plugins.bypass", ["strip_id": "demo-vocals", "insert_id": .string(insert.id),
                                                               "bypassed": true])
        #expect(try JSONCoding.decode(Strip.self, from: off["strip"]!).inserts.first?.bypassed == true)
        #expect(try await session.perform("plugins.open", ["strip_id": "demo-vocals", "insert_id": .string(insert.id)]) == [:])
        _ = try await session.perform("plugins.remove", ["strip_id": "demo-vocals", "insert_id": .string(insert.id)])
        let after = try await eventually(session) { $0.mixer?.strips.first { $0.id == "demo-vocals" }?.inserts.isEmpty == true }
        #expect(after.undo == start.undo, "plug-ins are no undo steps")
        await #expect(throws: RemoteError.self) {         // gone: stale_target
            try await session.perform("plugins.remove", ["strip_id": "demo-vocals", "insert_id": .string(insert.id)])
        }

        let synth = page.plugins.first(where: \.isInstrument)!
        let source = try await session.perform("plugins.insert", ["strip_id": "demo-guitar", "plugin_id": .string(synth.id)])
        #expect(source["sound_source"]?.boolValue == true, "an instrument becomes the MIDI track's sound source")
        await #expect(throws: RemoteError.self) {
            try await session.perform("plugins.insert", ["strip_id": "demo-vocals", "plugin_id": .string(synth.id)])
        }
        await session.stop()
    }
}
