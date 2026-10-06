import SplouchCore
import SplouchUI
import SwiftUI
import UIKit
import UserNotifications

/// The iOS app target. Everything else lives in the SwiftPM package.
@main
struct SplouchApp: App {
    /// APNs and the notification centre answer an application delegate, not a
    /// scene: the token, and a notification tapped while the app was not
    /// running, arrive there (app.md N-04, N-08). It owns the model so both
    /// halves reach the same one.
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    init() {
        // P-06, P-07: the folds the picker used to store mean nothing since
        // v3, amended. Deleted once per install.
        LegacyNoticeFolds.purge()
    }

    var body: some Scene {
        WindowGroup {
            SplouchRootView(app: delegate.model)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    /// The one URL the app ships knowing — the default cloud (app.md P-11 note).
    private static let defaultCloud = ServerAddress(typed: "https://splouch.org")!

    /// Development only: `SPLOUCH_SERVER=http://127.0.0.1:5055` in the scheme's
    /// environment points a debug build at a local server without touching
    /// stored preferences. Ignored in release builds.
    private static var startingServer: ServerAddress {
        #if DEBUG
        if let s = ProcessInfo.processInfo.environment["SPLOUCH_SERVER"], let a = ServerAddress(typed: s) { return a }
        #endif
        return defaultCloud
    }

    /// A debug build is signed for APNs' sandbox (`aps-environment` =
    /// development), and its token is only good there (api.md §5.13).
    private static var sandbox: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }

    let model = AppModel(defaultServer: AppDelegate.startingServer)

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let push = model.push
        push.ask = {
            // N-04: asked right after the first swimmer is added. Time Sensitive
            // is the app's entitlement, not a request: it is not asked for here.
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
            if granted { UIApplication.shared.registerForRemoteNotifications() }
            return granted ? .allowed : .refused
        }
        push.current = { await Self.permission(center) }
        push.onNewToken = { [model] in await model.registerAllFollows() }
        Task {
            let p = await Self.permission(center)
            push.setPermission(p)
            // Every launch: APNs may hand over a new token, and an allowed app
            // must ask for it to find out (N-07).
            if p == .allowed { application.registerForRemoteNotifications() }
        }
        return true
    }

    private static func permission(_ center: UNUserNotificationCenter) async -> PushPermission {
        switch await center.notificationSettings().authorizationStatus {
        case .authorized, .provisional, .ephemeral: .allowed
        case .denied: .refused
        case .notDetermined: .notAsked
        @unknown default: .notAsked
        }
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken token: Data) {
        model.push.setToken(PushToken(data: token, sandbox: Self.sandbox))
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: any Error) {
        // No token, no follows sent: the sheet still saves them on the device,
        // and the next launch asks APNs again.
    }

    /// In the foreground too: a heat in five minutes matters as much while the
    /// spectator is looking at the board.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    /// N-08: open the meet on the Schedule tab, at the heat.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
    ) async {
        let info = response.notification.request.content.userInfo
        guard let focus = HeatFocus(userInfo: info) else { return }
        await MainActor.run { model.pendingFocus = focus }
    }
}
