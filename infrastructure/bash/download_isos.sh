#!/usr/bin/env bash
# ============================================================
# VirtualCorp - Descàrrega i verificació de les ISO fixades
# ============================================================
# Ús: download_isos.sh [debian|pve|all]   (per defecte: all)
#
# Les versions, URL i SHA256 són a configs/versions.env.
# Les ISO es desen a ISO_DIR (artifacts/images/iso, ignorat per Git).
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
source "$SCRIPT_DIR/iso_lib.sh"

for tool in curl sha256sum; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        log_err "Falta l'eina '$tool' a l'amfitrió."
        exit 1
    fi
done

target="${1:-all}"
rc=0

if [[ "$target" == "debian" || "$target" == "all" ]]; then
    iso_ensure "Debian $DEBIAN_VERSION" "$DEBIAN_ISO_PATH" \
        "$DEBIAN_ISO_URL" "${DEBIAN_ISO_MIRROR_URL:-}" "$DEBIAN_ISO_SHA256" || rc=1
fi

if [[ "$target" == "pve" || "$target" == "all" ]]; then
    iso_ensure "Proxmox VE $PVE_VERSION" "$PVE_ISO_PATH" \
        "$PVE_ISO_URL" "${PVE_ISO_MIRROR_URL:-}" "$PVE_ISO_SHA256" || rc=1
fi

case "$target" in
    debian|pve|all) ;;
    *) log_err "Argument desconegut '$target' (useu debian, pve o all)."; exit 2 ;;
esac

exit "$rc"
