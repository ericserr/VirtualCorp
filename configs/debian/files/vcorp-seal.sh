#!/bin/bash
# ============================================================
# VirtualCorp - Segellat del template abans de clonar-lo
# ============================================================
# Elimina tot el que ha de ser únic per a cada màquina, perquè els
# clons no comparteixin identitat:
#   - claus de host SSH  (vcorp-firstboot les regenera)
#   - machine-id         (systemd en genera un de nou en arrencar;
#                         també determina el client-id de DHCP)
#   - concessions DHCP, logs i memòria cau d'apt
# Finalment apaga la màquina.
# ============================================================
set -eu

apt-get clean
rm -f /etc/ssh/ssh_host_*
truncate -s 0 /etc/machine-id
rm -f /var/lib/dbus/machine-id
rm -f /var/lib/dhcp/*.leases
find /var/log -type f -name '*.log' -exec truncate -s 0 {} +
journalctl --rotate >/dev/null 2>&1 || true
journalctl --vacuum-time=1s >/dev/null 2>&1 || true
rm -f /root/.bash_history /home/sysadmin/.bash_history

sync
systemctl poweroff
