import RemoteKit
import SwiftUI

/// The home screen: run the session from across the room (plan: The app).
struct SessionView: View {
    @Bindable var model: AppModel
    /// The readout follows Dynamic Type, up to what fits across a phone.
    @ScaledMetric(relativeTo: .largeTitle) private var posSize: CGFloat = 64
    @ScaledMetric(relativeTo: .title3) private var readoutSize: CGFloat = 20
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let state = model.state
        ScrollView {
            VStack(spacing: 22) {
                header(state)
                playhead(state)
                if let track = state.tracks.first(where: \.armed) {
                    ArmedTrackRow(track: track, peak: state.meters[track.id] ?? [])
                } else {
                    TrackPicker(model: model)
                }
                markerChips(state)
                toggles(state)
                if let problem = model.problem {
                    Label(problem, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(Studio.playhead)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("problem")
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Studio.bg1)
        .safeAreaInset(edge: .bottom) {
            Group {
                if let take = model.lastTake, !state.record.recording {
                    // The confirmed take, rating included (principle 3).
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
        .opacity(model.isConnected ? 1 : 0.45)        // stale state is never shown as live
        .animation(.easeInOut(duration: 0.25), value: model.isConnected)
        .safeAreaInset(edge: .top) {
            if let trouble = state.trouble {             // what is wrong, and the fix (TR6)
                FixItCard(model: model, trouble: trouble, computer: model.computerName)
                    .padding(.horizontal, 12)
                    .padding(.top, 4)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.35), value: state.trouble)
        .overlay { RecordingFrame(state: state) }
        .background(Studio.bg1.ignoresSafeArea())
    }

    private func header(_ state: SessionState) -> some View {
        // The computer and the song side by side; stacked at the largest text sizes.
        let layout = typeSize >= .xxLarge ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                                          : AnyLayout(HStackLayout(alignment: .firstTextBaseline))
        return layout {
            ConnectionBadge(link: state.link, name: state.host?.name ?? "Tabber Studio")
            if typeSize < .xxLarge { Spacer() }
            Text(state.project.title + (state.project.unsaved ? " *" : ""))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Studio.text2)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(state.project.unsaved ? "\(state.project.title), not saved" : state.project.title)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func section(_ state: SessionState) -> String? {
        guard let position = state.transport?.position else { return nil }
        return state.markers.last { ($0.bar, $0.beat) <= (position.bar, position.beat) }?.name
    }

    private func playhead(_ state: SessionState) -> some View {
        VStack(spacing: 10) {
            Text(section(state)?.uppercased() ?? " ")
                .font(.headline.weight(.semibold))
                .tracking(2)
                .foregroundStyle(Studio.text2)
                .accessibilityIdentifier("section")
            if let transport = state.transport {
                // Tabber Studio's readout: POS, TIME and BPM in a well, monospaced.
                VStack(spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        StudioLabel("Pos").accessibilityHidden(true)
                        Text("\(transport.position.bar) : \(transport.position.beat)")
                            .font(Studio.readout(min(posSize, 88)))
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .foregroundStyle(Studio.text1)
                            .contentTransition(.numericText())
                            .accessibilityIdentifier("playhead")
                            .accessibilityLabel("Bar \(transport.position.bar), beat \(transport.position.beat)")
                    }
                    // Side by side, or stacked at the largest text sizes: the same views either way.
                    let row = typeSize >= .xxLarge ? AnyLayout(VStackLayout(spacing: 6)) : AnyLayout(HStackLayout(spacing: 22))
                    row {
                        timeReadout(transport)
                        bpmReadout(transport)
                    }
                }
                .padding(.vertical, 14)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity)
                .studioWell()
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// A label beside its value; at the largest text sizes, above it.
    private var item: AnyLayout {
        typeSize >= .xxLarge ? AnyLayout(VStackLayout(spacing: 2)) : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))
    }

    private func timeReadout(_ transport: TransportState) -> some View {
        item {
            StudioLabel("Time").accessibilityHidden(true)
            TimelineView(.animation(minimumInterval: 0.1, paused: transport.state != .playing)) { _ in
                Text(Self.time(model.state.playheadSeconds))
                    .font(Studio.readout(readoutSize))
                    .foregroundStyle(Studio.text1)
            }
            .accessibilityHidden(true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Time")
        .accessibilityValue(Self.clock(model.state.playheadSeconds))
    }

    private func bpmReadout(_ transport: TransportState) -> some View {
        item {
            StudioLabel("Bpm").accessibilityHidden(true)
            Text(Self.bpm(transport))
                .font(Studio.readout(readoutSize))
                .foregroundStyle(Studio.text1)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Tempo")
        .accessibilityValue("\(Self.bpm(transport)) beats per minute")
    }

    /// Tabber Studio's TIME: m:ss.mmm.
    static func time(_ seconds: Double) -> String {
        let millis = max(0, Int((seconds * 1000).rounded(.down)))
        return String(format: "%d:%02d.%03d", millis / 60000, (millis / 1000) % 60, millis % 1000)
    }

    /// The song's tempo; at practice speed, the speed it plays at.
    static func bpm(_ transport: TransportState) -> String {
        let value = transport.tempoBPM * transport.tempoScale
        return value.rounded() == value ? "\(Int(value))" : String(format: "%.1f", value)
    }

    static func clock(_ seconds: Double) -> String {
        let total = max(0, Int(seconds))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    private func markerChips(_ state: SessionState) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Button(action: model.flag) {
                    Label {
                        Text("Flag").foregroundStyle(Studio.text1)
                    } icon: {
                        Image(systemName: "flag.fill").foregroundStyle(Studio.playhead)
                    }
                    .font(.callout.weight(.semibold))
                    .padding(.horizontal, 14)
                    .frame(minHeight: 44)
                    .background(Studio.bg3, in: RoundedRectangle(cornerRadius: Studio.radiusControl, style: .continuous))
                }
                .buttonStyle(.plain)
                .opacity(model.pending.contains("flag") ? 0.5 : 1)
                .accessibilityLabel("Flag this moment")
                .accessibilityIdentifier("flag")
                ForEach(state.markers) { marker in
                    MarkerChip(marker: marker, pending: model.pending.contains("marker-\(marker.id)"),
                               looped: state.transport?.loop.enabled == true && state.transport?.loop.start?.bar == marker.bar) {
                        model.act("marker-\(marker.id)", "markers.go", ["marker_id": .string(marker.id)])
                    } loop: {
                        model.act("marker-\(marker.id)", "markers.loop", ["marker_id": .string(marker.id)])
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Markers")
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
}

/// Connection status, always visible, driven by heartbeats (principle 3).
struct ConnectionBadge: View {
    let link: LinkState
    let name: String

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 9, height: 9)
            Text(text).font(.subheadline.weight(.semibold)).foregroundStyle(Studio.text1)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("connection")
    }

    private var color: Color {
        switch link {
        case .connected(let busy): busy ? Studio.playhead : Studio.accent
        case .connecting, .reconnecting: Studio.playhead
        case .failed: Studio.record
        case .idle: Studio.text3
        }
    }

    private var text: String {
        switch link {
        case .connected(let busy): busy ? "\(name) is busy" : name
        case .connecting: "Connecting"
        case .reconnecting: "Reconnecting"
        case .failed: "Not connected"
        case .idle: "Not connected"
        }
    }
}

/// The armed track and the input it records.
struct ArmedTrackRow: View {
    let track: Track
    let peak: [Double]

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(track.name).font(.headline).foregroundStyle(Studio.text1)
                Text("ARMED").font(.caption2.weight(.bold)).tracking(0.8).foregroundStyle(Studio.record)
            }
            MeterBar(level: peak.max() ?? 0)
                .frame(height: 10)
        }
        .padding(14)
        .padding(.leading, 4)
        .studioCard(Studio.bg2)
        .trackEdge(Color(hex: track.color))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("armed-track")
    }
}

/// A peak meter in dB, in Tabber Studio's colours: teal, then amber, then red near 0 dB.
struct MeterBar: View {
    let level: Double

    var fraction: Double {
        guard level > 0 else { return 0 }
        let db = 20 * log10(level)
        return min(1, max(0, (db + 60) / 60))
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Studio.bg3)
                Capsule()
                    .fill(LinearGradient(colors: [Studio.accent, Studio.accent, Studio.playhead, Studio.record],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: proxy.size.width * fraction)
                    .animation(.linear(duration: 0.08), value: fraction)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Pick the track to record when none is armed.
struct TrackPicker: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            StudioLabel("Arm a track to record")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(model.state.tracks) { track in
                        Button {
                            model.act("arm-\(track.id)", "tracks.arm", ["track_id": .string(track.id), "armed": true])
                        } label: {
                            Label(track.name, systemImage: track.kind == .audio ? "waveform" : "pianokeys")
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(Studio.text1)
                                .padding(.horizontal, 16)
                                .frame(minHeight: 44)
                                .background(Studio.bg3, in: RoundedRectangle(cornerRadius: Studio.radiusControl, style: .continuous))
                                .trackEdge(Color(hex: track.color), radius: Studio.radiusControl)
                        }
                        .buttonStyle(.plain)
                        .opacity(model.pending.contains("arm-\(track.id)") ? 0.5 : 1)
                        .accessibilityIdentifier("arm-\(track.name)")
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct MarkerChip: View {
    let marker: Marker
    let pending: Bool
    let looped: Bool
    let go: () -> Void
    let loop: () -> Void

    var body: some View {
        Text(marker.name)
            .font(.callout.weight(.semibold))
            .foregroundStyle(looped ? Studio.onAccent : Studio.text1)
            .padding(.horizontal, 16)
            .frame(minHeight: 44)
            .background(looped ? Studio.accent : Studio.bg3,
                        in: RoundedRectangle(cornerRadius: Studio.radiusControl, style: .continuous))
            .opacity(pending ? 0.5 : 1)
            .contentShape(.rect)
            .onTapGesture(perform: go)
            .onLongPressGesture(minimumDuration: 0.45, perform: loop)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(looped ? "\(marker.name), looping" : marker.name)
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
                .font(.callout.weight(.semibold))
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

/// The screen's frame glows red while the computer records: readable across the room.
struct RecordingFrame: View {
    let state: SessionState

    var body: some View {
        if state.record.recording {
            TimelineView(.animation(minimumInterval: 0.25)) { _ in
                let seconds = state.recordedSeconds ?? 0
                ZStack(alignment: .top) {
                    RoundedRectangle(cornerRadius: 44)
                        .strokeBorder(Studio.record, lineWidth: 10)
                        .shadow(color: Studio.record.opacity(0.6), radius: 18)    // a signal, not depth
                        .ignoresSafeArea()
                        .accessibilityHidden(true)
                    Text(seconds < 0 ? "COUNT-IN \(Int((-seconds).rounded(.up)))" : "REC \(SessionView.clock(seconds))")
                        .font(.system(.title, design: .rounded).weight(.heavy))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18).padding(.vertical, 8)
                        .background(Studio.record, in: .capsule)
                        .padding(.top, 4)
                        .accessibilityLabel(seconds < 0 ? "Counting in" : "Recording, \(Int(seconds)) seconds")
                        .accessibilityIdentifier("recording-frame")
                }
            }
            .allowsHitTesting(false)
        }
    }
}
