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
    /// The paired computer's addresses, and Bonjour when they all fail (TR6).
    private var book: RouteBook?

    /// Pairing from a scanned code: what the phone is doing, or why it stopped.
    enum Pairing: Equatable { case idle, working(String), failed(String) }
    private(set) var pairing: Pairing = .idle
    /// The scanner sheet; the Computer tab and the fix-it cards open it too.
    var scanning = false
    /// The computer the scanner's hint names, when known.
    var scanTarget: String?
    /// Whether the explainer before the Local Network prompt was shown (plan: Find your Mac).
    var explainedLocalNetwork: Bool = UserDefaults.standard.bool(forKey: "explainedLocalNetwork") {
        didSet { UserDefaults.standard.set(explainedLocalNetwork, forKey: "explainedLocalNetwork") }
    }

    static let app = AppInfo(version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0",
                             build: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1")

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        // UI tests: `-reset` is a fresh install; `-known-host <json>` a phone paired
        // with that computer; `-demo-speaks 2.0` a demo computer of another version.
        if arguments.contains("-reset") {
            HostStore.clear()
            explainedLocalNetwork = false
        }
        if let index = arguments.firstIndex(of: "-known-host"), index + 1 < arguments.count,
           let host = try? JSONDecoder().decode(KnownHost.self, from: Data(arguments[index + 1].utf8)) {
            HostStore.save(host)
        }
        known = HostStore.load()
        // Scripts: `-pair-link <link>` pairs at launch, as a scanned code does
        // (`simctl openurl` now stops at iOS's "Open in Tabber Spak?").
        if let index = arguments.firstIndex(of: "-pair-link"), index + 1 < arguments.count,
           let link = PairingLink(string: arguments[index + 1]) {
            Task { await self.pair(with: link) }
            return
        }
        if arguments.contains("-demo") {
            startDemo()
        } else if let index = arguments.firstIndex(of: "-demo-speaks"), index + 1 < arguments.count {
            startDemo(speaks: [arguments[index + 1]])
        } else if let known, let signer = try? DeviceKeyStore.loadOrCreate() {
            start(known, signer)
        }
    }

    private var demoSpeaks = ["1.0"]

    func startDemo(speaks: [String] = ["1.0"]) {
        isDemo = true
        demoSpeaks = speaks
        book = nil
        let host = DemoHost(speaks: speaks)
        attach(RemoteSession(credentials: .demo, app: Self.app) { _ in await host.connect() })
    }

    /// Start over after a stop (the Update cards' Try Again).
    func retry() {
        if isDemo {
            startDemo(speaks: demoSpeaks)
        } else if let known, let signer = try? DeviceKeyStore.loadOrCreate() {
            start(known, signer)
        }
    }

    /// Back on the screen: reconnect at once if the line went quiet (TR6, under a second).
    func wake() {
        guard let session else { return }
        Task { await session.wake() }
    }

    /// Pair from the QR code's link (scanned, pasted, or `simctl openurl`).
    func pair(with link: PairingLink) async {
        problem = nil
        pairing = .working(link.name)
        do {
            let signer = try DeviceKeyStore.loadOrCreate()
            var lastError: Error?
            for route in link.routes {
                let client = RemoteClient(transport: NetworkTransport(route: route, pin: link.pin))
                await client.start()
                do {
                    _ = try await client.sayHello(app: Self.app, timeout: .seconds(4))
                    _ = try await client.pair(token: link.token, pin: link.pin, device: signer,
                                              name: DeviceName.current, model: DeviceName.model)
                    await client.close()
                    let host = KnownHost(id: link.hostID, name: link.name, pin: link.pin, routes: [route] + link.routes.filter { $0 != route })
                    HostStore.save(host)
                    known = host
                    isDemo = false
                    pairing = .idle
                    start(host, signer)
                    return
                } catch let refusal as RemoteError {
                    await client.close()
                    lastError = refusal
                    break                   // the computer answered: another address would say the same
                } catch {
                    lastError = error
                    await client.close()
                }
            }
            pairing = .failed(Self.explainPairing(lastError, name: link.name))
        } catch {
            pairing = .failed(Self.explainPairing(error, name: link.name))
        }
    }

    func clearPairing() { pairing = .idle }

    /// A pairing that did not work, in words that say what to do (spec 10).
    static func explainPairing(_ error: Error?, name: String) -> String {
        switch error {
        case let refusal as RemoteError: return refusal.message
        case TransportFailure.wrongKey?: return "The computer that answered is not the one that showed this code. Scan the code again."
        case TransportFailure.localNetworkDenied?: return "Tabber Spak may not use the local network. Turn on Local Network in Settings › Tabber Spak, then scan again."
        case TransportFailure.closed(.some(4002))?: return "\(name) runs a newer Tabber Studio. Update Tabber Spak, then scan again."
        default: return "Can't reach \(name). Check that this iPhone is on the same Wi-Fi as the computer and that Tabber Studio is open, then scan again."
        }
    }

    private func start(_ host: KnownHost, _ signer: any DeviceSigner) {
        let book = RouteBook(routes: host.routes, hostID: host.id)
        self.book = book
        let pin = host.pin
        attach(RemoteSession(credentials: .paired(host, signer), app: Self.app) { attempt in
            NetworkTransport(route: await book.route(for: attempt), pin: pin)
        })
    }

    /// The address that connected goes first; a computer that moved is found there next time.
    private func remember(_ book: RouteBook) async {
        guard let routes = await book.connected(), var host = known, self.book === book else { return }
        host.routes = routes
        known = host
        HostStore.save(host)
    }

    private func attach(_ next: RemoteSession) {
        listener?.cancel()
        if let old = session { Task { await old.stop() } }
        session = next
        listener = Task { [weak self] in
            await next.start()
            var wasConnected = false
            for await update in next.updates {
                guard let self else { return }
                if case .connected = update.link {
                    if !wasConnected, let book = self.book { await self.remember(book) }
                    wasConnected = true
                } else {
                    wasConnected = false
                }
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

    /// Back from the demo to the paired computer, if there is one.
    func leaveDemo() {
        isDemo = false
        listener?.cancel()
        if let old = session { Task { await old.stop() } }
        session = nil
        state = SessionState()
        bar = TransportSummary()
        if let known, let signer = try? DeviceKeyStore.loadOrCreate() { start(known, signer) }
    }

    func forget() {
        HostStore.clear()
        known = nil
        isDemo = false
        book = nil
        listener?.cancel()
        if let old = session { Task { await old.stop() } }
        session = nil
        state = SessionState()
        bar = TransportSummary()
    }

    var isConnected: Bool { if case .connected = state.link { return true }; return false }

    /// The computer's name for the screen: as it says, as remembered, or in general words.
    var computerName: String { state.host?.name ?? known?.name ?? (isDemo ? DemoHost.name : "your computer") }

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
        lastTake = nil                       // recording again keeps the take
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

    /// After a discard: Undo for five seconds, naming the step it undoes (spec 9).
    private(set) var undoOffer: UndoOffer?

    struct UndoOffer: Equatable {
        var stepID: String
        var text: String
        var until: Date
    }

    func keep() { lastTake = nil }

    func discard(_ take: Take) {
        act("discard", "takes.discard", ["take_id": .string(take.id)], feel: .discard) { [weak self] result in
            guard let self else { return }
            self.lastTake = nil
            if let step = result["undo"]?["undo"]?["id"]?.stringValue {
                let offer = UndoOffer(stepID: step, text: "\(take.name) discarded", until: .now + 5)
                self.undoOffer = offer
                Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .seconds(5))
                    if self?.undoOffer == offer { self?.undoOffer = nil }
                }
            }
        }
    }

    func undoDiscard() {
        guard let offer = undoOffer else { return }
        undoOffer = nil
        act("undo", "edit.undo", ["expect": .string(offer.stepID)], feel: .goAgain)
    }

    func rate(_ take: Take, _ rating: Int) {
        act("rate-\(take.id)", "takes.rate", ["take_id": .string(take.id), "rating": .number(Double(rating))])
    }

    /// Flag a moment: a marker at the bar the phone shows now (spec 9: never "wherever the playhead is").
    func flag() {
        guard let position = state.transport?.position else { return }
        act("flag", "markers.add", ["at": ["bar": .number(Double(position.bar)), "beat": 1], "name": "Flag"])
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
