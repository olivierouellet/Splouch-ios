# Screenshots

Every screen in English, French and Spanish, light and dark, at the two sizes App Store
Connect requires: 6.9" iPhone (iPhone 17 Pro Max, 1320 × 2868) and 13" iPad
(iPad Pro 13-inch, 2064 × 2752).

```text
<device>/<lang>/<light|dark>/1-picker.png
                             2-scoreboard.png
                             3-results.png
                             4-schedule.png
AppStore/<en-CA|fr-CA|es-MX>/<device>/   the dark set, ready to drop into each listing
```

Every screen is the live `splouch.org`: the picker lists its meets, and the meet
screens open Dolphins, one of the test meets it replays around the clock. All images are flattened (no alpha channel), which
App Store Connect requires. The app icon is not here: App Store Connect takes it
from the build's `App/AppIcon.icon`.

Recapture with [`scripts/screenshots.sh`](../scripts/screenshots.sh); its header
lists what has to be running first.
