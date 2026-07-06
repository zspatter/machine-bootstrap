#!/usr/bin/env bash
#
# Fresh-machine bootstrap: installs Claude Code (the CLI) via the official
# native installer -- the documented recommended path, and unlike the
# apt/brew/winget alternatives it auto-updates in the background.
# Installs to ~/.local/bin/claude. Works everywhere including WSL.
#
# Auth is interactive (`claude` then browser login) -- same boundary as
# setup-gh-cli: install-only, no credential automation.
#
# Safe to re-run. Needs curl or wget.

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

log_step 'Installing / locating Claude Code'
if command -v claude >/dev/null 2>&1; then
    log_info "claude already installed: $(claude --version 2>&1 | head -n1) at $(command -v claude)"
    log_info 'Native installs auto-update; run `claude update` to force one.'
    exit 0
fi

# Official installer, downloaded to a file first rather than piped
# straight into bash -- same hygiene as the uv installer.
tmp=$(mktemp)
fetch 'https://claude.ai/install.sh' "$tmp"
bash "$tmp"
rm -f "$tmp"

log_step 'Verifying'
export PATH="$HOME/.local/bin:$PATH"
log_info "$(claude --version 2>&1 | head -n1) at $(command -v claude)"

log_step 'Done'
log_info 'Run `claude` in a project to authenticate (interactive browser login).'
