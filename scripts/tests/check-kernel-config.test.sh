#!/usr/bin/env bash
# Tests for check-kernel-config.sh.
#
# The case that matters is the middle one: a symbol present but demoted to =m.
# That is what a downstream ALL_KMODS build produces, and it is invisible to a
# naive `grep -q CONFIG_STMMAC_ETH` — which is how the bug shipped in the first
# place.

set -euo pipefail

here="$(cd -- "$(dirname -- "$0")" && pwd)"
script="$here/../check-kernel-config.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

failures=0

# Build a fake OpenWrt tree whose kernel .config holds the given lines.
make_tree() {
  local name="$1"; shift
  local dir="$tmp/$name/build_dir/target-aarch64_cortex-a53_musl/linux-qualcommax_ipq50xx/linux-6.12.94"
  mkdir -p "$dir"
  printf '%s\n' "$@" >"$dir/.config"
  echo "$tmp/$name"
}

expect() {
  local label="$1" want="$2" tree="$3"
  local got=0
  "$script" "$tree" >/dev/null 2>&1 || got=$?
  if [[ "$got" == "$want" ]]; then
    echo "ok   - $label (exit $got)"
  else
    echo "FAIL - $label: expected exit $want, got $got"
    failures=$((failures + 1))
  fi
}

BUILTIN=(
  CONFIG_STMMAC_ETH=y
  CONFIG_STMMAC_PLATFORM=y
  CONFIG_DWMAC_IPQ5018=y
  CONFIG_PCS_QCA_UNIPHY=y
  CONFIG_PTP_1588_CLOCK=y
)

MODULAR=(
  CONFIG_STMMAC_ETH=m
  CONFIG_STMMAC_PLATFORM=m
  CONFIG_DWMAC_IPQ5018=m
  CONFIG_PCS_QCA_UNIPHY=y
  CONFIG_PTP_1588_CLOCK=m
)

MISSING_PTP=(
  CONFIG_STMMAC_ETH=y
  CONFIG_STMMAC_PLATFORM=y
  CONFIG_DWMAC_IPQ5018=y
  CONFIG_PCS_QCA_UNIPHY=y
  '# CONFIG_PTP_1588_CLOCK is not set'
)

expect "all symbols built in"                 0 "$(make_tree good "${BUILTIN[@]}")"
expect "demoted to =m by a modular PTP"       1 "$(make_tree modular "${MODULAR[@]}")"
expect "PTP absent"                           1 "$(make_tree noptp "${MISSING_PTP[@]}")"
expect "no kernel config in the tree"         1 "$tmp/empty"

if [[ "$failures" -gt 0 ]]; then
  echo "$failures test(s) failed"
  exit 1
fi
echo "all tests passed"
