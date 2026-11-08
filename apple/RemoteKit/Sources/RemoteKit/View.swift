import Foundation

/// What Tabber Studio shows on the computer (view/1): the editor, Arrange,
/// Tab or Piano Roll, and whether Split is on beside it; and, from hosts
/// with view.part/1, the MIDI part the Tab editor shows.
public struct ViewState: Codable, Sendable, Hashable {
    public static let editors = ["arrange", "tab", "piano_roll"]

    /// "arrange", "tab" or "piano_roll"; in Split, the one beside Arrange.
    public var editor: String
    public var split: Bool
    /// The chosen MIDI track as the Tab editor shows it; nil when it shows none.
    public var part: ViewPart?
    /// Whether the host sent `part` at all (view.part/1), even as null: a
    /// view from an older host keeps it absent when written back.
    public var hasPart: Bool

    public init(editor: String, split: Bool, part: ViewPart? = nil, hasPart: Bool = false) {
        self.editor = editor; self.split = split; self.part = part; self.hasPart = hasPart || part != nil
    }

    /// The same view on the computer: whether `part` came as null or not at
    /// all is only how it was written.
    public static func == (a: ViewState, b: ViewState) -> Bool {
        a.editor == b.editor && a.split == b.split && a.part == b.part
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(editor); hasher.combine(split); hasher.combine(part)
    }

    enum CodingKeys: String, CodingKey { case editor, split, part }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        editor = try c.decode(String.self, forKey: .editor)
        split = try c.decode(Bool.self, forKey: .split)
        hasPart = c.contains(.part)
        part = try c.decodeIfPresent(ViewPart.self, forKey: .part)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(editor, forKey: .editor)
        try c.encode(split, forKey: .split)
        if hasPart { try c.encode(part, forKey: .part) }      // null when there is none
    }
}

/// Tabber Studio's "MIDI part" card and what follows it (view.part/1): the
/// card waits with Show standard notation, and for a melodic MIDI track Show
/// MIDI tab; then the track shows as MIDI tab or in standard notation.
public struct ViewPart: Codable, Sendable, Hashable {
    public var trackID: String
    /// "card", "midi_tab" or "notation".
    public var shows: String
    /// Whether the track can show MIDI tab: a melodic MIDI track, not drums.
    public var midiTab: Bool

    public init(trackID: String, shows: String, midiTab: Bool) {
        self.trackID = trackID; self.shows = shows; self.midiTab = midiTab
    }

    enum CodingKeys: String, CodingKey {
        case trackID = "track_id", shows, midiTab = "midi_tab"
    }
}
