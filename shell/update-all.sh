#!/usr/bin/env bash
#
# One-command update sweep across every package domain the bootstrap
# scripts installed -- `apt upgrade` and friends plus the language-tool
# domains, in one place. NOT part of the install-all chain; run it when
# you want updates.
#
# Continue-on-error like install-all: a failing domain reports and the
# sweep moves on.
#
# Deliberately NOT covered (each has its own owner):
#   - nvim plugins      : vim.pack.update() inside nvim (review buffer)
#   - treesitter parsers: :TSUpdate inside nvim
#   - GitHub-binary installs (lua-language-server, stylua, tree-sitter,
#     nvim tarball): delete from ~/.local and re-run the setup script
#   - PowerShell Editor Services: delete the bundle dir + re-run
#     setup-nvim-tooling.sh

set -uo pipefail

log_step() { printf '\n==> %s\n' "$1"; }
log_info() { printf '    %s\n' "$1"; }

run_privileged() {
    if [[ "$(id -u)" -eq 0 ]]; then "$@"; else sudo "$@"; fi
}

failed=()

log_step 'System packages'
if command -v apt-get >/dev/null 2>&1; then
    run_privileged apt-get update && run_privileged apt-get upgrade -y || failed+=(apt)
elif command -v pacman >/dev/null 2>&1; then
    run_privileged pacman -Syu --noconfirm || failed+=(pacman)
elif command -v brew >/dev/null 2>&1; then
    brew update && brew upgrade || failed+=(brew)
else
    log_info 'No supported system package manager found.'
fi

log_step 'uv tools'
if command -v uv >/dev/null 2>&1; then
    uv tool upgrade --all || failed+=(uv-tools)
else
    log_info 'uv not installed; skipping.'
fi

log_step 'npm globals'
if command -v npm >/dev/null 2>&1; then
    # NOT `npm update -g`: that respects semver ranges and never crosses a
    # major version, so globals silently pinned to an old major. Ask npm
    # what's outdated (parseable field 4 = name@latest; exits 1 when
    # anything is -- not an error here) and install those explicitly.
    outdated=$(npm outdated -g --parseable 2>/dev/null | cut -d: -f4 || true)
    if [[ -n "$outdated" ]]; then
        # shellcheck disable=SC2086  # word-splitting the name@latest list is the point
        npm install -g $outdated || failed+=(npm)
    else
        log_info 'All npm globals already at latest.'
    fi
else
    log_info 'npm not installed; skipping.'
fi

log_step 'dotnet tools (roslyn)'
if command -v dotnet >/dev/null 2>&1 && command -v roslyn-language-server >/dev/null 2>&1; then
    dotnet tool update -g roslyn-language-server --prerelease \
        --add-source https://pkgs.dev.azure.com/azure-public/vside/_packaging/vs-impl/nuget/v3/index.json \
        || failed+=(roslyn)
else
    log_info 'roslyn-language-server not installed; skipping.'
fi

log_step 'Summary'
if [[ ${#failed[@]} -eq 0 ]]; then
    log_info 'All domains updated.'
else
    log_info "Failed domains: ${failed[*]}"
fi
log_info 'Editor-owned updates: vim.pack.update() and :TSUpdate inside nvim.'
[[ ${#failed[@]} -eq 0 ]]
