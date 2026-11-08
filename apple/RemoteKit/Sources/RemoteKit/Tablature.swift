import Foundation

// Tab on the phone (spec 7, capability tab/1): the selected tab track's bars
// around the edit cursor, and the cursor itself, as Tabber Studio's Tab view
// has them. Strings count from 1, the highest; beats are the rhythmic slots
// of a bar, counted from 1.

/// A note value: 1 whole, 2 half, 4 quarter, 8, 16, 32.
public struct NoteValue: Codable, Sendable, Hashable {
    public var value: Int
    public var dotted: Bool
    public var triplet: Bool
    public init(value: Int, dotted: Bool = false, triplet: Bool = false) {
        self.value = value; self.dotted = dotted; self.triplet = triplet
    }

    /// Its length in quarter notes.
    public var quarters: Double {
        var q = 4.0 / Double(value)
        if dotted { q *= 1.5 }
        if triplet { q *= 2.0 / 3.0 }
        return q
    }

    public static let values = [1, 2, 4, 8, 16, 32]
}

public struct TabNote: Codable, Sendable, Hashable {
    public var string: Int
    public var fret: Int
    /// MIDI tab only (tab.midi/1): below its open string or past the last
    /// fret, drawn where Tabber Studio draws it; the fret can be negative.
    public var virtual: Bool?
    public init(string: Int, fret: Int, virtual: Bool? = nil) {
        self.string = string; self.fret = fret; self.virtual = virtual
    }
}

public struct TabBeat: Codable, Sendable, Hashable {
    public var duration: NoteValue
    public var rest: Bool
    public var notes: [TabNote]
    public init(duration: NoteValue, rest: Bool, notes: [TabNote]) {
        self.duration = duration; self.rest = rest; self.notes = notes
    }
}

public struct TabBar: Codable, Sendable, Hashable {
    public var bar: Int
    public var timeSignature: TimeSignature
    public var beats: [TabBeat]
    enum CodingKeys: String, CodingKey { case bar, beats, timeSignature = "time_signature" }
    public init(bar: Int, timeSignature: TimeSignature, beats: [TabBeat]) {
        self.bar = bar; self.timeSignature = timeSignature; self.beats = beats
    }

    /// The bar's length in quarter notes.
    public var capacity: Double { Double(timeSignature.beats) * 4.0 / Double(timeSignature.unit) }
    public var filled: Double { beats.reduce(0) { $0 + $1.duration.quarters } }
}

public struct TabCursor: Codable, Sendable, Hashable {
    public var bar: Int
    public var beat: Int
    public var string: Int
    public init(bar: Int, beat: Int, string: Int) { self.bar = bar; self.beat = beat; self.string = string }
}

public struct TabState: Codable, Sendable, Hashable {
    public var trackID: String
    public var revision: Int
    /// The open strings as MIDI notes, highest first.
    public var tuning: [Int]
    public var drum: Bool
    public var cursor: TabCursor
    /// What a new note gets.
    public var duration: NoteValue
    public var barCount: Int
    /// The cursor's bar and its neighbours.
    public var bars: [TabBar]
    /// A melodic MIDI track's MIDI tab (tab.midi/1); nil from hosts before it.
    public var midi: Bool?

    enum CodingKeys: String, CodingKey {
        case revision, tuning, drum, cursor, duration, bars, midi
        case trackID = "track_id", barCount = "bar_count"
    }

    public init(trackID: String, revision: Int, tuning: [Int], drum: Bool, cursor: TabCursor, duration: NoteValue,
                barCount: Int, bars: [TabBar], midi: Bool? = nil) {
        self.trackID = trackID; self.revision = revision; self.tuning = tuning; self.drum = drum
        self.cursor = cursor; self.duration = duration; self.barCount = barCount; self.bars = bars; self.midi = midi
    }

    /// Whether this is a MIDI track's MIDI tab rather than a tab track's tab.
    public var isMidiTab: Bool { midi ?? false }

    public var strings: Int { tuning.count }
    public var cursorBar: TabBar? { bars.first { $0.bar == cursor.bar } }

    /// The beat after (or before) the cursor among the beats written, adding
    /// none: nil at the song's first or last beat. For a held Next or Previous.
    public func neighbour(_ by: Int) -> TabCursor? {
        guard let bar = cursorBar else { return nil }
        if by > 0 {
            if cursor.beat < bar.beats.count { return TabCursor(bar: cursor.bar, beat: cursor.beat + 1, string: cursor.string) }
            guard cursor.bar < barCount else { return nil }
            return TabCursor(bar: cursor.bar + 1, beat: 1, string: cursor.string)
        }
        if cursor.beat > 1 { return TabCursor(bar: cursor.bar, beat: cursor.beat - 1, string: cursor.string) }
        guard cursor.bar > 1 else { return nil }
        let previous = bars.first { $0.bar == cursor.bar - 1 }
        return TabCursor(bar: cursor.bar - 1, beat: max(1, previous?.beats.count ?? 1), string: cursor.string)
    }

    /// The first beat of the next (or previous) bar: nil past the song's ends.
    public func barStep(_ by: Int) -> TabCursor? {
        let target = cursor.bar + (by > 0 ? 1 : -1)
        guard (1...max(1, barCount)).contains(target) else { return nil }
        return TabCursor(bar: target, beat: 1, string: cursor.string)
    }
    public var cursorBeat: TabBeat? {
        guard let bar = cursorBar, bar.beats.indices.contains(cursor.beat - 1) else { return nil }
        return bar.beats[cursor.beat - 1]
    }

    /// The pitch a fret on a string sounds.
    public func pitch(string: Int, fret: Int) -> Int? {
        guard tuning.indices.contains(string - 1) else { return nil }
        return tuning[string - 1] + fret
    }
}
