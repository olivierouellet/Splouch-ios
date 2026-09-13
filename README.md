# Splouch for iOS

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
- `Tests/SplouchCoreTests` — Swift Testing suites, one per model.
- The SwiftUI target sits on top of `SplouchCore` and is added once an iOS SDK is
  available on the build machine.

## Building and testing

```sh
scripts/test.sh
```

Runs `swift test` when SwiftPM works. On a machine whose CommandLineTools cannot
launch `swift-package`, it falls back to driving `swiftc` directly with the macOS
SDK that matches the compiler and the `Testing` framework that ships in
CommandLineTools. Either way the same suites run.

Dev servers (both default to port 5000, which macOS AirPlay Receiver may hold):

```sh
cd ../Splouch/server && uv run python app.py                                   # Pi
cd ../Splouch/cloud  && DATA_DIR=/tmp/splouch-cloud uv run uvicorn cloud_server:app --port 5055
```

## Refreshing the built-in strings

`Sources/SplouchCore/Strings/BuiltInStrings.generated.swift` is the compiled floor
of app.md T-10. Regenerate it from a running server, never by hand:

```sh
scripts/update-strings.sh http://127.0.0.1:5055
```
