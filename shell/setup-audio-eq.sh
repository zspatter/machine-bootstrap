#!/usr/bin/env bash
#
# Headphone EQ (Sennheiser HD 800 S, oratory1990 target) via PipeWire's
# builtin param_eq loading the vendored AutoEq file from assets/audio-eq.
# Hardware-scoped, so deliberately NOT in the install-all chain -- run it
# by hand on machines that actually have the DAC/headphones. Safe to
# re-run; every path converges.
#
# Modes:
#   (default)       PipeWire filter-chain via builtin param_eq (no packages, no daemons)
#   --easyeffects   EasyEffects (GUI) instead; installs the deb, links preset, autostarts
#   --remove        Tear down whichever mode is present
#   --status        Report current state
#
# Options:
#   --sink <node.name>   Pin the output DAC. Auto-detected (pattern: fiio) if omitted;
#                        an existing install's sink is reused on re-run.
#
# Env:
#   AUDIO_EQ_ASSETS       Override assets dir (default: <repo>/assets/audio-eq)
#   AUDIO_EQ_DAC_PATTERN  Case-insensitive substring for sink auto-detect (default: fiio)
#
# Idempotent: re-running any mode converges; switching modes deactivates the other.

set -euo pipefail

# --- constants ---------------------------------------------------------------
MIN_PW_VER="1.2.0"                       # param_eq builtin requires PipeWire >= 1.2
SINK_NODE="hd800s_eq_sink"
SINK_DESC="HD 800 S (EQ)"
TXT_NAME="hd800s-oratory1990-parametric.txt"
EE_JSON_NAME="hd800s-oratory1990-easyeffects.json"
EE_PRESET_NAME="hd800s-oratory1990"

CONF_DIR="${HOME}/.config/pipewire/pipewire.conf.d"
CONF="${CONF_DIR}/99-hd800s-eq.conf"
TXT_LINK="${HOME}/.config/pipewire/${TXT_NAME}"
EE_PRESET_DIR="${HOME}/.config/easyeffects/output"
EE_PRESET="${EE_PRESET_DIR}/${EE_PRESET_NAME}.json"
AUTOSTART="${HOME}/.config/autostart/easyeffects-service.desktop"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- helpers -----------------------------------------------------------------
log_step() { printf '\n==> %s\n' "$1"; }
log_info() { printf '    %s\n' "$1"; }
warn()     { printf '    WARN: %s\n' "$*" >&2; }
die()      { printf '    ERROR: %s\n' "$*" >&2; exit 1; }

# Linux-only by nature: the engine is PipeWire. macOS is deliberately out
# of scope (no PipeWire/EasyEffects there); see assets/audio-eq/README.md.
[[ "$(uname -s)" == "Linux" ]] || die "Linux-only (PipeWire); macOS is out of scope, see assets/audio-eq/README.md"

usage() { sed -n '2,23p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

find_assets() {
    local d
    for d in "${AUDIO_EQ_ASSETS:-}" \
             "${SCRIPT_DIR}/../assets/audio-eq" \
             "${SCRIPT_DIR}/assets/audio-eq" \
             "${SCRIPT_DIR}"; do
        [[ -n "${d}" && -f "${d}/${TXT_NAME}" ]] && { printf '%s' "$(cd "${d}" && pwd)"; return 0; }
    done
    die "assets not found (looked for ${TXT_NAME}); set AUDIO_EQ_ASSETS"
}

pw_version_ok() {
    command -v pipewire >/dev/null 2>&1 || die "pipewire not found; is this a desktop session?"
    local ver
    ver="$(pipewire --version 2>/dev/null | awk '/Compiled with/ {print $NF; exit}')"
    [[ -n "${ver}" ]] || die "could not determine PipeWire version"
    if [[ "$(printf '%s\n%s\n' "${MIN_PW_VER}" "${ver}" | sort -V | head -1)" != "${MIN_PW_VER}" ]]; then
        die "PipeWire ${ver} < ${MIN_PW_VER}; the param_eq builtin needs >= ${MIN_PW_VER}"
    fi
    log_info "PipeWire ${ver} OK (>= ${MIN_PW_VER})"
}

# List Audio/Sink nodes as: node.name<TAB>node.description
list_sinks() {
    command -v pw-cli >/dev/null 2>&1 || die "pw-cli not found (package: pipewire-bin)"
    pw-cli ls Node 2>/dev/null | awk '
        /^[ \t]*id [0-9]+,/ { if (cls == "Audio/Sink" && name != "") print name "\t" desc
                              name=""; desc=""; cls=""; next }
        {
            if (match($0, /node\.name = "/)) {
                s = substr($0, RSTART + RLENGTH); sub(/".*/, "", s); name = s
            } else if (match($0, /node\.description = "/)) {
                s = substr($0, RSTART + RLENGTH); sub(/".*/, "", s); desc = s
            } else if (match($0, /media\.class = "/)) {
                s = substr($0, RSTART + RLENGTH); sub(/".*/, "", s); cls = s
            }
        }
        END { if (cls == "Audio/Sink" && name != "") print name "\t" desc }
    ' | grep -v -- "^${SINK_NODE}"$'\t' || true
}

detect_sink() {
    local pattern="${AUDIO_EQ_DAC_PATTERN:-fiio}" all matches count
    all="$(list_sinks)"
    [[ -n "${all}" ]] || die "no Audio/Sink nodes visible; is the session's PipeWire running?"
    matches="$(printf '%s\n' "${all}" | grep -i -- "${pattern}" || true)"
    count="$(printf '%s' "${matches}" | grep -c . || true)"
    if [[ "${count}" -eq 1 ]]; then
        printf '%s' "${matches%%$'\t'*}"
    else
        {
            warn "sink auto-detect (pattern '${pattern}') matched ${count} sinks; pass --sink <node.name>"
            warn "available sinks:"
            printf '%s\n' "${all}" | sed 's/^/  /' >&2
        }
        return 1
    fi
}

existing_sink_from_conf() {
    [[ -f "${CONF}" ]] || return 1
    sed -n 's/.*target\.object[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "${CONF}" | head -1
}

validate_txt() {
    local f="$1"
    grep -q $'\r' "${f}" && die "asset has CRLF line endings; run: dos2unix '${f}'"
    # param_eq reads the preamp ONLY from line 1; a non-Preamp first line is
    # consumed and silently dropped (verified against PipeWire source).
    head -1 "${f}" | grep -qE '^Preamp:[[:space:]]*-?[0-9.]+[[:space:]]*dB' \
        || die "line 1 of ${f} must be the 'Preamp: ... dB' line"
    local preamp
    preamp="$(head -1 "${f}" | grep -oE '\-?[0-9]+(\.[0-9]+)?' | head -1)"
    log_info "asset OK: $(grep -c '^Filter' "${f}") filters, preamp ${preamp} dB (applied by param_eq)"
}

restart_pipewire() {
    if systemctl --user is-active pipewire.service >/dev/null 2>&1 || \
       systemctl --user list-unit-files pipewire.service >/dev/null 2>&1; then
        log_info "restarting pipewire user services"
        systemctl --user restart pipewire.service pipewire-pulse.service wireplumber.service \
            || warn "service restart failed; log out/in to apply"
    else
        warn "no pipewire user service found; log out/in to apply"
    fi
}

verify_sink_appeared() {
    for _ in 1 2 3 4 5 6; do
        sleep 0.5
        if pw-cli ls Node 2>/dev/null | grep -q "\"${SINK_NODE}\""; then
            log_info "virtual sink '${SINK_DESC}' is live"
            return 0
        fi
    done
    warn "sink not visible yet; check: journalctl --user -u pipewire -n 30"
    return 0
}

deactivate_easyeffects() {
    local changed=0
    if command -v easyeffects >/dev/null 2>&1 && pgrep -x easyeffects >/dev/null 2>&1; then
        easyeffects -q >/dev/null 2>&1 || pkill -x easyeffects || true
        changed=1
    fi
    [[ -e "${AUTOSTART}" ]] && { rm -f "${AUTOSTART}"; changed=1; }
    [[ "${changed}" -eq 1 ]] && log_info "EasyEffects deactivated (autostart removed, service stopped)"
    return 0
}

deactivate_filterchain() {
    if [[ -e "${CONF}" || -L "${TXT_LINK}" ]]; then
        rm -f "${CONF}" "${TXT_LINK}"
        log_info "filter-chain removed"
        return 0
    fi
    return 1
}

# --- modes -------------------------------------------------------------------
mode_filterchain() {
    local assets sink
    log_step "Provisioning headphone EQ (PipeWire filter-chain)"
    pw_version_ok
    assets="$(find_assets)"
    validate_txt "${assets}/${TXT_NAME}"

    if [[ -n "${SINK_ARG}" ]]; then
        sink="${SINK_ARG}"
    elif sink="$(existing_sink_from_conf)" && [[ -n "${sink}" ]]; then
        log_info "reusing sink from existing install: ${sink}"
    else
        sink="$(detect_sink)" || die "could not resolve target sink"
        log_info "auto-detected sink: ${sink}"
    fi

    deactivate_easyeffects

    mkdir -p "${CONF_DIR}"
    ln -sfn "${assets}/${TXT_NAME}" "${TXT_LINK}"

    local txt_abs
    txt_abs="$(readlink -f "${TXT_LINK}")"
    cat > "${CONF}" <<EOF
# Generated by setup-audio-eq on $(date -Iseconds); do not edit (re-run the script).
# EQ: Sennheiser HD 800 S, oratory1990 target (AutoEq). Preamp applied by param_eq.
context.modules = [
    { name = libpipewire-module-filter-chain
        args = {
            node.description = "${SINK_DESC}"
            media.name       = "${SINK_DESC}"
            filter.graph = {
                nodes = [
                    {
                        type   = builtin
                        name   = eq
                        label  = param_eq
                        config = { filename = "${txt_abs}" }
                    }
                ]
            }
            audio.channels = 2
            audio.position = [ FL FR ]
            capture.props = {
                node.name   = "${SINK_NODE}"
                media.class = Audio/Sink
            }
            playback.props = {
                node.name           = "hd800s_eq_out"
                node.passive        = true
                node.dont-reconnect = true
                target.object       = "${sink}"
            }
        }
    }
]
EOF
    log_info "wrote ${CONF} (target: ${sink})"
    restart_pipewire
    verify_sink_appeared
    log_info "one-time step: select '${SINK_DESC}' as the default output device (KDE remembers it)"
    log_info "note: chain targets the DAC only; if the DAC is absent, EQ output stays idle by design"
}

mode_easyeffects() {
    local assets
    log_step "Provisioning headphone EQ (EasyEffects)"
    assets="$(find_assets)"
    [[ -f "${assets}/${EE_JSON_NAME}" ]] || die "missing ${assets}/${EE_JSON_NAME}
  Export it once: https://autoeq.app -> Sennheiser HD 800 S (oratory1990) -> EasyEffects,
  save as ${EE_JSON_NAME} in the assets dir, and regenerate it together with the
  parametric txt so the two modes never drift."

    if ! command -v easyeffects >/dev/null 2>&1; then
        command -v apt-get >/dev/null 2>&1 || die "easyeffects missing and apt-get unavailable"
        log_info "installing easyeffects (sudo)"
        sudo apt-get install -y easyeffects
    fi

    if deactivate_filterchain; then restart_pipewire; fi

    mkdir -p "${EE_PRESET_DIR}" "$(dirname "${AUTOSTART}")"
    ln -sfn "${assets}/${EE_JSON_NAME}" "${EE_PRESET}"
    cat > "${AUTOSTART}" <<EOF
[Desktop Entry]
Type=Application
Name=EasyEffects (service)
Exec=easyeffects --gapplication-service
Icon=com.github.wwmm.easyeffects
X-GNOME-Autostart-enabled=true
EOF
    if ! pgrep -x easyeffects >/dev/null 2>&1; then
        nohup easyeffects --gapplication-service >/dev/null 2>&1 &
        disown || true
    fi
    log_info "EasyEffects active; preset '${EE_PRESET_NAME}' linked"
    log_info "one-time step: in EasyEffects, load the preset and bind its autoload to the FiiO device"
}

mode_remove() {
    log_step "Removing provisioned headphone EQ"
    deactivate_easyeffects
    rm -f "${EE_PRESET}"
    if deactivate_filterchain; then restart_pipewire; fi
    log_info "teardown complete (packages left installed)"
}

mode_status() {
    local sink
    if [[ -f "${CONF}" ]]; then
        sink="$(existing_sink_from_conf || true)"
        log_info "mode: filter-chain (target: ${sink:-unknown})"
        [[ -L "${TXT_LINK}" ]] && log_info "asset link: ${TXT_LINK} -> $(readlink "${TXT_LINK}")"
        if command -v pw-cli >/dev/null 2>&1; then
            if pw-cli ls Node 2>/dev/null | grep -q "\"${SINK_NODE}\""; then
                log_info "sink '${SINK_DESC}': live"
            else
                log_info "sink '${SINK_DESC}': NOT live"
            fi
        fi
    elif [[ -e "${AUTOSTART}" || -e "${EE_PRESET}" ]]; then
        log_info "mode: easyeffects (autostart: $([[ -e ${AUTOSTART} ]] && echo yes || echo no), preset: $([[ -e ${EE_PRESET} ]] && echo linked || echo missing))"
    else
        log_info "mode: none (no EQ provisioned)"
    fi
}

# --- main --------------------------------------------------------------------
[[ "${EUID}" -eq 0 && -z "${AUDIO_EQ_ALLOW_ROOT:-}" ]] \
    && die "run as your user, not root (writes user-scope config)"

MODE="filterchain"
SINK_ARG=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --easyeffects) MODE="easyeffects" ;;
        --remove)      MODE="remove" ;;
        --status)      MODE="status" ;;
        --sink)        shift; [[ $# -gt 0 ]] || die "--sink requires a value"; SINK_ARG="$1" ;;
        -h|--help)     usage 0 ;;
        *)             warn "unknown argument: $1"; usage 1 ;;
    esac
    shift
done

case "${MODE}" in
    filterchain) mode_filterchain ;;
    easyeffects) mode_easyeffects ;;
    remove)      mode_remove ;;
    status)      mode_status ;;
esac
