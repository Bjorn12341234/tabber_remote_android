import Foundation
import Testing
@testable import RemoteKit

/// Every address at once: away from the Wi-Fi the local addresses go
/// nowhere, and the phone must not wait them out before the one that works.
@Suite("Racing addresses")
struct RaceTests {
    static let app = AppInfo(version: "1.0", build: "1")
    static let local = Route(host: "192.168.0.69", port: 9474)
    static let tailscale = Route(host: "100.114.215.101", port: 9474)

    /// An address that fails at once, as iOS reports it.
    struct Failing: RemoteTransport {
        let failure: TransportFailure
        func send(_ text: String) async throws { throw failure }
        func receive() async throws -> String? { throw failure }
        func close() async {}
        func closeCode() async -> Int? { nil }
    }

    actor Winner {
        var route: Route?
        func set(_ route: Route) { self.route = route }
    }

    @Test func theFirstAddressToAnswerIsTheConnection() async throws {
        let live = await DemoHost().connect()
        let (dead, _) = MemoryTransport.pair()                     // nobody answers there
        let winner = Winner()
        let race = RacingTransport(routes: [Self.local, Self.tailscale],
                                   make: { $0 == Self.local ? dead as any RemoteTransport : live },
                                   onWinner: { await winner.set($0) })
        let client = RemoteClient(transport: race)
        await client.start()
        let hello = try await client.sayHello(app: Self.app, timeout: .seconds(2))
        #expect(hello.protocolVersion == RemoteClient.protocolVersions[0], "the demo answers")
        #expect(await winner.route == Self.tailscale, "the address that answered is remembered")
    }

    @Test func aWrongKeyAtOneAddressDoesNotStopAnother() async throws {
        let live = await DemoHost().connect()
        let race = RacingTransport(routes: [Self.local, Self.tailscale],
                                   make: { $0 == Self.local ? Failing(failure: .wrongKey) as any RemoteTransport : live })
        let client = RemoteClient(transport: race)
        await client.start()
        let hello = try await client.sayHello(app: Self.app, timeout: .seconds(2))
        #expect(hello.protocolVersion == RemoteClient.protocolVersions[0], "the demo answers")
    }

    @Test func whenEveryAddressFailsTheMostTellingFailureIsReported() async throws {
        let race = RacingTransport(routes: [Self.local, Self.tailscale],
                                   make: { $0 == Self.local ? Failing(failure: .wrongKey) : Failing(failure: .localNetworkDenied) })
        try await race.send("{}")
        await #expect(throws: TransportFailure.localNetworkDenied) { _ = try await race.receive() }
        #expect(Race.telling([TransportFailure.wrongKey, TransportFailure.unreachable("x")]) as? TransportFailure
                == .unreachable("x"), "a wrong key is reported only when nothing else failed")
        await #expect(throws: TransportFailure.self) {
            _ = try await RacingTransport(routes: [], make: { _ in Failing(failure: .wrongKey) }).receive()
        }
    }

    @Test func aSessionConnectsThroughADeadAddress() async throws {
        let host = DemoHost()
        let session = RemoteSession(credentials: .demo, app: Self.app) { _ in
            let (dead, _) = MemoryTransport.pair()
            let live = await host.connect()
            return RacingTransport(routes: [Self.local, Self.tailscale], make: { $0 == Self.local ? dead as any RemoteTransport : live })
        }
        await session.start()
        let started = ContinuousClock.now
        for _ in 0..<200 {
            if case .connected = await session.state.link { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        guard case .connected = await session.state.link else {
            Issue.record("never connected")
            return
        }
        #expect(ContinuousClock.now - started < .seconds(1), "without waiting out the dead address")
    }
}
