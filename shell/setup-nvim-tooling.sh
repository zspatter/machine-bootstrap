#!/usr/bin/env bash
#
# Fresh-machine bootstrap: installs the LSP servers, linters, and formatters
# the Neovim config (sym-lattice dotfiles/vim/nvim) expects. Companion to
# setup-nvim.sh, which installs the editor itself.
#
# The config deliberately uses no mason.nvim -- servers are ordinary CLI
# tools, so this script is where their maintenance lives. Tool inventory
# (driven by that config's lsp.lua / linting.lua / formatting.lua):
#
#   shfmt, shellcheck, node/npm  : apt (all packaged) / pacman / brew
#     (shfmt listed first: a comment starting '# shellcheck' parses as a
#     malformed shellcheck *directive* and errors the whole file)
#   lua-language-server, stylua  : pacman/brew have them; apt does NOT ->
#                                  GitHub release binaries into ~/.local
#   pyright, bash-language-server,
#     vscode-langservers-extracted (json),
#     yaml-language-server, @taplo/cli (toml): npm -g
#   roslyn-language-server (C#)  : dotnet tool from the Azure DevOps feed
#                                  (VS Code's source; nuget.org lags).
#                                  Skipped when no .NET SDK is present.
#   ruff                         : uv tool
#   tree-sitter CLI (>=0.26.1)   : GitHub release binary -> ~/.local/bin
#                                  (apt's tree-sitter-cli is too old)
#   C compiler (gcc)             : apt/pacman -- nvim-treesitter compiles
#                                  parsers locally
#   PSScriptAnalyzer + PowerShell Editor Services: only when pwsh exists
#     (PES lands at ~/.local/share/powershell-editor-services, the fixed
#     path the config's powershell_es setup relies on -- change one,
#     change both). Without pwsh these are skipped: no PowerShell editing
#     on this machine anyway.
#
# Safe to re-run; the privileged phase self-skips when its tools are
# already present (same pattern as setup-cli-tools.sh), so re-runs on a
# provisioned machine need no sudo. Note the ~/.local installs are
# per-user: run the script as the user who'll run nvim, not root -- when
# root is only needed for apt/npm, run it once as root (installs the
# system pieces, user pieces land in /root and are re-done on the user
# pass), then again as the user.

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

install_packaged_tools() {
    log_step 'Installing package-manager tools'
    case "$(uname -s)" in
        Linux)
            if command -v apt-get >/dev/null 2>&1; then
                if command -v shellcheck >/dev/null 2>&1 && command -v shfmt >/dev/null 2>&1 \
                        && command -v npm >/dev/null 2>&1; then
                    log_info 'shellcheck/shfmt/npm already installed -- skipping apt (no sudo needed)'
                else
                    run_privileged apt-get update
                    run_privileged apt-get install -y shellcheck shfmt nodejs npm
                fi
            elif command -v pacman >/dev/null 2>&1; then
                # Arch packages the whole set -- no GitHub-binary phase needed.
                run_privileged pacman -Syu --noconfirm --needed \
                    shellcheck shfmt nodejs npm lua-language-server stylua
            else
                log_info 'No supported package manager (apt/pacman); install manually, then re-run.'
                exit 1
            fi
            ;;
        Darwin)
            if ! command -v brew >/dev/null 2>&1; then
                log_info 'Homebrew not found. Install it from https://brew.sh, then re-run.'
                exit 1
            fi
            run_brew install shellcheck shfmt node lua-language-server stylua
            ;;
        *)
            log_info "Unsupported OS: $(uname -s). See setup-nvim-tooling.ps1 for Windows."
            exit 1
            ;;
    esac
}

install_github_binaries() {
    # apt has no lua-language-server or stylua packages; official release
    # binaries into ~/.local instead (same pattern as setup-nvim.sh). pacman
    # and brew installed these already, so both no-op via the presence checks.
    if ! command -v lua-language-server >/dev/null 2>&1; then
        log_step 'Installing lua-language-server (GitHub release binary)'
        local arch tag tmpdir
        case "$(uname -m)" in
            x86_64) arch='linux-x64' ;;
            aarch64) arch='linux-arm64' ;;
            *) log_info "Unsupported architecture: $(uname -m)"; exit 1 ;;
        esac
        tag=$(fetch_latest_tag 'LuaLS/lua-language-server')
        tmpdir=$(mktemp -d)
        fetch "https://github.com/LuaLS/lua-language-server/releases/download/$tag/lua-language-server-$tag-$arch.tar.gz" \
             "$tmpdir/luals.tar.gz"
        rm -rf "$HOME/.local/opt/lua-language-server"
        mkdir -p "$HOME/.local/opt/lua-language-server"
        tar -xzf "$tmpdir/luals.tar.gz" -C "$HOME/.local/opt/lua-language-server"
        rm -rf "$tmpdir"
        mkdir -p "$HOME/.local/bin"
        ln -sf "$HOME/.local/opt/lua-language-server/bin/lua-language-server" \
              "$HOME/.local/bin/lua-language-server"
    fi

    if ! command -v stylua >/dev/null 2>&1; then
        log_step 'Installing stylua (GitHub release binary)'
        local arch tmpdir
        case "$(uname -m)" in
            x86_64) arch='linux-x86_64' ;;
            aarch64) arch='linux-aarch64' ;;
            *) log_info "Unsupported architecture: $(uname -m)"; exit 1 ;;
        esac
        ensure_unzip
        tmpdir=$(mktemp -d)
        fetch "https://github.com/JohnnyMorganz/StyLua/releases/latest/download/stylua-$arch.zip" \
             "$tmpdir/stylua.zip"
        mkdir -p "$HOME/.local/bin"
        unzip -oq "$tmpdir/stylua.zip" -d "$HOME/.local/bin"
        chmod +x "$HOME/.local/bin/stylua"
        rm -rf "$tmpdir"
    fi
}

fetch_latest_tag() {
    # GitHub's /releases/latest redirect carries the tag; parse it from the
    # effective URL rather than requiring jq. lua-language-server needs the
    # literal tag in its asset filenames (no latest/download shortcut works).
    curl -fsSLI -o /dev/null -w '%{url_effective}' \
        "https://github.com/$1/releases/latest" | sed 's|.*/||'
}

install_treesitter_toolchain() {
    # nvim 0.12 ships treesitter highlighting in core but bundles only seven
    # parsers; the rest (python, bash, ...) are compiled locally by the
    # nvim-treesitter fork, which needs a C compiler and the tree-sitter CLI
    # >= 0.26.1. Distro CLI packages lag (Ubuntu 26.04 apt: 0.25.x), so the
    # CLI comes from GitHub release binaries regardless of distro -- same
    # pattern as lua-language-server above.
    log_step 'Installing treesitter parser toolchain'

    if ! command -v cc >/dev/null 2>&1 && ! command -v gcc >/dev/null 2>&1; then
        if command -v apt-get >/dev/null 2>&1; then
            run_privileged apt-get update
            run_privileged apt-get install -y gcc
        elif command -v pacman >/dev/null 2>&1; then
            run_privileged pacman -Syu --noconfirm --needed gcc
        else
            log_info 'No C compiler found; install one (Darwin: xcode-select --install), then re-run.'
            exit 1
        fi
    fi

    local required='0.26.1' current=''
    if command -v tree-sitter >/dev/null 2>&1; then
        current=$(tree-sitter --version | awk '{print $2}')
    fi
    if [[ -n "$current" && "$(printf '%s\n' "$required" "$current" | sort -V | head -1)" == "$required" ]]; then
        log_info "tree-sitter CLI $current already installed (>= $required)"
        return
    fi

    local arch os tmpdir
    case "$(uname -m)" in
        x86_64) arch='x64' ;;
        aarch64 | arm64) arch='arm64' ;;
        *) log_info "Unsupported architecture: $(uname -m)"; exit 1 ;;
    esac
    os='linux'
    [[ "$(uname -s)" == 'Darwin' ]] && os='macos'
    tmpdir=$(mktemp -d)
    fetch "https://github.com/tree-sitter/tree-sitter/releases/latest/download/tree-sitter-$os-$arch.gz" \
         "$tmpdir/tree-sitter.gz"
    gunzip "$tmpdir/tree-sitter.gz"
    mkdir -p "$HOME/.local/bin"
    install -m 0755 "$tmpdir/tree-sitter" "$HOME/.local/bin/tree-sitter"
    rm -rf "$tmpdir"
    log_info "Installed tree-sitter CLI $("$HOME/.local/bin/tree-sitter" --version | awk '{print $2}')"
}

install_npm_servers() {
    log_step 'Installing npm-based language servers'
    # npm i -g installs AND updates, so this normally re-runs every time.
    # The exception: when the global prefix is system-owned (apt/pacman
    # node) and both servers already exist, skip rather than demand sudo --
    # a re-run on a provisioned machine shouldn't hit a password wall just
    # to check for updates (same principle as the apt phase above).
    local servers=(pyright bash-language-server vscode-langservers-extracted
                   yaml-language-server '@taplo/cli')
    local prefix
    prefix=$(npm config get prefix)
    if [[ -w "$prefix/lib" || -w "$prefix" || "$(id -u)" -eq 0 ]]; then
        npm install -g "${servers[@]}"
    elif command -v pyright >/dev/null 2>&1 && command -v bash-language-server >/dev/null 2>&1 \
            && command -v vscode-json-language-server >/dev/null 2>&1 \
            && command -v yaml-language-server >/dev/null 2>&1 \
            && command -v taplo >/dev/null 2>&1; then
        log_info 'npm servers already installed; global npm prefix needs privileges -- re-run with sudo (or as root) to update them.'
    else
        run_privileged npm install -g "${servers[@]}"
    fi
}

install_roslyn() {
    # dotnet tool update installs when absent and updates when present. The
    # Azure DevOps feed is what VS Code itself pulls from; nuget.org lags.
    # plugins/roslyn.lua gates on the resulting exe, so skipping here just
    # means no C# LSP on this machine -- no errors.
    log_step 'Installing Roslyn language server (C#)'
    if ! command -v dotnet >/dev/null 2>&1; then
        log_info 'No dotnet SDK; skipping (install the .NET SDK and re-run for C# LSP).'
        return
    fi
    # The tool package carries its DotnetToolSettings.xml under
    # tools/net10.0/ -- older SDKs can't see it and fail with "settings file
    # not found". SDK 10 installs side-by-side; existing projects keep
    # building with whatever SDK their global.json picks.
    if ! dotnet --list-sdks | awk -F. '{print $1}' | grep -qE '^(1[0-9]|[2-9][0-9])$'; then
        log_info 'No .NET SDK >= 10 (required by the tool package format).'
        if command -v apt-get >/dev/null 2>&1; then
            run_privileged apt-get update
            run_privileged apt-get install -y dotnet-sdk-10.0
        else
            log_info 'Install a .NET SDK >= 10, then re-run for C# LSP.'
            return
        fi
    fi
    # --add-source, not --source: SDK 8's tool commands only know the former;
    # newer SDKs accept both, so this is the portable spelling.
    dotnet tool update -g roslyn-language-server --prerelease \
        --add-source https://pkgs.dev.azure.com/azure-public/vside/_packaging/vs-impl/nuget/v3/index.json
}

install_ruff() {
    log_step 'Installing ruff'
    if command -v ruff >/dev/null 2>&1; then
        log_info 'ruff already installed'
    elif command -v uv >/dev/null 2>&1; then
        uv tool install ruff
    else
        log_info 'Neither ruff nor uv found -- run setup-uv.sh first, then re-run.'
        exit 1
    fi
}

install_powershell_tooling() {
    if ! command -v pwsh >/dev/null 2>&1; then
        log_step 'PowerShell tooling: skipped'
        log_info 'No pwsh on this machine -- PSScriptAnalyzer and PowerShell Editor Services only matter where PowerShell is edited.'
        return
    fi

    log_step 'Installing PSScriptAnalyzer'
    pwsh -NoLogo -NoProfile -Command \
        'if (-not (Get-Module -ListAvailable PSScriptAnalyzer)) { Install-Module PSScriptAnalyzer -Scope CurrentUser -Force }'

    log_step 'Installing PowerShell Editor Services'
    local bundle="$HOME/.local/share/powershell-editor-services"
    if [[ -f "$bundle/PowerShellEditorServices/Start-EditorServices.ps1" ]]; then
        log_info "Bundle already present at $bundle (delete the dir and re-run to update)."
        return
    fi
    ensure_unzip
    local tmpdir
    tmpdir=$(mktemp -d)
    fetch 'https://github.com/PowerShell/PowerShellEditorServices/releases/latest/download/PowerShellEditorServices.zip' \
         "$tmpdir/pses.zip"
    mkdir -p "$bundle"
    unzip -oq "$tmpdir/pses.zip" -d "$bundle"
    rm -rf "$tmpdir"
    if [[ ! -f "$bundle/PowerShellEditorServices/Start-EditorServices.ps1" ]]; then
        log_info 'PES bundle extracted but launcher not found -- release layout may have changed.'
        exit 1
    fi
}

verify() {
    log_step 'Verifying'
    export PATH="$HOME/.local/bin:$PATH"
    local missing=0
    local expected=(lua-language-server shellcheck shfmt stylua ruff pyright-langserver
                    bash-language-server tree-sitter vscode-json-language-server
                    yaml-language-server taplo)
    # roslyn only expected where dotnet exists (see install_roslyn)
    command -v dotnet >/dev/null 2>&1 && expected+=(roslyn-language-server)
    for cmd in "${expected[@]}"; do
        if command -v "$cmd" >/dev/null 2>&1; then
            log_info "$cmd: ok"
        else
            log_info "$cmd: MISSING"
            missing=1
        fi
    done
    return "$missing"
}

export PATH="$HOME/.local/bin:$PATH"
install_packaged_tools
install_github_binaries
install_treesitter_toolchain
install_npm_servers
install_roslyn
install_ruff
install_powershell_tooling
verify
log_step 'Done'
log_info 'Launch nvim and run :checkhealth vim.lsp to confirm servers attach.'
