import Foundation

/// Tabber Studio's Speed Trainer (trainer/1), the plan's S6: with Loop on,
/// the song plays from `start` percent, and each time the loop comes round
/// the speed goes up by `step` until it reaches `target`. `speed` is the
/// speed now. A changed field starts the ramp again from `start`, as in
/// Tabber Studio.
public struct TrainerState: Codable, Sendable, Hashable {
    public var enabled: Bool
    public var start: Int
    public var step: Int
    public var target: Int
    public var speed: Int

    public init(enabled: Bool = false, start: Int = 50, step: Int = 5, target: Int = 100, speed: Int = 100) {
        self.enabled = enabled; self.start = start; self.step = step; self.target = target; self.speed = speed
    }

    /// What the phone offers for each field, in percent; Tabber Studio allows
    /// any whole number in range, so a value set there is offered too.
    public static let starts = [50, 60, 70, 75, 80, 85, 90, 100]
    public static let steps = [1, 2, 3, 5, 10]
    public static let targets = [80, 90, 100, 110, 120]

    public static func choices(_ base: [Int], with current: Int) -> [Int] {
        base.contains(current) ? base : (base + [current]).sorted()
    }
}
