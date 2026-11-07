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
        #expect(state.tracks.map(\.name) == ["Vocals", "Guitar", "Keys"])
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
            #expect(failure.data["tracks"]?.arrayValue?.count == 3)
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
}
