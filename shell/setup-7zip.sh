#!/usr/bin/env bash
#
# Fresh-machine bootstrap: 7-Zip's official CLI (7zz) everywhere.
#
#   apt    : '7zip' (the official upstream CLI; debian 12+/ubuntu 22.04+),
#            falling back to p7zip-full (the older fork; binary is `7z`)
#            on distros that predate the official package.
#   pacman : 7zip (official, replaced p7zip).
#   brew   : sevenzip -- the official 7zz from 7-zip.org, NOT the stale
#            p7zip fork that used to be the least-bad macOS answer --
#            PLUS Keka (cask), the 7z-based GUI that provides the
#            in-Finder integration 7zz can't. One manual toggle after
#            Keka's first launch: enable its Finder extension in Keka
#            settings (and optionally set it as the default archiver).
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

main() {
    case "$(uname -s)" in
        Linux)
            if command -v 7zz >/dev/null 2>&1 || command -v 7z >/dev/null 2>&1; then
                log_step '7-Zip already installed'
                log_info "$(command -v 7zz 2>/dev/null || command -v 7z)"
            elif command -v apt-get >/dev/null 2>&1; then
                log_step 'Installing 7zip (apt)'
                run_privileged apt-get update
                run_privileged apt-get install -y 7zip \
                    || run_privileged apt-get install -y p7zip-full
            elif command -v pacman >/dev/null 2>&1; then
                log_step 'Installing 7zip (pacman)'
                run_privileged pacman -Syu --noconfirm --needed 7zip
            else
                log_info 'No supported package manager (apt/pacman); install 7-Zip manually, then re-run.'
                exit 1
            fi
            ;;
        Darwin)
            if ! command -v brew >/dev/null 2>&1; then
                log_info 'Homebrew not found. Install it from https://brew.sh, then re-run.'
                exit 1
            fi
            # each piece guarded separately so a provisioned machine
            # still picks up whichever half it's missing
            if command -v 7zz >/dev/null 2>&1; then
                log_step 'sevenzip already installed'
            else
                log_step 'Installing sevenzip (brew)'
                run_brew install sevenzip
            fi
            if [[ -d '/Applications/Keka.app' ]]; then
                log_step 'Keka already installed'
            else
                log_step 'Installing Keka (brew cask)'
                run_brew install --cask keka
                log_info 'Manual once: enable the Finder extension in Keka settings (context menu / Services); optionally set Keka as the default archiver.'
            fi
            ;;
        *)
            log_info "Unsupported OS: $(uname -s). See setup-7zip.ps1 for Windows."
            exit 1
            ;;
    esac

    log_step 'Verifying'
    if command -v 7zz >/dev/null 2>&1 || command -v 7z >/dev/null 2>&1; then
        log_info "$(command -v 7zz 2>/dev/null || command -v 7z)"
    else
        log_info '7zz/7z not resolvable in this session; open a new shell and verify.'
    fi
    log_step 'Done'
}

main "$@"
