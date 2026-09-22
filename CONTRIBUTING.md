# Contributing to Splouch for iOS

Thanks for taking an interest. This is the spectator client: it reads a meet and shows
it, and it does that on a phone that may be sitting in a noisy pool gallery on a LAN with
no internet, or four hundred kilometres away through the cloud relay. The bar for a change
is not "it compiles", it is "it still reads right at arm's length while a heat is
swimming".

By participating you agree to the [Code of Conduct](CODE_OF_CONDUCT.md).

---

## The contracts come first

Two documents in the sibling [`Splouch`](https://github.com/olivierouellet/Splouch) repo
own what this app does, and **neither is ever copied into this tree**:

| | |
| --- | --- |
| [`docs/app.md`](https://github.com/olivierouellet/Splouch/blob/master/docs/app.md) | What a spectator sees and does, one feature per ID (v1) |
| [`docs/api.md`](https://github.com/olivierouellet/Splouch/blob/master/docs/api.md) | Sockets, events, payloads (v2) |

[`parity.md`](parity.md) is this repo's ledger against `app.md`: one row per feature ID,
whether it is built here, and why not. A change that implements, defers or diverges from a
feature updates its row in the same commit.

**Never invent a wire field.** If a payload doesn't carry what you need, the fix is in
`api.md` and the server, not a guess here. If the app has to behave differently from
`app.md` for a reason iOS imposes, that is a `diverges` row — build it, write down what it
does instead and why, and say in the PR that `app.md` needs the matching edit.

---

## What helps most

| | |
| --- | --- |
| **Time on a real device** | Most of `parity.md` was confirmed on the simulator. The section at the top lists what has *not* been seen on a screen or heard under VoiceOver — confirming any of it, or reporting that it's wrong, is the most useful thing you can do. |
| **Reports from a real meet** | Anything that surprised you in the gallery: a board that stopped updating, a reconnect that didn't, a name that clipped. |
| **Accessibility** | Dynamic Type at the accessibility sizes, VoiceOver order and traits, contrast in both themes. |
| **Languages** | The native words live in `Sources/SplouchUI/Resources/Localizable.xcstrings` (en, fr, es). The served words belong to the server — see [Strings](#strings). |

---

## Setup

```sh
swift test
```

That is the whole inner loop. `SplouchCore` is Foundation-only and its suites run on
macOS, so most work needs no simulator and no Xcode UI.

For the screens, and for anything you want to see:

```sh
xcodebuild -project App/Splouch.xcodeproj -scheme Splouch \
  -destination 'platform=iOS Simulator,name=iPhone 17' build
```

[`emulator.md`](emulator.md) has the full simulator recipe — booting a device, installing,
launching against a local server, taking screenshots. The [README](README.md) has the
two dev servers and how to push live frames without a timing console.

Debug builds read `SPLOUCH_SERVER`, `SPLOUCH_MEET` and `SPLOUCH_TAB` from the launch
environment. Be aware that a server address you have already saved in the app wins over
`SPLOUCH_SERVER` — reset the app's content if it seems to ignore you.

---

## Before you open a pull request

```sh
swift test
```

Green on `main`, and expected to stay that way. `LiveServerTests` skips unless
`SPLOUCH_LIVE_SERVER=http://host:port` points at a real server — fine for most changes, not
fine for one that touches `SplouchAPI` or the socket loop. Run it against a local Pi or a
local cloud for those.

Anything touching a screen also builds for the simulator and gets looked at, in both
orientations if the layout moved. Say in the PR what you saw.

---

## Conventions

These are the ones that trip people up. Each has a reason in the tree.

**`SplouchCore` imports Foundation and nothing else.** No SwiftUI, no UIKit, no third
party. It is the part that runs under `swift test` on macOS, and that is what keeps the
loop fast.

**No dependencies.** `Package.swift` has none, deliberately: the app ships to a phone in a
building with no internet, and every package added is one more thing to audit and to keep
building on the next Swift. Bring what you need in, in as little code as does the job.

**Swift 6 strict concurrency.** `@unchecked Sendable` is used, but only in one shape: a
`final class` whose mutable state is behind an `NSLock`, or a wrapper over a type Apple
documents as thread-safe without annotating it — `UserDefaults`, `URLSessionWebSocketTask`.
Each one carries the reason near it. An `@unchecked` that is really "the compiler was in my
way" doesn't pass review; reach for an `actor` or a value type instead.

**Don't format the tree.** There is no `swift-format` configuration here on purpose, and
running the formatter rewrites hand-aligned declarations and wrapped argument lists that
are laid out to be read. The editor settings in `.vscode/` turn format-on-save off for
Swift for exactly this reason.

**Tests are Swift Testing** (`@Test`, `#expect`), one suite per model, with the HTTP stub
and fake WebSocket in `Tests/SplouchCoreTests/Support/`. A network change is tested against
those, never against a live server in the default run.

**The app target is tracked.** `App/Splouch.xcodeproj` and its shared scheme are in git so
a clone can build; only `xcuserdata/` is ignored. Fonts under `App/Fonts/` are copies from
`../Splouch/shared/static/fonts/` — refresh them from there, never edit them here.

### Strings

Which table a word belongs in is decided by what the word is *about* (`app.md` T-05), and
getting it wrong is the most common mistake in this repo:

* **A word a spectator reads that the web pages also show** — tab names, empty states, the
  filter sheet, event names — is **served**, through `GET /i18n/{lang}` and
  `StringTable.mobile(...)`. It is added **on the server first**. The JSON under
  `Sources/SplouchCore/Resources/i18n/` is a captured floor for when the server can't be
  reached; it is regenerated with `scripts/update-strings.sh <base url>` and **never edited
  by hand**. `SnapshotCoverageTests` fails if the app asks for a key the snapshot lacks —
  that failure means "capture it", not "hand-add it".
* **A word about the app or the device** — the server sheet, nearby servers, connection and
  address errors, retry — is **native**, in `Localizable.xcstrings` behind the `Native`
  enum, in all three languages.

### Commits

One topic per commit, the area in brackets, and a title that says what changed and reads
as a sentence:

```text
[Board] A lap does not outlive its heat. The count clears with the row rather than waiting for the console to send the zero
[Schedule] The heading says it short and the time joins the column
[Core] The socket backs off instead of hammering a server that is still booting
```

Areas in use: `[Board]`, `[Schedule]`, `[Picker]`, `[Filter]`, `[UI]`, `[Shell]`,
`[Theme]`, `[Prefs]`, `[Strings]`, `[A11y]`, `[Core]`, `[App]`, `[Build]`, `[Docs]`.
Add a body when the *why* isn't obvious from the diff — that is where this tree keeps its
reasoning.

---

## Reporting a bug

Open an issue — the form asks for what's needed: what happened, which screen, which server,
the app and iOS versions, and the one question that routes it fastest, **did the web
scoreboard show the same thing at the same moment?** If it did, the bug is in the
[server repo](https://github.com/olivierouellet/Splouch/issues), not this one.

For anything security-sensitive, don't open a public issue — follow
[SECURITY.md](SECURITY.md), which also sets out what this app assumes about the network it
is on.

---

## Licence

Splouch for iOS is [MIT](LICENSE). Contributions are accepted under the same terms.
