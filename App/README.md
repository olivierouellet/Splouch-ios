# App target

This folder holds what only Xcode can build: the `@main` entry point, the
Info.plist keys the contract requires, and the bundled fonts. It is not part of
the SwiftPM package.

When Xcode is available:

1. Create an iOS App project here (SwiftUI, iOS 17), replacing its generated
   `App` file with `SplouchApp.swift`.
2. Add the package at the repo root as a local dependency and link `SplouchUI`.
3. Merge `Info.plist` into the target's Info: the scoped ATS exception,
   `NSLocalNetworkUsageDescription`, `NSBonjourServices`, and `UIAppFonts`.
4. Add `Fonts/` to the target (copy resources). The faces come from
   `../Splouch/shared/static/fonts/`, licences alongside; refresh them from there.
5. Set the default cloud URL in `SplouchApp.swift` if `https://splouch.app` is not it.
