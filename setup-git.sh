#!/usr/bin/env bash
#
# Fresh-machine bootstrap: installs git. Extracted from the retired
# setup-python-env.sh -- uv needs no git (prebuilt downloads, no repo
# clone), but cloning sym-lattice or anything else still does, and it's a
# near-universal requirement for a dev machine.
#
# Safe to re-run. Debian/Ubuntu/Kali (apt), Arch/CachyOS (pacman), and
# macOS (Xcode Command Line Tools).

set -euo pipefail

log_step() { printf '\n==> %s\n' "$1"; }
log_info() { printf '    %s\n' "$1"; }

run_privileged() {
    # Root-only environments (e.g. minimal containers) often don't have
    # `sudo` installed at all, and it's a no-op when already root anyway.
    if [[ "$(id -u)" -eq 0 ]]; then
        "$@"
    else
        sudo "$@"
    fi
}

install_git_linux() {
    log_step 'Installing git'
    if command -v apt-get >/dev/null 2>&1; then
        run_privileged apt-get update
        run_privileged apt-get install -y git
    elif command -v pacman >/dev/null 2>&1; then
        # -Syu, not a bare -S: Arch treats installing against a
        # freshly-synced database on top of stale local packages as an
        # unsupported partial upgrade.
        run_privileged pacman -Syu --noconfirm --needed git
    else
        log_info 'No supported package manager found (apt/pacman); install git manually, then re-run.'
        exit 1
    fi
}

install_git_macos() {
    log_step 'Installing git (Xcode Command Line Tools)'
    if xcode-select -p >/dev/null 2>&1; then
        log_info 'Xcode Command Line Tools already present.'
        return
    fi
    # This pops a GUI confirmation and installs asynchronously -- the
    # script can't wait on it. Tell the user and let them re-run.
    xcode-select --install || true
    log_info 'Command Line Tools install requested; confirm the dialog, then re-run this script to verify.'
    exit 0
}

main() {
    if command -v git >/dev/null 2>&1; then
        log_step 'git already installed'
        log_info "$(git --version) at $(command -v git)"
        return
    fi

    case "$(uname -s)" in
        Linux) install_git_linux ;;
        Darwin) install_git_macos ;;
        *)
            log_info "Unsupported OS: $(uname -s). This script targets Linux and macOS (see setup-git.ps1 for Windows)."
            exit 1
            ;;
    esac

    log_step 'Verifying'
    git --version
}

main "$@"
