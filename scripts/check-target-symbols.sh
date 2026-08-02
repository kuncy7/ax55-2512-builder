#!/usr/bin/env bash
# Assert that every Kconfig symbol our patch set introduces is answered in the
# SHARED target config (config-<version>), not only in ipq50xx/config-default.
#
# Why this exists: patches under target/linux/<target>/patches-* apply to EVERY
# subtarget of that target, so the symbols they add exist everywhere. Answer one
# only in ipq50xx/config-default and a build of ipq807x or ipq60xx meets a new,
# visible, unanswered symbol during syncconfig - kconfig turns interactive and
# dies on EOF, failing the build with no useful message. Our CI builds ipq50xx
# only and structurally cannot see this; a downstream builder of all subtargets
# hit it on 2026-08-01 (PCS_QCA_UNIPHY), with DWMAC_IPQ5018 one line behind.
#
# The list is explicit rather than scanned from the patches on purpose: upstream
# patches introduce symbols that are unanswered for ipq50xx as well (e.g.
# REGULATOR_CPR3_NPU) and are harmless because their dependencies are unmet, so
# kconfig never prompts. Scanning would drown a real failure in false alarms.
#
# Usage: check-target-symbols.sh <openwrt_dir> <symbol_list_file> [target]
# Exit:  0 = all answered, 1 = at least one missing, 2 = usage/setup error

set -euo pipefail

# shellcheck source=scripts/lib/log.sh
source "$(dirname -- "$0")/lib/log.sh"

openwrt="${1:?usage: check-target-symbols.sh <openwrt_dir> <symbol_list_file> [target]}"
list="${2:?symbol list file required}"
target="${3:-qualcommax}"

[[ -d "$openwrt" ]] || { log::error "no such directory: $openwrt"; exit 2; }
[[ -f "$list" ]] || { log::error "no such symbol list: $list"; exit 2; }

mapfile -t symbols < <(grep -vE '^\s*(#|$)' "$list" | awk '{print $1}')
((${#symbols[@]})) || { log::info "symbol list is empty, nothing to check"; exit 0; }

cd "$openwrt"

shopt -s nullglob
configs=("target/linux/$target"/config-*)
((${#configs[@]})) || { log::error "no target/linux/$target/config-* found"; exit 2; }

log::info "Checking ${#symbols[@]} owned symbol(s) against ${#configs[@]} shared config(s)"

rc=0
for cfg in "${configs[@]}"; do
  for s in "${symbols[@]}"; do
    if grep -qE "^(# )?CONFIG_${s}( is not set|=)" "$cfg"; then
      printf '    %-34s answered in %s\n' "$s" "${cfg##*/}"
    else
      printf '    %-34s MISSING  in %s\n' "$s" "${cfg##*/}"
      log::error "CONFIG_$s is introduced by our patches but unanswered in $cfg"
      rc=1
    fi
  done
done

((rc)) && log::die "add '# CONFIG_<symbol> is not set' to the shared config, or drop the symbol from $list"

log::info "OK - every owned symbol is answered in every shared config"
