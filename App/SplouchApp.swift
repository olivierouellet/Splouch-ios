import SwiftUI
import SplouchCore
import SplouchUI

/// The iOS app target. Built with Xcode once an iOS SDK is on the machine; see
/// App/README.md. Everything else lives in the SwiftPM package.
@main
struct SplouchApp: App {
    /// The one URL the app ships knowing — the default cloud (app.md P-11 note).
    private static let defaultCloud = ServerAddress(typed: "https://splouch.ca")!

    @State private var model = AppModel(defaultServer: defaultCloud)

    var body: some Scene {
        WindowGroup {
            SplouchRootView(app: model)
        }
    }
}
