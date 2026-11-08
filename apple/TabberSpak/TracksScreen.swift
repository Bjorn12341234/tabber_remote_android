import RemoteKit
import SwiftUI

/// The song's tracks, as Tabber Studio's Tracks panel shows them: tap a track
/// to choose it (the Tab screen writes on it), S to hear it alone, M to
/// silence it, ○ to record on it; "+ Add Track" under the last one. Below
/// them, the takes, each one tap from deletion.
struct TracksScreen: View {
    @Bindable var model: AppModel
    @Environment(\.dynamicTypeSize) private var textSize

    var body: some View {
        NavigationStack {
            Connected(model: model) {
                ScrollViewReader { list in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            if textSize.isAccessibilitySize {
                                controls             // at the largest text they would fill the screen, so they scroll
                            }
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
                                        .id(track.id)
                                }
                                if model.addTrackAvailable {
                                    AddTrackButton(model: model)
                                }
                            }
                            TakesSection(model: model)
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 4)
                        .padding(.bottom, 24)
                    }
                    // A track added from here is in view, however long the list.
                    .onChange(of: model.addedTrackID) { _, added in
                        guard let added else { return }
                        withAnimation { list.scrollTo(added, anchor: .center) }
                    }
                    // The owner: "the arrange and the stuff up top should stay up top
                    // even when you scroll down if there is a lot of tracks."
                    .safeAreaInset(edge: .top, spacing: 0) {
                        if !textSize.isAccessibilitySize {
                            controls
                                .padding(.horizontal, 16)
                                .padding(.top, 4)
                                .padding(.bottom, 12)
                                .background(Studio.bg1)
                        }
                    }
                }
            }
            .background(Studio.bg1)
            .navigationTitle(model.state.project.title.isEmpty ? "Tracks" : model.state.project.title)
            // In the bar, as on the other screens: a large title over the pinned
            // controls vanished after a visit to another tab (iOS 26).
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { ComputerChip(model: model) } }
            .takeSlot(model: model)
        }
    }

    /// What stays at the top: the computer's view, then Studio's transport
    /// toggles, and the Speed Trainer while Loop is on.
    private var controls: some View {
        VStack(alignment: .leading, spacing: 16) {
            if model.viewAvailable {
                ViewButtons(model: model)
            }
            VStack(alignment: .leading, spacing: 8) {
                RecordOptions(model: model)
                if model.trainerAvailable, model.state.transport?.loop.enabled == true {
                    TrainerRow(model: model)
                }
            }
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

/// Tabber Studio's "+ Add Track" under the last track, and its chooser: a
/// tab, MIDI or audio track, each as the computer makes it.
struct AddTrackButton: View {
    @Bindable var model: AppModel
    @State private var choosing = false

    var body: some View {
        Button("+ Add Track") { choosing = true }
            .buttonStyle(.studioGhost)
            // Not during a take: in Tabber Studio a new track clears the record arms.
            .disabled(model.pending.contains("add-track") || model.state.record.recording)
            .accessibilityLabel("Add Track")
            .accessibilityHint("Adds a tab, MIDI or audio track to the song on the computer.")
            .accessibilityIdentifier("add-track")
            .confirmationDialog("What kind of track do you want to add?", isPresented: $choosing,
                                titleVisibility: .visible) {
                Button("Tab track") { model.addTrack(.tab) }
                Button("MIDI track") { model.addTrack(.midi) }
                Button("Audio track") { model.addTrack(.audio) }
                Button("Cancel", role: .cancel) {}
            }
            .tint(Studio.text1)        // choices in plain words, as Studio's chooser has them: teal is for what is selected
    }
}

/// What Tabber Studio shows on the computer, switched as its own view
/// buttons do: Arrange, Tab or Piano Roll as one choice, and Split beside
/// them. A native segmented control, as Mixer | Routing is, so the three fit
/// at any width; at the largest text sizes Split goes on a line of its own.
struct ViewButtons: View {
    @Bindable var model: AppModel

    var body: some View {
        let view = model.state.view
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { editors(view); split(view) }
            VStack(alignment: .leading, spacing: 8) { editors(view); split(view) }
        }
    }

    private func editors(_ view: ViewState?) -> some View {
        Picker("Computer view", selection: Binding(get: { view?.editor ?? "tab" },
                                                    set: { model.showEditor($0) })) {
            Text("Arrange").tag("arrange")
            Text("Tab").tag("tab")
            Text("Piano Roll").tag("piano_roll")
        }
        .pickerStyle(.segmented)
        .frame(minWidth: 240)
        .accessibilityLabel("What the computer shows")
        .accessibilityIdentifier("view-editor")
    }

    private func split(_ view: ViewState?) -> some View {
        Button { model.toggleSplit() } label: {
            Text("Split")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle((view?.split ?? false) ? Studio.text1 : Studio.text2)
                .padding(.horizontal, 14)
                .frame(minHeight: 32)
                .background((view?.split ?? false) ? Studio.bgOn : Studio.bg3,
                            in: RoundedRectangle(cornerRadius: Studio.radiusControl, style: .continuous))
                .fixedSize()
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Split view on the computer")
        .accessibilityAddTraits((view?.split ?? false) ? .isSelected : [])
        .accessibilityIdentifier("view-split")
    }
}

/// Tabber Studio's transport toggles that matter for a take.
struct RecordOptions: View {
    @Bindable var model: AppModel

    var body: some View {
        // Side by side when they fit; stacked at the largest text, so no word breaks.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 4) { chips }
            VStack(spacing: 4) { chips }
        }
        .padding(3)
        .studioWell(radius: Studio.radiusControl + 3)
    }

    @ViewBuilder private var chips: some View {
        let transport = model.state.transport
        ToggleChip(title: "Loop", isOn: transport?.loop.enabled ?? false, action: model.toggleLoop)
            .accessibilityIdentifier("loop")
        ToggleChip(title: "Count-in", isOn: (transport?.countInBars ?? 0) > 0,
                   spoken: (transport?.countInBars ?? 0) > 0 ? "Count-in, one bar" : "Count-in", action: model.toggleCountIn)
            .accessibilityHint("Counts one bar in before recording.")
            .accessibilityIdentifier("count-in")
        ToggleChip(title: "Metro", isOn: transport?.click ?? false, spoken: "Metronome", action: model.toggleClick)
            .accessibilityIdentifier("click")
    }
}

/// Tabber Studio's Speed Trainer, shown as there only while Loop is on (the
/// plan's S6: loop the solo at 70% and step the speed up). The Trainer
/// button, the start speed, the step added each time the loop comes round
/// and the target, then the speed now, in Studio's order and its monospaced
/// figures.
struct TrainerRow: View {
    @Bindable var model: AppModel

    @Environment(\.dynamicTypeSize) private var textSize

    var body: some View {
        let trainer = model.state.trainer ?? TrainerState()
        // The button and the speed now, then the fields in Studio's order; at
        // the accessibility text sizes, each field on a line of its own, named.
        VStack(alignment: .leading, spacing: 6) {
            top(trainer)
            if textSize.isAccessibilitySize {
                named("Start", field("start", spoken: "Start speed", trainer.start, TrainerState.starts))
                named("Faster each loop by", field("step", spoken: "Faster each loop by", trainer.step, TrainerState.steps))
                named("Up to", field("target", spoken: "Target speed", trainer.target, TrainerState.targets))
            } else {
                fields(trainer)
            }
        }
        .padding(3)
        .studioWell(radius: Studio.radiusControl + 3)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("trainer-row")
    }

    private func top(_ trainer: TrainerState) -> some View {
        HStack(spacing: 6) {
            button(trainer)
            Spacer(minLength: 0)
            speed(trainer)
        }
    }

    private func named(_ title: String, _ field: some View) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(Studio.text2)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityHidden(true)
            Spacer(minLength: 0)
            field
        }
        .padding(.leading, 8)
    }

    private func button(_ trainer: TrainerState) -> some View {
        ToggleChip(title: "Trainer", isOn: trainer.enabled, spoken: "Speed Trainer", action: model.toggleTrainer)
            .fixedSize()
            .accessibilityIdentifier("trainer")
    }

    private func fields(_ trainer: TrainerState) -> some View {
        HStack(spacing: 4) {
            field("start", spoken: "Start speed", trainer.start, TrainerState.starts)
            sign("plus")
            field("step", spoken: "Faster each loop by", trainer.step, TrainerState.steps)
            sign("arrow.right")
            field("target", spoken: "Target speed", trainer.target, TrainerState.targets)
        }
    }

    /// Studio's "+" and "→" between the fields, as symbols that grow with the text.
    private func sign(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Studio.text2)
            .accessibilityHidden(true)
    }

    private func field(_ name: String, spoken: String, _ value: Int, _ base: [Int]) -> some View {
        Menu {
            Picker(spoken, selection: Binding(get: { value }, set: { model.setTrainer(name, $0) })) {
                ForEach(TrainerState.choices(base, with: value), id: \.self) { Text("\($0)%").tag($0) }
            }
        } label: {
            Text("\(value)%")
                .font(Studio.counter(.subheadline))
                .foregroundStyle(Studio.text1)
                .fixedSize()
                .accessibilityIdentifier("trainer-\(name)-value")   // the same in every layout
                .padding(.horizontal, 10)
                .frame(minHeight: 44)
                .background(Studio.bg3, in: RoundedRectangle(cornerRadius: Studio.radiusControl, style: .continuous))
                .contentShape(.rect)
        }
        .accessibilityLabel(spoken)
        .accessibilityValue("\(value) percent")
        .accessibilityIdentifier("trainer-\(name)")
    }

    private func speed(_ trainer: TrainerState) -> some View {
        Text("\(trainer.speed)%")
            .font(Studio.counter(.subheadline, weight: .bold))
            .foregroundStyle(trainer.enabled ? Studio.text1 : Studio.text2)
            .padding(.trailing, 8)
            .fixedSize()
            .accessibilityLabel("Speed now")
            .accessibilityValue("\(trainer.speed) percent")
            .accessibilityIdentifier("trainer-speed")
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
                    .truncationMode(.tail)
                    .frame(maxWidth: 150, alignment: .leading)   // a long name never runs into the bar's other buttons
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
