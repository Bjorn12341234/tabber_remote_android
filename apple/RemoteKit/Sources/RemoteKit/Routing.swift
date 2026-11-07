import Foundation

/// A track or a bus and the one place its sound goes (routing/1): the master,
/// or a bus. Ids are the mixer's strip ids.
public struct RoutingSource: Codable, Sendable, Hashable, Identifiable {
    public var stripID: String
    public var kind: String          // "track" or "bus"
    public var name: String
    public var output: String        // "master" or a bus's strip id

    public var id: String { stripID }
    public var isBus: Bool { kind == "bus" }

    enum CodingKeys: String, CodingKey {
        case kind, name, output
        case stripID = "strip_id"
    }

    public init(stripID: String, kind: String, name: String, output: String) {
        self.stripID = stripID; self.kind = kind; self.name = name; self.output = output
    }
}

/// A track's sound tapped into a bus beside its output.
public struct RoutingSend: Codable, Sendable, Hashable, Identifiable {
    public var stripID: String
    public var busID: String
    /// The send's gain, 0 to 1, as Tabber Studio stores it.
    public var level: Double
    public var levelDB: Double?
    /// As Tabber Studio writes it: "-6.0 dB".
    public var levelLabel: String
    public var preFader: Bool

    public var id: String { "\(stripID)>\(busID)" }

    enum CodingKeys: String, CodingKey {
        case level
        case stripID = "strip_id", busID = "bus_id", levelDB = "level_db", levelLabel = "level_label", preFader = "pre_fader"
    }

    public init(stripID: String, busID: String, level: Double, levelDB: Double?, levelLabel: String, preFader: Bool) {
        self.stripID = stripID; self.busID = busID; self.level = level
        self.levelDB = levelDB; self.levelLabel = levelLabel; self.preFader = preFader
    }

    /// Silence is an explicit null, as the computer sends it.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(stripID, forKey: .stripID); try c.encode(busID, forKey: .busID)
        try c.encode(level, forKey: .level); try c.encode(levelDB, forKey: .levelDB)
        try c.encode(levelLabel, forKey: .levelLabel); try c.encode(preFader, forKey: .preFader)
    }
}

/// Where each track and bus sends its sound, as Tabber Studio's Routing panel shows it.
public struct RoutingState: Codable, Sendable, Hashable {
    public static let master = "master"

    public var sources: [RoutingSource]
    public var sends: [RoutingSend]

    public init(sources: [RoutingSource], sends: [RoutingSend]) {
        self.sources = sources; self.sends = sends
    }

    public var tracks: [RoutingSource] { sources.filter { !$0.isBus } }
    public var buses: [RoutingSource] { sources.filter(\.isBus) }

    public func source(_ stripID: String) -> RoutingSource? { sources.first { $0.stripID == stripID } }

    /// The name of where a source's sound goes.
    public func outputName(of source: RoutingSource) -> String {
        source.output == Self.master ? "Master" : (self.source(source.output)?.name ?? "Master")
    }

    public func sends(from stripID: String) -> [RoutingSend] { sends.filter { $0.stripID == stripID } }

    /// What feeds a bus: the tracks and buses that output to it, then the sends into it.
    public func feeding(_ busID: String) -> (outputs: [RoutingSource], sends: [RoutingSend]) {
        (sources.filter { $0.output == busID }, sends.filter { $0.busID == busID })
    }

    /// The buses a source can output to: every bus but itself.
    public func outputs(for source: RoutingSource) -> [RoutingSource] {
        buses.filter { $0.stripID != source.stripID }
    }

    /// Whether routing bus `source` into bus `dest` would close a loop:
    /// `dest`'s outputs already lead back to `source` (Tabber Studio's rule).
    /// Returns the loop by name, from the source back to it, as Tabber Studio names it.
    public func wouldLoop(_ source: String, into dest: String) -> [String]? {
        guard dest != Self.master else { return nil }
        let name = { (id: String) in self.source(id)?.name ?? id }
        if source == dest { return [name(source), name(source)] }
        var path = [source, dest]
        var seen: Set<String> = [source, dest]
        var at = dest
        while let next = self.source(at)?.output, next != Self.master {
            path.append(next)
            if next == source { return path.map(name) }
            guard seen.insert(next).inserted else { return nil }     // a loop elsewhere, not through the source
            at = next
        }
        return nil
    }
}

/// How Tabber Studio writes a send level (ui/routing_matrix_view.py format_send_db).
public enum SendLevel {
    public static func db(_ level: Double) -> Double? {
        guard level > 0 else { return nil }
        let db = 20 * log10(level)
        return db <= -60 ? nil : db
    }

    public static func label(_ level: Double) -> String {
        guard let db = db(level) else { return "-∞ dB" }
        return String(format: "%+.1f dB", db)
    }
}
