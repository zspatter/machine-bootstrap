#!/usr/bin/env bash
#
# Fresh-machine bootstrap: the markdown desktop editor, per platform.
#
#   Debian/Ubuntu : Typora from its official apt repo, plus the house
#                   theme set (Blackout Gamer, Chernobyl, Drake -- the
#                   same set setup-typora.ps1 installs on Windows).
#   macOS         : Typora via brew cask, same themes.
#   other Linux   : Typora only ships a managed repo for deb (the
#                   tarball gets no updates), so MarkText stands in --
#                   actively maintained again (v0.19.x, 2026) and ships
#                   the ayu-dark theme that
#                   dotfiles/marktext/preferences.json selects via
#                   symlink-manager. AppImage into ~/.local/bin.
#   WSL           : skipped -- use Windows Typora (setup-typora.ps1),
#                   same reasoning as setup-vscode.sh.
#
# LICENSE IS MANUAL either way: Typora is a paid one-time purchase;
# enter the key in Typora > Preferences after first launch. Theme
# selection is manual too (Themes menu > Drake Vue3 as the house
# default) -- Typora persists it in profile.data alongside window
# state, which isn't safely pre-seedable.
#
# Safe to re-run; every piece is install-if-missing.

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
        curl -fsSL --retry 3 "$1" -o "$2"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$2" --tries=3 "$1"
    else
        log_info 'Neither curl nor wget found; install one, then re-run.'
        exit 1
    fi
}

ensure_unzip() {
    command -v unzip >/dev/null 2>&1 && return
    if command -v apt-get >/dev/null 2>&1; then
        run_privileged apt-get update
        run_privileged apt-get install -y unzip
    elif command -v pacman >/dev/null 2>&1; then
        run_privileged pacman -Syu --noconfirm --needed unzip
    fi
}

fetch_latest_tag() {
    curl -fsSLI --retry 3 -o /dev/null -w '%{url_effective}' \
        "https://github.com/$1/releases/latest" | sed 's|.*/||'
}

# --- themes (shared by the apt and brew paths) -------------------------
THEME_RELEASE='https://github.com/obscurefreeman/typora_theme_blackout/releases/latest/download'

typora_theme_dir() {
    if [[ "$(uname -s)" == 'Darwin' ]]; then
        echo "$HOME/Library/Application Support/abnerworks.Typora/themes"
    else
        echo "$HOME/.config/Typora/themes"
    fi
}

# install_theme_zip NAME URL MARKER_GLOB [ITEM...]
# Skips when MARKER_GLOB already matches in the theme dir; otherwise
# extracts the zip (unwrapping a single top-level folder, as GitHub
# zipballs have) and copies ITEMs (default: everything) in.
install_theme_zip() {
    local name="$1" url="$2" marker="$3"
    shift 3
    local items=("${@:-*}")
    local dir
    dir=$(typora_theme_dir)
    mkdir -p "$dir"
    if compgen -G "$dir/$marker" >/dev/null; then
        log_info "$name already present"
        return
    fi
    log_info "Fetching $name"
    ensure_unzip
    local tmpdir root
    tmpdir=$(mktemp -d)
    fetch "$url" "$tmpdir/theme.zip"
    unzip -oq "$tmpdir/theme.zip" -d "$tmpdir/x"
    root="$tmpdir/x"
    # unwrap a lone wrapping folder
    local entries=("$root"/*)
    if [[ ${#entries[@]} -eq 1 && -d "${entries[0]}" ]]; then
        root="${entries[0]}"
    fi
    local item
    for item in "${items[@]}"; do
        # unquoted on purpose: the item IS a glob (e.g. '*.css')
        # shellcheck disable=SC2086
        cp -r $root/$item "$dir/"
    done
    rm -rf "$tmpdir"
    log_info "$name installed"
}

install_themes() {
    log_step 'Installing Typora themes'
    install_theme_zip 'Blackout Gamer' "$THEME_RELEASE/blackout_theme_gamer.zip" '*gamer*.css'
    install_theme_zip 'Chernobyl' "$THEME_RELEASE/blackout_theme_chernobyl.zip" '*chernobyl*.css'
    install_theme_zip 'Drake' 'https://github.com/liangjingkanji/DrakeTyporaTheme/archive/refs/heads/master.zip' \
        'drake-vue3.css' '*.css' 'drake'
}

# --- editors ------------------------------------------------------------
install_typora_apt() {
    if command -v typora >/dev/null 2>&1; then
        log_step 'Typora already installed'
    else
        log_step "Installing Typora (official apt repo)"
        run_privileged apt-get update
        run_privileged apt-get install -y curl ca-certificates
        run_privileged mkdir -p -m 755 /etc/apt/keyrings
        curl -fsSL --retry 3 https://downloads.typora.io/typora.gpg \
            | run_privileged tee /etc/apt/keyrings/typora.gpg >/dev/null
        echo "deb [signed-by=/etc/apt/keyrings/typora.gpg] https://downloads.typora.io/linux ./" \
            | run_privileged tee /etc/apt/sources.list.d/typora.list >/dev/null
        run_privileged apt-get update
        run_privileged apt-get install -y typora
        log_info 'Installed. Reminder: enter the license in Typora > Preferences.'
    fi
    install_themes
}

install_typora_brew() {
    if [[ -d '/Applications/Typora.app' ]]; then
        log_step 'Typora already installed'
    else
        log_step 'Installing Typora (brew cask)'
        run_brew install --cask typora
        log_info 'Installed. Reminder: enter the license in Typora > Preferences.'
    fi
    install_themes
}

install_marktext() {
    if command -v marktext >/dev/null 2>&1; then
        log_step 'MarkText already installed'
        return
    fi
    log_step 'Installing MarkText (AppImage; Typora has no managed repo for this distro)'
    if [[ "$(uname -m)" != 'x86_64' ]]; then
        log_info "MarkText publishes x86_64 AppImages only; $(uname -m) needs a manual build."
        exit 1
    fi
    local tag ver tmpdir
    tag=$(fetch_latest_tag 'marktext/marktext')
    ver=${tag#v}
    tmpdir=$(mktemp -d)
    fetch "https://github.com/marktext/marktext/releases/download/$tag/marktext-linux-$ver.AppImage" \
         "$tmpdir/marktext"
    mkdir -p "$HOME/.local/bin"
    install -m 0755 "$tmpdir/marktext" "$HOME/.local/bin/marktext"
    rm -rf "$tmpdir"
    log_info "Installed MarkText $ver to ~/.local/bin/marktext"
    log_info 'Theme (ayu-dark) comes from dotfiles/marktext/preferences.json via symlink-manager.'
}

main() {
    case "$(uname -s)" in
        Linux)
            if grep -qi microsoft /proc/version 2>/dev/null; then
                log_step 'WSL detected -- skipping'
                log_info 'Use Windows Typora (setup-typora.ps1) instead of a GUI app inside WSL.'
                exit 0
            fi
            if command -v apt-get >/dev/null 2>&1; then
                install_typora_apt
            else
                install_marktext
            fi
            ;;
        Darwin)
            if ! command -v brew >/dev/null 2>&1; then
                log_info 'Homebrew not found. Install it from https://brew.sh, then re-run.'
                exit 1
            fi
            install_typora_brew
            ;;
        *)
            log_info "Unsupported OS: $(uname -s). See setup-typora.ps1 for Windows."
            exit 1
            ;;
    esac
    log_step 'Done'
}

main "$@"
