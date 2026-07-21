#!/usr/bin/env bash
# Parse builder.yml and emit GitHub Actions outputs.
#
# Required env (set by the workflow):
#   GITHUB_OUTPUT  path to outputs file (when running in Actions)
#
# Optional env:
#   BUILDER_YML    path to builder.yml (default: ./builder.yml)
#
# Outputs (when GITHUB_OUTPUT is set):
#   upstream_repo, upstream_branch
#   sources_repo, sources_branch, sources_dir
#   device, device_dir
#   feeds_lines           (newline-separated `src-git <name> <url>` lines)
#   release_prefix, release_keep, artifact_retention_days

set -euo pipefail

# shellcheck source=scripts/lib/log.sh
source "$(dirname -- "$0")/lib/log.sh"

BUILDER_YML="${BUILDER_YML:-builder.yml}"

[[ -f "$BUILDER_YML" ]] || log::die "$BUILDER_YML not found"
command -v yq >/dev/null || log::die "yq is required (install via apt or actions setup)"

upstream_repo="$(yq -r '.upstream.repo' "$BUILDER_YML")"
upstream_branch="$(yq -r '.upstream.branch' "$BUILDER_YML")"
sources_repo="$(yq -r '.sources.repo' "$BUILDER_YML")"
sources_branch="$(yq -r '.sources.branch' "$BUILDER_YML")"
sources_dir="$(yq -r '.sources.dir' "$BUILDER_YML")"
device="$(yq -r '.device' "$BUILDER_YML")"
release_prefix="$(yq -r '.release.prefix' "$BUILDER_YML")"
release_keep="$(yq -r '.release.keep' "$BUILDER_YML")"
artifact_retention_days="$(yq -r '.release.artifact_retention_days' "$BUILDER_YML")"

# Validate device directory exists.
device_dir="devices/$device"
[[ -d "$device_dir" ]] || log::die "$device_dir not found (referenced by .device in $BUILDER_YML)"
[[ -f "$device_dir/config" ]] || log::die "$device_dir/config not found"

# Build feeds_lines as newline-separated `src-git <name> <url>` (may be empty).
feeds_lines="$(yq -r '.feeds[] | "src-git " + .name + " " + .url' "$BUILDER_YML" 2>/dev/null || true)"

log::info "upstream:    $upstream_repo@$upstream_branch"
log::info "sources:     $sources_repo@$sources_branch ($sources_dir)"
log::info "device:      $device  ($device_dir)"
log::info "release:     prefix=$release_prefix keep=$release_keep retention=${artifact_retention_days}d"

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    echo "upstream_repo=$upstream_repo"
    echo "upstream_branch=$upstream_branch"
    echo "sources_repo=$sources_repo"
    echo "sources_branch=$sources_branch"
    echo "sources_dir=$sources_dir"
    echo "device=$device"
    echo "device_dir=$device_dir"
    echo "release_prefix=$release_prefix"
    echo "release_keep=$release_keep"
    echo "artifact_retention_days=$artifact_retention_days"
    echo "feeds_lines<<__EOF__"
    echo "$feeds_lines"
    echo "__EOF__"
  } >>"$GITHUB_OUTPUT"
fi
