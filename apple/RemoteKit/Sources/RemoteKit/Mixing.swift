import Foundation

// The mixer (spec 7, capability mixer/1): a strip for every track, every bus
// and the master, in Tabber Studio's mixer order.

/// A channel strip. A track's strip has the track's id; the master's is "master".
public struct Strip: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    /// "track", "bus" or "master".
    public var kind: String
    public var name: String
    public var color: String?
    /// The fader's travel, 0 to 1, in the computer's own fader law.
    public var volume: Double
    /// What the fader means; nil is silence.
    public var volumeDB: Double?
    /// -1 is hard left, 1 hard right.
    public var pan: Double
    /// As Tabber Studio writes it: "L64", "C", "R63".
    public var panLabel: String
    public var muted: Bool
    public var soloed: Bool

    enum CodingKeys: String, CodingKey {
        case id, kind, name, color, volume, pan, muted, soloed
        case volumeDB = "volume_db", panLabel = "pan_label"
    }

    public init(id: String, kind: String, name: String, color: String?, volume: Double, volumeDB: Double?,
                pan: Double, panLabel: String, muted: Bool, soloed: Bool) {
        self.id = id; self.kind = kind; self.name = name; self.color = color; self.volume = volume
        self.volumeDB = volumeDB; self.pan = pan; self.panLabel = panLabel; self.muted = muted; self.soloed = soloed
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id); try c.encode(kind, forKey: .kind); try c.encode(name, forKey: .name)
        try c.encode(color, forKey: .color); try c.encode(volume, forKey: .volume)
        try c.encode(volumeDB, forKey: .volumeDB); try c.encode(pan, forKey: .pan)
        try c.encode(panLabel, forKey: .panLabel); try c.encode(muted, forKey: .muted); try c.encode(soloed, forKey: .soloed)
    }

    public var isMaster: Bool { kind == "master" }
    public var isBus: Bool { kind == "bus" }
}

/// A mark on the fader's scale: where a level sits on the computer's fader.
public struct ScaleMark: Codable, Sendable, Hashable {
    public var db: Double
    public var volume: Double
    public init(db: Double, volume: Double) { self.db = db; self.volume = volume }
}

public struct MixerState: Codable, Sendable, Hashable {
    public var strips: [Strip]
    /// The fader scale, top down (0, -12, -24, -48 in Tabber Studio).
    public var scale: [ScaleMark]
    public init(strips: [Strip], scale: [ScaleMark]) { self.strips = strips; self.scale = scale }

    /// The fader travel that means 0 dB, for a double tap.
    public var unity: Double { scale.first { $0.db == 0 }?.volume ?? 0.7 }
}

public struct StripLevel: Codable, Sendable, Hashable {
    public var stripID: String
    public var peak: [Double]
    enum CodingKeys: String, CodingKey { case peak, stripID = "strip_id" }
    public init(stripID: String, peak: [Double]) { self.stripID = stripID; self.peak = peak }
}
