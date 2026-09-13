// swift-tools-version: 6.0
import PackageDescription

// SplouchCore is Foundation-only and testable on macOS with `swift test`.
// SplouchUI is the SwiftUI layer on top of it; it compiles on macOS 14 for
// checking and runs on iOS 17. The app target (App/) wraps SplouchUI once an
// iOS SDK is available on the build machine.
let package = Package(
    name: "Splouch",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "SplouchCore", targets: ["SplouchCore"]),
        .library(name: "SplouchUI", targets: ["SplouchUI"]),
    ],
    targets: [
        .target(name: "SplouchCore"),
        .target(name: "SplouchUI", dependencies: ["SplouchCore"]),
        .testTarget(name: "SplouchCoreTests", dependencies: ["SplouchCore"]),
    ]
)
