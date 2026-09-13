import Foundation
import Testing
@testable import SplouchCore

/// Integration checks against a real server, skipped unless
/// `SPLOUCH_LIVE_SERVER=http://host:port` is set. They exercise the
/// `URLSession` transport the fake-connector suites cannot.
@Suite(.serialized) struct LiveServerTests {
    static var address: ServerAddress? {
        ProcessInfo.processInfo.environment["SPLOUCH_LIVE_SERVER"].flatMap { ServerAddress(typed: $0) }
    }

    @Test(.enabled(if: address != nil)) func handshake() async throws {
        let api = SplouchAPI(address: Self.address!)
        let info = try await api.server()
        #expect(info.contract.api == "v2")
    }

    @Test(.enabled(if: address != nil)) func scoreboardSocketDeliversFrames() async throws {
        let address = Self.address!
        let info = try await SplouchAPI(address: address).server()
        let socket = SplouchSocket(url: address.webSocket("/ws/scoreboard"), connector: URLSessionWebSocketConnector(),
                                   join: info.kind == .cloud ? nil : nil)
        let recorder = EventRecorder(socket.events)
        await socket.start()
        #expect(await eventually(.seconds(5)) { await recorder.events.contains(.connected) })
        #expect(await eventually(.seconds(8)) { await recorder.count { if case .frame = $0 { return true } else { return false } } >= 1 })
        let events = await recorder.events.compactMap { e -> String? in if case .frame(let f) = e { return f.event } else { return nil } }
        print("live events:", events.prefix(10))
        #expect(events.contains("meet_live") || events.contains("update_scoreboard"))
        await socket.close()
    }
}
