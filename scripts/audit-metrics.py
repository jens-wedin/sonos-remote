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
    start = body.find("struct ToggleGlyph")
    if start == -1:
        return 0
    end = body.find("\n}\n", start)
    struct_body = body[start:end] if end != -1 else body[start:]
    return 0 if re.search(r"\.background\(", struct_body) else 1

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
    out["build.warnings"] = len([l for l in text.splitlines() if "warning:" in l and re.search(r"(SonosRemote/|Packages/SonosKit/(Sources|Tests)/).*warning:", l)])
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
