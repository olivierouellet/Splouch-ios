# Splouch for iOS

[![CI](https://github.com/olivierouellet/Splouch-ios/actions/workflows/ci.yml/badge.svg)](https://github.com/olivierouellet/Splouch-ios/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

The spectator app for Splouch meets. It follows two contracts that live in the
sibling `Splouch` repo and are never copied here:

- `../Splouch/docs/app.md` — what a spectator sees and does (v1)
- `../Splouch/docs/api.md` — sockets, events, payloads (v2)

[`parity.md`](parity.md) is this repo's ledger: one row per feature ID, whether it
is built here and why not.

## Layout

- `Sources/SplouchCore` — Foundation-only, Swift 6 strict concurrency, no UI.
  - `Wire/` envelope and typed payloads
  - `Transport/` `URLSessionWebSocketTask` behind a protocol, and `SplouchSocket`,
    the reconnecting socket loop of app.md §6
  - `Clock/` the race clock (L-12)
  - `Board/` the scoreboard frame merge and the results grid
  - `Session/` server address, per-server `vid`, REST client, `MeetSession`
    (three sockets → tab state)
  - `Strings/` string resolution, labels, event names, the compiled snapshot
  - `Theme/`, `Schedule/`
- `Sources/SplouchUI` — the SwiftUI screens: picker and server sheet, meet shell,
  scoreboard, results, schedule and filter sheet. Compiles on macOS for checking;
  runs on iOS.
- `Tests/SplouchCoreTests` — Swift Testing suites, one per model, plus an HTTP stub
  and a fake WebSocket.
- `App/` — the `@main` entry, Info.plist keys and bundled fonts for the Xcode app
  target (see `App/README.md`).

## Building and testing

```sh
swift test
```

Dev servers (both default to port 5000, which macOS AirPlay Receiver may hold):

```sh
cd ../Splouch/server && uv run python app.py                                   # Pi
cd ../Splouch/cloud  && DATA_DIR=/tmp/splouch-cloud uv run uvicorn cloud_server:app --port 5055
```

## Running on the simulator against local servers

```sh
cd ../Splouch/server && uv run uvicorn app:app --port 5056          # Pi
cd ../Splouch/cloud  && DATA_DIR=/tmp/splouch-cloud uv run uvicorn cloud_server:app --port 5055
xcodebuild -project App/Splouch.xcodeproj -scheme Splouch \
  -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath .build/xcode build
xcrun simctl install booted .build/xcode/Build/Products/Debug-iphonesimulator/Splouch.app
SIMCTL_CHILD_SPLOUCH_SERVER=http://127.0.0.1:5056 xcrun simctl launch booted app.splouch.ios
```

Debug builds read three launch-environment variables, ignored in release:
`SPLOUCH_SERVER` (start on this server instead of the default cloud, without
touching stored preferences), `SPLOUCH_MEET` (open this meet id at once) and
`SPLOUCH_TAB` (`scoreboard`, `results` or `schedule`).

Live frames without a timing console: log in to the Pi (`score` / `swimming` by
default) and `POST /test_play {"name": "200m_medley_2heats.cts"}`. To feed the
local cloud, create a relay key on it (`POST /admin`, Basic auth `admin` with an
empty password by default, form `action=add&organizer=Dev`; the key lands in
`$DATA_DIR/keys.json`) and save it on the Pi with `POST /settings`
(`cloud_settings_submit=1`, `cloud_relay_url`, `cloud_relay_key`).

`swift test` also runs two integration checks against a real server when
`SPLOUCH_LIVE_SERVER=http://host:port` is set.

`scripts/sim-tap.sh "iPhone 17" 0.5 0.93` taps the simulator at a fraction of the
device screen through System Events (the terminal needs Accessibility access), and
`xcrun simctl io <udid> screenshot out.png` captures it.

## Strings

Two kinds, split by what the word is about (app.md T-05):

- **Served.** Everything a spectator reads that the web pages also show — tab
  names, empty states, the filter sheet, the picker's chrome and preference
  controls, the compliance text — comes from `GET /i18n/{lang}` → `mobile`,
  through `StringTable.mobile(...)`, cached on disk and revalidated by ETag.
  `Sources/SplouchCore/Resources/i18n/<lang>.json` are its compiled floor: the
  body of `GET /i18n/{lang}` for each language the default cloud lists,
  verbatim, plus `locales.json`, the body of `GET /locales`, which is the
  language menu's floor when the server cannot be reached. Regenerate them from
  the default cloud before a release and whenever the server's `shared/locales/`
  changes, never by hand:

  ```sh
  scripts/update-strings.sh https://splouch.ca
  ```

  `SnapshotCoverageTests` fails if the app asks for a `mobile` key the captured
  snapshot does not carry, so a new key is added on the server first and
  captured here second.
- **Native.** Words about the app or the device — the server sheet, "nearby",
  connection and address errors, retry, open board — live in
  `Sources/SplouchUI/Resources/Localizable.xcstrings` (en, fr, es) behind the
  `Native` enum. Cancel, Done and OK use the platform's own labels where SwiftUI
  provides them.

## Community

| | |
| --- | --- |
| [Contributing](CONTRIBUTING.md) | The contracts, setup, the checks a PR must pass, conventions, reporting a bug |
| [Security](SECURITY.md) | Reporting a vulnerability, what the app assumes about the network it is on |
| [Code of Conduct](CODE_OF_CONDUCT.md) | Contributor Covenant 2.1 |

## License

MIT. See [LICENSE](LICENSE).
