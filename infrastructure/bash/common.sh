#!/usr/bin/env bash

VBOXMANAGE_BIN="${VBOXMANAGE_BIN:-$(command -v VBoxManage 2>/dev/null || command -v vboxmanage 2>/dev/null || true)}"
if [ -z "$VBOXMANAGE_BIN" ]; then
    echo "Error: VBoxManage no està instal·lat o no es troba al PATH del sistema." >&2
    exit 1
fi

VBOX_ROOT_GROUP="${VBOX_ROOT_GROUP:-/VirtualCorp}"
VM_ROUTERS_GROUP="${VM_ROUTERS_GROUP:-$VBOX_ROOT_GROUP/Routers}"
VM_TEMPLATES_GROUP="${VM_TEMPLATES_GROUP:-$VBOX_ROOT_GROUP/templates}"
VM_SERVERS_GROUP="${VM_SERVERS_GROUP:-$VBOX_ROOT_GROUP/Servers}"
VM_PRINTERS_GROUP="${VM_PRINTERS_GROUP:-$VBOX_ROOT_GROUP/Printers}"
VM_DESKTOPS_GROUP="${VM_DESKTOPS_GROUP:-$VBOX_ROOT_GROUP/Desktops}"


ROUTEROS_VERSION="${ROUTEROS_VERSION:-7.21.4}"
ROUTEROS_VDI_FILENAME="${ROUTEROS_VDI_FILENAME:-chr-${ROUTEROS_VERSION}.vdi}"
URL="${ROUTEROS_URL:-https://download.mikrotik.com/routeros/${ROUTEROS_VERSION}/${ROUTEROS_VDI_FILENAME}.zip}"

ROUTER_MEMORY=256
ROUTER_CPU=1

COMMON_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$COMMON_DIR/../.." && pwd)}"
ARTIFACTS_DIR="${ARTIFACTS_DIR:-${PROJECT_ROOT}/artifacts/images/chr}"
CONFIGS_DIR="${CONFIGS_DIR:-${PROJECT_ROOT}/configs}"
SSH_PUBLIC_KEY_DIR="${SSH_PUBLIC_KEY_DIR:-${CONFIGS_DIR}/ssh}"
SSH_PRIVATE_KEY_DIR="${SSH_PRIVATE_KEY_DIR:-${HOME}/.ssh}"
ROUTEROS_VDI_PATH="${ROUTEROS_VDI_PATH:-${ARTIFACTS_DIR}/${ROUTEROS_VDI_FILENAME}}"

VM_NAME="routeros_template"
BOX_NAME="${ROUTEROS_BOX_NAME:-routeros-base}"
BOX_FILE="${ROUTEROS_BOX_FILE:-${ARTIFACTS_DIR}/${BOX_NAME}.box}"

SSH_PORT=2222
SSH_USER=sysadmin

AUDIT_PRIVATE_KEY_FILE="${SSH_PRIVATE_KEY_DIR}/vcorp_auditor"
AUDIT_PUB_KEY_FILE="${SSH_PUBLIC_KEY_DIR}/vcorp_auditor.pub"
SYSADMIN_PRIVATE_KEY_FILE="${SSH_PRIVATE_KEY_DIR}/vcorp_sysadmin"
SYSADMIN_PUB_KEY_FILE="${SSH_PUBLIC_KEY_DIR}/vcorp_sysadmin.pub"

# Colors ANSI
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_ok() {
    echo -e "${GREEN}[ OK ]${NC} $*"
}

log_err() {
    echo -e "${RED}[ERROR]${NC} $*"
}

# Diversos scripts (wait_ssh, router_base.sh) criden log_error: alias de log_err.
log_error() {
    log_err "$@"
}

# ============================================================
# Activitat 2: templates Debian, equips i Proxmox VE
# ============================================================

# Versions fixades (fitxer versionat). Es carrega sempre, també quan
# els scripts s'executen sense passar pel Makefile.
VERSIONS_FILE="${VERSIONS_FILE:-${CONFIGS_DIR}/versions.env}"
if [[ -f "$VERSIONS_FILE" ]]; then
    # shellcheck source=../../configs/versions.env
    source "$VERSIONS_FILE"
else
    log_err "No s'ha trobat el fitxer de versions '$VERSIONS_FILE'."
    exit 1
fi

# Directoris d'artefactes locals (ignorats per Git).
# No depenen d'ARTIFACTS_DIR perquè el seu valor per defecte difereix entre
# .env i aquest fitxer (llegat de l'activitat 1).
ISO_DIR="${ISO_DIR:-${PROJECT_ROOT}/artifacts/images/iso}"
BUILD_DIR="${BUILD_DIR:-${PROJECT_ROOT}/artifacts/build}"
DEBIAN_ISO_PATH="${ISO_DIR}/${DEBIAN_ISO_FILENAME}"
PVE_ISO_PATH="${ISO_DIR}/${PVE_ISO_FILENAME}"

# Configuració dels templates Debian
DEBIAN_CONFIG_DIR="${CONFIGS_DIR}/debian"
VCORP_DOMAIN="${VCORP_DOMAIN:-del25.virtualcorp.internal}"
VM_LOCALE="${VM_LOCALE:-en_US.UTF-8}"
VM_KEYMAP="${VM_KEYMAP:-es}"
VM_TIMEZONE="${VM_TIMEZONE:-Europe/Madrid}"

TPL_SERVER_NAME="${TPL_SERVER_NAME:-tpl-debian-server}"
TPL_DESKTOP_NAME="${TPL_DESKTOP_NAME:-tpl-debian-desktop}"
TPL_SNAPSHOT="${TPL_SNAPSHOT:-base}"
TPL_INSTALL_TIMEOUT="${TPL_INSTALL_TIMEOUT:-5400}"

# Claus públiques autoritzades a l'usuari sysadmin de totes les màquines:
# clau del professor + clau personal de l'alumne.
PERSONAL_PUB_KEY_FILE="${PERSONAL_PUB_KEY_FILE:-${SYSADMIN_PUB_KEY_FILE}}"
PERSONAL_PRIVATE_KEY_FILE="${PERSONAL_PRIVATE_KEY_FILE:-${SYSADMIN_PRIVATE_KEY_FILE}}"

wait_ssh() {
    local ip="${1:-127.0.0.1}"
    local port="${2:-22}"
    local max_wait="${3:-60}"
    local elapsed=0
    local interval=5

    log_info "Esperant servei SSH a ${ip}:${port} (màx ${max_wait}s)..."

    while [ "$elapsed" -lt "$max_wait" ]; do
        # ssh-keyscan valida que el dimoni SSH estigui actiu i responent
        if ssh-keyscan -p "$port" "$ip" >/dev/null 2>&1; then
            log_info "SSH disponible a ${ip}:${port}!"
            return 0
        fi

        sleep "$interval"
        elapsed=$((elapsed + interval))
    done

    log_error "Timeout: SSH no disponible a ${ip}:${port} després de ${max_wait}s."
    return 1
}

# ---------- pve01 (Proxmox VE) ----------
# Adreçament fixat pel projecte (apartat 4.3): 10.xx.0.133 a la zona
# privada 10.25.0.128/26; porta d'enllaç = router0 a la privada.
PVE_VM_NAME="${PVE_VM_NAME:-pve01}"
PVE_NET="${PVE_NET:-privada}"
PVE_CIDR="${PVE_CIDR:-10.25.0.133/26}"
PVE_GATEWAY="${PVE_GATEWAY:-10.25.0.129}"
# Encara no hi ha DNS propi: es fa servir un resolutor públic (via NAT de
# router0) fins que es desplegui el servei DNS de la delegació.
PVE_DNS="${PVE_DNS:-1.1.1.1}"
# MAC fixa (08:00:27 = VirtualBox; 25 = delegació; 01:33 = .133): permet
# que answer.toml seleccioni la NIC sense dependre del nom d'interfície.
PVE_MAC="${PVE_MAC:-080027250133}"
# Una IP de cada router (la més propera a pve01) + una IP pública.
PVE_PING_TARGETS="${PVE_PING_TARGETS:-router0=10.25.0.129 router1=10.25.0.226 router2=10.25.0.230 router3=10.25.0.234 internet=1.1.1.1}"
PVE_INSTALL_TIMEOUT="${PVE_INSTALL_TIMEOUT:-3600}"
