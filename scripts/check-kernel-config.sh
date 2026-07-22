#!/usr/bin/env bash
# Assert that the AX55 ethernet symbols came out built-in (=y) in the kernel
# configuration OpenWrt generated for ipq50xx.
#
# Every symbol here has to be =y, not =m. kconfig will happily demote a
# tristate to =m when a dependency is modular and say nothing about it; the
# build then succeeds and produces an image with no eth0. That is exactly how
# CONFIG_PTP_1588_CLOCK went missing: STMMAC_ETH depends on
# PTP_1588_CLOCK_OPTIONAL, which follows PTP_1588_CLOCK down to =m in any
# build that pulls in kmod-ptp.
#
# Usage: check-kernel-config.sh <openwrt_dir>
# Exit:  0 = all symbols built-in, 1 = at least one missing or modular

set -euo pipefail

openwrt="${1:?usage: check-kernel-config.sh <openwrt_dir>}"

cfg="$(find "$openwrt/build_dir" -path "*linux-qualcommax_ipq50xx/linux-*/.config" | head -1)"
[[ -n "$cfg" ]] || { echo "::error::no kernel .config under $openwrt/build_dir"; exit 1; }
echo "kernel config: $cfg"

SYMBOLS=(
  CONFIG_STMMAC_ETH
  CONFIG_STMMAC_PLATFORM
  CONFIG_DWMAC_IPQ5018
  CONFIG_PCS_QCA_UNIPHY
  CONFIG_PTP_1588_CLOCK
)

rc=0
for sym in "${SYMBOLS[@]}"; do
  value="$(sed -n "s/^${sym}=//p" "$cfg")"
  case "$value" in
    y)  printf '  %-24s =y\n' "$sym" ;;
    m)  printf '  %-24s =m  <-- demoted to a module\n' "$sym"
        echo "::error::$sym is =m, expected =y (the image will have no eth0)"
        rc=1 ;;
    "") printf '  %-24s absent\n' "$sym"
        echo "::error::$sym is not set in the built kernel config"
        rc=1 ;;
    *)  printf '  %-24s =%s\n' "$sym" "$value"
        echo "::error::$sym has unexpected value '$value'"
        rc=1 ;;
  esac
done

exit "$rc"
