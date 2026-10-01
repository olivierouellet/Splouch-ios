# Screenshots

Every screen in English and French, light and dark, at the two sizes App Store
Connect requires: 6.9" iPhone (iPhone 17 Pro Max, 1320 × 2868) and 13" iPad
(iPad Pro 13-inch, 2064 × 2752).

```text
<device>/<lang>/<light|dark>/1-picker.png
                             2-scoreboard.png
                             3-results.png
                             4-schedule.png
AppStore/<en-CA|fr-CA>/<device>/   the dark set, ready to drop into each listing
```

The picker is the live `splouch.ca`; the meet screens are a local Pi replaying
heat 1 of `200m_medley_2heats`. All images are flattened (no alpha channel), which
App Store Connect requires. The app icon is not here: App Store Connect takes it
from the build's `App/AppIcon.icon`.

Recapture with [`scripts/screenshots.sh`](../scripts/screenshots.sh); its header
lists what has to be running first.
