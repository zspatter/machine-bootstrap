#!/usr/bin/env bash
#
# Fresh-machine bootstrap: installs the preferred Nerd Font families,
# per-user -- JetBrains Mono NF and Fira Code NF for editors (ligatures
# intact: NF patching only adds glyphs on top of the base font), Meslo LGM
# NF for terminal prompts (the oh-my-posh recommendation).
#
# Skips WSL: fonts render on the Windows host there -- run setup-fonts.ps1
# on the host instead (same reasoning as the GUI-app scripts).
#
# The nerd-fonts release zips ship every size/spacing variant (Meslo alone:
# 72 ttfs; JetBrainsMono: 96) -- installing them all is exactly the
# font-picker clutter this script exists to avoid. Only the curated
# patterns below land (11 files total). brew's font casks were rejected
# for macOS for the same reason: they install the whole zip. Extend a
# pattern if you ever want another weight; delete the family's probe file
# and re-run to update.
#
# Linux: ~/.local/share/fonts + fc-cache. macOS: ~/Library/Fonts.

set -euo pipefail

log_step() { printf '\n==> %s\n' "$1"; }
log_info() { printf '    %s\n' "$1"; }

run_privileged() {
    if [[ "$(id -u)" -eq 0 ]]; then "$@"; else sudo "$@"; fi
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

ensure_unzip() {
    command -v unzip >/dev/null 2>&1 && return
    if command -v apt-get >/dev/null 2>&1; then
        run_privileged apt-get update
        run_privileged apt-get install -y unzip
    elif command -v pacman >/dev/null 2>&1; then
        run_privileged pacman -Syu --noconfirm --needed unzip
    fi
}

if grep -qi microsoft /proc/version 2>/dev/null; then
    log_step 'WSL detected -- skipping'
    log_info 'Fonts render on the Windows host; run setup-fonts.ps1 there instead.'
    exit 0
fi

case "$(uname -s)" in
    Linux) font_dir="$HOME/.local/share/fonts" ;;
    Darwin) font_dir="$HOME/Library/Fonts" ;;
    *)
        log_info "Unsupported OS: $(uname -s). See setup-fonts.ps1 for Windows."
        exit 1
        ;;
esac
mkdir -p "$font_dir"

install_family() {
    local asset="$1" match="$2" probe="$3"
    log_step "Installing $asset Nerd Font (curated subset)"
    if [[ -f "$font_dir/$probe" ]]; then
        log_info "$probe already present -- skipping"
        return
    fi

    ensure_unzip
    local tmpdir count=0 f
    tmpdir=$(mktemp -d)
    fetch "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/$asset.zip" \
         "$tmpdir/$asset.zip"
    unzip -oq "$tmpdir/$asset.zip" -d "$tmpdir/extract"
    while IFS= read -r f; do
        cp "$f" "$font_dir/"
        count=$((count + 1))
    done < <(find "$tmpdir/extract" -maxdepth 1 -name '*.ttf' | grep -E "$match" || true)
    rm -rf "$tmpdir"

    if [[ "$count" -eq 0 ]]; then
        log_info "No files in $asset.zip matched '$match' -- release layout may have changed."
        exit 1
    fi
    log_info "Installed $count faces"
}

# NL = no-ligatures, Mono/Propo = alternate glyph spacing, LGS/LGL/DZ =
# other Meslo line gaps -- all deliberately excluded. FiraCode has no
# italics; Retina is its signature between-weight.
install_family 'JetBrainsMono' '/JetBrainsMonoNerdFont-(Regular|Bold|Italic|BoldItalic)\.ttf$' 'JetBrainsMonoNerdFont-Regular.ttf'
install_family 'FiraCode' '/FiraCodeNerdFont-(Regular|Retina|Bold)\.ttf$' 'FiraCodeNerdFont-Regular.ttf'
install_family 'Meslo' '/MesloLGMNerdFont-(Regular|Bold|Italic|BoldItalic)\.ttf$' 'MesloLGMNerdFont-Regular.ttf'

if command -v fc-cache >/dev/null 2>&1; then
    log_step 'Refreshing font cache'
    fc-cache -f "$font_dir" >/dev/null
fi

log_step 'Done'
log_info 'Restart terminals/editors to pick up the new fonts.'
