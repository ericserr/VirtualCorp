#!/usr/bin/env bash
# ============================================================
# VirtualCorp - Funcions genèriques de VirtualBox
# ============================================================
# S'ha de carregar DESPRÉS de common.sh.
# ============================================================

vm_exists() {
    "$VBOXMANAGE_BIN" showvminfo "$1" >/dev/null 2>&1
}

vm_state() {
    "$VBOXMANAGE_BIN" showvminfo "$1" --machinereadable 2>/dev/null \
        | sed -n 's/^VMState="\(.*\)"$/\1/p'
}

vm_is_running() {
    [[ "$(vm_state "$1")" == "running" ]]
}

# Espera que la VM arribi a l'estat "poweroff".
#   vm_wait_poweroff <vm> <timeout_s>
vm_wait_poweroff() {
    local vm="$1" timeout="$2" elapsed=0 state
    while (( elapsed < timeout )); do
        state="$(vm_state "$vm")"
        case "$state" in
            poweroff) return 0 ;;
            aborted)  log_err "La VM $vm s'ha avortat."; return 1 ;;
        esac
        sleep 10
        elapsed=$((elapsed + 10))
        if (( elapsed % 300 == 0 )); then
            log_info "  $vm encara en marxa ($((elapsed / 60)) min)..."
        fi
    done
    log_err "Temps d'espera esgotat ($timeout s) esperant que $vm s'apagui."
    return 1
}

# Espera la marca VCORP-READY al fitxer del port sèrie.
#   vm_wait_ready <vm> <fitxer_serial> <timeout_s>
vm_wait_ready() {
    local vm="$1" serial="$2" timeout="$3" elapsed=0
    while (( elapsed < timeout )); do
        if [[ -f "$serial" ]] && grep -q 'VCORP-READY' "$serial"; then
            return 0
        fi
        if [[ "$(vm_state "$vm")" != "running" ]]; then
            log_err "La VM $vm s'ha aturat abans d'estar a punt."
            return 1
        fi
        sleep 5
        elapsed=$((elapsed + 5))
    done
    log_err "La VM $vm no ha enviat VCORP-READY en $timeout s."
    return 1
}

# Apaga una VM de manera ordenada (ACPI) i, si cal, la força.
vm_shutdown() {
    local vm="$1" timeout="${2:-120}"
    vm_is_running "$vm" || return 0
    "$VBOXMANAGE_BIN" controlvm "$vm" acpipowerbutton >/dev/null 2>&1 || true
    if ! vm_wait_poweroff "$vm" "$timeout" 2>/dev/null; then
        log_warn "$vm no respon a l'ACPI; s'apaga forçadament."
        "$VBOXMANAGE_BIN" controlvm "$vm" poweroff >/dev/null 2>&1 || true
        sleep 3
    fi
}

# Esborra una VM i els seus discos. Falla (sense esborrar res) si
# té clons enllaçats: VirtualBox no deixa eliminar un disc amb fills.
vm_delete() {
    local vm="$1"
    vm_exists "$vm" || return 0
    vm_shutdown "$vm" 60
    "$VBOXMANAGE_BIN" unregistervm "$vm" --delete
}

# Executa una ordre per SSH a una VM amb redirecció de port local.
#   vm_ssh <port> <ordre...>
vm_ssh() {
    local port="$1"; shift
    ssh -o BatchMode=yes \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o LogLevel=ERROR \
        -o ConnectTimeout=10 \
        -i "$PERSONAL_PRIVATE_KEY_FILE" \
        -p "$port" sysadmin@127.0.0.1 "$@"
}
