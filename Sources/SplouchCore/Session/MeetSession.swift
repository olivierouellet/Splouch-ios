import Foundation
import Observation

/// One open meet: the three sockets of app.md §6 (C-01) and the state each tab
/// renders. The SwiftUI layer observes this and never touches a socket.
///
/// Both server kinds are handled by one object. On a cloud the sockets join a
/// room with `join_meet` on every connect (C-02); on a Pi there is one meet and
/// the server pushes on connect, so `join` is nil (api.md §2 vs §3).
@MainActor
@Observable
public final class MeetSession {
    public let address: ServerAddress
    public let kind: ServerKind
    /// nil on a Pi.
    public let meetID: String?

    public private(set) var settings: MeetSettings
    /// The Scoreboard tab (L-*). The view drives `tick(at:)` at ~10Hz.
    public private(set) var scoreboard: ScoreboardState
    /// The Results tab: nil is the empty grid with "Waiting for results…"
    /// (R-01). A disconnect or `meet_live` false wipes it back to nil (R-02).
    public private(set) var results: ResultsSnapshot?
    public private(set) var resultsLive = false
    /// The heat the meet is on, taken from whichever of the scoreboard and
    /// results sockets spoke last (S-05).
    public private(set) var currentHeat: HeatRef?
    /// Increments on `schedule_update` (S-21): the start list a client is holding
    /// belongs to the previous meet file, re-fetch `GET /meet/{id}/schedule`.
    public private(set) var scheduleVersion = 0
    /// Increments on `reload` (C-08): settings or theme changed, re-fetch config
    /// and call `apply(settings:)`.
    public private(set) var reloadVersion = 0
    public private(set) var scoreboardConnected = false
    public private(set) var resultsConnected = false
    public private(set) var scheduleConnected = false
    /// Called on `reload` (C-08) after `reloadVersion` changes.
    public var onReload: (@MainActor () -> Void)?
    /// Called on `schedule_update` (S-21) after `scheduleVersion` changes.
    public var onScheduleUpdate: (@MainActor () -> Void)?
    /// Called when the scoreboard socket comes back after a drop (A-09 re-check).
    public var onReconnected: (@MainActor () -> Void)?
    private var scoreboardEverConnected = false

    private let scoreboardSocket: SplouchSocket
    private let resultsSocket: SplouchSocket
    private let scheduleSocket: SplouchSocket
    private var pumps: [Task<Void, Never>] = []
    private var started = false

    public init(address: ServerAddress, kind: ServerKind, meetID: String?, settings: MeetSettings,
                vidStore: any VidStore, connector: any WebSocketConnector = URLSessionWebSocketConnector(),
                timing: SocketTiming = .standard) {
        self.address = address
        self.kind = kind
        self.meetID = kind == .cloud ? meetID : nil
        self.settings = settings
        self.scoreboard = ScoreboardState(numLanes: settings.numLanes)
        // C-10: one random id per server, generated on first use and stored.
        let join: Frame? = (kind == .cloud && meetID != nil)
            ? .joinMeet(meetID: meetID!, vid: vidStore.vid(for: address.origin)) : nil
        scoreboardSocket = SplouchSocket(url: address.webSocket("/ws/scoreboard"), connector: connector, join: join, timing: timing)
        resultsSocket = SplouchSocket(url: address.webSocket("/ws/results"), connector: connector, join: join, timing: timing)
        scheduleSocket = SplouchSocket(url: address.webSocket("/ws/schedule"), connector: connector, join: join, timing: timing)
    }

    public var meetLive: Bool { scoreboard.meetLive }

    /// Opens the three sockets. Idempotent.
    public func start() {
        guard !started else { return }
        started = true
        pumps = [
            pump(scoreboardSocket) { [weak self] e in self?.onScoreboard(e) },
            pump(resultsSocket) { [weak self] e in self?.onResults(e) },
            pump(scheduleSocket) { [weak self] e in self?.onSchedule(e) },
        ]
        Task {
            await scoreboardSocket.start()
            await resultsSocket.start()
            await scheduleSocket.start()
        }
    }

    /// Closes everything for good — back to the picker (A-02, A-09).
    public func stop() async {
        for p in pumps { p.cancel() }
        pumps = []
        await scoreboardSocket.close()
        await resultsSocket.close()
        await scheduleSocket.close()
        scoreboard.socketDisconnected()
        results = nil
        resultsLive = false
    }

    /// Foreground or network restored (C-05): probe every socket.
    public func wake() {
        Task {
            await scoreboardSocket.wake()
            await resultsSocket.wake()
            await scheduleSocket.wake()
        }
    }

    /// App or tab backgrounded: the race clock stops and stays stopped (L-12).
    public func suspend() {
        scoreboard.suspend()
    }

    /// The Scoreboard tab's ~10Hz tick, off a monotonic instant.
    public func tick(at now: ContinuousClock.Instant = .now) {
        scoreboard.tick(at: now)
    }

    /// Returning to the Results tab re-asserts the room, reconnecting first if
    /// needed (R-10).
    public func resultsTabShown() {
        Task {
            if await resultsSocket.isConnected {
                if let join = await resultsSocket.join { await resultsSocket.send(join) }
            } else {
                await resultsSocket.wake()
            }
        }
    }

    /// Pull-to-refresh (A-05) and `reload` (C-08): new config, then every socket
    /// re-joins so the server replays its snapshots into the redrawn board.
    public func apply(settings new: MeetSettings) {
        let lanesChanged = new.numLanes != settings.numLanes
        settings = new
        if lanesChanged {
            scoreboard = ScoreboardState(numLanes: new.numLanes)
        }
        rejoin()
    }

    /// Drops and reopens every socket so the join replay lands (A-05).
    public func rejoin() {
        Task {
            for s in [scoreboardSocket, resultsSocket, scheduleSocket] {
                if await s.isConnected, let join = await s.join { await s.send(join) } else { await s.wake() }
            }
        }
    }

    // MARK: - Dispatch

    private func pump(_ socket: SplouchSocket, _ handle: @escaping @MainActor (SocketEvent) -> Void) -> Task<Void, Never> {
        Task { @MainActor in
            for await e in socket.events {
                if Task.isCancelled { return }
                handle(e)
            }
        }
    }

    private func onScoreboard(_ e: SocketEvent) {
        switch e {
        case .connected:
            scoreboardConnected = true
            scoreboard.socketConnected()
            if scoreboardEverConnected { onReconnected?() }
            scoreboardEverConnected = true
        case .disconnected:
            scoreboardConnected = false
            scoreboard.socketDisconnected()   // C-09: a drop implies not live
        case .frame(let f):
            switch f.event {
            case "meet_live":
                scoreboard.setMeetLive(MeetLive(json: f.data).live)
            case "update_scoreboard":
                scoreboard.apply(f.data, at: .now)
                if f.data["current_event"] != nil || f.data["current_heat"] != nil {
                    currentHeat = HeatRef(event: scoreboard.currentEvent, heat: scoreboard.currentHeat)
                }
            case "reload":
                reloadVersion += 1
                onReload?()
            default:
                break   // C-07
            }
        }
    }

    private func onResults(_ e: SocketEvent) {
        switch e {
        case .connected:
            resultsConnected = true
        case .disconnected:
            resultsConnected = false
            wipeResults()
        case .frame(let f):
            switch f.event {
            case "meet_live":
                let live = MeetLive(json: f.data).live
                resultsLive = live
                if !live { wipeResults() }
            case "results_snapshot":
                let snap = ResultsSnapshot(json: f.data)
                guard !snap.lanes.isEmpty else { return }   // the reference ignores an empty snapshot
                results = snap
                currentHeat = HeatRef(event: snap.event, heat: snap.heat)
            case "reload":
                reloadVersion += 1
                onReload?()
            default:
                break
            }
        }
    }

    private func onSchedule(_ e: SocketEvent) {
        switch e {
        case .connected: scheduleConnected = true
        case .disconnected: scheduleConnected = false
        case .frame(let f):
            if f.event == "schedule_update" {
                scheduleVersion += 1
                onScheduleUpdate?()
            }
        }
    }

    private func wipeResults() {
        results = nil
        resultsLive = false
    }
}
