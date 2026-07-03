#!/usr/bin/env bash
#
# Fresh-machine bootstrap: installs uv (Astral's Python toolchain manager)
# and a current default Python. Not project-specific -- per-project pins
# (.python-version / pyproject.toml) are handled per-repo, and uv
# auto-downloads whatever a project pins on first `uv run`.
#
# No scope concept, unlike the retired pyenv scripts: uv is per-user by
# design (a single static binary in ~/.local/bin, managed Pythons under
# ~/.local/share/uv), and Python installs are prebuilt downloads that take
# seconds with no build deps -- "run this once per account" replaces the
# old shared-root + permission-lockdown machinery outright.
#
# Safe to re-run. Linux and macOS; needs curl or wget.

set -euo pipefail

log_step() { printf '\n==> %s\n' "$1"; }
log_info() { printf '    %s\n' "$1"; }

fetch() {
    # fetch <url> <dest>
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "$1" -o "$2"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$2" "$1"
    else
        log_info 'Neither curl nor wget found; install one, then re-run.'
        exit 1
    fi
}

ensure_uv() {
    log_step 'Installing / locating uv'
    if command -v uv >/dev/null 2>&1; then
        log_info "uv already installed: $(uv --version) at $(command -v uv)"
        log_info 'To update it later: uv self update (standalone installs only).'
        return
    fi

    # Official standalone installer, downloaded to a file first rather than
    # piped straight into sh -- same trust either way, but this is
    # inspection-friendly and immune to executing a truncated stream.
    local tmp
    tmp=$(mktemp)
    fetch 'https://astral.sh/uv/install.sh' "$tmp"
    sh "$tmp"
    rm -f "$tmp"
}

activate_uv_path() {
    # The installer wires PATH into shell rc files for future shells; this
    # process needs it now. The installer drops an env file next to the
    # binary for exactly this purpose.
    if [[ -f "$HOME/.local/bin/env" ]]; then
        # shellcheck disable=SC1091
        . "$HOME/.local/bin/env"
    else
        export PATH="$HOME/.local/bin:$PATH"
    fi
    uv --version >/dev/null
}

install_default_python() {
    log_step 'Installing latest Python (uv-managed, prebuilt)'
    # Everything below runs from $HOME with --no-project, deliberately: uv
    # respects .python-version pins in the current directory, so running
    # this from inside a project would install the project's pin as the
    # machine-wide default instead of latest -- and a bare `uv run` there
    # would sync that whole project (build + dependency download) as a
    # side effect of a "bootstrap" script. Both caught on the first real
    # machine run, not by CI, whose checkouts have no pin to trip on.
    (
        cd "$HOME"
        # --default also exposes bare python/python3 executables in
        # ~/.local/bin, filling the old `pyenv global` niche. The flag is
        # still marked experimental upstream, so fall back to a plain
        # managed install rather than failing the whole bootstrap if it
        # disappears or changes; uv-managed flows (uv run, uv venv, uvx)
        # are identical either way.
        if ! uv python install --default; then
            log_info 'Experimental --default flag failed; installing without bare python/python3 shims.'
            uv python install
        fi

        log_info "uv: $(uv --version)"
        log_info "default python: $(uv run --no-project python --version 2>&1)"
    )
}

main() {
    case "$(uname -s)" in
        Linux|Darwin) ;;
        *)
            log_info "Unsupported OS: $(uname -s). This script targets Linux and macOS (see setup-uv.ps1 for Windows)."
            exit 1
            ;;
    esac

    ensure_uv
    activate_uv_path
    install_default_python

    log_step 'Done'
    log_info 'Open a new shell (or `source ~/.local/bin/env`) to pick up PATH.'
    log_info 'Per-project: `uv run <cmd>` with a .python-version/pyproject pin -- uv auto-downloads pinned versions on demand.'
    log_info 'To update later: `uv self update` and `uv python upgrade`.'
}

main "$@"
