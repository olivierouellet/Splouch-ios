# Splouch for iOS — parity ledger

One row per feature ID in [`app.md`](../Splouch/docs/app.md) **v1**, the behaviour contract.
That document owns *what* each feature is and whether it is required; this file owns
*whether it is implemented here, and why not* (`app.md` §0.1).

**Stack:** SwiftUI (iOS 17+), Swift 6

Status is one of `done` / `deferred` / `diverges` / `n/a — <reason>`. `diverges` is
built and working, but deliberately not what the contract says — the note carries what
the app does instead, why, and that app.md still needs the matching edit. IDs are the join key across
the three repos and are never renumbered — a row that goes away keeps its ID and gains
a note. Rows already marked `n/a` below are the ones the contract itself puts out of
scope for a native client; everything else starts `deferred`.

`Level` is copied from `app.md` v1 for triage only. **`app.md` is authoritative** —
if the two ever disagree, that document wins and this one is stale.

**Where things stand (2026-09-14).** `SplouchCore` is tested with `swift test` (171
tests); `SplouchUI` and the app target (`App/Splouch.xcodeproj`) build with Xcode 26.6 and
were run on the iOS 26.5 simulator against the default cloud, a local cloud and a local Pi
(recorded session). The shell is the platform's throughout: a real tab bar, a real
navigation bar, the meet pushed onto the picker's stack. Seen working on screen: the
picker as a grouped list, its branding in both orientations, the disclaimer block, the
menu and the language and server sheets; the scoreboard with names and the ticking race
clock, in portrait and landscape; results and its empty state; the schedule at the default
text size and at `accessibility-large`, where the lane rows reflow; the filter sheet's
entry field, suggestions, tokens, capsule switches and reset, with the software keyboard
up as well as the hardware one; the app icon on the home screen and in the App Library.
**Not yet exercised on screen**: the server sheet's add row and the Bonjour list (menu
items do not take scripted taps), the lane pulse, the lock flash, pull-to-refresh,
backgrounding, a light-themed meet, and the landscape board header with live EVENT and
HEAT numbers in it. **Not yet heard**: none of the accessibility work below has been run
under VoiceOver — the labels and traits are in place and compile, but "reads sensibly" is
a judgement only the screen reader settles. Debug builds honour  `SPLOUCH_SERVER`, `SPLOUCH_MEET`
and `SPLOUCH_TAB` in the launch environment and `scripts/sim-tap.sh` taps the
simulator (README).

Suggested order: `P-13` (handshake) → `C-01`–`C-05` (sockets) → `P-01`/`P-08` (meet
list, open a meet) → `L-01`–`L-14` (scoreboard). Results, Schedule and the `T-*`
language controls reuse all of it.


## 1. Meet picker

| ID | Feature | Level | Status | Notes |
| --- | --- | --- | --- | --- |
| `P-01` | List of meets as cards: name, date, location, sport | must | `done` | `PickerScreen` + `MeetCard` over `AppModel.meets` (Sources/SplouchUI/PickerScreen.swift). An inset-grouped `List`, not a ScrollView of drawn cards: the rows were a `RoundedRectangle.stroke`, which is `picker.html`'s `border: 1px solid #2e2e2e`, around content the platform draws better itself — cell backgrounds, separators, insets and the system disclosure glyph. The `Ink` palette went with it; every grey is a semantic system colour now and the only hex left is `#4CAF50`, the live dot, which is product rather than chrome |
| `P-02` | Per-meet picker image on the card, when the meet supplies one | should | `done` | `MeetCard` loads `GET /picker_image/{id}` when `has_picker_image` |
| `P-03` | Offline meets stay listed, marked with a dimmed status dot | must | `done` | `MeetCard`: dimmed dot and 70% opacity when `offline` |
| `P-04` | Empty state when no meets are active | must | `done` | `ContentUnavailableView` titled `picker.strings["no_meets"]`. The server's words are the title and nothing is invented to fill a description (T-05) |
| `P-05` | Picker branding: title, logo, logo above or below the title | should | `done` | `PickerScreen.branding`: title, logo above or below. A title the operator leaves empty is not drawn at all, rather than holding an empty `.title2` line; and a compact vertical size class (landscape on a phone) halves the logo cap and its padding and trims the list's top inset, because the block was taking the top third of the screen with the logo floating in the middle of it |
| `P-06` | Unofficial-results disclaimer under the list | must | `done` | `PickerScreen.footer` renders `strings["results_disclaimer"]` in a grouped block of its own, subheadline and full contrast. It and P-07 were both footnote-sized and greyed down, trailing off the bottom where neither could be read — which for the one line standing between a live feed and a spectator treating it as a result is the wrong end of the page |
| `P-07` | Privacy note, shown whenever attendance counting is on for this server | must | `done` | `PickerScreen.footer`, gated on `analytics_enabled`. Still fine print, but subheadline and secondary rather than footnote and tertiary, so it can be read by someone who goes looking for it |
| `P-08` | Selecting a meet opens the app shell for it | must | `done` | `SplouchRootView.open` → `AppModel.open(_:)` → `MeetShell`; a 404 refreshes the list instead |
| `P-09` | Pull-to-refresh re-fetches the meet list | should | `done` | `.refreshable { await app.load() }` |
| `P-10` | Install hand-off: store links to the native iOS/Android apps once they ship, Add-to-Home-Screen until then | web-only | `n/a` | web-only — an app satisfies it by existing (app.md §0.3) |
| `P-11` | Choose which server to connect to, from a list, in the picker's menu | native-only | `done` | `ServerSheet`: `AppModel.knownServers` (default, `GET /servers`, hand-added), current one checked; the header shows the server name when it is not the default |
| `P-12` | Servers on the local network are offered without anyone typing an address | native-only | `done` | `BonjourBrowser` (NWBrowser on `_splouch._tcp`, TXT `kind` must be `pi`, resolved to host:port) listed in `ServerSheet`; App/Info.plist carries `NSBonjourServices`, `NSLocalNetworkUsageDescription` and the scoped `NSAllowsLocalNetworking` |
| `P-13` | A server can be added by hand, checked before it is saved | native-only | `done` | `ServerSheet.add` → `AppModel.probe(typed:)` must answer `GET /server` before `addServer` saves it. One row, not three: the section header already said "Add server" and the button under it said so again, sitting disabled until the field was filled. The field submits itself — return key, or an arrow that appears once there is something to send — and the footer carries the progress and the error |
| `P-14` | A server whose contract versions differ from the app's gets a one-line notice naming both; the app connects regardless | native-only | `done` | `AppModel.contractNotice` (`api v1 ≠ v2`, symbols only so nothing is translated in the app) shown under the picker title and in the shell header beside the server name; `load()` continues on a mismatch. Tests: AppModelTests |

## 2. App shell

| ID | Feature | Level | Status | Notes |
| --- | --- | --- | --- | --- |
| `A-01` | Three tabs — Scoreboard, Results, Schedule — each with icon and label | must | `done` | `MeetShell.tabs`: a plain SwiftUI `TabView`, which is `UITabBarController` underneath — so it is the system bar (iOS 26's floating glass one, the classic bar below that), with the selection states and VoiceOver tab traits that come with it. Labels are `mobile.scoreboard/results/schedule`, icons SF Symbols. T-01 reaches it through `.tint` (the meet's `time`) and `.toolbarBackground` (its `header_bg`); the unselected item has no SwiftUI hook and stays the system grey |
| `A-02` | Back affordance to the meet picker | must | `done` | The meet is a `navigationDestination` on the picker's `NavigationStack`, so the affordance is the system back button plus the interactive edge swipe. Both pop through one binding in `SplouchRootView`, which is where the session is stopped; A-09 reaches the same path with `dismiss()`. `mobile.back_to_meets` is no longer used — the platform labels and localises its own back button |
| `A-03` | Horizontal swipe moves between adjacent tabs, and the movement is visible — the tabs follow the finger and settle on release | must | `diverges` | **The swipe is there; the finger-tracking is not.** A horizontal drag on the tab's content selects the adjacent tab, so moving between tabs by swiping works — but it changes on release with the tab bar's own crossfade rather than the tabs following the drag, which is the half of A-03 this cannot satisfy. There is no native swipe between tab-bar sections: UIKit and SwiftUI give you a tab bar or a pager, never both, because swiping between peer sections is not an iOS idiom. Finger-tracking would need `UIPageViewController` under a `UITabBar` of our own — which forfeits the iOS 26 floating bar, since only `UITabBarController` draws it — or an interactive transition driven by hand against a framework that does not expect one. The gesture leaves the first 24pt alone, which is what lets it coexist with the system's interactive pop: the old full-width pager claimed that strip, which is why swiping back to the picker never worked before. Both gestures verified on device — edge to leave the meet, anywhere else to change tab. Android keeps its `HorizontalPager` and its `done` row is honest: there the pager *is* the Material idiom. **app.md §0.4 still needs the matching edit** — the native equivalent of the web's edge strips is the platform's own gesture for moving between peer sections, and on iOS that cannot be a drag-tracking pager while a real tab bar is on screen |
| `A-04` | The selected tab survives a relaunch | should | `done` | `@SceneStorage("splouch.tab")` |
| `A-05` | Pull-to-refresh re-fetches config and rejoins the sockets | should | `done` | every tab's scroll view is `.refreshable { await ctx.refresh() }` → re-fetch config, `apply(settings:)`, re-join |
| `A-06` | Content clears notch, Dynamic Island, and home indicator | must (free natively) | `done` | safe-area layout; only the background ignores it |
| `A-07` | Portrait stacks label under icon; landscape drops labels to save height | should | `done` | The system tab bar compacts itself in landscape — icon beside label rather than above it — so there is no `isLandscape` branch in the bar any more. `isLandscape` survives only for `L-16`'s table |
| `A-08` | Window and home-screen title is the meet's `app_window_title`, falling back to its `name` | web-only | `n/a` | web-only — an app satisfies it by existing (app.md §0.3) |
| `A-09` | Meet goes offline mid-session → return to the picker | must | `done` | `MeetContext.checkMeet()` fetches `/meet/{id}/config` on reconnect (`MeetSession.onReconnected`), foreground (`foregrounded()`), pull-to-refresh and `reload`; 404 → `gone` → `MeetShell` pops. A Pi never sets `gone`. Tests: MeetContextTests |

## 3.1 Header

| ID | Feature | Level | Status | Notes |
| --- | --- | --- | --- | --- |
| `L-01` | EVENT number, HEAT number, each a small label above a large value | must | `done` | `BoardHeader.labelled` with `labels["event"]`/`["heat"]`, the word over the number with room between them. In landscape the row moves into the navigation bar (`MeetShell.barBoardHeader`), where the bar was otherwise a back button in the corner and nothing beside it, and the label sits beside its number because a bar is one row high. `BoardHeader` itself no longer draws a background or a hairline: that was the web shell's `border-bottom`, and under a real navigation bar it made two bands of chrome for one screen |
| `L-02` | Event name | must | `done` | `BoardHeader` with `MeetContext.eventName` (T-11), centred in the row — it was pinned left between two items sitting at the edges, which read as floating rather than placed |
| `L-03` | Wall clock, `HH:MM`, ticking every second | must | `done` | `WallClock`: `TimelineView(.periodic(by: 1))`, device time, `HH:mm`. In landscape it is its own trailing toolbar item — one centred item holding EVENT, HEAT, the name and the clock squeezed the clock until it truncated to an ellipsis — and it opts out of the glass capsule iOS 26 gives a toolbar item, since a pill around a ticking time reads as something to tap |

## 3.2 Lane table

| ID | Feature | Level | Status | Notes |
| --- | --- | --- | --- | --- |
| `L-04` | One row per lane, `num_lanes` rows always present | must | `done` | `BoardTable` renders `1...numLanes` from `ScoreboardState` |
| `L-05` | Columns: lane · name (+ alt sub-line) · club · time · delta · place | must | `done` | `PortraitRow` / `LandscapeRow` over `BoardRow` |
| `L-06` | Relay member names on a dimmed second line under the name | must | `done` | `alt` under the name in `thText` |
| `L-07` | Column visibility follows config: `show_name`, `show_club`, `show_delta`, `show_position` | must | `done` | `Columns(settings)` from `show_name/club/delta/position` |
| `L-08` | Column *headers* hide independently of the columns: `show_*_header` | should | `done` | `BoardTable.header` per `show_*_header`, landscape only (L-16) |
| `L-09` | Empty lanes render blank in place — rows never collapse or shift | must | `done` | rows are fixed slots with a `minHeight` floor; blanks render in place. Portrait rows share the height the way the landscape table already did, with 52pt as the floor rather than the size: fixed at 52 under a Spacer, a six-lane board drew 312pt of stripes and left the rest of the screen bare, which is a table sized to its content rather than a board filling its board |
| `L-10` | Frames are partial: merge changed keys into local state, never replace | must | `done` | `ScoreboardState.apply` merges key by key (Board/ScoreboardState.swift); running flags first, then `running_time`, then cells. Tests: ScoreboardStateTests |
| `L-11` | A running lane's time is styled distinctly; on stop it plays a one-shot "locked" transition, cancelled if the lane starts running… | must | `done` | `TimeCell`: running dimmed, `.locked(generation:)` replays a 0.8s white→timing flash per edge |
| `L-12` | Every running lane's time cell shows the race clock: one value for the heat, re-based by the server every couple of seconds and… | must | `done` | `RaceClock`/`ScoreboardState` (tested) + `ScoreboardTab.task` ticking every 100ms off `ContinuousClock` while the tab is on screen; `LaneNumber` pulses and finishes its cycle before stopping; `MeetShell` suspends on backgrounding and wakes on foreground. `running_time` format taken from the reference (`m:ss.hh` / `ss.hh`), not stated in api.md |
| `L-13` | Event or heat change blanks all times, deltas, and places | must | `done` | three cases as app.md states them: baseline after a connect, times kept when a lane was running on the previous frame (ticker stopped), blank otherwise. Tests: ScoreboardStateTests |
| `L-14` | Returning to the tab re-runs layout and refreshes the clock | must (native: on-appear) | `done` | `ScoreboardTab.task` ticks on appear; `.onDisappear` suspends |

## 3.3 Layout

| ID | Feature | Level | Status | Notes |
| --- | --- | --- | --- | --- |
| `L-15` | Portrait: two-line compact row — lane number spanning left, name on line 1 with club right-aligned, time and delta and place on… | must | `done` | `PortraitRow`: lane number spanning, name + club right, time · delta · `#place`. The table holds off the floating tab bar by a fixed gap (`BoardTable.bottomGap`) so the last lane is not read against the glass |
| `L-16` | Landscape: full table with a header row, row font scaled to lane count | should | `done` | `LandscapeRow` + header, font = 42% of height / lanes, clamped 11–32pt |
| `L-17` | Long names shrink to fit their cell, ellipsis only as a floor | must | `done` | `fitOneLine()` = `lineLimit(1)` + `minimumScaleFactor` + tail truncation |

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
| `R-01` | Until the first snapshot: an empty grid, with "Waiting for results…" below it wherever there is room to say so | must | `diverges` | `ResultsTab`: the shared `Unavailable` view titled `mobile.waiting_results`, **not** an empty grid with the line under it. `diverges` from app.md's wording on purpose: blank rows mean something on the Scoreboard, where a heat is live and they fill in (L-09), but before the first snapshot they are a table the web had to draw to occupy the page and they tell a spectator nothing. The words are unchanged — "Waiting for results…" is truer during a meet than an absence. app.md R-01 needs the matching edit |
| `R-02` | A disconnect, or `meet_live` going false, wipes the board and returns it to that state | must | `done` | `MeetSession` wipes `results` on the results socket's disconnect and on `meet_live` false (Session/MeetSession.swift). Tests: MeetSessionTests |
| `R-03` | Header shows the snapshot's own event, heat, and event name | must | `done` | `BoardHeader` from the snapshot |
| `R-04` | Same six columns and visibility flags as the Scoreboard tab | must | `done` | same `BoardTable`, `Columns(settings)` |
| `R-05` | Lane sort: row index = `channel`; a lane with no final time leaves its row blank | must | `done` | `ResultsBoard.rows`: row = `channel`, `sort` absent reads as lane (Board/ResultsBoard.swift). Tests: ResultsBoardTests |
| `R-06` | Place sort: rows fill top-down as a ranking | must | `done` | `ResultsBoard.rows` with `sort == "place"` fills top-down |
| `R-07` | A missing time renders as `—`, not blank; a missing place renders empty — no dash, and no `#` in front of it | should | `done` | `ResultRow.time` is `—` when empty, `place` is `""` when empty; the view renders the strings as they are |
| `R-08` | Long names shrink to fit rather than clipping | should | `done` | `fitOneLine()` |
| `R-09` | Final times carry the "locked" styling | should | `done` | `ResultRow.locked` → `TimeCell` locked styling |
| `R-10` | Returning to the tab re-joins the meet, reconnecting first if needed | must | `done` | `ResultsTab.onAppear` and tab change → `MeetSession.resultsTabShown()`: re-join if connected, wake otherwise |

## 5.1 The list

| ID | Feature | Level | Status | Notes |
| --- | --- | --- | --- | --- |
| `S-01` | Every heat as a card: scheduled time, "Event N — Heat M", event name | must | `done` | `HeatCard` over `ScheduleView.visible`; `GET /meet/{id}/schedule` on a cloud, `GET /schedule.json` on a Pi (`SplouchAPI.piSchedule`). Seen on both. All three sit on one line, the event name to the right of "Event N — Heat M" rather than under it. Sizes follow the platform's body text rather than the web stylesheet's: names 17pt, lane numbers 15, clubs 14, the heading 17 semibold — it was 14/13/12 with a 14pt heading, so the heading was smaller than the rows it headed and the names, on the screen a spectator reads hardest, were four points under every other app's body. Rows sit 3pt apart rather than 6. The type scales with the device's text size through a `@ScaledMetric` multiplier rather than `Font.custom(_:size:relativeTo:)`, which only scales a face the bundle has — T-03 falls back to the system monospace for an unknown name, and that line would then be the one ignoring the setting. Past `dynamicTypeSize.isAccessibilitySize` the row reflows instead of shrinking: number and name take the full width and wrap, club and seed drop underneath, and the seed time is pinned to one line because a wrapped time reads as two times. Note the theme tokens read across their names: "Event N — Heat M" takes `schedule_event` and the event name takes `row_text`, swapped on request so the heat identifier is the coloured one |
| `S-02` | Each card lists its lanes: lane number, name, club, seed time | must | `done` | `HeatCard` lane rows |
| `S-03` | Relay entries show member first names joined by `·` | should | `done` | `ScheduleView.displayName` |
| `S-04` | Alternating card backgrounds, computed over *visible* cards so filtering keeps the stripe | should | `done` | `VisibleHeat.stripe` → `rowOdd`/`rowEven` |
| `S-05` | The heat the meet is on is highlighted in the list | must | `done` | `VisibleHeat.isCurrent` → accent bar; `MeetContext.currentHeat` from either socket |
| `S-06` | The list auto-scrolls to the current heat once per appearance | must | `done` | `ScheduleTab.scrolledToCurrent`, re-armed on appear and on `scenePhase == .active` |
| `S-07` | Empty state when no meet file is loaded | must | `done` | `ContentUnavailableView` titled `mobile.no_meet` on a Pi with empty `heats`, `mobile.no_schedule` on a cloud. It keeps the scroll view, so A-05's pull-to-refresh still works on an empty tab |

## 5.2 Filtering

| ID | Feature | Level | Status | Notes |
| --- | --- | --- | --- | --- |
| `S-08` | Full-screen filter sheet, opened from a button in the top bar | must | `done` | `FilterSheet` from a navigation-bar toolbar button. Order is field, tokens, switches, reset — and the three below the field stand down the moment it takes focus, not once something is typed: keyed to the text, the tap did nothing and the first letter then pushed the sheet down a row at a time. Title inline, so it shares the bar with the confirming checkmark |
| `S-09` | Typeahead search over swimmers and clubs, off a local index | must | `done` | A field that is a row in the sheet, over a `SuggestionIndex` built from the `S-01` start list — no request. **Not `.searchable`**: that is built to filter the content on screen and this field does not filter anything, it adds a term to a list, so tapping it pushed the system's search presentation — title and confirm swapped for a cancel X — over a body with nothing new to show, which read as a second window drawn to look like the first. It is entry, the way Mail takes a recipient. The clear button `.searchable` gave for free is explicit. `GET /search_suggestions` was removed from both servers (2026-09-13); it only ever read `lane.name`, `lane.club` and `lane.swimmers[].name`, all of which the schedule payload already carries, and answering from the server's list could suggest a name our lanes did not have yet. Rebuilt on every re-fetch (`S-21`). No debounce: the wait only ever spared the server. Match is substring of the folded query against a precomputed folded key (lowercase → NFD → expand the 17 letters with no canonical decomposition → drop above U+007F), so `Île-des-Sœurs` is reachable as `ile-des-soeurs`; the field never autocapitalises. Tests: FoldTests, SuggestionIndexTests |
| `S-10` | Suggestions show type (swimmer/club), name, and club; already-added ones are marked and inert | should | `done` | icon per type, name, club; added ones checked and disabled. Swimmers first, then clubs, capped at 20 |
| `S-11` | Active filters appear as chips; tapping a chip's × removes it | must | `done` | chips in a `FlowLayout`, × removes. The × carries a 44pt target with negative padding taking it back out of the layout, so the chip stays chip-sized: at 17pt, with chips shoulder to shoulder, a slightly-off tap removed the wrong swimmer |
| `S-12` | A count badge on the filter button shows how many filters are active | should | `done` | the count sits beside the symbol inside the button, and filters being active also fills the glyph and takes the meet's timing colour. It was an overlay offset outside the symbol, which a toolbar item's glass capsule clipped |
| `S-13` | Filters are OR-ed: a lane matches if it hits *any* club or swimmer filter | must | `done` | `ScheduleView.laneMatches` ORs every term (Schedule/ScheduleFilter.swift). Tests: ScheduleFilterTests |
| `S-14` | A swimmer filter matches relay members, not just the lane's display name | must | `done` | `ScheduleView.laneMatches` checks `lane.swimmers[].name` as well as `lane.name` |
| `S-15` | With filters on, non-matching lanes are hidden and heats with no match disappear | must | `done` | `ScheduleView.visible` |
| `S-16` | All heats toggle: keep every heat visible, still filtering the lanes inside | should | `done` | `Toggle` on `filter.showAllHeats`, drawn as a capsule by `.button` toggle style so it and S-17 share one row instead of taking two full-width ones, in a `FlowLayout` so a long translation wraps rather than clips. Still a Toggle, so VoiceOver announces a switch; on is filled and off is outlined, because `.bordered` draws the label in the accent either way and an off switch read as on |
| `S-17` | Upcoming toggle: hide every heat listed *ahead* of the current one, keeping that one | should | `done` | `Toggle` on `filter.upcomingOnly`, same capsule treatment as S-16; `ScheduleView.visible` cuts by index and changes nothing when the current heat is unknown |
| `S-18` | Reset clears filters and both toggles, behind a confirmation | should | `done` | `confirmationDialog` with `mobile.reset_confirm` |
| `S-19` | Distinct empty states for "no swimmers match these filters" and "no search results" | should | `done` | `mobile.no_matches` on a `ContentUnavailableView` in the Schedule tab, offering `mobile.reset_filters` as its action when there is something to clear; `mobile.no_search_results` as a row in the filter sheet's search results. Both served |
| `S-20` | Filters live only for the session — not persisted | should | `done` | `ScheduleFilter` lives on `MeetContext`, discarded with it |

## 5.3 Refresh

| ID | Feature | Level | Status | Notes |
| --- | --- | --- | --- | --- |
| `S-21` | A new schedule from the Pi refreshes the list | must | `done` | `MeetSession.onScheduleUpdate` → `MeetContext.loadSchedule()`, filters pruned to names that still exist, `S-09`'s index rebuilt with it |

## 6. Connection and session

| ID | Feature | Level | Status | Notes |
| --- | --- | --- | --- | --- |
| `C-01` | Three independent sockets: `/ws/scoreboard`, `/ws/results`, `/ws/schedule` | must | `done` | `MeetSession` opens `/ws/scoreboard`, `/ws/results`, `/ws/schedule`, one `SplouchSocket` each (Session/MeetSession.swift). Tests: MeetSessionTests |
| `C-02` | `join_meet {meet_id, vid}` on every connect, including every reconnect | must | `done` | `SplouchSocket` sends `join` on every connect including reconnects; nil on a Pi, which has no rooms (Transport/SplouchSocket.swift). Tests: SplouchSocketTests |
| `C-03` | Automatic reconnect, capped exponential backoff (web: 500ms → 5s) | must | `done` | 500ms doubling to 5s, reset on a successful open (`SocketTiming.standard`) |
| `C-04` | Heartbeat `ping` every 15s; no inbound frame for 35s means dead — close and reconnect | must | `done` | `ping` every 15s; no inbound frame for 35s closes the socket, which reconnects |
| `C-05` | On foreground or network-restored: probe with a `ping`; no `pong` within ~4s means dead | must | `done` | `SplouchSocket.wake()` (tested) called from `MeetShell` on `scenePhase == .active` and when `NetworkWatcher.isOnline` turns true |
| `C-06` | Frames sent while disconnected are queued and flushed on connect | should | `done` | frames sent while disconnected are queued and flushed before the join |
| `C-07` | Unknown events are ignored, not treated as errors | must | `done` | unknown events pass through `SplouchSocket` and fall to `default` in `MeetSession`; unknown `update_scoreboard` keys are ignored by `ScoreboardState` |
| `C-08` | `reload` → re-fetch config and redraw (web: full page reload) | must | `done` | `MeetSession.onReload` → `MeetContext.refresh()`: re-fetch config, rebuild the board if the lane count changed, re-join |
| `C-09` | `meet_live` gates live affordances; a `disconnect` implies `meet_live = false` | must | `done` | `ScoreboardState.socketDisconnected()` sets `meetLive = false` and stops the clock; `MeetSession` wipes results on the results socket's drop |
| `C-10` | Anonymous per-install, per-server id (`vid`) sent with `join_meet` | must | `done` | `VidStore`: a random UUID per `ServerAddress.origin` (scheme+host+port), created on first use, `UserDefaults`-backed (Session/VidStore.swift). Never derived from the device. Never sent on a Pi, which has no `join_meet` |

## 7. Theme and language

| ID | Feature | Level | Status | Notes |
| --- | --- | --- | --- | --- |
| `T-01` | Palette from the meet's config: `bg`, `header_bg`, `header_border`, `header_label`, `header_value`, `th_text`, `th_bg`… | must | `done` | `Palette(ThemeColors)` through the environment |
| `T-02` | Schedule-specific colours `schedule_event`, `schedule_time`, `schedule_name`, `schedule_club`, each with a built-in default | should | `done` | `HeatCard` uses `scheduleEvent/Time/Name/Club` |
| `T-03` | Three font roles — `family` (text), `digits` (clock), `timing` (times and deltas) | must | `done` | `Faces`: `family` for text, `digits` for EVENT/HEAT/clock, `timing` for times and deltas; six faces bundled in App/Fonts, unknown names fall back to system monospace |
| `T-04` | Column headers and header labels are the server's words, never the app's | must | `done` | `MeetContext.labels` via `LabelResolver`: the `/i18n` table for the effective language and the device's style, falling back to `settings.labels` when no table is cached or the language's table is empty. Nothing is layered on top: there is no per-meet override |
| `T-05` | The app's own chrome — tab names, empty states, filter UI — is fetched and cached, not translated in the app | must | `done` | served words come from `StringTable.mobile` (`GET /i18n/{lang}`, cached, snapshot floor); words about the app or the device — the server sheet, nearby, connection and address errors, retry, open board — are native in `SplouchUI/Resources/Localizable.xcstrings` (en, fr, es) via `Native`; Cancel, Done and OK use the platform's own labels where SwiftUI offers them (iOS 26 roles, alerts, confirmation dialogs). `SnapshotCoverageTests` asserts every `mobile(...)` key the app uses is in the captured `en.json` |
| `T-06` | Language defaults to the meet's locale and the user may override it | must | `done` | `MeetContext.effectiveLanguage` = preference or `settings.locale` |
| `T-07` | Missing theme keys fall back to the documented defaults rather than rendering unstyled | must | `done` | `ThemeColors` / `ThemeFonts` fall back per key to the servers' own defaults (`cloud_server._DEFAULT_COLORS`, `state.DEFAULT_THEME_COLORS`). Tests: ThemeTests |
| `T-08` | A language control, per device, applying to every meet opened afterwards | should | `done` | picker menu → a `LanguageSheet` shaped like the server list, rows with the current one checked, rather than a Picker nested inside the menu — a menu that opens a menu buries the choice and leaves the current value nowhere to show. `AppModel.setLanguage`, stored in `Preferences`, `?lang=` on `/picker/config`, applied to every meet opened afterwards. The list is `GET /locales`, with the captured `Resources/i18n/locales.json` as its floor; a failed refresh keeps the previous list |
| `T-09` | A short/long control over the EVENT and HEAT headers only, starting from short | should | `diverges` | **There is no control: the labels are always long.** Product decision 2026-09-14, on top of 2026-09-13's (which had already dropped app.md's third `prefs_auto` row and made long the default rather than short). Withdrawn, not deleted — `Preferences.effectiveLabelStyle` returns `.long` and reads over the stored value rather than rewriting it, so a user who had chosen short keeps that choice and gets it back if the control returns. Reverting is uncommenting the picker in `PickerScreen.toolbar` and returning `labelStyle` from that property; `LabelStyle`, `AppModel.setLabelStyle`, `MeetContext.setLabelStyle`, the decode path and `StringTable.labels(_:)` are untouched and still covered by the existing tests. `settings.label_style` is still decoded and still not consulted. The server needs nothing: `prefs_labels`, `prefs_short` and `prefs_long` are still served and still in the snapshot. app.md T-09 needs the matching edit |
| `T-10` | A built-in snapshot of the strings is the floor: compiled into the app, refreshed from the server, cached to disk | must | `done` | one checked-in JSON body per language plus `locales.json` in `Sources/SplouchCore/Resources/i18n/`, captured verbatim by `scripts/update-strings.sh` from the default cloud; the run-time cache stores the fetched body verbatim beside its ETag (`FileBundleCache`), same shape, one decoder; `StringTable` is the lookup chain |
| `T-11` | The event name follows the chosen language, composed from parts the server sends | should | `done` | `EventName.compose`/`resolve` join `event_name_parts` against `StringTable.eventVocabulary`, falling back to `event_name`; mirrors the reference `composeEventName` exactly (Strings/EventName.swift). Tests: EventNameTests |

## 8. Accessibility

`app.md` carries no IDs for this, so there is nothing to join against and nothing
below claims one — IDs are the key across three repos and are not invented here.
Recorded so the next person knows what was done and what was only started.

| Area | State | Notes |
| --- | --- | --- |
| Board rows | done | A lane is one accessibility element saying the whole lane, not six Texts read as unrelated fragments. The sentence is composed from the server's own column words (`T-04`), so it is spoken in the meet's language rather than the app's; an empty lane says only its number. `BoardTable.spoken(_:)` |
| EVENT / HEAT | done | The word and its number read as one, and say nothing at all before a number arrives rather than stopping VoiceOver on a blank |
| Hit targets | done | The filter chip's remove × and the entry field's clear × were sized to their 17pt symbol against the HIG's 44. The chip's is the one that mattered — chips sit shoulder to shoulder, so a slightly-off tap removed the wrong swimmer |
| Decorative glyphs | done | The meet row's chevron, the entry field's magnifying glass and the person/building icons are hidden: each sat beside text already saying the same thing |
| Headers | done | Heat headings carry `.isHeader`, so the rotor can jump heat to heat instead of walking every lane — on the screen whose whole purpose is finding one swimmer among several hundred |
| Selection | done | The server and language sheets carry `.isSelected`; the checkmark was the only thing marking the current choice and a glyph says nothing out loud |
| Dynamic Type | partial | The picker, the sheets and the schedule scale (see `S-01`). The board does not, on purpose: `L-16` computes row sizes from the height they share, so scaling would fight the layout rather than serve it |
| Reduce Motion | done | The picker's live dot and `CardButtonStyle` both honour it. The board's `L-12` pulse and `L-11` flash do not yet |
| VoiceOver, heard | **not done** | None of the above has been run under VoiceOver. The labels and traits are in place and compile; whether the board *reads* sensibly is a judgement only the screen reader settles |
| Contrast | n/a | The palette is the operator's (`T-01`), so contrast is theirs to get right; the app renders what it is sent |
