<!--
Thanks for this. CONTRIBUTING.md has the setup, the conventions, and the reasoning
behind the ones that look arbitrary: https://github.com/olivierouellet/Splouch-ios/blob/main/CONTRIBUTING.md
-->

## What this changes

<!-- One or two sentences. The *why* matters more than the diff — that is where this
     tree keeps its reasoning. -->

## Checks

```sh
swift test
```

- [ ] Green.
- [ ] `parity.md` updated — the rows this touches say `done`, `deferred` or `diverges`, and a `diverges` row says what the app does instead and why.
- [ ] No wire field invented: every payload key read here is in `api.md`.
- [ ] No new package dependency.
- [ ] The formatter was not run over the tree.

## Seen on a screen

<!-- Which device or simulator, and what you looked at. "Doesn't touch the UI" is a
     complete answer. -->

- [ ] Built for the simulator and looked at.
- [ ] Both orientations, if the layout moved.
- [ ] Doesn't touch the UI.

## Strings

- [ ] Doesn't add a user-visible string.
- [ ] Served string — added on the server first, then captured with `scripts/update-strings.sh`. The snapshot files were not edited by hand.
- [ ] Native string — in `Localizable.xcstrings`, in en, fr and es.

## Also

- [ ] `README.md` / `emulator.md` updated, if this changes something a developer runs.
- [ ] Commits read `[Area] What changed`, one topic each.
- [ ] Accessibility held up: Dynamic Type at an accessibility size, and VoiceOver order and labels, for any screen this touches.

<!-- Closes #NNN -->
