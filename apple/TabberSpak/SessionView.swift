import RemoteKit
import SwiftUI

/// The home screen: run the session from across the room (plan: The app).
struct SessionView: View {
    @Bindable var model: AppModel

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
                        .foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("problem")
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .scrollBounceBehavior(.basedOnSize)
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
    }

    private func header(_ state: SessionState) -> some View {
        HStack(alignment: .firstTextBaseline) {
            ConnectionBadge(link: state.link, name: state.host?.name ?? "Tabber Studio")
            Spacer()
            Text(state.project.title + (state.project.unsaved ? " *" : ""))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .accessibilityLabel(state.project.unsaved ? "\(state.project.title), not saved" : state.project.title)
        }
    }

    private func section(_ state: SessionState) -> String? {
        guard let position = state.transport?.position else { return nil }
        return state.markers.last { ($0.bar, $0.beat) <= (position.bar, position.beat) }?.name
    }

    private func playhead(_ state: SessionState) -> some View {
        VStack(spacing: 4) {
            Text(section(state)?.uppercased() ?? " ")
                .font(.headline.weight(.semibold))
                .tracking(2)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("section")
            if let transport = state.transport {
                Text("\(transport.position.bar) . \(transport.position.beat)")
                    .font(.system(size: 76, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .accessibilityIdentifier("playhead")
                    .accessibilityLabel("Bar \(transport.position.bar), beat \(transport.position.beat)")
                TimelineView(.animation(minimumInterval: 0.1, paused: transport.state != .playing)) { _ in
                    Text(Self.clock(model.state.playheadSeconds))
                        .font(.title2.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    static func clock(_ seconds: Double) -> String {
        let total = max(0, Int(seconds))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    private func markerChips(_ state: SessionState) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Button(action: model.flag) {
                    Label("Flag", systemImage: "flag.fill")
                        .font(.callout.weight(.semibold))
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(.fill.tertiary, in: .capsule)
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
        return HStack(spacing: 10) {
            let bars = transport?.countInBars ?? 0
            ToggleTile(title: bars == 0 ? "No count-in" : "Count-in \(bars) bar\(bars == 1 ? "" : "s")",
                       systemImage: "metronome", on: bars > 0, pending: model.pending.contains("countin"), id: "count-in") {
                model.act("countin", "transport.set_count_in", ["bars": .number(Double((bars + 1) % 3))])
            }
            ToggleTile(title: "Click", systemImage: "waveform.path", on: transport?.click == true,
                       pending: model.pending.contains("click"), id: "click") {
                model.act("click", "transport.set_click", ["enabled": .bool(!(transport?.click ?? false))])
            }
            ToggleTile(title: "Loop", systemImage: "repeat", on: transport?.loop.enabled == true,
                       pending: model.pending.contains("loop"), id: "loop") {
                model.act("loop", "transport.set_loop", ["enabled": .bool(!(transport?.loop.enabled ?? false))])
            }
        }
    }
}

/// Connection status, always visible, driven by heartbeats (principle 3).
struct ConnectionBadge: View {
    let link: LinkState
    let name: String

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 9, height: 9)
            Text(text).font(.subheadline.weight(.semibold)).lineLimit(1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("connection")
    }

    private var color: Color {
        switch link {
        case .connected(let busy): busy ? .yellow : .green
        case .connecting, .reconnecting: .orange
        case .failed: .red
        case .idle: .gray
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
                Text(track.name).font(.headline)
                Text("Armed").font(.caption.weight(.semibold)).foregroundStyle(.red)
            }
            MeterBar(level: peak.max() ?? 0)
                .frame(height: 10)
        }
        .padding(14)
        .background(.fill.tertiary, in: .rect(cornerRadius: 16))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("armed-track")
    }
}

/// A peak meter in dB: green, then yellow from -12 dB, red from -3 dB.
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
                Capsule().fill(.fill.secondary)
                Capsule()
                    .fill(LinearGradient(colors: [.green, .green, .yellow, .red],
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
            Text("Arm a track to record").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(model.state.tracks) { track in
                        Button {
                            model.act("arm-\(track.id)", "tracks.arm", ["track_id": .string(track.id), "armed": true])
                        } label: {
                            Label(track.name, systemImage: track.kind == .audio ? "waveform" : "pianokeys")
                                .padding(.horizontal, 14).padding(.vertical, 10)
                        }
                        .buttonStyle(.bordered)
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
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(looped ? AnyShapeStyle(.tint.opacity(0.25)) : AnyShapeStyle(.fill.tertiary), in: .capsule)
            .overlay { if looped { Capsule().strokeBorder(.tint, lineWidth: 1.5) } }
            .opacity(pending ? 0.5 : 1)
            .contentShape(.capsule)
            .onTapGesture(perform: go)
            .onLongPressGesture(minimumDuration: 0.45, perform: loop)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(looped ? "\(marker.name), looping" : marker.name)
            .accessibilityHint("Goes to bar \(marker.bar). Touch and hold to loop it.")
            .accessibilityAction(named: "Loop \(marker.name)", loop)
            .accessibilityIdentifier("marker-\(marker.name)")
    }
}

struct ToggleTile: View {
    let title: String
    let systemImage: String
    let on: Bool
    let pending: Bool
    let id: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: systemImage).font(.title3)
                Text(title).font(.caption.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 64)
            .foregroundStyle(on ? Color.white : Color.primary)
            .background(on ? AnyShapeStyle(.tint) : AnyShapeStyle(.fill.tertiary), in: .rect(cornerRadius: 16))
            .opacity(pending ? 0.55 : 1)
        }
        .buttonStyle(.plain)
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
                        .strokeBorder(Color.red, lineWidth: 10)
                        .shadow(color: .red.opacity(0.6), radius: 18)
                        .ignoresSafeArea()
                        .accessibilityHidden(true)
                    Text(seconds < 0 ? "COUNT-IN \(Int((-seconds).rounded(.up)))" : "REC \(SessionView.clock(seconds))")
                        .font(.system(.title, design: .rounded).weight(.heavy))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18).padding(.vertical, 8)
                        .background(.red, in: .capsule)
                        .padding(.top, 4)
                        .accessibilityLabel(seconds < 0 ? "Counting in" : "Recording, \(Int(seconds)) seconds")
                        .accessibilityIdentifier("recording-frame")
                }
            }
            .allowsHitTesting(false)
        }
    }
}
