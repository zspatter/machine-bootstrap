#!/usr/bin/env bash
#
# One-command chain over the atomic setup scripts. Deliberately NOT
# fail-fast: each script runs independently, failures are recorded and
# the chain continues -- a broken browser install shouldn't block the
# Python toolchain. Exits non-zero if anything failed, with a summary
# table either way. Every underlying script is idempotent, so re-running
# this after fixing a failure only redoes the broken pieces.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Chain order: foundations first (git, uv), then everything else.
SCRIPTS=(
    setup-git.sh
    setup-uv.sh
    setup-cli-tools.sh
    setup-nvim.sh
    setup-oh-my-posh.sh
    setup-gh-cli.sh
    setup-obsidian.sh
    setup-vscode.sh
    setup-zen-browser.sh
    setup-librewolf.sh
    setup-claude-desktop.sh
    setup-claude-code.sh
)

declare -a passed=()
declare -a failed=()

for script in "${SCRIPTS[@]}"; do
    printf '\n########## %s ##########\n' "$script"
    if bash "$SCRIPT_DIR/$script"; then
        passed+=("$script")
    else
        failed+=("$script (exit $?)")
    fi
done

printf '\n########## Summary ##########\n'
# ${arr[@]+...} guards: macOS ships bash 3.2, where expanding an *empty*
# array under `set -u` is an "unbound variable" error (fixed in bash 4.4).
# Caught in CI -- all 12 scripts passed, then the summary died printing
# the empty failure list.
for s in ${passed[@]+"${passed[@]}"}; do printf '  PASS  %s\n' "$s"; done
for s in ${failed[@]+"${failed[@]}"}; do printf '  FAIL  %s\n' "$s"; done

if [[ ${#failed[@]} -gt 0 ]]; then
    printf '\n%d of %d scripts failed. Fix and re-run -- everything is idempotent, only the broken pieces redo work.\n' "${#failed[@]}" "${#SCRIPTS[@]}"
    exit 1
fi
printf '\nAll %d scripts succeeded.\n' "${#SCRIPTS[@]}"
