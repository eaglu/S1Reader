#!/usr/bin/env bash
# Runs the unit tests on an iOS simulator.
#
#   scripts/test.sh                      # pick a simulator automatically
#   scripts/test.sh --ui                 # the UI smoke tests (needs network)
#   TEST_DESTINATION='platform=iOS Simulator,name=iPhone 16' scripts/test.sh
#   scripts/test.sh -only-testing:S1ReaderTests/HTMLTextTests
#
# Extra arguments are forwarded to xcodebuild, so a single suite can be re-run
# while iterating. Exits non-zero when anything fails.
set -euo pipefail
cd "$(dirname "$0")/.."

scheme=S1Reader
log=/tmp/s1-test.log
if [ "${1:-}" = "--ui" ]; then
  # Separate scheme: the UI tests only ever run when asked for.
  scheme=S1ReaderUI
  log=/tmp/s1-ui-test.log
  shift
fi

destination="${TEST_DESTINATION:-}"
if [ -z "$destination" ]; then
  udid=$(xcrun simctl list devices available --json | python3 -c '
import json, sys
data = json.load(sys.stdin)["devices"]
best = None
for runtime, devices in data.items():
    if "iOS" not in runtime:
        continue
    for device in devices:
        name = device.get("name", "")
        # An already booted phone wins so a test run does not boot a second
        # simulator next to the one being looked at. Otherwise an iPhone beats
        # an iPad, and later runtimes sort higher: "iOS-26-0" > "iOS-18-2".
        key = (
            device.get("state") == "Booted",
            name.startswith("iPhone"),
            runtime,
            name,
        )
        if best is None or key > best[0]:
            best = (key, device["udid"])
print(best[1] if best else "")
')
  if [ -z "$udid" ]; then
    echo "no bootable iPhone simulator found; set TEST_DESTINATION" >&2
    exit 1
  fi
  destination="platform=iOS Simulator,id=$udid"
fi

echo "scheme: $scheme"
echo "destination: $destination"
log="${TEST_LOG:-$log}"

# A failing xcodebuild would abort under `set -e` before the log is summarised,
# so the pipeline is allowed to fail and the verdict comes from the log.
xcodebuild \
  -project S1Reader.xcodeproj \
  -scheme "$scheme" \
  -configuration Debug \
  -destination "$destination" \
  -derivedDataPath "${DERIVED_DATA:-/tmp/s1dd}" \
  CODE_SIGNING_ALLOWED=NO \
  test "$@" 2>&1 | tee "$log" \
  | grep -E "error:|Test Case .* failed|Executed [0-9]+ test|TEST (SUCCEEDED|FAILED)" || true

if ! grep -q "TEST SUCCEEDED" "$log"; then
  echo
  echo "tests did not pass; failing cases:" >&2
  grep -E "Test Case .* failed|error:" "$log" | sed 's/^/  /' >&2 || true
  echo "full log: $log" >&2
  exit 1
fi

grep -E "Executed [0-9]+ tests" "$log" | tail -1
