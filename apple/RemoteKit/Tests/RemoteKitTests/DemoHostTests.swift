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
}
