#!/bin/bash
# Simulator screenshot harness — captures deep app screens headlessly.
#
# This machine has no Simulator.app and there is no tap API for a physical
# Apple Watch, so screens are reached by launch argument (ScreenshotRoute.swift)
# rather than by tapping. Products come from Points.storekit, attached to the
# scheme's Test action, so prices render exactly as they do in the real app.
#
# Usage:  scripts/screenshots.sh [output-dir] [simulator-udid]
# Output: one PNG per captured screen in the output directory.
#
# See CLAUDE.md, "Simulator screenshot harness".
set -euo pipefail

OUT="${1:-screenshots}"
SIM="${2:-}"
cd "$(dirname "$0")/../PongWatch"

# UDIDs go stale whenever Xcode rotates runtimes, so resolve one by name.
if [ -z "$SIM" ]; then
  # Biggest screen available: watch captures are small, and Apple's in-app
  # purchase review screenshots have a 640x920 minimum to clear.
  DESTS=$(xcodebuild -scheme "PongWatch Watch App" -showdestinations 2>/dev/null \
          | grep "platform:watchOS Simulator" | grep -v placeholder)
  SIM=$(echo "$DESTS" | grep -E "Ultra|49mm" | head -1 | sed -E 's/.*id:([0-9A-F-]+).*/\1/')
  [ -n "$SIM" ] || SIM=$(echo "$DESTS" | grep -E "46mm|45mm" | head -1 | sed -E 's/.*id:([0-9A-F-]+).*/\1/')
  [ -n "$SIM" ] || SIM=$(echo "$DESTS" | head -1 | sed -E 's/.*id:([0-9A-F-]+).*/\1/')
fi
[ -n "$SIM" ] || { echo "No watchOS simulator found." >&2; exit 1; }
echo "Simulator: $SIM"

RESULT=$(mktemp -d)/screenshots.xcresult
xcodebuild test \
  -scheme "PongWatch Watch App" \
  -destination "platform=watchOS Simulator,id=$SIM" \
  -only-testing:"PongWatch Watch AppUITests/ScreenshotTests" \
  -resultBundlePath "$RESULT" \
  >/dev/null 2>&1 || true   # a failed assertion still leaves usable attachments

mkdir -p "$OUT"
# Attachments are named in the result bundle; export them by name.
xcrun xcresulttool export attachments \
  --path "$RESULT" --output-path "$OUT" >/dev/null 2>&1 || true

# export dumps a manifest plus opaque filenames; rename to the attachment names.
python3 - "$OUT" <<'PY'
import json, pathlib, shutil, sys
out = pathlib.Path(sys.argv[1])
man = out / "manifest.json"
if not man.exists():
    print("No manifest — check the xcresult; the test may not have run."); raise SystemExit(1)
n = 0
for entry in json.loads(man.read_text()):
    for a in entry.get("attachments", []):
        src = out / a["exportedFileName"]
        name = a.get("suggestedHumanReadableName") or a.get("name") or src.stem
        if src.exists() and src.suffix.lower() in (".png", ".jpeg", ".jpg", ""):
            dst = out / (name if name.endswith(".png") else name + ".png")
            shutil.move(str(src), dst); n += 1
            print("captured:", dst)
man.unlink(missing_ok=True)
print(f"{n} screenshot(s) in {out}")
PY
