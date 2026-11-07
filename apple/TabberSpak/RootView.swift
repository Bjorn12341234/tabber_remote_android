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
                TabView(selection: $model.screen) {
                    Tab("Tracks", systemImage: "rectangle.stack", value: AppModel.Screen.tracks) { TracksScreen(model: model) }
                    Tab("Tab", systemImage: "guitars", value: AppModel.Screen.tab) { TabScreen(model: model) }
                    Tab("Mixer", systemImage: "slider.vertical.3", value: AppModel.Screen.mixer) { MixerScreen(model: model) }
                    Tab("Tuner", systemImage: "tuningfork", value: AppModel.Screen.tuner) { TunerScreen(model: model) }
                    Tab("Chat", systemImage: "bubble.left.and.text.bubble.right", value: AppModel.Screen.chat) { ChatScreen(model: model) }
                }
                .tabViewBottomAccessory { TransportBar(model: model) }
                .tabBarMinimizeBehavior(.never)          // the transport never moves (principle 5)
            }
        }
        .overlay {
            if case .working(let name) = model.pairing { PairingOverlay(name: name) }
        }
        .sheet(isPresented: $model.scanning) { ScannerSheet(model: model) }
        .sheet(isPresented: $model.showingComputer) { ComputerView(model: model) }
        .sheet(isPresented: $model.choosingPlace) { GoToSheet(model: model) }
        .alert("Pairing did not work", isPresented: pairingFailed) {
            Button("Scan again") {
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
