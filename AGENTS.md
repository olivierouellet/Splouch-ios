# Agent instructions

For AI coding assistants (Claude Code, GitHub Copilot, Codex, Cursor and others) working in this repository.
People should start with [CONTRIBUTING.md](CONTRIBUTING.md) and [docs/development.md](docs/development.md). Both say more than this file; when they disagree,
they win.

## What this is

The spectator app for iOS (SwiftUI, Swift 6, no dependencies) for [Splouch](https://github.com/olivierouellet/Splouch)
swim meets. Its contracts are in the Splouch repo: `docs/app.md` (features, by ID) and `docs/api.md`
(sockets and payloads). They are **never copied here**. [`parity.md`](parity.md) is this repo's ledger
against `app.md`.

## Before you finish

```sh
swift format lint --strict -r -p Sources Tests App Package.swift   # `swift format -i …` fixes the layout
swift test -Xswiftc -warnings-as-errors
swift build --triple arm64-apple-ios17.0-simulator \
  --sdk "$(xcrun --sdk iphonesimulator --show-sdk-path)" \
  --scratch-path .build/ios -Xswiftc -warnings-as-errors
uvx rumdl@0.2.77 check .
```

`swift test` builds `SplouchUI` for macOS, so `#if os(iOS)` blocks only compile in the simulator build.
`LiveServerTests` skips without `SPLOUCH_LIVE_SERVER`: not enough for a change to `SplouchAPI` or the socket
loop. A screen change also gets built for the simulator and looked at (see [`emulator.md`](emulator.md)).

## Conventions

* **Never invent a wire field.** If a payload lacks something, the fix is in `api.md` and the server. A
  behaviour iOS forces away from `app.md` is a `diverges` row in `parity.md`.
* A change that implements, defers or diverges from a feature updates its `parity.md` row in the same commit.
* **`SplouchCore` imports Foundation and nothing else.** No SwiftUI, no UIKit, no third party.
* **No dependencies.** `Package.swift` has none, deliberately.
* Swift 6 strict concurrency. `@unchecked Sendable` only for a `final class` whose state is behind an
  `NSLock`, or a wrapper over a type Apple documents as thread-safe, with the reason next to it.
* swift-format owns layout; tests are Swift Testing (`@Test`, `#expect`), against the stubs in
  `Tests/SplouchCoreTests/Support/`, never a live server.
* **Strings:** a word the web pages also show is *served*: it is added on the server first, and the JSON
  under `Sources/SplouchCore/Resources/i18n/` is regenerated with `scripts/update-strings.sh`, never edited by
  hand. A word about the app or the device is *native*, in `Localizable.xcstrings`, in en, fr and es.
* The fonts in `App/Fonts/` are copies from the Splouch repo: refresh them from there, never edit them.

## Commits and publishing

* Commit titles read `[Topic] What changed`, one topic per commit. Areas in use: `[Board]`, `[Schedule]`, `[Picker]`, `[Filter]`, `[UI]`, `[Shell]`, `[Theme]`, `[Prefs]`,
  `[Strings]`, `[A11y]`, `[Core]`, `[App]`, `[Build]`, `[Docs]`; the title reads as a sentence.
* **Never commit, push, tag, publish a release, or open an issue or pull request unless asked.** Approval for
  one of these is not approval for the next.
* Releases go through `scripts/release.sh` (see `docs/development.md`): it tags the release and moves
  `MARKETING_VERSION` to the next version. `main` is always one version ahead; don't tag by hand.
* `main` is protected against force-pushes and deletion: never rewrite history that is already pushed.
* Never post comments on issues or pull requests on the user's behalf without their review.

## AI policy

This project follows its [AI policy](AI_POLICY.md): a person reviews and understands every change, no
autonomous contributions, and nothing is posted on someone's behalf without their review.
