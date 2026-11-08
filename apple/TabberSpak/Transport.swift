import RemoteKit
import SwiftUI

/// Tabber Studio's transport, in the same place on every screen: Stop, Play
/// and Record, then the position. While recording, the position becomes the
/// take's time in red; during a count-in, the beats left in amber. Tapping the
/// position goes to the start or to a marker.
struct TransportBar: View {
    @Bindable var model: AppModel
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement

    /// One identifier per control: iOS keeps a second, inline copy of the accessory.
    private func id(_ name: String) -> String { placement == .inline ? "\(name)-inline" : name }

    var body: some View {
        let recording = model.bar.recording
        let playing = model.bar.playing
        HStack(spacing: 2) {
            Button(action: model.stopButton) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Studio.text1)
                    .frame(width: 14, height: 14)
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .accessibilityLabel(playing || recording ? "Stop" : "Go to the start")
            .accessibilityIdentifier(id("stop"))

            // Tabber Studio's Play is Play / Pause: ❚❚ while playing stops right
            // there, and Play goes on from where it stopped.
            Button(action: model.playOrStop) {
                Image(systemName: playing ? "pause.fill" : "play.fill")
                    .font(.system(size: 19))
                    .foregroundStyle(playing && !recording ? Studio.accent : Studio.text1)
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .opacity(model.pending.contains("play") ? 0.5 : 1)
            .accessibilityLabel(playing ? "Pause" : "Play")
            .accessibilityAddTraits(playing ? .isSelected : [])
            .accessibilityIdentifier(id("play"))

            Button(action: model.record) {
                ZStack {
                    Circle().fill(recording ? Studio.record.opacity(0.22) : .clear).frame(width: 36, height: 36)
                    Circle().fill(Studio.record).frame(width: 17, height: 17)
                }
                .frame(width: 44, height: 44)
                .contentShape(.rect)
            }
            .opacity(model.pending.contains("record") || model.pending.contains("stop") ? 0.5 : 1)
            .accessibilityLabel(recording ? "Stop recording" : model.bar.armed.isEmpty ? "Record"
                                : "Record on \(model.bar.armed.joined(separator: " and "))")
            .accessibilityIdentifier(id("record"))

            Spacer(minLength: 6)
            Readout(model: model)
                .accessibilityIdentifier(id("readout"))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .disabled(!model.bar.connected)
        .opacity(model.bar.connected ? 1 : 0.45)
    }
}

/// Where the song is: Tabber Studio's POS, or the take's time while
/// recording, counted by the system's own timer text so nothing redraws.
private struct Readout: View {
    @Bindable var model: AppModel

    var body: some View {
        // Nothing presents from inside the tab bar's accessory, so the root view shows Go to.
        Button { model.choosingPlace = true } label: {
            content
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(spoken)
        .accessibilityHint("Go to the start or a marker.")
    }

    @ViewBuilder private var content: some View {
        let bar = model.bar                       // the summary only: no redraw for every meter
        if let since = bar.recordingSince {
            HStack(spacing: 7) {
                Circle().fill(Studio.record).frame(width: 8, height: 8)
                Text("REC").font(.caption.weight(.bold)).foregroundStyle(Studio.record)
                Text(timerInterval: since...Date.distantFuture, countsDown: false)
                    .font(Studio.counter(.title3, weight: .semibold))
                    .foregroundStyle(Studio.record)
                    .monospacedDigit()
            }
        } else if bar.countingIn {
            Text("Count-in").font(.subheadline.weight(.semibold)).foregroundStyle(Studio.playhead)
        } else if let position = bar.position {
            HStack(spacing: 7) {
                ReadoutLabel("POS")
                Text("\(position.bar) : \(position.beat)")
                    .font(Studio.counter(.title3, weight: .semibold))
                    .foregroundStyle(Studio.text1)
            }
        } else {
            Text("Not connected").font(.subheadline).foregroundStyle(Studio.text2)
        }
    }

    private var spoken: String {
        let bar = model.bar
        if bar.recordingSince != nil { return "Recording" }
        if bar.countingIn { return "Count-in" }
        guard let position = bar.position else { return "Not connected" }
        return "Bar \(position.bar), beat \(position.beat)"
    }
}

/// Go to: the start or one of the song's markers, from the transport's position.
struct GoToSheet: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                row("Start", bar: 1) { model.goToStart() }
                ForEach(model.state.markers) { marker in
                    row(marker.name, bar: marker.bar) { model.go(to: marker) }
                }
            }
            .studioList()
            .navigationTitle("Go to")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func row(_ name: String, bar: Int, _ go: @escaping () -> Void) -> some View {
        Button {
            go()
            dismiss()
        } label: {
            HStack {
                Text(name).font(.body.weight(.semibold)).foregroundStyle(Studio.text1)
                Spacer()
                Text("Bar \(bar)").font(Studio.counter(.subheadline)).foregroundStyle(Studio.text2)
            }
            .frame(minHeight: 44)
            .contentShape(.rect)
        }
        .listRowBackground(Studio.bg2)
        .accessibilityLabel("\(name), bar \(bar)")
        .accessibilityIdentifier("goto-\(name)")
    }
}
