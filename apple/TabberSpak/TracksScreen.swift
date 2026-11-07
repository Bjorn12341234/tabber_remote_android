import RemoteKit
import SwiftUI

/// The song's tracks, as Tabber Studio's Tracks panel shows them: tap a track
/// to choose it (the Tab screen writes on it), S to hear it alone, M to
/// silence it, ○ to record on it. Below them, the takes, each one tap from
/// deletion.
struct TracksScreen: View {
    @Bindable var model: AppModel

    var body: some View {
        NavigationStack {
            Connected(model: model) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        RecordOptions(model: model)
                        if showHint {
                            Text("To record, tap ○ on a track, then ● below.")
                                .font(.subheadline)
                                .foregroundStyle(Studio.text2)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("record-hint")
                        }
                        VStack(spacing: 8) {
                            ForEach(Array(model.state.tracks.enumerated()), id: \.element.id) { index, track in
                                TrackCard(model: model, track: track, index: index)
                            }
                        }
                        TakesSection(model: model)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .padding(.bottom, 24)
                }
            }
            .background(Studio.bg1)
            .navigationTitle(model.state.project.title.isEmpty ? "Tracks" : model.state.project.title)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { ComputerChip(model: model) } }
            .takeSlot(model: model)
        }
    }

    private var showHint: Bool {
        model.isConnected && !model.state.record.recording && !model.state.tracks.isEmpty
            && !model.state.tracks.contains(where: \.armed)
    }
}

/// One track, as a card in Tabber Studio's Tracks panel.
struct TrackCard: View {
    @Bindable var model: AppModel
    let track: Track
    let index: Int

    var body: some View {
        let strip = model.strip(track.id)
        let audible = model.audible(track.id)
        HStack(spacing: 0) {
            Button { model.select(track) } label: {
                HStack(alignment: .center, spacing: 10) {
                    RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                        .fill(Studio.track(track.color, index: index))
                        .frame(width: 10, height: 10)
                    Text("\(index + 1)")
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(Studio.text2)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(track.name)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(audible ? Studio.text1 : Studio.text3)
                            .fixedSize(horizontal: false, vertical: true)
                        if track.armed, let level = model.state.meters[track.id]?.max() {
                            LevelMeter(level: level)
                                .frame(height: 6)
                                .frame(maxWidth: 160)
                                .padding(.vertical, 4)
                                .accessibilityIdentifier("meter-\(track.name)")
                        } else {
                            Text(subtitle)
                                .font(.subheadline)
                                .foregroundStyle(Studio.text2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 4)
                }
                .padding(.vertical, 10)
                .padding(.leading, 14)
                .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(spoken(audible: audible))
            .accessibilityHint(track.selected ? "" : "Chooses this track. The Tab screen writes on it.")
            .accessibilityAddTraits(track.selected ? .isSelected : [])
            .accessibilityIdentifier("track-\(track.name)")

            if let strip {
                LetterButton(letter: "S", isOn: strip.soloed, onColor: Studio.solo,
                             spoken: strip.soloed ? "Stop hearing \(track.name) alone" : "Hear \(track.name) alone") {
                    model.solo(track.id)
                }
                .accessibilityIdentifier("solo-\(track.name)")
                LetterButton(letter: "M", isOn: strip.muted, onColor: Studio.mute,
                             spoken: strip.muted ? "Unmute \(track.name)" : "Mute \(track.name)") {
                    model.mute(track.id)
                }
                .accessibilityIdentifier("mute-\(track.name)")
            }
            ArmButton(armed: track.armed,
                      spoken: track.armed ? "Stop recording on \(track.name)" : "Record on \(track.name)") {
                model.arm(track)
            }
            .accessibilityIdentifier("arm-\(track.name)")
            .padding(.trailing, 4)
        }
        .studioCard(selected: track.selected)
        .accessibilityElement(children: .contain)
    }

    private var subtitle: String {
        if track.kind == .audio { return "Audio" }
        return track.instrument ?? "MIDI"
    }

    private func spoken(audible: Bool) -> String {
        var words = "\(track.name), \(track.armed ? "armed for recording" : subtitle)"
        if !audible { words += ", not heard" }
        return words
    }
}

/// Tabber Studio's transport toggles that matter for a take.
struct RecordOptions: View {
    @Bindable var model: AppModel

    var body: some View {
        let transport = model.state.transport
        HStack(spacing: 4) {
            ToggleChip(title: "Loop", isOn: transport?.loop.enabled ?? false, action: model.toggleLoop)
                .accessibilityIdentifier("loop")
            ToggleChip(title: "Count-in", isOn: (transport?.countInBars ?? 0) > 0,
                       spoken: (transport?.countInBars ?? 0) > 0 ? "Count-in, one bar" : "Count-in", action: model.toggleCountIn)
                .accessibilityIdentifier("count-in")
            ToggleChip(title: "Metro", isOn: transport?.click ?? false, spoken: "Metronome", action: model.toggleClick)
                .accessibilityIdentifier("click")
        }
        .padding(3)
        .studioWell(radius: Studio.radiusControl + 3)
    }
}

/// The takes, newest first: each says what it is and deletes with one tap.
struct TakesSection: View {
    @Bindable var model: AppModel

    var body: some View {
        let takes = model.state.takes
        if !takes.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Takes")
                    .font(.headline)
                    .foregroundStyle(Studio.text1)
                    .padding(.top, 8)
                    .accessibilityAddTraits(.isHeader)
                ForEach(takes) { take in
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                            .fill(color(take))
                            .frame(width: 10, height: 10)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(take.name)
                                .font(.body.weight(.semibold))
                                .foregroundStyle(take.active ? Studio.text1 : Studio.text2)
                            Text(detail(take))
                                .font(.subheadline)
                                .foregroundStyle(Studio.text2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("take-info-\(take.name)")
                        Button("Delete") { model.delete(take) }
                            .buttonStyle(.studioDestructive)
                            .opacity(model.pending.contains("delete-\(take.id)") ? 0.5 : 1)
                            .accessibilityLabel("Delete \(take.name)")
                            .accessibilityIdentifier("delete-\(take.name)")
                    }
                    .padding(.leading, 14)
                    .padding(.trailing, 8)
                    .padding(.vertical, 8)
                    .studioCard()
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("take-\(take.name)")
                }
            }
        }
    }

    /// A take that a newer one covers waits in its lane in Tabber Studio, as
    /// the computer's take lanes show it; the list says it doesn't play.
    private func detail(_ take: Take) -> String {
        let place = "\(Format.length(take.lengthSeconds)) from bar \(take.start.bar)"
        return take.active ? place : "\(place), not playing"
    }

    private func color(_ take: Take) -> Color {
        let index = model.state.tracks.firstIndex { $0.id == take.trackID } ?? 0
        return Studio.track(model.state.tracks.first { $0.id == take.trackID }?.color, index: index)
    }
}

/// The computer this phone runs, at the top of every screen; tap for the Computer sheet.
struct ComputerChip: View {
    @Bindable var model: AppModel

    var body: some View {
        Button { model.showingComputer = true } label: {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 7, height: 7)
                Text(model.computerName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Studio.text1)
                    .lineLimit(1)
            }
        }
        .accessibilityLabel("\(model.computerName), \(words)")
        .accessibilityHint("Shows the computer, pairing and settings.")
        .accessibilityIdentifier("connection")
    }

    private var color: Color {
        switch model.state.link {
        case .connected: Studio.accent
        case .connecting, .reconnecting: Studio.playhead
        case .failed, .idle: Studio.record
        }
    }

    private var words: String {
        switch model.state.link {
        case .connected: "connected"
        case .connecting: "connecting"
        case .reconnecting: "reconnecting"
        case .failed, .idle: "not connected"
        }
    }
}

/// A screen's content while the computer can be used; what to do when it can't.
struct Connected<Content: View>: View {
    @Bindable var model: AppModel
    @ViewBuilder let content: () -> Content

    var body: some View {
        if let trouble = model.state.trouble {
            ScrollView {
                FixItView(model: model, trouble: trouble, computer: model.computerName)
                    .padding(16)
            }
        } else if model.state.transport == nil {
            VStack(spacing: 12) {
                ProgressView().tint(Studio.text2)
                Text("Connecting to \(model.computerName)")
                    .font(.subheadline)
                    .foregroundStyle(Studio.text2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            content()
                .opacity(model.isConnected ? 1 : 0.5)
                .allowsHitTesting(model.isConnected)
        }
    }
}

extension View {
    /// The take card after a take, Undo after a delete, or what went wrong, above the transport.
    func takeSlot(model: AppModel) -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) {
            Group {
                if let take = model.lastTake {
                    TakeCard(model: model, take: take)
                } else if let offer = model.undoOffer {
                    UndoBanner(model: model, text: offer.text)
                } else if let problem = model.problem {
                    ProblemBanner(model: model, text: problem)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
            .animation(.spring(duration: 0.3), value: model.lastTake?.id)
        }
    }
}
