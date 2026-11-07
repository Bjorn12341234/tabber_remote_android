import RemoteKit
import SwiftUI

/// After every take: keep it (the default), discard it, or go again (plan: screen 2).
struct TakeCard: View {
    @Bindable var model: AppModel
    let take: Take
    @State private var holding = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(take.name).font(.headline)
                    Text("Bar \(take.start.bar) · \(SessionView.clock(take.lengthSeconds))")
                        .font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
                }
                Spacer()
                Stars(rating: take.rating) { model.rate(take, $0) }
            }
            HStack(spacing: 10) {
                Button { model.keep() } label: {
                    Text("Keep").frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("keep")

                ZStack {
                    RoundedRectangle(cornerRadius: 14).fill(.fill.tertiary)
                    GeometryReader { proxy in
                        RoundedRectangle(cornerRadius: 14).fill(.red.opacity(0.85))
                            .frame(width: holding ? proxy.size.width : 0)
                            .animation(holding ? .linear(duration: 0.6) : .easeOut(duration: 0.15), value: holding)
                    }
                    Text("Hold to discard").font(.callout.weight(.semibold))
                        .foregroundStyle(holding ? .white : .red)
                }
                .frame(maxWidth: .infinity, minHeight: 50)
                .clipShape(.rect(cornerRadius: 14))
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
                    Label("Go again", systemImage: "arrow.counterclockwise").frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("card-go-again")
            }
        }
        .padding(18)
        .background(.regularMaterial, in: .rect(cornerRadius: 24))
        .shadow(color: .black.opacity(0.18), radius: 16, y: 6)
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
            Text(offer.text).font(.callout.weight(.medium))
            Spacer()
            Button("Undo") { model.undoDiscard() }
                .font(.callout.weight(.bold))
                .accessibilityIdentifier("undo-discard")
        }
        .padding(16)
        .background(.regularMaterial, in: .capsule)
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
                    .foregroundStyle(star <= rating ? Color.yellow : Color.secondary)
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
                            Text(take.name).font(.body.weight(.medium))
                            Text("Bar \(take.start.bar) · \(SessionView.clock(take.lengthSeconds))")
                                .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                        }
                        Spacer()
                        Stars(rating: take.rating) { model.rate(take, $0) }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("take-\(take.name)")
                }
            }
            .navigationTitle("Takes")
        }
    }
}

/// Arm, select and monitor the session's tracks.
struct TracksView: View {
    @Bindable var model: AppModel

    var body: some View {
        NavigationStack {
            List(model.state.tracks) { track in
                HStack(spacing: 12) {
                    Image(systemName: track.kind == .audio ? "waveform" : "pianokeys")
                        .foregroundStyle(Color(hex: track.color) ?? .secondary)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(track.name).font(.body.weight(track.selected ? .bold : .regular))
                        if track.kind == .midi {
                            Text("Monitor: \(track.monitor.rawValue)").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if let peak = model.state.meters[track.id] {
                        MeterBar(level: peak.max() ?? 0).frame(width: 60, height: 6)
                    }
                    Button {
                        model.act("arm-\(track.id)", "tracks.arm", ["track_id": .string(track.id), "armed": .bool(!track.armed)])
                    } label: {
                        Image(systemName: track.armed ? "record.circle.fill" : "record.circle")
                            .font(.title2)
                            .foregroundStyle(track.armed ? .red : .secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(track.armed ? "Disarm \(track.name)" : "Arm \(track.name)")
                    .accessibilityIdentifier("track-arm-\(track.name)")
                }
                .contentShape(.rect)
                .onTapGesture {
                    model.act("select-\(track.id)", "tracks.select", ["track_id": .string(track.id)])
                }
                .swipeActions {
                    if track.kind == .midi, model.state.capabilities.contains("tracks.monitor/1") {
                        Button("Monitor") {
                            let next: MonitorMode = track.monitor == .on ? .off : track.monitor == .off ? .auto : .on
                            model.act("monitor-\(track.id)", "tracks.set_monitor",
                                      ["track_id": .string(track.id), "mode": .string(next.rawValue)])
                        }
                    }
                }
                .accessibilityElement(children: .contain)     // the arm button stays reachable
                .accessibilityAction(named: "Select \(track.name)") {
                    model.act("select-\(track.id)", "tracks.select", ["track_id": .string(track.id)])
                }
                .accessibilityIdentifier("track-\(track.name)")
            }
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
