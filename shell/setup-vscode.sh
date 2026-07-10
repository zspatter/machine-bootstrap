#!/usr/bin/env bash
#
# Fresh-machine bootstrap: installs Visual Studio Code. Refuses WSL --
# there you want the Windows VS Code (setup-vscode.ps1) plus its Remote-WSL
# extension, not a Linux build inside the distro.
#
# apt uses Microsoft's official repo (armored key via signed-by; modern
# apt handles .asc directly, no gpg --dearmor dependency). pacman installs
# `code`, the open-source build in Arch's official repos -- Microsoft's
# proprietary build is AUR-only, and this script doesn't do AUR; note the
# marketplace/telemetry differences if they matter to you. macOS uses the
# brew cask (proprietary build).
#
# Extension sync is a fixed-path contract (like PES in setup-nvim-tooling):
# sym-lattice's symlink-manager links dotfiles/vscode/extensions.txt to
# ~/.vscode/extensions.txt, and anything listed there installs if missing.
# Never uninstalls -- prune by hand. No file = no-op, so this script stays
# usable standalone.
#
# Safe to re-run.

set -euo pipefail

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

install_vscode_apt() {
    log_step "Installing VS Code (Microsoft's apt repo)"
    run_privileged apt-get update
    run_privileged apt-get install -y curl ca-certificates

    run_privileged mkdir -p -m 755 /etc/apt/keyrings
    curl -fsSL --retry 3 https://packages.microsoft.com/keys/microsoft.asc \
        | run_privileged tee /etc/apt/keyrings/microsoft.asc >/dev/null
    run_privileged chmod go+r /etc/apt/keyrings/microsoft.asc

    echo "deb [arch=amd64,arm64 signed-by=/etc/apt/keyrings/microsoft.asc] https://packages.microsoft.com/repos/code stable main" \
        | run_privileged tee /etc/apt/sources.list.d/vscode.list >/dev/null

    run_privileged apt-get update
    run_privileged apt-get install -y code
}

sync_extensions() {
    local ext_file="$HOME/.vscode/extensions.txt"
    command -v code >/dev/null 2>&1 || return 0
    [[ -f "$ext_file" ]] || { log_info "No $ext_file -- extension sync skipped (symlink-manager deploys it)."; return 0; }
    log_step 'Syncing VS Code extensions'
    local installed ext
    installed=$(code --list-extensions 2>/dev/null)
    while IFS= read -r ext; do
        ext="${ext%%#*}"
        ext="$(echo "$ext" | tr -d '[:space:]')"
        [[ -z "$ext" ]] && continue
        if grep -qix -- "$ext" <<<"$installed"; then
            log_info "$ext already installed"
        else
            log_info "Installing $ext"
            code --install-extension "$ext" >/dev/null || log_info "FAILED: $ext"
        fi
    done <"$ext_file"
}

main() {
    if command -v code >/dev/null 2>&1; then
        log_step 'VS Code already installed'
        log_info "$(code --version 2>/dev/null | head -n1) at $(command -v code)"
        sync_extensions
        exit 0
    fi

    case "$(uname -s)" in
        Linux)
            if grep -qi microsoft /proc/version 2>/dev/null; then
                log_step 'WSL detected -- skipping'
                log_info 'Use Windows VS Code (setup-vscode.ps1) with the Remote-WSL extension instead of a Linux build inside WSL.'
                exit 0
            fi
            if command -v apt-get >/dev/null 2>&1; then
                install_vscode_apt
            elif command -v pacman >/dev/null 2>&1; then
                log_step "Installing code (Arch's open-source build)"
                run_privileged pacman -Syu --noconfirm --needed code
            else
                log_info 'No supported package manager found (apt/pacman); install manually from https://code.visualstudio.com, then re-run.'
                exit 1
            fi
            ;;
        Darwin)
            log_step 'Installing VS Code (brew cask)'
            if ! command -v brew >/dev/null 2>&1; then
                log_info 'Homebrew not found. Install it from https://brew.sh, then re-run.'
                exit 1
            fi
            run_brew install --cask visual-studio-code
            ;;
        *)
            log_info "Unsupported OS: $(uname -s). See setup-vscode.ps1 for Windows."
            exit 1
            ;;
    esac

    log_step 'Verifying'
    log_info "$(code --version 2>/dev/null | head -n1) at $(command -v code)"
    sync_extensions
    log_step 'Done'
}

main "$@"
