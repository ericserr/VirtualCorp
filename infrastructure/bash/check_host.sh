#!/usr/bin/env bash
# ============================================================
# VirtualCorp - Comprovació de l'equip amfitrió
# ============================================================
# Verifica, abans de crear templates i desplegar equips, que l'amfitrió
# compleix els requisits de l'Activitat 2 (apartat 6, virtualització
# anidada) i disposa de les eines, claus i recursos necessaris.
#
# Codi de sortida: 0 si no hi ha errors (els avisos no aturen).
# ============================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

errors=0
warnings=0
fail() { log_err "$*"; errors=$((errors + 1)); }
warn() { log_warn "$*"; warnings=$((warnings + 1)); }

# Recursos previstos (MB). Han de coincidir amb deploy_equipment.
# 4 routers x 256 + pve01 + 3 servidors x 1024 + 4 impressores x 512
# + 15 escriptoris x 1536. No cal tenir-les totes engegades alhora.
PVE_MEMORY="${PVE_MEMORY:-8192}"
PVE_CPUS="${PVE_CPUS:-4}"
PVE_DISK_MB="${PVE_DISK_MB:-65536}"
MIN_FREE_DISK_GB="${MIN_FREE_DISK_GB:-40}"

echo "=========================================="
echo " Comprovació de l'amfitrió VirtualCorp"
echo "=========================================="

# ---------- 1. Virtualització per maquinari ----------
log_info "1. Virtualització per maquinari (VT-x / AMD-V)"
if grep -qE '\b(vmx|svm)\b' /proc/cpuinfo; then
    vendor="$(grep -qw vmx /proc/cpuinfo && echo 'Intel VT-x' || echo 'AMD-V')"
    log_ok "El processador exposa $vendor (habilitat a la BIOS/UEFI)."
else
    fail "El processador no exposa vmx/svm: habiliteu VT-x/AMD-V a la BIOS/UEFI."
fi

# ---------- 2. VirtualBox i virtualització anidada ----------
log_info "2. VirtualBox i virtualització anidada"
vbox_version="$("$VBOXMANAGE_BIN" --version 2>/dev/null || true)"
if [[ -z "$vbox_version" ]]; then
    fail "No s'ha pogut executar VBoxManage."
else
    vbox_major="${vbox_version%%.*}"
    if (( vbox_major >= 7 )); then
        log_ok "VirtualBox $vbox_version"
    else
        warn "VirtualBox $vbox_version: es recomana la 7.x (nested HW virt amb Intel des de la 6.1)."
    fi
    hostinfo="$("$VBOXMANAGE_BIN" list hostinfo 2>/dev/null)"
    if grep -q 'supports nested HW virtualization: yes' <<<"$hostinfo"; then
        log_ok "VirtualBox pot exposar VT-x/AMD-V a les VM (--nested-hw-virt on)."
    else
        fail "VirtualBox indica que aquest processador NO admet virtualització anidada."
    fi
fi

# KVM i VirtualBox competeixen per VT-x. Des de Linux 6.12, KVM activa la
# virtualització en carregar el mòdul (enable_virt_at_load=Y) i VirtualBox
# pot fallar amb VERR_VMX_IN_VMX_ROOT_MODE en engegar una VM.
if [[ -r /sys/module/kvm/parameters/enable_virt_at_load ]] &&
   [[ "$(cat /sys/module/kvm/parameters/enable_virt_at_load)" == "Y" ]]; then
    warn "El mòdul kvm està carregat amb enable_virt_at_load=Y."
    log_info "  Si una VM no arrenca (VERR_VMX_IN_VMX_ROOT_MODE), descarregueu-lo:"
    log_info "  sudo modprobe -r kvm_intel kvm_amd kvm"
fi

# ---------- 3. Eines de l'amfitrió ----------
log_info "3. Eines necessàries"
declare -A tool_pkg=(
    [curl]=curl [sha256sum]=coreutils [xorriso]=xorriso [openssl]=openssl
    [ssh]=openssh-client [ssh-keygen]=openssh-client [ssh-keyscan]=openssh-client
    [dpkg-deb]=dpkg [cpio]=cpio [gzip]=gzip
)
missing_pkgs=()
for tool in curl sha256sum xorriso openssl ssh ssh-keygen ssh-keyscan dpkg-deb cpio gzip; do
    if command -v "$tool" >/dev/null 2>&1; then
        log_ok "$tool"
    else
        fail "Falta '$tool' (paquet ${tool_pkg[$tool]})."
        missing_pkgs+=("${tool_pkg[$tool]}")
    fi
done
if (( ${#missing_pkgs[@]} > 0 )); then
    log_info "  Instal·leu-les amb: sudo apt install $(printf '%s\n' "${missing_pkgs[@]}" | sort -u | tr '\n' ' ')"
fi

# ---------- 4. Claus SSH ----------
log_info "4. Claus SSH"
for pub in "$AUDIT_PUB_KEY_FILE" "$PERSONAL_PUB_KEY_FILE"; do
    if [[ -f "$pub" ]] && ssh-keygen -l -f "$pub" >/dev/null 2>&1; then
        log_ok "Clau pública vàlida: ${pub#"$PROJECT_ROOT"/}"
    else
        fail "Falta o no és vàlida la clau pública $pub."
    fi
done
if [[ -f "$PERSONAL_PRIVATE_KEY_FILE" ]]; then
    log_ok "Clau privada personal present ($PERSONAL_PRIVATE_KEY_FILE), fora del repositori."
else
    fail "Falta la clau privada $PERSONAL_PRIVATE_KEY_FILE (necessària per validar l'SSH dels templates)."
fi
if git -C "$PROJECT_ROOT" ls-files | grep -qE '(^|/)(id_[a-z0-9]+|vcorp_[a-z]+)$'; then
    fail "Hi ha fitxers que semblen claus privades versionats al repositori!"
fi

# ---------- 5. Contrasenyes locals ----------
log_info "5. Contrasenyes locals (.env)"
for var in SYSADMIN_PASSWORD PVE_ROOT_PASSWORD; do
    if [[ -n "${!var:-}" ]]; then
        log_ok "$var definida."
    else
        fail "$var no està definida a .env (vegeu .env.example)."
    fi
done

# ---------- 6. Recursos ----------
log_info "6. Recursos de l'amfitrió"
host_cpus="$(nproc)"
host_mem_mb="$(awk '/MemTotal/ {printf "%d", $2/1024}' /proc/meminfo)"
if (( PVE_CPUS < host_cpus )); then
    log_ok "CPU: $host_cpus lògiques; pve01 en tindrà $PVE_CPUS."
else
    fail "pve01 té $PVE_CPUS vCPU però l'amfitrió només en té $host_cpus: reduïu PVE_CPUS."
fi

if (( PVE_MEMORY > host_mem_mb / 2 )); then
    warn "RAM: pve01 ($PVE_MEMORY MB) supera la meitat de l'amfitrió ($host_mem_mb MB)."
else
    log_ok "RAM: $host_mem_mb MB; pve01 en tindrà $PVE_MEMORY MB."
fi
log_info "  Amb $host_mem_mb MB no es poden engegar totes les VM alhora: engegueu-les per blocs."

free_gb="$(df -BG --output=avail "$PROJECT_ROOT" | tail -1 | tr -dc '0-9')"
vbox_folder="$("$VBOXMANAGE_BIN" list systemproperties 2>/dev/null | sed -n 's/^Default machine folder: *//p')"
[[ -d "$vbox_folder" ]] && free_vbox_gb="$(df -BG --output=avail "$vbox_folder" | tail -1 | tr -dc '0-9')" || free_vbox_gb="$free_gb"
if (( free_gb < MIN_FREE_DISK_GB || free_vbox_gb < MIN_FREE_DISK_GB )); then
    warn "Disc: ${free_gb} GB lliures al projecte i ${free_vbox_gb} GB a '$vbox_folder' (< ${MIN_FREE_DISK_GB} GB recomanats)."
else
    log_ok "Disc: ${free_gb} GB lliures al projecte i ${free_vbox_gb} GB a la carpeta de VirtualBox."
fi
log_info "  Disc de pve01: $((PVE_DISK_MB / 1024)) GB dinàmic (només ocupa el que s'escriu)."

# ---------- Resum ----------
echo "=========================================="
if (( errors > 0 )); then
    log_err "$errors error(s) i $warnings avís(os). Corregiu els errors abans de continuar."
    exit 1
fi
log_ok "Amfitrió preparat ($warnings avís(os))."
