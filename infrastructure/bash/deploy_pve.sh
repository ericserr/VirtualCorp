#!/usr/bin/env bash
# ============================================================
# VirtualCorp - Instal·lació desatesa de Proxmox VE a pve01
# ============================================================
# Ús:
#   deploy_pve.sh            crea pve01 si no existeix
#   FORCE=1 deploy_pve.sh    l'esborra i la torna a instal·lar
#   deploy_pve.sh --delete   esborra pve01
#
# pve01 és l'única màquina que NO surt d'un template Debian:
#   1. Descarrega (si cal) i verifica la ISO fixada de Proxmox VE.
#   2. Descarrega i verifica proxmox-auto-install-assistant (versió i
#      SHA256 fixats a configs/versions.env) i l'extreu amb dpkg-deb.
#   3. Genera answer.toml (hostname, IP estàtica, hash de la contrasenya
#      de root, claus SSH) i el hook first-boot.sh.
#   4. Crea la ISO desatesa amb "prepare-iso --fetch-from iso".
#   5. Crea la VM (recursos de .env, NIC única a "privada" amb MAC fixa,
#      COM1 a fitxer) i activa la virtualització anidada ABANS d'engegar-la.
#   6. Instal·la, espera "PVE-READY" pel port sèrie (l'escriu el hook en
#      la primera arrencada) i mostra el resultat de les comprovacions
#      de KVM i de connectivitat fetes des de dins de pve01.
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
source "$SCRIPT_DIR/iso_lib.sh"
source "$SCRIPT_DIR/vm_lib.sh"

FORCE="${FORCE:-0}"
PVE_MEMORY="${PVE_MEMORY:-8192}"
PVE_CPUS="${PVE_CPUS:-4}"
PVE_DISK_MB="${PVE_DISK_MB:-65536}"
PVE_CONFIG_DIR="${CONFIGS_DIR}/proxmox"
PVE_BUILD_DIR="${BUILD_DIR}/${PVE_VM_NAME}"
PVE_SERIAL="${PVE_BUILD_DIR}/serial.log"
PVE_AUTO_ISO="${PVE_BUILD_DIR}/${PVE_VM_NAME}-auto.iso"
AIA_DIR="${BUILD_DIR}/tools/proxmox-auto-install-assistant"
AIA_BIN="${AIA_DIR}/root/usr/bin/proxmox-auto-install-assistant"

# ---------- 2. Eina de preparació de la ISO ----------
aia_ensure() {
    # iso_ensure és genèrica: descàrrega reprenible + verificació SHA256.
    iso_ensure "proxmox-auto-install-assistant $PVE_AIA_VERSION" \
        "${AIA_DIR}/${PVE_AIA_DEB}" "$PVE_AIA_URL" "" "$PVE_AIA_SHA256"
    if [[ ! -x "$AIA_BIN" ]]; then
        rm -rf "${AIA_DIR}/root"
        dpkg-deb -x "${AIA_DIR}/${PVE_AIA_DEB}" "${AIA_DIR}/root"
    fi
    "$AIA_BIN" --version >/dev/null
}

# ---------- 3. answer.toml i hook ----------
render_files() {
    local hash auditor personal answer hook
    if [[ -z "${PVE_ROOT_PASSWORD:-}" ]]; then
        log_err "PVE_ROOT_PASSWORD no està definida a .env."
        exit 1
    fi
    hash="$(printf '%s' "$PVE_ROOT_PASSWORD" | openssl passwd -6 -stdin)"
    auditor="$(tr -d '\n' < "$AUDIT_PUB_KEY_FILE")"
    personal="$(tr -d '\n' < "$PERSONAL_PUB_KEY_FILE")"
    answer="${PVE_BUILD_DIR}/answer.toml"
    hook="${PVE_BUILD_DIR}/first-boot.sh"

    # Delimitador "|": no apareix ni al hash ni a les claus OpenSSH.
    sed -e "s|@@FQDN@@|${PVE_VM_NAME}.${VCORP_DOMAIN}|g" \
        -e "s|@@DOMAIN@@|${VCORP_DOMAIN}|g" \
        -e "s|@@ROOT_PASSWORD_HASH@@|${hash}|g" \
        -e "s|@@AUDITOR_KEY@@|${auditor}|g" \
        -e "s|@@PERSONAL_KEY@@|${personal}|g" \
        -e "s|@@CIDR@@|${PVE_CIDR}|g" \
        -e "s|@@GATEWAY@@|${PVE_GATEWAY}|g" \
        -e "s|@@DNS@@|${PVE_DNS}|g" \
        -e "s|@@MAC_FILTER@@|$(echo "$PVE_MAC" | tr 'A-F' 'a-f')|g" \
        "${PVE_CONFIG_DIR}/answer.toml.tpl" > "$answer"
    chmod 0600 "$answer"
    sed -e "s|@@PING_TARGETS@@|${PVE_PING_TARGETS}|g" \
        "${PVE_CONFIG_DIR}/first-boot.sh" > "$hook"

    if grep -nE '@@[A-Z_]+@@' "$answer" "$hook"; then
        log_err "Queden marcadors sense substituir."
        exit 1
    fi
    "$AIA_BIN" validate-answer "$answer"
}

# ---------- 4. ISO desatesa ----------
build_iso() {
    rm -f "$PVE_AUTO_ISO"
    log_info "Generant la ISO desatesa de Proxmox VE..."
    "$AIA_BIN" prepare-iso "$PVE_ISO_PATH" \
        --fetch-from iso \
        --answer-file "${PVE_BUILD_DIR}/answer.toml" \
        --on-first-boot "${PVE_BUILD_DIR}/first-boot.sh" \
        --output "$PVE_AUTO_ISO"
    # La ISO conté el hash de root: només llegible per l'usuari.
    chmod 0600 "$PVE_AUTO_ISO"
}

# ---------- 5. Màquina virtual ----------
create_vm() {
    local vm="$PVE_VM_NAME" vm_dir
    log_info "Creant la VM $vm (${PVE_MEMORY} MB, ${PVE_CPUS} vCPU, $((PVE_DISK_MB / 1024)) GB)"
    "$VBOXMANAGE_BIN" createvm --name "$vm" --ostype Debian_64 \
        --groups "$VM_SERVERS_GROUP" --register >/dev/null
    vm_dir="$(dirname "$("$VBOXMANAGE_BIN" showvminfo "$vm" --machinereadable \
        | sed -n 's/^CfgFile="\(.*\)"$/\1/p')")"

    : > "$PVE_SERIAL"
    "$VBOXMANAGE_BIN" modifyvm "$vm" \
        --memory "$PVE_MEMORY" --cpus "$PVE_CPUS" \
        --firmware bios --ioapic on --rtc-use-utc on \
        --hwvirtex on --nested-paging on \
        --graphicscontroller vmsvga --vram 16 \
        --audio-driver none --usb-ohci off --usb-ehci off --usb-xhci off \
        --boot1 disk --boot2 dvd --boot3 none --boot4 none \
        --nic1 intnet --intnet1 "$PVE_NET" --nic-type1 82540EM \
        --mac-address1 "$PVE_MAC" --cable-connected1 on \
        --uart1 0x3F8 4 --uart-mode1 file "$PVE_SERIAL" \
        --description "VirtualCorp delegació 25 - Proxmox VE $PVE_VERSION ($PVE_CIDR)"

    # Enunciat, apartat 6: després de crear la VM i abans d'engegar-la.
    if ! "$VBOXMANAGE_BIN" modifyvm "$vm" --nested-hw-virt on; then
        log_err "VirtualBox no permet activar la virtualització anidada (vegeu make check_host)."
        exit 1
    fi

    "$VBOXMANAGE_BIN" storagectl "$vm" --name SATA --add sata \
        --controller IntelAhci --portcount 2 --hostiocache on
    "$VBOXMANAGE_BIN" createmedium disk --filename "$vm_dir/${vm}.vdi" \
        --size "$PVE_DISK_MB" --format VDI --variant Standard >/dev/null
    "$VBOXMANAGE_BIN" storageattach "$vm" --storagectl SATA --port 0 \
        --device 0 --type hdd --medium "$vm_dir/${vm}.vdi"
    "$VBOXMANAGE_BIN" storageattach "$vm" --storagectl SATA --port 1 \
        --device 0 --type dvddrive --medium "$PVE_AUTO_ISO"
}

# ---------- 6. Instal·lació i validació ----------
install_and_check() {
    local vm="$PVE_VM_NAME" elapsed=0 result
    log_info "Instal·lant Proxmox VE $PVE_VERSION a $vm (pot trigar 10-20 min)..."
    "$VBOXMANAGE_BIN" startvm "$vm" --type headless >/dev/null

    # El disc buit no arrenca i la BIOS passa al DVD (instal·lador automàtic);
    # en reiniciar, el disc ja té GRUB i arrenca Proxmox.
    while ! grep -q 'PVE-READY' "$PVE_SERIAL" 2>/dev/null; do
        if [[ "$(vm_state "$vm")" != "running" ]]; then
            log_err "$vm s'ha aturat durant la instal·lació (estat: $(vm_state "$vm"))."
            exit 1
        fi
        if (( elapsed >= PVE_INSTALL_TIMEOUT )); then
            log_err "No s'ha rebut PVE-READY en $PVE_INSTALL_TIMEOUT s (vegeu $PVE_SERIAL)."
            exit 1
        fi
        sleep 15
        elapsed=$((elapsed + 15))
        (( elapsed % 300 == 0 )) && log_info "  instal·lació en curs ($((elapsed / 60)) min)..."
    done

    # La instal·lació ja ha acabat: es treu la ISO (conté el hash de root).
    "$VBOXMANAGE_BIN" storageattach "$vm" --storagectl SATA --port 1 \
        --device 0 --type dvddrive --medium emptydrive --forceunmount || true

    log_info "Resultat de les comprovacions dins de $vm:"
    tr -d '\r' < "$PVE_SERIAL" | grep -E '^(VCORP|PVE-READY)' | sed 's/^/    /'
    result="$(tr -d '\r' < "$PVE_SERIAL" | grep -m1 '^PVE-READY')"
    if [[ "$result" == *"kvm=fail"* ]]; then
        log_err "KVM no disposa de les extensions de virtualització (anidada no funcional)."
        exit 1
    fi
    if [[ "$result" == *"net=fail"* ]]; then
        log_warn "Algun ping ha fallat: comproveu que els quatre routers estan engegats."
    fi
    log_ok "$vm instal·lat: https://${PVE_CIDR%/*}:8006 (des de la xarxa privada)."
}

# ---------- Principal ----------
if [[ "${1:-}" == "--delete" ]]; then
    vm_delete "$PVE_VM_NAME"
    exit 0
fi

if vm_exists "$PVE_VM_NAME"; then
    if [[ "$FORCE" == "1" ]]; then
        log_info "FORCE=1: esborrant $PVE_VM_NAME"
        vm_delete "$PVE_VM_NAME"
    else
        log_info "$PVE_VM_NAME ja existeix (FORCE=1 per reinstal·lar-lo)."
        exit 0
    fi
fi

mkdir -p "$PVE_BUILD_DIR" "$AIA_DIR"
chmod 0700 "$PVE_BUILD_DIR"
iso_ensure "Proxmox VE $PVE_VERSION" "$PVE_ISO_PATH" \
    "$PVE_ISO_URL" "${PVE_ISO_MIRROR_URL:-}" "$PVE_ISO_SHA256"
aia_ensure
render_files
build_iso
create_vm
install_and_check
