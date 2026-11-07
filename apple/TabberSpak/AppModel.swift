import Foundation
import Observation
import RemoteKit

/// The app's one session, on the main actor for SwiftUI.
@MainActor
@Observable
final class AppModel {
    private(set) var state = SessionState()
    /// What the transport bar shows. It changes only when one of these does, so
    /// the bar does not redraw with every playhead update (principle 7).
    private(set) var bar = TransportSummary()

    struct TransportSummary: Equatable {
        var connected = false
        var recording = false
        var playing = false
        var armed: [String] = []
        var hasTake = false
        var hasSession = false
    }
    private(set) var problem: String?
    /// Controls whose command is on its way: they look pending until confirmed (principle 3).
    private(set) var pending: Set<String> = []
    /// The take the newest Stop made: the take card shows it (TR8).
    var lastTake: Take?
    /// Bumped on every confirmed action, for haptics.
    private(set) var feedback: (kind: Feedback, count: Int) = (.tap, 0)
    var keepAwake: Bool = UserDefaults.standard.object(forKey: "keepAwake") as? Bool ?? true {
        didSet { UserDefaults.standard.set(keepAwake, forKey: "keepAwake") }
    }

    enum Feedback: Equatable { case tap, record, stop, goAgain, discard, failure }
    private(set) var isDemo = false
    private(set) var known: KnownHost?
    private var session: RemoteSession?
    private var listener: Task<Void, Never>?

    static let app = AppInfo(version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0",
                             build: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1")

    init() {
        known = HostStore.load()
        if ProcessInfo.processInfo.arguments.contains("-demo") {
            startDemo()
        } else if let known, let signer = try? DeviceKeyStore.loadOrCreate() {
            start(.paired(known, signer), routes: known.routes)
        }
    }

    func startDemo() {
        isDemo = true
        let host = DemoHost()
        attach(RemoteSession(credentials: .demo, app: Self.app) { _ in await host.connect() })
    }

    /// Pair from the QR code's link (scanned, pasted, or `simctl openurl`).
    func pair(with link: PairingLink) async {
        problem = nil
        do {
            let signer = try DeviceKeyStore.loadOrCreate()
            var lastError: Error?
            for route in link.routes {
                let client = RemoteClient(transport: NetworkTransport(route: route, pin: link.pin))
                await client.start()
                do {
                    _ = try await client.sayHello(app: Self.app)
                    _ = try await client.pair(token: link.token, pin: link.pin, device: signer,
                                              name: DeviceName.current, model: DeviceName.model)
                    await client.close()
                    let host = KnownHost(id: link.hostID, name: link.name, pin: link.pin, routes: [route] + link.routes.filter { $0 != route })
                    HostStore.save(host)
                    known = host
                    isDemo = false
                    start(.paired(host, signer), routes: host.routes)
                    return
                } catch {
                    lastError = error
                    await client.close()
                }
            }
            problem = Self.explain(lastError)
        } catch {
            problem = Self.explain(error)
        }
    }

    private func start(_ credentials: RemoteSession.Credentials, routes: [Route]) {
        attach(RemoteSession(credentials: credentials, app: Self.app) { attempt in
            NetworkTransport(route: routes[attempt % max(1, routes.count)], pin: {
                if case .paired(let host, _) = credentials { return host.pin }
                return nil
            }())
        })
    }

    private func attach(_ next: RemoteSession) {
        listener?.cancel()
        if let old = session { Task { await old.stop() } }
        session = next
        listener = Task { [weak self] in
            await next.start()
            for await update in next.updates {
                guard let self else { return }
                self.state = update
                var summary = TransportSummary()
                if case .connected = update.link { summary.connected = true }
                summary.recording = update.record.recording
                summary.playing = update.transport?.state == .playing
                summary.armed = update.tracks.filter(\.armed).map(\.name)
                summary.hasTake = !update.takes.isEmpty
                summary.hasSession = update.transport != nil
                if summary != self.bar { self.bar = summary }
            }
        }
    }

    func forget() {
        HostStore.clear()
        known = nil
        listener?.cancel()
        if let old = session { Task { await old.stop() } }
        session = nil
        state = SessionState()
        bar = TransportSummary()
    }

    var isConnected: Bool { if case .connected = state.link { return true }; return false }

    /// Run a verb for a control: pending until the computer confirms, then a
    /// haptic; a refusal is shown in words (spec 10).
    func act(_ control: String, _ method: String, _ params: JSONValue = [:], feel: Feedback = .tap,
             then: ((JSONValue) -> Void)? = nil) {
        guard let session, !pending.contains(control) else { return }
        pending.insert(control)
        Task {
            do {
                let result = try await session.perform(method, params)
                pending.remove(control)
                problem = nil
                feedback = (feel, feedback.count + 1)
                then?(result)
            } catch {
                pending.remove(control)
                problem = Self.explain(error)
                feedback = (.failure, feedback.count + 1)
            }
        }
    }

    // The take loop (plan: The app, screens 1 and 2)

    var armedIDs: [String] { state.tracks.filter(\.armed).map(\.id) }

    func record() {
        if state.record.recording {
            stop()
        } else if !armedIDs.isEmpty {
            act("record", "transport.record", ["armed_track_ids": .array(armedIDs.map { .string($0) })], feel: .record)
        } else {
            problem = "Arm a track first."
            feedback = (.failure, feedback.count + 1)
        }
    }

    func stop() {
        act("stop", "transport.stop", feel: .stop) { [weak self] result in
            if let take = result["take"], take != .null, let decoded = try? JSONCoding.decode(Take.self, from: take) {
                self?.lastTake = decoded
            }
        }
    }

    func playOrStop() {
        if state.transport?.state == .playing { stop() } else { act("play", "transport.play") }
    }

    func goAgain() {
        guard let take = lastTake ?? state.takes.first else { return }
        lastTake = nil
        act("goagain", "takes.go_again", ["take_id": .string(take.id)], feel: .goAgain)
    }

    /// Run a verb; a refusal is shown in words (spec 10).
    func perform(_ method: String, _ params: JSONValue = [:]) {
        guard let session else { return }
        Task {
            do {
                _ = try await session.perform(method, params)
                problem = nil
            } catch {
                problem = Self.explain(error)
            }
        }
    }

    static func explain(_ error: Error?) -> String {
        switch error {
        case let failure as RemoteError: return failure.message
        case TransportFailure.wrongKey?: return "This is not the computer you paired with."
        case TransportFailure.closed?: return "Tabber Studio closed the connection."
        case .some(let other): return "Could not reach Tabber Studio (\(other.localizedDescription))."
        case nil: return "Could not reach Tabber Studio."
        }
    }
}

/// The paired computer, kept on this phone (no secrets: the key stays in the Keychain).
enum HostStore {
    static let key = "studio.tabber.spak.known-host"
    static func load() -> KnownHost? {
        UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(KnownHost.self, from: $0) }
    }
    static func save(_ host: KnownHost) {
        UserDefaults.standard.set(try? JSONEncoder().encode(host), forKey: key)
    }
    static func clear() { UserDefaults.standard.removeObject(forKey: key) }
}

@MainActor
enum DeviceName {
    static var current: String {
        #if canImport(UIKit)
        return UIDeviceName.name
        #else
        return Host.current().localizedName ?? "Tabber Spak"
        #endif
    }
    static var model: String {
        #if targetEnvironment(simulator)
        return "Simulator"
        #else
        return "iPhone"
        #endif
    }
}

#if canImport(UIKit)
import UIKit
enum UIDeviceName {
    @MainActor static var name: String { UIDevice.current.name }
}
#endif
