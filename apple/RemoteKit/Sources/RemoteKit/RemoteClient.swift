import Foundation

/// What arrives besides answers: events, heartbeats, the end of the connection.
public enum Incoming: Sendable, Hashable {
    case event(Event)
    case heartbeat(Heartbeat)
    case closed(Int?)
}

/// One connection to a host: requests matched to answers by id, events in order.
public actor RemoteClient {
    public static let protocolVersions = ["1.6"]

    private let transport: any RemoteTransport
    private var nextID = 0
    private var pending: [Int: CheckedContinuation<JSONValue, Error>] = [:]
    private var reader: Task<Void, Never>?
    private var beater: Task<Void, Never>?
    private let incomingContinuation: AsyncStream<Incoming>.Continuation
    public nonisolated let incoming: AsyncStream<Incoming>
    public private(set) var hello: HelloResult?
    public private(set) var isClosed = false
    /// Why the line ended, when the transport could tell (a denied local network, a wrong key).
    private var failure: TransportFailure?

    public init(transport: any RemoteTransport) {
        self.transport = transport
        (incoming, incomingContinuation) = AsyncStream<Incoming>.makeStream(bufferingPolicy: .bufferingNewest(1024))
    }

    /// Start reading and sending heartbeats every two seconds (spec 6.1).
    public func start(heartbeat: Duration = .seconds(2)) {
        guard reader == nil else { return }
        reader = Task { [weak self] in await self?.readLoop() }
        beater = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: heartbeat)
                guard let self, await !self.isClosed else { return }
                try? await self.sendRaw("{\"jsonrpc\":\"2.0\",\"method\":\"heartbeat\",\"params\":{}}")
            }
        }
    }

    private func sendRaw(_ text: String) async throws { try await transport.send(text) }

    private func readLoop() async {
        while true {
            let text: String?
            do {
                text = try await transport.receive()
            } catch let reason as TransportFailure {
                failure = reason
                text = nil
            } catch {
                text = nil
            }
            guard let text else { break }
            handle(text)
        }
        await finish()
    }

    private func finish() async {
        guard !isClosed else { return }
        isClosed = true
        let code = await transport.closeCode()
        let reason = failure ?? TransportFailure.closed(code)
        for (_, continuation) in pending { continuation.resume(throwing: reason) }
        pending.removeAll()
        beater?.cancel()
        incomingContinuation.yield(.closed(code))
        incomingContinuation.finish()
    }

    private func handle(_ text: String) {
        guard let message = try? JSONCoding.parse(text) else { return }
        if let id = message["id"]?.intValue, let continuation = pending.removeValue(forKey: id) {
            if let error = message["error"], let failure = RemoteError(json: error) {
                continuation.resume(throwing: failure)
            } else {
                continuation.resume(returning: message["result"] ?? .null)
            }
            return
        }
        guard let method = message["method"]?.stringValue, let params = message["params"] else { return }
        if method == "event", let topic = params["topic"]?.stringValue, let seq = params["seq"]?.intValue {
            incomingContinuation.yield(.event(Event(topic: topic, seq: seq, t: params["t"]?.doubleValue ?? 0,
                                                    data: params["data"] ?? .null)))
        } else if method == "heartbeat", let beat = try? JSONCoding.decode(Heartbeat.self, from: params) {
            incomingContinuation.yield(.heartbeat(beat))
        }
    }

    /// Call a verb. Throws `RemoteError` for a refusal, `TransportFailure` when the line drops.
    public func call(_ method: String, _ params: JSONValue = [:], timeout: Duration = .seconds(15)) async throws -> JSONValue {
        if isClosed {
            if let failure { throw failure }
            throw TransportFailure.closed(await transport.closeCode())
        }
        nextID += 1
        let id = nextID
        let request: JSONValue = ["jsonrpc": "2.0", "id": .number(Double(id)), "method": .string(method), "params": params]
        let text = try JSONCoding.encode(request)
        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            Task {
                do { try await self.sendRaw(text) } catch { self.fail(id, error) }
            }
            Task {
                try? await Task.sleep(for: timeout)
                self.fail(id, TransportFailure.unreachable("no answer to \(method)"))
            }
        }
    }

    private func fail(_ id: Int, _ error: Error) {
        pending.removeValue(forKey: id)?.resume(throwing: error)
    }

    public func call<T: Decodable>(_ method: String, _ params: JSONValue = [:], as type: T.Type,
                                   timeout: Duration = .seconds(15)) async throws -> T {
        try JSONCoding.decode(T.self, from: try await call(method, params, timeout: timeout))
    }

    /// The first request on a connection. Its timeout is also how long a dead
    /// address may hold up a reconnect, so the session passes a short one.
    public func sayHello(app: AppInfo, timeout: Duration = .seconds(15)) async throws -> HelloResult {
        let result = try await call("hello", ["app": try JSONCoding.value(app),
                                              "protocol_versions": .array(Self.protocolVersions.map { .string($0) })],
                                    as: HelloResult.self, timeout: timeout)
        hello = result
        return result
    }

    /// Pair with the QR code's token (spec 4.3).
    public func pair(token: String, pin: String, device: DeviceSigner, name: String, model: String) async throws -> PairResult {
        guard let challenge = hello.flatMap({ Base64URL.decode($0.challenge) }), let pinHash = Base64URL.decode(pin),
              let tokenBytes = Base64URL.decode(token) else { throw TransportFailure.unreachable("say hello first") }
        let message = RemoteCrypto.signedBytes(context: RemoteCrypto.pairContext, pinHash: pinHash,
                                               challenge: challenge, token: tokenBytes)
        return try await call("pair", ["mode": "token", "token": .string(token),
                                       "device": ["name": .string(name), "model": .string(model),
                                                  "key": .string(Base64URL.encode(device.publicKeyDER))],
                                       "signature": .string(Base64URL.encode(try device.sign(message)))],
                              as: PairResult.self)
    }

    /// Prove a paired device (spec 4.5).
    public func authenticate(pin: String, device: DeviceSigner) async throws -> AuthResult {
        guard let challenge = hello.flatMap({ Base64URL.decode($0.challenge) }), let pinHash = Base64URL.decode(pin) else {
            throw TransportFailure.unreachable("say hello first")
        }
        let message = RemoteCrypto.signedBytes(context: RemoteCrypto.authContext, pinHash: pinHash, challenge: challenge)
        return try await call("auth", ["device_id": .string(device.deviceID),
                                       "signature": .string(Base64URL.encode(try device.sign(message)))],
                              as: AuthResult.self)
    }

    public func subscribe(_ topics: [String]) async throws -> Snapshot {
        try await call("session.subscribe", ["topics": .array(topics.map { .string($0) })], as: Snapshot.self)
    }

    public func close() async {
        await transport.close()
        await finish()
    }
}

public struct AppInfo: Codable, Sendable, Hashable {
    public var name: String
    public var version: String
    public var build: String
    public var platform: String
    public init(name: String = "Tabber Spak", version: String, build: String, platform: String = "ios") {
        self.name = name; self.version = version; self.build = build; self.platform = platform
    }
}
