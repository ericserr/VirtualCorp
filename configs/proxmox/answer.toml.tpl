# ============================================================
# VirtualCorp - Fitxer de respostes de Proxmox VE (pve01)
# ============================================================
# Plantilla: deploy_pve.sh substitueix els marcadors (entre @@) i la incrusta a
# la ISO amb proxmox-auto-install-assistant (--fetch-from iso).
# Format de claus de Proxmox VE 9 (kebab-case).
# ============================================================

[global]
keyboard = "es"
country = "es"
fqdn = "@@FQDN@@"
mailto = "root@@@DOMAIN@@"
timezone = "Europe/Madrid"
# Hash SHA-512 generat en temps de desplegament des de PVE_ROOT_PASSWORD
# (.env): la contrasenya mai queda en clar a la ISO ni al repositori.
root-password-hashed = "@@ROOT_PASSWORD_HASH@@"
# Mecanisme propi de Proxmox per autoritzar claus a root:
# clau del professor + clau personal de l'alumne.
root-ssh-keys = [
    "@@AUDITOR_KEY@@",
    "@@PERSONAL_KEY@@",
]
reboot-on-error = false

[network]
# IP estàtica del disseny (10.25.0.133/26, porta d'enllaç router0).
source = "from-answer"
cidr = "@@CIDR@@"
gateway = "@@GATEWAY@@"
dns = "@@DNS@@"
# La NIC es tria per la MAC fixa que deploy_pve.sh assigna a la VM.
filter.ID_NET_NAME_MAC = "*@@MAC_FILTER@@"

[disk-setup]
# ext4 sobre LVM: arrel ext4 + emmagatzematge "local-lvm" LVM-thin.
# L'enunciat prohibeix ZFS.
filesystem = "ext4"
disk-list = ["sda"]

[first-boot]
# Script incrustat a la ISO: comprova KVM i la connectivitat i ho
# notifica per COM1 (PVE-READY).
source = "from-iso"
ordering = "network-online"
