# Splouch for iOS

[![CI](https://github.com/olivierouellet/Splouch-ios/actions/workflows/ci.yml/badge.svg)](https://github.com/olivierouellet/Splouch-ios/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

The spectator app for [Splouch](https://github.com/olivierouellet/Splouch), the live
swimming scoreboard for timing consoles.

Pick a meet from the cloud, or from the pool's own server on the venue's wifi, and
follow it from the stands: the live scoreboard with the race clock, splits and
places as they land, each heat's results, and the meet's schedule. The app speaks
English, French and Spanish, follows each meet's own theme, and runs on iPhone and
iPad (iOS 17 or later).

---

## Screenshots

| Meets | Scoreboard | Results | Schedule |
| --- | --- | --- | --- |
| <img src="Screenshots/iphone-6.9/en/dark/1-picker.png" alt="Meet picker" width="200"> | <img src="Screenshots/iphone-6.9/en/dark/2-scoreboard.png" alt="Live scoreboard at the finish" width="200"> | <img src="Screenshots/iphone-6.9/en/dark/3-results.png" alt="Heat results" width="200"> | <img src="Screenshots/iphone-6.9/en/dark/4-schedule.png" alt="Meet schedule" width="200"> |
| <img src="Screenshots/iphone-6.9/fr/light/1-picker.png" alt="Choix de la compétition" width="200"> | <img src="Screenshots/iphone-6.9/fr/light/2-scoreboard.png" alt="Tableau en direct à l'arrivée" width="200"> | <img src="Screenshots/iphone-6.9/fr/light/3-results.png" alt="Résultats de la série" width="200"> | <img src="Screenshots/iphone-6.9/fr/light/4-schedule.png" alt="Horaire de la compétition" width="200"> |

Swimmers, clubs and times are fictional (a bundled test recording). Every screen
in English and French, light and dark, on iPhone and iPad is in
[`Screenshots/`](Screenshots/).

---

## Related repositories

| | |
| --- | --- |
| [Splouch](https://github.com/olivierouellet/Splouch) | Scoreboard server, TV kiosk and cloud relay; holds the app and API contracts |
| [Splouch-android](https://github.com/olivierouellet/Splouch-android) | Spectator app for Android |

---

## Documentation

| | |
| --- | --- |
| [Development](docs/development.md) | The contracts, code layout, building and testing, local servers, strings |
| [Simulator](emulator.md) | Booting, installing, launching against a local server, driving and capturing |
| [Parity ledger](parity.md) | One row per feature ID: built here or not, and why |
| [Screenshots](Screenshots/README.md) | What is captured, the App Store set, recapturing |

---

## Community

| | |
| --- | --- |
| [Contributing](CONTRIBUTING.md) | The contracts, setup, the checks a PR must pass, conventions, reporting a bug |
| [Security](SECURITY.md) | Reporting a vulnerability, what the app assumes about the network it is on |
| [Code of Conduct](CODE_OF_CONDUCT.md) | Contributor Covenant 2.1 |

---

## License

MIT. See [LICENSE](LICENSE).
