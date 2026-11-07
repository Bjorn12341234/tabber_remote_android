import Foundation

/// How long the computer takes to answer a change made on this phone: from
/// sending it to applying the computer's answer, which is when the phone shows
/// the confirmed state (plan: TR7's gate, 19 taps in 20 within 150 ms on home
/// Wi-Fi). It is measured on the phone, so a run on the owner's iPhone gives
/// the numbers with nothing added on the computer.
public struct ResponseTimes: Sendable, Hashable {
    /// The newest answers, oldest first.
    public private(set) var samples: [Duration] = []
    /// How many answers are kept: enough for a rehearsal, small enough to sort each second.
    public static let kept = 500

    public init() {}

    public var count: Int { samples.count }
    /// Half the taps were answered within this.
    public var median: Duration? { percentile(50) }
    /// 19 taps in 20 were answered within this.
    public var p95: Duration? { percentile(95) }

    mutating func add(_ sample: Duration) {
        samples.append(sample)
        if samples.count > Self.kept { samples.removeFirst(samples.count - Self.kept) }
    }

    /// The nearest-rank percentile: the smallest answer time with at least
    /// `percent` of the answers at or under it.
    public func percentile(_ percent: Int) -> Duration? {
        guard !samples.isEmpty else { return nil }
        let sorted = samples.sorted()
        let rank = (percent * sorted.count + 99) / 100          // rounded up, in whole numbers
        return sorted[min(max(rank, 1), sorted.count) - 1]
    }

    /// Whether a verb's answer is a tap's. Reads are not taps, and the chat's
    /// answers wait for the AI, which is not the line's speed.
    static func counts(_ method: String) -> Bool {
        !RemoteSession.reads.contains(method) && !method.hasPrefix("chat.")
    }
}

public extension Duration {
    /// Whole milliseconds, for showing.
    var milliseconds: Int {
        let parts = components
        return Int((Double(parts.seconds) * 1000 + Double(parts.attoseconds) / 1e15).rounded())
    }
}
