import RemoteKit
import SwiftUI

/// The home screen, read from across the room with an instrument in hand
/// (plan: The app). Top to bottom by how far away it must read: where you
/// are and whether it records (the lamp), what records (the tracks and their
/// input), where to go (markers), and how the take starts (count-in, metro,
/// loop). When the computer cannot be reached, the screen says why instead.
struct SessionView: View {
    @Bindable var model: AppModel

    var body: some View {
        let state = model.state
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                StatusLine(link: state.link, computer: model.computerName, project: state.project)
                if let trouble = state.trouble {
                    FixItView(model: model, trouble: trouble, computer: model.computerName)
                        .padding(.top, 12)
                } else {
                    VStack(alignment: .leading, spacing: 20) {
                        Text(section(state) ?? " ")
                            .font(.system(.title, weight: .semibold))
                            .foregroundStyle(Studio.text1)
                            .accessibilityIdentifier("section")
                        Lamp(state: state)
                        TrackRow(model: model)
                        MarkerRow(model: model, current: section(state))
                        toggles(state)
                        if let problem = model.problem {
                            Text(problem)
                                .font(.subheadline)
                                .foregroundStyle(Studio.playhead)
                                .accessibilityIdentifier("problem")
                        }
                    }
                    .opacity(model.isConnected ? 1 : 0.45)        // stale state is never shown as live
                    .animation(.easeInOut(duration: 0.25), value: model.isConnected)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom) {
            Group {
                if let take = model.lastTake, !state.record.recording {
                    TakeCard(model: model, take: state.takes.first { $0.id == take.id } ?? take)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else if let offer = model.undoOffer {
                    UndoBanner(model: model, offer: offer)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
            .animation(.spring(duration: 0.35), value: model.lastTake?.id)
            .animation(.spring(duration: 0.35), value: model.undoOffer)
        }
        .animation(.spring(duration: 0.35), value: state.trouble)
        .background(Studio.bg1.ignoresSafeArea())
    }

    private func section(_ state: SessionState) -> String? {
        guard let position = state.transport?.position else { return nil }
        return state.markers.last { ($0.bar, $0.beat) <= (position.bar, position.beat) }?.name
    }

    private func toggles(_ state: SessionState) -> some View {
        let transport = state.transport
        let bars = transport?.countInBars ?? 0
        return HStack(spacing: 4) {
            ToggleTile(title: bars == 0 ? "Count-in" : "Count-in \(bars)",
                       spoken: bars == 0 ? "No count-in" : "Count-in \(bars) bar\(bars == 1 ? "" : "s")",
                       on: bars > 0, pending: model.pending.contains("countin"), id: "count-in") {
                model.act("countin", "transport.set_count_in", ["bars": .number(Double((bars + 1) % 3))])
            }
            ToggleTile(title: "Metro", spoken: "Metronome", on: transport?.click == true,
                       pending: model.pending.contains("click"), id: "click") {
                model.act("click", "transport.set_click", ["enabled": .bool(!(transport?.click ?? false))])
            }
            ToggleTile(title: "Loop", spoken: "Loop", on: transport?.loop.enabled == true,
                       pending: model.pending.contains("loop"), id: "loop") {
                model.act("loop", "transport.set_loop", ["enabled": .bool(!(transport?.loop.enabled ?? false))])
            }
        }
        .padding(4)
        .studioWell()
    }

    /// Tabber Studio's TIME: m:ss.mmm.
    static func time(_ seconds: Double) -> String {
        let millis = max(0, Int((seconds * 1000).rounded(.down)))
        return String(format: "%d:%02d.%03d", millis / 60000, (millis / 1000) % 60, millis % 1000)
    }

    /// Tabber Studio's REC counter: m:ss.
    static func rec(_ seconds: Double) -> String {
        let total = max(0, Int(seconds))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// A take's length in words: "42 seconds", "1:42".
    static func length(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        return total < 60 ? "\(total) second\(total == 1 ? "" : "s")" : rec(seconds)
    }

    /// The song's tempo; at practice speed, the speed it plays at.
    static func bpm(_ transport: TransportState) -> String {
        let value = transport.tempoBPM * transport.tempoScale
        return value.rounded() == value ? "\(Int(value))" : String(format: "%.1f", value)
    }

    static func clock(_ seconds: Double) -> String { rec(seconds) }
}

/// Which computer, whether it answers, and the song: the quietest line on the screen.
struct StatusLine: View {
    let link: LinkState
    let computer: String
    let project: ProjectState
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        // Side by side; stacked at the largest text sizes. The same views either way.
        let stacked = typeSize >= .xxLarge
        let layout = stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
                             : AnyLayout(HStackLayout(alignment: .firstTextBaseline))
        layout {
            connection
            if !stacked { Spacer() }
            song
        }
    }

    private var connection: some View {
        Text(words)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("connection")
    }

    private var song: some View {
        Text(project.title + (project.unsaved ? " *" : ""))
            .font(.subheadline)
            .foregroundStyle(Studio.text2)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel(project.unsaved ? "\(project.title), not saved" : project.title)
    }

    private var words: String {
        switch link {
        case .connected(let busy): busy ? "\(computer) is busy" : computer
        case .connecting: "Connecting to \(computer)"
        case .reconnecting: "Reconnecting to \(computer)"
        case .failed, .idle: "Not connected"
        }
    }

    private var color: Color {
        switch link {
        case .connected(let busy): busy ? Studio.playhead : Studio.text1
        case .connecting, .reconnecting: Studio.playhead
        case .failed, .idle: Studio.text3
        }
    }
}

/// Tabber Studio's readout, and the session's recording light: at rest a dark
/// well with POS, TIME and BPM; amber while counting in; red with REC and the
/// take's length while recording, pulsing as Tabber Studio's record button does.
struct Lamp: View {
    let state: SessionState
    @ScaledMetric(relativeTo: .largeTitle) private var big: CGFloat = 64
    @ScaledMetric(relativeTo: .title3) private var small: CGFloat = 20
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.1, paused: !live)) { context in
            let seconds = state.recordedSeconds
            let phase = Self.phase(recording: state.record.recording, seconds: seconds)
            content(phase: phase, seconds: seconds ?? 0)
                .padding(.vertical, 18)
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(fill(phase), in: RoundedRectangle(cornerRadius: Studio.radiusLamp, style: .continuous))
                .opacity(phase == .recording && !reduceMotion ? Self.pulse(context.date) : 1)
                .animation(.easeInOut(duration: 0.2), value: phase)
        }
    }

    enum Phase: Equatable { case rest, countIn, recording }

    static func phase(recording: Bool, seconds: Double?) -> Phase {
        guard recording else { return .rest }
        return (seconds ?? 0) < 0 ? .countIn : .recording
    }

    /// Between 0.82 and 1 once a second.
    static func pulse(_ date: Date) -> Double {
        0.91 + 0.09 * cos(date.timeIntervalSinceReferenceDate * 2 * .pi)
    }

    private var live: Bool { state.record.recording || state.transport?.state == .playing }

    private func fill(_ phase: Phase) -> Color {
        switch phase {
        case .rest: Studio.bg0
        case .countIn: Studio.playhead
        case .recording: Studio.record
        }
    }

    @ViewBuilder private func content(phase: Phase, seconds: Double) -> some View {
        switch phase {
        case .rest: rest
        case .countIn: countIn(seconds)
        case .recording: recording(seconds)
        }
    }

    private var position: (bar: Int, beat: Int) {
        let p = state.transport?.position
        return (p?.bar ?? 1, p?.beat ?? 1)
    }

    private var rest: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                ReadoutLabel("POS")
                Text("\(position.bar) : \(position.beat)")
                    .font(Studio.counter(min(big, 88)))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .foregroundStyle(Studio.text1)
                    .contentTransition(.numericText())
                    .accessibilityIdentifier("playhead")
                    .accessibilityLabel("Bar \(position.bar), beat \(position.beat)")
            }
            let row = typeSize >= .xxLarge ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
                                           : AnyLayout(HStackLayout(spacing: 24))
            row {
                pair("TIME", SessionView.time(state.playheadSeconds), spoken: "Time", value: SessionView.clock(state.playheadSeconds))
                if let transport = state.transport {
                    pair("BPM", SessionView.bpm(transport), spoken: "Tempo", value: "\(SessionView.bpm(transport)) beats per minute")
                }
            }
        }
    }

    private func pair(_ label: String, _ text: String, spoken: String, value: String) -> some View {
        let layout = typeSize >= .xxLarge ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
                                          : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))
        return layout {
            ReadoutLabel(label)
            Text(text)
                .font(Studio.counter(small))
                .foregroundStyle(Studio.text1)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
        .accessibilityValue(value)
    }

    private func countIn(_ seconds: Double) -> some View {
        let beat = state.transport.map { 60.0 / max(1, $0.tempoBPM * $0.tempoScale) } ?? 0.6
        let beatsLeft = max(1, Int((-seconds / beat).rounded(.up)))
        return VStack(alignment: .leading, spacing: 4) {
            Text("Count-in")
                .font(.title3.weight(.semibold))
            Text("\(beatsLeft)")
                .font(Studio.counter(min(big, 88), weight: .semibold))
                .contentTransition(.numericText())
        }
        .foregroundStyle(Studio.bg0)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Counting in, \(beatsLeft) beat\(beatsLeft == 1 ? "" : "s") to go")
        .accessibilityIdentifier("rec-lamp")
    }

    private func recording(_ seconds: Double) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                ReadoutLabel("REC", color: .white)
                Text(SessionView.rec(seconds))
                    .font(Studio.counter(min(big, 88), weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            Text("From bar \(state.record.started?.position.bar ?? position.bar)")
                .font(.subheadline.weight(.medium))
                .opacity(0.85)
        }
        .foregroundStyle(.white)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Recording, \(Int(seconds)) seconds")
        .accessibilityIdentifier("rec-lamp")
    }
}

/// The tracks, each with Tabber Studio's record-arm circle (hollow, or red
/// when armed), and the armed track's input underneath.
struct TrackRow: View {
    @Bindable var model: AppModel

    var body: some View {
        let tracks = model.state.tracks
        VStack(alignment: .leading, spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(tracks) { track in
                        Button {
                            model.act("arm-\(track.id)", "tracks.arm", ["track_id": .string(track.id), "armed": .bool(!track.armed)])
                        } label: {
                            HStack(spacing: 8) {
                                Text(track.armed ? "●" : "○")
                                    .foregroundStyle(track.armed ? Studio.record : Studio.text2)
                                Text(track.name)
                                    .foregroundStyle(track.armed ? Studio.text1 : Studio.text2)
                            }
                        }
                        .buttonStyle(.studio)
                        .opacity(model.pending.contains("arm-\(track.id)") ? 0.5 : 1)
                        .accessibilityLabel(track.armed ? "Disarm \(track.name)" : "Arm \(track.name)")
                        .accessibilityIdentifier("arm-\(track.name)")
                    }
                }
            }
            .scrollClipDisabled()
            if let armed = tracks.first(where: \.armed) {
                LevelMeter(level: model.state.meters[armed.id]?.max() ?? 0)
                    .frame(height: 6)
                    .accessibilityElement()
                    .accessibilityLabel("\(armed.name) armed, input level")
                    .accessibilityIdentifier("armed-track")
            } else {
                Text("Tap a track to arm it for recording.")
                    .font(.subheadline)
                    .foregroundStyle(Studio.text3)
            }
        }
    }
}

/// An input meter in Tabber Studio's colours: green, yellow from -12 dB, red from -3 dB.
struct LevelMeter: View {
    let level: Double

    static func fraction(_ db: Double) -> Double { min(1, max(0, (db + 60) / 60)) }
    var fraction: Double { level > 0 ? Self.fraction(20 * log10(level)) : 0 }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let yellow = Self.fraction(-12), red = Self.fraction(-3)
            ZStack(alignment: .leading) {
                Rectangle().fill(Studio.bg0)
                HStack(spacing: 0) {
                    Rectangle().fill(Studio.meterLow).frame(width: width * yellow)
                    Rectangle().fill(Studio.meterMid).frame(width: width * (red - yellow))
                    Rectangle().fill(Studio.record)
                }
                .mask(alignment: .leading) {
                    Rectangle().frame(width: width * fraction)
                }
                .animation(.linear(duration: 0.08), value: fraction)
            }
            .clipShape(RoundedRectangle(cornerRadius: 2))
        }
        .accessibilityHidden(true)
    }
}

/// The song's markers: tap to go, hold to loop. The section the playhead is
/// in is amber, Tabber Studio's playhead colour; a looped one is the
/// selected choice, teal. The last button adds a marker at the shown bar.
struct MarkerRow: View {
    @Bindable var model: AppModel
    let current: String?

    var body: some View {
        let state = model.state
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(state.markers) { marker in
                    let looped = state.transport?.loop.enabled == true && state.transport?.loop.start?.bar == marker.bar
                    MarkerButton(marker: marker, here: marker.name == current, looped: looped,
                                 pending: model.pending.contains("marker-\(marker.id)")) {
                        model.act("marker-\(marker.id)", "markers.go", ["marker_id": .string(marker.id)])
                    } loop: {
                        model.act("marker-\(marker.id)", "markers.loop", ["marker_id": .string(marker.id)])
                    }
                }
                Button(action: model.flag) {
                    Label("Flag", systemImage: "plus")
                }
                .buttonStyle(.studio)
                .opacity(model.pending.contains("flag") ? 0.5 : 1)
                .accessibilityLabel("Add a marker at bar \(state.transport?.position.bar ?? 1)")
                .accessibilityIdentifier("flag")
            }
        }
        .scrollClipDisabled()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Markers")
    }
}

struct MarkerButton: View {
    let marker: Marker
    let here: Bool
    let looped: Bool
    let pending: Bool
    let go: () -> Void
    let loop: () -> Void

    var body: some View {
        Text(marker.name)
            .font(.body.weight(.semibold))
            .foregroundStyle(looped ? Studio.onAccent : here ? Studio.playhead : Studio.text1)
            .padding(.horizontal, 18)
            .frame(minHeight: 48)
            .background(looped ? Studio.accent : Studio.bg3,
                        in: RoundedRectangle(cornerRadius: Studio.radiusControl, style: .continuous))
            .opacity(pending ? 0.5 : 1)
            .contentShape(.rect)
            .onTapGesture(perform: go)
            .onLongPressGesture(minimumDuration: 0.45, perform: loop)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(looped ? "\(marker.name), looping" : marker.name)
            .accessibilityValue(here ? "Playhead here" : "")
            .accessibilityHint("Goes to bar \(marker.bar). Touch and hold to loop it.")
            .accessibilityAction(named: "Loop \(marker.name)", loop)
            .accessibilityIdentifier("marker-\(marker.name)")
    }
}

/// A toggle in a well, as Tabber Studio's toolbar toggles: ON is a lighter fill.
struct ToggleTile: View {
    let title: String
    let spoken: String
    let on: Bool
    let pending: Bool
    let id: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.body.weight(.semibold))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(on ? Studio.text1 : Studio.textWellOff)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(on ? Studio.bgOn : Color.clear,
                            in: RoundedRectangle(cornerRadius: Studio.radiusControl - 2, style: .continuous))
                .contentShape(.rect)
                .opacity(pending ? 0.55 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(spoken)
        .accessibilityValue(on ? "On" : "Off")
        .accessibilityIdentifier(id)
    }
}
