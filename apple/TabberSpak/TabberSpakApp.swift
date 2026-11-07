import RemoteKit
import SwiftUI

@main
struct TabberSpakApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
                .onOpenURL { url in
                    // The QR code's link, or `xcrun simctl openurl booted <link>` in the Simulator.
                    if let link = PairingLink(url: url) {
                        Task { await model.pair(with: link) }
                    }
                }
        }
    }
}
