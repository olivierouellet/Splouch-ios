# Splouch for iOS — parity ledger

One row per feature ID in [`app.md`](../Splouch/docs/app.md) **v1**, the behaviour contract.
That document owns *what* each feature is and whether it is required; this file owns
*whether it is implemented here, and why not* (`app.md` §0.1).

**Stack:** SwiftUI (iOS 17+), Swift 6

Status is one of `done` / `deferred` / `n/a — <reason>`. IDs are the join key across
the three repos and are never renumbered — a row that goes away keeps its ID and gains
a note. Rows already marked `n/a` below are the ones the contract itself puts out of
scope for a native client; everything else starts `deferred`.

`Level` is copied from `app.md` v1 for triage only. **`app.md` is authoritative** —
if the two ever disagree, that document wins and this one is stale.

**Where things stand (2026-09-12).** The build machine has no Xcode and a broken
CommandLineTools SwiftPM, so everything so far is `SplouchCore`, a Foundation-only
SwiftPM package tested with `scripts/test.sh` (see README). `done` below means the
behaviour is complete and tested in that package and the view only has to render
what it exposes. A `deferred` row whose note starts with `core:` has its logic in the
package and is waiting on the SwiftUI target.

Suggested order: `P-13` (handshake) → `C-01`–`C-05` (sockets) → `P-01`/`P-08` (meet
list, open a meet) → `L-01`–`L-14` (scoreboard). Results, Schedule and the `T-*`
language controls reuse all of it.


## 1. Meet picker

| ID | Feature | Level | Status | Notes |
| --- | --- | --- | --- | --- |
| `P-01` | List of meets as cards: name, date, location, sport | must | `deferred` | core: `SplouchAPI.meets()` (Session/SplouchAPI.swift); card view pending Xcode |
| `P-02` | Per-meet picker image on the card, when the meet supplies one | should | `deferred` |  |
| `P-03` | Offline meets stay listed, marked with a dimmed status dot | must | `deferred` |  |
| `P-04` | Empty state when no meets are active | must | `deferred` | core: `PickerConfig.strings["no_meets"]`; view pending |
| `P-05` | Picker branding: title, logo, logo above or below the title | should | `deferred` | core: `SplouchAPI.pickerConfig(lang:)`, `pickerLogoURL()`; view pending |
| `P-06` | Unofficial-results disclaimer under the list | must | `deferred` | core: `PickerConfig.strings["results_disclaimer"]`; view pending |
| `P-07` | Privacy note, shown whenever attendance counting is on for this server | must | `deferred` | core: `PickerConfig.analyticsEnabled` gates `strings["privacy_note"]`; view pending |
| `P-08` | Selecting a meet opens the app shell for it | must | `deferred` | core: `SplouchAPI.meetConfig(_:)` → `MeetSession`; navigation pending |
| `P-09` | Pull-to-refresh re-fetches the meet list | should | `deferred` |  |
| `P-10` | Install hand-off: store links to the native iOS/Android apps once they ship, Add-to-Home-Screen until then | web-only | `n/a` | web-only — an app satisfies it by existing (app.md §0.3) |
| `P-11` | Choose which server to connect to, from a list, in the picker's menu | native-only | `deferred` | core: `SplouchAPI.servers()`, each entry checked with `server()`; menu pending |
| `P-12` | Servers on the local network are offered without anyone typing an address | native-only | `deferred` | needs the app target: `NSBonjourServices` `_splouch._tcp`, `NSLocalNetworkUsageDescription`, scoped ATS; `ServerAddress(typed:)` already maps `.local`/IPs to `http://` |
| `P-13` | A server can be added by hand, checked before it is saved | native-only | `deferred` | core: `ServerAddress(typed:)` + `SplouchAPI.server()` (`APIError.notASplouchServer` on a non-Splouch answer, `contractMismatches` for versions); entry form pending |

## 2. App shell

| ID | Feature | Level | Status | Notes |
| --- | --- | --- | --- | --- |
| `A-01` | Three tabs — Scoreboard, Results, Schedule — each with icon and label | must | `deferred` |  |
| `A-02` | Back affordance to the meet picker | must | `deferred` |  |
| `A-03` | Horizontal swipe moves between adjacent tabs, and the movement is visible — the tabs follow the finger and settle on release | must | `deferred` |  |
| `A-04` | The selected tab survives a relaunch | should | `deferred` |  |
| `A-05` | Pull-to-refresh re-fetches config and rejoins the sockets | should | `deferred` | core: `MeetSession.apply(settings:)` / `rejoin()`; refresh control pending |
| `A-06` | Content clears notch, Dynamic Island, and home indicator | must (free natively) | `deferred` |  |
| `A-07` | Portrait stacks label under icon; landscape drops labels to save height | should | `deferred` |  |
| `A-08` | Window and home-screen title is the meet's `app_window_title`, falling back to its `name` | web-only | `n/a` | web-only — an app satisfies it by existing (app.md §0.3) |
| `A-09` | Meet goes offline mid-session → return to the picker | must | `deferred` | no socket signal exists: a `join_meet` for a gone meet is silently ignored. Plan (to confirm in app.md): re-fetch `/meet/{id}/config` on reconnect, foreground, refresh and `reload`; `APIError.notFound` → back to the picker |

## 3.1 Header

| ID | Feature | Level | Status | Notes |
| --- | --- | --- | --- | --- |
| `L-01` | EVENT number, HEAT number, each a small label above a large value | must | `deferred` | core: `ScoreboardState.currentEvent/currentHeat`; view pending |
| `L-02` | Event name | must | `deferred` | core: `ScoreboardState.eventName` + `EventName.resolve` for T-11; view pending |
| `L-03` | Wall clock, `HH:MM`, ticking every second | must | `deferred` |  |

## 3.2 Lane table

| ID | Feature | Level | Status | Notes |
| --- | --- | --- | --- | --- |
| `L-04` | One row per lane, `num_lanes` rows always present | must | `deferred` | core: `ScoreboardState(numLanes:)` always holds `numLanes` rows; view pending |
| `L-05` | Columns: lane · name (+ alt sub-line) · club · time · delta · place | must | `deferred` | core: `LaneRow` carries all six; view pending |
| `L-06` | Relay member names on a dimmed second line under the name | must | `deferred` | core: `LaneRow.alt`; view pending |
| `L-07` | Column visibility follows config: `show_name`, `show_club`, `show_delta`, `show_position` | must | `deferred` | core: `MeetSettings.show*`; view pending |
| `L-08` | Column *headers* hide independently of the columns: `show_*_header` | should | `deferred` | core: `MeetSettings.show*Header`; view pending |
| `L-09` | Empty lanes render blank in place — rows never collapse or shift | must | `deferred` | core: rows are fixed slots, never removed; view pending |
| `L-10` | Frames are partial: merge changed keys into local state, never replace | must | `done` | `ScoreboardState.apply` merges key by key (Board/ScoreboardState.swift); running flags first, then `running_time`, then cells. Tests: ScoreboardStateTests |
| `L-11` | A running lane's time is styled distinctly; on stop it plays a one-shot "locked" transition, cancelled if the lane starts running… | must | `deferred` | core: `LaneRow.timeStyle` = `.running` / `.locked(generation:)`, generation bumps on every false edge and `.running` cancels it; the 0.8s flash itself is view work |
| `L-12` | Every running lane's time cell shows the race clock: one value for the heat, re-based by the server every couple of seconds and… | must | `deferred` | core: `RaceClock` + `ScoreboardState.tick(at:)` implement the whole L-12 table (hard re-base, monotonic tick, 6s freeze-forward, pulse, suspend, meet_live/disconnect stop); tests cover each row. Pending: the ~10Hz display-link loop and the pulse animation in the view. `running_time` format taken from the reference (`m:ss.hh` / `ss.hh`), not stated in api.md |
| `L-13` | Event or heat change blanks all times, deltas, and places | must | `done` | blank on change (decided 2026-09-12). The first event/heat seen after a connect is a baseline, not a change, so a join replay never blanks the snapshot it just delivered |
| `L-14` | Returning to the tab re-runs layout and refreshes the clock | must (native: on-appear) | `deferred` | core: `MeetSession.tick`/`suspend`; on-appear hook pending |

## 3.3 Layout

| ID | Feature | Level | Status | Notes |
| --- | --- | --- | --- | --- |
| `L-15` | Portrait: two-line compact row — lane number spanning left, name on line 1 with club right-aligned, time and delta and place on… | must | `deferred` |  |
| `L-16` | Landscape: full table with a header row, row font scaled to lane count | should | `deferred` |  |
| `L-17` | Long names shrink to fit their cell, ellipsis only as a floor | must | `deferred` |  |

## 3.4 Not on this tab

| ID | Feature | Level | Status | Notes |
| --- | --- | --- | --- | --- |
| `L-18` | Carousel / fullscreen image overlay | n/a | `n/a` | images are local to the Pi and are never relayed |
| `L-19` | Podium highlight animation | n/a | `n/a` | Pi-local, `race_finished` is not forwarded |
| `L-20` | Animated column show/hide, operator-driven | n/a | `n/a` | cloud columns are always visible |
| `L-21` | Any timed hold on a state — the kiosk's 3s `brief_results` flash, its results pause, its leave-results debounce | n/a | `n/a` | still real on the kiosk, still deliberately absent here: the phone shows the last frame received and runs no… |
| `L-22` | Independent per-lane clock, each lane timing its own length | n/a | `n/a` | the console has one race clock and the lanes mirror it; a lane's own figure exists only as its split… |

## 4. Results tab

| ID | Feature | Level | Status | Notes |
| --- | --- | --- | --- | --- |
| `R-01` | Until the first snapshot: an empty grid, with "Waiting for results…" below it wherever there is room to say so | must | `deferred` | core: `MeetSession.results == nil` ⇒ `ResultsBoard.empty(numLanes:)`; text `mobile.waiting_results` via `StringTable`; view pending |
| `R-02` | A disconnect, or `meet_live` going false, wipes the board and returns it to that state | must | `done` | `MeetSession` wipes `results` on the results socket's disconnect and on `meet_live` false (Session/MeetSession.swift). Tests: MeetSessionTests |
| `R-03` | Header shows the snapshot's own event, heat, and event name | must | `deferred` | core: `ResultsSnapshot.event/heat/eventName`; view pending |
| `R-04` | Same six columns and visibility flags as the Scoreboard tab | must | `deferred` | core: same `MeetSettings.show*`; view pending |
| `R-05` | Lane sort: row index = `channel`; a lane with no final time leaves its row blank | must | `done` | `ResultsBoard.rows`: row = `channel`, `sort` absent reads as lane (Board/ResultsBoard.swift). Tests: ResultsBoardTests |
| `R-06` | Place sort: rows fill top-down as a ranking | must | `done` | `ResultsBoard.rows` with `sort == "place"` fills top-down |
| `R-07` | A missing time renders as `—`, not blank; a missing place renders empty — no dash, and no `#` in front of it | should | `done` | `ResultRow.time` is `—` when empty, `place` is `""` when empty; the view renders the strings as they are |
| `R-08` | Long names shrink to fit rather than clipping | should | `deferred` | view: `minimumScaleFactor` + `lineLimit(1)` |
| `R-09` | Final times carry the "locked" styling | should | `deferred` | core: `ResultRow.locked`; styling pending |
| `R-10` | Returning to the tab re-joins the meet, reconnecting first if needed | must | `deferred` | core: `MeetSession.resultsTabShown()` re-sends `join_meet` or wakes the socket; tab hook pending |

## 5.1 The list

| ID | Feature | Level | Status | Notes |
| --- | --- | --- | --- | --- |
| `S-01` | Every heat as a card: scheduled time, "Event N — Heat M", event name | must | `deferred` | core: `SplouchAPI.schedule(meetID:)`, `ScheduleHeat`; view pending. **Pi gap:** api.md §4 lists no schedule JSON for a Pi (`/schedule` there is HTML), so this row has no data source against a Pi until the contract says otherwise |
| `S-02` | Each card lists its lanes: lane number, name, club, seed time | must | `deferred` | core: `ScheduleLane`; view pending |
| `S-03` | Relay entries show member first names joined by `·` | should | `deferred` | core: `ScheduleView.displayName` joins first names with `·`; view pending |
| `S-04` | Alternating card backgrounds, computed over *visible* cards so filtering keeps the stripe | should | `deferred` | core: `VisibleHeat.stripe` counts visible cards only; view pending |
| `S-05` | The heat the meet is on is highlighted in the list | must | `deferred` | core: `MeetSession.currentHeat` from whichever of the two sockets spoke last, `VisibleHeat.isCurrent`; view pending |
| `S-06` | The list auto-scrolls to the current heat once per appearance | must | `deferred` |  |
| `S-07` | Empty state when no meet file is loaded | must | `deferred` | core: empty `heats` is not an error (`Schedule.heats.isEmpty`); strings `mobile.no_schedule`/`no_meet`; view pending |

## 5.2 Filtering

| ID | Feature | Level | Status | Notes |
| --- | --- | --- | --- | --- |
| `S-08` | Full-screen filter sheet, opened from a button in the top bar | must | `deferred` |  |
| `S-09` | Typeahead search over swimmers and clubs, debounced ~220ms | must | `deferred` | core: `SplouchAPI.searchSuggestions(meetID:query:)`; sheet and debounce pending. Not listed for a Pi in api.md §4 either |
| `S-10` | Suggestions show type (swimmer/club), name, and club; already-added ones are marked and inert | should | `deferred` | core: `ScheduleFilter.contains` marks an added suggestion; view pending |
| `S-11` | Active filters appear as chips; tapping a chip's × removes it | must | `deferred` | core: `ScheduleFilter.add/remove`; chips pending |
| `S-12` | A count badge on the filter button shows how many filters are active | should | `deferred` | core: `ScheduleFilter.count`; badge pending |
| `S-13` | Filters are OR-ed: a lane matches if it hits *any* club or swimmer filter | must | `done` | `ScheduleView.laneMatches` ORs every term (Schedule/ScheduleFilter.swift). Tests: ScheduleFilterTests |
| `S-14` | A swimmer filter matches relay members, not just the lane's display name | must | `done` | `ScheduleView.laneMatches` checks `lane.swimmers[].name` as well as `lane.name` |
| `S-15` | With filters on, non-matching lanes are hidden and heats with no match disappear | must | `deferred` | core: `ScheduleView.visible` hides non-matching lanes and empty heats; view pending |
| `S-16` | All heats toggle: keep every heat visible, still filtering the lanes inside | should | `deferred` | core: `ScheduleFilter.showAllHeats`; toggle pending |
| `S-17` | Upcoming toggle: hide every heat listed *ahead* of the current one, keeping that one | should | `deferred` | core: `ScheduleFilter.upcomingOnly` cuts by index in the start list and changes nothing when the current heat is unknown or absent; toggle pending |
| `S-18` | Reset clears filters and both toggles, behind a confirmation | should | `deferred` | core: `ScheduleFilter.reset()`; confirmation UI pending |
| `S-19` | Distinct empty states for "no swimmers match these filters" and "no search results" | should | `deferred` |  |
| `S-20` | Filters live only for the session — not persisted | should | `deferred` | core: `ScheduleFilter` is in-memory only; nothing persists it |

## 5.3 Refresh

| ID | Feature | Level | Status | Notes |
| --- | --- | --- | --- | --- |
| `S-21` | A new schedule from the Pi refreshes the list | must | `deferred` | core: `MeetSession.scheduleVersion` bumps on `schedule_update`, `ScheduleFilter.prune(to:)` keeps filters whose names still exist; the re-fetch is app wiring |

## 6. Connection and session

| ID | Feature | Level | Status | Notes |
| --- | --- | --- | --- | --- |
| `C-01` | Three independent sockets: `/ws/scoreboard`, `/ws/results`, `/ws/schedule` | must | `done` | `MeetSession` opens `/ws/scoreboard`, `/ws/results`, `/ws/schedule`, one `SplouchSocket` each (Session/MeetSession.swift). Tests: MeetSessionTests |
| `C-02` | `join_meet {meet_id, vid}` on every connect, including every reconnect | must | `done` | `SplouchSocket` sends `join` on every connect including reconnects; nil on a Pi, which has no rooms (Transport/SplouchSocket.swift). Tests: SplouchSocketTests |
| `C-03` | Automatic reconnect, capped exponential backoff (web: 500ms → 5s) | must | `done` | 500ms doubling to 5s, reset on a successful open (`SocketTiming.standard`) |
| `C-04` | Heartbeat `ping` every 15s; no inbound frame for 35s means dead — close and reconnect | must | `done` | `ping` every 15s; no inbound frame for 35s closes the socket, which reconnects |
| `C-05` | On foreground or network-restored: probe with a `ping`; no `pong` within ~4s means dead | must | `deferred` | core: `SplouchSocket.wake()` probes with `ping` and closes after 4s without a `pong`; `MeetSession.wake()` probes all three. Pending: the `scenePhase` / `NWPathMonitor` trigger in the app target |
| `C-06` | Frames sent while disconnected are queued and flushed on connect | should | `done` | frames sent while disconnected are queued and flushed before the join |
| `C-07` | Unknown events are ignored, not treated as errors | must | `done` | unknown events pass through `SplouchSocket` and fall to `default` in `MeetSession`; unknown `update_scoreboard` keys are ignored by `ScoreboardState` |
| `C-08` | `reload` → re-fetch config and redraw (web: full page reload) | must | `deferred` | core: `MeetSession.reloadVersion` bumps on `reload`; `apply(settings:)` rebuilds the board on a lane-count change and re-joins. The config re-fetch is app wiring |
| `C-09` | `meet_live` gates live affordances; a `disconnect` implies `meet_live = false` | must | `done` | `ScoreboardState.socketDisconnected()` sets `meetLive = false` and stops the clock; `MeetSession` wipes results on the results socket's drop |
| `C-10` | Anonymous per-install, per-server id (`vid`) sent with `join_meet` | must | `done` | `VidStore`: a random UUID per `ServerAddress.origin` (scheme+host+port), created on first use, `UserDefaults`-backed (Session/VidStore.swift). Never derived from the device. Never sent on a Pi, which has no `join_meet` |

## 7. Theme and language

| ID | Feature | Level | Status | Notes |
| --- | --- | --- | --- | --- |
| `T-01` | Palette from the meet's config: `bg`, `header_bg`, `header_border`, `header_label`, `header_value`, `th_text`, `th_bg`… | must | `deferred` | core: `ThemeColors` (Theme/Theme.swift); colour conversion in the view pending |
| `T-02` | Schedule-specific colours `schedule_event`, `schedule_time`, `schedule_name`, `schedule_club`, each with a built-in default | should | `deferred` | core: `ThemeColors.schedule*` with defaults; view pending |
| `T-03` | Three font roles — `family` (text), `digits` (clock), `timing` (times and deltas) | must | `deferred` | core: `ThemeFonts` roles; embedding the faces needs the app target |
| `T-04` | Column headers and header labels are the server's words, never the app's | must | `deferred` | core: `LabelResolver.labels` renders `settings.labels` as sent, or the `/i18n` table when the user chose (Strings/StringTable.swift); view pending |
| `T-05` | The app's own chrome — tab names, empty states, filter UI — is fetched and cached, not translated in the app | must | `deferred` | core: `StringTable.mobile(_:)`, `SplouchAPI.i18n(_:etag:)`; view pending |
| `T-06` | Language defaults to the meet's locale and the user may override it | must | `deferred` | core: `StringTable(language:)` per meet locale; the stored preference is app wiring |
| `T-07` | Missing theme keys fall back to the documented defaults rather than rendering unstyled | must | `done` | `ThemeColors` / `ThemeFonts` fall back per key to the servers' own defaults (`cloud_server._DEFAULT_COLORS`, `state.DEFAULT_THEME_COLORS`). Tests: ThemeTests |
| `T-08` | A language control, per device, applying to every meet opened afterwards | should | `deferred` | core: `SplouchAPI.locales()`; control pending |
| `T-09` | A short/long control over the EVENT and HEAT headers only, starting from short | should | `deferred` | core: `LabelResolver` applies the style to `event`/`heat` only and keeps narrow columns short even under a `long` override; control pending |
| `T-10` | A built-in snapshot of the strings is the floor: compiled into the app, refreshed from the server, cached to disk | must | `deferred` | core: compiled snapshot `BuiltInStrings` (generated by `scripts/update-strings.sh` from `GET /i18n/{lang}`, en/es/fr) and the `StringTable` chain server → built-in → English → key; `SplouchAPI.i18n` revalidates with the ETag. Pending: the on-disk cache of fetched bundles |
| `T-11` | The event name follows the chosen language, composed from parts the server sends | should | `done` | `EventName.compose`/`resolve` join `event_name_parts` against `StringTable.eventVocabulary`, falling back to `event_name`; mirrors the reference `composeEventName` exactly (Strings/EventName.swift). Tests: EventNameTests |
