import Foundation

// Plug-ins (spec 9, capability plugins/1): each strip's INSERTS, as Tabber
// Studio's mixer strip lists them, and the rows of its Insert Plugin browser.

/// One plug-in in a strip's INSERTS.
public struct Insert: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var name: String
    /// The strip's hollow dot: the sound passes it by.
    public var bypassed: Bool
    /// Tabber Studio bypassed it itself, because it took too long.
    public var autoBypassed: Bool

    enum CodingKeys: String, CodingKey {
        case id, name, bypassed
        case autoBypassed = "auto_bypassed"
    }

    public init(id: String, name: String, bypassed: Bool = false, autoBypassed: Bool = false) {
        self.id = id; self.name = name; self.bypassed = bypassed; self.autoBypassed = autoBypassed
    }
}

/// A row of the Insert Plugin browser: its Name, Vendor, Category, Type and Format.
public struct PluginRow: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var name: String
    public var vendor: String
    public var category: String
    /// "effect" or "instrument".
    public var kind: String
    /// "native" (one of Tabber's own devices), "vst3" or "clap".
    public var format: String
    /// In the browser's Tabber Plugins tab; otherwise its Plugins tab.
    public var tabber: Bool
    public var available: Bool
    /// Why it can't be inserted, in the browser's words.
    public var reason: String?

    public init(id: String, name: String, vendor: String, category: String, kind: String, format: String,
                tabber: Bool, available: Bool = true, reason: String? = nil) {
        self.id = id; self.name = name; self.vendor = vendor; self.category = category; self.kind = kind
        self.format = format; self.tabber = tabber; self.available = available; self.reason = reason
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id); try c.encode(name, forKey: .name); try c.encode(vendor, forKey: .vendor)
        try c.encode(category, forKey: .category); try c.encode(kind, forKey: .kind); try c.encode(format, forKey: .format)
        try c.encode(tabber, forKey: .tabber); try c.encode(available, forKey: .available)
        try c.encode(reason, forKey: .reason)                 // null when it can be inserted, as the protocol has it
    }

    public var isInstrument: Bool { kind == "instrument" }
    /// The browser's Type column.
    public var typeLabel: String { isInstrument ? "Instrument" : "Effect" }
    /// The browser's Format column, short.
    public var formatLabel: String { format == "native" ? "Tabber" : format.uppercased() }
}

/// A page of the browser's rows.
public struct PluginPage: Codable, Sendable, Hashable {
    public var plugins: [PluginRow]
    public var total: Int
    public var offset: Int
    public init(plugins: [PluginRow], total: Int, offset: Int) {
        self.plugins = plugins; self.total = total; self.offset = offset
    }
}
