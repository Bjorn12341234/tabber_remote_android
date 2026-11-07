import Foundation
import Network
import Security

/// One connection's text frames, whatever carries them.
public protocol RemoteTransport: Sendable {
    func send(_ text: String) async throws
    /// The next text frame, or nil once the connection is closed.
    func receive() async throws -> String?
    func close() async
    /// The WebSocket close code, once closed by the other side.
    func closeCode() async -> Int?
}

public enum TransportFailure: Error, Sendable, Hashable {
    case wrongKey                // the computer's key does not match the pin
    case closed(Int?)
    case unreachable(String)
    case localNetworkDenied      // iOS keeps the app off the local network (Settings › Tabber Spak)
}

/// Checks the computer's key against the pin (spec 2, Trust). With no pin
/// yet (6-digit pairing) it accepts the key and remembers it.
final class PinBox: @unchecked Sendable {
    private let lock = NSLock()
    private var seen: String?
    let expected: String?

    init(expected: String?) { self.expected = expected }

    var observed: String? { lock.withLock { seen } }

    func check(_ trust: sec_trust_t) -> Bool {
        let secTrust = sec_trust_copy_ref(trust).takeRetainedValue()
        guard let chain = SecTrustCopyCertificateChain(secTrust) as? [SecCertificate], let leaf = chain.first,
              let key = SecCertificateCopyKey(leaf),
              let raw = SecKeyCopyExternalRepresentation(key, nil) as Data?,
              let spki = RemoteCrypto.spkiDER(x963: raw) else { return false }
        let pin = RemoteCrypto.pin(spkiDER: spki)
        lock.withLock { seen = pin }
        return expected == nil || expected == pin
    }
}

/// WebSocket over TLS 1.3 with the Network framework, pinned to the computer's key.
public final class NetworkTransport: RemoteTransport, @unchecked Sendable {
    private let connection: NetworkConnection<WebSocket>
    private let pins: PinBox
    private let lock = NSLock()
    private var code: Int?

    /// `pin` nil only for 6-digit pairing; read `observedPin` afterwards.
    public init(route: Route, pin: String?) {
        let box = PinBox(expected: pin)
        pins = box
        // A WebSocket needs a wss:// URL endpoint: with a bare host and port the
        // Network framework aborts right after the TLS handshake (TR5 interop).
        let url = Self.url(for: route)
        connection = NetworkConnection(to: .url(url)) {
            WebSocket {
                TLS()
                    .version(min: .TLSv13)
                    .certificateValidator { _, trust in box.check(trust) }
            }
            .subprotocols(["tabber-remote.v1"])
            .maximumMessageSize(65536)
        }
    }

    public var observedPin: String? { pins.observed }

    /// `wss://host:port/`. An IPv6 zone (`fe80::1%en0`, from a Bonjour lookup)
    /// is written `%25` in a URL, or the URL would not parse.
    static func url(for route: Route) -> URL {
        let host = route.host.contains(":") ? "[\(route.host.replacingOccurrences(of: "%", with: "%25"))]" : route.host
        return URL(string: "wss://\(host):\(route.port)/") ?? URL(string: "wss://127.0.0.1:\(route.port)/")!
    }

    public func send(_ text: String) async throws {
        try await connection.send(text)
    }

    public func receive() async throws -> String? {
        do {
            let (content, metadata) = try await connection.receive()
            switch metadata.opcode {
            case .text:
                return String(decoding: content, as: UTF8.self)
            case .close:
                lock.withLock { code = metadata.closeCode.map(Self.number) }
                return nil
            default:
                return try await receive()
            }
        } catch {
            if pins.expected != nil, let seen = pins.observed, seen != pins.expected {
                throw TransportFailure.wrongKey
            }
            if let path = connection.currentPath, path.status == .unsatisfied, path.unsatisfiedReason == .localNetworkDenied {
                throw TransportFailure.localNetworkDenied
            }
            throw error
        }
    }

    /// Send a close frame if the connection is up, without waiting for it.
    /// A connection that never came up (a wrong pin, nobody listening) waits
    /// and retries; it is cancelled when this transport is released, and
    /// `close()` on it would never return.
    public func close() async {
        guard case .ready = connection.state else { return }
        let connection = self.connection
        Task { try? await connection.close() }
    }

    public func closeCode() async -> Int? { lock.withLock { code } }

    static func number(_ code: NWProtocolWebSocket.CloseCode) -> Int {
        switch code {
        case .protocolCode(let value): return Int(value.rawValue)
        case .applicationCode(let value): return Int(value)
        case .privateCode(let value): return Int(value)
        @unknown default: return 0
        }
    }
}

/// An in-process connection: DemoHost and tests. Each side's sends are the
/// other side's receives.
public final class MemoryTransport: RemoteTransport, @unchecked Sendable {
    private let inbound: AsyncStream<String>
    private var iterator: AsyncStream<String>.Iterator
    private let outbound: AsyncStream<String>.Continuation
    private let closeOutbound: @Sendable (Int?) -> Void
    private let lock = NSLock()
    private var code: Int?
    private var finished = false

    init(inbound: AsyncStream<String>, outbound: AsyncStream<String>.Continuation,
         closeOutbound: @escaping @Sendable (Int?) -> Void) {
        self.inbound = inbound
        self.iterator = inbound.makeAsyncIterator()
        self.outbound = outbound
        self.closeOutbound = closeOutbound
    }

    /// Two connected ends.
    public static func pair() -> (phone: MemoryTransport, host: MemoryTransport) {
        let (toHost, toHostIn) = AsyncStream<String>.makeStream()
        let (toPhone, toPhoneIn) = AsyncStream<String>.makeStream()
        nonisolated(unsafe) var phoneRef: MemoryTransport?
        nonisolated(unsafe) var hostRef: MemoryTransport?
        let phone = MemoryTransport(inbound: toPhone, outbound: toHostIn,
                                    closeOutbound: { code in hostRef?.closed(by: code); toHostIn.finish() })
        let host = MemoryTransport(inbound: toHost, outbound: toPhoneIn,
                                   closeOutbound: { code in phoneRef?.closed(by: code); toPhoneIn.finish() })
        phoneRef = phone
        hostRef = host
        return (phone, host)
    }

    func closed(by code: Int?) { lock.withLock { self.code = code } }

    public func send(_ text: String) async throws {
        guard sendNow(text) else { throw TransportFailure.closed(lock.withLock { code }) }
    }

    /// Deliver a frame at once, in order; false once closed.
    @discardableResult
    public func sendNow(_ text: String) -> Bool {
        let done = lock.withLock { finished }
        if done { return false }
        outbound.yield(text)
        return true
    }

    public func receive() async throws -> String? {
        var it = lock.withLock { iterator }
        let next = await it.next()
        lock.withLock { iterator = it }
        return next
    }

    public func close() async { close(code: 1000) }

    /// Close with a code the other side will see.
    public func close(code: Int) {
        let first = lock.withLock { () -> Bool in
            if finished { return false }
            finished = true
            return true
        }
        if first { closeOutbound(code) }
    }

    /// The network dropped: no close frame, the other side sees nothing.
    public func drop() { close(code: 1006) }

    public func closeCode() async -> Int? { lock.withLock { code } }
}
