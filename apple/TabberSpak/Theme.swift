import SwiftUI

/// Tabber Studio's design language on the phone (the owner, 2026-11-07: "spak
/// should follow the design language of Tabber Studio"). Colours are Tabber
/// Studio's own: its dark design tokens (`ui/design_tokens.py`), its record
/// and meter colours (`ui/theme.py`). Surfaces get lighter as they come
/// closer; there are no shadows, gradients or decorative edges. Teal marks
/// the one selected choice, red means recording, amber marks where the
/// playhead is. Words are sentence case; only the readout keeps Tabber
/// Studio's own labels (POS, TIME, BPM). Numbers that count are monospaced,
/// as in Tabber Studio's transport.
enum Studio {
    // Surfaces, lighter = closer
    static let bg0 = Color(red: 0x12 / 255, green: 0x12 / 255, blue: 0x19 / 255)    // the room: wells, the lamp at rest
    static let bg1 = Color(red: 0x1D / 255, green: 0x1D / 255, blue: 0x2B / 255)    // the screen
    static let bg2 = Color(red: 0x26 / 255, green: 0x26 / 255, blue: 0x38 / 255)    // the take card
    static let bg3 = Color(red: 0x30 / 255, green: 0x30 / 255, blue: 0x4A / 255)    // buttons
    static let bgOn = Color(red: 0x33 / 255, green: 0x33 / 255, blue: 0x4D / 255)   // an ON toggle in a well
    static let edge = Color.white.opacity(0.06)                                      // a panel's hairline

    // Ink
    static let text1 = Color(red: 0xEC / 255, green: 0xEC / 255, blue: 0xF3 / 255)
    static let text2 = Color(red: 0xB0 / 255, green: 0xB0 / 255, blue: 0xC4 / 255)
    static let text3 = Color(red: 0x85 / 255, green: 0x85 / 255, blue: 0xA0 / 255)
    static let textWellOff = Color(red: 0x9A / 255, green: 0x9A / 255, blue: 0xB2 / 255)

    // Signals
    static let accent = Color(red: 0x00 / 255, green: 0xD4 / 255, blue: 0xAA / 255)   // the one selected choice
    static let onAccent = Color(red: 0x0D / 255, green: 0x1F / 255, blue: 0x1A / 255)
    static let record = Color(red: 0xFF / 255, green: 0x4D / 255, blue: 0x6A / 255)   // Tabber Studio's record arm
    static let playhead = Color(red: 0xFF / 255, green: 0xB0 / 255, blue: 0x20 / 255) // where the playhead is
    static let meterLow = Color(red: 0x4C / 255, green: 0xAF / 255, blue: 0x7D / 255) // Tabber Studio's meters
    static let meterMid = Color(red: 0xFF / 255, green: 0xC1 / 255, blue: 0x07 / 255)

    // Shape: Tabber Studio's small corners, grown a little for fingers; the lamp is the largest thing.
    static let radiusLamp: CGFloat = 12
    static let radiusPanel: CGFloat = 12
    static let radiusControl: CGFloat = 7

    /// Counters (position, time, tempo, lengths) are monospaced, as in Tabber Studio's transport.
    static func counter(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

/// Tabber Studio's readout labels, POS, TIME and BPM: the only small capitals in the app.
struct ReadoutLabel: View {
    let text: String
    let color: Color
    @ScaledMetric(relativeTo: .subheadline) private var size: CGFloat = 11
    init(_ text: String, color: Color = Studio.text3) { self.text = text; self.color = color }

    var body: some View {
        Text(text)
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(color)
            .accessibilityHidden(true)
    }
}

/// The app's buttons, as Tabber Studio's: flat fills, small corners, plain words.
struct StudioButtonStyle: ButtonStyle {
    enum Kind { case normal, primary, quiet }
    var kind: Kind = .normal
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)      // a long label wraps instead of clipping
            .foregroundStyle(foreground)
            .padding(.horizontal, kind == .quiet ? 4 : 18)
            .frame(minHeight: 48)
            .background(background, in: RoundedRectangle(cornerRadius: Studio.radiusControl, style: .continuous))
            .opacity(configuration.isPressed ? 0.7 : enabled ? 1 : 0.4)
            .contentShape(.rect)
    }

    private var foreground: Color {
        switch kind {
        case .normal: Studio.text1
        case .primary: Studio.onAccent
        case .quiet: Studio.text2
        }
    }

    private var background: Color {
        switch kind {
        case .normal: Studio.bg3
        case .primary: Studio.accent
        case .quiet: .clear
        }
    }
}

extension ButtonStyle where Self == StudioButtonStyle {
    static var studio: StudioButtonStyle { StudioButtonStyle() }
    static var studioPrimary: StudioButtonStyle { StudioButtonStyle(kind: .primary) }
    static var studioQuiet: StudioButtonStyle { StudioButtonStyle(kind: .quiet) }
}

extension View {
    /// A recessed well: the darkest surface with a hairline (the toggles).
    func studioWell(radius: CGFloat = Studio.radiusControl) -> some View {
        background(Studio.bg0, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Studio.edge, lineWidth: 1))
    }

    /// A list on Tabber Studio's background, with rows on the panel surface.
    func studioList() -> some View {
        scrollContentBackground(.hidden).background(Studio.bg0)
    }
}
