#!/usr/bin/env bash
# Prepare an OpenWrt source tree for the AX55 v1 build:
#   - fetch the published patch + BDFs from the sources repo (SOURCES_*)
#   - apply the patch with git apply (atomic: any rejected hunk fails the run)
#   - drop the BDFs into package/firmware/ipq-wifi/files/
#   - assert the ethernet symbols actually landed in config-default
#   - apply local patches from $BUILDER_REPO/patches/*.patch (if any)
#   - feeds update/install, device .config, defconfig
#
# Required env:
#   OPENWRT_DIR      path to checked-out OpenWrt source
#   BUILDER_REPO     path to this repo
#   DEVICE_DIR       path to devices/<id>/  (relative to BUILDER_REPO)
#   SOURCES_REPO     e.g. kuncy7/openwrt-ax55-v1
#   SOURCES_SHA      commit to fetch the patch set from
#   SOURCES_DIR      directory inside the sources repo, e.g. src-2512
#
# Optional env:
#   FEEDS_LINES      newline-separated `src-git <name> <url>` lines (may be empty)
#   COMMON_FILES     path to common/files (default: $BUILDER_REPO/common/files)

set -euo pipefail

# shellcheck source=scripts/lib/log.sh
source "$(dirname -- "$0")/lib/log.sh"

: "${OPENWRT_DIR:?OPENWRT_DIR required}"
: "${BUILDER_REPO:?BUILDER_REPO required}"
: "${DEVICE_DIR:?DEVICE_DIR required}"
: "${SOURCES_REPO:?SOURCES_REPO required}"
: "${SOURCES_SHA:?SOURCES_SHA required}"
: "${SOURCES_DIR:?SOURCES_DIR required}"

COMMON_FILES="${COMMON_FILES:-$BUILDER_REPO/common/files}"

cd "$OPENWRT_DIR"

# 1. Fetch the published AX55 patch set (exactly what a downstream builder
#    gets). In branch mode (SOURCES_PATCH=none) the upstream branch already
#    carries the AX55 support, so only the BDFs are fetched.
srcbase="https://raw.githubusercontent.com/${SOURCES_REPO}/${SOURCES_SHA}/${SOURCES_DIR}"
fetch() {
  local name="$1" out="$2"
  log::info "  fetching $name"
  curl -fsSL --retry 3 -o "$out" "$srcbase/$name"
}

tmp="$(mktemp -d)"
fetch "board-tplink_ax55v1.ipq5018"     "$tmp/board-tplink_ax55v1.ipq5018"
fetch "board-tplink_ax55v1.qcn6122"     "$tmp/board-tplink_ax55v1.qcn6122"

if [[ "${SOURCES_PATCH:-full}" == "none" ]]; then
  log::info "sources.patch=none: skipping full.patch (AX55 support comes from the upstream branch)"
else
  log::info "Fetching AX55 patch set from ${SOURCES_REPO}@${SOURCES_SHA}/${SOURCES_DIR}"
  fetch "ax55-v1-openwrt-2512-full.patch" "$tmp/full.patch"

  # 2. Apply the patch. git apply is atomic: if any hunk does not apply the
  #    whole run fails here, loudly, instead of building a broken image.
  log::info "Applying ax55-v1-openwrt-2512-full.patch (git apply --check first)"
  git apply --check "$tmp/full.patch"
  git apply "$tmp/full.patch"
fi

# 3. Board data files.
log::info "Installing BDFs into package/firmware/ipq-wifi/files/"
mkdir -p package/firmware/ipq-wifi/files
cp "$tmp/board-tplink_ax55v1.ipq5018" package/firmware/ipq-wifi/files/
cp "$tmp/board-tplink_ax55v1.qcn6122" package/firmware/ipq-wifi/files/
md5sum package/firmware/ipq-wifi/files/board-tplink_ax55v1.*

# 4. Fail fast if the ethernet symbols did not land where the kernel build
#    will read them. This is the exact failure mode seen downstream: image
#    builds fine, but without stmmac/DWMAC the switch has no conduit.
#    Layouts differ: the 25.12 patch set puts the symbols in the ipq50xx
#    subtarget config-default, the openwrt-main branch keeps some (PCS) in
#    the shared per-kernel qualcommax configs — accept either, but a shared
#    config only counts if EVERY kernel version has the symbol, so a 6.18
#    regression cannot hide behind a healthy 6.12 line. The built kernel
#    .config is verified again after the build by check-kernel-config.sh.
log::info "Asserting ethernet symbols in the target kernel configs"
for sym in CONFIG_DWMAC_IPQ5018=y CONFIG_STMMAC_ETH=y CONFIG_PCS_QCA_UNIPHY=y; do
  if grep -q "^$sym" target/linux/qualcommax/ipq50xx/config-default; then
    continue
  fi
  in_all=1
  for cfg in target/linux/qualcommax/config-*; do
    grep -q "^$sym" "$cfg" || in_all=0
  done
  [[ "$in_all" == 1 ]] \
    || log::die "missing $sym in ipq50xx/config-default and not present in every qualcommax config-*"
done
log::info "  OK: DWMAC/STMMAC/PCS present in the target kernel configs"

# 5. Local patches (builder-specific extras, e.g. an overclock experiment).
patches_dir="$BUILDER_REPO/patches"
if compgen -G "$patches_dir/*.patch" >/dev/null; then
  log::info "Applying local patches from $patches_dir"
  while IFS= read -r patch; do
    log::info "  $patch"
    git apply --verbose "$patch"
  done < <(find "$patches_dir" -maxdepth 1 -type f -name '*.patch' | sort)
else
  log::info "No local patches."
fi

# 6. Feeds.
[[ -f feeds.conf ]] || cp feeds.conf.default feeds.conf
if [[ -n "${FEEDS_LINES:-}" ]]; then
  log::info "Appending custom feeds:"
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    log::info "  $line"
    # Idempotent: a plain append duplicates every custom feed when the
    # script is re-run over an existing tree (adopted from Julius's
    # Qualcommax_NSS_Builder).
    grep -qxF "$line" feeds.conf || echo "$line" >>feeds.conf
  done <<<"$FEEDS_LINES"
fi

log::info "Updating feeds"
./scripts/feeds update -a
log::info "Installing packages from feeds"
./scripts/feeds install -a

# 7. Device .config and resolve.
log::info "Loading device config: $DEVICE_DIR/config"
cp "$BUILDER_REPO/$DEVICE_DIR/config" .config

# Optional fragment appended on top of the device config, used by the guard
# build to reproduce a downstream configuration (see devices/*/config.*).
if [[ -n "${CONFIG_FRAGMENT:-}" ]]; then
  frag="$BUILDER_REPO/$DEVICE_DIR/$CONFIG_FRAGMENT"
  [[ -f "$frag" ]] || log::die "CONFIG_FRAGMENT=$CONFIG_FRAGMENT not found at $frag"
  log::info "Appending config fragment: $CONFIG_FRAGMENT"
  cat "$frag" >>.config
fi

make defconfig

# Assert defconfig kept the device profile (a wrong symbol name silently
# falls back to the first device in the target list).
grep -q '^CONFIG_TARGET_qualcommax_ipq50xx_DEVICE_tplink_archer-ax55-v1=y' .config \
  || log::die "device profile lost after defconfig (check devices/*/config symbol names)"

# Until ethernet is proven on a given image, WiFi is the only access path to
# this board. defconfig silently demotes the BDF package to =m when the
# package would build empty (BDFs missing), so pin it and fail loudly.
grep -q '^CONFIG_PACKAGE_ipq-wifi-tplink_ax55v1=y' .config \
  || log::die "ipq-wifi-tplink_ax55v1 not built-in after defconfig (BDFs missing?)"

# Generic sweep over everything the seed (and fragment) requested: kconfig
# silently drops a symbol whose dependencies are unmet, and a build that
# quietly leaves a package out is worse than one that stops. Only
# requested-on symbols are asserted - a requested "=n" legitimately comes
# back on when another selected package depends on it. (Adopted from
# Julius's Qualcommax_NSS_Builder.)
log::info "Verifying defconfig kept the requested symbols"
seed_files=("$BUILDER_REPO/$DEVICE_DIR/config")
[[ -n "${CONFIG_FRAGMENT:-}" ]] && seed_files+=("$BUILDER_REPO/$DEVICE_DIR/$CONFIG_FRAGMENT")
dropped=()
while IFS= read -r req; do
  grep -qxF "$req" .config || dropped+=("$req")
done < <(cat "${seed_files[@]}" | grep -E '^CONFIG_[A-Za-z0-9_-]+=' | grep -vE '=n$')

if ((${#dropped[@]})); then
  log::error "defconfig dropped ${#dropped[@]} requested symbol(s):"
  printf '  %s\n' "${dropped[@]}" >&2
  log::die "add the missing dependency or remove the line - do not ship a silently reduced image"
fi

# 8. Overlay files (common first, then device-specific so device wins).
log::info "Applying overlay files"
mkdir -p files
if [[ -d "$COMMON_FILES" ]]; then
  rsync -a "$COMMON_FILES/" files/
fi
if [[ -d "$BUILDER_REPO/$DEVICE_DIR/files" ]]; then
  rsync -a "$BUILDER_REPO/$DEVICE_DIR/files/" files/
fi

log::info "Build environment ready."
