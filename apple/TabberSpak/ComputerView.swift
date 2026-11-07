import RemoteKit
import SwiftUI

/// The Computer sheet, from the computer's name at the top of every screen:
/// which computer this iPhone runs, how the line is, and pairing again or
/// forgetting it (plan: The app, screen 7).
struct ComputerView: View {
    @Bindable var model: AppModel
    @State private var confirmForget = false
    @State private var times = ResponseTimes()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Computer") {
                    LabeledContent("Computer", value: computerName)
                        .accessibilityIdentifier("host-name")
                    LabeledContent("State", value: linkLabel)
                        .accessibilityIdentifier("link-state")
                    if let route = model.known?.routes.first, !model.isDemo {
                        LabeledContent("Address", value: route.description)
                            .font(.callout.monospaced())
                    }
                    if let trouble = model.state.trouble {
                        FixItView(model: model, trouble: trouble, computer: computerName)
                            .padding(.vertical, 8)
                    }
                }
                .listRowBackground(Studio.bg1)
                Section {
                    Button("Pair again") {
                        model.scanTarget = model.known?.name
                        model.showingComputer = false
                        model.scanning = true
                    }
                    .accessibilityIdentifier("pair-again")
                    if model.isDemo {
                        Button("Leave the demo") { model.leaveDemo() }
                            .accessibilityIdentifier("leave-demo")
                    } else if model.known != nil {
                        Button("Forget this computer", role: .destructive) { confirmForget = true }
                            .accessibilityIdentifier("forget")
                    }
                }
                .listRowBackground(Studio.bg1)
                Section {
                    Toggle("Keep the screen awake during a session", isOn: $model.keepAwake)
                }
                .listRowBackground(Studio.bg1)
                ResponseTimeSection(times: times, computer: computerName) {
                    Task {
                        await model.startResponseTimesAgain()
                        times = await model.responseTimes()
                    }
                }
                Section {
                    LabeledContent("Tabber Spak", value: "\(AppModel.app.version) (\(AppModel.app.build))")
                    LabeledContent("Protocol", value: RemoteClient.protocolVersions.joined(separator: ", "))
                }
                .listRowBackground(Studio.bg1)
            }
            .studioList()
            // Read once: while the sheet is open its controls are covered, so no tap lands.
            .task { times = await model.responseTimes() }
            .navigationTitle("Computer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.accessibilityIdentifier("done")
                }
            }
            .confirmationDialog("Forget \(computerName)?", isPresented: $confirmForget, titleVisibility: .visible) {
                Button("Forget", role: .destructive) { model.forget() }
            } message: {
                Text("To use it again, pair again with its code.")
            }
        }
    }

    private var computerName: String { model.computerName }

    private var linkLabel: String {
        switch model.state.link {
        case .idle: "Not connected"
        case .connecting: "Connecting"
        case .connected(let busy): busy ? "Connected, Tabber Studio is busy" : "Connected"
        case .reconnecting: "Reconnecting"
        case .failed: "Stopped"
        }
    }
}

/// How long the computer takes to answer this phone, from a tap to the
/// confirmed state (TR7's gate: 19 taps in 20 within 150 ms on home Wi-Fi).
/// Measured on the phone. Start again before a second run, as with AirDrop
/// on after a run with it off.
private struct ResponseTimeSection: View {
    let times: ResponseTimes
    let computer: String
    let startAgain: () -> Void

    var body: some View {
        Section {
            LabeledContent("Typical", value: shown(times.median))
                .accessibilityIdentifier("response-typical")
            LabeledContent("19 in 20 taps within", value: shown(times.p95))
                .accessibilityIdentifier("response-p95")
            Button("Start again", action: startAgain)
                .disabled(times.count == 0)
                .accessibilityIdentifier("response-again")
        } header: {
            Text("Response time")
        } footer: {
            Text(note)
                .accessibilityIdentifier("response-note")
        }
        .listRowBackground(Studio.bg1)
    }

    private var note: String {
        switch times.count {
        case 0: "Tap a control, like Play, and the time \(computer) takes to answer shows here."
        case 1: "From a tap on this iPhone to \(computer)'s answer, over 1 tap."
        default: "From a tap on this iPhone to \(computer)'s answer, over the last \(times.count) taps."
        }
    }

    private func shown(_ time: Duration?) -> String {
        time.map { "\($0.milliseconds) ms" } ?? "Not yet"
    }
}
