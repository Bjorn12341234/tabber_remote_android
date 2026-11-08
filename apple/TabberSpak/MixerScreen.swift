import RemoteKit
import SwiftUI

/// Tabber Studio's mixer: a strip for every track, then the buses and the
/// master, each with pan, S and M, a fader on Tabber Studio's scale and its
/// meter. Double-tap a fader for 0 dB, a pan knob for the centre. Routing is
/// the Mixer's other view, as Tabber Studio's Routing panel can be a tab
/// beside its Mixer.
struct MixerScreen: View {
    enum Page: String { case mixer = "Mixer", routing = "Routing" }

    @Bindable var model: AppModel
    @State private var page = Page.mixer

    var body: some View {
        NavigationStack {
            Connected(model: model) {
                if !model.mixerAvailable {
                    Unavailable(text: "Update Tabber Studio on \(model.computerName) to use its mixer from this phone.")
                } else if page == .routing, model.routingAvailable {
                    if let routing = model.state.routing {
                        RoutingView(model: model, routing: routing)
                    }
                } else if let mixer = model.state.mixer {
                    GeometryReader { proxy in
                        ScrollViewReader { strips in
                            ScrollView(.horizontal) {
                                HStack(alignment: .top, spacing: 8) {
                                    ForEach(Array(mixer.strips.enumerated()), id: \.element.id) { index, strip in
                                        StripView(model: model, strip: strip, scale: mixer.scale, unity: mixer.unity, index: index)
                                            .id(strip.id)
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .frame(height: proxy.size.height)
                            }
                            .scrollIndicators(.hidden)
                            // A bus added from here comes into view.
                            .onChange(of: model.addedBusID) { _, added in
                                guard let added else { return }
                                withAnimation { strips.scrollTo(added, anchor: .center) }
                            }
                        }
                    }
                }
            }
            // Mixer or Routing, under the bar and always in view: in the bar it
            // ran into Undo and the computer's name (the owner, 2026-11-08).
            .safeAreaInset(edge: .top, spacing: 0) {
                if model.mixerAvailable, model.isConnected, model.routingAvailable || model.addBusAvailable {
                    HStack(spacing: 8) {
                        if model.routingAvailable {
                            Picker("View", selection: $page) {
                                Text(Page.mixer.rawValue).tag(Page.mixer)
                                Text(Page.routing.rawValue).tag(Page.routing)
                            }
                            .pickerStyle(.segmented)
                            .accessibilityIdentifier("mixer-page")
                        }
                        if model.addBusAvailable {
                            AddBusButton(model: model)       // the mixer header's own "+ Bus"
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Studio.bg1)
                }
            }
            .background(Studio.bg1)
            .navigationTitle(model.routingAvailable ? "" : "Mixer")    // the switch under the bar says which
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { model.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                        .disabled(model.state.undo.undo == nil || !model.mixerAvailable)
                        .accessibilityLabel(model.state.undo.undo.map { "Undo \($0.label)" } ?? "Undo")
                        .accessibilityIdentifier("undo")
                }
                ToolbarItem(placement: .topBarTrailing) { ComputerChip(model: model) }
            }
            .takeSlot(model: model)
            .onAppear { model.watchMixerMeters(true) }
            .onDisappear { model.watchMixerMeters(false) }
        }
    }
}

/// Tabber Studio's mixer "+ Bus" and its New Bus dialog: name the bus, and it
/// joins the mixer and the routing at once (not an undo step, as there).
struct AddBusButton: View {
    @Bindable var model: AppModel
    @State private var naming = false
    @State private var name = ""

    var body: some View {
        Button("+ Bus") {
            name = ""
            naming = true
        }
        .buttonStyle(.studioGhostCompact)
        .disabled(model.pending.contains("add-bus"))
        .accessibilityLabel("Add Bus")
        .accessibilityHint("Adds a bus to the mixer on the computer.")
        .accessibilityIdentifier("add-bus")
        .alert("New Bus", isPresented: $naming) {
            TextField("Bus name", text: $name)
                .accessibilityIdentifier("bus-name")
            Button("Add Bus") { model.addBus(name) }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Bus name:")
        }
        .tint(Studio.text1)        // plain words, as Studio's dialog: teal is for what is selected
    }
}

/// One channel strip, top to bottom as in Tabber Studio's mixer.
struct StripView: View {
    @Bindable var model: AppModel
    let strip: Strip
    let scale: [ScaleMark]
    let unity: Double
    let index: Int
    @State private var dragVolume: Double?
    @State private var dragStart: Double?
    @State private var dragPan: Double?
    @State private var panStart: Double?

    var body: some View {
        let volume = dragVolume ?? strip.volume
        let pan = dragPan ?? strip.pan
        VStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(strip.isMaster ? Studio.bg3 : tint.opacity(0.3))
                Text(strip.name)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Studio.text1)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 6)
                    .accessibilityAddTraits(.isHeader)
            }
            .frame(maxWidth: .infinity, minHeight: 34)
            .fixedSize(horizontal: false, vertical: true)       // the name's height, not the strip's

            if !strip.isMaster {
                PanKnob(pan: pan, label: dragPan.map(PanLabel.pan) ?? strip.panLabel)
                    .gesture(DragGesture(minimumDistance: 2)
                        .onChanged { drag in
                            let start = panStart ?? strip.pan
                            panStart = start
                            let next = max(-1, min(1, start + Double(drag.translation.width - drag.translation.height) / 120))
                            dragPan = next
                            model.setPan(strip.id, next)
                        }
                        .onEnded { _ in
                            panStart = nil
                            Task { try? await Task.sleep(for: .milliseconds(400)); dragPan = nil }
                        })
                    .onTapGesture(count: 2) { model.setPan(strip.id, 0) }
                    .accessibilityElement()
                    .accessibilityLabel("Pan \(strip.name)")
                    .accessibilityValue(spokenPan(strip.panLabel))
                    .accessibilityAdjustableAction { direction in
                        let step = direction == .increment ? 0.1 : -0.1
                        model.setPan(strip.id, max(-1, min(1, strip.pan + step)))
                    }
                    .accessibilityIdentifier("pan-\(strip.name)")

                HStack(spacing: 0) {
                    LetterButton(letter: "S", isOn: strip.soloed, onColor: Studio.solo,
                                 spoken: strip.soloed ? "Stop hearing \(strip.name) alone" : "Hear \(strip.name) alone") {
                        model.solo(strip.id)
                    }
                    .accessibilityIdentifier("strip-solo-\(strip.name)")
                    LetterButton(letter: "M", isOn: strip.muted, onColor: Studio.mute,
                                 spoken: strip.muted ? "Unmute \(strip.name)" : "Mute \(strip.name)") {
                        model.mute(strip.id)
                    }
                    .accessibilityIdentifier("strip-mute-\(strip.name)")
                }
            } else {
                Spacer().frame(height: 98)
            }

            VStack(spacing: 10) {
                GeometryReader { proxy in
                    HStack(alignment: .top, spacing: 4) {
                        FaderTrack(volume: volume, scale: scale, height: proxy.size.height)
                        LevelMeter(level: model.state.stripMeters[strip.id]?.max() ?? 0, vertical: true)
                            .frame(width: 6)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(.rect)
                    .gesture(DragGesture(minimumDistance: 2)
                        .onChanged { drag in
                            let start = dragStart ?? strip.volume
                            dragStart = start
                            let next = max(0, min(1, start - Double(drag.translation.height / max(1, proxy.size.height))))
                            dragVolume = next
                            model.setVolume(strip.id, next)
                        }
                        .onEnded { _ in
                            dragStart = nil
                            Task { try? await Task.sleep(for: .milliseconds(400)); dragVolume = nil }
                        })
                    .onTapGesture(count: 2) { model.setVolume(strip.id, unity) }
                }
                .frame(minHeight: 140)

                Text(dragVolume.flatMap { _ in "…" } ?? Format.db(strip.volumeDB))
                    .font(Studio.counter(.footnote, weight: .semibold))
                    .foregroundStyle(Studio.text1)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity, minHeight: 26)
                    .studioWell(radius: 4)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(strip.name) level")
            .accessibilityValue(spokenDB(strip.volumeDB))
            .accessibilityAdjustableAction { direction in
                let step = direction == .increment ? 0.02 : -0.02
                model.setVolume(strip.id, max(0, min(1, strip.volume + step)))
            }
            .accessibilityIdentifier("fader-\(strip.name)")
        }
        .padding(8)
        .frame(width: 96)
        .studioCard()
        .opacity(model.audible(strip.id) || strip.isMaster || strip.isBus ? 1 : 0.55)
        .accessibilityElement(children: .contain)
    }

    private var tint: Color { strip.isBus ? Studio.text3 : Studio.track(strip.color, index: index) }

    private func spokenDB(_ db: Double?) -> String {
        guard let db else { return "silent" }
        return db == 0 ? "0 decibels" : String(format: "%@%.1f decibels", db > 0 ? "plus " : "minus ", abs(db))
    }

    private func spokenPan(_ label: String) -> String {
        if label == "C" { return "centre" }
        let side = label.hasPrefix("L") ? "left" : "right"
        return "\(label.dropFirst()) \(side)"
    }
}

/// The pan label while a finger moves the knob, before the computer answers.
enum PanLabel {
    static func pan(_ pan: Double) -> String {
        let value = Int((64 + pan * (pan < 0 ? 64 : 63)).rounded())
        return value == 64 ? "C" : value < 64 ? "L\(64 - value)" : "R\(value - 64)"
    }
}

/// Tabber Studio's pan knob: a dial with a pointer, and its L/C/R value,
/// drawn (the knob says its value to VoiceOver itself).
struct PanKnob: View {
    let pan: Double
    let label: String

    var body: some View {
        Canvas { context, size in
            let dial = CGRect(x: 0, y: (size.height - 30) / 2, width: 30, height: 30)
            context.fill(Path(ellipseIn: dial), with: .color(Studio.bg3))
            context.stroke(Path(ellipseIn: dial.insetBy(dx: 0.5, dy: 0.5)), with: .color(Studio.edge), lineWidth: 1)
            let angle = Angle.degrees(pan * 135 - 90).radians
            let centre = CGPoint(x: dial.midX, y: dial.midY)
            var pointer = Path()
            pointer.move(to: CGPoint(x: centre.x + cos(angle) * 4, y: centre.y + sin(angle) * 4))
            pointer.addLine(to: CGPoint(x: centre.x + cos(angle) * 11, y: centre.y + sin(angle) * 11))
            context.stroke(pointer, with: .color(Studio.text1), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
            context.draw(Text(label).font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Studio.text1),
                         at: CGPoint(x: 38, y: size.height / 2), anchor: .leading)
        }
        .frame(width: 76, height: 44)
        .contentShape(.rect)
    }
}

/// The fader: Tabber Studio's dB marks, then the groove with its cap, drawn
/// (the fader says its level to VoiceOver itself).
struct FaderTrack: View {
    let volume: Double
    let scale: [ScaleMark]
    let height: CGFloat
    private let cap: CGFloat = 18
    private let marks: CGFloat = 22
    private let capWidth: CGFloat = 30

    var body: some View {
        let travel = max(1, height - cap)
        let groove = marks + 6 + capWidth / 2
        Canvas { context, _ in
            for mark in scale {
                let y = cap / 2 + travel * (1 - mark.volume)
                context.draw(Text(mark.db == 0 ? "0" : "\(Int(mark.db))")
                                .font(.system(size: 9, weight: .medium).monospacedDigit())
                                .foregroundStyle(Studio.text2),
                             at: CGPoint(x: marks, y: y), anchor: .trailing)
            }
            context.fill(Path(roundedRect: CGRect(x: groove - 2, y: 0, width: 4, height: height), cornerRadius: 2),
                         with: .color(Studio.bg0))
            let top = travel * (1 - volume)
            context.fill(Path(roundedRect: CGRect(x: groove - capWidth / 2, y: top, width: capWidth, height: cap), cornerRadius: 3),
                         with: .color(Studio.text2))
            context.fill(Path(CGRect(x: groove - capWidth / 2, y: top + cap / 2 - 0.75, width: capWidth, height: 1.5)),
                         with: .color(Studio.bg0))
        }
        .frame(width: groove + capWidth / 2, height: height)
    }
}

/// A screen the computer cannot serve yet, in plain words.
struct Unavailable: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.body)
            .foregroundStyle(Studio.text2)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .accessibilityIdentifier("unavailable")
    }
}
