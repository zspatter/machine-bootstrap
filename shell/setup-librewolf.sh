#!/usr/bin/env bash
#
# Fresh-machine bootstrap: installs LibreWolf. Refuses WSL (GUI app -- use
# setup-librewolf.ps1 on the Windows host).
#
# Debian-family uses LibreWolf's officially recommended extrepo path.
# Arch has no official-repo package (AUR only, which this script doesn't
# do) -- it exits with a pointer instead. macOS uses the brew cask with
# --no-quarantine per LibreWolf's own docs (their updater fights the
# quarantine attribute otherwise).
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

install_librewolf_apt() {
    # Official recommended path: extrepo manages the repo + keyring.
    log_step 'Installing LibreWolf (extrepo, official path)'
    run_privileged apt-get update
    run_privileged apt-get install -y extrepo
    run_privileged extrepo enable librewolf
    run_privileged extrepo update librewolf
    run_privileged apt-get update
    run_privileged apt-get install -y librewolf
}

main() {
    if command -v librewolf >/dev/null 2>&1 || [[ -d /Applications/LibreWolf.app ]]; then
        log_step 'LibreWolf already installed'
        exit 0
    fi

    case "$(uname -s)" in
        Linux)
            if grep -qi microsoft /proc/version 2>/dev/null; then
                log_step 'WSL detected -- skipping'
                log_info 'Run setup-librewolf.ps1 on the Windows host instead.'
                exit 0
            fi
            if command -v apt-get >/dev/null 2>&1; then
                install_librewolf_apt
            elif command -v pacman >/dev/null 2>&1; then
                log_step 'Arch detected -- skipping'
                log_info 'LibreWolf is AUR-only on Arch (librewolf-bin); this script does not manage AUR packages. Install via your AUR helper.'
                exit 0
            else
                log_info 'No supported package manager found; install manually from https://librewolf.net, then re-run.'
                exit 1
            fi
            ;;
        Darwin)
            log_step 'Installing LibreWolf (brew cask, no-quarantine per official docs)'
            if ! command -v brew >/dev/null 2>&1; then
                log_info 'Homebrew not found. Install it from https://brew.sh, then re-run.'
                exit 1
            fi
            # Current Homebrew rejects --no-quarantine as a command flag
            # ("invalid option", caught in CI); HOMEBREW_CASK_OPTS is the
            # supported mechanism for cask options now.
            export HOMEBREW_CASK_OPTS="--no-quarantine"
            run_brew install --cask librewolf
            ;;
        *)
            log_info "Unsupported OS: $(uname -s). See setup-librewolf.ps1 for Windows."
            exit 1
            ;;
    esac

    log_step 'Verifying'
    if command -v librewolf >/dev/null 2>&1; then
        log_info "$(librewolf --version 2>/dev/null | head -n1) at $(command -v librewolf)"
    elif [[ -d /Applications/LibreWolf.app ]]; then
        log_info 'LibreWolf.app installed.'
    fi
    log_step 'Done'
}

main "$@"
