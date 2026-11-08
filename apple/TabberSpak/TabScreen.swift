import RemoteKit
import SwiftUI

/// Tabber Studio's Tab view on the phone: the chosen track's tab around the
/// cursor, the note values, and the fretboard or the piano to write with. A
/// fretboard tap writes that fret at the cursor (tap it again to take it off)
/// and the cursor stays, so more taps make a chord; Next moves on.
struct TabScreen: View {
    @Bindable var model: AppModel
    @AppStorage("tabInput") private var input = "Fretboard"

    var body: some View {
        NavigationStack {
            Connected(model: model) {
                if !model.tabAvailable {
                    Unavailable(text: "Update Tabber Studio on \(model.computerName) to write tab from this phone.")
                } else if let tab = model.state.tab {
                    editor(tab)
                } else {
                    ChooseTabTrack(model: model)
                }
            }
            .background(Studio.bg1)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarTitleMenu {
                ForEach(model.state.tracks.filter(\.hasTab)) { track in
                    Button(track.name) { model.select(track) }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { model.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                        .disabled(model.state.undo.undo == nil || !model.tabAvailable)
                        .accessibilityLabel(model.state.undo.undo.map { "Undo \($0.label)" } ?? "Undo")
                        .accessibilityIdentifier("undo")
                }
                ToolbarItem(placement: .topBarTrailing) { ComputerChip(model: model) }
            }
            .takeSlot(model: model)
        }
    }

    private var title: String {
        if let tab = model.state.tab, let track = model.state.tracks.first(where: { $0.id == tab.trackID }) { return track.name }
        return "Tab"
    }

    private func editor(_ tab: TabState) -> some View {
        ScrollView {
            VStack(spacing: 8) {
                TabStaff(model: model, tab: tab)
                HStack(spacing: 4) {
                    ForEach(NoteValue.values, id: \.self) { value in
                        ChoiceChip(title: value == 1 ? "1" : "1/\(value)", spoken: Format.value(value),
                                   chosen: tab.duration.value == value) {
                            model.tab("tab.set_duration", ["value": .number(Double(value)),
                                                           "dotted": .bool(tab.duration.dotted),
                                                           "triplet": .bool(tab.duration.triplet)])
                        }
                        .accessibilityIdentifier("value-\(value)")
                    }
                }
                HStack(spacing: 4) {
                    EditChip(title: "Dot", lit: tab.duration.dotted, spoken: "Dotted") {
                        model.tab("tab.set_duration", ["value": .number(Double(tab.duration.value)),
                                                       "dotted": .bool(!tab.duration.dotted), "triplet": .bool(tab.duration.triplet)])
                    }
                    .accessibilityIdentifier("dot")
                    EditChip(title: "Triplet", lit: tab.duration.triplet) {
                        model.tab("tab.set_duration", ["value": .number(Double(tab.duration.value)),
                                                       "dotted": .bool(tab.duration.dotted), "triplet": .bool(!tab.duration.triplet)])
                    }
                    .accessibilityIdentifier("triplet")
                    EditChip(title: "Rest", spoken: "Rest, on or off for this beat") { model.tab("tab.rest") }
                        .accessibilityIdentifier("rest")
                    EditChip(title: "Delete", spoken: "Delete the note on this string") { model.tab("tab.delete") }
                        .accessibilityIdentifier("delete-note")
                }
                HStack(spacing: 6) {
                    HoldButton(kind: .normal, tap: { model.tab("tab.move", ["by": -1]) },
                               hold: { bars in await model.fastStep(by: -1, bars: bars) }) {
                        Image(systemName: "chevron.left").frame(width: 20)
                    }
                    .accessibilityLabel("Previous beat")
                    .accessibilityHint("Hold to go back fast.")
                    .accessibilityIdentifier("previous")
                    Picker("Write with", selection: $input) {
                        Text("Fretboard").tag("Fretboard")
                        Text("Piano").tag("Piano")
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("input")
                    HoldButton(kind: .primary, tap: { model.tab("tab.move", ["by": 1]) },
                               hold: { bars in await model.fastStep(by: 1, bars: bars) }) {
                        HStack(spacing: 6) { Text("Next"); Image(systemName: "chevron.right") }
                    }
                    .accessibilityLabel("Next beat")
                    .accessibilityHint("Hold to go forward fast.")
                    .accessibilityIdentifier("next")
                }
                .padding(.top, 2)
                if input == "Piano" {
                    Piano(model: model, tab: tab)
                } else {
                    Fretboard(model: model, tab: tab)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 6)
            .padding(.bottom, 16)
        }
    }
}

/// A word button in the Tab screen's edit row; teal while its setting is on.
private struct EditChip: View {
    let title: String
    var lit = false
    var spoken: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(lit ? Studio.onAccent : Studio.text1)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(lit ? Studio.accent : Studio.bg3,
                            in: RoundedRectangle(cornerRadius: Studio.radiusControl, style: .continuous))
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(spoken ?? title)
        .accessibilityAddTraits(lit ? .isSelected : [])
    }
}

/// When the chosen track has no tab: which tracks do, and "+ Add Tab Track"
/// for a new one, as in a song of only audio (the owner, 2026-11-08). A MIDI
/// track the computer's Tab editor shows gets Tabber Studio's "MIDI part"
/// card first, so the computer never waits on it (TR39).
private struct ChooseTabTrack: View {
    @Bindable var model: AppModel

    var body: some View {
        let tabs = Array(model.state.tracks.enumerated()).filter { $0.element.hasTab }
        let chosen = model.state.tracks.first(where: \.selected)
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                let part = model.partAvailable ? model.state.view?.part.flatMap { p in chosen?.id == p.trackID ? p : nil } : nil
                if let part, let track = chosen {
                    MidiPartCard(model: model, part: part, name: track.name)
                }
                Text(tabs.isEmpty ? (model.addTrackAvailable ? "This song has no tab tracks yet. Add one to write on it here."
                                     : "This song has no tab tracks yet. Add one in Tabber Studio, then write on it here.")
                     : part != nil ? "Tab tracks to write on here:"
                     : chosen.map { "\($0.name) has no tab. Choose a track to write on:" } ?? "Choose a track to write on:")
                    .font(.body)
                    .foregroundStyle(Studio.text2)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(tabs, id: \.element.id) { index, track in
                    Button { model.select(track) } label: {
                        HStack(spacing: 10) {
                            RoundedRectangle(cornerRadius: 2.5).fill(Studio.track(track.color, index: index)).frame(width: 10, height: 10)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(track.name).font(.body.weight(.semibold)).foregroundStyle(Studio.text1)
                                Text(track.instrument ?? "Tab").font(.subheadline).foregroundStyle(Studio.text2)
                            }
                            Spacer()
                        }
                        .padding(14)
                        .frame(minHeight: 60)
                        .studioCard()
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("write-\(track.name)")
                }
                if model.addTrackAvailable {
                    Button("+ Add Tab Track") { model.addTrack(.tab) }
                        .buttonStyle(.studioGhost)
                        .disabled(model.pending.contains("add-track") || model.state.record.recording)
                        .accessibilityLabel("Add Tab Track")
                        .accessibilityHint("Adds a guitar tab track to the song on the computer, to write on here.")
                        .accessibilityIdentifier("add-tab-track")
                }
            }
            .padding(16)
        }
    }
}

/// Tabber Studio's "MIDI part" card for the chosen MIDI track, as the
/// computer's Tab editor shows it: Show standard notation, and for a melodic
/// track Show MIDI tab, pressing the computer's own buttons. Once answered,
/// what the computer shows.
private struct MidiPartCard: View {
    @Bindable var model: AppModel
    let part: ViewPart
    let name: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("MIDI part")
                .font(.headline)
                .foregroundStyle(Studio.text1)
                .accessibilityAddTraits(.isHeader)
            Text(words)
                .font(.subheadline)
                .foregroundStyle(Studio.text2)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("part-shows")
            if part.shows == "card" {
                Button("Show standard notation") { model.showPart(part.trackID, as: "notation") }
                    .buttonStyle(.studioPrimary)
                    .accessibilityHint("Shows \(name) in standard notation on the computer.")
                    .accessibilityIdentifier("show-notation")
                if part.midiTab {
                    Button("Show MIDI tab") { model.showPart(part.trackID, as: "midi_tab") }
                        .buttonStyle(.studio)
                        .accessibilityHint("Shows \(name) as tab on the computer.")
                        .accessibilityIdentifier("show-midi-tab")
                }
            }
        }
        .disabled(model.pending.contains("show-part"))
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .studioCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("midi-part")
    }

    private var words: String {
        switch part.shows {
        case "midi_tab": "The computer shows \(name) as MIDI tab."
        case "notation": "The computer shows \(name) in standard notation."
        default: "\(name) is a MIDI part. The computer waits for a choice: how should it show it?"
        }
    }
}

// MARK: the staff

/// The tab around the cursor, drawn as Tabber Studio draws it: strings 20
/// apart, fret numbers on the lines, the cursor as a teal band with a box on
/// its string. Tap a beat on a string to put the cursor there.
struct TabStaff: View {
    @Bindable var model: AppModel
    let tab: TabState
    static let gap: CGFloat = 20
    static let top: CGFloat = 26
    static let bottom: CGFloat = 14
    static let lead: CGFloat = 14

    var height: CGFloat { Self.top + Self.gap * CGFloat(max(1, tab.strings - 1)) + Self.bottom }

    static func width(_ beat: TabBeat) -> CGFloat { max(30, 40 * pow(CGFloat(beat.duration.quarters), 0.6)) }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 0) {
                    ForEach(tab.bars, id: \.bar) { bar in
                        BarView(model: model, tab: tab, bar: bar, height: height).id(bar.bar)
                    }
                }
            }
            .scrollIndicators(.hidden)
            .background(Studio.editor, in: RoundedRectangle(cornerRadius: Studio.radiusCard, style: .continuous))
            .onAppear { proxy.scrollTo(tab.cursor.bar, anchor: .center) }
            .onChange(of: tab.cursor) { _, cursor in
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(cursor.bar, anchor: .center) }
            }
        }
        .frame(height: height)
        .accessibilityIdentifier("staff")
    }
}

private struct BarView: View {
    @Bindable var model: AppModel
    let tab: TabState
    let bar: TabBar
    let height: CGFloat

    private var widths: [CGFloat] { bar.beats.map(TabStaff.width) }
    private var width: CGFloat { TabStaff.lead + max(60, widths.reduce(0, +)) + 10 }

    private func y(_ string: Int) -> CGFloat { TabStaff.top + CGFloat(string - 1) * TabStaff.gap }

    var body: some View {
        Canvas { context, size in
            let strings = tab.strings
            for s in 1...max(1, strings) {
                var line = Path()
                line.move(to: CGPoint(x: 0, y: y(s)))
                line.addLine(to: CGPoint(x: size.width, y: y(s)))
                context.stroke(line, with: .color(Studio.staffLine), lineWidth: 1)
            }
            var edge = Path()
            edge.move(to: CGPoint(x: size.width - 0.75, y: y(1)))
            edge.addLine(to: CGPoint(x: size.width - 0.75, y: y(strings)))
            context.stroke(edge, with: .color(Studio.barLine), lineWidth: 1.5)
            context.draw(Text("\(bar.bar)").font(Studio.counter(.caption2)).foregroundStyle(Studio.text3),
                         at: CGPoint(x: 4, y: 6), anchor: .topLeading)

            var x = TabStaff.lead
            for (index, beat) in bar.beats.enumerated() {
                let w = widths[index]
                let centre = x + w / 2
                if beat.notes.isEmpty {
                    let mid = (y(1) + y(strings)) / 2
                    context.fill(Path(roundedRect: CGRect(x: centre - 5, y: mid - 1.5, width: 10, height: 3), cornerRadius: 1),
                                 with: .color(Studio.text3))
                }
                for note in beat.notes {
                    let label = context.resolve(Text("\(note.fret)").font(.system(size: 15, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Studio.text1))
                    let measured = label.measure(in: CGSize(width: 60, height: 30))
                    let knock = CGRect(x: centre - measured.width / 2 - 2, y: y(note.string) - measured.height / 2,
                                       width: measured.width + 4, height: measured.height)
                    context.fill(Path(knock), with: .color(Studio.editor))
                    context.draw(label, at: CGPoint(x: centre, y: y(note.string)))
                }
                if tab.cursor.bar == bar.bar && tab.cursor.beat == index + 1 {
                    let band = CGRect(x: x + 1, y: y(1) - 12, width: w - 2, height: y(strings) - y(1) + 24)
                    context.fill(Path(roundedRect: band, cornerRadius: 3), with: .color(Studio.accent.opacity(0.16)))
                    let box = CGRect(x: centre - 13, y: y(tab.cursor.string) - 10, width: 26, height: 20)
                    context.stroke(Path(roundedRect: box, cornerRadius: 3), with: .color(Studio.accent), lineWidth: 1.5)
                }
                x += w
            }
        }
        .frame(width: width, height: height)
        .contentShape(.rect)
        .gesture(SpatialTapGesture().onEnded { tap in
            var x = TabStaff.lead
            var beat = max(1, bar.beats.count)
            for (index, w) in widths.enumerated() {
                if tap.location.x < x + w { beat = index + 1; break }
                x += w
            }
            let string = max(1, min(tab.strings, Int(((tap.location.y - TabStaff.top) / TabStaff.gap).rounded()) + 1))
            model.tab("tab.set_cursor", ["bar": .number(Double(bar.bar)), "beat": .number(Double(beat)),
                                         "string": .number(Double(string))])
        })
        .accessibilityElement()
        .accessibilityIdentifier("bar-\(bar.bar)")
        .accessibilityLabel("Bar \(bar.bar)")
        .accessibilityValue(spoken)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { model.tab("tab.set_cursor", ["bar": .number(Double(bar.bar)), "beat": 1, "string": 1]) }
    }

    private var spoken: String {
        bar.beats.enumerated().map { index, beat in
            let notes = beat.notes.isEmpty ? "rest" : beat.notes.map { "string \($0.string) fret \($0.fret)" }.joined(separator: ", ")
            let here = tab.cursor.bar == bar.bar && tab.cursor.beat == index + 1 ? ", cursor" : ""
            return "beat \(index + 1): \(notes)\(here)"
        }.joined(separator: "; ")
    }
}

// MARK: the fretboard

/// Tabber Studio's fretboard: rosewood with nickel frets, inlays at 3, 5, 7,
/// 9, 12, 15, 17, 19, 21 and 24, strings thicker toward the bottom, and the
/// cursor beat's notes as teal circles. Tap a fret on a string to write it.
struct Fretboard: View {
    @Bindable var model: AppModel
    let tab: TabState
    @State private var spokenFret = 0
    static let open: CGFloat = 38
    static let nut: CGFloat = 6
    static let fret: CGFloat = 58
    static let gap: CGFloat = 34
    static let frets = 24

    private var neck: CGFloat { Self.gap * CGFloat(tab.strings) }
    private var width: CGFloat { Self.open + Self.nut + Self.fret * CGFloat(Self.frets) }

    private func x(_ fret: Int) -> CGFloat {
        fret == 0 ? Self.open / 2 : Self.open + Self.nut + (CGFloat(fret) - 0.5) * Self.fret
    }

    private func y(_ string: Int) -> CGFloat { (CGFloat(string) - 0.5) * Self.gap }

    var body: some View {
        ScrollView(.horizontal) {
            Canvas { context, size in draw(&context) }
                .frame(width: width, height: neck + 22)
                .contentShape(.rect)
                .gesture(SpatialTapGesture().onEnded { tap in
                    let point = tap.location
                    guard point.y < neck else { return }
                    let string = max(1, min(tab.strings, Int(point.y / Self.gap) + 1))
                    let fret = point.x < Self.open + Self.nut ? 0
                        : max(1, min(Self.frets, Int((point.x - Self.open - Self.nut) / Self.fret) + 1))
                    model.tab("tab.put", ["string": .number(Double(string)), "fret": .number(Double(fret))])
                })
        }
        .scrollIndicators(.hidden)
        .accessibilityElement()
        .accessibilityLabel("Fretboard")
        .accessibilityValue("String \(tab.cursor.string), \(stringName(tab.cursor.string)), fret \(spokenFret)")
        .accessibilityHint("Swipe up or down to choose a fret, double-tap to write it.")
        .accessibilityAdjustableAction { direction in
            spokenFret = max(0, min(Self.frets, spokenFret + (direction == .increment ? 1 : -1)))
        }
        .accessibilityAction { model.tab("tab.put", ["string": .number(Double(tab.cursor.string)), "fret": .number(Double(spokenFret))]) }
        .accessibilityAction(named: "Higher string") {
            model.tab("tab.set_cursor", ["bar": .number(Double(tab.cursor.bar)), "beat": .number(Double(tab.cursor.beat)),
                                         "string": .number(Double(max(1, tab.cursor.string - 1)))])
        }
        .accessibilityAction(named: "Lower string") {
            model.tab("tab.set_cursor", ["bar": .number(Double(tab.cursor.bar)), "beat": .number(Double(tab.cursor.beat)),
                                         "string": .number(Double(min(tab.strings, tab.cursor.string + 1)))])
        }
        .accessibilityIdentifier("fretboard")
    }

    private func stringName(_ string: Int) -> String {
        guard tab.tuning.indices.contains(string - 1) else { return "" }
        return Format.noteNames[tab.tuning[string - 1] % 12]
    }

    private func draw(_ context: inout GraphicsContext) {
        let left = Self.open + Self.nut
        let board = CGRect(x: left, y: 0, width: width - left, height: neck)
        context.fill(Path(roundedRect: board, cornerRadius: 2),
                     with: .linearGradient(Gradient(colors: [Studio.woodEdge, Studio.woodCentre, Studio.wood, Studio.woodEdge]),
                                           startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 0, y: neck)))
        context.fill(Path(CGRect(x: Self.open, y: 0, width: Self.nut, height: neck)), with: .color(Studio.nut))
        for fret in 1...Self.frets {
            let fx = left + CGFloat(fret) * Self.fret
            context.fill(Path(CGRect(x: fx - 0.75, y: 0, width: 1.5, height: neck)), with: .color(Studio.fret))
        }
        for fret in [3, 5, 7, 9, 15, 17, 19, 21] {
            context.fill(Path(ellipseIn: CGRect(x: x(fret) - 5, y: neck / 2 - 5, width: 10, height: 10)), with: .color(Studio.inlay))
        }
        for fret in [12, 24] {
            for fraction in [0.3, 0.7] {
                context.fill(Path(ellipseIn: CGRect(x: x(fret) - 5, y: neck * fraction - 5, width: 10, height: 10)),
                             with: .color(Studio.inlay))
            }
        }
        for string in 1...max(1, tab.strings) {
            let thickness = 0.8 + 0.3 * CGFloat(string - 1)
            context.fill(Path(CGRect(x: left - Self.nut, y: y(string) - thickness / 2, width: width - left + Self.nut, height: thickness)),
                         with: .color(Studio.string))
        }
        let notes = tab.cursorBeat?.notes ?? []
        for string in 1...max(1, tab.strings) {
            let name = Text(stringName(string)).font(Studio.counter(.caption, weight: .semibold))
            let open = notes.contains { $0.string == string && $0.fret == 0 }
            if open {
                context.fill(Path(ellipseIn: CGRect(x: x(0) - 12, y: y(string) - 12, width: 24, height: 24)), with: .color(Studio.openNote))
                context.draw(name.foregroundStyle(Studio.onAccent), at: CGPoint(x: x(0), y: y(string)))
            } else {
                context.draw(name.foregroundStyle(string == tab.cursor.string ? Studio.accent : Studio.text3),
                             at: CGPoint(x: x(0), y: y(string)))
            }
            if string == tab.cursor.string {
                context.stroke(Path(ellipseIn: CGRect(x: x(0) - 13, y: y(string) - 13, width: 26, height: 26)),
                               with: .color(Studio.accent), lineWidth: 1.5)
            }
        }
        for note in notes where note.fret > 0 {
            let centre = CGPoint(x: x(note.fret), y: y(note.string))
            context.fill(Path(ellipseIn: CGRect(x: centre.x - 12, y: centre.y - 12, width: 24, height: 24)), with: .color(Studio.accent))
            context.draw(Text("\(note.fret)").font(.system(size: 13, weight: .bold).monospacedDigit()).foregroundStyle(Studio.onAccent), at: centre)
        }
        for fret in [1, 3, 5, 7, 9, 12, 15, 17, 19, 21, 24] {
            context.draw(Text("\(fret)").font(Studio.counter(.caption2)).foregroundStyle(Studio.text3),
                         at: CGPoint(x: x(fret), y: neck + 12))
        }
    }
}

// MARK: the piano

/// Tabber Studio's piano: 88 keys, A0 to C8, C keys named, the cursor beat's
/// pitches lit teal. A key writes its pitch at the cursor on the string that
/// plays it lowest.
struct Piano: View {
    @Bindable var model: AppModel
    let tab: TabState
    @State private var position = ScrollPosition()
    @State private var spokenPitch = 60
    static let lowest = 21
    static let highest = 108
    static let white: CGFloat = 38
    static let height: CGFloat = 170

    private static let whites: [Int] = (lowest...highest).filter { [0, 2, 4, 5, 7, 9, 11].contains($0 % 12) }
    private static let blacks: [Int] = (lowest...highest).filter { ![0, 2, 4, 5, 7, 9, 11].contains($0 % 12) }

    private static func whiteIndex(_ pitch: Int) -> Int { whites.firstIndex(of: pitch) ?? 0 }
    /// A black key sits on the line between its white neighbours.
    private static func blackCentre(_ pitch: Int) -> CGFloat { CGFloat(whiteIndex(pitch + 1)) * white }

    var body: some View {
        let width = CGFloat(Self.whites.count) * Self.white
        let lit = Set((tab.cursorBeat?.notes ?? []).compactMap { tab.pitch(string: $0.string, fret: $0.fret) })
        ScrollView(.horizontal) {
            Canvas { context, _ in
                for pitch in Self.whites {
                    let rect = CGRect(x: CGFloat(Self.whiteIndex(pitch)) * Self.white, y: 0, width: Self.white - 1, height: Self.height)
                    let shape = Path(roundedRect: rect, cornerRadius: 2)
                    if lit.contains(pitch) {
                        context.fill(shape, with: .color(Studio.accent))
                    } else {
                        context.fill(shape, with: .linearGradient(Gradient(colors: [Studio.keyTop, Studio.keyBottom]),
                                                                  startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 0, y: Self.height)))
                    }
                    context.stroke(shape, with: .color(Studio.keyBorder), lineWidth: 1)
                    if pitch % 12 == 0 {
                        context.draw(Text(Format.note(pitch)).font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(Studio.rgb(90, 90, 110)),
                                     at: CGPoint(x: rect.midX, y: Self.height - 12))
                    }
                }
                let bw = Self.white * 0.58, bh = Self.height * 0.6
                for pitch in Self.blacks {
                    let rect = CGRect(x: Self.blackCentre(pitch) - bw / 2, y: 0, width: bw, height: bh)
                    let shape = Path(roundedRect: rect, cornerRadius: 2)
                    if lit.contains(pitch) {
                        context.fill(shape, with: .color(Studio.accent))
                    } else {
                        context.fill(shape, with: .linearGradient(Gradient(colors: [Studio.blackTop, Studio.blackBottom]),
                                                                  startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 0, y: bh)))
                    }
                }
            }
            .frame(width: width, height: Self.height)
            .contentShape(.rect)
            .gesture(SpatialTapGesture().onEnded { tap in
                if let pitch = Self.pitch(at: tap.location) {
                    model.tab("tab.put_pitch", ["pitch": .number(Double(pitch))])
                }
            })
        }
        .scrollPosition($position)
        .scrollIndicators(.hidden)
        .onAppear {
            let low = tab.tuning.min() ?? 40
            position.scrollTo(x: max(0, CGFloat(Self.whiteIndex(low - low % 12)) * Self.white - Self.white))
        }
        .accessibilityElement()
        .accessibilityLabel("Piano")
        .accessibilityValue(Format.note(spokenPitch))
        .accessibilityHint("Swipe up or down to choose a note, double-tap to write it.")
        .accessibilityAdjustableAction { direction in
            spokenPitch = max(Self.lowest, min(Self.highest, spokenPitch + (direction == .increment ? 1 : -1)))
        }
        .accessibilityAction { model.tab("tab.put_pitch", ["pitch": .number(Double(spokenPitch))]) }
        .accessibilityIdentifier("piano")
    }

    private static func pitch(at point: CGPoint) -> Int? {
        let bw = white * 0.58, bh = height * 0.6
        if point.y < bh, let black = blacks.first(where: { abs(blackCentre($0) - point.x) <= bw / 2 }) { return black }
        let index = Int(point.x / white)
        return whites.indices.contains(index) ? whites[index] : nil
    }
}
