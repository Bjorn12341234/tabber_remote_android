import Foundation

/// One tab track's notes in the demo computer, edited as Tabber Studio's Tab
/// view edits them (remote_host/tablature.py, ui/main_window.py
/// _on_fretboard_click, ui/piano_staff_input.py, ui/score_scene.py):
/// - a fretboard tap writes that fret on that string at the cursor's beat, or
///   takes it away if it is already there; the cursor stays, so more taps
///   build a chord; the chosen duration applies only to an empty beat;
/// - a piano key does the same with the lowest fret that plays the pitch;
/// - R toggles a rest; Delete takes the note on the cursor's string, and a
///   beat left with none is a rest;
/// - moving on past the last beat fills the bar with a rest beat, or starts
///   the next bar, adding one at the end of the song.
///
/// A drum track's drum tab (tab.drum/1) has six lines and GM numbers for
/// frets; the Drum Map writes on it as `putDrum` says.
struct DemoTab: Equatable, Sendable {
    var tuning: [Int]
    var bars: [[TabBeat]]
    var timeSignature = TimeSignature(beats: 4, unit: 4)
    /// A drum track's drum tab: lines without pitch, GM numbers for frets.
    var drum = false

    static let maxFret = 24

    var capacity: Double { Double(timeSignature.beats) * 4.0 / Double(timeSignature.unit) }

    func filled(_ bar: Int) -> Double { bars[bar - 1].reduce(0) { $0 + $1.duration.quarters } }

    func clamp(_ cursor: TabCursor) -> TabCursor {
        let bar = max(1, min(bars.count, cursor.bar))
        let beat = max(1, min(max(1, bars[bar - 1].count), cursor.beat))
        let string = max(1, min(tuning.count, cursor.string))
        return TabCursor(bar: bar, beat: beat, string: string)
    }

    /// The bar's beat at the cursor, made if the bar has none yet.
    private mutating func beatIndex(_ cursor: TabCursor, _ duration: NoteValue) -> Int {
        if bars[cursor.bar - 1].isEmpty {
            bars[cursor.bar - 1].append(TabBeat(duration: duration, rest: true, notes: []))
        }
        return min(cursor.beat, bars[cursor.bar - 1].count) - 1
    }

    /// A fretboard tap. Returns whether the song changed.
    mutating func put(string: Int, fret: Int, at cursor: TabCursor, duration: NoteValue) -> Bool {
        guard (1...tuning.count).contains(string), (0...Self.maxFret).contains(fret) else { return false }
        let i = beatIndex(cursor, duration)
        var beat = bars[cursor.bar - 1][i]
        if let same = beat.notes.firstIndex(where: { $0.string == string && $0.fret == fret }) {
            beat.notes.remove(at: same)                   // tapping the same fret again takes it away
            beat.rest = beat.notes.isEmpty
        } else {
            if beat.rest && beat.notes.isEmpty { beat.duration = duration }   // an empty beat takes the chosen value
            beat.notes.removeAll { $0.string == string }  // one note per string
            beat.notes.append(TabNote(string: string, fret: fret))
            beat.notes.sort { $0.string < $1.string }
            beat.rest = false
        }
        bars[cursor.bar - 1][i] = beat
        return true
    }

    /// Where a piano key lands: the lowest fret that plays it, then the higher string.
    func place(pitch: Int) -> (string: Int, fret: Int)? {
        var best: (string: Int, fret: Int)?
        for (index, open) in tuning.enumerated() {
            let fret = pitch - open
            guard (0...Self.maxFret).contains(fret) else { continue }
            if best == nil || fret < best!.fret { best = (index + 1, fret) }
        }
        return best
    }

    /// A piano key: takes the pitch away if the beat has it, else writes it.
    mutating func put(pitch: Int, at cursor: TabCursor, duration: NoteValue) -> (string: Int, changed: Bool) {
        if bars.indices.contains(cursor.bar - 1), bars[cursor.bar - 1].indices.contains(cursor.beat - 1) {
            let beat = bars[cursor.bar - 1][cursor.beat - 1]
            if let note = beat.notes.first(where: { tuning[$0.string - 1] + $0.fret == pitch }) {
                return (note.string, put(string: note.string, fret: note.fret, at: cursor, duration: duration))
            }
        }
        guard let spot = place(pitch: pitch) else { return (cursor.string, false) }
        return (spot.string, put(string: spot.string, fret: spot.fret, at: cursor, duration: duration))
    }

    mutating func setDuration(_ duration: NoteValue, at cursor: TabCursor) -> Bool {
        guard bars.indices.contains(cursor.bar - 1), bars[cursor.bar - 1].indices.contains(cursor.beat - 1),
              bars[cursor.bar - 1][cursor.beat - 1].duration != duration else { return false }
        bars[cursor.bar - 1][cursor.beat - 1].duration = duration
        return true
    }

    /// R: a beat with notes becomes a rest; a rest becomes an empty beat.
    mutating func rest(at cursor: TabCursor) -> Bool {
        guard bars.indices.contains(cursor.bar - 1), bars[cursor.bar - 1].indices.contains(cursor.beat - 1) else { return false }
        let beat = bars[cursor.bar - 1][cursor.beat - 1]
        bars[cursor.bar - 1][cursor.beat - 1] = TabBeat(duration: beat.duration, rest: !beat.rest || !beat.notes.isEmpty, notes: [])
        return true
    }

    /// Delete: the note on the cursor's string, and nothing else.
    mutating func delete(at cursor: TabCursor) -> Bool {
        guard bars.indices.contains(cursor.bar - 1), bars[cursor.bar - 1].indices.contains(cursor.beat - 1) else { return false }
        var beat = bars[cursor.bar - 1][cursor.beat - 1]
        guard beat.notes.contains(where: { $0.string == cursor.string }) else { return false }
        beat.notes.removeAll { $0.string == cursor.string }
        beat.rest = beat.notes.isEmpty
        bars[cursor.bar - 1][cursor.beat - 1] = beat
        return true
    }

    /// What a Drum Map tap did (tab.drum/1).
    enum DrumTap: Equatable { case wrote(line: Int), tookOff(line: Int), full }

    /// A tap on the Drum Map, as Tabber Studio's remote host makes it
    /// (remote_host/tablature.py _put_drum): the drum comes off the cursor's
    /// beat when it is there; else it goes on the beat's first free line, as
    /// Studio's staff places a drum; a beat with every line taken is full.
    mutating func putDrum(_ gm: Int, at cursor: TabCursor, duration: NoteValue) -> DrumTap {
        let i = beatIndex(cursor, duration)
        var beat = bars[cursor.bar - 1][i]
        if let same = beat.notes.firstIndex(where: { $0.fret == gm }) {
            let line = beat.notes[same].string
            beat.notes.remove(at: same)
            beat.rest = beat.notes.isEmpty
            bars[cursor.bar - 1][i] = beat
            return .tookOff(line: line)
        }
        guard let line = (1...tuning.count).first(where: { l in !beat.notes.contains { $0.string == l } }) else {
            return .full
        }
        if beat.rest && beat.notes.isEmpty { beat.duration = duration }   // an empty beat takes the chosen value
        beat.notes.append(TabNote(string: line, fret: gm))
        beat.notes.sort { $0.string < $1.string }
        beat.rest = false
        bars[cursor.bar - 1][i] = beat
        return .wrote(line: line)
    }

    /// The beat under the cursor, when the bar has it.
    func beat(at cursor: TabCursor) -> TabBeat? {
        guard bars.indices.contains(cursor.bar - 1), bars[cursor.bar - 1].indices.contains(cursor.beat - 1) else { return nil }
        return bars[cursor.bar - 1][cursor.beat - 1]
    }

    /// The note on a string at the cursor's beat, for the undo label of a tap that takes it off.
    func note(on string: Int, at cursor: TabCursor) -> TabNote? {
        guard bars.indices.contains(cursor.bar - 1), bars[cursor.bar - 1].indices.contains(cursor.beat - 1) else { return nil }
        return bars[cursor.bar - 1][cursor.beat - 1].notes.first { $0.string == string }
    }

    /// The next or previous beat. Forward past the last beat fills the bar
    /// with a rest beat, or goes to the next bar, adding one at the end.
    mutating func move(_ cursor: TabCursor, by step: Int, duration: NoteValue) -> (cursor: TabCursor, changed: Bool) {
        var c = clamp(cursor)
        if step < 0 {
            if c.beat > 1 { c.beat -= 1 } else if c.bar > 1 { c.bar -= 1; c.beat = max(1, bars[c.bar - 1].count) }
            return (c, false)
        }
        if c.beat < bars[c.bar - 1].count { c.beat += 1; return (c, false) }
        if filled(c.bar) + duration.quarters <= capacity + 0.0001 {
            bars[c.bar - 1].append(TabBeat(duration: duration, rest: true, notes: []))
            c.beat = bars[c.bar - 1].count
            return (c, true)
        }
        if c.bar == bars.count {
            bars.append([TabBeat(duration: duration, rest: true, notes: [])])
            c.bar += 1; c.beat = 1
            return (c, true)
        }
        c.bar += 1; c.beat = 1
        return (c, false)
    }

    /// The cursor's bar and its neighbours, as the phone shows them.
    func window(around cursor: TabCursor) -> [TabBar] {
        let first = max(1, cursor.bar - 1), last = min(bars.count, cursor.bar + 3)
        guard first <= last else { return [] }
        return (first...last).map { TabBar(bar: $0, timeSignature: timeSignature, beats: bars[$0 - 1]) }
    }

    // MARK: the demo song

    static let standard = [64, 59, 55, 50, 45, 40]
    static let bass = [43, 38, 33, 28]

    /// Eight bars of Em, C, G, D arpeggios in eighths, then eight empty bars.
    static func demoGuitar() -> DemoTab {
        let eighth = NoteValue(value: 8)
        func bar(_ notes: [(Int, Int)]) -> [TabBeat] {
            notes.map { TabBeat(duration: eighth, rest: false, notes: [TabNote(string: $0.0, fret: $0.1)]) }
        }
        let em = bar([(6, 0), (4, 2), (3, 0), (2, 0), (1, 0), (2, 0), (3, 0), (4, 2)])
        let c = bar([(5, 3), (4, 2), (3, 0), (2, 1), (1, 0), (2, 1), (3, 0), (4, 2)])
        let g = bar([(6, 3), (5, 2), (4, 0), (3, 0), (2, 0), (1, 3), (2, 0), (3, 0)])
        let d = bar([(4, 0), (3, 2), (2, 3), (1, 2), (2, 3), (3, 2), (4, 0), (3, 2)])
        let empty = [TabBeat(duration: NoteValue(value: 4), rest: true, notes: [])]
        return DemoTab(tuning: standard, bars: [em, c, g, d, em, c, g, d] + Array(repeating: empty, count: 8))
    }

    /// Roots in quarters under the guitar.
    static func demoBass() -> DemoTab {
        let quarter = NoteValue(value: 4)
        func bar(_ string: Int, _ fret: Int) -> [TabBeat] {
            Array(repeating: TabBeat(duration: quarter, rest: false, notes: [TabNote(string: string, fret: fret)]), count: 4)
        }
        let bars = [bar(4, 0), bar(3, 3), bar(4, 3), bar(3, 5)]
        let empty = [TabBeat(duration: quarter, rest: true, notes: [])]
        return DemoTab(tuning: bass, bars: bars + bars + Array(repeating: empty, count: 8))
    }

    /// Six empty lines of drum tab, as a new drum track has them.
    static func emptyDrums(bars count: Int) -> DemoTab {
        let rest = [TabBeat(duration: NoteValue(value: 4), rest: true, notes: [])]
        return DemoTab(tuning: Array(repeating: 0, count: 6), bars: Array(repeating: rest, count: count), drum: true)
    }

    /// A rock beat in eighths under the guitar: closed hi-hat (42) on line 1,
    /// snare (38) on line 2 on two and four, bass drum (36) on line 3.
    static func demoDrums() -> DemoTab {
        let eighth = NoteValue(value: 8)
        func hits(_ lines: [(Int, Int)]) -> TabBeat {
            TabBeat(duration: eighth, rest: false, notes: lines.map { TabNote(string: $0.0, fret: $0.1) })
        }
        let groove = [hits([(1, 42), (3, 36)]), hits([(1, 42)]), hits([(1, 42), (2, 38)]), hits([(1, 42)]),
                      hits([(1, 42), (3, 36)]), hits([(1, 42), (3, 36)]), hits([(1, 42), (2, 38)]), hits([(1, 42)])]
        var tab = emptyDrums(bars: 16)
        for bar in 0..<8 { tab.bars[bar] = groove }
        return tab
    }
}
