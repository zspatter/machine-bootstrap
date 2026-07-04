#!/usr/bin/env bash
#
# Fresh-machine bootstrap: installs the Zed editor.
#
# Safe to re-run. Linux uses Zed's official installer script (downloaded
# to disk first, never piped straight to sh -- house rule), macOS uses
# the brew cask. Refuses WSL: a Linux GUI app inside WSL is almost never
# what you want -- run setup-zed.ps1 on the Windows host instead.

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

main() {
    export PATH="$HOME/.local/bin:$PATH"
    if command -v zed >/dev/null 2>&1 || [[ -d /Applications/Zed.app ]]; then
        log_step 'Zed already installed'
        log_info 'Zed updates itself in-app.'
        exit 0
    fi

    case "$(uname -s)" in
        Linux)
            if grep -qi microsoft /proc/version 2>/dev/null; then
                log_step 'WSL detected -- skipping'
                log_info 'A Linux GUI app inside WSL is almost never what you want; run setup-zed.ps1 on the Windows host instead.'
                exit 0
            fi
            log_step "Installing Zed (official installer, downloaded first per house rule)"
            local tmpdir
            tmpdir=$(mktemp -d)
            fetch 'https://zed.dev/install.sh' "$tmpdir/zed-install.sh"
            sh "$tmpdir/zed-install.sh"
            rm -rf "$tmpdir"
            ;;
        Darwin)
            if ! command -v brew >/dev/null 2>&1; then
                log_info 'Homebrew not found. Install it from https://brew.sh, then re-run.'
                exit 1
            fi
            log_step 'Installing Zed (brew cask)'
            run_brew install --cask zed
            ;;
        *)
            log_info "Unsupported OS: $(uname -s). See setup-zed.ps1 for Windows."
            exit 1
            ;;
    esac

    log_step 'Done'
}

main "$@"
