#!/usr/bin/env bash
#
# Fresh-machine bootstrap: installs the Claude Desktop app. Refuses WSL
# (GUI app -- use setup-claude-desktop.ps1 on the Windows host).
#
# Linux support is beta and Debian-family only (Ubuntu 22.04+/Debian 12+),
# via Anthropic's official signed apt repo -- updates then arrive through
# normal system updates. No Arch/Fedora builds exist yet; the CLI
# (setup-claude-code.sh) covers those. macOS uses the brew cask.
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

install_claude_desktop_apt() {
    # Official instructions (code.claude.com/docs/en/desktop-linux):
    # signed apt repo keyed by Anthropic's release key.
    log_step "Installing Claude Desktop (Anthropic's apt repo)"
    run_privileged apt-get update
    run_privileged apt-get install -y curl ca-certificates

    curl -fsSL https://downloads.claude.ai/claude-desktop/key.asc \
        | run_privileged tee /usr/share/keyrings/claude-desktop-archive-keyring.asc >/dev/null
    echo "deb [arch=amd64,arm64 signed-by=/usr/share/keyrings/claude-desktop-archive-keyring.asc] https://downloads.claude.ai/claude-desktop/apt/stable stable main" \
        | run_privileged tee /etc/apt/sources.list.d/claude-desktop.list >/dev/null

    run_privileged apt-get update
    run_privileged apt-get install -y claude-desktop
}

main() {
    if command -v claude-desktop >/dev/null 2>&1 || [[ -d /Applications/Claude.app ]]; then
        log_step 'Claude Desktop already installed'
        exit 0
    fi

    case "$(uname -s)" in
        Linux)
            if grep -qi microsoft /proc/version 2>/dev/null; then
                log_step 'WSL detected -- skipping'
                log_info 'Run setup-claude-desktop.ps1 on the Windows host instead.'
                exit 0
            fi
            if command -v apt-get >/dev/null 2>&1; then
                install_claude_desktop_apt
            else
                log_step 'Non-Debian Linux -- skipping'
                log_info 'Claude Desktop for Linux is beta and Debian-family only; the CLI (setup-claude-code.sh) works everywhere.'
                exit 0
            fi
            ;;
        Darwin)
            log_step 'Installing Claude Desktop (brew cask)'
            if ! command -v brew >/dev/null 2>&1; then
                log_info 'Homebrew not found. Install it from https://brew.sh, then re-run.'
                exit 1
            fi
            run_brew install --cask claude
            ;;
        *)
            log_info "Unsupported OS: $(uname -s). See setup-claude-desktop.ps1 for Windows."
            exit 1
            ;;
    esac

    log_step 'Verifying'
    if command -v claude-desktop >/dev/null 2>&1; then
        log_info "claude-desktop at $(command -v claude-desktop)"
    elif [[ -d /Applications/Claude.app ]]; then
        log_info 'Claude.app installed.'
    fi
    log_step 'Done'
}

main "$@"
