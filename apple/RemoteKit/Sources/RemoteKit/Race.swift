import Foundation

/// Every remembered address at once: the first that answers is the
/// connection (the owner, 2026-11-07: "it doesn't work when I'm not on the
/// same wifi"). Away from the Wi-Fi the local addresses go nowhere, so trying
/// them one after another kept the phone waiting before it reached the
/// computer's Tailscale address. Now each frame sent before an answer goes to
/// every address, the first to answer wins, and the others are dropped.
///
/// Nothing is weaker for it: each address is its own TLS connection, pinned
/// to the paired computer's key, and the first frame is the hello, which
/// carries no secret. A wrong key at one address is only a failure there.
public final class RacingTransport: RemoteTransport, @unchecked Sendable {
    public typealias Make = @Sendable (Route) -> any RemoteTransport

    private let lock = NSLock()
    private var candidates: [(route: Route, transport: any RemoteTransport)]
    private var winner: (any RemoteTransport)?
    /// Each address's work in flight, cancelled when another address wins, so
    /// a dead address stops retrying and is released.
    private var tasks: [Int: [Task<Void, Never>]] = [:]
    private let onWinner: @Sendable (Route) async -> Void

    public init(routes: [Route], make: Make, onWinner: @escaping @Sendable (Route) async -> Void = { _ in }) {
        var seen: Set<Route> = []
        candidates = routes.filter { seen.insert($0).inserted }.map { ($0, make($0)) }
        self.onWinner = onWinner
    }

    private var decided: (any RemoteTransport)? { lock.withLock { winner } }

    public func send(_ text: String) async throws {
        if let winner = decided {
            try await winner.send(text)
            return
        }
        let all = lock.withLock { candidates }
        guard !all.isEmpty else { throw TransportFailure.unreachable("No address for the computer.") }
        for (index, candidate) in all.enumerated() {
            let task = Task { _ = try? await candidate.transport.send(text) }   // each address on its own
            lock.withLock { tasks[index, default: []].append(task) }
        }
    }

    public func receive() async throws -> String? {
        if let winner = decided { return try await winner.receive() }
        let all = lock.withLock { candidates }
        guard !all.isEmpty else { throw TransportFailure.unreachable("No address for the computer.") }
        let race = Race(count: all.count)
        let (index, frame): (Int, String) = try await withCheckedThrowingContinuation { continuation in
            race.start(continuation)
            for (index, candidate) in all.enumerated() {
                let task = Task {
                    do {
                        if let frame = try await candidate.transport.receive() {
                            race.win(index, frame)
                        } else {
                            race.lose(TransportFailure.closed(await candidate.transport.closeCode()))
                        }
                    } catch {
                        race.lose(error)
                    }
                }
                lock.withLock { tasks[index, default: []].append(task) }
            }
        }
        let chosen = all[index]
        let (losers, stale): ([any RemoteTransport], [Task<Void, Never>]) = lock.withLock {
            winner = chosen.transport
            let others = candidates.enumerated().filter { $0.offset != index }.map(\.element.transport)
            let work = tasks.filter { $0.key != index }.flatMap(\.value)
            candidates = [chosen]                                  // the others are released, and so cancelled
            tasks = [:]
            return (others, work)
        }
        for task in stale { task.cancel() }
        for loser in losers { await loser.close() }
        await onWinner(chosen.route)
        return frame
    }

    public func close() async {
        if let winner = decided {
            await winner.close()
            return
        }
        for candidate in lock.withLock({ candidates }) { await candidate.transport.close() }
    }

    public func closeCode() async -> Int? {
        guard let winner = decided else { return nil }
        return await winner.closeCode()
    }
}

/// The first answer, or once every address has failed, the failure that
/// says most: the local network refused, then any other, a wrong key last.
final class Race: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<(Int, String), Error>?
    private var failures: [Error] = []
    private let count: Int

    init(count: Int) { self.count = count }

    func start(_ continuation: CheckedContinuation<(Int, String), Error>) {
        lock.withLock { self.continuation = continuation }
    }

    func win(_ index: Int, _ frame: String) {
        let waiting: CheckedContinuation<(Int, String), Error>? = lock.withLock {
            defer { continuation = nil }
            return continuation
        }
        waiting?.resume(returning: (index, frame))
    }

    func lose(_ error: Error) {
        let (waiting, all): (CheckedContinuation<(Int, String), Error>?, [Error]) = lock.withLock {
            failures.append(error)
            guard failures.count == count, let waiting = continuation else { return (nil, []) }
            continuation = nil
            return (waiting, failures)
        }
        guard let waiting else { return }
        waiting.resume(throwing: Self.telling(all))
    }

    static func telling(_ failures: [Error]) -> Error {
        if failures.contains(where: { ($0 as? TransportFailure) == .localNetworkDenied }) {
            return TransportFailure.localNetworkDenied
        }
        if let other = failures.first(where: { ($0 as? TransportFailure) != .wrongKey }) { return other }
        return failures.first ?? TransportFailure.unreachable("No address answered.")
    }
}
