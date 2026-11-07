import Foundation
import Network

/// A Tabber Studio found on the network with Bonjour (spec 3).
public struct FoundComputer: Sendable, Hashable, Identifiable {
    public var id: String { name }
    /// The computer's name, as Tabber Studio announces it.
    public let name: String
    /// The host id from the TXT record: which paired computer this is.
    public let hostID: String?
    public let versions: [String]
    let endpoint: NWEndpoint

    public init(name: String, hostID: String?, versions: [String] = ["1"], endpoint: NWEndpoint) {
        self.name = name
        self.hostID = hostID
        self.versions = versions
        self.endpoint = endpoint
    }

    init(_ result: Bonjour.Endpoint) {
        let txt = result.txtRecord.dictionary
        self.init(name: result.name, hostID: txt["id"],
                  versions: (txt["v"] ?? "1").split(separator: ",").map(String.init), endpoint: result.nwEndpoint)
    }
}

/// Finding Tabber Studio: browsing, resolving a result to an address, and
/// finding a paired computer again after its address or port changed.
public enum Discovery {
    public static let serviceType = "_tabber-remote._tcp"

    public enum Update: Sendable, Hashable {
        case found([FoundComputer])
        /// iOS keeps the app off the local network: Settings › Tabber Spak › Local Network.
        case denied
        case failed(String)
    }

    /// Browse until the stream is dropped. The first browse asks iOS for the
    /// Local Network permission.
    public static func browse() -> AsyncStream<Update> {
        AsyncStream { continuation in
            let task = Task {
                let browser = NetworkBrowser(for: .bonjour(serviceType, includeTxtRecord: true))
                    .onStateUpdate { _, state in
                        switch state {
                        case .waiting(let error), .failed(let error):
                            continuation.yield(isDenied(error) ? .denied : .failed("\(error)"))
                        default:
                            break
                        }
                    }
                do {
                    try await browser.run { endpoints in
                        continuation.yield(.found(endpoints.map(FoundComputer.init).sorted { $0.name < $1.name }))
                    }
                } catch {
                    if !Task.isCancelled { continuation.yield(isDenied(error) ? .denied : .failed("\(error)")) }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// `kDNSServiceErr_PolicyDenied`: the Local Network permission is off (Known traps).
    static func isDenied(_ error: Error) -> Bool {
        if case .dns(let code)? = error as? NWError { return code == -65570 }
        return false
    }

    /// The address and port of a found computer. The WebSocket needs a URL, so
    /// a Bonjour result is resolved first (Known traps): a TCP connection is
    /// opened to it and closed again once its address is known. IPv4 first,
    /// since it needs no interface name in the URL.
    public static func resolve(_ computer: FoundComputer, timeout: Duration = .seconds(3)) async -> Route? {
        if let route = await resolve(computer.endpoint, ipv4Only: true, timeout: timeout) { return route }
        return await resolve(computer.endpoint, ipv4Only: false, timeout: timeout)
    }

    static func resolve(_ endpoint: NWEndpoint, ipv4Only: Bool, timeout: Duration) async -> Route? {
        let parameters = NWParameters.tcp
        if ipv4Only, let ip = parameters.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options {
            ip.version = .v4
        }
        let connection = NWConnection(to: endpoint, using: parameters)
        let queue = DispatchQueue(label: "studio.tabber.spak.resolve")
        let once = Once<Route?>()
        return await withCheckedContinuation { continuation in
            once.set(continuation)
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    once.resume(route(connection.currentPath?.remoteEndpoint))
                    connection.cancel()
                case .failed, .waiting:
                    once.resume(nil)
                    connection.cancel()
                default:
                    break
                }
            }
            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + timeout.seconds) {
                once.resume(nil)
                connection.cancel()
            }
        }
    }

    static func route(_ endpoint: NWEndpoint?) -> Route? {
        guard case .hostPort(let host, let port)? = endpoint else { return nil }
        switch host {
        case .ipv4(let address): return Route(host: address.debugDescription, port: port.rawValue)
        case .ipv6(let address): return Route(host: address.debugDescription, port: port.rawValue)
        case .name(let name, _): return Route(host: name, port: port.rawValue)
        @unknown default: return nil
        }
    }

    /// Where a paired computer is now, by its host id: after its address or
    /// port changed, Bonjour still finds it (TR6).
    public static func lookup(hostID: String, within timeout: Duration = .seconds(2)) async -> Route? {
        let found: FoundComputer? = await withTaskGroup(of: FoundComputer?.self) { group in
            group.addTask {
                for await update in browse() {
                    if case .found(let list) = update, let match = list.first(where: { $0.hostID == hostID }) {
                        return match
                    }
                }
                return nil
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
        guard let found else { return nil }
        return await resolve(found)
    }
}

/// The addresses to try for a paired computer, in turn, with a Bonjour lookup
/// after each round, so a computer whose address or port changed is found
/// again without pairing (TR6).
public actor RouteBook {
    public private(set) var routes: [Route]
    public private(set) var lastTried: Route?
    private let hostID: String
    private let lookup: @Sendable (String) async -> Route?
    static let kept = 6

    public init(routes: [Route], hostID: String,
                lookup: @escaping @Sendable (String) async -> Route? = { await Discovery.lookup(hostID: $0) }) {
        self.routes = routes
        self.hostID = hostID
        self.lookup = lookup
    }

    /// Attempt n: the remembered addresses in turn, then Bonjour.
    public func route(for attempt: Int) async -> Route {
        let slot = attempt % (routes.count + 1)
        if slot < routes.count {
            lastTried = routes[slot]
        } else {
            lastTried = await lookup(hostID) ?? routes.first
        }
        return lastTried ?? Route(host: "127.0.0.1", port: 9474)
    }

    /// Every address to try at once (``RacingTransport``): the remembered
    /// ones, and on every other attempt the one Bonjour finds now.
    public func candidates(for attempt: Int) async -> [Route] {
        var all = routes
        if attempt % 2 == 1 || all.isEmpty, let found = await lookup(hostID), !all.contains(found) {
            all.append(found)
        }
        return all
    }

    /// The address that answered, for ``connected()``.
    public func use(_ route: Route) { lastTried = route }

    /// After a connection: the route that worked goes first, and when the port
    /// moved, the other addresses move with it (the computer has one port).
    /// Returns the new list when it changed, for the app to remember.
    public func connected() -> [Route]? {
        guard let used = lastTried else { return nil }
        var next = [used]
        for route in routes {
            let moved = Route(host: route.host, port: used.port)
            if !next.contains(moved) { next.append(moved) }
        }
        next = Array(next.prefix(Self.kept))
        guard next != routes else { return nil }
        routes = next
        return next
    }
}

/// Resumes a continuation once, from whichever callback comes first.
final class Once<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Never>?

    func set(_ continuation: CheckedContinuation<T, Never>) { lock.withLock { self.continuation = continuation } }

    func resume(_ value: T) {
        let waiting = lock.withLock { () -> CheckedContinuation<T, Never>? in
            defer { continuation = nil }
            return continuation
        }
        waiting?.resume(returning: value)
    }
}
