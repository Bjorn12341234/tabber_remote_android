import RemoteKit
import SwiftUI

/// Tabber Studio's design language on the phone. Every colour is Tabber
/// Studio's own: its dark design tokens (ui/design_tokens.py), its record,
/// solo, mute and meter colours and the fretboard's rosewood and the piano's
/// keys (ui/theme.py), and its twelve track colours (core/models.py).
/// Surfaces get lighter as they come closer; there are no shadows, glows or
/// decorative edges. Teal marks the one selected thing, red means recording,
/// amber marks where the playhead is. Words are sentence case; only Tabber
/// Studio's own readout labels (POS, TIME, BPM) are capitals.
enum Studio {
    // Surfaces, lighter = closer
    static let bg0 = rgb(0x12, 0x12, 0x19)       // wells, the readout
    static let bg1 = rgb(0x1D, 0x1D, 0x2B)       // the screen
    static let bg2 = rgb(0x26, 0x26, 0x38)       // track cards, strips, the take card
    static let bg3 = rgb(0x30, 0x30, 0x4A)       // buttons
    static let bgOn = rgb(0x3D, 0x3D, 0x5C)      // a toggle that is on
    static let edge = Color.white.opacity(0.06)
    static let editor = rgb(0x22, 0x22, 0x3B)    // the tab editor's paper
    static let staffLine = rgb(0x5C, 0x5C, 0x7C)
    static let barLine = rgb(0x6E, 0x6E, 0x90)

    // Ink
    static let text1 = rgb(0xEC, 0xEC, 0xF3)
    static let text2 = rgb(0xB0, 0xB0, 0xC4)
    static let text3 = rgb(0x85, 0x85, 0xA0)

    // Signals
    static let accent = rgb(0x00, 0xD4, 0xAA)    // the one selected thing
    static let onAccent = rgb(0x0D, 0x1F, 0x1A)
    static let record = rgb(0xFF, 0x4D, 0x6A)    // record arm, recording
    static let playhead = rgb(0xFF, 0xB0, 0x20)
    static let solo = rgb(0xD4, 0xA2, 0x4C)
    static let mute = rgb(0x5D, 0x6D, 0x90)
    static let meterLow = rgb(0x4C, 0xAF, 0x7D)
    static let meterMid = rgb(0xFF, 0xC1, 0x07)

    // The fretboard (dark theme): rosewood, nickel frets, a bone nut
    static let woodEdge = rgb(44, 31, 21)
    static let wood = rgb(72, 48, 28)
    static let woodCentre = rgb(85, 61, 40)
    static let fret = rgb(154, 147, 135)
    static let nut = rgb(240, 238, 228)
    static let string = rgb(210, 210, 205)
    static let inlay = rgb(216, 207, 189).opacity(0.6)
    static let openNote = rgb(0, 180, 130)

    // The piano
    static let keyTop = rgb(235, 232, 222)
    static let keyBottom = rgb(215, 212, 200)
    static let blackTop = rgb(30, 30, 35)
    static let blackBottom = rgb(50, 50, 55)
    static let keyBorder = rgb(60, 60, 80)

    // Shape: Tabber Studio's small corners, grown a little for fingers.
    static let radiusCard: CGFloat = 8
    static let radiusControl: CGFloat = 6

    /// Tabber Studio's twelve track colours, for a track that sends none.
    static let tracks: [Color] = [rgb(80, 160, 220), rgb(100, 190, 100), rgb(220, 170, 60), rgb(170, 100, 210),
                                  rgb(154, 134, 214), rgb(220, 80, 80), rgb(220, 130, 70), rgb(150, 190, 60),
                                  rgb(200, 100, 160), rgb(100, 140, 200), rgb(190, 160, 100), rgb(210, 200, 80)]

    static func track(_ hex: String?, index: Int) -> Color {
        Color(hex: hex) ?? tracks[index % tracks.count]
    }

    /// Counters (position, time, levels, frets) are monospaced, as in Tabber
    /// Studio's transport, and grow with Dynamic Type.
    static func counter(_ style: Font.TextStyle, weight: Font.Weight = .medium) -> Font {
        .system(style, design: .monospaced, weight: weight)
    }

    static func rgb(_ r: Int, _ g: Int, _ b: Int) -> Color {
        Color(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255)
    }
}

extension Color {
    init?(hex: String?) {
        guard let hex, hex.count == 7, hex.hasPrefix("#"), let value = UInt32(hex.dropFirst(), radix: 16) else { return nil }
        self.init(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255,
                  blue: Double(value & 0xFF) / 255)
    }
}

/// Tabber Studio's readout labels, POS, TIME and BPM: the only capitals in the app.
struct ReadoutLabel: View {
    let text: String
    var color: Color = Studio.text2
    @ScaledMetric(relativeTo: .subheadline) private var size: CGFloat = 10
    init(_ text: String, color: Color = Studio.text2) { self.text = text; self.color = color }

    var body: some View {
        Text(text)
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(color)
            .accessibilityHidden(true)
    }
}

/// The app's buttons, as Tabber Studio's: flat fills, small corners, plain words.
struct StudioButtonStyle: ButtonStyle {
    enum Kind { case normal, primary, quiet, destructive }
    var kind: Kind = .normal
    var minHeight: CGFloat = 44
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .foregroundStyle(foreground)
            .padding(.horizontal, kind == .quiet ? 4 : 16)
            .frame(minHeight: minHeight)
            .background(background, in: RoundedRectangle(cornerRadius: Studio.radiusControl, style: .continuous))
            .opacity(configuration.isPressed ? 0.7 : enabled ? 1 : 0.4)
            .contentShape(.rect)
    }

    private var foreground: Color {
        switch kind {
        case .normal: Studio.text1
        case .primary: Studio.onAccent
        case .quiet: Studio.text2
        case .destructive: Studio.record
        }
    }

    private var background: Color {
        switch kind {
        case .normal, .destructive: Studio.bg3
        case .primary: Studio.accent
        case .quiet: .clear
        }
    }
}

/// A Studio button that repeats while held: a tap is one step; held, it
/// steps by itself, faster, then a whole bar at a time, until it is let go
/// or `hold` says there is nowhere further to go.
struct HoldButton<Label: View>: View {
    var kind: StudioButtonStyle.Kind = .normal
    let tap: () -> Void
    /// One held step; `bars` once it has run a while. False ends the hold.
    let hold: @MainActor (_ bars: Bool) async -> Bool
    @ViewBuilder let label: () -> Label
    @State private var task: Task<Void, Never>?
    @State private var held = false

    var body: some View {
        label()
            .font(.body.weight(.semibold))
            .foregroundStyle(kind == .primary ? Studio.onAccent : Studio.text1)
            .padding(.horizontal, 16)
            .frame(minHeight: 44)
            .background(kind == .primary ? Studio.accent : Studio.bg3,
                        in: RoundedRectangle(cornerRadius: Studio.radiusControl, style: .continuous))
            .opacity(task != nil ? 0.7 : 1)
            .contentShape(.rect)
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard task == nil else { return }
                    held = false
                    task = Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(400))
                        guard !Task.isCancelled else { return }
                        held = true
                        var steps = 0
                        while !Task.isCancelled, await hold(steps >= 12) {
                            steps += 1
                            try? await Task.sleep(for: .milliseconds(steps < 6 ? 140 : 70))
                        }
                    }
                }
                .onEnded { _ in
                    task?.cancel()
                    task = nil
                    if !held { tap() }
                    held = false
                })
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { tap() }
    }
}

extension ButtonStyle where Self == StudioButtonStyle {
    static var studio: StudioButtonStyle { StudioButtonStyle() }
    static var studioPrimary: StudioButtonStyle { StudioButtonStyle(kind: .primary) }
    static var studioQuiet: StudioButtonStyle { StudioButtonStyle(kind: .quiet) }
    static var studioDestructive: StudioButtonStyle { StudioButtonStyle(kind: .destructive) }
}

/// Tabber Studio's toggles (Loop, Count-in, Metro, Dot): a word that is lit when on.
struct ToggleChip: View {
    let title: String
    let isOn: Bool
    var spoken: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isOn ? Studio.text1 : Studio.text2)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(isOn ? Studio.bgOn : Color.clear,
                            in: RoundedRectangle(cornerRadius: Studio.radiusControl, style: .continuous))
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(spoken ?? title)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// A choice among several (note values): the chosen one is teal, as in Tabber Studio's toolbar.
struct ChoiceChip: View {
    let title: String
    let spoken: String
    let chosen: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Studio.counter(.subheadline, weight: .semibold))
                .foregroundStyle(chosen ? Studio.onAccent : Studio.text1)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(chosen ? Studio.accent : Studio.bg3,
                            in: RoundedRectangle(cornerRadius: Studio.radiusControl, style: .continuous))
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(spoken)
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }
}

/// Tabber Studio's S and M: a letter on a small square, filled when on.
struct LetterButton: View {
    let letter: String
    let isOn: Bool
    let onColor: Color
    let spoken: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(letter)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(isOn ? Studio.bg0 : Studio.text2)
                .fixedSize()
                .frame(minWidth: 34, minHeight: 30)
                .background(isOn ? onColor : Studio.bg3,
                            in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(spoken)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// Tabber Studio's record arm: an empty ring, a red dot when armed.
struct ArmButton: View {
    let armed: Bool
    let spoken: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(armed ? Studio.record.opacity(0.18) : Studio.bg3)
                    .frame(width: 34, height: 30)
                if armed {
                    Circle().fill(Studio.record).frame(width: 13, height: 13)
                } else {
                    Circle().strokeBorder(Studio.text2, lineWidth: 1.6).frame(width: 13, height: 13)
                }
            }
            .frame(width: 44, height: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(spoken)
        .accessibilityAddTraits(armed ? .isSelected : [])
    }
}

/// A level, green to -12 dB, yellow to -6, red above, as Tabber Studio's meters.
struct LevelMeter: View {
    let level: Double
    var vertical = false

    static func fraction(_ db: Double) -> Double { min(1, max(0, (db + 60) / 60)) }
    var fraction: Double { level > 0 ? Self.fraction(20 * log10(level)) : 0 }

    var body: some View {
        GeometryReader { proxy in
            let length = vertical ? proxy.size.height : proxy.size.width
            let yellow = Self.fraction(-12), red = Self.fraction(-6)
            let bands = Group {
                Rectangle().fill(Studio.meterLow).frame(width: vertical ? nil : length * yellow,
                                                       height: vertical ? length * yellow : nil)
                Rectangle().fill(Studio.meterMid).frame(width: vertical ? nil : length * (red - yellow),
                                                       height: vertical ? length * (red - yellow) : nil)
                Rectangle().fill(Studio.record)
            }
            ZStack(alignment: vertical ? .bottom : .leading) {
                Rectangle().fill(Studio.bg0)
                Group {
                    if vertical {
                        VStack(spacing: 0) { bands }.rotationEffect(.degrees(180))
                    } else {
                        HStack(spacing: 0) { bands }
                    }
                }
                .mask(alignment: vertical ? .bottom : .leading) {
                    Rectangle().frame(width: vertical ? nil : length * fraction, height: vertical ? length * fraction : nil)
                }
                .animation(.linear(duration: 0.08), value: fraction)
            }
            .clipShape(RoundedRectangle(cornerRadius: 2))
        }
        .accessibilityHidden(true)
    }
}

extension View {
    /// A recessed well: the darkest surface with a hairline (the toggles, the readout).
    func studioWell(radius: CGFloat = Studio.radiusControl) -> some View {
        background(Studio.bg0, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Studio.edge, lineWidth: 1))
    }

    /// A list on Tabber Studio's background.
    func studioList() -> some View {
        scrollContentBackground(.hidden).background(Studio.bg1)
    }

    /// A card: Tabber Studio's panel surface with its hairline.
    func studioCard(selected: Bool = false) -> some View {
        background(Studio.bg2, in: RoundedRectangle(cornerRadius: Studio.radiusCard, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Studio.radiusCard, style: .continuous)
                .strokeBorder(selected ? Studio.accent : Studio.edge, lineWidth: selected ? 1.5 : 1))
    }
}

/// Words for times, lengths and levels, as Tabber Studio writes them.
enum Format {
    /// Tabber Studio's position: "25 : 1".
    static func position(_ position: Position) -> String { "\(position.bar) : \(position.beat)" }

    /// m:ss, for a take or a recording.
    static func clock(_ seconds: Double) -> String {
        let whole = max(0, Int(seconds))
        return "\(whole / 60):" + String(format: "%02d", whole % 60)
    }

    /// "42 seconds", "1 minute 5 seconds".
    static func length(_ seconds: Double) -> String {
        let whole = max(1, Int(seconds.rounded()))
        let minutes = whole / 60, rest = whole % 60
        let s = rest == 1 ? "1 second" : "\(rest) seconds"
        if minutes == 0 { return s }
        let m = minutes == 1 ? "1 minute" : "\(minutes) minutes"
        return rest == 0 ? m : "\(m) \(s)"
    }

    static func bpm(_ transport: TransportState) -> String {
        let value = transport.tempoBPM * transport.tempoScale
        return value == value.rounded() ? "\(Int(value))" : String(format: "%.1f", value)
    }

    /// A fader's level: "+0.0", "-12.0", "-∞".
    static func db(_ value: Double?) -> String {
        guard let value else { return "-∞" }
        return (value >= 0 ? "+" : "") + String(format: "%.1f", value)
    }

    static let noteNames = ["C", "C♯", "D", "E♭", "E", "F", "F♯", "G", "G♯", "A", "B♭", "B"]

    /// A MIDI note's name: "E2", "C♯4".
    static func note(_ pitch: Int) -> String { "\(noteNames[((pitch % 12) + 12) % 12])\(pitch / 12 - 1)" }

    /// A note value in words, for VoiceOver.
    static func value(_ value: Int) -> String {
        switch value {
        case 1: "Whole note"
        case 2: "Half note"
        case 4: "Quarter note"
        case 8: "Eighth note"
        case 16: "Sixteenth note"
        default: "Thirty-second note"
        }
    }
}
