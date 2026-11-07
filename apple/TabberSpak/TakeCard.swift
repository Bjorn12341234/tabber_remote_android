import RemoteKit
import SwiftUI

/// After every take, the take's slate: what was recorded, and the two
/// decisions that matter with an instrument in hand, discard or go again.
/// Keep is the default (recording again keeps the take too), so it is the
/// quiet word in the corner.
struct TakeCard: View {
    @Bindable var model: AppModel
    let take: Take
    @State private var holding = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(take.name)
                        .font(.headline)
                        .foregroundStyle(Studio.text1)
                    Text("\(SessionView.length(take.lengthSeconds)) from bar \(take.start.bar)")
                        .font(.subheadline)
                        .foregroundStyle(Studio.text2)
                }
                Spacer()
                Button("Keep") { model.keep() }
                    .buttonStyle(.studioQuiet)
                    .accessibilityHint("Keeps the take and closes this.")
                    .accessibilityIdentifier("keep")
            }
            HStack(spacing: 10) {
                // The fill grows while held; in a background, so it never sizes the card.
                Text("Hold to discard")
                    .font(.body.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(holding ? Color.white : Studio.text1)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(alignment: .leading) {
                        GeometryReader { proxy in
                            Rectangle().fill(Studio.record)
                                .frame(width: holding ? proxy.size.width : 0)
                                .animation(holding ? .linear(duration: 0.6) : .easeOut(duration: 0.15), value: holding)
                        }
                    }
                    .background(Studio.bg3)
                    .clipShape(.rect(cornerRadius: Studio.radiusControl))
                    .onLongPressGesture(minimumDuration: 0.6) {
                        model.discard(take)
                    } onPressingChanged: { pressing in
                        holding = pressing
                    }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityLabel("Discard \(take.name)")
                    .accessibilityHint("Touch and hold. You can undo it for five seconds.")
                    .accessibilityAction { model.discard(take) }
                    .accessibilityIdentifier("discard")

                Button { model.goAgain() } label: {
                    HStack(spacing: 8) {
                        Text("●").foregroundStyle(Studio.record)       // it records: the record dot
                        Text("Go again")
                    }
                    .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(.studio)
                .accessibilityLabel("Go again")
                .accessibilityHint("Records again from bar \(take.start.bar).")
                .accessibilityIdentifier("card-go-again")
            }
        }
        .padding(18)
        .background(Studio.bg2, in: RoundedRectangle(cornerRadius: Studio.radiusPanel, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Studio.radiusPanel, style: .continuous).strokeBorder(Studio.edge, lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("take-card")
    }
}

/// The Undo offer after a discard, for five seconds.
struct UndoBanner: View {
    @Bindable var model: AppModel
    let offer: AppModel.UndoOffer

    var body: some View {
        HStack {
            Text(offer.text)
                .font(.body)
                .foregroundStyle(Studio.text1)
            Spacer()
            Button("Undo") { model.undoDiscard() }
                .buttonStyle(.studio)
                .accessibilityIdentifier("undo-discard")
        }
        .padding(.leading, 18)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .background(Studio.bg2, in: RoundedRectangle(cornerRadius: Studio.radiusPanel, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Studio.radiusPanel, style: .continuous).strokeBorder(Studio.edge, lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("undo-banner")
    }
}

struct Stars: View {
    let rating: Int
    let rate: (Int) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(1...5, id: \.self) { star in
                Image(systemName: star <= rating ? "star.fill" : "star")
                    .foregroundStyle(star <= rating ? Studio.playhead : Studio.text3)
                    .font(.title3)
                    .onTapGesture { rate(star == rating ? 0 : star) }
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Rating")
        .accessibilityValue(rating == 0 ? "Not rated" : "\(rating) of 5")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: rate(min(5, rating + 1))
            case .decrement: rate(max(0, rating - 1))
            @unknown default: break
            }
        }
        .accessibilityIdentifier("stars")
    }
}

/// Every take on the session's tracks, newest first, with ratings.
struct TakesView: View {
    @Bindable var model: AppModel

    var body: some View {
        NavigationStack {
            List {
                if model.state.takes.isEmpty {
                    ContentUnavailableView("No takes yet", systemImage: "waveform",
                                           description: Text("Record on the Session tab."))
                }
                ForEach(model.state.takes) { take in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(take.name).font(.body.weight(.medium)).foregroundStyle(Studio.text1)
                            Text("\(SessionView.length(take.lengthSeconds)) from bar \(take.start.bar)")
                                .font(.subheadline).foregroundStyle(Studio.text2)
                        }
                        Spacer()
                        Stars(rating: take.rating) { model.rate(take, $0) }
                    }
                    .accessibilityElement(children: .contain)     // the rating stays adjustable
                    .accessibilityIdentifier("take-\(take.name)")
                    .listRowBackground(Studio.bg1)
                }
            }
            .studioList()
            .navigationTitle("Takes")
        }
    }
}

/// Arm, select and monitor the session's tracks. Each row is two buttons:
/// the track (select it) and its arm button, each its own target (TR9 audit).
struct TracksView: View {
    @Bindable var model: AppModel

    var body: some View {
        NavigationStack {
            List(model.state.tracks) { track in
                HStack(spacing: 8) {
                    Button {
                        model.act("select-\(track.id)", "tracks.select", ["track_id": .string(track.id)])
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: track.kind == .audio ? "waveform" : "pianokeys")
                                .foregroundStyle(Color(hex: track.color) ?? Studio.text3)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                // The selected track's name in teal: Tabber Studio's selection.
                                Text(track.name).font(.body.weight(.semibold))
                                    .foregroundStyle(track.selected ? Studio.accent : Studio.text1)
                                if track.kind == .midi {
                                    Text("Monitor \(track.monitor.rawValue)").font(.subheadline).foregroundStyle(Studio.text2)
                                }
                            }
                            Spacer()
                            if let peak = model.state.meters[track.id] {
                                LevelMeter(level: peak.max() ?? 0).frame(width: 64, height: 4)
                            }
                        }
                        .frame(minHeight: 44)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(track.name), \(track.kind == .audio ? "audio" : "MIDI")"
                                        + (track.kind == .midi ? ", monitor \(track.monitor.rawValue)" : ""))
                    .accessibilityValue(track.selected ? "Selected" : "")
                    .accessibilityHint("Selects the track in Tabber Studio.")
                    .accessibilityIdentifier("track-\(track.name)")
                    if track.kind == .midi, model.state.capabilities.contains("tracks.monitor/1") {
                        Menu {
                            Picker("Monitor", selection: Binding(get: { track.monitor }, set: { mode in
                                model.act("monitor-\(track.id)", "tracks.set_monitor",
                                          ["track_id": .string(track.id), "mode": .string(mode.rawValue)])
                            })) {
                                Text("Auto").tag(MonitorMode.auto)
                                Text("On").tag(MonitorMode.on)
                                Text("Off").tag(MonitorMode.off)
                            }
                        } label: {
                            Image(systemName: track.monitor == .off ? "speaker.slash" : "speaker.wave.2")
                                .font(.title3)
                                .foregroundStyle(track.monitor == .on ? Studio.accent : Studio.text2)
                                .frame(minWidth: 44, minHeight: 44)
                                .contentShape(.rect)
                        }
                        .accessibilityLabel("Monitor \(track.name)")
                        .accessibilityValue(track.monitor.rawValue)
                        .accessibilityIdentifier("track-monitor-\(track.name)")
                    }
                    Button {
                        model.act("arm-\(track.id)", "tracks.arm", ["track_id": .string(track.id), "armed": .bool(!track.armed)])
                    } label: {
                        Text(track.armed ? "●" : "○")                 // Tabber Studio's record arm
                            .font(.title2)
                            .foregroundStyle(track.armed ? Studio.record : Studio.text3)
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(track.armed ? "Disarm \(track.name)" : "Arm \(track.name)")
                    .accessibilityIdentifier("track-arm-\(track.name)")
                }
                .listRowBackground(Studio.bg1)
            }
            .studioList()
            .navigationTitle("Tracks")
        }
    }
}

extension Color {
    init?(hex: String?) {
        guard let hex, hex.count == 7, hex.hasPrefix("#"), let value = UInt32(hex.dropFirst(), radix: 16) else { return nil }
        self.init(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255,
                  blue: Double(value & 0xFF) / 255)
    }
}
