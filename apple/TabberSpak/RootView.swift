import RemoteKit
import SwiftUI

struct RootView: View {
    @Bindable var model: AppModel

    var body: some View {
        Group {
            if !model.bar.hasSession && model.known == nil && !model.isDemo {
                DebugView(model: model)            // pairing; TR6 replaces it with Welcome
            } else {
                TabView {
                    Tab("Session", systemImage: "record.circle") { SessionView(model: model) }
                    Tab("Takes", systemImage: "square.stack") { TakesView(model: model) }
                    Tab("Tracks", systemImage: "slider.vertical.3") { TracksView(model: model) }
                    Tab("Computer", systemImage: "desktopcomputer") { DebugView(model: model) }
                }
                .tabViewBottomAccessory { TransportBar(model: model) }
                .tabBarMinimizeBehavior(.never)          // the transport never moves (principle 5)
            }
        }
        .tint(Color(red: 0.898, green: 0.282, blue: 0.302))
        .sensoryFeedback(trigger: model.feedback.count) { _, _ in
            switch model.feedback.kind {
            case .tap: .selection
            case .record: .impact(weight: .heavy, intensity: 1)
            case .stop: .impact(weight: .medium, intensity: 0.9)
            case .goAgain: .success
            case .discard: .warning
            case .failure: .error
            }
        }
        .onChange(of: model.bar.connected, initial: true) { _, connected in
            UIApplication.shared.isIdleTimerDisabled = connected && model.keepAwake
        }
    }
}

/// Go again, Record and Play/Stop: in the same place on every screen (principle 5).
struct TransportBar: View {
    @Bindable var model: AppModel
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement

    /// One identifier per control: iOS keeps a second, inline copy of the accessory.
    private func id(_ name: String) -> String { placement == .inline ? "\(name)-inline" : name }

    var body: some View {
        let recording = model.bar.recording
        let playing = model.bar.playing
        let armed = model.bar.armed
        HStack(spacing: 0) {
            Button(action: model.goAgain) {
                Label("Go again", systemImage: "arrow.counterclockwise.circle.fill")
                    .labelStyle(.iconOnly)
                    .font(.system(size: 30))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .disabled(model.lastTake == nil && !model.bar.hasTake)
            .opacity(model.pending.contains("goagain") ? 0.5 : 1)
            .accessibilityLabel("Go again")
            .accessibilityIdentifier(id("go-again"))

            Button(action: model.record) {
                ZStack {
                    Circle().fill(recording ? Color.red : Color.clear)
                    Circle().strokeBorder(Color.red, lineWidth: 4)
                    if recording {
                        RoundedRectangle(cornerRadius: 3).fill(.white).frame(width: 14, height: 14)
                    } else {
                        Circle().fill(Color.red).padding(10)
                    }
                }
                .frame(width: 46, height: 46)
                .opacity(model.pending.contains("record") || model.pending.contains("stop") ? 0.5 : 1)
                .frame(maxWidth: .infinity)
            }
            .accessibilityLabel(recording ? "Stop recording" : armed.isEmpty ? "Record" : "Record on \(armed.joined(separator: ", "))")
            .accessibilityIdentifier(id("record"))

            Button(action: model.playOrStop) {
                Image(systemName: playing ? "stop.fill" : "play.fill")
                    .font(.system(size: 26))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .opacity(model.pending.contains("play") ? 0.5 : 1)
            .accessibilityLabel(playing ? "Stop" : "Play")
            .accessibilityIdentifier(id("play"))
        }
        .disabled(!model.bar.connected)
    }
}
