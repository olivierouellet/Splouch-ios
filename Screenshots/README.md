# Screenshots

Every screen in English, French and Spanish, light and dark, at App Store Connect's
sizes: 6.9" iPhone (iPhone 17 Pro Max, 1320 × 2868), 6.3" iPhone (iPhone 17 Pro,
1206 × 2622) and 13" iPad (iPad Pro 13-inch, 2064 × 2752).

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

## Marketing

`Marketing/<en-CA|fr-CA|es-MX>/` (not tracked) holds what the listing shows, built from the dark
captures by [`scripts/store-art.py`](../scripts/store-art.py)
(`uv run --with pillow python scripts/store-art.py`, after a recapture):

```text
screenshots/iphone-6.3/         1206 × 2622   a caption over the capture in a device frame
            iphone-6.9/         1320 × 2868
            iphone-duo-outer/   1398 × 2034   iPhone Duo has no simulator: the 6.3" captures
            iphone-duo-inner/   2007 × 2853   and the 6.9" ones, framed
            ipad-13/            2064 × 2752
artwork/header-5244x2950.png    product page header: three screens, no text
        header-3840x1646.png
        search-5244x2950.png    search results: icon, name, one line, two screens
        search-3840x2560.png
        search-1920x1280.png
```

No URL, price or other platform in the art, as App Store's asset guidelines ask, and
the focal point stays in the middle so any crop keeps it.
