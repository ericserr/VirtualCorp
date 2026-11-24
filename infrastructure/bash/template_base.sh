#!/usr/bin/env bash
# ============================================================
# VirtualCorp - Funcions per construir els templates Debian
# ============================================================
# S'ha de carregar DESPRÉS de common.sh i iso_lib.sh.
# ============================================================

# Paquets addicionals de cada template. La resta ve del sistema base
# (sense recomanats ni tasques de tasksel: instal·lació lleugera).
#   server : administració remota (SSH + sudo) i res més.
#   desktop: el mateix + servidor X mínim, LXQt (amb openbox com a
#            gestor de finestres), SDDM i Falkon. Sense Firefox ni
#            ofimàtica (enunciat, apartat 4.2).
TPL_SERVER_PACKAGES="${TPL_SERVER_PACKAGES:-openssh-server sudo ca-certificates}"
TPL_DESKTOP_PACKAGES="${TPL_DESKTOP_PACKAGES:-${TPL_SERVER_PACKAGES} \
xserver-xorg-core xserver-xorg-input-libinput xserver-xorg-video-vmware \
xserver-xorg-video-fbdev lxqt-core openbox sddm falkon fonts-dejavu-core}"

# Retorna el nom de la VM template d'un rol.
tpl_vm_name() {
    case "$1" in
        server)  echo "$TPL_SERVER_NAME" ;;
        desktop) echo "$TPL_DESKTOP_NAME" ;;
        *) log_err "Rol de template desconegut: $1"; return 1 ;;
    esac
}

# Genera el hash SHA-512 de la contrasenya de sysadmin (de .env).
# La contrasenya en clar no s'escriu mai a cap fitxer.
tpl_password_hash() {
    if [[ -z "${SYSADMIN_PASSWORD:-}" ]]; then
        log_err "SYSADMIN_PASSWORD no està definida a .env."
        return 1
    fi
    printf '%s' "$SYSADMIN_PASSWORD" | openssl passwd -6 -stdin
}

# Genera el preseed.cfg d'un rol a partir de la plantilla.
#   tpl_render_preseed <server|desktop> <fitxer_sortida>
tpl_render_preseed() {
    local role="$1"
    local out="$2"
    local hostname packages hash

    hostname="$(tpl_vm_name "$role")" || return 1
    case "$role" in
        server)  packages="$TPL_SERVER_PACKAGES" ;;
        desktop) packages="$TPL_DESKTOP_PACKAGES" ;;
    esac
    packages="$(echo $packages)"   # normalitza espais i salts de línia
    hash="$(tpl_password_hash)" || return 1

    local tpl="${DEBIAN_CONFIG_DIR}/preseed.cfg.tpl"
    [[ -f "$tpl" ]] || { log_err "No existeix $tpl"; return 1; }

    # El hash només conté [./0-9A-Za-z$]: segur amb el delimitador "|".
    sed -e "s|@@LOCALE@@|${VM_LOCALE}|g" \
        -e "s|@@KEYMAP@@|${VM_KEYMAP}|g" \
        -e "s|@@TIMEZONE@@|${VM_TIMEZONE}|g" \
        -e "s|@@HOSTNAME@@|${hostname}|g" \
        -e "s|@@DOMAIN@@|${VCORP_DOMAIN}|g" \
        -e "s|@@PACKAGES@@|${packages}|g" \
        -e "s|@@TEMPLATE_ROLE@@|${role}|g" \
        -e "s|@@PASSWORD_HASH@@|${hash}|g" \
        "$tpl" > "$out" || return 1
    chmod 0600 "$out"

    if grep -qE '@@[A-Z_]+@@' "$out"; then
        log_err "Queden marcadors sense substituir a $out:"
        grep -nE '@@[A-Z_]+@@' "$out" >&2
        return 1
    fi
}

# Prepara el directori /vcorp que s'incrusta a la ISO: scripts,
# serveis i authorized_keys (clau del professor + clau personal).
#   tpl_stage_files <directori_destí>
tpl_stage_files() {
    local dest="$1"
    local key

    rm -rf "$dest"
    mkdir -p "$dest"
    cp -a "${DEBIAN_CONFIG_DIR}/files/." "$dest/" || return 1

    : > "$dest/authorized_keys"
    for key in "$AUDIT_PUB_KEY_FILE" "$PERSONAL_PUB_KEY_FILE"; do
        if [[ ! -s "$key" ]]; then
            log_err "Falta la clau pública $key"
            return 1
        fi
        # Comprova que és realment una clau pública vàlida.
        ssh-keygen -l -f "$key" >/dev/null 2>&1 || {
            log_err "$key no és una clau pública SSH vàlida."
            return 1
        }
        cat "$key" >> "$dest/authorized_keys"
        # Garanteix el salt de línia entre claus.
        if [[ -n "$(tail -c1 "$dest/authorized_keys")" ]]; then
            echo >> "$dest/authorized_keys"
        fi
    done
}

# Construeix la ISO desatesa d'un rol.
#   tpl_build_iso <server|desktop>   → escriu el camí a stdout
tpl_build_iso() {
    local role="$1"
    local dir="${BUILD_DIR}/${role}"
    local iso="${dir}/debian-${DEBIAN_VERSION}-vcorp-${role}.iso"

    mkdir -p "$dir"
    tpl_render_preseed "$role" "$dir/preseed.cfg" >&2 || return 1
    tpl_stage_files "$dir/vcorp" >&2 || return 1
    iso_remaster_debian "$DEBIAN_ISO_PATH" "$iso" "$dir/preseed.cfg" "$dir/vcorp" >&2 || return 1
    echo "$iso"
}
