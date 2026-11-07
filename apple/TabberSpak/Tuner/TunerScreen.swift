import RemoteKit
import SwiftUI

/// Tabber Tuner: the note the instrument plays, how far off it is, and which
/// of the chosen track's strings it is. It works with or without a computer.
struct TunerScreen: View {
    @Bindable var model: AppModel
    @State private var tuner = TunerModel()
    @AppStorage("tunerAsked") private var asked = false

    /// The chosen track's strings when it has tab, else a standard guitar.
    private var source: (name: String, tuning: [Int]) {
        if let track = model.state.tracks.first(where: \.selected), let tuning = track.tuning {
            return ("Strings of \(track.name)", tuning)
        }
        return ("Standard tuning", [64, 59, 55, 50, 45, 40])
    }

    var body: some View {
        NavigationStack {
            Group {
                if model.isDemo || tuner.access == .granted {
                    tuning
                } else if tuner.access == .denied {
                    ask(text: "Tabber Spak can't hear your instrument. Turn on the microphone for Tabber Spak in Settings.",
                        button: "Open Settings") { FixItView.openSettings() }
                } else {
                    ask(text: "The tuner listens to your instrument through this iPhone's microphone. Nothing is recorded, and the sound never leaves the phone.",
                        button: "Start tuning") { Task { await tuner.start(demo: false) } }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Studio.bg1)
            .navigationTitle("Tuner")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { ComputerChip(model: model) } }
        }
        .onAppear {
            tuner.tuning = source.tuning
            if model.isDemo || tuner.access == .granted { Task { await tuner.start(demo: model.isDemo) } }
        }
        .onDisappear { tuner.stop() }
        .onChange(of: source.tuning) { _, strings in tuner.tuning = strings }
    }

    private var tuning: some View {
        ScrollView {
            VStack(spacing: 28) {
                TunerDial(reading: tuner.reading)
                    .frame(height: 300)
                StringsRow(tuning: tuner.tuning, lit: tuner.reading?.string,
                           inTune: abs(tuner.reading?.cents ?? 99) <= TunerModel.inTune)
                VStack(spacing: 6) {
                    Text(tuner.reading.map { String(format: "%.2f Hz", $0.frequency) } ?? " ")
                        .font(Studio.counter(.footnote))
                        .foregroundStyle(Studio.text2)
                        .accessibilityHidden(true)
                    Text("\(source.name), A4 = \(Int(tuner.reference)) Hz")
                        .font(.footnote)
                        .foregroundStyle(Studio.text2)
                        .accessibilityIdentifier("tuner-strings")
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
    }

    private func ask(text: String, button: String, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(text)
                .font(.body)
                .foregroundStyle(Studio.text2)
                .fixedSize(horizontal: false, vertical: true)
            Button(button, action: action)
                .buttonStyle(.studioPrimary)
                .accessibilityIdentifier("tuner-start")
        }
        .padding(24)
    }
}

/// The note, and a needle on a cents scale from -50 to +50: teal once it is
/// within three cents. Drawn; it tells VoiceOver the note and how far off it is.
struct TunerDial: View {
    let reading: TunerModel.Reading?

    var body: some View {
        Canvas { context, size in
            let inTune = reading.map { abs($0.cents) <= TunerModel.inTune } ?? false
            let ink = inTune ? Studio.accent : Studio.text1
            // The note, the one large thing on the screen
            if let reading {
                let note = context.resolve(Text(reading.note).font(.system(size: 120, weight: .semibold)).foregroundStyle(ink))
                let size120 = note.measure(in: size)
                context.draw(note, at: CGPoint(x: size.width / 2, y: 92))
                context.draw(Text("\(reading.octave)").font(.system(size: 30, weight: .semibold)).foregroundStyle(Studio.text2),
                             at: CGPoint(x: size.width / 2 + size120.width / 2 + 6, y: 128), anchor: .leading)
                let words = inTune ? "In tune" : String(format: "%.0f cents %@", abs(reading.cents), reading.cents < 0 ? "flat" : "sharp")
                context.draw(Text(words).font(.system(size: 17, weight: .semibold)).foregroundStyle(inTune ? Studio.accent : Studio.text2),
                             at: CGPoint(x: size.width / 2, y: 178))
            } else {
                context.draw(Text("Play a string").font(.system(size: 22, weight: .semibold)).foregroundStyle(Studio.text2),
                             at: CGPoint(x: size.width / 2, y: 100))
            }
            // The scale
            let left: CGFloat = 12, right = size.width - 12, base: CGFloat = 250
            func x(_ cents: Double) -> CGFloat { left + (right - left) * CGFloat((cents + 50) / 100) }
            context.fill(Path(roundedRect: CGRect(x: x(-TunerModel.inTune), y: base - 34, width: x(TunerModel.inTune) - x(-TunerModel.inTune),
                                                  height: 40), cornerRadius: 3),
                         with: .color(Studio.accent.opacity(0.16)))
            for cents in stride(from: -50, through: 50, by: 5) {
                let major = cents % 25 == 0
                let height: CGFloat = cents == 0 ? 40 : major ? 24 : 12
                context.fill(Path(CGRect(x: x(Double(cents)) - 0.75, y: base - height + 6, width: 1.5, height: height)),
                             with: .color(cents == 0 ? Studio.accent : Studio.staffLine))
                if major {
                    context.draw(Text(cents == 0 ? "0" : String(format: "%+d", cents)).font(.system(size: 11, weight: .medium).monospacedDigit())
                                    .foregroundStyle(Studio.text2),
                                 at: CGPoint(x: x(Double(cents)), y: base + 20))
                }
            }
            if let reading {
                let needle = x(max(-50, min(50, reading.cents)))
                context.fill(Path(roundedRect: CGRect(x: needle - 2.5, y: base - 44, width: 5, height: 54), cornerRadius: 2.5),
                             with: .color(ink))
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Tuner")
        .accessibilityValue(spoken)
        .accessibilityAddTraits(.updatesFrequently)
        .accessibilityIdentifier("tuner-dial")
    }

    private var spoken: String {
        guard let reading else { return "Play a string" }
        if abs(reading.cents) <= TunerModel.inTune { return "\(reading.note)\(reading.octave), in tune" }
        return "\(reading.note)\(reading.octave), \(Int(abs(reading.cents).rounded())) cents \(reading.cents < 0 ? "flat" : "sharp")"
    }
}

/// The strings, low to high as they face the player; the one being tuned is lit.
struct StringsRow: View {
    let tuning: [Int]
    let lit: Int?
    let inTune: Bool

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(tuning.enumerated().reversed()), id: \.offset) { index, pitch in
                let on = lit == index + 1
                Text(Format.noteNames[pitch % 12])
                    .font(Studio.counter(.headline, weight: .semibold))
                    .foregroundStyle(on ? Studio.onAccent : Studio.text1)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(on ? (inTune ? Studio.accent : Studio.text2) : Studio.bg2,
                                in: RoundedRectangle(cornerRadius: Studio.radiusControl, style: .continuous))
            }
        }
        .accessibilityHidden(true)
    }
}
