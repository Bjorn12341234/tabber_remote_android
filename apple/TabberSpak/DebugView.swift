import RemoteKit
import SwiftUI

/// TR5's debug screen: connect to DemoHost or pair with a computer, and see
/// the confirmed session. TR7 replaces it with the Session screen.
struct DebugView: View {
    @Bindable var model: AppModel
    @State private var linkText = ""

    var body: some View {
        NavigationStack {
            List {
                Section("Connection") {
                    LabeledContent("State", value: linkLabel)
                        .accessibilityIdentifier("link-state")
                    if let host = model.state.host {
                        LabeledContent("Computer", value: host.name)
                            .accessibilityIdentifier("host-name")
                    }
                    if let problem = model.problem {
                        Text(problem).foregroundStyle(.red).accessibilityIdentifier("problem")
                    }
                }
                if model.state.transport != nil {
                    sessionSection
                    actionsSection
                } else {
                    pairingSection
                }
            }
            .navigationTitle("Tabber Spak")
            .toolbar {
                if model.known != nil || model.isDemo {
                    Button("Forget", role: .destructive) { model.forget() }
                }
            }
        }
    }

    private var linkLabel: String {
        switch model.state.link {
        case .idle: "Not connected"
        case .connecting: "Connecting"
        case .connected(let busy): busy ? "Connected, Tabber Studio is busy" : "Connected"
        case .reconnecting: "Reconnecting"
        case .failed(let reason): "Stopped: \(reason)"
        }
    }

    private var sessionSection: some View {
        Section("Session") {
            LabeledContent("Song", value: model.state.project.title + (model.state.project.unsaved ? " *" : ""))
            if let transport = model.state.transport {
                LabeledContent("Playhead", value: "\(transport.position.bar) . \(transport.position.beat)")
                    .monospacedDigit()
                    .accessibilityIdentifier("playhead")
                LabeledContent("Transport", value: transport.state.rawValue)
                    .accessibilityIdentifier("transport-state")
            }
            LabeledContent("Recording", value: model.state.record.recording ? "REC" : "no")
                .accessibilityIdentifier("record-state")
            LabeledContent("Armed", value: armedNames)
            LabeledContent("Takes", value: "\(model.state.takes.count)")
                .accessibilityIdentifier("take-count")
            if let undo = model.state.undo.undo {
                LabeledContent("Undo", value: undo.label)
            }
        }
    }

    private var armedNames: String {
        let names = model.state.tracks.filter(\.armed).map(\.name)
        return names.isEmpty ? "none" : names.joined(separator: ", ")
    }

    private var actionsSection: some View {
        Section("Try it") {
            if let first = model.state.tracks.first {
                Button(first.armed ? "Disarm \(first.name)" : "Arm \(first.name)") {
                    model.perform("tracks.arm", ["track_id": .string(first.id), "armed": .bool(!first.armed)])
                }
                .accessibilityIdentifier("arm-first")
            }
            Button("Record") {
                model.perform("transport.record",
                              ["armed_track_ids": .array(model.state.tracks.filter(\.armed).map { .string($0.id) })])
            }
            .disabled(model.state.tracks.allSatisfy { !$0.armed } || model.state.record.recording)
            .accessibilityIdentifier("record")
            Button("Stop") { model.perform("transport.stop") }
                .accessibilityIdentifier("stop")
            Button("Play") { model.perform("transport.play") }
                .accessibilityIdentifier("play")
        }
    }

    private var pairingSection: some View {
        Section {
            TextField("tabber-remote://pair?...", text: $linkText, axis: .vertical)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.footnote.monospaced())
            Button("Pair with this link") {
                if let link = PairingLink(string: linkText.trimmingCharacters(in: .whitespacesAndNewlines)) {
                    Task { await model.pair(with: link) }
                }
            }
            .disabled(PairingLink(string: linkText.trimmingCharacters(in: .whitespacesAndNewlines)) == nil)
            Button("Try the demo session") { model.startDemo() }
                .accessibilityIdentifier("demo")
        } header: {
            Text("Pair")
        } footer: {
            Text("Paste the link Tabber Studio's Pair iPhone shows, or open it on this device.")
        }
    }
}
