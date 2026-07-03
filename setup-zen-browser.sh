#!/usr/bin/env bash
#
# Fresh-machine bootstrap: installs Zen Browser. Refuses WSL (GUI app --
# use setup-zen-browser.ps1 on the Windows host).
#
# Linux has no Zen repo for apt/pacman (AUR only on Arch), so this uses
# the official release tarball into ~/.local, nvim-style: re-running
# updates to latest, and a .desktop entry is written for launcher
# integration. Note tarball installs don't self-update. macOS uses the
# brew cask.
#
# Safe to re-run. Linux needs curl/wget, tar, and xz.

set -euo pipefail

MANAGED_DIR="$HOME/.local/opt/zen"

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

fetch() {
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "$1" -o "$2"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$2" "$1"
    else
        log_info 'Neither curl nor wget found; install one, then re-run.'
        exit 1
    fi
}

ensure_xz() {
    # Zen ships .tar.xz; minimal containers may lack xz.
    command -v xz >/dev/null 2>&1 && return
    if command -v apt-get >/dev/null 2>&1; then
        run_privileged apt-get update
        run_privileged apt-get install -y xz-utils
    elif command -v pacman >/dev/null 2>&1; then
        run_privileged pacman -Syu --noconfirm --needed xz
    else
        log_info 'xz is required to extract the Zen tarball; install it, then re-run.'
        exit 1
    fi
}

install_zen_linux() {
    local asset
    case "$(uname -m)" in
        x86_64) asset='zen.linux-x86_64.tar.xz' ;;
        aarch64) asset='zen.linux-aarch64.tar.xz' ;;
        *)
            log_info "Unsupported architecture: $(uname -m)."
            exit 1
            ;;
    esac

    log_step "Installing Zen Browser (official tarball, $asset)"
    ensure_xz

    local tmpdir
    tmpdir=$(mktemp -d)
    fetch "https://github.com/zen-browser/desktop/releases/latest/download/$asset" "$tmpdir/$asset"

    rm -rf "$MANAGED_DIR"
    mkdir -p "$MANAGED_DIR"
    tar -xJf "$tmpdir/$asset" -C "$MANAGED_DIR" --strip-components=1
    rm -rf "$tmpdir"

    mkdir -p "$HOME/.local/bin"
    ln -sf "$MANAGED_DIR/zen" "$HOME/.local/bin/zen"

    mkdir -p "$HOME/.local/share/applications"
    cat > "$HOME/.local/share/applications/zen.desktop" <<DESKTOP
[Desktop Entry]
Name=Zen Browser
Exec=$MANAGED_DIR/zen %u
Icon=$MANAGED_DIR/browser/chrome/icons/default/default128.png
Type=Application
Categories=Network;WebBrowser;
MimeType=text/html;x-scheme-handler/http;x-scheme-handler/https;
DESKTOP
}

main() {
    if command -v zen >/dev/null 2>&1 || [[ -d /Applications/Zen.app ]]; then
        log_step 'Zen Browser already installed'
        log_info 'Linux tarball installs: re-run after removing ~/.local/opt/zen to force-update, or rely on this script re-running.'
        exit 0
    fi

    case "$(uname -s)" in
        Linux)
            if grep -qi microsoft /proc/version 2>/dev/null; then
                log_step 'WSL detected -- skipping'
                log_info 'Run setup-zen-browser.ps1 on the Windows host instead.'
                exit 0
            fi
            install_zen_linux
            ;;
        Darwin)
            log_step 'Installing Zen Browser (brew cask)'
            if ! command -v brew >/dev/null 2>&1; then
                log_info 'Homebrew not found. Install it from https://brew.sh, then re-run.'
                exit 1
            fi
            run_brew install --cask zen
            ;;
        *)
            log_info "Unsupported OS: $(uname -s). See setup-zen-browser.ps1 for Windows."
            exit 1
            ;;
    esac

    log_step 'Verifying'
    if command -v zen >/dev/null 2>&1; then
        log_info "$("$HOME/.local/bin/zen" --version 2>/dev/null | head -n1 || echo 'zen installed') at $(command -v zen)"
    elif [[ -d /Applications/Zen.app ]]; then
        log_info 'Zen.app installed.'
    fi
    log_step 'Done'
    log_info 'Tarball installs do not self-update -- re-run this script to update (Linux only).'
}

main "$@"
