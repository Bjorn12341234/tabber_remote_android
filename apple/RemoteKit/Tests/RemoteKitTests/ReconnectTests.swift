import Foundation
import Testing
@testable import RemoteKit

/// TR6: finding the computer again, waking up, and saying what is wrong.
@Suite("Reconnecting and trouble")
struct ReconnectTests {
    static let app = AppInfo(version: "1.0", build: "1")

    func eventually(_ session: RemoteSession, within seconds: Double = 3,
                    _ check: (SessionState) -> Bool) async throws -> SessionState {
        let deadline = ContinuousClock.now + .milliseconds(Int(seconds * 1000))
        while ContinuousClock.now < deadline {
            let state = await session.state
            if check(state) { return state }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("the state never got there")
        return await session.state
    }

    static func isConnected(_ state: SessionState) -> Bool {
        if case .connected = state.link, state.transport != nil { return true }
        return false
    }

    @Test func theRouteBookTriesEachAddressThenBonjour() async {
        let local = Route(host: "Studio.local", port: 9474)
        let wifi = Route(host: "192.168.8.20", port: 9474)
        let moved = Route(host: "192.168.8.31", port: 50211)
        let book = RouteBook(routes: [local, wifi], hostID: "h1") { id in id == "h1" ? moved : nil }
        #expect(await book.route(for: 0) == local)
        #expect(await book.route(for: 1) == wifi)
        #expect(await book.route(for: 2) == moved)        // after a round: where Bonjour says it is now
        #expect(await book.route(for: 3) == local)
        _ = await book.route(for: 2)
        let remembered = await book.connected()
        // The address that worked goes first; the others follow it to the new port.
        #expect(remembered == [moved, Route(host: "Studio.local", port: 50211), Route(host: "192.168.8.20", port: 50211)])
        #expect(await book.connected() == nil)            // nothing new to remember
    }

    @Test func withoutBonjourTheBookFallsBackToTheFirstAddress() async {
        let local = Route(host: "Studio.local", port: 9474)
        let book = RouteBook(routes: [local], hostID: "h1") { _ in nil }
        #expect(await book.route(for: 1) == local)
        #expect(await book.connected() == nil)
    }

    @Test func versionsSayWhichSideToUpdate() {
        #expect(Trouble.versions(["2.0"]) == .updateSpak(hostVersions: ["2.0"]))
        #expect(Trouble.versions(["0.9"]) == .updateStudio(hostVersions: ["0.9"]))
    }

    @Test(arguments: [(["2.0"], Trouble.updateSpak(hostVersions: ["2.0"])),
                      (["0.9"], Trouble.updateStudio(hostVersions: ["0.9"]))])
    func aComputerOfAnotherVersionSaysWhatToUpdate(speaks: [String], trouble: Trouble) async throws {
        let host = DemoHost(speaks: speaks)
        let session = RemoteSession(credentials: .demo, app: Self.app) { _ in await host.connect() }
        await session.start()
        let state = try await eventually(session) { if case .failed = $0.link { return true }; return false }
        #expect(state.link == .failed("unsupported_version"))
        #expect(state.trouble == trouble)
        await session.stop()
    }

    @Test func anUnreachableComputerIsNamedAfterThePatienceRunsOut() async throws {
        let session = RemoteSession(credentials: .demo, app: Self.app) { _ in
            throw TransportFailure.unreachable("nobody listens")
        }
        await session.start()
        try await Task.sleep(for: .seconds(1))
        #expect(await session.state.trouble == nil)       // a short drop is not trouble yet
        let state = try await eventually(session, within: 6) { $0.trouble == .unreachable }
        #expect(state.link == .reconnecting)
        await session.stop()
    }

    @Test func aDeniedLocalNetworkIsNamedAtOnce() async throws {
        let session = RemoteSession(credentials: .demo, app: Self.app) { _ in throw TransportFailure.localNetworkDenied }
        await session.start()
        let state = try await eventually(session, within: 1) { $0.trouble == .localNetworkDenied }
        #expect(state.link == .reconnecting)              // it keeps trying: it may be allowed in Settings
        await session.stop()
    }

    final class Gate: @unchecked Sendable {
        private let lock = NSLock()
        private var open = false
        var isOpen: Bool { lock.withLock { open } }
        func letIn() { lock.withLock { open = true } }
    }

    @Test func wakeTriesAtOnceInsteadOfWaitingOutTheBackoff() async throws {
        let host = DemoHost()
        let gate = Gate()
        let session = RemoteSession(credentials: .demo, app: Self.app) { _ in
            guard gate.isOpen else { throw TransportFailure.unreachable("away") }
            return await host.connect()
        }
        await session.start()
        try await Task.sleep(for: .seconds(2.2))          // four failures: the backoff is now 2 s
        gate.letIn()
        try await Task.sleep(for: .milliseconds(50))
        let woken = ContinuousClock.now
        await session.wake()
        _ = try await eventually(session, within: 1.5, Self.isConnected)
        #expect(ContinuousClock.now - woken < .milliseconds(500))
        #expect(await session.state.trouble == nil)
        await session.stop()
    }

    @Test func wakeRemakesAConnectionThatWentQuiet() async throws {
        let host = DemoHost()
        let session = RemoteSession(credentials: .demo, app: Self.app) { _ in await host.connect() }
        await session.start()
        _ = try await eventually(session, Self.isConnected)
        await host.goSilent()                              // the phone was away; its socket is dead
        try await Task.sleep(for: .seconds(2.8))
        let woken = ContinuousClock.now
        await session.wake()
        try await Task.sleep(for: .milliseconds(20))
        _ = try await eventually(session, within: 2, Self.isConnected)
        #expect(ContinuousClock.now - woken < .seconds(1))  // TR6's target: back within a second
        #expect(await host.connectionsMade == 2)
        await session.stop()
    }
}
