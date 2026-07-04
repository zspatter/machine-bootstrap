#!/usr/bin/env bash
#
# Fresh-machine bootstrap: installs Neovide (GUI frontend for Neovim).
# The nvim config it renders lives in sym-lattice; Neovide embeds whatever
# nvim is on PATH, so setup-nvim.sh is the real prerequisite.
#
# Safe to re-run. Arch/CachyOS (pacman, official package), other Linux
# (AppImage from GitHub releases -> ~/.local/bin), macOS (brew cask).
# Refuses WSL: a Linux GUI app inside WSL is almost never what you want --
# install on the Windows host with setup-neovide.ps1 instead.

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

install_neovide_appimage() {
    # Neovide publishes an AppImage; a single self-contained executable
    # into ~/.local/bin is the least-moving-parts install for non-Arch
    # distros (no fuse mount needed on modern AppImages with --appimage-
    # extract-and-run fallbacks; plain execution works on typical desktops).
    log_step 'Installing Neovide (AppImage from GitHub releases)'
    if [[ "$(uname -m)" != 'x86_64' ]]; then
        log_info "No AppImage published for $(uname -m); build from source or use a distro package."
        exit 1
    fi
    local tmpdir
    tmpdir=$(mktemp -d)
    fetch 'https://github.com/neovide/neovide/releases/latest/download/neovide.AppImage' \
         "$tmpdir/neovide.AppImage"
    mkdir -p "$HOME/.local/bin"
    install -m 0755 "$tmpdir/neovide.AppImage" "$HOME/.local/bin/neovide"
    rm -rf "$tmpdir"

    mkdir -p "$HOME/.local/share/applications"
    cat > "$HOME/.local/share/applications/neovide.desktop" <<DESKTOP
[Desktop Entry]
Name=Neovide
Exec=$HOME/.local/bin/neovide %F
Type=Application
Categories=Utility;TextEditor;
DESKTOP
}

main() {
    export PATH="$HOME/.local/bin:$PATH"
    if command -v neovide >/dev/null 2>&1 || [[ -d /Applications/Neovide.app ]]; then
        log_step 'Neovide already installed'
        log_info 'Update via your package manager (pacman/brew) or re-run after removing ~/.local/bin/neovide.'
        exit 0
    fi

    case "$(uname -s)" in
        Linux)
            if grep -qi microsoft /proc/version 2>/dev/null; then
                log_step 'WSL detected -- skipping'
                log_info 'A Linux GUI app inside WSL is almost never what you want; run setup-neovide.ps1 on the Windows host instead.'
                exit 0
            fi
            if command -v pacman >/dev/null 2>&1; then
                log_step 'Installing Neovide (pacman)'
                run_privileged pacman -Syu --noconfirm --needed neovide
            else
                install_neovide_appimage
            fi
            ;;
        Darwin)
            if ! command -v brew >/dev/null 2>&1; then
                log_info 'Homebrew not found. Install it from https://brew.sh, then re-run.'
                exit 1
            fi
            log_step 'Installing Neovide (brew cask)'
            run_brew install --cask neovide
            ;;
        *)
            log_info "Unsupported OS: $(uname -s). See setup-neovide.ps1 for Windows."
            exit 1
            ;;
    esac

    log_step 'Done'
}

main "$@"
