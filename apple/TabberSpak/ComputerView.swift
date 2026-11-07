import RemoteKit
import SwiftUI

/// The Computer tab: which computer this iPhone runs, how the line is, and
/// pairing again or forgetting it (plan: The app, screen 7).
struct ComputerView: View {
    @Bindable var model: AppModel
    @State private var confirmForget = false

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
                Section {
                    LabeledContent("Tabber Spak", value: "\(AppModel.app.version) (\(AppModel.app.build))")
                    LabeledContent("Protocol", value: RemoteClient.protocolVersions.joined(separator: ", "))
                }
                .listRowBackground(Studio.bg1)
            }
            .studioList()
            .navigationTitle("Computer")
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
