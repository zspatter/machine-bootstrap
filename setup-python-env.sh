#!/usr/bin/env bash
#
# Fresh-machine bootstrap: installs pyenv, sets a global latest-release
# Python, and installs + hooks direnv. Not project-specific — no per-repo
# .python-version or .envrc handling here.
#
# Safe to re-run. Supports Debian/Ubuntu (apt) and macOS (brew).
#
# Usage: setup-python-env.sh [--system|--user]
#   --system  Shared install under /opt/pyenv, wired into system-wide shell
#             files (/etc/profile.d, /etc/zsh/zshenv on Linux; /etc/zshenv,
#             /etc/bashrc on macOS). Requires root. New user accounts get
#             the tooling automatically on next login — no per-user setup.
#             Only root can `pyenv install`/`pyenv global`; everyday users
#             can still use any already-installed version and `pyenv local`.
#   --user    Install under $HOME/.pyenv for the current user only.
#   (default) Auto-detected: root -> --system, otherwise -> --user.

set -euo pipefail

SYSTEM_PYENV_ROOT="${SYSTEM_PYENV_ROOT:-/opt/pyenv}"
PYTHON_VERSION="${PYTHON_VERSION:-}"
INCLUDE_FREE_THREADED="${INCLUDE_FREE_THREADED:-0}"

log_step() { printf '\n==> %s\n' "$1"; }
log_info() { printf '    %s\n' "$1"; }

detect_os() {
    case "$(uname -s)" in
        Linux) echo linux ;;
        Darwin) echo macos ;;
        *) echo unknown ;;
    esac
}

SCOPE_OVERRIDE=""
for arg in "$@"; do
    case "$arg" in
        --system) SCOPE_OVERRIDE="system" ;;
        --user) SCOPE_OVERRIDE="user" ;;
        -h|--help)
            sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
    esac
done

if [[ -n "$SCOPE_OVERRIDE" ]]; then
    SCOPE="$SCOPE_OVERRIDE"
elif [[ "$(id -u)" -eq 0 ]]; then
    SCOPE="system"
else
    SCOPE="user"
fi

if [[ "$SCOPE" == "system" && "$(id -u)" -ne 0 ]]; then
    log_info '--system requires root. Re-run with sudo.'
    exit 1
fi

if [[ "$SCOPE" == "system" ]]; then
    PYENV_ROOT_DEFAULT="$SYSTEM_PYENV_ROOT"
else
    PYENV_ROOT_DEFAULT="$HOME/.pyenv"
fi

# Root-only environments (e.g. minimal containers) often don't have `sudo`
# installed at all, and it's a no-op when we're already root anyway.
run_privileged() {
    if [[ "$(id -u)" -eq 0 ]]; then
        "$@"
    else
        sudo "$@"
    fi
}

# Homebrew refuses to run as root. Under --system on macOS we're root, so
# brew calls must be delegated to the user who invoked sudo.
run_brew() {
    if [[ "$(id -u)" -eq 0 ]]; then
        if [[ -z "${SUDO_USER:-}" ]]; then
            log_info 'Running as root with no SUDO_USER; cannot invoke Homebrew (it refuses to run as root). Install these packages manually as a normal user.'
            return 1
        fi
        sudo -u "$SUDO_USER" -H brew "$@"
    else
        brew "$@"
    fi
}

detect_shell_rc_files() {
    # user scope only: write to whatever rc files exist so the change takes
    # effect regardless of which shell the user actually launches.
    local files=()
    [[ -f "$HOME/.bashrc" ]] && files+=("$HOME/.bashrc")
    [[ -f "$HOME/.zshrc" ]] && files+=("$HOME/.zshrc")
    if [[ ${#files[@]} -eq 0 ]]; then
        files+=("$HOME/.bashrc")
        touch "$HOME/.bashrc"
    fi
    printf '%s\n' "${files[@]}"
}

# System-wide shell init targets, keyed by shell family, per OS. Linux
# reads /etc/profile.d/*.sh from login shells via /etc/profile, and every
# zsh instance (login or not) reads /etc/zsh/zshenv. macOS's default shell
# is zsh, which always reads /etc/zshenv; /etc/bashrc is best-effort for
# legacy bash (depends on the user's own ~/.bash_profile sourcing it).
bash_system_files() {
    local os; os=$(detect_os)
    if [[ "$os" == "linux" ]]; then
        echo "/etc/profile.d/machine-bootstrap.sh"
    else
        echo "/etc/bashrc"
    fi
}

zsh_system_files() {
    local os; os=$(detect_os)
    if [[ "$os" == "linux" ]]; then
        [[ -d /etc/zsh ]] && echo "/etc/zsh/zshenv"
    else
        echo "/etc/zshenv"
    fi
}

append_once() {
    # append_once <file> <marker> <block>
    local file="$1" marker="$2" block="$3"
    if [[ -f "$file" ]] && grep -qF "$marker" "$file"; then
        log_info "Already configured in $file"
        return
    fi
    printf '\n# %s\n%s\n' "$marker" "$block" >> "$file"
    chmod 644 "$file" 2>/dev/null || true
    log_info "Updated $file"
}

write_shell_block() {
    # write_shell_block <marker> <bash-block> <zsh-block>
    local marker="$1" bash_block="$2" zsh_block="$3"

    if [[ "$SCOPE" == "system" ]]; then
        while IFS= read -r f; do
            [[ -n "$f" ]] && append_once "$f" "$marker" "$bash_block"
        done < <(bash_system_files)
        while IFS= read -r f; do
            [[ -n "$f" ]] && append_once "$f" "$marker" "$zsh_block"
        done < <(zsh_system_files)
    else
        while IFS= read -r rc; do
            local block="$bash_block"
            [[ "$rc" == *zshrc ]] && block="$zsh_block"
            append_once "$rc" "$marker" "$block"
        done < <(detect_shell_rc_files)
    fi
}

harden_system_permissions() {
    [[ "$SCOPE" == "system" ]] || return 0
    # Shared root stays root-owned so only root can `pyenv install`/`pyenv
    # global`; a+rX lets every other account read/execute already-installed
    # versions and shims. Everyday users can still `pyenv local` freely.
    #
    # go-w is required, not optional: `a+rX` alone is purely additive and
    # won't strip a stray group/other write bit left over from whatever
    # umask created these files during clone/build. Confirmed in CI this
    # isn't hypothetical -- on one runner image a non-root user could still
    # write (and pyenv would silently rehash) with only `a+rX` applied,
    # because the ambient umask had already left the shims dir group- or
    # other-writable before this ran.
    chmod -R a+rX,go-w "$PYENV_ROOT_DEFAULT"
}

install_build_deps_apt() {
    log_step 'Installing pyenv build dependencies (apt)'

    local ncurses_pkg=libncurses-dev
    if ! apt-cache show "$ncurses_pkg" >/dev/null 2>&1; then
        # Renamed on newer Ubuntu; older distros may still need the old name.
        ncurses_pkg=libncursesw5-dev
    fi

    run_privileged apt-get update
    run_privileged apt-get install -y \
        build-essential libssl-dev zlib1g-dev libbz2-dev libreadline-dev \
        libsqlite3-dev "$ncurses_pkg" xz-utils tk-dev libxml2-dev \
        libxmlsec1-dev libffi-dev liblzma-dev curl
}

install_build_deps_pacman() {
    log_step 'Installing pyenv build dependencies (pacman)'

    # Arch (and derivatives like CachyOS) explicitly discourage a bare
    # `-Sy` sync without an immediate `-u` upgrade -- installing against a
    # freshly-synced database on top of stale local packages is an
    # unsupported "partial upgrade" that can break the system. -Syu keeps
    # sync+upgrade+install atomic.
    run_privileged pacman -Syu --noconfirm --needed \
        base-devel openssl zlib bzip2 readline sqlite ncurses xz tk \
        libxml2 xmlsec libffi curl
}

install_build_deps_linux() {
    if command -v apt-get >/dev/null 2>&1; then
        install_build_deps_apt
    elif command -v pacman >/dev/null 2>&1; then
        install_build_deps_pacman
    else
        log_step 'Installing pyenv build dependencies'
        log_info 'No supported package manager found (apt/pacman); install pyenv build deps for your distro manually, then re-run.'
    fi
}

install_build_deps_macos() {
    log_step 'Installing pyenv build dependencies (Homebrew)'
    if ! command -v brew >/dev/null 2>&1; then
        log_info 'Homebrew not found. Install it from https://brew.sh, then re-run.'
        exit 1
    fi

    if ! xcode-select -p >/dev/null 2>&1; then
        log_info 'Xcode Command Line Tools not found; requesting install (may need manual confirmation).'
        xcode-select --install || true
    fi

    run_brew install openssl readline sqlite3 xz zlib
}

ensure_pyenv() {
    log_step "Installing / locating pyenv ($SCOPE scope: $PYENV_ROOT_DEFAULT)"
    if [[ -d "$PYENV_ROOT_DEFAULT" ]]; then
        log_info "pyenv already present at $PYENV_ROOT_DEFAULT; updating."
        git -C "$PYENV_ROOT_DEFAULT" pull --quiet
    else
        git clone --depth 1 https://github.com/pyenv/pyenv.git "$PYENV_ROOT_DEFAULT"
    fi
    harden_system_permissions

    export PYENV_ROOT="$PYENV_ROOT_DEFAULT"
    export PATH="$PYENV_ROOT/bin:$PATH"
    eval "$(pyenv init - bash)"

    local root_expr='"$HOME/.pyenv"'
    [[ "$SCOPE" == "system" ]] && root_expr="\"$PYENV_ROOT_DEFAULT\""

    # `pyenv init -` always emits an auto-rehash call in its output, run on
    # every new shell. Under --system, everyday (non-root) accounts can't
    # write to the shared shims dir by design (see harden_system_permissions)
    # -- so that auto-rehash would fail on every single shell start for
    # every account but root. --no-rehash disables it; only the account
    # that actually ran `pyenv install`/`pyenv global` (root) needs a
    # rehash, and that already happened during install. Not needed under
    # --user, since the account owns its own root and rehashing is harmless.
    local rehash_flag=''
    [[ "$SCOPE" == "system" ]] && rehash_flag=' --no-rehash'

    local bash_block="export PYENV_ROOT=$root_expr
[[ -d \"\$PYENV_ROOT/bin\" ]] && export PATH=\"\$PYENV_ROOT/bin:\$PATH\"
eval \"\$(pyenv init - bash${rehash_flag})\""

    local zsh_block="export PYENV_ROOT=$root_expr
[[ -d \"\$PYENV_ROOT/bin\" ]] && export PATH=\"\$PYENV_ROOT/bin:\$PATH\"
eval \"\$(pyenv init - zsh${rehash_flag})\""

    write_shell_block 'pyenv (machine-bootstrap)' "$bash_block" "$zsh_block"
}

get_latest_python_version() {
    local pattern='^  3\.[0-9]+\.[0-9]+$'
    if [[ "$INCLUDE_FREE_THREADED" == "1" ]]; then
        pattern='^  3\.[0-9]+\.[0-9]+t?$'
    fi

    pyenv install --list | grep -E "$pattern" | tr -d ' ' | sort -V | tail -n1
}

install_global_python() {
    log_step 'Resolving latest Python release'
    local version="$PYTHON_VERSION"
    if [[ -z "$version" ]]; then
        version=$(get_latest_python_version)
    fi
    if [[ -z "$version" ]]; then
        log_info 'Could not resolve a latest Python version from `pyenv install --list`.'
        exit 1
    fi
    log_info "Target version: $version"

    log_step "Installing Python $version via pyenv"
    pyenv install --skip-existing "$version"
    pyenv global "$version"
    harden_system_permissions

    log_info "pyenv version: $(pyenv version)"
}

ensure_direnv() {
    log_step 'Installing direnv'
    local os
    os=$(detect_os)

    if command -v direnv >/dev/null 2>&1; then
        log_info "direnv already installed: $(direnv --version)"
    elif [[ "$os" == "linux" ]] && command -v apt-get >/dev/null 2>&1; then
        run_privileged apt-get install -y direnv
    elif [[ "$os" == "linux" ]] && command -v pacman >/dev/null 2>&1; then
        # -Syu, not a bare -S: see the comment in install_build_deps_pacman.
        run_privileged pacman -Syu --noconfirm --needed direnv
    elif [[ "$os" == "macos" ]] && command -v brew >/dev/null 2>&1; then
        run_brew install direnv
    else
        log_info 'No supported package manager found; install direnv manually from https://direnv.net'
        return
    fi

    log_step 'Hooking direnv into shell init'
    write_shell_block 'direnv (machine-bootstrap)' \
        'eval "$(direnv hook bash)"' \
        'eval "$(direnv hook zsh)"'
}

main() {
    local os
    os=$(detect_os)

    log_step "Scope: $SCOPE"
    if [[ "$SCOPE" == "system" ]]; then
        log_info "Shared under $PYENV_ROOT_DEFAULT; other user accounts pick this up on next login."
    fi

    case "$os" in
        linux) install_build_deps_linux ;;
        macos) install_build_deps_macos ;;
        *)
            log_info "Unsupported OS: $(uname -s). This script targets Linux and macOS."
            exit 1
            ;;
    esac

    ensure_pyenv
    install_global_python
    ensure_direnv

    log_step 'Done'
    log_info 'Open a new shell (or source your rc file) to pick up pyenv and the direnv hook.'
}

main "$@"
