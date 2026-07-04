#!/usr/bin/env bash
#
# Fresh-machine bootstrap: generates an ed25519 SSH key (if absent) and
# registers the public key with GitHub via the gh CLI when authenticated.
#
# Runs everywhere INCLUDING WSL -- unlike the GUI apps, a WSL environment
# wants its own key (a long-standing gap: WSL git pushes had to detour
# through the Windows host).
#
# Safe to re-run: existing keys are never touched, the GitHub upload is
# skipped when the key is already registered. The key is generated
# WITHOUT a passphrase -- the deliberate trade for unattended bootstrap;
# regenerate with one (ssh-keygen -p) if the machine's threat model
# wants it.

set -euo pipefail

log_step() { printf '\n==> %s\n' "$1"; }
log_info() { printf '    %s\n' "$1"; }

key_path="$HOME/.ssh/id_ed25519"
pub_path="$key_path.pub"

log_step 'SSH key'
if [[ -f "$key_path" ]]; then
    log_info "Key already exists at $key_path -- leaving it alone."
else
    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"
    ssh-keygen -t ed25519 -f "$key_path" -N '' -C "$(whoami)@$(hostname)" >/dev/null
    log_info "Generated $key_path (no passphrase -- see header)."
fi

log_step 'GitHub registration'
pub_key=$(cat "$pub_path")
key_body=$(awk '{print $2}' "$pub_path")
if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
    if gh ssh-key list 2>/dev/null | grep -qF "$key_body"; then
        log_info 'Key already registered with GitHub.'
    else
        gh ssh-key add "$pub_path" --title "$(hostname)"
        log_info "Registered with GitHub as '$(hostname)'."
    fi
else
    log_info 'gh CLI missing or unauthenticated; add the key manually:'
    log_info "  $pub_key"
    log_info 'https://github.com/settings/ssh/new (or run setup-gh-cli.sh + gh auth login, then re-run).'
fi

log_step 'Done'
log_info 'Test with: ssh -T git@github.com'
