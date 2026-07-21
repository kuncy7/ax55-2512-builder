#!/usr/bin/env bash
# Verify a built AX55 sysupgrade image WITHOUT flashing it: unpack the FIT
# kernel and confirm the DWMAC ethernet driver was actually compiled in.
#
# This guards against the known downstream failure mode: a rejected
# config-default hunk still produces a bootable image, but without
# stmmac/DWMAC there is no eth0 and the DSA switch cannot register
# ("rtl8365mb: unable to register switch").
#
# Usage: check-image.sh <sysupgrade.bin>
# Exit:  0 = drivers present, 1 = missing (image is broken), 2 = usage/error

set -euo pipefail

img="${1:?usage: check-image.sh <sysupgrade.bin>}"
[[ -f "$img" ]] || { echo "no such file: $img"; exit 2; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

tar xf "$img" -C "$tmp" 2>/dev/null || { echo "not a sysupgrade tar: $img"; exit 2; }
kernel="$(find "$tmp" -name kernel | head -1)"
[[ -n "$kernel" ]] || { echo "no kernel in image"; exit 2; }

python3 - "$kernel" "$tmp/kernel.raw" <<'PY'
import sys, lzma
d = open(sys.argv[1], 'rb').read()
for i in range(len(d) - 16):
    if d[i] == 0x6d and d[i+1] == 0 and d[i+2] == 0 and d[i+3] == 0x80:
        try:
            out = lzma.LZMADecompressor(format=lzma.FORMAT_ALONE).decompress(d[i:])
            if len(out) > 4_000_000:
                open(sys.argv[2], 'wb').write(out)
                sys.exit(0)
        except Exception:
            pass
sys.exit(3)
PY
[[ -f "$tmp/kernel.raw" ]] || { echo "could not decompress kernel"; exit 2; }

ok=1
echo "--- drivers in the image kernel ---"
# Dump strings once; `strings | grep -q` under pipefail turns a MATCH into a
# pipeline failure (grep -q exits early -> strings dies of SIGPIPE).
strings -a "$tmp/kernel.raw" >"$tmp/kernel.strings"
for s in ipq5018-gmac-dwmac stmmaceth; do
  if grep -q "$s" "$tmp/kernel.strings"; then
    printf '  %-20s PRESENT\n' "$s"
  else
    printf '  %-20s MISSING\n' "$s"
    ok=0
  fi
done

if [[ "$ok" == 1 ]]; then
  echo ">>> OK - ethernet driver present"
  exit 0
else
  echo ">>> FAIL - DWMAC driver missing, ethernet will NOT work on this image"
  exit 1
fi
