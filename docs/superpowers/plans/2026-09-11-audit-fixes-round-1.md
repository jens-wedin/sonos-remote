# Audit Fixes Round 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the top findings of the 2026-09-11 accessibility, performance and security audits in priority order, measuring a fixed set of numbers before and after every task so the improvement is visible.

**Architecture:** A small Python metrics script plus two probe tests in the SonosKit package produce a JSON snapshot of about 25 static and dynamic numbers (focusable controls, announcement sites, snapshot yields per event burst, live subscriptions while the panel is closed, traps on network data, and so on). Task 0 records the baseline; every later task re-runs the script and appends a row to a history file; Task 9 writes the before/after report. The fixes themselves touch three layers: the SonosKit trust boundary and subscription plan, the app's `AppState` observation model, and the SwiftUI views' accessibility.

**Tech Stack:** Swift 6 strict concurrency, SwiftUI (macOS 26), Swift Testing, CryptoKit and Security for key pinning, Python 3 (standard library only) for the metrics script.

**Spec:** `docs/audits/2026-09-11-accessibility.md`, `docs/audits/2026-09-11-performance.md`, `docs/audits/2026-09-11-security.md` (the finding ids below, C1/S1/H-1/H1 etc., refer to those files). The consolidated summary and priority order is the audit page published from this session.

## Global Constraints

- Swift language mode 6 with strict concurrency in every target; builds warning-free from our own files. Report the unfiltered warning check `xcodebuild … build 2>&1 | grep -E "warning:" | grep -v "DerivedData\|SourcePackages" || echo "no warnings"`.
- Every `swift` command runs from `Packages/SonosKit`; every `xcodegen`/`xcodebuild` command from the repo root; all with `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`. Never `sudo xcode-select`. Run `xcodegen generate` after adding or deleting Swift files. Never commit `SonosRemote.xcodeproj`, `.build/`, `.superpowers/`.
- Test commands: package `swift test` (79 tests before this plan); app `xcodebuild test -project SonosRemote.xcodeproj -scheme SonosRemote -destination 'platform=macOS' -derivedDataPath .build/xcode 2>&1 | grep -E "error:|Test run with|TEST (SUCCEEDED|FAILED)" | tail -3` (41 tests before this plan). Build: `xcodebuild -project SonosRemote.xcodeproj -scheme SonosRemote -configuration Debug -derivedDataPath .build/xcode build 2>&1 | grep -E "error:|warning: .*SonosRemote/|BUILD" | head`.
- Metrics: every task ends with `python3 scripts/audit-metrics.py --label task-N` (N = the task number) from the repo root, which appends one row to `docs/audits/metrics/history.md` and writes `docs/audits/metrics/task-N.json`; both files are committed with the task. Task 0 runs it with `--label before`, Task 9 with `--label after`. The `--label` value must be exactly as stated so the history reads in order.
- Existing behaviour stays: the panel layout and copy from the redesign spec, the volume slider's command gate (`isProgrammaticUpdate`, `setLocalProgrammatically`, `commit`, `scheduleFlush` unchanged), all existing tests green after every task.
- Views refer to SonosKit's `Group` as `SonosGroup` (typealias in `SonosRemote/Views/SonosGroupAlias.swift`) in files that import SwiftUI.
- Quit the running app before rebuilding (`pkill -x SonosRemote`) and relaunch after (`open .build/xcode/Build/Products/Debug/SonosRemote.app`).
- Do not exercise the owner's speakers from scripts (no `sonosctl` commands that change state, no automated clicking); visual checks are for the owner.
- Conventional commits; commit at the end of every task.

---

## File Structure

```
scripts/audit-metrics.py                         Task 0: static greps + probe-test parsing → JSON + markdown history
docs/audits/metrics/README.md                    Task 0: what each metric means and its direction
docs/audits/metrics/history.md                   Task 0 creates; every task appends one row
docs/audits/metrics/<label>.json                 one file per run
Packages/SonosKit/Tests/SonosKitTests/MetricsProbeTests.swift   Task 0: prints METRIC lines (yields per burst, subscriptions while closed)

SonosRemote/Views/Shell/PanelShellView.swift     Task 1 (default focus), Task 8 (reduce motion)
SonosRemote/Views/Shell/HeaderView.swift         Task 1 (focusable, 28 pt back)
SonosRemote/Views/Components/IconButton.swift    Task 1
SonosRemote/Views/Components/SearchField.swift   Task 1 (focusable clear, 28 pt), Task 7 (border)
SonosRemote/Views/Main/TransportView.swift       Task 1 (focusable, shortcuts, non-colour on cue, 28 pt), Task 7 (dim)
SonosRemote/Views/Main/MainScreen.swift          Task 1 (passes the focus binding)
SonosRemote/Views/Main/RoomsListView.swift       Task 1 (focusable link), Task 5 (list semantics kept simple), Task 7 (dim)
SonosRemote/Views/Main/RoomRowView.swift         Task 5 (label/value/action)
SonosRemote/Views/Main/ProgressBarView.swift     Task 5 (updatesFrequently)
SonosRemote/Views/VolumeSliderView.swift         Task 1 (28 pt mute, focusable)
SonosRemote/Views/Shell/FooterView.swift         Task 1
SonosRemote/Views/Favorites/FavoriteRow.swift    Task 1
SonosRemote/Views/Sound/PresetChips.swift        Task 1, Task 7 (lit chip contrast)
SonosRemote/Views/Sound/SoundScreen.swift        Task 1 (Reset focusable), Task 5 (Reading EQ updatesFrequently)
SonosRemote/Views/Sound/ToneSlider.swift         Task 8 (reset action)
SonosRemote/Views/Settings/SettingsScreen.swift  Task 1 (focusable), Task 8 (SMAppService onAppear)
SonosRemote/Views/Group/GroupScreen.swift        Task 5 (toggle value/hint), Task 8 (Text(verbatim:))
SonosRemote/Views/Components/ErrorLine.swift     Task 5 (updatesFrequently), Task 7 (red)
SonosRemote/Views/StatusBannerView.swift         Task 5 (updatesFrequently)
SonosRemote/Views/Components/Palette.swift       Task 7: supporting/faint text tokens, borders
SonosRemote/Views/Components/Card.swift          Task 7 (border)

Packages/SonosKit/Sources/SonosKit/Transport/TrustPolicy.swift        Task 2: isLocalSpeakerAddress, pinned TrustStore, TrustPinStore
Packages/SonosKit/Sources/SonosKit/Transport/URLSessionTransport.swift Task 2: delegate evaluates the pin
Packages/SonosKit/Sources/SonosKit/Discovery/BonjourDiscovery.swift    Task 2: validated TXT location
Packages/SonosKit/Sources/SonosKit/Wire/WireTypes.swift                Task 2: validated websocket host
Packages/SonosKit/Sources/SonosKit/Household/Household.swift           Task 2 (revoke on lost), Task 4 (buffer + no-op guard), Task 6 (panel visibility)
Packages/SonosKit/Sources/SonosKit/Household/SubscriptionPlan.swift    Task 6
SonosRemote/App/UserDefaultsPinStore.swift        Task 2: persists pins across launches
Packages/SonosKit/Sources/SonosKit/LocalAPI/LocalAPIClient.swift       Task 3: throwing makeRequest
Packages/SonosKit/Sources/SonosKit/Socket/PlayerSocket.swift           Task 3 (failable init), Task 8 (ping interval)
Packages/SonosKit/Sources/SonosKit/UPnP/UPnPClient.swift               Task 3
Packages/SonosKit/Sources/SonosKit/Models/Models.swift                 Task 3: PlaybackProgress.maximumMillis
Packages/SonosKit/Sources/SonosKit/Wire/WireMapping.swift              Task 3 (clamp)
Packages/SonosKit/Sources/SonosKit/Socket/SocketFrame.swift            Task 3 (clamp)
SonosRemote/App/PlaybackDisplay.swift             Task 3 (overflow-safe)
SonosRemote/App/AppState.swift                    Task 4 (narrow properties), Task 5 (announcements), Task 6 (panel visibility), Task 8 (pruning)
project.yml                                       Task 8 (exact dependency versions)
docs/audits/2026-09-11-fix-round-1.md            Task 9: before/after report
```

**Metrics every task must move** (ids from `scripts/audit-metrics.py`; the script defines the exact greps):

| Task | Metric ids that must change | Direction |
|---|---|---|
| 1 | `a11y.unfocusable_custom_buttons` → 0, `a11y.small_targets` → 0, `a11y.colour_only_toggles` → 0 | lower |
| 2 | `sec.cert_pinning` → 1, `sec.address_validation` → 1, `sec.trust_revoke_on_lost` → 1 | higher |
| 3 | `sec.traps_on_network_data` → 0, `sec.overflow_safe_progress` → 1 | lower / higher |
| 4 | `perf.views_reading_snapshot` → 0, `perf.snapshot_yields_per_40_burst` → 1, `perf.sort_per_access` → 0 | lower |
| 5 | `a11y.announcement_sites` ≥ 2, `a11y.updates_frequently` ≥ 4, `a11y.actions` ≥ 1 | higher |
| 6 | `perf.subscriptions_per_coordinator_closed` → 2, `perf.player_volume_subscribed` → 0 | lower |
| 7 | `a11y.system_secondary_sites` → 0 | lower |
| 8 | `sec.interpolated_text_sites` → 0, `sec.deps_pinned` → 1, `a11y.reduce_motion` → 1, `perf.ping_interval_seconds` → 90, `perf.smappservice_in_initialiser` → 0 | mixed |

---

### Task 0: Metrics harness and baseline

**Files:**
- Create: `scripts/audit-metrics.py`
- Create: `docs/audits/metrics/README.md`
- Create: `Packages/SonosKit/Tests/SonosKitTests/MetricsProbeTests.swift`
- Create (by running the script): `docs/audits/metrics/before.json`, `docs/audits/metrics/history.md`

**Interfaces:**
- Consumes: `HouseholdTests.Harness` (`startAndDiscover(_:)`, `transport.sockets`, `household.snapshots()`), `FakeSocketConnection.push(_:)`, `SubscriptionPlan.make(groups:players:gatewayID:)`.
- Produces: `python3 scripts/audit-metrics.py --label <name> [--no-tests] [--compare before after]`; `METRIC <id>=<int>` lines printed by `MetricsProbeTests`.

- [ ] **Step 1: Write the probe tests**

`Packages/SonosKit/Tests/SonosKitTests/MetricsProbeTests.swift`:
```swift
import Foundation
import Synchronization
import Testing
@testable import SonosKit

/// Not behaviour tests: these print `METRIC id=value` lines that scripts/audit-metrics.py parses.
/// They never fail on the value; they only fail if the harness itself breaks.
@Suite struct MetricsProbeTests {
    /// How many snapshots the Household yields for 40 identical groupVolume events.
    /// Before the performance fixes every event yields (40 + the initial snapshot).
    @Test func snapshotYieldsPerBurst() async throws {
        let h = HouseholdTests.Harness()
        let first = try await h.startAndDiscover(DiscoveredPlayer(id: "RINCON_PROBE", address: "192.168.1.10", householdID: "hh"))
        let groupID = try #require(first.groups.first?.id)
        let socket = try #require(h.transport.sockets.first)

        let count = Mutex(0)
        let stream = await h.household.snapshots()
        let counter = Task {
            for await _ in stream { count.withLock { $0 += 1 } }
        }
        try await Task.sleep(for: .milliseconds(50))
        let frame = #"[{"namespace":"groupVolume:1","type":"groupVolume","groupId":"\#(groupID)"},{"volume":20,"muted":false,"fixed":false}]"#
        for _ in 0..<40 { socket.push(frame) }
        try await Task.sleep(for: .milliseconds(300))
        counter.cancel()
        let yields = count.withLock { $0 } - 1   // minus the initial snapshot every observer gets
        print("METRIC perf.snapshot_yields_per_40_burst=\(max(yields, 0))")
    }

    /// How many namespaces the coordinator's socket subscribes to when the panel is closed.
    @Test func subscriptionsWhileClosed() {
        let player = Player(id: "P1", name: "Kitchen", address: "192.168.1.10", hasSub: false)
        let group = Group(id: "G1", name: "Kitchen", coordinatorID: "P1", playerIDs: ["P1"], playbackState: .idle, volume: .silent, nowPlaying: nil)
        let plan = SubscriptionPlan.make(groups: [group], players: [player], gatewayID: "P1")
        let count = plan["P1"]?.count ?? 0
        let playerVolume = plan.values.contains { set in set.contains { $0.namespace == "playerVolume:1" } } ? 1 : 0
        print("METRIC perf.subscriptions_per_coordinator_closed=\(count)")
        print("METRIC perf.player_volume_subscribed=\(playerVolume)")
    }
}
```
(`Player.init` and `Group.init` signatures: check `Packages/SonosKit/Sources/SonosKit/Models/Models.swift`; if `Player` has extra parameters, pass their defaults. `HouseholdTests.Harness` is `struct Harness` nested in `HouseholdTests`; if it is `private`, make it `internal` in that file.)

- [ ] **Step 2: Run the probes**

```bash
cd Packages/SonosKit && swift test --filter MetricsProbeTests 2>&1 | grep -E "METRIC|error:|passed|failed" | tail -6
```
Expected: two `METRIC` lines (about `perf.snapshot_yields_per_40_burst=40`, `perf.subscriptions_per_coordinator_closed=6`, `perf.player_volume_subscribed=1`) and `2 tests … passed`. If the yield count is far below 40 because pushes raced the subscription, raise the first sleep to 200 ms.

- [ ] **Step 3: Write the metrics script**

`scripts/audit-metrics.py`:
```python
#!/usr/bin/env python3
"""Audit metrics: static greps over the sources plus two probe tests.

    python3 scripts/audit-metrics.py --label before          # run tests, write JSON, append history
    python3 scripts/audit-metrics.py --label task-3 --no-tests
    python3 scripts/audit-metrics.py --compare before after  # print a delta table

Every metric is (id, description, direction). direction is "lower" or "higher" = better.
"""
import argparse, json, os, re, subprocess, sys, datetime, pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
VIEWS = ROOT / "SonosRemote" / "Views"
APP = ROOT / "SonosRemote"
KIT = ROOT / "Packages" / "SonosKit" / "Sources" / "SonosKit"
OUT = ROOT / "docs" / "audits" / "metrics"

def swift_files(*dirs):
    for d in dirs:
        for p in sorted(pathlib.Path(d).rglob("*.swift")):
            yield p

def read(p):
    return p.read_text(encoding="utf-8")

def count(pattern, *dirs, flags=0):
    rx = re.compile(pattern, flags)
    return sum(len(rx.findall(read(p))) for p in swift_files(*dirs))

def files_with(pattern, *dirs):
    rx = re.compile(pattern)
    return sum(1 for p in swift_files(*dirs) if rx.search(read(p)))

def exists(pattern, *dirs):
    return 1 if files_with(pattern, *dirs) else 0

def unfocusable_custom_buttons():
    """Custom-styled Buttons/Links with no .focusable() within the next 4 lines."""
    n = 0
    rx = re.compile(r"\.buttonStyle\(\.(plain|borderless|link)\)")
    for p in swift_files(VIEWS):
        lines = read(p).splitlines()
        for i, line in enumerate(lines):
            if rx.search(line):
                window = "\n".join(lines[i:i + 5])
                if ".focusable(" not in window:
                    n += 1
    return n

def colour_only_toggles():
    """ToggleGlyph in TransportView signalling 'on' with foregroundStyle only."""
    p = VIEWS / "Main" / "TransportView.swift"
    if not p.exists():
        return 0
    body = read(p)
    if "ToggleGlyph" not in body:
        return 0
    return 0 if re.search(r"ToggleGlyph[\s\S]*?\.background\(", body) else 1

def small_targets():
    return count(r"\.frame\(width:\s*2[0-3],\s*height:\s*2[0-3]\)", VIEWS)

def ping_interval():
    m = re.search(r"pingInterval:\s*Duration\s*=\s*\.seconds\((\d+)\)", read(KIT / "Socket" / "PlayerSocket.swift"))
    return int(m.group(1)) if m else 0

def deps_pinned():
    y = read(ROOT / "project.yml")
    return 1 if "exactVersion:" in y and "from:" not in y.split("packages:")[1].split("targets:")[0] else 0

def interpolated_text_sites():
    """Text("…\(…)…") literals in views where the interpolation is metadata (title, name)."""
    return count(r'Text\("[^"\n]*\\\([^)]*\b(title|name|secondLine|line)\b[^)]*\)[^"\n]*"\)', VIEWS)

STATIC = [
    ("a11y.unfocusable_custom_buttons", "custom-styled buttons/links with no .focusable()", "lower", unfocusable_custom_buttons),
    ("a11y.focusable_sites", ".focusable() call sites in views", "higher", lambda: count(r"\.focusable\(", VIEWS)),
    ("a11y.small_targets", "icon buttons framed at 20–23 pt", "lower", small_targets),
    ("a11y.colour_only_toggles", "toggle glyphs whose on state is colour-only", "lower", colour_only_toggles),
    ("a11y.announcement_sites", "AccessibilityNotification call sites", "higher", lambda: count(r"AccessibilityNotification", APP)),
    ("a11y.updates_frequently", ".updatesFrequently trait sites", "higher", lambda: count(r"\.updatesFrequently", VIEWS)),
    ("a11y.actions", "accessibilityAction sites", "higher", lambda: count(r"\.accessibilityAction\(", VIEWS)),
    ("a11y.hints", "accessibilityHint sites", "higher", lambda: count(r"\.accessibilityHint\(", VIEWS)),
    ("a11y.system_secondary_sites", ".secondary/.tertiary text colour sites", "lower", lambda: count(r"foregroundStyle\(\.(secondary|tertiary)\)", VIEWS)),
    ("a11y.fixed_font_sites", ".system(size:) without relativeTo", "lower", lambda: count(r"\.system\(size:\s*[\d.]+(?:,\s*weight:[^)]*)?\)", VIEWS)),
    ("a11y.reduce_motion", "accessibilityReduceMotion honoured", "higher", lambda: exists(r"accessibilityReduceMotion", VIEWS)),
    ("perf.views_reading_snapshot", "view files reading state.snapshot", "lower", lambda: files_with(r"state\.snapshot", VIEWS)),
    ("perf.sort_per_access", "orderedGroups is a computed (re-sorting) property", "lower", lambda: exists(r"var orderedGroups:\s*\[Group\]\s*\{", APP / "App")),
    ("perf.stream_buffered", "snapshot stream uses bufferingNewest", "higher", lambda: exists(r"bufferingNewest", KIT)),
    ("perf.noop_guard", "Household.apply skips unchanged snapshots", "higher", lambda: exists(r"guard next != snapshot", KIT)),
    ("perf.lazy_lists", "LazyVStack sites", "higher", lambda: count(r"LazyVStack", VIEWS)),
    ("perf.ping_interval_seconds", "websocket ping interval", "higher", ping_interval),
    ("perf.smappservice_in_initialiser", "SMAppService queried in a @State initialiser", "lower", lambda: count(r"@State[^\n]*=\s*SMAppService", VIEWS)),
    ("sec.traps_on_network_data", "preconditionFailure/fatalError/try! in SonosKit sources", "lower", lambda: count(r"preconditionFailure\(|fatalError\(|try!", KIT)),
    ("sec.cert_pinning", "TrustStore pins the leaf key hash", "higher", lambda: exists(r"keyHash", KIT / "Transport")),
    ("sec.address_validation", "isLocalSpeakerAddress applied in discovery", "higher", lambda: exists(r"isLocalSpeakerAddress", KIT / "Discovery")),
    ("sec.trust_revoke_on_lost", "trust revoked when a player is lost", "higher", lambda: exists(r"revoke\(host", KIT / "Household")),
    ("sec.overflow_safe_progress", "PlaybackProgress.maximumMillis clamp exists", "higher", lambda: exists(r"maximumMillis", KIT)),
    ("sec.public_privacy_logs", "privacy: .public log arguments", "lower", lambda: count(r"privacy:\s*\.public", KIT, APP)),
    ("sec.interpolated_text_sites", "Text literals interpolating metadata", "lower", interpolated_text_sites),
    ("sec.deps_pinned", "project.yml pins exact dependency versions", "higher", deps_pinned),
    ("code.swift_lines", "lines of Swift in app + package sources", "info", lambda: sum(len(read(p).splitlines()) for p in swift_files(APP, KIT))),
]

def run_tests():
    env = dict(os.environ, DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer")
    out = {}
    pkg = subprocess.run(["swift", "test"], cwd=ROOT / "Packages" / "SonosKit", env=env, capture_output=True, text=True)
    text = pkg.stdout + pkg.stderr
    for m in re.finditer(r"METRIC (\S+)=(\d+)", text):
        out[m.group(1)] = int(m.group(2))
    m = re.search(r"Test run with (\d+) tests", text)
    out["tests.package"] = int(m.group(1)) if m else -1
    subprocess.run(["xcodegen", "generate"], cwd=ROOT, env=env, capture_output=True)
    app = subprocess.run(["xcodebuild", "test", "-project", "SonosRemote.xcodeproj", "-scheme", "SonosRemote",
                          "-destination", "platform=macOS", "-derivedDataPath", ".build/xcode"],
                         cwd=ROOT, env=env, capture_output=True, text=True)
    text = app.stdout + app.stderr
    m = re.search(r"Test run with (\d+) tests", text)
    out["tests.app"] = int(m.group(1)) if m else -1
    out["build.warnings"] = len([l for l in text.splitlines() if "warning:" in l and "DerivedData" not in l and "SourcePackages" not in l])
    return out

DYNAMIC = [
    ("perf.snapshot_yields_per_40_burst", "snapshots yielded for 40 identical events", "lower"),
    ("perf.subscriptions_per_coordinator_closed", "namespaces subscribed on the coordinator while the panel is closed", "lower"),
    ("perf.player_volume_subscribed", "playerVolume:1 subscribed at all", "lower"),
    ("tests.package", "SonosKit tests", "higher"),
    ("tests.app", "app tests", "higher"),
    ("build.warnings", "warnings from our own files", "lower"),
]

def collect(run):
    values = {mid: fn() for mid, _, _, fn in STATIC}
    if run:
        values.update(run_tests())
    return values

def directions():
    d = {mid: direction for mid, _, direction, _ in STATIC}
    d.update({mid: direction for mid, _, direction in DYNAMIC})
    return d

def descriptions():
    d = {mid: desc for mid, desc, _, _ in STATIC}
    d.update({mid: desc for mid, desc, _ in DYNAMIC})
    return d

def sha():
    return subprocess.run(["git", "rev-parse", "--short", "HEAD"], cwd=ROOT, capture_output=True, text=True).stdout.strip()

def append_history(label, values):
    OUT.mkdir(parents=True, exist_ok=True)
    path = OUT / "history.md"
    keys = [k for k, *_ in STATIC] + [k for k, *_ in DYNAMIC]
    if not path.exists():
        path.write_text("# Metrics history\n\nOne row per run; `-` means the metric was not collected in that run (tests skipped).\n\n| label | commit | " + " | ".join(keys) + " |\n|" + "---|" * (len(keys) + 2) + "\n")
    row = "| " + label + " | " + sha() + " | " + " | ".join(str(values.get(k, "-")) for k in keys) + " |\n"
    with path.open("a") as f:
        f.write(row)

def compare(a, b):
    va = json.loads((OUT / f"{a}.json").read_text())["values"]
    vb = json.loads((OUT / f"{b}.json").read_text())["values"]
    desc, dirs = descriptions(), directions()
    print(f"| metric | {a} | {b} | change | better? |\n|---|---:|---:|---:|:--:|")
    for k in [k for k, *_ in STATIC] + [k for k, *_ in DYNAMIC]:
        x, y = va.get(k), vb.get(k)
        if x is None or y is None:
            print(f"| {desc[k]} | {x if x is not None else '-'} | {y if y is not None else '-'} | | |")
            continue
        delta = y - x
        better = "" if dirs[k] == "info" or delta == 0 else ("✅" if (delta < 0) == (dirs[k] == "lower") else "⚠️")
        print(f"| {desc[k]} | {x} | {y} | {delta:+d} | {better} |")

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--label")
    ap.add_argument("--no-tests", action="store_true")
    ap.add_argument("--compare", nargs=2, metavar=("BEFORE", "AFTER"))
    args = ap.parse_args()
    if args.compare:
        compare(*args.compare)
        return
    if not args.label:
        ap.error("--label is required unless --compare is used")
    values = collect(run=not args.no_tests)
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / f"{args.label}.json").write_text(json.dumps({
        "label": args.label, "commit": sha(), "date": datetime.date.today().isoformat(), "values": values,
    }, indent=2) + "\n")
    append_history(args.label, values)
    desc = descriptions()
    for k, v in values.items():
        print(f"{k:45} {v:>6}   {desc.get(k, '')}")

if __name__ == "__main__":
    main()
```

`docs/audits/metrics/README.md`:
```markdown
# Audit metrics

`scripts/audit-metrics.py` collects the numbers below from the sources (static greps) and from two probe tests in `MetricsProbeTests` (dynamic). Run it with `--label <name>` to write `<name>.json` here and append a row to `history.md`; `--compare before after` prints a delta table. Directions: "lower" or "higher" is better; "info" is context only.

The metric ids and what they measure are defined in the script's `STATIC` and `DYNAMIC` tables; keep this file and the script in step when adding one. The baseline is `before.json` (main at the v0.2.0 docs commit); each fix task appends `task-N`; the closing run is `after.json`.
```

- [ ] **Step 4: Record the baseline**

```bash
chmod +x scripts/audit-metrics.py
python3 scripts/audit-metrics.py --label before
sed -n 1,8p docs/audits/metrics/history.md
```
Expected: a printed table with every metric; `docs/audits/metrics/before.json` and `history.md` created; `tests.package` = 81 (79 + the two probes), `tests.app` = 41, `build.warnings` = 0, `a11y.unfocusable_custom_buttons` well above 0, `sec.traps_on_network_data` = 3, `perf.views_reading_snapshot` ≥ 5.

- [ ] **Step 5: Commit**

```bash
git add scripts/audit-metrics.py docs/audits/metrics Packages/SonosKit/Tests/SonosKitTests/MetricsProbeTests.swift
git commit -m "chore(metrics): audit metrics script, probe tests and baseline"
```

---

### Task 1: Keyboard reach, target sizes and a non-colour "on" cue (a11y C1, S4, S5)

**Files:**
- Modify: `SonosRemote/Views/Components/IconButton.swift`, `SonosRemote/Views/Shell/HeaderView.swift`, `SonosRemote/Views/Shell/FooterView.swift`, `SonosRemote/Views/Shell/PanelShellView.swift`, `SonosRemote/Views/Main/MainScreen.swift`, `SonosRemote/Views/Main/TransportView.swift`, `SonosRemote/Views/Main/RoomsListView.swift`, `SonosRemote/Views/VolumeSliderView.swift`, `SonosRemote/Views/Favorites/FavoriteRow.swift`, `SonosRemote/Views/Sound/PresetChips.swift`, `SonosRemote/Views/Sound/SoundScreen.swift`, `SonosRemote/Views/Settings/SettingsScreen.swift`, `SonosRemote/Views/Components/SearchField.swift`
- Create: `SonosRemote/App/PanelFocus.swift`

**Interfaces:**
- Produces: `enum PanelFocus: Hashable { case playPause }`; `MainScreen(focus:)` and `TransportView(group:focus:)` take `FocusState<PanelFocus?>.Binding`.

- [ ] **Step 1: The focus target and default focus**

`SonosRemote/App/PanelFocus.swift`:
```swift
import Foundation

/// Panel-level keyboard focus targets. The play/pause button is where the first keypress lands.
enum PanelFocus: Hashable {
    case playPause
}
```

In `SonosRemote/Views/Shell/PanelShellView.swift` add `@FocusState private var focus: PanelFocus?`, pass it to the main screen (`case .main: MainScreen(focus: $focus)…`), and add `.defaultFocus($focus, .playPause)` on the outer `VStack` (after `.frame(width: 420)`). In `MainScreen.swift` add `let focus: FocusState<PanelFocus?>.Binding` and pass it on: `TransportView(group: state.selectedGroup, focus: focus)`.

- [ ] **Step 2: Every custom control focusable, 28 pt targets, shortcuts**

Apply `.focusable()` directly after the `.buttonStyle(.plain)` / `.buttonStyle(.borderless)` / `.buttonStyle(.link)` modifier of every custom control (the metric counts a button style with no `.focusable()` within four lines):
- `IconButton.swift` (the header icons)
- `HeaderView.swift` Back button; also change its frame to `.frame(width: 28, height: 28)` and add `.contentShape(Rectangle())`
- `FooterView.swift` Quit
- `TransportView.swift`: previous, play/pause, next, and `ToggleGlyph`'s button; give previous and next `.frame(width: 28, height: 28).contentShape(Rectangle())` on their label; add `.focused(focus, equals: .playPause)` to the play/pause button and these shortcuts: play/pause `.keyboardShortcut(.space, modifiers: [])`, previous `.keyboardShortcut(.leftArrow, modifiers: .command)`, next `.keyboardShortcut(.rightArrow, modifiers: .command)`
- `RoomsListView.swift` Group link
- `VolumeSliderView.swift` `muteButton`: frame `28 × 28` (both styles) and `.focusable()`
- `FavoriteRow.swift` row button
- `PresetChips.swift` preset buttons
- `SoundScreen.swift` Reset (`.buttonStyle(.link)`) 
- `SettingsScreen.swift` refresh button and the Releases `Link`
- `SearchField.swift` clear button: `.frame(width: 28, height: 28).contentShape(Rectangle())` on its label and `.focusable()`

`TransportView.swift` `ToggleGlyph` — replace the label's foreground-only "on" cue with a background as well:
```swift
        Button { action(!isOn) } label: {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(!enabled ? Color.secondary.opacity(0.4) : isOn ? Color.accentColor : Color.secondary)
                .frame(width: 28, height: 28)
                .background(isOn ? AnyShapeStyle(Color.accentColor.opacity(0.18)) : AnyShapeStyle(.clear), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .focusable()
        .disabled(!enabled)
        .accessibilityLabel(label)
        .accessibilityValue(isOn ? "on" : "off")
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
```

- [ ] **Step 3: Build, test, metrics**

```bash
xcodegen generate >/dev/null && xcodebuild test -project SonosRemote.xcodeproj -scheme SonosRemote -destination 'platform=macOS' -derivedDataPath .build/xcode 2>&1 | grep -E "error:|Test run with|TEST (SUCCEEDED|FAILED)" | tail -3
pkill -x SonosRemote; open .build/xcode/Build/Products/Debug/SonosRemote.app
python3 scripts/audit-metrics.py --label task-1 --no-tests | grep -E "a11y\.(unfocusable|small|colour|focusable)"
```
Expected: 41 app tests pass; `a11y.unfocusable_custom_buttons 0`, `a11y.small_targets 0`, `a11y.colour_only_toggles 0`. Owner check: with System Settings → Keyboard → Keyboard navigation OFF, open the panel, press Space (play/pause toggles), Tab through header icons, transport, volume, rooms; Cmd-← / Cmd-→ skip tracks.

- [ ] **Step 4: Commit**

```bash
git add -A SonosRemote docs/audits/metrics
git commit -m "fix(a11y): make every control keyboard-focusable, 28 pt targets, non-colour on cue"
```

---

### Task 2: Pin speaker certificates and validate discovered addresses (security H-1, H-2, L-1, L-2)

**Files:**
- Modify: `Packages/SonosKit/Sources/SonosKit/Transport/TrustPolicy.swift`, `Packages/SonosKit/Sources/SonosKit/Transport/URLSessionTransport.swift`, `Packages/SonosKit/Sources/SonosKit/Discovery/BonjourDiscovery.swift`, `Packages/SonosKit/Sources/SonosKit/Wire/WireTypes.swift`, `Packages/SonosKit/Sources/SonosKit/Household/Household.swift`
- Create: `SonosRemote/App/UserDefaultsPinStore.swift`
- Modify: `SonosRemote/App/AppState.swift` (`live()` and `retryDiscovery()` pass the pin store)
- Test: `Packages/SonosKit/Tests/SonosKitTests/TrustPolicyTests.swift` (new), `Packages/SonosKit/Tests/SonosKitTests/DiscoveryTests.swift` (add cases)

**Interfaces:**
- Consumes: `TrustStore.allow(host:)` and `shouldTrust(host:)` call sites in `Household` (lines ~168, 294, 404, 436) and the delegate.
- Produces: `TrustPolicy.isLocalSpeakerAddress(_:) -> Bool`, `TrustPolicy.speakerHost(from urlString: String, schemes: Set<String>) -> String?`, `protocol TrustPinStore: Sendable { func load() -> [String: Data]; func save(_ pins: [String: Data]) }`, `TrustStore(pinStore:)`, `TrustStore.decision(host:port:keyHash:) -> TrustDecision`, `TrustStore.revoke(host:)`, `enum TrustDecision { case accept, reject }`, `TrustPolicy.leafKeyHash(of: SecTrust) -> Data?`, `UserDefaultsPinStore`.

- [ ] **Step 1: Write the failing tests**

`Packages/SonosKit/Tests/SonosKitTests/TrustPolicyTests.swift`:
```swift
import Foundation
import Testing
@testable import SonosKit

@Suite struct TrustPolicyTests {
    let keyA = Data(repeating: 0xA1, count: 32)
    let keyB = Data(repeating: 0xB2, count: 32)

    @Test func localSpeakerAddresses() {
        #expect(TrustPolicy.isLocalSpeakerAddress("192.168.1.10"))
        #expect(TrustPolicy.isLocalSpeakerAddress("10.0.0.7"))
        #expect(TrustPolicy.isLocalSpeakerAddress("172.16.4.4"))
        #expect(TrustPolicy.isLocalSpeakerAddress("169.254.10.1"))
        #expect(TrustPolicy.isLocalSpeakerAddress("fe80::1"))
        #expect(!TrustPolicy.isLocalSpeakerAddress("8.8.8.8"))
        #expect(!TrustPolicy.isLocalSpeakerAddress("sonos.example.com"))
        #expect(!TrustPolicy.isLocalSpeakerAddress("172.32.0.1"))
        #expect(!TrustPolicy.isLocalSpeakerAddress(""))
    }

    @Test func speakerHostRequiresAllowedSchemeAndLocalLiteral() {
        #expect(TrustPolicy.speakerHost(from: "http://192.168.1.10:1400/xml/device_description.xml", schemes: ["http", "https"]) == "192.168.1.10")
        #expect(TrustPolicy.speakerHost(from: "wss://192.168.1.10:1443/websocket/api", schemes: ["wss"]) == "192.168.1.10")
        #expect(TrustPolicy.speakerHost(from: "https://attacker.example/x", schemes: ["http", "https"]) == nil)
        #expect(TrustPolicy.speakerHost(from: "http://93.184.216.34/x", schemes: ["http", "https"]) == nil)
        #expect(TrustPolicy.speakerHost(from: "file:///etc/hosts", schemes: ["http", "https"]) == nil)
        #expect(TrustPolicy.speakerHost(from: "ws://192.168.1.10/", schemes: ["wss"]) == nil)
    }

    @Test func firstContactPinsAndLaterContactsMustMatch() {
        let store = TrustStore()
        #expect(store.decision(host: "192.168.1.10", port: 1443, keyHash: keyA) == .reject, "not allowed yet")
        store.allow(host: "192.168.1.10")
        #expect(store.decision(host: "192.168.1.10", port: 1443, keyHash: keyA) == .accept, "first contact records the pin")
        #expect(store.decision(host: "192.168.1.10", port: 1443, keyHash: keyA) == .accept)
        #expect(store.decision(host: "192.168.1.10", port: 1443, keyHash: keyB) == .reject, "a different key is an impostor")
        #expect(store.decision(host: "192.168.1.10", port: 8443, keyHash: keyA) == .reject, "only the speaker port")
        #expect(store.decision(host: "8.8.8.8", port: 1443, keyHash: keyA) == .reject)
    }

    @Test func revokeForgetsHostAndPin() {
        let store = TrustStore()
        store.allow(host: "192.168.1.10")
        _ = store.decision(host: "192.168.1.10", port: 1443, keyHash: keyA)
        store.revoke(host: "192.168.1.10")
        #expect(store.decision(host: "192.168.1.10", port: 1443, keyHash: keyB) == .reject)
        store.allow(host: "192.168.1.10")
        #expect(store.decision(host: "192.168.1.10", port: 1443, keyHash: keyB) == .accept, "after revoke the next contact pins afresh")
    }

    @Test func pinsPersistThroughTheStore() {
        final class MemoryPins: TrustPinStore, @unchecked Sendable {
            var saved: [String: Data] = [:]
            func load() -> [String: Data] { saved }
            func save(_ pins: [String: Data]) { saved = pins }
        }
        let pins = MemoryPins()
        let first = TrustStore(pinStore: pins)
        first.allow(host: "192.168.1.10")
        _ = first.decision(host: "192.168.1.10", port: 1443, keyHash: keyA)
        #expect(pins.saved["192.168.1.10"] == keyA)
        let second = TrustStore(pinStore: pins)
        second.allow(host: "192.168.1.10")
        #expect(second.decision(host: "192.168.1.10", port: 1443, keyHash: keyB) == .reject, "the persisted pin survives a relaunch")
        #expect(second.decision(host: "192.168.1.10", port: 1443, keyHash: keyA) == .accept)
    }
}
```

Add to `DiscoveryTests.swift`:
```swift
    @Test func txtRecordsPointingOffTheLANAreIgnored() {
        #expect(BonjourDiscovery.player(fromTXT: ["uuid": "RINCON_1", "location": "http://192.168.1.10:1400/xml/device_description.xml"]) != nil)
        #expect(BonjourDiscovery.player(fromTXT: ["uuid": "RINCON_1", "location": "http://attacker.example/xml"]) == nil)
        #expect(BonjourDiscovery.player(fromTXT: ["uuid": "RINCON_1", "location": "ftp://192.168.1.10/x"]) == nil)
        #expect(WirePlayer.host(fromWebsocketURL: "wss://192.168.1.11:1443/websocket/api") == "192.168.1.11")
        #expect(WirePlayer.host(fromWebsocketURL: "wss://evil.example:1443/websocket/api") == nil)
    }
```
(Check how existing DiscoveryTests build TXT dictionaries — the key for the id may be `uuid`; match it.)

- [ ] **Step 2: Run them to verify they fail**

```bash
cd Packages/SonosKit && swift test --filter "TrustPolicyTests|DiscoveryTests" 2>&1 | grep -E "error:|passed|failed" | tail -5
```
Expected: compile errors for `isLocalSpeakerAddress`, `speakerHost`, `decision`, `TrustPinStore`.

- [ ] **Step 3: Implement**

`Packages/SonosKit/Sources/SonosKit/Transport/TrustPolicy.swift` (replace the file):
```swift
import CryptoKit
import Foundation
import os
import Security
import Synchronization

public enum TrustDecision: Sendable, Equatable {
    case accept
    case reject
}

/// Where pins live between launches. The app persists them in UserDefaults; tests keep them in memory.
public protocol TrustPinStore: Sendable {
    func load() -> [String: Data]
    func save(_ pins: [String: Data])
}

public enum TrustPolicy {
    /// The only port the local Control API and websocket use.
    public static let speakerPort = 1443

    /// 10/8, 172.16/12, 192.168/16. Hostnames and public addresses are never private.
    public static func isPrivateIPv4(_ host: String) -> Bool {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }
        let octets = parts.compactMap { UInt8($0) }
        guard octets.count == 4 else { return false }
        switch (octets[0], octets[1]) {
        case (10, _): return true
        case (172, 16...31): return true
        case (192, 168): return true
        default: return false
        }
    }

    /// Private IPv4, IPv4 link-local (169.254/16), or IPv6 link-local / unique-local literals.
    /// Sonos always publishes IP literals; a DNS name is never a speaker.
    public static func isLocalSpeakerAddress(_ host: String) -> Bool {
        if isPrivateIPv4(host) { return true }
        if host.hasPrefix("169.254.") { return isIPv4Literal(host) }
        let lower = host.lowercased()
        if lower.contains(":") {
            return lower.hasPrefix("fe80:") || lower.hasPrefix("fc") || lower.hasPrefix("fd")
        }
        return false
    }

    /// The host of `urlString` when its scheme is allowed and the host is a local speaker literal.
    public static func speakerHost(from urlString: String, schemes: Set<String>) -> String? {
        guard let components = URLComponents(string: urlString),
              let scheme = components.scheme?.lowercased(), schemes.contains(scheme),
              let host = components.host, isLocalSpeakerAddress(host) else { return nil }
        return host
    }

    /// SHA-256 of the leaf certificate's public key (SPKI bytes), or nil when the chain is unreadable.
    public static func leafKeyHash(of trust: SecTrust) -> Data? {
        guard let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
              let leaf = chain.first,
              let key = SecCertificateCopyKey(leaf),
              let bytes = SecKeyCopyExternalRepresentation(key, nil) as Data? else { return nil }
        return Data(SHA256.hash(data: bytes))
    }

    private static func isIPv4Literal(_ host: String) -> Bool {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count == 4 && parts.allSatisfy { UInt8($0) != nil }
    }
}

/// Hosts discovered on the LAN whose self-signed certificate we accept, pinned to the key seen on first contact.
public final class TrustStore: Sendable {
    private struct State: Sendable {
        var hosts: Set<String> = []
        var pins: [String: Data] = [:]
    }

    private let logger = Logger(subsystem: "com.jenswedin.SonosRemote", category: "trust")
    private let state: Mutex<State>
    private let pinStore: (any TrustPinStore)?

    public init(pinStore: (any TrustPinStore)? = nil) {
        self.pinStore = pinStore
        state = Mutex(State(hosts: [], pins: pinStore?.load() ?? [:]))
    }

    public func allow(host: String) {
        guard TrustPolicy.isLocalSpeakerAddress(host) else { return }
        state.withLock { _ = $0.hosts.insert(host) }
    }

    /// Forget a host and its pin; the next contact pins afresh.
    public func revoke(host: String) {
        let pins = state.withLock { s -> [String: Data] in
            s.hosts.remove(host)
            s.pins[host] = nil
            return s.pins
        }
        pinStore?.save(pins)
    }

    /// Trust-on-first-use: an allowed host with no pin records `keyHash`; afterwards the key must match.
    public func decision(host: String, port: Int, keyHash: Data) -> TrustDecision {
        guard port == TrustPolicy.speakerPort, TrustPolicy.isLocalSpeakerAddress(host) else { return .reject }
        let (decision, pins) = state.withLock { s -> (TrustDecision, [String: Data]?) in
            guard s.hosts.contains(host) else { return (.reject, nil) }
            if let pinned = s.pins[host] {
                return (pinned == keyHash ? .accept : .reject, nil)
            }
            s.pins[host] = keyHash
            return (.accept, s.pins)
        }
        if let pins { pinStore?.save(pins) }
        if decision == .reject {
            logger.error("rejected certificate for \(host, privacy: .private(mask: .hash)) on port \(port): key does not match the pinned speaker")
        }
        return decision
    }

    /// Kept for callers that only need the allow-list (the websocket URL builder, tests).
    public func shouldTrust(host: String) -> Bool {
        TrustPolicy.isLocalSpeakerAddress(host) && state.withLock { $0.hosts.contains(host) }
    }
}
```

`URLSessionTransport.swift` `TrustDelegate.urlSession(_:didReceive:completionHandler:)` — replace the body after the server-trust guard:
```swift
        guard let trust = space.serverTrust, let keyHash = TrustPolicy.leafKeyHash(of: trust),
              store.decision(host: space.host, port: space.port, keyHash: keyHash) == .accept else {
            logger.error("declined trust for host \(space.host, privacy: .private(mask: .hash)); cancelling the challenge")
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        completionHandler(.useCredential, URLCredential(trust: trust))
```
(`.cancelAuthenticationChallenge`, not default handling: default handling would let a CA-signed certificate through for a host we have no business trusting.)

`BonjourDiscovery.swift` `player(fromTXT:)`:
```swift
    public static func player(fromTXT txt: [String: String]) -> DiscoveredPlayer? {
        guard let id = txt["uuid"], !id.isEmpty,
              let location = txt["location"],
              let host = TrustPolicy.speakerHost(from: location, schemes: ["http", "https"]) else { return nil }
        return DiscoveredPlayer(id: id, address: host, householdID: txt["hhid"])
    }
```
(Keep whatever key the existing code uses for the id.)

`WireTypes.swift`:
```swift
    static func host(fromWebsocketURL string: String) -> String? {
        TrustPolicy.speakerHost(from: string, schemes: ["wss"])
    }
```

`Household.swift` `.lost` branch: after `apply(.playerRemoved(playerID: playerID))` add
```swift
            if let address = addresses.removeValue(forKey: playerID) {
                trustStore?.revoke(host: address)
            }
```

`SonosRemote/App/UserDefaultsPinStore.swift`:
```swift
import Foundation
import SonosKit

/// Persists speaker key pins under one UserDefaults key so a relaunch keeps trusting the same keys.
struct UserDefaultsPinStore: TrustPinStore {
    static let key = "speakerKeyPins"
    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func load() -> [String: Data] {
        defaults.dictionary(forKey: Self.key)?.compactMapValues { $0 as? Data } ?? [:]
    }

    func save(_ pins: [String: Data]) {
        defaults.set(pins, forKey: Self.key)
    }
}
```
In `AppState.live()` and `retryDiscovery()`: `let transport = URLSessionTransport(trustStore: TrustStore(pinStore: UserDefaultsPinStore()))`.

- [ ] **Step 4: Run all package tests, build the app, metrics**

```bash
cd Packages/SonosKit && swift test 2>&1 | grep -E "error:|warning:|Test run with|failed" | tail -4
cd ../.. && xcodegen generate >/dev/null && xcodebuild -project SonosRemote.xcodeproj -scheme SonosRemote -configuration Debug -derivedDataPath .build/xcode build 2>&1 | grep -E "error:|warning: .*SonosRemote/|BUILD" | head -3
pkill -x SonosRemote; open .build/xcode/Build/Products/Debug/SonosRemote.app
python3 scripts/audit-metrics.py --label task-2 --no-tests | grep -E "sec\.(cert|address|trust)"
```
Expected: 87 package tests (81 + 5 + 1), BUILD SUCCEEDED, `sec.cert_pinning 1`, `sec.address_validation 1`, `sec.trust_revoke_on_lost 1`. Owner check: the panel still connects (first launch after this change pins every speaker); `defaults read com.jenswedin.SonosRemote speakerKeyPins` lists the speakers' IPs.

- [ ] **Step 5: Commit**

```bash
git add -A Packages SonosRemote docs/audits/metrics
git commit -m "fix(security): pin speaker keys on first contact and validate discovered addresses"
```

---

### Task 3: Never trap on network data (security H-3, H-4)

**Files:**
- Modify: `Packages/SonosKit/Sources/SonosKit/LocalAPI/LocalAPIClient.swift`, `Packages/SonosKit/Sources/SonosKit/Socket/PlayerSocket.swift`, `Packages/SonosKit/Sources/SonosKit/UPnP/UPnPClient.swift`, `Packages/SonosKit/Sources/SonosKit/Household/Household.swift` (socket creation), `Packages/SonosKit/Sources/SonosKit/Models/Models.swift`, `Packages/SonosKit/Sources/SonosKit/Wire/WireMapping.swift`, `Packages/SonosKit/Sources/SonosKit/Socket/SocketFrame.swift`, `SonosRemote/App/PlaybackDisplay.swift`
- Test: `LocalAPIClientTests.swift`, `SocketFrameTests.swift`, `SonosRemoteTests/PlaybackDisplayTests.swift`

**Interfaces:**
- Produces: `LocalAPIError.badAddress`, `UPnPError.badAddress`, `PlayerSocket.init` becomes failable (`init?`), `PlaybackProgress.maximumMillis: Int = 86_400_000`, `PlaybackProgress.clamped(_ millis: Int) -> Int`.

- [ ] **Step 1: Write the failing tests**

`LocalAPIClientTests.swift`:
```swift
    @Test func badAddressThrowsInsteadOfTrapping() async {
        let transport = FakeTransport()
        let client = LocalAPIClient(transport: transport)
        await #expect(throws: LocalAPIError.badAddress) {
            try await client.play(groupID: "g", at: "not a host")
        }
        #expect(transport.requests.isEmpty)
    }
```
(Use the client's real initialiser and one real command name from the file; `"not a host"` contains spaces so `URL(string:)` returns nil.)

`SocketFrameTests.swift`:
```swift
    @Test func absurdPositionsAndDurationsAreClamped() throws {
        let status = #"[{"namespace":"playback:1","type":"playbackStatus","groupId":"g"},{"playbackState":"PLAYBACK_STATE_PLAYING","positionMillis":9223372036854775807,"playModes":{"shuffle":false,"repeat":false},"availablePlaybackActions":{"canShuffle":true,"canRepeat":true}}]"#
        guard case .playbackStatus(_, _, let progress) = try SocketFrameDecoder.decode(Data(status.utf8), now: { Date() }) else { Issue.record("wrong event"); return }
        #expect(progress.positionMillis == PlaybackProgress.maximumMillis)
        let metadata = #"[{"namespace":"playbackMetadata:1","type":"metadataStatus","groupId":"g"},{"currentItem":{"track":{"name":"t","durationMillis":-5}}}]"#
        guard case .metadata(_, _, let duration) = try SocketFrameDecoder.decode(Data(metadata.utf8), now: { Date() }) else { Issue.record("wrong event"); return }
        #expect(duration == 0)
    }
```
(Match `SocketFrameDecoder.decode`'s real signature from `SocketFrame.swift`; the existing tests show it.)

`SonosRemoteTests/PlaybackDisplayTests.swift`:
```swift
    @Test func extremeValuesNeverTrap() {
        let huge = PlaybackProgress(positionMillis: Int.max, durationMillis: Int.max, reportedAt: .distantPast, shuffle: false, repeatEnabled: false, canShuffle: true, canRepeat: true)
        #expect(PlaybackDisplay.displayedPosition(progress: huge, state: .playing, now: .distantFuture) == Int.max)
        #expect(PlaybackDisplay.remainingString(position: 0, duration: Int.max).hasPrefix("−"))
        #expect(PlaybackDisplay.remainingString(position: Int.max, duration: 1) == "−0:00")
    }
```

- [ ] **Step 2: Run them to verify they fail**

```bash
cd Packages/SonosKit && swift test --filter "LocalAPIClientTests|SocketFrameTests" 2>&1 | grep -E "error:|passed|failed" | tail -4
```
Expected: compile errors (`badAddress`, `maximumMillis`). The app test traps or fails to compile.

- [ ] **Step 3: Implement**

`LocalAPIClient.swift`: add `case badAddress` to `LocalAPIError`; make `makeRequest` `throws` and replace the `preconditionFailure` with `throw LocalAPIError.badAddress`; prefix every `makeRequest(` call site with `try` (13 sites, all inside `async throws` functions already).

`UPnPClient.swift`: add `case badAddress` to `UPnPError`; in `call(action:arguments:address:)` replace the `preconditionFailure` with `throw UPnPError.badAddress`.

`PlayerSocket.swift`: change `init(...)` to `init?(...)` and replace the `preconditionFailure` with `return nil`. In `Household.swift`, where sockets are created (`ensureSockets`, search for `PlayerSocket(playerID:`), bind with `guard let socket = PlayerSocket(...) else { logger.error("skipping player \(id, privacy: .public): unusable address"); continue }`.

`Models.swift`, in `PlaybackProgress`:
```swift
    /// 24 hours. Anything above is treated as corrupt (a stream cannot be longer, a position cannot be later).
    public static let maximumMillis = 86_400_000

    public static func clamped(_ millis: Int) -> Int { min(max(millis, 0), maximumMillis) }
```
`WireMapping.swift` `PlaybackProgress.init(wire:reportedAt:)`: `positionMillis: PlaybackProgress.clamped(wire.positionMillis ?? 0)`. `SocketFrame.swift` metadata case: `durationMillis: frame.body.currentItem?.track?.durationMillis.map(PlaybackProgress.clamped)`.

`PlaybackDisplay.swift`:
```swift
    static func displayedPosition(progress: PlaybackProgress, state: PlaybackState, now: Date) -> Int? {
        guard let duration = progress.durationMillis, duration > 0 else { return nil }
        var position = progress.positionMillis
        if state == .playing {
            let elapsed = now.timeIntervalSince(progress.reportedAt)
            if elapsed > 0 {
                let elapsedMillis = Int(min(elapsed, Double(PlaybackProgress.maximumMillis) / 1000) * 1000)
                let (sum, overflow) = position.addingReportingOverflow(elapsedMillis)
                position = overflow ? Int.max : sum
            }
        }
        return max(0, min(position, duration))
    }

    static func remainingString(position: Int, duration: Int) -> String {
        let (difference, overflow) = duration.subtractingReportingOverflow(position)
        let remainingMillis = overflow ? (duration > position ? Int.max : 0) : max(0, difference)
        let totalSeconds = remainingMillis >= Int.max - 999 ? Int.max / 1000 : (remainingMillis + 999) / 1000
        return "−" + format(totalSeconds: totalSeconds)
    }
```

- [ ] **Step 4: Run everything, metrics**

```bash
cd Packages/SonosKit && swift test 2>&1 | grep -E "error:|Test run with|failed" | tail -3
cd ../.. && xcodebuild test -project SonosRemote.xcodeproj -scheme SonosRemote -destination 'platform=macOS' -derivedDataPath .build/xcode 2>&1 | grep -E "error:|Test run with|TEST (SUCCEEDED|FAILED)" | tail -3
python3 scripts/audit-metrics.py --label task-3 --no-tests | grep -E "sec\.(traps|overflow)"
```
Expected: 89 package tests, 42 app tests, `sec.traps_on_network_data 0`, `sec.overflow_safe_progress 1`.

- [ ] **Step 5: Commit**

```bash
git add -A Packages SonosRemote docs/audits/metrics
git commit -m "fix(security): recoverable errors instead of traps on network-derived addresses; clamp wire millis"
```

---

### Task 4: Narrow observable state, buffered stream, stored ordering (perf H1, H3, M1)

**Files:**
- Modify: `SonosRemote/App/AppState.swift`, every file under `SonosRemote/Views` that reads `state.snapshot`, `Packages/SonosKit/Sources/SonosKit/Household/Household.swift:67,418-428`
- Test: `SonosRemoteTests/AppStateTests.swift`, `Packages/SonosKit/Tests/SonosKitTests/HouseholdTests.swift`

**Interfaces:**
- Produces on `AppState`: `private(set) var status: HouseholdStatus`, `private(set) var groups: [Group]`, `private(set) var players: [Player]`, `private(set) var favorites: [Favorite]`, `private(set) var softwareVersion: String?`, `private(set) var orderedGroups: [Group]` (stored), `func group(_ id: String) -> Group?`, `func player(_ id: String) -> Player?`, `func group(containing playerID: String) -> Group?`. `snapshot` is removed from `AppState`.

- [ ] **Step 1: Write the failing tests**

`HouseholdTests.swift`:
```swift
    @Test func identicalEventsDoNotYieldNewSnapshots() async throws {
        let h = Harness()
        let first = try await h.startAndDiscover(DiscoveredPlayer(id: "RINCON_1", address: "192.168.1.10", householdID: "hh"))
        let groupID = try #require(first.groups.first?.id)
        let socket = try #require(h.transport.sockets.first)
        let yields = Mutex(0)
        let stream = await h.household.snapshots()
        let counter = Task { for await _ in stream { yields.withLock { $0 += 1 } } }
        try await Task.sleep(for: .milliseconds(50))
        let frame = #"[{"namespace":"groupVolume:1","type":"groupVolume","groupId":"\#(groupID)"},{"volume":20,"muted":false,"fixed":false}]"#
        for _ in 0..<10 { socket.push(frame) }
        try await Task.sleep(for: .milliseconds(200))
        counter.cancel()
        #expect(yields.withLock { $0 } <= 2, "initial snapshot plus at most one change")
    }
```

`AppStateTests.swift`: replace every `appState.snapshot.` read with the narrow property (`appState.groups`, `appState.status`, …) and add:
```swift
    @Test func orderedGroupsIsRecomputedOnlyWhenGroupsChange() {
        let appState = makeAppState()
        appState.apply(snapshot([group("b", .idle), group("a", .playing)]))
        #expect(appState.orderedGroups.map(\.id) == ["a", "b"])
        appState.apply(snapshot([group("b", .playing), group("a", .idle)]))
        #expect(appState.orderedGroups.map(\.id) == ["b", "a"])
    }
```

- [ ] **Step 2: Implement in SonosKit**

`Household.swift` `snapshots()`: `let (stream, continuation) = AsyncStream<HouseholdSnapshot>.makeStream(bufferingPolicy: .bufferingNewest(1))`.
`Household.swift` `apply(_:)`:
```swift
    private func apply(_ event: HouseholdEvent) {
        let previousStatus = snapshot.status
        let next = SnapshotReducer.reduce(snapshot, event)
        guard next != snapshot else { return }
        snapshot = next
        if snapshot.status != previousStatus {
            logger.info("status changed from \(String(describing: previousStatus), privacy: .public) to \(String(describing: snapshot.status), privacy: .public)")
        }
        for continuation in observers.values {
            continuation.yield(snapshot)
        }
    }
```
(`HouseholdSnapshot` is `Hashable`, so `!=` exists.)

- [ ] **Step 3: Implement in AppState**

Replace `private(set) var snapshot = HouseholdSnapshot()` and the computed `orderedGroups` with:
```swift
    private(set) var status: HouseholdStatus = .discovering
    private(set) var groups: [Group] = []
    private(set) var players: [Player] = []
    private(set) var favorites: [Favorite] = []
    private(set) var softwareVersion: String?
    /// Groups for display: the ones playing (or about to) first, then the rest, each tier by name.
    /// Stored, recomputed only when `groups` changes, so a render never sorts.
    private(set) var orderedGroups: [Group] = []

    func group(_ id: String) -> Group? { groups.first { $0.id == id } }
    func player(_ id: String) -> Player? { players.first { $0.id == id } }
    func group(containing playerID: String) -> Group? { groups.first { $0.playerIDs.contains(playerID) } }
```
`selectedGroup` becomes `selectedGroupID.flatMap(group)`. In `apply(_:)` the first line becomes:
```swift
        if status != snapshot.status { status = snapshot.status }
        if groups != snapshot.groups {
            groups = snapshot.groups
            orderedGroups = Self.ordered(snapshot.groups)
        }
        if players != snapshot.players { players = snapshot.players }
        if favorites != snapshot.favorites { favorites = snapshot.favorites }
        if softwareVersion != snapshot.softwareVersion { softwareVersion = snapshot.softwareVersion }
```
with
```swift
    private static func ordered(_ groups: [Group]) -> [Group] {
        groups.sorted { lhs, rhs in
            let lhsActive = lhs.playbackState.isActive
            let rhsActive = rhs.playbackState.isActive
            if lhsActive != rhsActive { return lhsActive }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }
```
Every other `snapshot.` inside `AppState` (`snapshot.group(`, `snapshot.player(`, `snapshot.groups`, `snapshot.group(containing:`) becomes the matching method or property on `self`. `retryDiscovery()` resets the five properties instead of `snapshot = HouseholdSnapshot()`.

Views: replace `state.snapshot.status` → `state.status`, `state.snapshot.players` → `state.players`, `state.snapshot.favorites` → `state.favorites`, `state.snapshot.softwareVersion` → `state.softwareVersion`, `state.snapshot.groups` → `state.groups`, `state.snapshot.group(` → `state.group(`, `state.snapshot.player(` → `state.player(`. `grep -rn "state\.snapshot" SonosRemote/Views` must return nothing.

- [ ] **Step 4: Run everything, metrics**

```bash
cd Packages/SonosKit && swift test 2>&1 | grep -E "error:|Test run with|failed" | tail -3
cd ../.. && xcodebuild test -project SonosRemote.xcodeproj -scheme SonosRemote -destination 'platform=macOS' -derivedDataPath .build/xcode 2>&1 | grep -E "error:|Test run with|TEST (SUCCEEDED|FAILED)" | tail -3
pkill -x SonosRemote; open .build/xcode/Build/Products/Debug/SonosRemote.app
python3 scripts/audit-metrics.py --label task-4 | grep -E "perf\.(views|sort|stream|noop|snapshot_yields)|tests\."
```
Expected: 90 package tests, 43 app tests, `perf.views_reading_snapshot 0`, `perf.sort_per_access 0`, `perf.stream_buffered 1`, `perf.noop_guard 1`, `perf.snapshot_yields_per_40_burst` ≤ 1.

- [ ] **Step 5: Commit**

```bash
git add -A Packages SonosRemote docs/audits/metrics
git commit -m "perf: narrow observable state, buffered snapshot stream, stored group ordering"
```

---

### Task 5: Announcements, live regions, the room row's action, the Group screen's hint (a11y S2, S3, S6, S7)

**Files:**
- Modify: `SonosRemote/App/AppState.swift`, `SonosRemote/Views/Components/ErrorLine.swift`, `SonosRemote/Views/StatusBannerView.swift`, `SonosRemote/Views/Sound/SoundScreen.swift` ("Reading EQ…"), `SonosRemote/Views/Favorites/FavoritesScreen.swift` (count), `SonosRemote/Views/Main/ProgressBarView.swift`, `SonosRemote/Views/Main/RoomRowView.swift`, `SonosRemote/Views/Group/GroupScreen.swift`
- Test: `SonosRemoteTests/AppStateTests.swift`

**Interfaces:**
- Produces: `AppState.announcements: [String]` (test-visible log of what was announced), `AppState.announce(_:)`.

- [ ] **Step 1: Write the failing test**

```swift
    @Test func errorsAndStatusChangesAreAnnounced() {
        let appState = makeAppState()
        appState.report("g", LocalAPIError.http(status: 500))
        #expect(appState.announcements.last == AppState.message(for: LocalAPIError.http(status: 500)))
        var s = snapshot([group("a", .playing)])
        s.status = .ready
        appState.apply(s)
        #expect(appState.announcements.last == "Connected to Sonos")
    }
```
(Use a real `LocalAPIError` case from the enum; `.http` may carry a different payload — match it.)

- [ ] **Step 2: Implement**

`AppState.swift`: add `import SwiftUI` (for `AccessibilityNotification`), then
```swift
    /// Every VoiceOver announcement posted, newest last (tests read it; the app posts it).
    private(set) var announcements: [String] = []

    func announce(_ message: String) {
        announcements.append(message)
        AccessibilityNotification.Announcement(message).post()
    }

    static func statusAnnouncement(_ status: HouseholdStatus) -> String? {
        switch status {
        case .ready: "Connected to Sonos"
        case .discovering: "Looking for Sonos"
        case .noPlayersFound: "No Sonos found on this network"
        case .unauthorized: "Not authorized by the Sonos system"
        case .localNetworkDenied: "Local network access is off"
        }
    }
```
In `apply(_:)`, where `status` is assigned: `if status != snapshot.status { status = snapshot.status; if let text = Self.statusAnnouncement(snapshot.status) { announce(text) } }` (do not announce the initial `.discovering` set in `init`). In `report(_:_:)`: after `rowErrors[groupID] = …`, `announce(Self.message(for: error))`.

Views: add `.accessibilityAddTraits(.updatesFrequently)` to `ErrorLine`'s Text, to the `Banner` element in `StatusBannerView`, to the "Reading EQ…" HStack in `SoundScreen`, to the count Text in `FavoritesScreen`, and to the progress bar element in `ProgressBarView` (the one that has `.accessibilityLabel("Progress")`).

`RoomRowView.swift` select button modifiers become:
```swift
            .accessibilityLabel(group.name)
            .accessibilityValue(line)
            .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            .accessibilityHint("Press Space to play or pause")
            .accessibilityAction(named: Text(group.playbackState == .playing ? "Pause" : "Play")) {
                state.togglePlayPause(group: group.id)
            }
```

`GroupScreen.swift` `MembershipRow`: keep the name/note VStack hidden, and on the Toggle replace the label modifier with
```swift
        .accessibilityLabel(player.name)
        .accessibilityValue(isMember ? "in \(group.name)" : "not in \(group.name)")
        .accessibilityHint(isCoordinator ? "Source of this group" : (playingElsewhere ? "Playing elsewhere; switching it will move it to this group" : ""))
```

- [ ] **Step 3: Run, metrics**

```bash
xcodebuild test -project SonosRemote.xcodeproj -scheme SonosRemote -destination 'platform=macOS' -derivedDataPath .build/xcode 2>&1 | grep -E "error:|Test run with|TEST (SUCCEEDED|FAILED)" | tail -3
pkill -x SonosRemote; open .build/xcode/Build/Products/Debug/SonosRemote.app
python3 scripts/audit-metrics.py --label task-5 --no-tests | grep -E "a11y\.(announcement|updates|actions|hints)"
```
Expected: 44 app tests; `a11y.announcement_sites` ≥ 1 (the `announce` implementation counts), `a11y.updates_frequently` ≥ 5, `a11y.actions` ≥ 1, `a11y.hints` ≥ 2. Owner check with VoiceOver: an unreachable speaker error is spoken; opening the panel while discovering speaks "Looking for Sonos"; the room row offers Play/Pause in the actions rotor.

- [ ] **Step 4: Commit**

```bash
git add -A SonosRemote docs/audits/metrics
git commit -m "fix(a11y): announce errors and status, live regions, room row action, group screen hints"
```

---

### Task 6: Subscribe only while the panel is open; drop per-player volume (perf H5, H2)

**Files:**
- Modify: `Packages/SonosKit/Sources/SonosKit/Household/SubscriptionPlan.swift`, `Packages/SonosKit/Sources/SonosKit/Household/Household.swift`, `SonosRemote/App/AppState.swift`, `Packages/SonosKit/Tests/SonosKitTests/MetricsProbeTests.swift`
- Test: `SubscriptionPlanTests.swift`, `HouseholdTests.swift`

**Interfaces:**
- Produces: `SubscriptionPlan.make(groups:players:gatewayID:panelVisible:)`, `Household.setPanelVisible(_ visible: Bool) async`.

- [ ] **Step 1: Write the failing tests**

`SubscriptionPlanTests.swift`:
```swift
    @Test func closedPanelKeepsOnlyHouseholdSubscriptions() {
        let player = Player(id: "P1", name: "Kitchen", address: "192.168.1.10", hasSub: false)
        let group = Group(id: "G1", name: "Kitchen", coordinatorID: "P1", playerIDs: ["P1"], playbackState: .idle, volume: .silent, nowPlaying: nil)
        let closed = SubscriptionPlan.make(groups: [group], players: [player], gatewayID: "P1", panelVisible: false)
        #expect(closed["P1"]?.map(\.namespace).sorted() == ["favorites:1", "groups:1"])
        let open = SubscriptionPlan.make(groups: [group], players: [player], gatewayID: "P1", panelVisible: true)
        #expect(open["P1"]?.map(\.namespace).sorted() == ["favorites:1", "groupVolume:1", "groups:1", "playback:1", "playbackMetadata:1"])
        #expect(!open.values.contains { $0.contains { $0.namespace == "playerVolume:1" } })
    }
```
`HouseholdTests.swift`:
```swift
    @Test func openingThePanelSubscribesToPlaybackAndClosingUnsubscribes() async throws {
        let h = Harness()
        _ = try await h.startAndDiscover(DiscoveredPlayer(id: "RINCON_1", address: "192.168.1.10", householdID: "hh"))
        let socket = try #require(h.transport.sockets.first)
        try await h.waitUntil { !socket.sentText.contains { $0.contains("playback:1") && $0.contains("subscribe") } }
        await h.household.setPanelVisible(true)
        try await h.waitUntil { socket.sentText.contains { $0.contains("playback:1") && $0.contains("\"subscribe\"") } }
        await h.household.setPanelVisible(false)
        try await h.waitUntil { socket.sentText.contains { $0.contains("playback:1") && $0.contains("unsubscribe") } }
    }
```
(`waitUntil` exists in the test support; if its signature differs, adapt. The frame text for subscribe/unsubscribe comes from `PlayerSocket` — read how it encodes commands and match the strings.)

- [ ] **Step 2: Implement**

`SubscriptionPlan.swift`:
```swift
    static func make(groups: [Group], players: [Player], gatewayID: String?, panelVisible: Bool) -> [String: Set<Subscription>] {
        var plan: [String: Set<Subscription>] = [:]
        if panelVisible {
            for group in groups {
                for namespace in groupNamespaces {
                    plan[group.coordinatorID, default: []].insert(Subscription(namespace: namespace, scope: .group(group.id)))
                }
            }
        }
        let gateway = players.first { $0.id == gatewayID }?.id ?? players.map(\.id).sorted().first
        if let gateway {
            for namespace in householdNamespaces {
                plan[gateway, default: []].insert(Subscription(namespace: namespace, scope: .household))
            }
        }
        return plan
    }
```
(No `playerVolume:1` anywhere; `snapshot.playerVolumes` stays in the model for `sonosctl` and simply stays empty.)

`Household.swift`: add `private var panelVisible = false` and
```swift
    /// The app calls this when the menu bar panel opens or closes; playback subscriptions exist only while it is open.
    public func setPanelVisible(_ visible: Bool) async {
        guard visible != panelVisible else { return }
        panelVisible = visible
        await reconcileSubscriptions()
    }
```
and `reconcileSubscriptions()` passes `panelVisible: panelVisible`. Update every other `SubscriptionPlan.make(` call site and test.

`AppState.setPanelPresented(_:)`: add `Task { [household] in await household.setPanelVisible(presented) }`; `retryDiscovery()` re-applies the current `panelPresented` to the new household after `start()`.

`MetricsProbeTests.subscriptionsWhileClosed`: call `make(..., panelVisible: false)`.

- [ ] **Step 3: Run, metrics**

```bash
cd Packages/SonosKit && swift test 2>&1 | grep -E "error:|Test run with|failed" | tail -3
cd ../.. && xcodebuild test -project SonosRemote.xcodeproj -scheme SonosRemote -destination 'platform=macOS' -derivedDataPath .build/xcode 2>&1 | grep -E "error:|Test run with|TEST (SUCCEEDED|FAILED)" | tail -3
pkill -x SonosRemote; open .build/xcode/Build/Products/Debug/SonosRemote.app
python3 scripts/audit-metrics.py --label task-6 | grep -E "perf\.(subscriptions|player_volume)|tests\."
```
Expected: 92 package tests, 44 app tests, `perf.subscriptions_per_coordinator_closed 2`, `perf.player_volume_subscribed 0`. Owner check: open the panel while music plays; the hero and progress fill within about a second (the subscribe reply carries the current state); close and reopen; Activity Monitor shows the app idle while closed.

- [ ] **Step 4: Commit**

```bash
git add -A Packages SonosRemote docs/audits/metrics
git commit -m "perf: subscribe to playback only while the panel is open; drop per-player volume events"
```

---

### Task 7: Contrast tokens, borders, disabled dimming (a11y S1, M10, m10)

**Files:**
- Create: `SonosRemote/Views/Components/Palette.swift`
- Modify: every view using `.foregroundStyle(.secondary)` or `.tertiary` (32 + 1 sites), `SonosRemote/Views/Components/ErrorLine.swift`, `SonosRemote/Views/Sound/PresetChips.swift`, `SonosRemote/Views/Components/SearchField.swift`, `SonosRemote/Views/Components/Card.swift`, `SonosRemote/Views/Main/TransportView.swift`, `SonosRemote/Views/Main/RoomsListView.swift`

**Interfaces:**
- Produces: `Color.supporting` (≈5.2:1 on white), `Color.faint` (≈4.6:1), `Color.errorText`, `Palette.border(_ contrast: ColorSchemeContrast) -> Color`, `Palette.disabledOpacity = 0.55`.

- [ ] **Step 1: Palette**

`SonosRemote/Views/Components/Palette.swift`:
```swift
import SwiftUI

/// App text and surface tokens verified against WCAG 1.4.3 in light and dark appearance.
/// `.secondary` (≈3.9:1 on white) and `.tertiary` (≈1.9:1) are never used for text the user must read.
enum Palette {
    static let disabledOpacity = 0.55

    static func border(_ contrast: ColorSchemeContrast) -> Color {
        Color.primary.opacity(contrast == .increased ? 0.55 : 0.25)
    }
}

extension Color {
    /// Supporting text: labels, second lines, captions. Primary at 72% ≈ 5.2:1 on white, ≈ 7:1 on black.
    static let supporting = Color.primary.opacity(0.72)
    /// The faintest readable tier (album line, footer). Primary at 60% ≈ 4.6:1 on white.
    static let faint = Color.primary.opacity(0.60)
    /// Error text that clears 4.5:1 on both grounds.
    static let errorText = Color(light: Color(red: 0.72, green: 0.13, blue: 0.11), dark: Color(red: 1.0, green: 0.56, blue: 0.51))

    init(light: Color, dark: Color) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(dark) : NSColor(light)
        })
    }
}
```

- [ ] **Step 2: Apply**

- `sed`-style replacement across `SonosRemote/Views`: `.foregroundStyle(.secondary)` → `.foregroundStyle(Color.supporting)`, `.foregroundStyle(.tertiary)` → `.foregroundStyle(Color.faint)`. Where a view uses `.secondary` for a purely decorative glyph next to a labelled control, `Color.supporting` is still fine. `grep -rn "foregroundStyle(\.\(secondary\|tertiary\))" SonosRemote/Views` must return nothing.
- `ErrorLine.swift`: `.foregroundStyle(Color.errorText)`.
- `PresetChips.swift` `Chip`: lit = `.foregroundStyle(Color.primary).fontWeight(.semibold)` on `Color.accentColor.opacity(0.22)` with an `.overlay(Capsule().strokeBorder(Color.accentColor, lineWidth: 1))`; unlit = `Color.supporting` on `.quaternary.opacity(0.5)`.
- `SearchField.swift`: add `@Environment(\.colorSchemeContrast) private var contrast` and `.overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Palette.border(contrast)))`.
- `Card.swift`: same environment and `.overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Palette.border(contrast).opacity(0.6)))`.
- `TransportView.swift` `ToggleGlyph` and `RoomsListView.swift` Group link: dim with `.opacity(Palette.disabledOpacity)` instead of colour `opacity(0.4)`.
- `VolumeSliderView.swift` readouts and `FooterView` text: `Color.supporting`.

- [ ] **Step 3: Run, metrics**

```bash
xcodebuild test -project SonosRemote.xcodeproj -scheme SonosRemote -destination 'platform=macOS' -derivedDataPath .build/xcode 2>&1 | grep -E "error:|Test run with|TEST (SUCCEEDED|FAILED)" | tail -3
pkill -x SonosRemote; open .build/xcode/Build/Products/Debug/SonosRemote.app
python3 scripts/audit-metrics.py --label task-7 --no-tests | grep -E "a11y\.system_secondary"
```
Expected: 44 app tests, `a11y.system_secondary_sites 0`. Owner check in light mode: second lines and captions are clearly darker than before; the error line is readable; Increase Contrast thickens the search field and card borders.

- [ ] **Step 4: Commit**

```bash
git add -A SonosRemote docs/audits/metrics
git commit -m "fix(a11y): text and border tokens that meet 4.5:1 and 3:1 in both appearances"
```

---

### Task 8: Quick wins batch (security M-4, L-3, L-4; perf M5, M8, L2; a11y M5, M6)

**Files:**
- Modify: `SonosRemote/Views/Group/GroupScreen.swift`, `SonosRemote/Views/Main/RoomRowView.swift`, `SonosRemote/Views/Favorites/FavoriteRow.swift`, `SonosRemote/Views/VolumeSliderView.swift`, `SonosRemote/Views/Sound/SoundScreen.swift`, `SonosRemote/Views/Sound/ToneSlider.swift`, `SonosRemote/Views/Shell/PanelShellView.swift`, `SonosRemote/Views/Settings/SettingsScreen.swift`, `SonosRemote/App/AppState.swift`, `Packages/SonosKit/Sources/SonosKit/Socket/PlayerSocket.swift`, `Packages/SonosKit/Sources/SonosKit/Household/Household.swift`, `Packages/SonosKit/Sources/SonosKit/Transport/URLSessionTransport.swift`, `project.yml`

One batched dispatch; each item is a few lines:

- [ ] **Step 1: Apply every item**

1. **Text(verbatim:) for metadata** (M-4): every `Text("…\(now.title)…")`, `Text("…\(player.name)…")`, `Text("…\(group.name)…")` literal that interpolates speaker-supplied strings becomes `Text(verbatim: "…")` (GroupScreen line ~62 first; grep `Text("` with `\(` in `SonosRemote/Views`). Accessibility labels are plain Strings and need no change.
2. **Exact dependency versions** (L-4): in `project.yml`, replace each package's `from:` with `exactVersion:` set to the version currently resolved in `SonosRemote.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` (read it after `xcodegen generate`). Add one line to `knowledge/procedural/release.md`: "Dependencies are pinned with `exactVersion` in project.yml; bump deliberately."
3. **Log privacy** (L-3): in `URLSessionTransport.swift` and `Household.swift`, drop `privacy: .public` from interpolated IP addresses and player ids (keep it for enum states and error codes).
4. **SMAppService once** (M5): `SettingsScreen.swift` → `@State private var launchAtLogin = false` and `.onAppear { launchAtLogin = SMAppService.mainApp.status == .enabled }`; keep the `onChange` guard.
5. **Ping interval** (M8): `PlayerSocket.pingInterval = .seconds(90)`.
6. **Pruning** (L2): in `AppState.report(_:_:)`'s delayed clear, also `errorGeneration[groupID] = nil` when the error is cleared; in `Household`'s `.lost` branch, `addresses` is already removed by Task 2.
7. **Reduce Motion** (a11y M5): `PanelShellView` reads `@Environment(\.accessibilityReduceMotion) private var reduceMotion` and uses `.animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: state.screen)`; when `reduceMotion` is true the screen transitions are `.opacity` instead of `.move`.
8. **Reset action** (a11y M6): `ToneSlider` adds `.accessibilityAction(named: Text("Reset \(label)")) { local = 0; onChange(0) }` on the Slider.

- [ ] **Step 2: Run everything, metrics**

```bash
cd Packages/SonosKit && swift test 2>&1 | grep -E "error:|Test run with|failed" | tail -3
cd ../.. && xcodegen generate >/dev/null && xcodebuild test -project SonosRemote.xcodeproj -scheme SonosRemote -destination 'platform=macOS' -derivedDataPath .build/xcode 2>&1 | grep -E "error:|Test run with|TEST (SUCCEEDED|FAILED)" | tail -3
pkill -x SonosRemote; open .build/xcode/Build/Products/Debug/SonosRemote.app
python3 scripts/audit-metrics.py --label task-8 --no-tests | grep -E "sec\.(interpolated|deps|public)|perf\.(ping|smapp)|a11y\.reduce"
```
Expected: `sec.interpolated_text_sites 0`, `sec.deps_pinned 1`, `sec.public_privacy_logs` lower than the baseline, `perf.ping_interval_seconds 90`, `perf.smappservice_in_initialiser 0`, `a11y.reduce_motion 1`; tests unchanged (92 / 44).

- [ ] **Step 3: Commit**

```bash
git add -A Packages SonosRemote project.yml knowledge docs/audits/metrics
git commit -m "chore: quick wins from the audit — verbatim text, pinned deps, log privacy, reduce motion, ping, pruning"
```

---

### Task 9: After-metrics and the before/after report

**Files:**
- Create: `docs/audits/2026-09-11-fix-round-1.md`
- Modify: `changelog.md` (Unreleased), `MEMORY.md`, `docs/audits/metrics/after.json`, `docs/audits/metrics/history.md`

- [ ] **Step 1: Closing run**

```bash
python3 scripts/audit-metrics.py --label after
python3 scripts/audit-metrics.py --compare before after
```

- [ ] **Step 2: Report**

`docs/audits/2026-09-11-fix-round-1.md`: title "Audit fix round 1 — results"; a paragraph naming the base commit (`before.json`'s commit) and the head; the full `--compare before after` table pasted verbatim; a "Findings addressed" list mapping each fixed finding id (C1, S1, S2, S3, S4, S5, S6, S7, M5, M6, M10, m10; H1, H2, H3, H5, M1, M5, M8, L2; H-1, H-2, H-3, H-4, L-1, L-2, L-3, L-4, M-4) to the task and commit that fixed it; a "Still open" list of every other finding id from the three audits with one line each; and the owner's manual checks (keyboard navigation off, VoiceOver announcements, Activity Monitor idle when closed).

`changelog.md` under `## [Unreleased]`:
```markdown
### Changed
- Speaker certificates are pinned on first contact and discovered addresses are validated; malformed network data no longer crashes the app.
- The panel keeps only household subscriptions while closed and no longer subscribes to per-player volume; the app re-renders only what changed.
- Every control is keyboard-focusable with Full Keyboard Access off; errors and connection changes are announced to VoiceOver; text and borders meet WCAG contrast; Reduce Motion is honoured.
```
`MEMORY.md`: replace the top "Last state" paragraph with one sentence per fact: audit fix round 1 merged on this branch, metrics history in `docs/audits/metrics/`, what is still open.

- [ ] **Step 3: Commit**

```bash
git add docs/audits changelog.md MEMORY.md
git commit -m "docs: audit fix round 1 results with before/after metrics"
```
