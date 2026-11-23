#!/bin/bash
# ============================================================
# VirtualCorp - Preparació de cada clon en arrencar
# ============================================================
# 1. Regenera les claus de host SSH si el template s'ha segellat
#    (cada clon ha de tenir una identitat SSH pròpia).
# 2. Fixa el nom de host a partir del número de sèrie DMI que el
#    script de desplegament assigna a cada VM:
#      VBoxManage setextradata <vm> \
#        VBoxInternal/Devices/pcbios/0/Config/DmiSystemSerial <hostname>
#    Així el clon obté el seu nom sense cap intervenció manual.
# ============================================================
set -u

DOMAIN_FILE=/etc/vcorp-domain

# --- 1. Claus de host SSH ---
if ! ls /etc/ssh/ssh_host_*_key >/dev/null 2>&1; then
    ssh-keygen -A
fi

# --- 2. Nom de host ---
serial="$(cat /sys/class/dmi/id/product_serial 2>/dev/null || true)"
serial="$(echo "$serial" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9-')"

# VirtualBox posa "0" quan no s'ha definit cap sèrie: es manté el nom actual.
if [[ -n "$serial" && "$serial" != "0" && "$serial" != "$(hostname)" ]]; then
    domain="$(cat "$DOMAIN_FILE" 2>/dev/null || true)"
    echo "$serial" > /etc/hostname
    hostname "$serial"
    if [[ -n "$domain" ]]; then
        fqdn_line="127.0.1.1\t${serial}.${domain} ${serial}"
    else
        fqdn_line="127.0.1.1\t${serial}"
    fi
    sed -i '/^127\.0\.1\.1/d' /etc/hosts
    echo -e "$fqdn_line" >> /etc/hosts
fi

exit 0
