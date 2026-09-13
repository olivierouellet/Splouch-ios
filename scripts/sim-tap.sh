#!/bin/zsh
# Taps the iOS simulator through System Events (needs Accessibility access for
# the terminal). Coordinates are fractions of the device screen, 0…1. The screen
# is the window's AXGroup, so bezels and the title bar are accounted for.
#
#   scripts/sim-tap.sh "iPhone 17" 0.5 0.93
set -euo pipefail
DEV=$1; X=$2; Y=$3
osascript - "$DEV" "$X" "$Y" <<'APPLESCRIPT'
on run argv
    set dev to item 1 of argv
    set fx to (item 2 of argv) as real
    set fy to (item 3 of argv) as real
    tell application "System Events" to tell process "Simulator"
        set frontmost to true
        set ws to every window
        set theWindow to missing value
        repeat with i from 1 to count of ws
            if (name of item i of ws) starts with dev then
                set theWindow to item i of ws
                exit repeat
            end if
        end repeat
        if theWindow is missing value then error "no window for " & dev
        set screenEl to missing value
        set es to every UI element of theWindow
        repeat with j from 1 to count of es
            if role of item j of es is "AXGroup" then
                set screenEl to item j of es
                exit repeat
            end if
        end repeat
        if screenEl is missing value then error "no screen group in window"
        set p to position of screenEl
        set s to size of screenEl
        set sx to (item 1 of p) + (fx * (item 1 of s))
        set sy to (item 2 of p) + (fy * (item 2 of s))
        click at {sx, sy}
        return "tapped " & (sx as integer) & "," & (sy as integer)
    end tell
end run
APPLESCRIPT
