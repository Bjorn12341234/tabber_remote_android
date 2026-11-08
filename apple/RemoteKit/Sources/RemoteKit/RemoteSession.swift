import Foundation

/// A paired computer, as the phone remembers it.
public struct KnownHost: Codable, Sendable, Hashable, Identifiable {
    public var id: String            // host id
    public var name: String
    public var pin: String
    public var routes: [Route]
    public init(id: String, name: String, pin: String, routes: [Route]) {
        self.id = id; self.name = name; self.pin = pin; self.routes = routes
    }
}

/// What the app shows: the computer's confirmed state (principle 3).
public struct SessionState: Sendable, Hashable {
    public var link: LinkState = .idle
    /// Why the computer cannot be used, once that is clear (TR6's fix-it cards).
    public var trouble: Trouble?
    public var host: HostInfo?
    public var capabilities: Set<String> = []
    public var project = ProjectState(title: "", unsaved: false, hasFile: false)
    public var transport: TransportState?
    public var record = RecordState(recording: false, started: nil, armedTrackIDs: [])
    public var tracks: [Track] = []
    public var markers: [Marker] = []
    public var takes: [Take] = []
    public var undo = UndoState(undo: nil, redo: nil)
    public var meters: [String: [Double]] = [:]
    /// Every strip, bus and the master (mixer/1); nil when the computer has no mixer for phones.
    public var mixer: MixerState?
    /// Strip levels while the Mixer is on screen (the mixer_meters topic).
    public var stripMeters: [String: [Double]] = [:]
    /// The selected tab track's bars around the cursor (tab/1); nil when the selected track has no tab.
    public var tab: TabState?
    /// Each track's and bus's output and every send (routing/1); nil when the computer has no routing for phones.
    public var routing: RoutingState?
    /// Tabber Studio's chat (chat/1); nil when the computer has no chat for phones.
    public var chat: ChatState?
    /// What the computer shows (view/1); nil when the computer has no view buttons for phones.
    public var view: ViewState?
    /// The Speed Trainer (trainer/1); nil when the computer has none for phones.
    public var trainer: TrainerState?
    public var seq = 0
    /// The host time of the newest message, and when it arrived here.
    public var hostTime = 0.0
    public var receivedAt = ContinuousClock.now
    /// When the playhead in `transport` was last confirmed, to count on from it.
    public var positionAt = ContinuousClock.now
    public init() {}

    /// The host's clock now, from the newest message (spec 1, host time).
    public var hostNow: Double {
        let gap = ContinuousClock.now - receivedAt
        return hostTime + Double(gap.components.seconds) + Double(gap.components.attoseconds) / 1e18
    }

    /// The playhead's seconds now: counted on locally while playing (spec 8.2).
    public var playheadSeconds: Double {
        guard let transport else { return 0 }
        guard transport.state == .playing else { return transport.position.seconds }
        let gap = ContinuousClock.now - positionAt
        let elapsed = Double(gap.components.seconds) + Double(gap.components.attoseconds) / 1e18
        return transport.position.seconds + min(elapsed, 1.0) * transport.tempoScale
    }

    /// Seconds recorded so far; negative while the count-in runs.
    public var recordedSeconds: Double? {
        guard record.recording, let started = record.started else { return nil }
        return hostNow - started.t
    }
}

/// Keeps one computer connected, applies its events, and resends changes
/// with the same key after a drop (spec 5.1), so Record never records twice.
public actor RemoteSession {
    public typealias Connector = @Sendable (_ attempt: Int) async throws -> any RemoteTransport
    public enum Credentials: Sendable {
        case demo
        case paired(KnownHost, any DeviceSigner)
    }

    public static let reads: Set<String> = ["takes.list", "session.snapshot", "mixer.state", "tab.state", "routing.state",
                                            "chat.state", "view.state", "trainer.state"]
    public static let topics = ["transport", "position", "record", "tracks", "markers", "takes", "undo", "project", "meters"]

    /// The topics to follow on a computer with these capabilities: a 1.0 host
    /// refuses a topic it does not know (spec 7).
    public static func topics(for capabilities: Set<String>) -> [String] {
        var topics = Self.topics
        if capabilities.contains("mixer/1") { topics.append("mixer") }
        if capabilities.contains("tab/1") { topics.append("tab") }
        if capabilities.contains("routing/1") { topics.append("routing") }
        if capabilities.contains("chat/1") { topics.append("chat") }
        if capabilities.contains("view/1") { topics.append("view") }
        if capabilities.contains("trainer/1") { topics.append("trainer") }
        return topics
    }

    /// Topics a screen asked for while it shows (the Mixer's meters), kept across reconnects.
    private var extraTopics: Set<String> = []

    private let credentials: Credentials
    private let connector: Connector
    private let app: AppInfo
    private var client: RemoteClient?
    private var supervisor: Task<Void, Never>?
    /// The wait between reconnect attempts; `wake()` cuts it short.
    private var nap: Task<Void, Never>?
    /// How long reconnecting may fail before the app is told the computer is unreachable.
    public static let patience: Duration = .seconds(4)
    /// How long a dead address may hold up a reconnect (the hello's timeout).
    public static let connectTimeout: Duration = .seconds(3)
    private var connectedWaiters: [CheckedContinuation<Void, Never>] = []
    public private(set) var state = SessionState()
    /// How long each change took to be answered, across reconnects, since the
    /// session started or since `resetResponseTimes()`.
    public private(set) var responseTimes = ResponseTimes()
    private let continuation: AsyncStream<SessionState>.Continuation
    public nonisolated let updates: AsyncStream<SessionState>

    public init(credentials: Credentials, app: AppInfo, connector: @escaping Connector) {
        self.credentials = credentials
        self.app = app
        self.connector = connector
        (updates, continuation) = AsyncStream<SessionState>.makeStream(bufferingPolicy: .bufferingNewest(1))
    }

    public func start() {
        guard supervisor == nil else { return }
        supervisor = Task { [weak self] in await self?.supervise() }
    }

    public func stop() async {
        supervisor?.cancel()
        supervisor = nil
        await client?.close()
        setLink(.idle)
    }

    private func publish() { continuation.yield(state) }

    private func setLink(_ link: LinkState) {
        state.link = link
        publish()
        if case .connected = link {
            for waiter in connectedWaiters { waiter.resume() }
            connectedWaiters.removeAll()
        }
    }

    private func supervise() async {
        var attempt = 0
        var failingSince: ContinuousClock.Instant?
        while !Task.isCancelled {
            setLink(attempt == 0 ? .connecting : .reconnecting)
            do {
                try await connectOnce(attempt: attempt)
                attempt = 0
                failingSince = nil
                await consume()
            } catch let failure as RemoteError where ["unknown_device", "signature_invalid"].contains(failure.reason) {
                fail(failure.reason, .forgotten)
                return
            } catch let failure as RemoteError where failure.reason == "unsupported_version" {
                let versions = failure.data["host_versions"]?.arrayValue?.compactMap(\.stringValue) ?? []
                fail(failure.reason, Trouble.versions(versions))
                return
            } catch TransportFailure.closed(.some(4002)) {
                // No shared major version at all: this phone offers only 1.x, so the
                // computer speaks only newer ones (spec 2).
                fail("unsupported_version", .updateSpak(hostVersions: []))
                return
            } catch TransportFailure.wrongKey {
                fail("wrong_key", .otherComputer)
                return
            } catch TransportFailure.localNetworkDenied {
                failingSince = failingSince ?? .now
                state.trouble = .localNetworkDenied    // keep trying: it may be allowed in Settings
            } catch {
                failingSince = failingSince ?? .now
            }
            guard !Task.isCancelled else { return }
            attempt += 1
            if let since = failingSince, ContinuousClock.now - since >= Self.patience, state.trouble == nil {
                state.trouble = .unreachable
            }
            setLink(.reconnecting)
            let delay = Duration.milliseconds(min(2000, 250 * (1 << min(attempt - 1, 3))))
            let wait = Task { _ = try? await Task.sleep(for: delay) }
            nap = wait
            await wait.value
            nap = nil
        }
    }

    private func fail(_ reason: String, _ trouble: Trouble) {
        state.trouble = trouble
        setLink(.failed(reason))
    }

    /// The app is back on the screen (TR6: reconnected within a second). A
    /// connection that went quiet while the app was away is dropped and made
    /// again at once; a reconnect waiting out its backoff tries now.
    /// Start measuring again, as for a run with AirDrop on after one with it off.
    public func resetResponseTimes() { responseTimes = ResponseTimes() }

    public func wake() async {
        nap?.cancel()
        if case .connected = state.link, client != nil, silentFor() > 2.5 {
            await client?.close()
        }
    }

    private func connectOnce(attempt: Int) async throws {
        let transport = try await connector(attempt)
        let client = RemoteClient(transport: transport)
        await client.start()
        let hello: HelloResult
        do {
            hello = try await client.sayHello(app: app, timeout: Self.connectTimeout)
        } catch {
            await client.close()
            throw error
        }
        switch credentials {
        case .demo:
            let signer = SoftwareSigner()
            _ = try await client.pair(token: Base64URL.encode(Data(count: 16)), pin: Base64URL.encode(Data(count: 32)),
                                      device: signer, name: "Demo iPhone", model: "demo")
        case .paired(let host, let signer):
            _ = try await client.authenticate(pin: host.pin, device: signer)
        }
        let capabilities = Set(hello.capabilities)
        let extra = capabilities.contains("mixer/1") ? extraTopics.sorted() : []
        let snapshot = try await client.subscribe(Self.topics(for: capabilities) + extra)
        self.client = client
        state.host = hello.host
        state.capabilities = capabilities
        apply(snapshot)
        await readExtras(client)
        state.trouble = nil
        setLink(.connected(busy: false))
    }

    private func consume() async {
        guard let client else { return }
        let watchdog = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
                if await self.silentFor() > 6.0 { await client.close(); return }
            }
        }
        defer { watchdog.cancel() }
        for await message in client.incoming {
            switch message {
            case .event(let event):
                if event.seq != state.seq + 1 {
                    await resnapshot()
                } else {
                    state.seq = event.seq
                    apply(event)
                }
            case .heartbeat(let beat):
                state.hostTime = beat.t
                state.receivedAt = .now
                if case .connected(let busy) = state.link, busy != beat.busy { setLink(.connected(busy: beat.busy)) }
                if beat.seq > state.seq { await resnapshot() }
            case .closed:
                self.client = nil
                return
            }
        }
        self.client = nil
    }

    private func silentFor() -> Double {
        let gap = ContinuousClock.now - state.receivedAt
        return Double(gap.components.seconds) + Double(gap.components.attoseconds) / 1e18
    }

    private func resnapshot() async {
        guard let client, let snapshot = try? await client.call("session.snapshot", [:], as: Snapshot.self) else { return }
        apply(snapshot)
        await readExtras(client)
    }

    /// The mixer, the tab and the routing are not in the snapshot: they are
    /// read once, then followed by their topics (spec 7: mixer/1, tab/1, routing/1).
    private func readExtras(_ client: RemoteClient) async {
        if state.capabilities.contains("mixer/1"), let result = try? await client.call("mixer.state", [:]) {
            applyResult(result)
        } else if !state.capabilities.contains("mixer/1") {
            state.mixer = nil
        }
        if state.capabilities.contains("view/1"), let result = try? await client.call("view.state", [:]) {
            applyResult(result)
        } else if !state.capabilities.contains("view/1") {
            state.view = nil
        }
        if state.capabilities.contains("trainer/1"), let result = try? await client.call("trainer.state", [:]) {
            applyResult(result)
        } else if !state.capabilities.contains("trainer/1") {
            state.trainer = nil
        }
        if state.capabilities.contains("chat/1"), let result = try? await client.call("chat.state", [:]) {
            applyResult(result)
        } else if !state.capabilities.contains("chat/1") {
            state.chat = nil
        }
        if state.capabilities.contains("routing/1"), let result = try? await client.call("routing.state", [:]) {
            applyResult(result)
        } else if !state.capabilities.contains("routing/1") {
            state.routing = nil
        }
        if state.capabilities.contains("tab/1"), let result = try? await client.call("tab.state", [:]) {
            applyResult(result)
        } else if !state.capabilities.contains("tab/1") {
            state.tab = nil
        }
    }

    /// Follow a topic while a screen shows it (the Mixer's meters), or stop.
    public func watch(_ topic: String, _ on: Bool) async {
        if on { extraTopics.insert(topic) } else { extraTopics.remove(topic) }
        if !on, topic == "mixer_meters" { state.stripMeters = [:]; publish() }
        guard let client, state.capabilities.contains("mixer/1") else { return }
        if on {
            if let snapshot = try? await client.call("session.subscribe", ["topics": [.string(topic)]], as: Snapshot.self) {
                apply(snapshot)
            }
        } else {
            _ = try? await client.call("session.unsubscribe", ["topics": [.string(topic)]])
        }
    }

    private func apply(_ snapshot: Snapshot) {
        state.seq = snapshot.seq
        state.hostTime = snapshot.t
        state.receivedAt = .now
        state.project = snapshot.project
        state.transport = snapshot.transport
        state.positionAt = .now
        state.record = snapshot.record
        state.tracks = snapshot.tracks
        state.markers = snapshot.markers
        state.takes = snapshot.takes
        state.undo = snapshot.undo
        publish()
    }

    private func apply(_ event: Event) {
        state.hostTime = event.t
        state.receivedAt = .now
        let data = event.data
        switch event.topic {
        case "transport":
            if let v = try? JSONCoding.decode(TransportState.self, from: data) { state.transport = v; state.positionAt = .now }
        case "position":
            if let p = data["position"], let v = try? JSONCoding.decode(Position.self, from: p),
               let s = data["state"]?.stringValue, let play = PlayState(rawValue: s) {
                state.transport?.position = v
                state.transport?.state = play
                state.positionAt = .now
            }
        case "record": if let v = try? JSONCoding.decode(RecordState.self, from: data) { state.record = v }
        case "tracks": if let v = try? JSONCoding.decode([Track].self, from: data["tracks"] ?? []) { state.tracks = v }
        case "markers": if let v = try? JSONCoding.decode([Marker].self, from: data["markers"] ?? []) { state.markers = v }
        case "takes": if let v = try? JSONCoding.decode([Take].self, from: data["takes"] ?? []) { state.takes = v }
        case "undo": if let v = try? JSONCoding.decode(UndoState.self, from: data) { state.undo = v }
        case "project": if let v = try? JSONCoding.decode(ProjectState.self, from: data) { state.project = v }
        case "meters":
            if let levels = try? JSONCoding.decode([MeterLevel].self, from: data["levels"] ?? []) {
                state.meters = Dictionary(levels.map { ($0.trackID, $0.peak) }, uniquingKeysWith: { _, b in b })
            }
        case "mixer": if let v = try? JSONCoding.decode(MixerState.self, from: data) { state.mixer = v }
        case "mixer_meters":
            if let levels = try? JSONCoding.decode([StripLevel].self, from: data["levels"] ?? []) {
                state.stripMeters = Dictionary(levels.map { ($0.stripID, $0.peak) }, uniquingKeysWith: { _, b in b })
            }
        case "tab":
            if let value = data["tab"] { state.tab = value == .null ? nil : try? JSONCoding.decode(TabState.self, from: value) }
        case "routing": if let v = try? JSONCoding.decode(RoutingState.self, from: data) { state.routing = v }
        case "chat": if let v = try? JSONCoding.decode(ChatState.self, from: data) { state.chat = v }
        case "view": if let v = try? JSONCoding.decode(ViewState.self, from: data) { state.view = v }
        case "trainer": if let v = try? JSONCoding.decode(TrainerState.self, from: data) { state.trainer = v }
        default: break
        }
        publish()
    }

    /// Apply the confirmed state a verb returned (spec 5.3).
    private func applyResult(_ result: JSONValue) {
        if let v = result["transport"], let t = try? JSONCoding.decode(TransportState.self, from: v) {
            state.transport = t
            state.positionAt = .now
        }
        if let v = result["record"], let r = try? JSONCoding.decode(RecordState.self, from: v) { state.record = r }
        if let v = result["tracks"], let t = try? JSONCoding.decode([Track].self, from: v) { state.tracks = t }
        if let v = result["markers"], let m = try? JSONCoding.decode([Marker].self, from: v) { state.markers = m }
        if let v = result["undo"], let u = try? JSONCoding.decode(UndoState.self, from: v) { state.undo = u }
        if let v = result["project"], let p = try? JSONCoding.decode(ProjectState.self, from: v) { state.project = p }
        if let v = result["mixer"], let m = try? JSONCoding.decode(MixerState.self, from: v) { state.mixer = m }
        if let v = result["strip"], let strip = try? JSONCoding.decode(Strip.self, from: v),
           let index = state.mixer?.strips.firstIndex(where: { $0.id == strip.id }) {
            state.mixer?.strips[index] = strip
        }
        if let v = result["tab"] { state.tab = v == .null ? nil : try? JSONCoding.decode(TabState.self, from: v) }
        if let v = result["routing"], let r = try? JSONCoding.decode(RoutingState.self, from: v) { state.routing = r }
        if let v = result["chat"], let c = try? JSONCoding.decode(ChatState.self, from: v) { state.chat = c }
        if let v = result["view"], let w = try? JSONCoding.decode(ViewState.self, from: v) { state.view = w }
        if let v = result["trainer"], let t = try? JSONCoding.decode(TrainerState.self, from: v) { state.trainer = t }
        publish()
    }

    private func waitForConnection(timeout: Duration) async -> Bool {
        if case .connected = state.link, client != nil { return true }
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if case .connected = state.link, client != nil { return true }
            if case .failed = state.link { return false }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return false
    }

    /// Run a verb on the computer. A change gets a key once, and is resent with
    /// it after a drop until the computer answers or `patience` runs out.
    public func perform(_ method: String, _ params: JSONValue = [:], patience: Duration = .seconds(10)) async throws -> JSONValue {
        var params = params
        if !Self.reads.contains(method), params["key"] == nil, case .object(var fields) = params {
            fields["key"] = .string(UUID().uuidString.lowercased())
            params = .object(fields)
        }
        let deadline = ContinuousClock.now + patience
        while true {
            guard await waitForConnection(timeout: deadline - .now), let client else {
                throw TransportFailure.unreachable("Tabber Studio is not connected.")
            }
            do {
                let sent = ContinuousClock.now
                let result = try await client.call(method, params)
                applyResult(result)
                if ResponseTimes.counts(method) { responseTimes.add(.now - sent) }
                return result
            } catch let failure as RemoteError {
                throw failure
            } catch {
                if ContinuousClock.now >= deadline { throw error }
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }
}
