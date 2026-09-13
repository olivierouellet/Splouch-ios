// swift-tools-version: 6.0
import PackageDescription

// SplouchCore is Foundation-only and testable on macOS with `swift test`.
// The SwiftUI layer sits on top of it in a separate target added once the
// iOS SDK is available on the build machine.
let package = Package(
    name: "Splouch",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "SplouchCore", targets: ["SplouchCore"]),
    ],
    targets: [
        .target(name: "SplouchCore"),
        .testTarget(name: "SplouchCoreTests", dependencies: ["SplouchCore"]),
    ]
)
