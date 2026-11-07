import RemoteKit
import SwiftUI

struct RootView: View {
    @Bindable var model: AppModel
    @Environment(\.scenePhase) private var phase

    var body: some View {
        Group {
            if model.known == nil && !model.isDemo {
                WelcomeView(model: model)
            } else {
                TabView {
                    Tab("Session", systemImage: "record.circle") { SessionView(model: model) }
                    Tab("Takes", systemImage: "square.stack") { TakesView(model: model) }
                    Tab("Tracks", systemImage: "slider.vertical.3") { TracksView(model: model) }
                    Tab("Computer", systemImage: "desktopcomputer") { ComputerView(model: model) }
                }
                .tabViewBottomAccessory { TransportBar(model: model) }
                .tabBarMinimizeBehavior(.never)          // the transport never moves (principle 5)
            }
        }
        .overlay {
            if case .working(let name) = model.pairing { PairingOverlay(name: name) }
        }
        .sheet(isPresented: $model.scanning) { ScannerSheet(model: model) }
        .alert("Pairing did not work", isPresented: pairingFailed) {
            Button("Scan Again") {
                model.clearPairing()
                model.scanning = true
            }
            Button("OK", role: .cancel) { model.clearPairing() }
        } message: {
            if case .failed(let message) = model.pairing { Text(message) }
        }
        .onChange(of: phase) { _, now in
            if now == .active { model.wake() }       // back within a second (TR6)
        }
        .tint(Studio.accent)
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

extension RootView {
    private var pairingFailed: Binding<Bool> {
        Binding(get: { if case .failed = model.pairing { return true } else { return false } },
                set: { shown in if !shown, case .failed = model.pairing { model.clearPairing() } })
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
                Label("Go again", systemImage: "arrow.counterclockwise")
                    .labelStyle(.iconOnly)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(Studio.text1)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .disabled(model.lastTake == nil && !model.bar.hasTake)
            .opacity(model.pending.contains("goagain") ? 0.5 : 1)
            .accessibilityLabel("Go again")
            .accessibilityIdentifier(id("go-again"))

            Button(action: model.record) {
                ZStack {                            // Tabber Studio's record: a red dot
                    Circle().fill(Studio.record)
                        .frame(width: recording ? 40 : 30, height: recording ? 40 : 30)
                    if recording {
                        RoundedRectangle(cornerRadius: 2).fill(.white).frame(width: 13, height: 13)
                    }
                }
                .frame(width: 46, height: 46)
                .animation(.spring(duration: 0.25), value: recording)
                .opacity(model.pending.contains("record") || model.pending.contains("stop") ? 0.5 : model.bar.connected ? 1 : 0.35)
                .frame(maxWidth: .infinity)
            }
            .accessibilityLabel(recording ? "Stop recording" : armed.isEmpty ? "Record" : "Record on \(armed.joined(separator: ", "))")
            .accessibilityIdentifier(id("record"))

            Button(action: model.playOrStop) {
                Image(systemName: playing ? "stop.fill" : "play.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(Studio.text1)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .opacity(model.pending.contains("play") ? 0.5 : 1)
            .accessibilityLabel(playing ? "Stop" : "Play")
            .accessibilityIdentifier(id("play"))
        }
        .disabled(!model.bar.connected)
        .opacity(model.bar.connected ? 1 : 0.5)
    }
}
