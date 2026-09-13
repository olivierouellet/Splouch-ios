import SwiftUI
import SplouchCore
import SplouchUI

/// The iOS app target. Everything else lives in the SwiftPM package.
@main
struct SplouchApp: App {
    /// The one URL the app ships knowing — the default cloud (app.md P-11 note).
    private static let defaultCloud = ServerAddress(typed: "https://splouch.ca")!

    /// Development only: `SPLOUCH_SERVER=http://127.0.0.1:5055` in the scheme's
    /// environment points a debug build at a local server without touching
    /// stored preferences. Ignored in release builds.
    private static var startingServer: ServerAddress {
        #if DEBUG
        if let s = ProcessInfo.processInfo.environment["SPLOUCH_SERVER"], let a = ServerAddress(typed: s) { return a }
        #endif
        return defaultCloud
    }

    @State private var model = AppModel(defaultServer: startingServer)

    var body: some Scene {
        WindowGroup {
            SplouchRootView(app: model)
        }
    }
}
