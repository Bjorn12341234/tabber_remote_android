import RemoteKit
import SwiftUI
import VisionKit

/// The first screen on a fresh install (plan: TR6): what Tabber Spak is for,
/// the three steps that pair it, and the demo for trying it without a computer.
struct WelcomeView: View {
    @Bindable var model: AppModel

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 24)
                Image("SpakMark")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .accessibilityHidden(true)
                Text("Tabber Spak")
                    .font(.largeTitle.bold())
                    .foregroundStyle(Studio.text1)
                    .padding(.top, 20)
                Text("Record in Tabber Studio from across the room.")
                    .font(.title3)
                    .foregroundStyle(Studio.text2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
                VStack(alignment: .leading, spacing: 16) {
                    step(1, "On your computer, open Tabber Studio's Settings › Remote and turn it on.")
                    step(2, "Click Pair iPhone. A code appears.")
                    step(3, "Scan the code with this iPhone.")
                }
                .padding(.top, 36)
                Spacer(minLength: 24)
                NavigationLink {
                    FindComputerView(model: model)
                } label: {
                    Text("Pair with Tabber Studio").frame(maxWidth: .infinity)
                }
                .buttonStyle(.studioPrimary)
                .accessibilityIdentifier("get-started")
                Button("Try the demo") { model.startDemo() }
                    .buttonStyle(.studioQuiet)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 6)
                    .accessibilityIdentifier("demo")
            }
            .padding(24)
            .frame(maxWidth: 560, alignment: .leading)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Studio.bg1.ignoresSafeArea())
        }
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text("\(number)")
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(Studio.text3)
            Text(text)
                .font(.body)
                .foregroundStyle(Studio.text1)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Before iOS asks for the local network, why; then the computers Bonjour
/// finds, and the scanner (plan: Find your Mac).
struct FindComputerView: View {
    @Bindable var model: AppModel
    @State private var found: [FoundComputer] = []
    @State private var denied = false
    @State private var searchedLong = false

    var body: some View {
        Group {
            if model.explainedLocalNetwork { finder } else { explainer }
        }
        .navigationTitle("Pair")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var explainer: some View {
        VStack(alignment: .leading, spacing: 14) {
            Spacer(minLength: 24)
            Text("Tabber Spak looks for your computer on this Wi-Fi")
                .font(.title2.weight(.semibold))
                .foregroundStyle(Studio.text1)
                .fixedSize(horizontal: false, vertical: true)
            Text("iPhone asks first whether Tabber Spak may find devices on your local network. Tap Allow. Nothing leaves your network.")
                .font(.body)
                .foregroundStyle(Studio.text2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 24)
            Button {
                model.explainedLocalNetwork = true
            } label: {
                Text("Continue").frame(maxWidth: .infinity)
            }
            .buttonStyle(.studioPrimary)
            .accessibilityIdentifier("continue")
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Studio.bg1.ignoresSafeArea())
    }

    private var finder: some View {
        List {
            Section {
                ForEach(found) { computer in
                    Button {
                        model.scanTarget = computer.name
                        model.scanning = true
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(computer.name).font(.body.weight(.semibold)).foregroundStyle(Studio.text1)
                            Text("Scan its pairing code").font(.subheadline).foregroundStyle(Studio.text2)
                        }
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("found-computer")
                    .listRowBackground(Studio.bg1)
                }
                if found.isEmpty && !denied {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Looking for Tabber Studio").foregroundStyle(Studio.text2)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("searching")
                    .listRowBackground(Studio.bg1)
                }
            } header: {
                Text("On this Wi-Fi")
            } footer: {
                Text("Your computer shows here while Tabber Studio's remote is on.")
            }
            if denied {
                Section {
                    FixItView(model: model, trouble: .localNetworkDenied, computer: "your computer")
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 8, leading: 4, bottom: 8, trailing: 4))
                }
            } else if found.isEmpty && searchedLong {
                Section {
                    Text("Nothing found yet. The code works without this list, because it carries the computer's address. On a guest or venue Wi-Fi, use your own router.")
                        .font(.subheadline)
                        .foregroundStyle(Studio.text2)
                        .accessibilityIdentifier("nothing-found")
                        .listRowBackground(Studio.bg1)
                }
            }
        }
        .studioList()
        .safeAreaInset(edge: .bottom) {
            Button {
                model.scanTarget = found.count == 1 ? found[0].name : nil
                model.scanning = true
            } label: {
                Text("Scan the code").frame(maxWidth: .infinity)
            }
            .buttonStyle(.studioPrimary)
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
            .accessibilityIdentifier("scan")
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
                        .foregroundStyle(Studio.text2)
                        .multilineTextAlignment(.center)
                } else {
                    paste
                }
                if notACode {
                    Text("That isn't a Tabber Studio pairing code.")
                        .foregroundStyle(Studio.playhead)
                        .accessibilityIdentifier("not-a-code")
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Studio.bg1.ignoresSafeArea())
            .navigationTitle("Scan the code")
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
        VStack(alignment: .leading, spacing: 14) {
            if DataScannerViewController.isSupported {
                Text("Tabber Spak can't use the camera. Allow it in Settings, or paste the link instead.")
                    .foregroundStyle(Studio.text2)
                Button("Open Settings") { FixItView.openSettings() }
                    .buttonStyle(.studio)
            } else {
                Text("This device can't scan codes. Paste the link that Pair iPhone in Tabber Studio shows.")
                    .foregroundStyle(Studio.text2)
            }
            TextField("tabber-remote://pair?…", text: $linkText, axis: .vertical)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.footnote.monospaced())
                .foregroundStyle(Studio.text1)
                .padding(12)
                .studioWell()
                .accessibilityIdentifier("pair-link-field")
            Button("Pair") { handle(linkText) }
                .buttonStyle(.studio)
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
            Text("Pairing with \(name)…").font(.headline).foregroundStyle(Studio.text1)
        }
        .padding(28)
        .background(Studio.bg2, in: RoundedRectangle(cornerRadius: Studio.radiusCard, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Studio.radiusCard, style: .continuous).strokeBorder(Studio.edge, lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("pairing")
    }
}
