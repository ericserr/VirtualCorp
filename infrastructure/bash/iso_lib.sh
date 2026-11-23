#!/usr/bin/env bash
# ============================================================
# VirtualCorp - Llibreria de gestió d'imatges ISO
# ============================================================
# Funcions per descarregar i verificar les ISO fixades a
# configs/versions.env. S'ha de carregar DESPRÉS de common.sh.
#
# Principis (enunciat Activitat 2, apartat 3.1):
#   - Mai es cerca "la darrera versió": només es descarrega la URL fixada.
#   - Tota ISO es verifica amb el SHA256 fixat abans de fer-la servir.
#   - El mirror opcional ha de servir EXACTAMENT el mateix fitxer
#     (mateix nom i mateix hash); no és cap canvi de versió.
# ============================================================

# Comprova el SHA256 d'un fitxer. Retorna 0 si coincideix.
#   iso_verify_sha256 <fitxer> <sha256_esperat>
iso_verify_sha256() {
    local file="$1"
    local expected="$2"
    local actual

    [[ -f "$file" ]] || return 1
    actual="$(sha256sum "$file" | awk '{print $1}')"
    if [[ "$actual" == "$expected" ]]; then
        return 0
    fi
    log_warn "SHA256 incorrecte per a $(basename "$file")"
    log_warn "  esperat: $expected"
    log_warn "  obtingut: $actual"
    return 1
}

# Descarrega una URL a un fitxer temporal (.part), reprenent-la si
# s'havia interromput. Retorna el codi de curl.
_iso_fetch() {
    local url="$1"
    local part="$2"

    log_info "Descarregant $url"
    # --fail: un 404 és un error, no un fitxer HTML desat com a ISO.
    # -C -: reprèn descàrregues parcials.
    # --speed-limit/--speed-time: si un mirror es queda penjat (<1 KB/s
    #   durant 60 s) s'avorta en lloc d'esperar indefinidament.
    # Sense --insecure: un error TLS s'ha d'investigar, no ignorar.
    # Cada intent reprèn el fitxer .part on s'havia quedat.
    local attempt rc max_attempts="${ISO_DOWNLOAD_ATTEMPTS:-5}"
    for ((attempt = 1; attempt <= max_attempts; attempt++)); do
        rc=0
        curl --fail --location --show-error --progress-bar \
             --connect-timeout 20 --speed-limit 1024 --speed-time 60 \
             -C - -o "$part" "$url" || rc=$?
        (( rc == 0 )) && return 0
        # Errors no transitoris (HTTP 4xx, DNS, TLS/certificat): reintentar
        # no serveix de res, cal passar al mirror o investigar-ho.
        case "$rc" in
            6|22|35|51|58|60|77) return "$rc" ;;
        esac
        log_warn "Intent $attempt/$max_attempts fallit; es reprèn en 5 s..."
        sleep 5
    done
    return 1
}

# Garanteix que una ISO existeix i és íntegra.
#   iso_ensure <nom_lògic> <fitxer_destí> <url> <url_mirror|""> <sha256>
iso_ensure() {
    local label="$1"
    local dest="$2"
    local url="$3"
    local mirror="$4"
    local sha256="$5"
    local part="${dest}.part"

    if [[ -z "$url" || -z "$sha256" ]]; then
        log_err "$label: falta la URL o el SHA256 a configs/versions.env."
        return 1
    fi

    mkdir -p "$(dirname "$dest")"

    # 1. Ja descarregada i correcta: no es torna a baixar.
    if [[ -f "$dest" ]]; then
        log_info "$label: verificant la ISO existent $(basename "$dest")..."
        if iso_verify_sha256 "$dest" "$sha256"; then
            log_ok "$label: ISO present i verificada."
            return 0
        fi
        log_warn "$label: la ISO existent està corrupta o és d'una altra versió; s'esborra."
        rm -f "$dest"
    fi

    # 2. URL oficial; 3. mirror del mateix fitxer només si l'oficial falla.
    local source
    for source in "$url" "$mirror"; do
        [[ -n "$source" ]] || continue
        if [[ "$source" == "$mirror" ]]; then
            log_warn "$label: la URL oficial ha fallat; es prova el mirror configurat."
            log_warn "$label: el SHA256 garantirà que és el mateix fitxer."
            # Una descàrrega parcial d'un altre origen no es pot reprendre.
            rm -f "$part"
        fi

        if _iso_fetch "$source" "$part"; then
            if iso_verify_sha256 "$part" "$sha256"; then
                mv -f "$part" "$dest"
                log_ok "$label: ISO descarregada i verificada ($(basename "$dest"))."
                return 0
            fi
            log_err "$label: el fitxer descarregat de $source no coincideix amb el SHA256 fixat."
            rm -f "$part"
        else
            log_warn "$label: no s'ha pogut descarregar de $source."
        fi
    done

    log_err "$label: no s'ha pogut obtenir una ISO vàlida."
    log_err "No es canvia automàticament de versió: investigueu la causa i,"
    log_err "si cal, actualitzeu configs/versions.env en una branca específica."
    return 1
}
