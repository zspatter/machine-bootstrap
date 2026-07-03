#!/usr/bin/env bash
#
# Fresh-machine bootstrap: installs a curated bundle of small, zero-config
# CLI tools -- currently jq, ripgrep, fd, fzf, bat, zoxide. One list-driven
# script rather than a file pair per tool, since these all share the same
# shape: single package, no setup, every package manager has them.
# Adding a tool later = adding one entry to the lists below.
#
# Safe to re-run. Debian/Ubuntu/Kali (apt), Arch/CachyOS (pacman),
# macOS (brew).

set -euo pipefail

# Expected command names, used for verification on every platform.
COMMANDS=(jq rg fd fzf bat zoxide)

APT_PACKAGES=(jq ripgrep fd-find fzf bat zoxide)
PACMAN_PACKAGES=(jq ripgrep fd fzf bat zoxide)
BREW_PACKAGES=(jq ripgrep fd fzf bat zoxide)

log_step() { printf '\n==> %s\n' "$1"; }
log_info() { printf '    %s\n' "$1"; }

run_privileged() {
    if [[ "$(id -u)" -eq 0 ]]; then "$@"; else sudo "$@"; fi
}

run_brew() {
    if [[ "$(id -u)" -eq 0 ]]; then
        if [[ -z "${SUDO_USER:-}" ]]; then
            log_info 'Running as root with no SUDO_USER; cannot invoke Homebrew. Install as a normal user.'
            return 1
        fi
        sudo -u "$SUDO_USER" -H brew "$@"
    else
        brew "$@"
    fi
}

install_tools() {
    log_step 'Installing CLI tools bundle'
    case "$(uname -s)" in
        Linux)
            if command -v apt-get >/dev/null 2>&1; then
                run_privileged apt-get update
                run_privileged apt-get install -y "${APT_PACKAGES[@]}"
            elif command -v pacman >/dev/null 2>&1; then
                run_privileged pacman -Syu --noconfirm --needed "${PACMAN_PACKAGES[@]}"
            else
                log_info 'No supported package manager found (apt/pacman); install manually, then re-run.'
                exit 1
            fi
            ;;
        Darwin)
            if ! command -v brew >/dev/null 2>&1; then
                log_info 'Homebrew not found. Install it from https://brew.sh, then re-run.'
                exit 1
            fi
            run_brew install "${BREW_PACKAGES[@]}"
            ;;
        *)
            log_info "Unsupported OS: $(uname -s). This script targets Linux and macOS (see setup-cli-tools.ps1 for Windows)."
            exit 1
            ;;
    esac
}

fix_debian_names() {
    # Debian/Ubuntu package fd-find installs the binary as `fdfind`, and
    # bat installs as `batcat` (upstream-name collisions with older Debian
    # packages). Alias them to their real names in ~/.local/bin so
    # dotfiles/scripts referencing fd/bat work identically across distros.
    mkdir -p "$HOME/.local/bin"
    if ! command -v fd >/dev/null 2>&1 && command -v fdfind >/dev/null 2>&1; then
        ln -sf "$(command -v fdfind)" "$HOME/.local/bin/fd"
        log_info 'Aliased fdfind -> ~/.local/bin/fd (Debian package naming)'
    fi
    if ! command -v bat >/dev/null 2>&1 && command -v batcat >/dev/null 2>&1; then
        ln -sf "$(command -v batcat)" "$HOME/.local/bin/bat"
        log_info 'Aliased batcat -> ~/.local/bin/bat (Debian package naming)'
    fi
}

verify() {
    log_step 'Verifying'
    export PATH="$HOME/.local/bin:$PATH"
    local missing=0
    for cmd in "${COMMANDS[@]}"; do
        if command -v "$cmd" >/dev/null 2>&1; then
            log_info "$cmd: $("$cmd" --version 2>&1 | head -n1)"
        else
            log_info "$cmd: MISSING"
            missing=1
        fi
    done
    return "$missing"
}

install_tools
fix_debian_names
verify
log_step 'Done'
