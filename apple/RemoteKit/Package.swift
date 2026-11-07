// swift-tools-version: 6.2
// RemoteKit: the Tabber Remote Protocol for Tabber Spak, with no UI framework.
import PackageDescription

let package = Package(
    name: "RemoteKit",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [.library(name: "RemoteKit", targets: ["RemoteKit"])],
    targets: [
        .target(name: "RemoteKit"),
        .testTarget(name: "RemoteKitTests", dependencies: ["RemoteKit"]),
    ]
)
