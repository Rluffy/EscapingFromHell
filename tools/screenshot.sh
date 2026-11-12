#!/bin/sh
# Usage: [EXTRA_LUA='<lua>'] tools/screenshot.sh <rom> <out.png> [frames]   (default 120 frames)
# EXTRA_LUA is prepended to the capture script, e.g. to hold a button:
#   EXTRA_LUA='emu.addEventCallback(function() emu.setInput({right=true},0,0) end, emu.eventType.inputPolled)'
set -e
[ $# -ge 2 ] || { echo "usage: $0 <rom> <out.png> [frames]" >&2; exit 2; }
root=$(cd "$(dirname "$0")/.." && pwd)
rom=$(realpath "$1"); out=$(realpath -m "$2"); frames=${3:-120}   # Mesen changes its cwd: absolute paths
grep -q NesController "$root/tools/mesen/settings.json" 2>/dev/null || echo '{"Nes":{"Port1":{"Type":"NesController"}}}' > "$root/tools/mesen/settings.json"
lua=$(mktemp --suffix=.lua)
log=$(mktemp)
trap 'rm -f "$lua" "$log"' EXIT
# Mesen's Lua has no io library: the script prints the PNG as hex, Python writes the file.
cat > "$lua" <<LUA
${EXTRA_LUA:-}
local n = 0
emu.addEventCallback(function()
  n = n + 1
  if n < $frames then return end
  local png = emu.takeScreenshot()
  print("PNGHEX:" .. png:gsub(".", function(c) return string.format("%02x", c:byte()) end))
  emu.stop(0)
end, emu.eventType.endFrame)
LUA
mkdir -p "$(dirname "$out")"
DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1 timeout 60 xvfb-run -a "$root/tools/mesen/Mesen" --testRunner "$lua" "$rom" > "$log"
python3 -I - "$log" "$out" <<'PY'
import sys
hexs = [l[7:].strip() for l in open(sys.argv[1]) if l.startswith("PNGHEX:")][0]
open(sys.argv[2], "wb").write(bytes.fromhex(hexs))
PY
