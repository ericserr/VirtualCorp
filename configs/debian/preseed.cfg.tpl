#_preseed_V1
# ============================================================
# VirtualCorp - Fitxer de respostes de l'instal·lador Debian
# ============================================================
# Plantilla: create_templates.sh substitueix els marcadors (@ @NOM@ @, sense espais)
# i genera un preseed.cfg per a cada template (server / desktop)
# que s'incrusta a la ISO remasteritzada (artifacts/build/, ignorat
# per Git). Aquí NO hi ha cap contrasenya: només s'hi posa un hash
# SHA-512 generat en temps de construcció a partir de .env.
# ============================================================

# ---------- Localització i teclat ----------
d-i debian-installer/locale string @@LOCALE@@
d-i keyboard-configuration/xkb-keymap select @@KEYMAP@@
d-i console-setup/ask_detect boolean false

# ---------- Xarxa (DHCP) ----------
# Durant la construcció la VM té una NIC NAT temporal amb DHCP de
# VirtualBox; els clons faran DHCP a la seva xarxa interna.
d-i netcfg/choose_interface select auto
d-i netcfg/disable_autoconfig boolean false
d-i netcfg/get_hostname string @@HOSTNAME@@
d-i netcfg/get_domain string @@DOMAIN@@
d-i netcfg/hostname string @@HOSTNAME@@
d-i hw-detect/load_firmware boolean false

# ---------- Rèplica de paquets ----------
d-i mirror/country string manual
d-i mirror/http/hostname string deb.debian.org
d-i mirror/http/directory string /debian
d-i mirror/http/proxy string
d-i apt-setup/cdrom/set-first boolean false
d-i apt-setup/disable-cdrom-entries boolean true
d-i apt-setup/non-free-firmware boolean false
d-i apt-setup/services-select multiselect security, updates

# ---------- Comptes ----------
# Sense contrasenya de root: root queda bloquejat i sysadmin rep
# sudo automàticament (grup sudo).
d-i passwd/root-login boolean false
d-i passwd/make-user boolean true
d-i passwd/user-fullname string VirtualCorp sysadmin
d-i passwd/username string sysadmin
d-i passwd/user-password-crypted password @@PASSWORD_HASH@@
d-i passwd/user-default-groups string sudo

# ---------- Rellotge ----------
d-i clock-setup/utc boolean true
d-i time/zone string @@TIMEZONE@@
d-i clock-setup/ntp boolean true

# ---------- Particionat (disc sencer, sense LVM) ----------
# Una sola partició arrel + swap: és el més senzill per a clons
# enllaçats i no cal redimensionar volums en aquesta activitat.
d-i partman-auto/disk string /dev/sda
d-i partman-auto/method string regular
d-i partman-auto/choose_recipe select atomic
d-i partman-partitioning/confirm_write_new_label boolean true
d-i partman/choose_partition select finish
d-i partman/confirm boolean true
d-i partman/confirm_nooverwrite boolean true
d-i partman-md/confirm boolean true

# ---------- Sistema base i paquets ----------
# Sense paquets recomanats: instal·lació lleugera (evita, p. ex., que
# el navegador o l'escriptori arrosseguin Firefox o suites ofimàtiques).
d-i base-installer/install-recommends boolean false
d-i base-installer/kernel/image string linux-image-amd64
tasksel tasksel/first multiselect
d-i pkgsel/include string @@PACKAGES@@
d-i pkgsel/upgrade select safe-upgrade
popularity-contest popularity-contest/participate boolean false

# ---------- Carregador d'arrencada ----------
d-i grub-installer/only_debian boolean true
d-i grub-installer/with_other_os boolean false
d-i grub-installer/bootdev string /dev/sda

# ---------- Personalització final ----------
# late.sh (copiat de la ISO) instal·la les claus SSH, endureix sshd i
# activa els serveis de primera arrencada. Les claus públiques arriben
# dins la ISO, no s'han d'autoritzar manualment.
d-i preseed/late_command string \
    cp -r /cdrom/vcorp /target/root/vcorp-install; \
    in-target /bin/bash /root/vcorp-install/late.sh @@TEMPLATE_ROLE@@ @@DOMAIN@@; \
    rm -rf /target/root/vcorp-install

# ---------- Final ----------
# S'apaga en acabar: l'script de construcció detecta l'estat
# "poweroff" de la VM per saber que la instal·lació ha acabat.
d-i finish-install/reboot_in_progress note
d-i debian-installer/exit/poweroff boolean true
