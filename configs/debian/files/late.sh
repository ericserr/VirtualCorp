#!/bin/bash
# ============================================================
# VirtualCorp - Personalització del sistema instal·lat
# ============================================================
# S'executa DINS del sistema instal·lat (in-target) al final de la
# instal·lació desatesa. Rep el rol (server | desktop) i el domini DNS.
# Els fitxers són a /root/vcorp-install (copiats de /cdrom/vcorp).
# ============================================================
set -euo pipefail

ROLE="${1:-server}"
DOMAIN="${2:-}"
SRC=/root/vcorp-install

# ---------- Claus SSH autoritzades (professor + alumne) ----------
install -d -m 0700 -o sysadmin -g sysadmin /home/sysadmin/.ssh
install -m 0600 -o sysadmin -g sysadmin \
    "$SRC/authorized_keys" /home/sysadmin/.ssh/authorized_keys

# ---------- Enduriment de sshd ----------
# Només autenticació per clau i sense accés directe de root.
install -d -m 0755 /etc/ssh/sshd_config.d
cat > /etc/ssh/sshd_config.d/10-vcorp.conf <<'EOF'
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
EOF

# ---------- sudo sense contrasenya per a sysadmin ----------
# Permet l'administració automatitzada (scripts i, més endavant,
# Ansible) només amb la clau SSH.
echo 'sysadmin ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/90-sysadmin
chmod 0440 /etc/sudoers.d/90-sysadmin

# ---------- Serveis i scripts VirtualCorp ----------
install -m 0755 "$SRC/vcorp-firstboot.sh" /usr/local/sbin/vcorp-firstboot
install -m 0755 "$SRC/vcorp-seal.sh"      /usr/local/sbin/vcorp-seal
install -m 0644 "$SRC/vcorp-firstboot.service" /etc/systemd/system/
install -m 0644 "$SRC/vcorp-ready.service"     /etc/systemd/system/
systemctl enable vcorp-firstboot.service vcorp-ready.service

# ---------- Escriptori ----------
if [[ "$ROLE" == "desktop" ]]; then
    systemctl set-default graphical.target
    systemctl enable sddm.service || true
else
    systemctl set-default multi-user.target
fi

# Identificació del template (útil per a la validació) i domini que
# vcorp-firstboot fa servir per construir el FQDN de cada clon.
echo "$ROLE" > /etc/vcorp-template
echo "$DOMAIN" > /etc/vcorp-domain
