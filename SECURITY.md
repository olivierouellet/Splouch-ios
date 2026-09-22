# Security Policy

This is the iOS spectator client. It logs nobody in, stores no credentials, and cannot
change anything on a meet: everything it does is read a server and draw it. Most of what
follows is about what it reads, what it keeps on the phone, and where it will and won't
send either.

The server, the console decoders and the cloud relay are in the
[Splouch repo](https://github.com/olivierouellet/Splouch) and have their
[own policy](https://github.com/olivierouellet/Splouch/blob/master/SECURITY.md). If the
finding is in what a server *sends*, report it there.

## Reporting a vulnerability

**Don't open a public issue.** Report privately through GitHub:

* [Report a vulnerability](https://github.com/olivierouellet/Splouch-ios/security/advisories/new)
  from the repository's **Security** tab — visible only to the maintainer, or
* Contact [@olivierouellet](https://github.com/olivierouellet) directly.

Useful to include:

* Which part — the server picker and address handling, the socket loop, the string cache,
  or a screen that renders meet content.
* What the attacker has to be: on the same Wi-Fi as the phone, running a server the user
  chose to add, or in a position to answer the app's requests.
* A payload or a server response that shows it. A crafted `GET /i18n/{lang}` body or a
  socket frame is ideal — those and meet content are the app's untrusted input.

This is a one-maintainer project that gets most of its attention on weekends around swim
meets. Expect acknowledgement within 2 weeks; a fix takes as long as it takes, and you'll
be told where it stands. Credit in the release notes if you'd like it, and no objection to
you publishing once a fix has shipped.

---

## Supported versions

| Version | Supported |
| --- | --- |
| Latest App Store / TestFlight build | ✅ Fixes land here |
| `main` | ✅ Fixes land here first |
| Any earlier build | ❌ No backports — update instead |

There is no long-term support branch. The app talks to servers over the versioned
[`api.md`](https://github.com/olivierouellet/Splouch/blob/master/docs/api.md) contract, so
an older build usually keeps working against a newer server — that is a compatibility
promise, not a security one.

---

## What this app assumes

| | |
| --- | --- |
| **It only ever reads** | There is no login, no write endpoint, no admin surface. The app holds nothing an attacker would want to steal from it. |
| **Everything from a server is untrusted text** | Swimmer names, club names, event names and served strings come from whoever typed them into Splash, through a server this phone does not control. They are rendered as text by SwiftUI, never as markup and never as a format string. |
| **Cleartext is for the local network only** | `Info.plist` sets `NSAllowsLocalNetworking`, and nothing else — never `NSAllowsArbitraryLoads`. A `.local` host or a private IP the user types gets `http://`; anything else gets `https://` and the system's normal ATS rules. A remote server that only speaks HTTP will fail to connect, and that is the intended outcome. |
| **The attendance id identifies nobody** | `vid` is a random UUID, generated per server on first use and stored locally. It is never derived from the device — no `identifierForVendor`, no advertising id — and never shared between servers, so two servers cannot correlate a phone. The server counts distinct ids and nothing else. |
| **Nothing leaves the phone but what a server needs** | The app sends the meet it is joining and its `vid`, to the server the user chose. There is no analytics SDK, no crash reporter, no third-party package of any kind — `Package.swift` has no dependencies. |
| **What is cached is only what was served** | The string bundle is cached in Application Support and revalidated by ETag; the server address, the saved language and theme, and the `vid` are in `UserDefaults`. None of it is secret, and all of it goes when the app is deleted. |
| **Adding a server is a deliberate act** | Servers come from the bundled default, from Bonjour on the current network, or from an address the user types. The app does not follow a server's suggestion of another server. |

### Out of scope

* Physical access to an unlocked phone. Everything the app stores is readable there by
  design, and none of it is a credential.
* A malicious server the user chose to add showing false or offensive meet content. Bad
  data drawn as data is a bad meet, not a vulnerability. Bad data that *escapes* being
  data — a crash, a hang, a read outside the app's own state — is very much in scope.
* Another device on the pool-deck LAN watching the app's traffic to a Pi. That traffic is
  cleartext on purpose (the Pi has no certificate and no internet), and it carries only
  what the scoreboard on the wall is already showing the room.
* Anything the server does with what it is sent. That is the
  [server's policy](https://github.com/olivierouellet/Splouch/blob/master/SECURITY.md).
* Jailbroken devices, and builds modified after signing.

---

## Hardening your install

There is little to configure — which is the point — but:

1. **Use `https://` for anything not on the local network.** The app defaults to it for a
   typed hostname; don't talk it out of that.
2. **Only add servers you were given by the meet's organizer.** A server you add sees the
   meets you open on it.
3. **Keep the app current**, and on the same generation as the server you follow most.
4. **Delete the app to clear everything.** There is no separate reset: the address, the
   preferences, the `vid` and the cached strings all live in the app container.
