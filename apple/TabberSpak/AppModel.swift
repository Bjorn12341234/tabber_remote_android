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
        /// The readout's bar and beat, the moment the take's time started, and a running count-in.
        var position: BarBeat?
        var recordingSince: Date?
        var countingIn = false
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
    /// The scanner sheet; the Computer sheet and the fix-it cards open it too.
    var scanning = false
    /// The Computer sheet, opened from the computer's name at the top of each screen.
    var showingComputer = false
    /// Go to: the start or a marker, from the transport's position.
    var choosingPlace = false
    /// The screen on show; `-screen tab` opens another one (screenshots, tests).
    enum Screen: String, Hashable { case tracks, tab, mixer, tuner, chat }
    var screen: Screen = ProcessInfo.processInfo.arguments.firstIndex(of: "-screen")
        .flatMap { index in ProcessInfo.processInfo.arguments.dropFirst(index + 1).first }
        .flatMap(Screen.init(rawValue:)) ?? .tracks
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
        if arguments.contains("-reset") || arguments.contains("-reset-input") {
            UserDefaults.standard.removeObject(forKey: "tabInput")     // the Tab screen opens on the fretboard
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

    private var demoSpeaks = RemoteClient.protocolVersions

    func startDemo(speaks: [String] = RemoteClient.protocolVersions) {
        isDemo = true
        demoSpeaks = speaks
        book = nil
        // Screenshots: `-demo-name "Björn's Mac Studio"` names the demo computer as a real one is named.
        let arguments = ProcessInfo.processInfo.arguments
        let name = arguments.firstIndex(of: "-demo-name").flatMap { arguments.dropFirst($0 + 1).first } ?? DemoHost.name
        let host = DemoHost(speaks: speaks, computerName: name)
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
            // Every address in the code at once; the first to answer pairs.
            let book = RouteBook(routes: link.routes, hostID: link.hostID)
            let client = RemoteClient(transport: RacingTransport(routes: link.routes,
                                                                 make: { NetworkTransport(route: $0, pin: link.pin) },
                                                                 onWinner: { await book.use($0) }))
            await client.start()
            var lastError: Error?
            do {
                _ = try await client.sayHello(app: Self.app, timeout: .seconds(6))
                _ = try await client.pair(token: link.token, pin: link.pin, device: signer,
                                          name: DeviceName.current, model: DeviceName.model)
                await client.close()
                let routes = await book.connected() ?? link.routes
                let host = KnownHost(id: link.hostID, name: link.name, pin: link.pin, routes: routes)
                HostStore.save(host)
                known = host
                isDemo = false
                pairing = .idle
                start(host, signer)
                return
            } catch {
                lastError = error
                await client.close()
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
        default: return "Can't reach \(name). Check that this iPhone is on the same Wi-Fi as the computer, or that Tailscale is on, on both, and that Tabber Studio is open, then scan again."
        }
    }

    private func start(_ host: KnownHost, _ signer: any DeviceSigner) {
        let book = RouteBook(routes: host.routes, hostID: host.id)
        self.book = book
        let pin = host.pin
        // Every remembered address at once, so away from the Wi-Fi the phone
        // reaches the computer's Tailscale address without waiting out the
        // local ones first; the one that answers is remembered first.
        attach(RemoteSession(credentials: .paired(host, signer), app: Self.app) { attempt in
            RacingTransport(routes: await book.candidates(for: attempt),
                            make: { NetworkTransport(route: $0, pin: pin) },
                            onWinner: { await book.use($0) })
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
                // While recording the readout shows the take's time, so the bar
                // and beat stay out of the summary: the transport holds still.
                summary.position = update.record.recording ? nil : update.transport?.position.barBeat
                if let seconds = update.recordedSeconds {
                    if seconds >= 0 {
                        let since = Date.now.addingTimeInterval(-seconds)
                        if let kept = self.bar.recordingSince, abs(kept.timeIntervalSince(since)) < 0.5 {
                            summary.recordingSince = kept       // steady, so the timer text never jumps
                        } else {
                            summary.recordingSince = since
                        }
                    } else {
                        summary.countingIn = true
                    }
                }
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

    /// How long the computer took to answer this phone's taps (the Computer sheet; TR7's gate).
    func responseTimes() async -> ResponseTimes {
        guard let session else { return ResponseTimes() }
        return await session.responseTimes
    }

    /// Measure from now on, as for a run with AirDrop on after one with it off.
    func startResponseTimesAgain() async {
        await session?.resetResponseTimes()
    }

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
            problem = "Arm a track first: tap ○ on the track you want to record on."
            feedback = (.failure, feedback.count + 1)
        }
    }

    func clearProblem() { problem = nil }

    /// Once: Tabber Spak is a remote, so Play is heard on the computer (the
    /// owner, 2026-11-07: "no sound in the app when I press play").
    private func tellWhereSoundPlays() {
        let key = "toldWhereSoundPlays"
        guard !isDemo, !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        problem = "The sound plays on \(computerName), not on this iPhone."
    }

    func stop() {
        act("stop", "transport.stop", feel: .stop) { [weak self] result in
            if let take = result["take"], take != .null, let decoded = try? JSONCoding.decode(Take.self, from: take) {
                self?.lastTake = decoded
            }
        }
    }

    func playOrStop() {
        if state.transport?.state == .playing {
            stop()
        } else {
            act("play", "transport.play") { [weak self] _ in self?.tellWhereSoundPlays() }
        }
    }

    /// After a discard: Undo for five seconds, naming the step it undoes (spec 9).
    private(set) var undoOffer: UndoOffer?

    struct UndoOffer: Equatable {
        var stepID: String
        var text: String
        var until: Date
    }

    func keep() { lastTake = nil }

    /// Delete a take: one tap, then Undo for five seconds. Tabber Studio keeps
    /// the audio file, so Undo there or here brings the take back (spec 9).
    func delete(_ take: Take) {
        act("delete-\(take.id)", "takes.discard", ["take_id": .string(take.id)], feel: .discard) { [weak self] result in
            guard let self else { return }
            if self.lastTake?.id == take.id { self.lastTake = nil }
            if let step = result["undo"]?["undo"]?["id"]?.stringValue {
                let offer = UndoOffer(stepID: step, text: "\(take.name) deleted", until: .now + 5)
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

    // Tracks (the Tracks screen: choose, arm, listen alone, mute)

    var mixerAvailable: Bool { state.capabilities.contains("mixer/1") }
    var tabAvailable: Bool { state.capabilities.contains("tab/1") }

    func select(_ track: Track) {
        guard !track.selected else { return }
        act("select-\(track.id)", "tracks.select", ["track_id": .string(track.id)])
    }

    func arm(_ track: Track) {
        act("arm-\(track.id)", "tracks.arm", ["track_id": .string(track.id), "armed": .bool(!track.armed)])
    }

    func strip(_ id: String) -> Strip? { state.mixer?.strips.first { $0.id == id } }

    func solo(_ id: String) {
        act("solo-\(id)", "mixer.set_solo", ["strip_id": .string(id), "soloed": .bool(!(strip(id)?.soloed ?? false))])
    }

    func mute(_ id: String) {
        act("mute-\(id)", "mixer.set_mute", ["strip_id": .string(id), "muted": .bool(!(strip(id)?.muted ?? false))])
    }

    /// Whether a strip is heard now: not muted, and soloed if anything is.
    func audible(_ id: String) -> Bool {
        guard let mixer = state.mixer, let strip = strip(id) else { return true }
        let soloing = mixer.strips.contains { $0.soloed }
        return !strip.muted && (!soloing || strip.soloed)
    }

    // Faders and pan: the newest value wins; at most one change in flight, so a
    // drag stays inside the computer's rate limit (spec 6: 20 a second).
    private var wanted: [String: (method: String, params: JSONValue)] = [:]
    private var draining = false

    func setVolume(_ id: String, _ volume: Double) {
        send("volume-\(id)", "mixer.set_volume", ["strip_id": .string(id), "volume": .number((volume * 1000).rounded() / 1000)])
    }

    func setPan(_ id: String, _ pan: Double) {
        send("pan-\(id)", "mixer.set_pan", ["strip_id": .string(id), "pan": .number((pan * 1000).rounded() / 1000)])
    }

    private func send(_ key: String, _ method: String, _ params: JSONValue) {
        wanted[key] = (method, params)
        guard !draining, let session else { return }
        draining = true
        Task {
            while let key = wanted.keys.first, let next = wanted.removeValue(forKey: key) {
                _ = try? await session.perform(next.method, next.params, patience: .seconds(2))
                try? await Task.sleep(for: .milliseconds(60))
            }
            draining = false
        }
    }

    // The computer's view (view/1): Studio's own Arrange, Tab, Piano Roll and Split.

    var viewAvailable: Bool { state.capabilities.contains("view/1") }

    func showEditor(_ editor: String) {
        act("view-\(editor)", "view.set", ["editor": .string(editor)])
    }

    func toggleSplit() {
        act("view-split", "view.set", ["split": .bool(!(state.view?.split ?? false))])
    }

    /// Tabber Studio's Speed Trainer, on a computer that offers it to phones (trainer/1).
    var trainerAvailable: Bool { state.capabilities.contains("trainer/1") }

    /// The Trainer button, as in Tabber Studio's transport bar (S6: loop the
    /// solo at 70% and step the speed up).
    func toggleTrainer() {
        act("trainer", "trainer.set", ["enabled": .bool(!(state.trainer?.enabled ?? false))])
    }

    /// One of the trainer's fields: "start", "step" or "target", in percent.
    /// A changed field starts the ramp again from the start, as in Studio.
    func setTrainer(_ field: String, _ percent: Int) {
        act("trainer-\(field)", "trainer.set", [field: .number(Double(percent))])
    }

    /// One step of a held Previous or Next (the owner: "pressing and holding
    /// previous and next in tab ... should fast forward"): the next beat
    /// written, or once held a while the next bar, adding none. False at the
    /// song's first or last beat, which ends the hold.
    func fastStep(by: Int, bars: Bool) async -> Bool {
        guard let session, let tab = state.tab,
              let target = bars ? tab.barStep(by) : tab.neighbour(by) else { return false }
        do {
            _ = try await session.perform("tab.set_cursor", ["bar": .number(Double(target.bar)),
                                                              "beat": .number(Double(target.beat)),
                                                              "string": .number(Double(target.string))],
                                          patience: .seconds(2))
            return true
        } catch {
            problem = Self.explain(error)
            return false
        }
    }

    // Chat (chat/1): words to the computer's chat, a plan back, Execute to run it.

    var chatAvailable: Bool { state.capabilities.contains("chat/1") }

    func chatSend(_ text: String) {
        act("chat-send", "chat.send", ["text": .string(String(text.prefix(2000)))])
    }

    func chatConfirm(_ plan: ChatPlan) {
        act("chat-execute", "chat.confirm", ["plan_id": .string(plan.id)], feel: .goAgain)
    }

    func chatCancel(_ plan: ChatPlan) {
        act("chat-cancel", "chat.cancel", ["plan_id": .string(plan.id)])
    }

    func chatStop() { act("chat-stop", "chat.stop") }

    // Routing (the Mixer's Routing view, routing/1)

    var routingAvailable: Bool { state.capabilities.contains("routing/1") }

    /// Where a track's or bus's sound goes: one undo step on the computer.
    func setOutput(_ source: RoutingSource, to output: String) {
        guard output != source.output else { return }
        act("output-\(source.stripID)", "routing.set_output",
            ["strip_id": .string(source.stripID), "output": .string(output)])
    }

    /// A new send, at Tabber Studio's -6 dB: an undo step.
    func addSend(from track: String, to bus: String) {
        act("send-\(track)>\(bus)", "routing.set_send", ["strip_id": .string(track), "bus_id": .string(bus)])
    }

    /// A send's level: no undo step, as the mixer's send controls; the newest value only.
    func setSendLevel(_ send: RoutingSend, _ level: Double) {
        self.send("sendlevel-\(send.id)", "routing.set_send",
                  ["strip_id": .string(send.stripID), "bus_id": .string(send.busID),
                   "level": .number((max(0, min(1, level)) * 10000).rounded() / 10000)])
    }

    func setPreFader(_ send: RoutingSend, _ on: Bool) {
        act("pre-\(send.id)", "routing.set_send",
            ["strip_id": .string(send.stripID), "bus_id": .string(send.busID), "pre_fader": .bool(on)])
    }

    func removeSend(_ send: RoutingSend) {
        act("remove-\(send.id)", "routing.remove_send", ["strip_id": .string(send.stripID), "bus_id": .string(send.busID)])
    }

    /// The Mixer's meters, only while it is on screen (plan: TR25).
    func watchMixerMeters(_ on: Bool) {
        guard let session else { return }
        Task { await session.watch("mixer_meters", on) }
    }

    // Tab (the Tab screen): edits go one after another, in the order tapped.
    private var edits: [(method: String, params: JSONValue)] = []
    private var editing = false

    func tab(_ method: String, _ params: JSONValue = [:]) {
        edits.append((method, params))
        guard !editing, let session else { return }
        editing = true
        Task {
            while !edits.isEmpty {
                let next = edits.removeFirst()
                do {
                    _ = try await session.perform(next.method, next.params)
                    problem = nil
                } catch {
                    problem = Self.explain(error)
                    feedback = (.failure, feedback.count + 1)
                    edits.removeAll()
                }
            }
            editing = false
        }
    }

    /// Undo the computer's newest step, naming it so nothing else is undone (spec 9).
    func undo() {
        guard let step = state.undo.undo else { return }
        act("undo", "edit.undo", ["expect": .string(step.id)], feel: .goAgain)
    }

    // The transport's toggles and Go to

    func toggleLoop() {
        guard let transport = state.transport else { return }
        act("loop", "transport.set_loop", ["enabled": .bool(!transport.loop.enabled)])
    }

    func toggleCountIn() {
        guard let transport = state.transport else { return }
        let on = transport.countInBars == 0
        act("count-in", "transport.set_count_in", ["bars": .number(on ? 1 : 0)]) { [weak self] _ in
            if on { self?.tellCountInIsForRecording() }
        }
    }

    /// Once: Count-in is Tabber Studio's recording count-in, so Play starts at
    /// once (the owner, 2026-11-08: "no difference when pressing count in and
    /// then play"; asked, the owner kept it for recording).
    private func tellCountInIsForRecording() {
        let key = "toldCountInIsForRecording"
        guard !isDemo, !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        problem = "Count-in counts one bar in before recording (●). Play starts at once, as in Tabber Studio."
    }

    func toggleClick() {
        guard let transport = state.transport else { return }
        act("click", "transport.set_click", ["enabled": .bool(!transport.click)])
    }

    func go(to marker: Marker) {
        act("goto", "markers.go", ["marker_id": .string(marker.id)])
    }

    func goToStart() {
        act("goto", "transport.seek", ["to": ["bar": 1, "beat": 1]])
    }

    /// Stop, and when already stopped, back to the start, as a DAW's Stop does.
    func stopButton() {
        if state.record.recording || state.transport?.state == .playing { stop() } else { goToStart() }
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
        case let failure as RemoteError where failure.reason == "routing_loop":
            let path = failure.data["path"]?.arrayValue?.compactMap(\.stringValue) ?? []
            return path.isEmpty ? failure.message : "\(failure.message) \(path.joined(separator: " → "))."
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
