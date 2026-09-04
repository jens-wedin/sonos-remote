# Research: controlling Sonos from a macOS menu bar app

Date: 2026-09-04. Written before any design decision. Facts marked **verified** were tested hands-on on Jens's own network; the rest come from web research with sources linked.

## Summary

- **The whole thing works locally, with no Sonos account, no cloud, no OAuth.** Every S2 player exposes an undocumented local version of Sonos's own Control API on HTTPS port 1443: REST for commands and a websocket for push events. It uses the same JSON shapes as the public cloud docs, so documentation effectively exists. **Verified** on this system: groups, playback state, now-playing metadata with album art, group volume, favorites, and live event subscriptions.
- **The older UPnP/SOAP API on port 1400 also works** and covers things the 1443 API lacks (queue editing, line-in, arbitrary stream URIs, EQ). Since mid-2025 Sonos labels it "unsupported" and gives users an off switch, so it is best kept as a fallback, not the foundation.
- **The official cloud Control API is the wrong shape** for a menu bar app: developer-account approval reportedly takes ~2 months, every command round-trips through Sonos's cloud, and events require a public HTTPS callback URL.
- **Recommended stack: native SwiftUI with a thin AppKit layer.** Media keys, Control Center now-playing, VoiceOver polish, and self-signed websocket trust are all native-only or painful in a webview. Tauri would only make sense for Windows/Linux, which is not a goal.
- **No paid Apple Developer account is needed** to build and run the app yourself. Developer ID plus notarization ($99/yr) is only needed to hand it to other people.

## Jens's system (verified 2026-09-03)

| Room | Model | IP | Notes |
|---|---|---|---|
| Stereo | Sonos Amp (S16) | 192.168.1.105 | Has a bonded rear satellite; was playing Spotify via Spotify Connect |
| Sovrum | (not probed) | 192.168.1.28 | |
| Flyttbar | (not probed) | 192.168.1.216 | |
| Elsas Sovrum | (not probed) | 192.168.1.250 | |

S2 system, firmware 96.0/96.1, local API version 1.53.1. One favorite (P3, Sveriges Radio).

## 1. Discovery

- **Bonjour `_sonos._tcp` works from macOS (verified).** `dns-sd -B _sonos._tcp local.` lists all four players. The TXT record carries the player UUID, household ID, the UPnP description URL on port 1400, `sslport=1443`, `wss=/websocket/api`, `info=/api/v1/players/{id}/info`, and `variant=2` for S2.
- **Raw SSDP multicast failed (verified)** from a non-entitled process with "No route to host". This is macOS 15's Local Network privacy. Prefer Bonjour via `NWBrowser`, which works inside the App Sandbox. A GUI app must ship `NSLocalNetworkUsageDescription` and `NSBonjourServices` (`_sonos._tcp`) in Info.plist or discovery fails silently. The permission state cannot be reset through a supported path ([Apple forum 760964](https://developer.apple.com/forums/thread/760964), [814226](https://developer.apple.com/forums/thread/814226)).

## 2. Local Control API on HTTPS 1443 (primary candidate)

**Verified on this system:**

- Header `X-Sonos-Api-Key: 123e4567-e89b-12d3-a456-426655440000` is required. Without it the player returns HTTP 400. The key is the RFC 4122 example UUID and has been used unchanged by community clients since April 2023.
- The certificate is self-signed, so the client must override trust, ideally only for private IPv4 hosts.
- REST endpoints returning 200: `/api/v1/households/local/groups`, `/api/v1/groups/{gid}/playback`, `/api/v1/groups/{gid}/playbackMetadata` (track, artist, album, image URL, container/service), `/api/v1/groups/{gid}/groupVolume`, `/api/v1/households/local/favorites`, `/api/v1/players/{pid}/info`.
- Websocket `wss://{ip}:1443/websocket/api` with subprotocol `v1.api.smartspeaker.audio` and the same API key header. Messages are JSON arrays `[header, body]`. Sending `[{"namespace":"playback:1","command":"subscribe","groupId":gid},{}]` returns `success:true` and the player immediately pushes current state. Verified for `playback:1`, `groupVolume:1`, `playbackMetadata:1`, and `groups:1` (with `householdId:"local"`). Event headers carry `type` of `playbackStatus`, `groupVolume`, `metadataStatus`, or `groups`.

**From research:**

- Sonos's official position: "The Control API on the LAN is not available for wide release" ([connected-home-architecture](https://docs.sonos.com/docs/connected-home-architecture)). No docs exist even for registered developers.
- The best open reference implementation is the SmartThings Edge driver ([source](https://github.com/SmartThingsCommunity/SmartThingsEdgeDrivers/tree/main/drivers/SmartThings/sonos/src)): one websocket per player, exponential-backoff reconnect capped at 60 s, group-scoped namespaces subscribed on the coordinator only, re-subscribe when a `groups` event changes coordinators. REST responses are `Connection: Close`, so use one-shot requests.
- Do not send an `Origin` header on websocket connections ([Sonos sample app page](https://developer.sonos.com/tools/sample-apps/javascript-sample-app/)).
- Documentation for shapes and commands: `docs.sonos.com/reference/*` ([playback](https://docs.sonos.com/reference/playback.md), [playbackMetadata](https://docs.sonos.com/reference/playbackmetadata-getmetadatastatus-groupid.md), [groupVolume](https://docs.sonos.com/reference/groupvolume-setvolume-groupid.md), [playerVolume](https://docs.sonos.com/reference/playervolume-setvolume-playerid.md), [favorites](https://docs.sonos.com/reference/favorites-loadfavorite-groupid.md), [groups](https://docs.sonos.com/reference/groups.md), [playlists](https://docs.sonos.com/reference/playlists-loadplaylist-groupid.md), [audioClip](https://docs.sonos.com/reference/audioclip.md)). Index at [llms.txt](https://docs.sonos.com/llms.txt).
- Other community clients using the same key: [jjlawren/sonos-websocket](https://github.com/jjlawren/sonos-websocket) (Python, used by Home Assistant), [node-sonos-ts](https://github.com/svrooij/node-sonos-ts), [SonoGlass MuseClient.swift](https://github.com/plantbob0101/SonoGlass) (Swift, one-shot).

**Risks:**

- Sonos added an "Authentication" switch in the app in July 2025. If a user turns it on, players with a newer API version return 401 `ERROR_NOT_AUTHORIZED` to the placeholder key. Detect it and show guidance.
- The placeholder key could be revoked by a firmware update. No report of that happening between 2022 and firmware 96.x. Keeping a UPnP fallback for transport and volume mitigates it.

## 3. UPnP/SOAP on HTTP 1400 (fallback)

- **Verified:** `device_description.xml`, `ZoneGroupTopology.GetZoneGroupState`, `AVTransport.GetTransportInfo` all respond.
- Extra capability over 1443: queue editing, `SetAVTransportURI` for arbitrary streams, line-in and TV sources, `ContentDirectory.Browse` for favorites and playlists, EQ, alarms. Reference docs at [sonos.svrooij.io](https://sonos.svrooij.io/sonos-communication).
- Events use GENA, which requires the app to run its own HTTP listener for NOTIFY callbacks. A sandboxed app would need the network server entitlement.
- Since player firmware 85.0 (July 2025) the Sonos app calls this "the unsupported UPnP protocol" and offers an off switch, default on ([release note](https://en.community.sonos.com/product-updates/a-new-player-update-is-live-6930092), [support article](https://support.sonos.com/en-us/article/adjust-connection-security-settings)).

## 4. Official cloud Control API (not recommended)

- OAuth 2.0, single scope, base URL `https://api.ws.sonos.com/control/api/v1/` ([docs](https://docs.sonos.com/docs/control)).
- Registration is company-oriented and a 2025 thread reports ~2 months waiting for approval. Developer support reportedly unresponsive.
- Rate limits: 1,000 requests/min per integration. Events only via a public HTTPS callback with 3-day subscription expiry. No websocket.
- Useful only as documentation for the local API.

## 5. Libraries

**Swift:** no maintained, permissively licensed package covers the 1443 API. Expect to write roughly 300 lines over URLSession and URLSessionWebSocketTask, porting the SmartThings logic.

| Library | API | Status |
|---|---|---|
| [Choragus](https://github.com/scottwaters/Choragus) (internal SonosKit) | UPnP + GENA, SSDP + Bonjour, SMAPI | 208 stars, pushed 2026-08, macOS 14+. **PolyForm Noncommercial license**, do not copy code |
| [SonoGlass](https://github.com/plantbob0101/SonoGlass) (SonosKit) | UPnP + GENA + 1443 websocket | 1 star, Aug 2026, macOS 26+, MIT. Worth reading for the trust-override pattern |
| [SwiftSSDP](https://github.com/happycodelucky/SwiftSSDP) | SSDP only | 41 stars, 2026-05, MIT |
| [sonos-swift-sdk](https://github.com/JimmyJammed/sonos-swift-sdk) | Cloud API | Stale (2023) |
| RxSonosLib, nathanborror/SonosKit | UPnP | Dead (2018, 2019) |

**Reference implementations to read:** SmartThings driver (Lua), [SoCo](https://github.com/SoCo/SoCo) (Python, 0.31.2 from 2026-07), [node-sonos-ts](https://github.com/svrooij/node-sonos-ts) (TypeScript, 2026-07).

**Rust (only relevant if Tauri):** [sonor](https://github.com/jakobhellermann/sonor), [sonos-api](https://lib.rs/crates/sonos-api), [wez-sonos](https://github.com/wez/wez-sonos). All UPnP, none cover 1443.

## 6. Existing macOS menu bar Sonos apps

- **Menu Bar Controller for Sonos** ([site](https://mbc-for-sonos.app/), [App Store](https://apps.apple.com/us/app/menu-bar-controller-for-sonos/id6749351423?mt=12)): the incumbent. Free with $12.99 lifetime unlock, macOS 13+, v7.2.2 Aug 2026. Popover with now-playing, transport, volume, room grouping, plus a separate library window, queue editor, Scenes, widgets, Control Center integration, media keys, Shortcuts, AppleScript, VoiceOver, Liquid Glass. Complaints: incomplete search, trial/IAP confusion. Lite version requires a Sonos login and "pauses music everywhere".
- **Clic for Sonos** ([App Store](https://apps.apple.com/app/apple-store/id6451395577)): 4.4 stars, macOS 14+, IAP. Complaint: discovery flakiness.
- **Open source:** [nfarina/sonos-control](https://github.com/nfarina/sonos-control) (MIT, 2026, UPnP, 10 s polling, sandbox disabled for SSDP), [SonoMac](https://github.com/inakizamores/SonoMac) (MIT, Aug 2026, UPnP), Choragus (noncommercial), SonoGlass.
- Market context: Sonos's own desktop app is Intel-only and users are pushed to play.sonos.com, which has no menu bar presence or media keys. That is the gap these apps fill.

## 7. macOS stack findings

**MenuBarExtra (SwiftUI, macOS 13+).** `.menu` style is a real NSMenu but only allows menu items. `.window` style hosts a SwiftUI view in a borderless window, not an NSPopover, and has documented gaps: no programmatic show/dismiss, no fade-out, no right-click handling, clunky resize. Workarounds:

- [MenuBarExtraAccess](https://github.com/orchetect/MenuBarExtraAccess) (219 stars, v1.3.1 Aug 2026): adds an `isPresented` binding and window introspection. Cheapest fix.
- [FluidMenuBarExtra](https://github.com/lfroms/fluid-menu-bar-extra) (82 stars, Nov 2025): NSStatusItem + NSPanel replacement with animated resize and fade-out.
- Roll your own NSStatusItem + NSPanel hosting an NSHostingView, which is what [Ice](https://github.com/jordanbaird/Ice) (29.5k stars), [Stats](https://github.com/exelban/stats), and [Tuneful](https://github.com/martinfekete10/Tuneful) do.

**Settings windows** from a Dock-less app remain fiddly on macOS 26: `openSettings` needs activation-policy juggling ([steipete.me](https://steipete.me/posts/2025/showing-settings-from-macos-menu-bar-items)).

**macOS 26 Tahoe:** Liquid Glass applies automatically when built with Xcode 26. The menu bar is transparent, so the status icon must be a template SF Symbol and tested over busy wallpapers. New WidgetKit `ControlWidget` allows a third-party Control Center control (play/pause) on Mac. Pragmatic minimum target: macOS 14.

**Plumbing:**

- Hide Dock icon: `LSUIElement = YES`. Launch at login: `SMAppService.mainApp.register()`.
- Global hotkeys: [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) (2.7k stars, v3.0.1 June 2026) with a SwiftUI recorder view.
- **Media keys and Control Center now-playing:** a third-party app that plays no audio can own F7/F8/F9 and appear in Control Center. Register handlers on `MPRemoteCommandCenter.shared()` and set `MPNowPlayingInfoCenter.default().playbackState` and `nowPlayingInfo` explicitly, since macOS has no audio session to infer from ([Apple forum 685333](https://developer.apple.com/forums/thread/685333)). Whichever app last reported `.playing` gets the keys.
- **Self-signed TLS with URLSession:** implement the server-trust challenge on the session delegate, check the host is a known speaker IP on a private range, then accept with `URLCredential(trust:)`. The same delegate covers `URLSessionWebSocketTask`. ATS does not apply to IP-address hosts; add `NSAllowsLocalNetworking` anyway. Websocket tasks need manual ping keepalive and re-arming `receive()` per message.

**Tauri v2:** tray icon and [tauri-nspanel](https://github.com/ahkohd/tauri-nspanel) exist and the result can look good, but WKWebView cannot accept a self-signed wss:// ([tauri #7651](https://github.com/tauri-apps/tauri/issues/7651)), so all Sonos I/O would live in Rust, media keys would need hand-written objc2 bindings, and native accessibility on sliders and pickers must be rebuilt in ARIA. Only worth it for cross-platform.

**Electron:** [menubar](https://github.com/max-mapper/menubar) makes the shell trivial, but ships Chromium for a 320×420 popover. Not worth it.

**Distribution:** a locally built app signed with a free Personal Team never gets the quarantine attribute, so Gatekeeper never intervenes ([Eclectic Light](https://eclecticlight.co/2024/10/01/living-without-notarization/)). App Sandbox is optional outside the App Store. If enabled, `com.apple.security.network.client` covers HTTP, websocket, and Bonjour browsing; `network.server` is needed only for UPnP GENA callbacks.

## 8. UI patterns worth studying

Typical layout at roughly 320 to 360 pt wide: room or group picker in the header, hero album art with title, artist, and source, a transport row, group volume slider with per-speaker disclosure, favorites, and a footer with settings and quit. Sliders need `accessibilityValue` and arrow-key steps.

Repos: [Tuneful](https://github.com/martinfekete10/Tuneful) (SwiftUI now-playing popover, closest match), [Ice](https://github.com/jordanbaird/Ice) (NSStatusItem + NSPanel hosting SwiftUI), [SwiftBar](https://github.com/swiftbar/SwiftBar), [FontSwitch](https://github.com/swiftlyjp/FontSwitch) (tiny MenuBarExtra + AppKit escape-hatch template).
