#!/bin/bash
# ============================================================
# VirtualCorp - Hook de primera arrencada de pve01
# ============================================================
# L'executa Proxmox VE una sola vegada, quan la xarxa ja és activa
# ([first-boot] ordering = "network-online" a answer.toml).
#
# Comprova des de DINS de pve01 el que demana l'enunciat i ho
# escriu a /root/vcorp-validacio.log i al port sèrie COM1, que
# VirtualBox redirigeix a un fitxer de l'amfitrió:
#   1. Extensions de virtualització disponibles per a KVM (vmx/svm,
#      /dev/kvm, mòdul kvm_intel|kvm_amd).
#   2. Ping a una IP de cadascun dels quatre routers.
#   3. Ping a una IP pública d'Internet.
# La darrera línia és "PVE-READY kvm=<ok|fail> net=<ok|fail>".
# ============================================================
set -u

LOG=/root/vcorp-validacio.log
SERIAL=/dev/ttyS0

# router0 (privada), router1, router2 i router3 (enllaços /30) i Internet.
TARGETS="@@PING_TARGETS@@"

out() {
    echo "$*" | tee -a "$LOG"
    echo "$*" > "$SERIAL" 2>/dev/null || true
}

: > "$LOG"
out "VCORP pve01 primera arrencada: $(date -Is)"
out "VCORP hostname=$(hostname -f) ip=$(ip -4 -o addr show scope global | awk '{print $4}' | xargs)"

# ---------- 1. Virtualització anidada ----------
kvm=ok
flags="$(grep -o -w -E 'vmx|svm' /proc/cpuinfo | sort -u | xargs)"
[[ -n "$flags" ]] && out "VCORP kvm cpu-flags=$flags" || { out "VCORP kvm cpu-flags=CAP"; kvm=fail; }
[[ -c /dev/kvm ]] && out "VCORP kvm /dev/kvm=present" || { out "VCORP kvm /dev/kvm=absent"; kvm=fail; }
mods="$(lsmod | awk '$1 ~ /^kvm(_intel|_amd)?$/ {print $1}' | xargs)"
out "VCORP kvm moduls=${mods:-cap}"
[[ "$mods" == *kvm_intel* || "$mods" == *kvm_amd* ]] || kvm=fail

# ---------- 2 i 3. Connectivitat ----------
# Els routers poden trigar a aprendre la ruta per RIP: fins a 3 intents.
net=ok
for target in $TARGETS; do
    name="${target%%=*}" ip="${target#*=}" result=fail
    for _ in 1 2 3; do
        if ping -c 2 -W 2 "$ip" >/dev/null 2>&1; then result=ok; break; fi
        sleep 10
    done
    out "VCORP ping $name $ip $result"
    [[ "$result" == ok ]] || net=fail
done

out "PVE-READY kvm=$kvm net=$net"
exit 0
