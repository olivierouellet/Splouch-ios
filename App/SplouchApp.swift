import SplouchCore
import SplouchUI
import SwiftUI

/// The iOS app target. Everything else lives in the SwiftPM package.
@main
struct SplouchApp: App {
    /// The one URL the app ships knowing — the default cloud (app.md P-11 note).
    private static let defaultCloud = ServerAddress(typed: "https://splouch.org")!
    /// The default before 2026-10-05. A stored selection of it moves to
    /// `defaultCloud` once, and its `/add` codes still open the app (P-16).
    private static let formerClouds = [ServerAddress(typed: "https://splouch.ca")!]

    /// Development only: `SPLOUCH_SERVER=http://127.0.0.1:5055` in the scheme's
    /// environment points a debug build at a local server without touching
    /// stored preferences. Ignored in release builds.
    private static var startingServer: ServerAddress {
        #if DEBUG
        if let s = ProcessInfo.processInfo.environment["SPLOUCH_SERVER"], let a = ServerAddress(typed: s) { return a }
        #endif
        return defaultCloud
    }

    @State private var model = AppModel(defaultServer: startingServer, formerDefaults: formerClouds)

    init() {
        // P-06, P-07: the folds the picker used to store mean nothing since
        // v3, amended. Deleted once per install.
        LegacyNoticeFolds.purge()
    }

    var body: some Scene {
        WindowGroup {
            SplouchRootView(app: model)
        }
    }
}
