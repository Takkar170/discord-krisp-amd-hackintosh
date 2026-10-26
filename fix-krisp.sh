#!/bin/bash
# Makes Discord's Krisp noise suppression work on AMD hackintoshes.
# Quit Discord, then run: sudo ./fix-krisp.sh
# Re-run after Discord updates.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
TARGET_USER="${SUDO_USER:-$USER}"
USER_HOME="$(dscl . -read "/Users/$TARGET_USER" NFSHomeDirectory | awk '{print $2}')"
APP=/Applications/Discord.app
RENDERER="$APP/Contents/Frameworks/Discord Helper (Renderer).app"
SUPPORT="$USER_HOME/Library/Application Support/discord"
BACKUPS="$HERE/originals"

if [ "$(uname -m)" != "x86_64" ]; then
  echo "This fix is for x86_64 AMD hackintoshes only." >&2
  exit 1
fi
if ! sysctl -n machdep.cpu.vendor | grep -q AuthenticAMD; then
  echo "This is not an AMD CPU; Krisp already works here." >&2
  exit 1
fi
if [ ! -d "$APP" ]; then
  echo "Discord.app not found in /Applications." >&2
  exit 1
fi
if pgrep -xq Discord; then
  echo "Quit Discord first." >&2
  exit 1
fi

shopt -s nullglob
modules=("$SUPPORT"/app-*/modules/discord_krisp-*/discord_krisp/discord_krisp.node)
if [ ${#modules[@]} -eq 0 ]; then
  echo "No discord_krisp.node found. Open Discord once so it downloads Krisp, quit it, re-run." >&2
  exit 1
fi

mkdir -p "$BACKUPS"

for node in "${modules[@]}"; do
  tag="$(echo "$node" | sed -E 's#.*/(app-[^/]+)/modules/(discord_krisp-[^/]+)/.*#\1_\2#')"
  backup="$BACKUPS/$tag.discord_krisp.node"
  if [ ! -f "$backup" ] && codesign -dv "$node" 2>&1 | grep -q 53Q6R32WPB; then
    cp -p "$node" "$backup"
  fi

  echo "Patching $tag"
  /usr/bin/python3 -I - "$node" <<'PY'
import struct, subprocess, sys

path = sys.argv[1]
signed = "__ZN7discord4util17IsSignedByDiscordERKNSt3__112basic_stringIcNS1_11char_traitsIcEENS1_9allocatorIcEEEE"
# symbol -> (expected original prologue, replacement)
targets = {
    "_mkl_serv_intel_cpu_true": (bytes.fromhex("534883ec208b"), bytes.fromhex("b801000000c3")),  # mov eax,1; ret
    "_mkl_serv_intel_cpu": (bytes.fromhex("534883ec208b"), bytes.fromhex("b801000000c3")),       # mov eax,1; ret
    signed: (bytes.fromhex("554889"), bytes.fromhex("b001c3")),                                   # mov al,1; ret
}

data = bytearray(open(path, "rb").read())
magic, count = struct.unpack(">II", data[:8])
if magic != 0xCAFEBABE:
    sys.exit("not a universal binary")
slice_off = None
for i in range(count):
    cputype, _, off, _, _ = struct.unpack(">iiIII", data[8 + i * 20: 28 + i * 20])
    if cputype == 0x01000007:
        slice_off = off
if slice_off is None:
    sys.exit("no x86_64 slice")

syms = {}
out = subprocess.run(["nm", "-arch", "x86_64", path], capture_output=True, text=True, check=True).stdout
for line in out.splitlines():
    parts = line.split()
    if len(parts) == 3 and parts[2] in targets:
        syms[parts[2]] = int(parts[0], 16)
missing = set(targets) - set(syms)
if missing:
    sys.exit("symbols not found: " + ", ".join(sorted(missing)))

changed = False
for name, (orig, patch) in targets.items():
    at = slice_off + syms[name]
    if bytes(data[at:at + len(patch)]) == patch:
        continue
    if bytes(data[at:at + len(orig)]) != orig:
        sys.exit(f"unexpected bytes at {name}: {bytes(data[at:at + 8]).hex()} (Discord changed the module)")
    data[at:at + len(patch)] = patch
    changed = True

if changed:
    open(path, "wb").write(data)
    print("  patched")
else:
    print("  already patched")
PY
  codesign -f -s - "$node" >/dev/null 2>&1
done

# The Renderer helper enforces library validation, so it must be re-signed to load the
# ad-hoc signed module. Team-only entitlements are dropped or AMFI kills it at launch.
if codesign -dv "$RENDERER" 2>&1 | grep -q 53Q6R32WPB || codesign -d --entitlements - --xml "$RENDERER" 2>/dev/null | grep -q keychain-access-groups; then
  helper_backup="$BACKUPS/Discord Helper (Renderer).app"
  if codesign -dv "$RENDERER" 2>&1 | grep -q 53Q6R32WPB; then
    rm -rf "$helper_backup"
    cp -Rp "$RENDERER" "$helper_backup"
  fi
  ent="$(mktemp)"
  codesign -d --entitlements - --xml "$helper_backup" > "$ent" 2>/dev/null
  /usr/libexec/PlistBuddy -c "Add :com.apple.security.cs.disable-library-validation bool true" "$ent" >/dev/null
  /usr/libexec/PlistBuddy -c "Delete :com.apple.application-identifier" "$ent" >/dev/null 2>&1 || true
  /usr/libexec/PlistBuddy -c "Delete :keychain-access-groups" "$ent" >/dev/null 2>&1 || true
  codesign -f -s - --options runtime --entitlements "$ent" "$RENDERER"
  rm -f "$ent"
  echo "Renderer helper re-signed"
else
  echo "Renderer helper already re-signed"
fi

echo "Done. Open Discord and turn on Krisp."
