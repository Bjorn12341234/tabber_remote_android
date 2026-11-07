import SwiftUI

/// Tabber Studio's design language on the phone (the owner, 2026-11-07: "spak
/// should follow the design language of Tabber Studio"). The values are Tabber
/// Studio's dark design tokens (`ui/design_tokens.py`, DARK_TOKENS): four
/// surface levels where lighter means closer, three text levels, and one rare
/// teal accent for selection and one-of-many choices. Depth comes from
/// surface lightness, never from shadows. Record keeps its red, and the
/// playhead its amber, as in Tabber Studio. Liquid Glass stays on the
/// system's floating controls (tab bar, transport, sheets) only.
enum Studio {
    // Surfaces, lighter = closer
    static let bg0 = Color(red: 0x12 / 255, green: 0x12 / 255, blue: 0x19 / 255)    // app background, wells
    static let bg1 = Color(red: 0x1D / 255, green: 0x1D / 255, blue: 0x2B / 255)    // panels, list rows
    static let bg2 = Color(red: 0x26 / 255, green: 0x26 / 255, blue: 0x38 / 255)    // raised: cards
    static let bg3 = Color(red: 0x30 / 255, green: 0x30 / 255, blue: 0x4A / 255)    // controls
    static let bgOn = Color(red: 0x33 / 255, green: 0x33 / 255, blue: 0x4D / 255)   // an ON toggle in a well
    /// A panel's 1 px edge: white at 6 % over the panel.
    static let edge = Color.white.opacity(0.06)

    // Text
    static let text1 = Color(red: 0xEC / 255, green: 0xEC / 255, blue: 0xF3 / 255)  // primary
    static let text2 = Color(red: 0xB0 / 255, green: 0xB0 / 255, blue: 0xC4 / 255)  // secondary, button labels
    static let text3 = Color(red: 0x85 / 255, green: 0x85 / 255, blue: 0xA0 / 255)  // muted labels, units

    // Accent and signals
    static let accent = Color(red: 0x00 / 255, green: 0xD4 / 255, blue: 0xAA / 255) // selection, the ON state
    static let onAccent = Color(red: 0x0D / 255, green: 0x1F / 255, blue: 0x1A / 255)
    static let record = Color(red: 0xE5 / 255, green: 0x48 / 255, blue: 0x4D / 255)
    static let playhead = Color(red: 0xFF / 255, green: 0xB0 / 255, blue: 0x20 / 255)

    static let textWellOff = Color(red: 0x9A / 255, green: 0x9A / 255, blue: 0xB2 / 255)  // OFF toggles in a well

    // Shape: Tabber Studio's corners (panel 6, well 7, button 5 px), a little larger for fingers.
    static let radiusCard: CGFloat = 10
    static let radiusControl: CGFloat = 7

    /// Tabber Studio's readouts (POS, TIME, BPM) are monospaced.
    static func readout(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

/// A small uppercase label, as Tabber Studio names its readouts and panels (POS, TIME, TRACKS).
struct StudioLabel: View {
    let text: String
    @ScaledMetric(relativeTo: .subheadline) private var size: CGFloat = 11
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: size, weight: .semibold))
            .tracking(0.8)
            .foregroundStyle(Studio.text3)
            .accessibilityLabel(text)                  // read as words, not spelled out
    }
}

extension View {
    /// A raised card in Tabber Studio's language: a lighter surface and a hairline edge, no shadow.
    func studioCard(_ fill: Color = Studio.bg2, radius: CGFloat = Studio.radiusCard) -> some View {
        background(fill, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Studio.edge, lineWidth: 1))
    }

    /// A recessed well: the darkest surface with a hairline edge (readouts, toggle groups).
    func studioWell(radius: CGFloat = Studio.radiusControl) -> some View {
        background(Studio.bg0, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Studio.edge, lineWidth: 1))
    }

    /// A track's colour as the leading edge of its row or card, as Tabber Studio's track headers have.
    func trackEdge(_ color: Color?, radius: CGFloat = Studio.radiusCard) -> some View {
        overlay(alignment: .leading) {
            Rectangle().fill(color ?? Studio.text3).frame(width: 4).accessibilityHidden(true)
        }
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }

    /// A list on Tabber Studio's background, with rows on the panel surface.
    func studioList() -> some View {
        scrollContentBackground(.hidden).background(Studio.bg0)
    }
}
