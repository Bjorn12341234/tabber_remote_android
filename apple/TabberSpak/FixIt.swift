import RemoteKit
import SwiftUI
import UIKit

/// When the phone cannot use its computer: what happened, what to check, and
/// the action that fixes it (plan: TR6's fix-it cards, principle 3). It takes
/// the place of the session, in the screen's own voice: no alert box, no icon.
struct FixItView: View {
    @Bindable var model: AppModel
    let trouble: Trouble
    let computer: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.title2.weight(.semibold))
                .foregroundStyle(Studio.text1)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("fix-it-title")
            Text(message)
                .font(.body)
                .foregroundStyle(Studio.text2)
                .fixedSize(horizontal: false, vertical: true)
            if !checks.isEmpty {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(checks, id: \.self) { check in
                        Text(check)
                            .font(.body)
                            .foregroundStyle(Studio.text1)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.top, 2)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { actions }
                VStack(alignment: .leading, spacing: 10) { actions }
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("fix-it")
    }

    private var title: String {
        switch trouble {
        case .unreachable: "Can't reach \(computer)"
        case .localNetworkDenied: "Tabber Spak can't use the local network"
        case .updateStudio: "Update Tabber Studio"
        case .updateSpak: "Update Tabber Spak"
        case .forgotten: "\(computer) no longer knows this iPhone"
        case .otherComputer: "A different computer answers"
        }
    }

    private var message: String {
        switch trouble {
        case .unreachable:
            "Tabber Spak keeps trying. In the meantime, check that:"
        case .localNetworkDenied:
            "It needs the local network to reach \(computer). Turn on Local Network for Tabber Spak in Settings."
        case .updateStudio:
            "Tabber Studio on \(computer) is too old for this Tabber Spak. Update Tabber Studio on the computer, then try again."
        case .updateSpak:
            "Tabber Studio on \(computer) is newer than this Tabber Spak. Update Tabber Spak from the App Store or TestFlight."
        case .forgotten:
            "It was removed in Tabber Studio's Preferences › Remote. Pair again to use it."
        case .otherComputer:
            "The computer at this address is not the one this iPhone paired with. Pair again with the right one."
        }
    }

    private var checks: [String] {
        guard trouble == .unreachable else { return [] }
        return ["Tabber Studio is open, with Preferences › Remote turned on. If Preferences has no Remote page, update Tabber Studio.",
                "This iPhone is on the same Wi-Fi as the computer. Away from it, Tailscale is on, on both, with the same account.",
                "The Wi-Fi isn't a guest or venue network. Those keep devices apart, so bring your own router.",
                "No VPN but Tailscale is on. Another VPN can keep this iPhone from the computer."]
    }

    @ViewBuilder private var actions: some View {
        switch trouble {
        case .unreachable:
            Button("Try again") { model.wake() }
                .buttonStyle(.studio)
                .accessibilityIdentifier("fix-it-retry")
            Button("Pair again") { model.scanning = true }
                .buttonStyle(.studioQuiet)
                .accessibilityIdentifier("fix-it-pair")
        case .localNetworkDenied:
            Button("Open Settings") { Self.openSettings() }
                .buttonStyle(.studio)
                .accessibilityIdentifier("fix-it-settings")
        case .updateStudio, .updateSpak:
            Button("Try again") { model.retry() }
                .buttonStyle(.studio)
                .accessibilityIdentifier("fix-it-retry")
        case .forgotten, .otherComputer:
            Button("Pair again") { model.scanning = true }
                .buttonStyle(.studio)
                .accessibilityIdentifier("fix-it-pair")
        }
    }

    static func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
    }
}
