import RemoteKit
import SwiftUI
import UIKit

/// What to do when the phone cannot use its computer: the cause in plain words
/// and the one action that fixes it (plan: TR6's fix-it cards, principle 3).
struct FixItCard: View {
    @Bindable var model: AppModel
    let trouble: Trouble
    let computer: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label {
                Text(title).accessibilityIdentifier("fix-it-title")
            } icon: {
                Image(systemName: symbol).foregroundStyle(Studio.playhead).accessibilityHidden(true)
            }
            .font(.headline)
            .foregroundStyle(Studio.text1)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Studio.text2)
                .fixedSize(horizontal: false, vertical: true)
            if !checks.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(checks, id: \.self) { check in
                        Label(check, systemImage: "checkmark.circle")
                            .font(.subheadline)
                            .foregroundStyle(Studio.text1)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            ViewThatFits {
                HStack(spacing: 10) { actions }
                VStack(alignment: .leading, spacing: 10) { actions }
            }
            .padding(.top, 2)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .studioCard(Studio.bg2, radius: 18)
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Studio.playhead.opacity(0.5), lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("fix-it")
    }

    private var title: String {
        switch trouble {
        case .unreachable: "Can't reach \(computer)"
        case .localNetworkDenied: "Allow Local Network"
        case .updateStudio: "Update Tabber Studio"
        case .updateSpak: "Update Tabber Spak"
        case .forgotten: "\(computer) no longer knows this iPhone"
        case .otherComputer: "A different computer answers"
        }
    }

    private var symbol: String {
        switch trouble {
        case .unreachable: "wifi.exclamationmark"
        case .localNetworkDenied: "network.slash"
        case .updateStudio, .updateSpak: "arrow.down.app"
        case .forgotten, .otherComputer: "qrcode.viewfinder"
        }
    }

    private var message: String {
        switch trouble {
        case .unreachable:
            "Tabber Spak keeps trying. Check these:"
        case .localNetworkDenied:
            "Tabber Spak needs the local network to reach \(computer). Turn on Local Network in Settings › Tabber Spak."
        case .updateStudio:
            "Tabber Studio on \(computer) is too old for this Tabber Spak. Update Tabber Studio on the computer, then try again."
        case .updateSpak:
            "Tabber Studio on \(computer) is newer than this Tabber Spak. Update Tabber Spak from the App Store or TestFlight."
        case .forgotten:
            "This iPhone was removed in Tabber Studio's Settings › Remote. Pair again to use it."
        case .otherComputer:
            "The computer at this address is not the one this iPhone paired with. Pair again with the right one."
        }
    }

    private var checks: [String] {
        guard trouble == .unreachable else { return [] }
        return ["Tabber Studio is open on the computer, with Settings › Remote turned on. No Remote page there? Update Tabber Studio.",
                "This iPhone is on the same Wi-Fi as the computer.",
                "It is not a guest or venue Wi-Fi: those keep devices apart. Bring your own router.",
                "No VPN is on on this iPhone."]
    }

    @ViewBuilder private var actions: some View {
        switch trouble {
        case .unreachable:
            Button { model.wake() } label: { Text("Try Again").foregroundStyle(Studio.onAccent) }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("fix-it-retry")
            Button("Pair Again") { model.scanning = true }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("fix-it-pair")
        case .localNetworkDenied:
            Button { Self.openSettings() } label: { Text("Open Settings").foregroundStyle(Studio.onAccent) }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("fix-it-settings")
        case .updateStudio, .updateSpak:
            Button { model.retry() } label: { Text("Try Again").foregroundStyle(Studio.onAccent) }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("fix-it-retry")
        case .forgotten, .otherComputer:
            Button { model.scanning = true } label: { Text("Pair Again").foregroundStyle(Studio.onAccent) }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("fix-it-pair")
        }
    }

    static func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
    }
}
