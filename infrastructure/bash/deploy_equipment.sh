#!/usr/bin/env bash
# ============================================================
# VirtualCorp - Desplegament dels equips (clons enllaçats)
# ============================================================
# Ús:
#   deploy_equipment.sh [nom...]          desplega tot l'inventari o els noms indicats
#   FORCE=1 deploy_equipment.sh [nom...]  esborra i torna a crear els existents
#   VERIFY=0 deploy_equipment.sh ...      no arrenca els clons per comprovar-los
#   deploy_equipment.sh --delete [nom...] esborra els clons (els templates es mantenen)
#   deploy_equipment.sh --list            mostra l'inventari i l'estat de cada VM
#
# Inventari: configs/equipment.conf (nom, template, xarxa, RAM, CPU, grup, IP).
#
# Per a cada equip:
#   1. Clon ENLLAÇAT des de la instantània "base" del template: el disc
#      del clon és un disc diferencial que només guarda els seus canvis.
#   2. RAM, CPU i grup segons l'inventari.
#   3. NIC1 en xarxa interna (mai NAT) amb una MAC nova per clon.
#   4. Hostname via DmiSystemSerial (el llegeix vcorp-firstboot).
#   5. COM1 redirigit a un fitxer per rebre la marca VCORP-READY.
#   6. Comprovació d'arrencada: s'engega, s'espera "VCORP-READY <nom>"
#      (prova que ha arrencat i té el hostname correcte) i s'apaga.
#      Es fa en tandes de VERIFY_PARALLEL per no esgotar la RAM.
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
source "$SCRIPT_DIR/vm_lib.sh"

EQUIPMENT_FILE="${EQUIPMENT_FILE:-${CONFIGS_DIR}/equipment.conf}"
EQUIPMENT_SERIAL_DIR="${BUILD_DIR}/equipment"
VERIFY="${VERIFY:-1}"
VERIFY_PARALLEL="${VERIFY_PARALLEL:-3}"
CLONE_BOOT_TIMEOUT="${CLONE_BOOT_TIMEOUT:-300}"
FORCE="${FORCE:-0}"

DMI_SERIAL_KEY="VBoxInternal/Devices/pcbios/0/Config/DmiSystemSerial"

# ---------- Inventari ----------
# Imprimeix les línies útils de l'inventari (sense comentaris ni buides).
inventory() {
    [[ -f "$EQUIPMENT_FILE" ]] || { log_err "No existeix $EQUIPMENT_FILE"; exit 1; }
    sed -e 's/#.*//' -e '/^[[:space:]]*$/d' "$EQUIPMENT_FILE"
}

# Filtra l'inventari pels noms demanats (tots si no se n'indica cap).
selected() {
    local names=("$@") line name n
    if (( ${#names[@]} == 0 )); then inventory; return; fi
    for n in "${names[@]}"; do
        line="$(inventory | awk -v n="$n" '$1 == n')"
        [[ -n "$line" ]] || { log_err "'$n' no és a l'inventari ($EQUIPMENT_FILE)."; exit 1; }
        echo "$line"
    done
}

template_vm() {
    case "$1" in
        server)  echo "$TPL_SERVER_NAME" ;;
        desktop) echo "$TPL_DESKTOP_NAME" ;;
        *) log_err "Template desconegut: $1"; exit 1 ;;
    esac
}

group_path() {
    case "$1" in
        servers)  echo "$VM_SERVERS_GROUP" ;;
        printers) echo "$VM_PRINTERS_GROUP" ;;
        desktops) echo "$VM_DESKTOPS_GROUP" ;;
        *) log_err "Grup desconegut: $1"; exit 1 ;;
    esac
}

serial_file() { echo "${EQUIPMENT_SERIAL_DIR}/$1.serial.log"; }

# ---------- Comprovacions prèvies ----------
check_templates() {
    local role tpl
    for role in server desktop; do
        tpl="$(template_vm "$role")"
        if ! vm_exists "$tpl"; then
            log_err "No existeix el template $tpl. Executa primer: make create_templates"
            exit 1
        fi
        if ! "$VBOXMANAGE_BIN" snapshot "$tpl" showvminfo "$TPL_SNAPSHOT" >/dev/null 2>&1; then
            log_err "El template $tpl no té la instantània '$TPL_SNAPSHOT'."
            exit 1
        fi
        if vm_is_running "$tpl"; then
            log_err "El template $tpl està engegat; apaga'l abans de clonar."
            exit 1
        fi
    done
}

# ---------- Creació d'un clon ----------
create_clone() {
    local name="$1" role="$2" net="$3" ram="$4" cpus="$5" group="$6"
    local tpl serial
    tpl="$(template_vm "$role")"
    serial="$(serial_file "$name")"

    if vm_exists "$name"; then
        if [[ "$FORCE" == "1" ]]; then
            log_info "FORCE=1: esborrant $name"
            vm_delete "$name"
        else
            log_info "$name ja existeix (FORCE=1 per refer-lo)."
            return 0
        fi
    fi

    log_info "Clonant $name  <- $tpl@$TPL_SNAPSHOT  [$net, ${ram} MB, ${cpus} CPU]"
    "$VBOXMANAGE_BIN" clonevm "$tpl" --snapshot "$TPL_SNAPSHOT" \
        --options link --name "$name" --groups "$(group_path "$group")" \
        --register >/dev/null

    # clonevm només usa --groups per a la carpeta: el grup visible el
    # copia del template, i s'ha de fixar explícitament.
    : > "$serial"
    "$VBOXMANAGE_BIN" modifyvm "$name" --groups "$(group_path "$group")" \
        --memory "$ram" --cpus "$cpus" \
        --nic1 intnet --intnet1 "$net" --cable-connected1 on \
        --mac-address1 auto \
        --uart1 0x3F8 4 --uart-mode1 file "$serial" \
        --description "VirtualCorp delegació 25 - $name ($role, xarxa $net)"
    "$VBOXMANAGE_BIN" setextradata "$name" "$DMI_SERIAL_KEY" "$name"
}

# ---------- Comprovació d'arrencada ----------
# Engega una tanda de clons, espera la marca de cadascun i els apaga.
verify_batch() {
    local names=("$@") name serial failed=0
    for name in "${names[@]}"; do
        serial="$(serial_file "$name")"
        : > "$serial"
        "$VBOXMANAGE_BIN" startvm "$name" --type headless >/dev/null
    done
    for name in "${names[@]}"; do
        serial="$(serial_file "$name")"
        if vm_wait_ready "$name" "$serial" "$CLONE_BOOT_TIMEOUT" \
            && grep -q "VCORP-READY ${name}\$" <(tr -d '\r' < "$serial"); then
            log_ok "$name arrenca i té el hostname correcte."
        else
            log_err "$name: no s'ha rebut 'VCORP-READY $name' (vegeu $serial)."
            failed=1
        fi
    done
    for name in "${names[@]}"; do
        vm_shutdown "$name" 120
    done
    return "$failed"
}

verify_all() {
    local names=("$@") batch=() name failed=0
    for name in "${names[@]}"; do
        batch+=("$name")
        if (( ${#batch[@]} == VERIFY_PARALLEL )); then
            verify_batch "${batch[@]}" || failed=1
            batch=()
        fi
    done
    if (( ${#batch[@]} > 0 )); then
        verify_batch "${batch[@]}" || failed=1
    fi
    return "$failed"
}

# ---------- Llistat ----------
list_equipment() {
    local name role net ram cpus group ip state
    printf '%-12s %-8s %-13s %5s %4s %-9s %-13s %s\n' \
        NOM TEMPLATE XARXA RAM CPU GRUP IP ESTAT
    while read -r name role net ram cpus group ip; do
        vm_exists "$name" && state="$(vm_state "$name")" || state="(no creada)"
        printf '%-12s %-8s %-13s %5s %4s %-9s %-13s %s\n' \
            "$name" "$role" "$net" "$ram" "$cpus" "$group" "$ip" "$state"
    done < <(inventory)
}

# ---------- Principal ----------
case "${1:-}" in
    --list)
        list_equipment
        exit 0
        ;;
    --delete)
        shift
        while read -r name _; do
            if vm_exists "$name"; then
                log_info "Esborrant $name"
                vm_delete "$name" </dev/null
            fi
        done < <(selected "$@")
        exit 0
        ;;
esac

check_templates
mkdir -p "$EQUIPMENT_SERIAL_DIR"

deployed=()
while read -r name role net ram cpus group ip; do
    # </dev/null: VBoxManage no ha de consumir l'entrada del bucle.
    create_clone "$name" "$role" "$net" "$ram" "$cpus" "$group" </dev/null
    deployed+=("$name")
done < <(selected "$@")

if [[ "$VERIFY" == "1" ]]; then
    log_info "Comprovant l'arrencada de ${#deployed[@]} equips (tandes de $VERIFY_PARALLEL)..."
    if ! verify_all "${deployed[@]}"; then
        log_err "Alguns equips no han superat la comprovació d'arrencada."
        exit 1
    fi
fi
log_ok "Desplegament d'equips completat (${#deployed[@]} màquines)."
