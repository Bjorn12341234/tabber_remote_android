import RemoteKit
import SwiftUI
import VisionKit

/// The first screen on a fresh install (plan: TR6): what the app is, then
/// Find your computer and the QR code, or the demo.
struct WelcomeView: View {
    @Bindable var model: AppModel

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Spacer()
                Image("SpakMark")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 132, height: 132)
                    .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                    .accessibilityHidden(true)
                Text("Tabber Spak")
                    .font(.largeTitle.bold())
                Text("Record, stop and go again from across the room. Your computer runs Tabber Studio; this iPhone is its remote.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
                Spacer()
                NavigationLink {
                    FindComputerView(model: model)
                } label: {
                    Text("Get Started").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityIdentifier("get-started")
                Button {
                    model.startDemo()
                } label: {
                    Text("Try the Demo").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .accessibilityIdentifier("demo")
            }
            .padding(24)
            .frame(maxWidth: 520)
        }
    }
}

/// Find your computer: an explainer before iOS asks for the local network,
/// then the computers Bonjour finds (plan: Find your Mac).
struct FindComputerView: View {
    @Bindable var model: AppModel
    @State private var found: [FoundComputer] = []
    @State private var denied = false
    @State private var searchedLong = false

    var body: some View {
        Group {
            if model.explainedLocalNetwork { finder } else { explainer }
        }
        .navigationTitle("Find Your Computer")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var explainer: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "wifi")
                .font(.system(size: 56, weight: .semibold))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text("Tabber Spak finds Tabber Studio on this Wi-Fi")
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            Text("Next, iPhone asks whether Tabber Spak may find devices on your local network. Tap Allow: that is how it reaches your computer. Nothing leaves your network.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
            Button {
                model.explainedLocalNetwork = true
            } label: {
                Text("Continue").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityIdentifier("continue")
        }
        .padding(24)
    }

    private var finder: some View {
        List {
            Section {
                ForEach(found) { computer in
                    Button {
                        model.scanTarget = computer.name
                        model.scanning = true
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(computer.name).foregroundStyle(.primary)
                                Text("Tabber Studio: scan its code to pair").font(.caption).foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "desktopcomputer")
                        }
                    }
                    .accessibilityIdentifier("found-computer")
                }
                if found.isEmpty && !denied {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Looking for Tabber Studio…").foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("searching")
                }
            } header: {
                Text("On this Wi-Fi")
            } footer: {
                Text("In Tabber Studio on your computer, open Settings › Remote, turn it on and click Pair iPhone.")
            }
            if denied {
                Section {
                    FixItCard(model: model, trouble: .localNetworkDenied, computer: "your computer")
                        .listRowInsets(EdgeInsets())
                }
            } else if found.isEmpty && searchedLong {
                Section {
                    Text("No computer found yet. The code works without this list: it carries the computer's address. On a guest or venue Wi-Fi, use your own router.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("nothing-found")
                }
            }
            Section {
                Button {
                    model.scanTarget = found.count == 1 ? found[0].name : nil
                    model.scanning = true
                } label: {
                    Label("Scan the Code", systemImage: "qrcode.viewfinder")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .listRowInsets(EdgeInsets())
                .accessibilityIdentifier("scan")
            }
        }
        .task {
            let patience = Task { @MainActor in
                try? await Task.sleep(for: .seconds(6))
                searchedLong = true
            }
            defer { patience.cancel() }
            for await update in Discovery.browse() {
                switch update {
                case .found(let list):
                    found = list
                    denied = false
                case .denied:
                    denied = true
                case .failed:
                    break
                }
            }
        }
    }
}

/// The QR scanner (VisionKit). Without a camera (the Simulator) or without
/// camera access, the link can be pasted instead.
struct ScannerSheet: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var linkText = ""
    @State private var notACode = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
                    QRScanner { handle($0) }
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .accessibilityLabel("Camera, looking for the code")
                    Text(hint)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                } else {
                    paste
                }
                if notACode {
                    Label("That is not a Tabber Studio pairing code.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .accessibilityIdentifier("not-a-code")
                }
            }
            .padding(20)
            .navigationTitle("Scan the Code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var hint: String {
        "In Tabber Studio on \(model.scanTarget ?? "your computer"): Settings › Remote, then Pair iPhone. Point the camera at the code."
    }

    @ViewBuilder private var paste: some View {
        VStack(alignment: .leading, spacing: 12) {
            if DataScannerViewController.isSupported {
                Text("Tabber Spak may not use the camera. Allow it in Settings › Tabber Spak, or paste the link instead.")
                Button("Open Settings") { FixItCard.openSettings() }
            } else {
                Text("This device cannot scan codes. Paste the link that Pair iPhone in Tabber Studio shows.")
            }
            TextField("tabber-remote://pair?…", text: $linkText, axis: .vertical)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.footnote.monospaced())
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("pair-link-field")
            Button("Pair") { handle(linkText) }
                .buttonStyle(.borderedProminent)
                .disabled(linkText.isEmpty)
                .accessibilityIdentifier("pair-link-button")
            Spacer()
        }
    }

    private func handle(_ text: String) {
        guard let link = PairingLink(string: text.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            notACode = true
            return
        }
        dismiss()
        Task { await model.pair(with: link) }
    }
}

/// VisionKit's live scanner, for QR codes only.
struct QRScanner: UIViewControllerRepresentable {
    let found: @MainActor (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(recognizedDataTypes: [.barcode(symbologies: [.qr])],
                                                qualityLevel: .balanced, recognizesMultipleItems: false,
                                                isHighFrameRateTrackingEnabled: false, isPinchToZoomEnabled: true,
                                                isGuidanceEnabled: true, isHighlightingEnabled: true)
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        if !scanner.isScanning { try? scanner.startScanning() }
    }

    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) {
        scanner.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(found: found) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let found: @MainActor (String) -> Void
        private var done = false
        init(found: @escaping @MainActor (String) -> Void) { self.found = found }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem],
                         allItems: [RecognizedItem]) {
            guard !done else { return }
            for item in addedItems {
                if case .barcode(let code) = item, let text = code.payloadStringValue {
                    if PairingLink(string: text) != nil { done = true }
                    found(text)
                    return
                }
            }
        }
    }
}

/// Pairing in progress, over whatever screen is showing.
struct PairingOverlay: View {
    let name: String

    var body: some View {
        VStack(spacing: 14) {
            ProgressView().controlSize(.large)
            Text("Pairing with \(name)…").font(.headline)
        }
        .padding(28)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("pairing")
    }
}
