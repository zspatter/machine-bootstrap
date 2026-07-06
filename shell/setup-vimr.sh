#!/usr/bin/env bash
#
# Fresh-machine bootstrap: installs VimR, the macOS-native Neovim GUI
# (window management, native tabs/fonts -- the Mac-feeling alternative to
# the cross-platform Neovide, which setup-neovide.sh covers everywhere).
# macOS-only by nature: no Linux or Windows build exists, so this script
# self-skips everywhere else rather than pretending. Config is NOT this
# script's job -- VimR reads the same nvim config the dotfiles deploy.
#
# Safe to re-run. Needs Homebrew (the cask is the official distribution).

set -euo pipefail

log_step() { printf '\n==> %s\n' "$1"; }
log_info() { printf '    %s\n' "$1"; }

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

if [[ "$(uname -s)" != 'Darwin' ]]; then
    log_step 'VimR: skipped'
    log_info 'VimR is macOS-only (no Linux/Windows build); Neovide is the GUI everywhere else.'
    exit 0
fi

if ! command -v brew >/dev/null 2>&1; then
    log_step 'VimR: skipped'
    log_info 'Homebrew not found. Install it from https://brew.sh, then re-run.'
    exit 1
fi

log_step 'Installing VimR'
if [[ -d '/Applications/VimR.app' ]]; then
    log_info 'VimR.app already present -- skipping.'
    log_info 'To update: brew upgrade --cask vimr'
else
    run_brew install --cask vimr
fi

log_step 'Verifying'
if [[ -d '/Applications/VimR.app' ]]; then
    log_info 'VimR.app present'
else
    log_info 'VimR.app not found after install -- check the brew output above.'
    exit 1
fi

log_step 'Done'
log_info 'VimR picks up the deployed nvim config automatically (same ~/.config/nvim).'
