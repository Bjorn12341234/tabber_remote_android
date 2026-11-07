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

    public static let reads: Set<String> = ["takes.list", "session.snapshot"]
    public static let topics = ["transport", "position", "record", "tracks", "markers", "takes", "undo", "project", "meters"]

    private let credentials: Credentials
    private let connector: Connector
    private let app: AppInfo
    private var client: RemoteClient?
    private var supervisor: Task<Void, Never>?
    private var connectedWaiters: [CheckedContinuation<Void, Never>] = []
    public private(set) var state = SessionState()
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
        while !Task.isCancelled {
            setLink(attempt == 0 ? .connecting : .reconnecting)
            do {
                try await connectOnce(attempt: attempt)
                attempt = 0
                await consume()
            } catch let failure as RemoteError where ["unknown_device", "signature_invalid", "unsupported_version"].contains(failure.reason) {
                setLink(.failed(failure.reason))
                return
            } catch TransportFailure.wrongKey {
                setLink(.failed("wrong_key"))
                return
            } catch {
                // fall through to a retry
            }
            guard !Task.isCancelled else { return }
            attempt += 1
            setLink(.reconnecting)
            try? await Task.sleep(for: .milliseconds(min(2000, 250 * (1 << min(attempt - 1, 3)))))
        }
    }

    private func connectOnce(attempt: Int) async throws {
        let transport = try await connector(attempt)
        let client = RemoteClient(transport: transport)
        await client.start()
        let hello = try await client.sayHello(app: app)
        switch credentials {
        case .demo:
            let signer = SoftwareSigner()
            _ = try await client.pair(token: Base64URL.encode(Data(count: 16)), pin: Base64URL.encode(Data(count: 32)),
                                      device: signer, name: "Demo iPhone", model: "demo")
        case .paired(let host, let signer):
            _ = try await client.authenticate(pin: host.pin, device: signer)
        }
        let snapshot = try await client.subscribe(Self.topics)
        self.client = client
        state.host = hello.host
        state.capabilities = Set(hello.capabilities)
        apply(snapshot)
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
                let result = try await client.call(method, params)
                applyResult(result)
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
