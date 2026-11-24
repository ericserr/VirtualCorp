#!/usr/bin/env bash
# ============================================================
# VirtualCorp - Creació dels templates Debian Server i Desktop
# ============================================================
# Ús:
#   create_templates.sh [server|desktop|all]      (per defecte: all)
#   FORCE=1 create_templates.sh ...                 refà els existents
#   create_templates.sh --delete [server|desktop|all]
#
# Procés per a cada template (tot desatès):
#   1. Genera la ISO desatesa (preseed + claus + scripts) amb xorriso.
#   2. Crea la VM amb una NIC NAT TEMPORAL (cal Internet per baixar
#      paquets) i COM1 redirigit a un fitxer.
#   3. Instal·la Debian; l'instal·lador apaga la VM en acabar.
#   4. Arrenca des del disc, espera VCORP-READY i valida per SSH
#      (amb la clau personal) els requisits de l'enunciat.
#   5. Segella (claus de host, machine-id...) i apaga.
#   6. Treu la NIC NAT (només router0 pot tenir NAT) i fa la
#      instantània "base", que és d'on surten els clons enllaçats.
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
source "$SCRIPT_DIR/iso_lib.sh"
source "$SCRIPT_DIR/vm_lib.sh"
source "$SCRIPT_DIR/template_base.sh"

# Recursos de construcció (els clons els ajusten després).
TPL_SERVER_MEMORY="${TPL_SERVER_MEMORY:-1024}"
TPL_DESKTOP_MEMORY="${TPL_DESKTOP_MEMORY:-2048}"
TPL_CPUS="${TPL_CPUS:-2}"
TPL_DISK_MB="${TPL_DISK_MB:-20480}"
TPL_SERVER_SSH_PORT="${TPL_SERVER_SSH_PORT:-2210}"
TPL_DESKTOP_SSH_PORT="${TPL_DESKTOP_SSH_PORT:-2211}"
TPL_BOOT_TIMEOUT="${TPL_BOOT_TIMEOUT:-600}"

tpl_ssh_port() {
    case "$1" in
        server)  echo "$TPL_SERVER_SSH_PORT" ;;
        desktop) echo "$TPL_DESKTOP_SSH_PORT" ;;
    esac
}

# ---------- 2. Creació de la VM ----------
tpl_create_vm() {
    local role="$1" iso="$2"
    local vm memory port vm_dir serial
    vm="$(tpl_vm_name "$role")"
    port="$(tpl_ssh_port "$role")"
    [[ "$role" == "desktop" ]] && memory="$TPL_DESKTOP_MEMORY" || memory="$TPL_SERVER_MEMORY"
    serial="${BUILD_DIR}/${role}/serial.log"

    log_info "Creant la VM $vm"
    "$VBOXMANAGE_BIN" createvm --name "$vm" --ostype Debian_64 \
        --groups "$VM_TEMPLATES_GROUP" --register >/dev/null

    vm_dir="$(dirname "$("$VBOXMANAGE_BIN" showvminfo "$vm" --machinereadable \
        | sed -n 's/^CfgFile="\(.*\)"$/\1/p')")"

    : > "$serial"
    "$VBOXMANAGE_BIN" modifyvm "$vm" \
        --memory "$memory" --cpus "$TPL_CPUS" \
        --firmware bios --ioapic on --rtc-use-utc on \
        --graphicscontroller vmsvga --vram 16 \
        --audio-driver none --usb-ohci off --usb-ehci off --usb-xhci off \
        --boot1 disk --boot2 dvd --boot3 none --boot4 none \
        --nic1 nat --nic-type1 82540EM --cable-connected1 on \
        --natpf1 "ssh,tcp,127.0.0.1,${port},,22" \
        --uart1 0x3F8 4 --uart-mode1 file "$serial"

    "$VBOXMANAGE_BIN" storagectl "$vm" --name SATA --add sata \
        --controller IntelAhci --portcount 2 --hostiocache on
    "$VBOXMANAGE_BIN" createmedium disk --filename "$vm_dir/${vm}.vdi" \
        --size "$TPL_DISK_MB" --format VDI --variant Standard >/dev/null
    "$VBOXMANAGE_BIN" storageattach "$vm" --storagectl SATA --port 0 \
        --device 0 --type hdd --medium "$vm_dir/${vm}.vdi"
    "$VBOXMANAGE_BIN" storageattach "$vm" --storagectl SATA --port 1 \
        --device 0 --type dvddrive --medium "$iso"
}

# ---------- 4. Validació per SSH ----------
tpl_validate() {
    local role="$1" port="$2"
    local ok=0

    log_info "Validant el template per SSH (clau personal)..."
    vm_ssh "$port" true || { log_err "No s'hi pot accedir per SSH amb la clau personal."; return 1; }

    vm_ssh "$port" 'grep -qF "$(cat)" ~/.ssh/authorized_keys' < "$AUDIT_PUB_KEY_FILE" \
        && log_ok "Clau del professor autoritzada." \
        || { log_err "Falta la clau del professor."; ok=1; }
    vm_ssh "$port" 'sudo -n true' \
        && log_ok "sysadmin té sudo." || { log_err "sysadmin no té sudo."; ok=1; }
    vm_ssh "$port" 'grep -rqs "iface .* inet dhcp" /etc/network/interfaces /etc/network/interfaces.d' \
        && log_ok "Xarxa per DHCP." || { log_err "La xarxa no és DHCP."; ok=1; }

    if [[ "$role" == "desktop" ]]; then
        vm_ssh "$port" 'dpkg -s lxqt-core falkon sddm >/dev/null 2>&1' \
            && log_ok "LXQt, SDDM i Falkon instal·lats." \
            || { log_err "Falten paquets d'escriptori."; ok=1; }
        if vm_ssh "$port" 'dpkg -l | grep -qE "^ii +(firefox|libreoffice)"'; then
            log_err "Hi ha Firefox o LibreOffice instal·lats."; ok=1
        else
            log_ok "Sense Firefox ni ofimàtica."
        fi
    else
        if vm_ssh "$port" 'dpkg -l | grep -qE "^ii +xserver-xorg-core"'; then
            log_err "El template server té entorn gràfic."; ok=1
        else
            log_ok "Sense entorn gràfic."
        fi
    fi
    return "$ok"
}

# ---------- Construcció completa d'un template ----------
build_template() {
    local role="$1"
    local vm port iso serial
    vm="$(tpl_vm_name "$role")"
    port="$(tpl_ssh_port "$role")"
    serial="${BUILD_DIR}/${role}/serial.log"

    if vm_exists "$vm"; then
        if [[ "${FORCE:-}" == "1" ]]; then
            log_warn "FORCE=1: s'esborra el template existent $vm."
            vm_delete "$vm" || {
                log_err "No es pot esborrar $vm (té clons enllaçats?). Esborreu primer els clons."
                return 1
            }
        else
            log_ok "El template $vm ja existeix (FORCE=1 per refer-lo)."
            return 0
        fi
    fi

    log_info "===== Template $role ($vm) ====="
    iso="$(tpl_build_iso "$role")"
    tpl_create_vm "$role" "$iso"

    # 3. Instal·lació desatesa
    log_info "Instal·lant Debian $DEBIAN_VERSION (pot trigar una bona estona)..."
    "$VBOXMANAGE_BIN" startvm "$vm" --type headless >/dev/null
    vm_wait_poweroff "$vm" "$TPL_INSTALL_TIMEOUT"
    log_ok "Instal·lació acabada."

    # 4. Primera arrencada i validació
    "$VBOXMANAGE_BIN" storageattach "$vm" --storagectl SATA --port 1 \
        --device 0 --type dvddrive --medium emptydrive
    : > "$serial"
    "$VBOXMANAGE_BIN" startvm "$vm" --type headless >/dev/null
    vm_wait_ready "$vm" "$serial" "$TPL_BOOT_TIMEOUT"
    log_ok "$vm ha arrencat (VCORP-READY)."
    if ! tpl_validate "$role" "$port"; then
        log_err "La validació de $vm ha fallat; la VM es deixa engegada per revisar-la (ssh -p $port sysadmin@127.0.0.1)."
        return 1
    fi

    # 5. Segellat
    log_info "Segellant el template..."
    vm_ssh "$port" 'sudo /usr/local/sbin/vcorp-seal' || true
    vm_wait_poweroff "$vm" 180

    # 6. Sense NAT i instantània base
    "$VBOXMANAGE_BIN" modifyvm "$vm" --natpf1 delete ssh
    "$VBOXMANAGE_BIN" modifyvm "$vm" --nic1 intnet --intnet1 unused --cable-connected1 off
    "$VBOXMANAGE_BIN" modifyvm "$vm" --uart-mode1 disconnected
    "$VBOXMANAGE_BIN" snapshot "$vm" take "$TPL_SNAPSHOT" \
        --description "Template $role segellat (Debian $DEBIAN_VERSION)" >/dev/null
    log_ok "Template $vm creat amb la instantània '$TPL_SNAPSHOT'."
}

# ---------- Principal ----------
roles_for() {
    case "${1:-all}" in
        server|desktop) echo "$1" ;;
        all) echo "server desktop" ;;
        *) log_err "Ús: $0 [--delete] [server|desktop|all]"; exit 1 ;;
    esac
}

if [[ "${1:-}" == "--delete" ]]; then
    for role in $(roles_for "${2:-all}"); do
        vm="$(tpl_vm_name "$role")"
        if vm_exists "$vm"; then
            log_info "Esborrant $vm"
            vm_delete "$vm" || { log_err "No s'ha pogut esborrar $vm (té clons enllaçats?)."; exit 1; }
        fi
    done
    exit 0
fi

iso_ensure "Debian" "$DEBIAN_ISO_PATH" "$DEBIAN_ISO_URL" \
    "${DEBIAN_ISO_MIRROR_URL:-}" "$DEBIAN_ISO_SHA256"

for role in $(roles_for "${1:-all}"); do
    build_template "$role"
done
