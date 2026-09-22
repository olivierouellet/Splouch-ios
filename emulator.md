# Running Splouch on the simulator

iOS has no emulator — it has the **Simulator**, which runs a native arm64 build of
the app against a simulated device rather than emulating hardware. Everything
below drives it from the command line; nothing here needs the Xcode UI.

## What you need

- Xcode 26.6 (Swift 6.3.3) with the **iOS 26.5** platform installed.
- A booted simulator device. `xcrun simctl list devices available` shows what is
  installed; the recipes below use `iPhone 17`.

Signing is automatic with no team set, so a simulator build needs no account. A
device build does — pick a team in Xcode first.

## The short version

```sh
# 1. Boot a device and bring the Simulator window up
xcrun simctl boot "iPhone 17"
open -a Simulator

# 2. Build the app target
xcodebuild -project App/Splouch.xcodeproj -scheme Splouch \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath .build/xcode build

# 3. Install and launch
xcrun simctl install booted .build/xcode/Build/Products/Debug-iphonesimulator/Splouch.app
xcrun simctl launch booted app.splouch.ios
```

The bundle id is **`app.splouch.ios`**. (It is not `ca.splouch.Splouch`; that
guess fails with a "found nothing to launch" error.)

`xcrun simctl boot "iPhone 17"` fails harmlessly if the device is already booted,
and `booted` in the later commands resolves to whichever single device is running.
With more than one booted, pass the UDID from `simctl list` instead.

## Pointing the app at a server

Debug builds read four launch-environment variables, ignored in release. `simctl`
passes an environment variable through to the app by prefixing it with
`SIMCTL_CHILD_`:

```sh
SIMCTL_CHILD_SPLOUCH_SERVER=http://127.0.0.1:5056 \
SIMCTL_CHILD_SPLOUCH_MEET=<meet-id> \
SIMCTL_CHILD_SPLOUCH_TAB=scoreboard \
xcrun simctl launch booted app.splouch.ios
```

- `SPLOUCH_SERVER` — start on this server instead of the default cloud.
- `SPLOUCH_MEET` — open this meet id immediately.
- `SPLOUCH_TAB` — `scoreboard`, `results` or `schedule`.
- `SPLOUCH_LINK` — hand the app a scanned QR link at launch (`P-16`), as if the OS
  had routed a universal link to it.

### Scanning a code without a camera (`P-16`)

A real universal link is routed by iOS only when the host serves an
`apple-app-site-association` naming this app, and a simulator cannot be handed a
signed one — so `xcrun simctl openurl` with an `https` link opens Safari, not the
app. `SPLOUCH_LINK` delivers the same link to the model with the OS's own
resolution left out, which is everything the app itself does with a code:

```sh
SIMCTL_CHILD_SPLOUCH_SERVER=http://127.0.0.1:5055 \
SIMCTL_CHILD_SPLOUCH_LINK='https://127.0.0.1/add?server=http%3A%2F%2F127.0.0.1%3A5056' \
xcrun simctl launch booted app.splouch.ios
```

The link's **host must be the default server's** — `SPLOUCH_SERVER`'s host in a
debug run, `splouch.ca` otherwise — because that is the only authority the app
accepts (`P-16`). A link on any other host raises the prompt as a bad one, which
is itself worth seeing.

> **`SPLOUCH_SERVER` only sets the default server, and a server saved in
> preferences beats it.** Once the app has stored one, it silently ignores the
> variable and keeps talking to whatever it saved — a session can spend a long
> while rendering live splouch.ca while you believe it is on your local cloud.
> Tell them apart by the meet list in the picker, never by the variable you
> passed. To clear the stored preference, wipe the container:
>
> ```sh
> xcrun simctl uninstall booted app.splouch.ios   # then install again
> ```

### Local dev servers

Port 5000 is held by macOS AirPlay Receiver, so both servers get explicit ports.
From the sibling `../Splouch` repo:

```sh
cd ../Splouch/server && uv run uvicorn app:app --port 5056                 # Pi
cd ../Splouch/cloud  && DATA_DIR=/tmp/splouch-cloud \
  uv run uvicorn cloud_server:app --port 5055                              # cloud
```

For live frames without a timing console, log in to the Pi (`score` / `swimming`)
and `POST /test_play {"name": "200m_medley_2heats.cts"}`. Relaying those to the
local cloud needs a key: `POST /admin` on the cloud (Basic auth `admin`, empty
password, form `action=add&organizer=Dev`), then save it on the Pi via
`POST /settings`. README.md has the full form fields.

## Driving and capturing the simulator

```sh
xcrun simctl io booted screenshot out.png          # capture
scripts/sim-tap.sh "iPhone 17" 0.5 0.93           # tap, as fractions of the screen
```

`sim-tap.sh` clicks through System Events, so the terminal needs Accessibility
access (System Settings → Privacy & Security → Accessibility). Two quirks worth
knowing before you debug a tap that "does nothing":

- A SwiftUI `Menu` needs **two** taps on its button — the first only focuses it.
- Menu *items* ignore synthetic clicks entirely. Drive them with the hardware
  keyboard instead:

  ```sh
  osascript -e 'tell application "System Events" to tell process "Simulator" \
    to key code 125' -e 'tell application "System Events" to tell process \
    "Simulator" to key code 36'
  ```

  (`125` is arrow-down, `36` is return.) `Cmd+Left` / `Cmd+Right` rotate the
  device.

## Tests don't need the simulator

`SplouchCore` is Foundation-only and `SplouchUI` compiles on macOS, so the suite
runs natively on the host:

```sh
swift test
```

Setting `SPLOUCH_LIVE_SERVER=http://host:port` additionally runs two integration
checks against a real server.

## Troubleshooting

| Symptom | Cause |
| --- | --- |
| `Unable to boot device in current state: Booted` | Already booted — carry on. |
| `No devices are booted` | Run the `simctl boot` step, or name a UDID explicitly. |
| Launch fails, "found nothing to launch" | Wrong bundle id — it is `app.splouch.ios`. |
| App shows the wrong meets | A saved server preference is beating `SPLOUCH_SERVER`; uninstall and reinstall. |
| Taps land nowhere | Terminal lacks Accessibility access, or you are tapping a `Menu` item. |
| `xcodebuild` can't find a destination | The iOS 26.5 platform isn't installed — add it in Xcode's Components settings. |
