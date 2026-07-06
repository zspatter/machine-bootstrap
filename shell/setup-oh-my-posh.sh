#!/usr/bin/env bash
#
# Fresh-machine bootstrap: installs oh-my-posh via its official installer
# into ~/.local/bin. The prompt *config* lives in dotfiles (sym-lattice)
# and depends on this binary existing -- without it a fresh machine comes
# up with a broken prompt.
#
# Note: oh-my-posh themes generally want a Nerd Font, which is a
# per-machine, partly-GUI concern (terminal settings) left out of scope
# here -- `oh-my-posh font install` exists for it interactively.
#
# Safe to re-run. Linux and macOS; needs curl or wget.

set -euo pipefail

log_step() { printf '\n==> %s\n' "$1"; }
log_info() { printf '    %s\n' "$1"; }

fetch() {
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL --retry 3 "$1" -o "$2"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$2" --tries=3 "$1"
    else
        log_info 'Neither curl nor wget found; install one, then re-run.'
        exit 1
    fi
}

run_privileged() {
    if [[ "$(id -u)" -eq 0 ]]; then "$@"; else sudo "$@"; fi
}

ensure_unzip() {
    # The official installer hard-requires unzip; minimal containers (and
    # potentially minimal server installs) don't ship it. Caught in CI --
    # native runners have it preinstalled, containers don't.
    command -v unzip >/dev/null 2>&1 && return
    if command -v apt-get >/dev/null 2>&1; then
        run_privileged apt-get update
        run_privileged apt-get install -y unzip
    elif command -v pacman >/dev/null 2>&1; then
        run_privileged pacman -Syu --noconfirm --needed unzip
    else
        log_info 'unzip is required by the oh-my-posh installer; install it, then re-run.'
        exit 1
    fi
}

log_step 'Installing / locating oh-my-posh'
if command -v oh-my-posh >/dev/null 2>&1; then
    log_info "oh-my-posh already installed: $(oh-my-posh version) at $(command -v oh-my-posh)"
    log_info 'To update: oh-my-posh upgrade'
    exit 0
fi

ensure_unzip

# Official installer, downloaded to a file first rather than piped
# straight into bash -- same hygiene as the uv installer.
tmp=$(mktemp)
fetch 'https://ohmyposh.dev/install.sh' "$tmp"
bash "$tmp" -d "$HOME/.local/bin"
rm -f "$tmp"

log_step 'Verifying'
export PATH="$HOME/.local/bin:$PATH"
log_info "oh-my-posh $(oh-my-posh version) at $(command -v oh-my-posh)"

log_step 'Done'
log_info 'Prompt config comes from your dotfiles; themes generally want a Nerd Font (out of scope here).'
