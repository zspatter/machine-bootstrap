#!/usr/bin/env bash
#
# Fresh-machine bootstrap: installs Neovim from the official release
# tarball into ~/.local -- distro packages (especially Debian stable) are
# often years behind and too old for the modern plugin ecosystem, so this
# takes the uv approach: current prebuilt binaries everywhere, per-user.
#
# Re-running updates to the latest release (the managed install under
# ~/.local/opt/nvim is replaced). A foreign nvim already on PATH is left
# alone. Config is NOT this script's job -- dotfiles handle that.
#
# Safe to re-run. Linux and macOS; needs curl or wget, and tar.

set -euo pipefail

MANAGED_DIR="$HOME/.local/opt/nvim"

log_step() { printf '\n==> %s\n' "$1"; }
log_info() { printf '    %s\n' "$1"; }

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

asset_name() {
    # Official release asset naming as of v0.10.4+ (verified against the
    # live releases page).
    case "$(uname -s)/$(uname -m)" in
        Linux/x86_64) echo 'nvim-linux-x86_64' ;;
        Linux/aarch64) echo 'nvim-linux-arm64' ;;
        Darwin/arm64) echo 'nvim-macos-arm64' ;;
        Darwin/x86_64) echo 'nvim-macos-x86_64' ;;
        *)
            log_info "Unsupported platform: $(uname -s)/$(uname -m)."
            exit 1
            ;;
    esac
}

install_nvim() {
    if [[ ! -d "$MANAGED_DIR" ]] && command -v nvim >/dev/null 2>&1; then
        log_step 'Foreign nvim install detected -- leaving it alone'
        log_info "$(nvim --version | head -n1) at $(command -v nvim)"
        log_info "Remove it if you want this script's managed latest-release install instead."
        exit 0
    fi

    local asset tarball tmpdir
    asset=$(asset_name)
    log_step "Installing Neovim (latest release, $asset)"

    tmpdir=$(mktemp -d)
    tarball="$tmpdir/$asset.tar.gz"
    fetch "https://github.com/neovim/neovim/releases/latest/download/$asset.tar.gz" "$tarball"

    # macOS gatekeeper quarantines downloaded binaries ("unknown
    # developer"); clearing the xattr on the tarball before extraction is
    # the neovim-documented fix.
    if [[ "$(uname -s)" == "Darwin" ]] && command -v xattr >/dev/null 2>&1; then
        xattr -c "$tarball" 2>/dev/null || true
    fi

    rm -rf "$MANAGED_DIR"
    mkdir -p "$MANAGED_DIR"
    tar -xzf "$tarball" -C "$MANAGED_DIR" --strip-components=1
    rm -rf "$tmpdir"

    mkdir -p "$HOME/.local/bin"
    ln -sf "$MANAGED_DIR/bin/nvim" "$HOME/.local/bin/nvim"
}

install_nvim

log_step 'Verifying'
export PATH="$HOME/.local/bin:$PATH"
log_info "$(nvim --version | head -n1) at $(command -v nvim)"

log_step 'Done'
log_info 'Re-run this script to update to the latest release.'
log_info 'Config is handled by your dotfiles (sym-lattice), not here.'
