#!/usr/bin/env bash
#
# Fresh-machine bootstrap: installs the GitHub CLI (gh). Not project-specific.
#
# Deliberately install-only, not auth-only: `gh auth login` is an
# interactive OAuth device-code / browser flow (or requires a
# pre-existing token via $GH_TOKEN) -- there's no way to complete it
# unattended without either hanging a non-interactive run or taking on
# secret-handling this script has no business doing. This installs the
# binary and tells you to run `gh auth login` yourself, once.
#
# Safe to re-run. Supports Debian/Ubuntu/Kali (apt), Arch/CachyOS (pacman),
# and macOS (brew).

set -euo pipefail

log_step() { printf '\n==> %s\n' "$1"; }
log_info() { printf '    %s\n' "$1"; }

detect_os() {
    case "$(uname -s)" in
        Linux) echo linux ;;
        Darwin) echo macos ;;
        *) echo unknown ;;
    esac
}

run_privileged() {
    if [[ "$(id -u)" -eq 0 ]]; then
        "$@"
    else
        sudo "$@"
    fi
}

run_brew() {
    if [[ "$(id -u)" -eq 0 ]]; then
        if [[ -z "${SUDO_USER:-}" ]]; then
            log_info 'Running as root with no SUDO_USER; cannot invoke Homebrew (it refuses to run as root). Install gh manually as a normal user.'
            return 1
        fi
        sudo -u "$SUDO_USER" -H brew "$@"
    else
        brew "$@"
    fi
}

install_gh_apt() {
    log_step 'Installing GitHub CLI (apt)'
    # Official install path (https://github.com/cli/cli/blob/trunk/docs/install_linux.md):
    # gh isn't in Debian/Ubuntu's default repos, so this adds GitHub's own
    # apt repo with a GPG-verified keyring (the modern /etc/apt/keyrings
    # approach, not the deprecated apt-key).
    run_privileged apt-get update
    run_privileged apt-get install -y curl ca-certificates

    run_privileged mkdir -p -m 755 /etc/apt/keyrings
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        | run_privileged tee /etc/apt/keyrings/githubcli-archive-keyring.gpg >/dev/null
    run_privileged chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg

    run_privileged mkdir -p -m 755 /etc/apt/sources.list.d
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
        | run_privileged tee /etc/apt/sources.list.d/github-cli.list >/dev/null

    run_privileged apt-get update
    run_privileged apt-get install -y gh
}

install_gh_pacman() {
    log_step 'Installing GitHub CLI (pacman)'
    # github-cli is in Arch's official "extra" repo -- no separate
    # repo/key setup needed, unlike apt. -Syu per Arch's partial-upgrade
    # guidance (see setup-python-env.sh).
    run_privileged pacman -Syu --noconfirm --needed github-cli
}

install_gh_linux() {
    if command -v gh >/dev/null 2>&1; then
        log_info "gh already installed: $(gh --version | head -n1)"
        return
    fi

    if command -v apt-get >/dev/null 2>&1; then
        install_gh_apt
    elif command -v pacman >/dev/null 2>&1; then
        install_gh_pacman
    else
        log_step 'Installing GitHub CLI'
        log_info 'No supported package manager found (apt/pacman); install gh manually from https://cli.github.com, then re-run.'
    fi
}

install_gh_macos() {
    if command -v gh >/dev/null 2>&1; then
        log_info "gh already installed: $(gh --version | head -n1)"
        return
    fi

    log_step 'Installing GitHub CLI (Homebrew)'
    if ! command -v brew >/dev/null 2>&1; then
        log_info 'Homebrew not found. Install it from https://brew.sh, then re-run.'
        exit 1
    fi

    run_brew install gh
}

report_auth_status() {
    log_step 'Checking auth status'
    if gh auth status >/dev/null 2>&1; then
        log_info 'Already authenticated.'
    else
        log_info "Not authenticated. Run 'gh auth login' to authenticate -- this needs your interactive input (browser or token), not something a bootstrap script can do for you."
    fi
}

main() {
    local os
    os=$(detect_os)

    case "$os" in
        linux) install_gh_linux ;;
        macos) install_gh_macos ;;
        *)
            log_info "Unsupported OS: $(uname -s). This script targets Linux and macOS."
            exit 1
            ;;
    esac

    if command -v gh >/dev/null 2>&1; then
        log_info "gh version: $(gh --version | head -n1)"
        report_auth_status
    fi

    log_step 'Done'
}

main "$@"
