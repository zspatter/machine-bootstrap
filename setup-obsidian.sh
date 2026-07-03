#!/usr/bin/env bash
#
# Fresh-machine bootstrap: installs Obsidian (the app only). Vault setup
# is deliberately not here -- a notes vault is personal data, and this
# repo is public; sym-lattice's onboarding handles the private vault
# clone, matching the existing public/private split.
#
# Safe to re-run. Debian/Ubuntu/Kali (apt, via the official .deb from
# GitHub releases -- Obsidian has no apt repo), Arch/CachyOS (pacman,
# official package), macOS (brew cask). Refuses WSL: a Linux GUI app
# inside WSL is almost never what you want -- install on the Windows host
# with setup-obsidian.ps1 instead.

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

install_obsidian_deb() {
    # No apt repo exists; the official distribution for Debian-family is
    # the .deb attached to each GitHub release. Resolve the latest via the
    # API without depending on jq (this script may run before
    # setup-cli-tools).
    log_step 'Installing Obsidian (.deb from GitHub releases)'
    local api tmpdir deb url
    api='https://api.github.com/repos/obsidianmd/obsidian-releases/releases/latest'
    tmpdir=$(mktemp -d)

    fetch "$api" "$tmpdir/release.json"
    url=$(grep -o '"browser_download_url": *"[^"]*_amd64\.deb"' "$tmpdir/release.json" | head -n1 | sed 's/.*"\(https[^"]*\)"/\1/')
    if [[ -z "$url" ]]; then
        log_info 'Could not find an amd64 .deb asset in the latest release.'
        exit 1
    fi

    deb="$tmpdir/obsidian.deb"
    log_info "Downloading $url"
    fetch "$url" "$deb"
    run_privileged apt-get update
    run_privileged apt-get install -y "$deb"
    rm -rf "$tmpdir"
}

main() {
    if command -v obsidian >/dev/null 2>&1 || [[ -d /Applications/Obsidian.app ]]; then
        log_step 'Obsidian already installed'
        exit 0
    fi

    case "$(uname -s)" in
        Linux)
            if grep -qi microsoft /proc/version 2>/dev/null; then
                log_step 'WSL detected -- skipping'
                log_info 'A Linux GUI app inside WSL is almost never what you want; run setup-obsidian.ps1 on the Windows host instead.'
                exit 0
            fi
            if command -v apt-get >/dev/null 2>&1; then
                install_obsidian_deb
            elif command -v pacman >/dev/null 2>&1; then
                log_step 'Installing Obsidian (pacman)'
                run_privileged pacman -Syu --noconfirm --needed obsidian
            else
                log_info 'No supported package manager found (apt/pacman); install manually from https://obsidian.md, then re-run.'
                exit 1
            fi
            ;;
        Darwin)
            log_step 'Installing Obsidian (brew cask)'
            if ! command -v brew >/dev/null 2>&1; then
                log_info 'Homebrew not found. Install it from https://brew.sh, then re-run.'
                exit 1
            fi
            run_brew install --cask obsidian
            ;;
        *)
            log_info "Unsupported OS: $(uname -s). This script targets Linux and macOS (see setup-obsidian.ps1 for Windows)."
            exit 1
            ;;
    esac

    log_step 'Verifying'
    if command -v obsidian >/dev/null 2>&1; then
        log_info "obsidian at $(command -v obsidian)"
    elif [[ -d /Applications/Obsidian.app ]]; then
        log_info 'Obsidian.app installed.'
    else
        log_info 'Install finished but no obsidian binary found -- check the output above.'
        exit 1
    fi

    log_step 'Done'
    log_info 'Vault setup is personal data and lives in sym-lattice onboarding, not here.'
}

main "$@"
