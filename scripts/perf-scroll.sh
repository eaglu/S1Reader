#!/usr/bin/env bash
# Measures scrolling on the thread screen: build the app the way a reader runs
# it (Release), drive one fixed scroll script, and print what the probe saw.
#
#   scripts/perf-scroll.sh                    # thread 2206666, 2 down-and-back legs
#   S1_PERF_TRAVEL=4000 scripts/perf-scroll.sh
#   SIM_UDID=<udid> scripts/perf-scroll.sh
#
# The probe itself lives in S1Reader/Core/Debug/PerfProbe.swift and is inert
# unless S1_PERF_SCROLL is set, so this script is the only thing that turns it
# on. Numbers come from the frame-to-frame intervals of a CADisplayLink plus
# counters on the views the list rebuilds, so two runs of the same script are
# comparable even though the app never shows the same frames twice.
set -euo pipefail
cd "$(dirname "$0")/.."

bundle=com.faye.S1Reader
derived="${DERIVED_DATA:-/tmp/s1rd}"
thread="${S1_PERF_THREAD:-2206666}"
configuration="${S1_PERF_CONFIG:-Release}"
app="$derived/Build/Products/$configuration-iphonesimulator/S1Reader.app"

udid="${SIM_UDID:-}"
if [ -z "$udid" ]; then
  udid=$(xcrun simctl list devices booted --json | python3 -c '
import json, sys
data = json.load(sys.stdin)["devices"]
for runtime, devices in data.items():
    for device in devices:
        if device.get("name", "").startswith("iPhone"):
            print(device["udid"])
            raise SystemExit
')
fi
if [ -z "$udid" ]; then
  echo "no booted iPhone simulator; boot one or set SIM_UDID" >&2
  exit 1
fi

echo "device: $udid"
echo "configuration: $configuration"
echo "thread: $thread  travel=${S1_PERF_TRAVEL:-2400}pt speed=${S1_PERF_SPEED:-700}pt/s cycles=${S1_PERF_CYCLES:-2}"

xcodebuild \
  -project S1Reader.xcodeproj \
  -scheme S1Reader \
  -configuration "$configuration" \
  -destination "platform=iOS Simulator,id=$udid" \
  -derivedDataPath "$derived" \
  CODE_SIGNING_ALLOWED=NO \
  build 2>&1 | grep -E "error:|BUILD" | tail -3

xcrun simctl terminate "$udid" "$bundle" 2>/dev/null || true
# S1_PERF_KEEP=1 keeps the install, so a second run starts with the image cache
# already on disk.
if [ "${S1_PERF_KEEP:-0}" != "1" ]; then
  xcrun simctl uninstall "$udid" "$bundle" 2>/dev/null || true
fi
xcrun simctl install "$udid" "$app"

# The script is over in about 15s; the wait also covers the page load in front of it.
# S1_PERF_RUNS=N discards a warm-up run and then measures N runs, so a comparison
# is not thrown off by the first run paying for cold caches.
runs="${S1_PERF_RUNS:-1}"
log="$(xcrun simctl get_app_container "$udid" "$bundle" data)/tmp/s1-perf-scroll.log"
results=""
for index in $(seq 0 "$runs"); do
  # A still-running instance would swallow the launch and never write a fresh
  # log, which looks exactly like a probe that never finished.
  xcrun simctl terminate "$udid" "$bundle" 2>/dev/null || true
  sleep 1
  rm -f "$log"
  # Everything the probe reads travels in the app's environment; `simctl` passes
  # SIMCTL_CHILD_<name> through as <name>.
  SIMCTL_CHILD_S1_PERF_SCROLL=1 \
  SIMCTL_CHILD_S1_PERF_THREAD="$thread" \
  SIMCTL_CHILD_S1_PERF_TRAVEL="${S1_PERF_TRAVEL:-2400}" \
  SIMCTL_CHILD_S1_PERF_SPEED="${S1_PERF_SPEED:-700}" \
  SIMCTL_CHILD_S1_PERF_CYCLES="${S1_PERF_CYCLES:-2}" \
  SIMCTL_CHILD_S1_PERF_DELAY="${S1_PERF_DELAY:-0}" \
  SIMCTL_CHILD_S1_PERF_NO_IMAGES="${S1_PERF_NO_IMAGES:-}" \
  SIMCTL_CHILD_S1_PERF_NO_SELECTION="${S1_PERF_NO_SELECTION:-}" \
  SIMCTL_CHILD_S1_PERF_NO_MENU="${S1_PERF_NO_MENU:-}" \
  SIMCTL_CHILD_S1_PERF_NO_MOTION="${S1_PERF_NO_MOTION:-}" \
  SIMCTL_CHILD_S1_PERF_NO_DIVIDER="${S1_PERF_NO_DIVIDER:-}" \
  SIMCTL_CHILD_S1_PERF_STATIC_PLACEHOLDER="${S1_PERF_STATIC_PLACEHOLDER:-}" \
  SIMCTL_CHILD_S1_PERF_NO_IMAGE_FADE="${S1_PERF_NO_IMAGE_FADE:-}" \
    xcrun simctl launch "$udid" "$bundle" >/dev/null
  for _ in $(seq 1 60); do
    if [ -s "$log" ] && grep -q "view_ms" "$log"; then break; fi
    sleep 1
  done
  xcrun simctl terminate "$udid" "$bundle" 2>/dev/null || true
  if [ ! -s "$log" ]; then
    echo "no probe output; the app never finished the script" >&2
    exit 1
  fi
  if [ "$index" -gt 0 ]; then
    results="$results$log.$index\n"
    cp "$log" "$log.$index"
    cat "$log"
  else
    echo "warm-up run discarded"
  fi
  sleep 1
done

if [ "$runs" -gt 1 ]; then
  echo "== median of $runs runs"
  cat $(printf "$results") | python3 -c '
import sys, re, statistics, collections
lines = [l.strip() for l in sys.stdin if l.strip()]
def nums(key):
    out = []
    for line in lines:
        m = re.search(key + r"=([\d.]+)", line)
        if m: out.append(float(m.group(1)))
    return out
def counters(name):
    out = []
    for line in lines:
        if "counts" in line:
            m = re.search(name + r"=(\d+)", line)
            if m: out.append(int(m.group(1)))
    return out
for key in ["mean", "p95", "p99", "max", "hitches", "hitchRatio", "droppedFrames", "smoothPct"]:
    vals = nums(key)
    if vals: print("%-14s median %.1f  runs %s" % (key, statistics.median(vals), vals))
for key in ["rowBodies", "contentBodies", "blockBuilds", "texts", "filterRuns", "filterPosts", "avatars"]:
    vals = counters(key)
    if vals: print("%-14s median %d  runs %s" % (key, statistics.median(vals), vals))
'
fi

