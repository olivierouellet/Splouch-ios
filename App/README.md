# App target

`Splouch.xcodeproj` is the iOS app: one target, `Splouch`, that links the
`SplouchUI` product of the package at the repo root. Everything that only Xcode
can build lives here — the `@main` entry point, the Info.plist keys the contract
requires (scoped local-network ATS exception, `NSLocalNetworkUsageDescription`,
`NSBonjourServices`, `UIAppFonts`), the associated-domains entitlement, and the
bundled fonts.

```sh
xcodebuild -project App/Splouch.xcodeproj -scheme Splouch \
  -destination 'platform=iOS Simulator,name=iPhone 17' build
```

- The fonts come from `../Splouch/shared/static/fonts/`, licences alongside;
  refresh them from there, never edit them here.
- The default cloud URL is set in `SplouchApp.swift`.
- **Universal links (`P-16`).** `Splouch.entitlements` claims `applinks:splouch.ca`
  and `SplouchDebug.entitlements` claims `applinks:splouch.ca?mode=developer`,
  which skips Apple's CDN cache when the association file on the host changes.
  The app half is inert without the host's
  `/.well-known/apple-app-site-association`, which is the `Splouch` repo's to
  serve — see `parity.md` `P-16` for what it must say and what is deployed.
- Signing is automatic with no team set; pick a team in Xcode to run on a device.
