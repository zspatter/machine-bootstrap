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

run_privileged() {
    if [[ "$(id -u)" -eq 0 ]]; then "$@"; else sudo "$@"; fi
}

# Minimal containers (arch, debian slim) ship neither ssh-keygen nor even
# hostname -- caught by CI. uname -n replaces hostname everywhere below.
if ! command -v ssh-keygen >/dev/null 2>&1; then
    log_step 'Installing OpenSSH client'
    if command -v apt-get >/dev/null 2>&1; then
        run_privileged apt-get update
        run_privileged apt-get install -y openssh-client
    elif command -v pacman >/dev/null 2>&1; then
        run_privileged pacman -Syu --noconfirm --needed openssh
    else
        log_info 'No ssh-keygen and no supported package manager; install OpenSSH, then re-run.'
        exit 1
    fi
fi

key_path="$HOME/.ssh/id_ed25519"
pub_path="$key_path.pub"

log_step 'SSH key'
if [[ -f "$key_path" ]]; then
    log_info "Key already exists at $key_path -- leaving it alone."
else
    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"
    ssh-keygen -t ed25519 -f "$key_path" -N '' -C "$(whoami)@$(uname -n)" >/dev/null
    log_info "Generated $key_path (no passphrase -- see header)."
fi

log_step 'GitHub registration'
pub_key=$(cat "$pub_path")
key_body=$(awk '{print $2}' "$pub_path")
if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
    if gh ssh-key list 2>/dev/null | grep -qF "$key_body"; then
        log_info 'Key already registered with GitHub.'
    else
        gh ssh-key add "$pub_path" --title "$(uname -n)"
        log_info "Registered with GitHub as '$(uname -n)'."
    fi
else
    log_info 'gh CLI missing or unauthenticated; add the key manually:'
    log_info "  $pub_key"
    log_info 'https://github.com/settings/ssh/new (or run setup-gh-cli.sh + gh auth login, then re-run).'
fi

# Seed github.com into known_hosts, or the FIRST ssh operation (vault
# clones, plugin installs riding an insteadOf rewrite) stops on the
# interactive host-key prompt -- a third interactive moment the
# onboarding flow promises not to have. Preferred source is the GitHub
# API over TLS (`gh api meta`, authenticated above); ssh-keyscan is the
# fallback when gh isn't ready -- trust-on-first-scan, same trust the
# interactive prompt would have asked for.
log_step 'known_hosts (github.com)'
known_hosts="$HOME/.ssh/known_hosts"
if [[ -f "$known_hosts" ]] && grep -q '^github\.com ' "$known_hosts"; then
    log_info 'github.com already present in known_hosts.'
else
    host_lines=''
    if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
        host_lines=$(gh api meta --jq '.ssh_keys[]' 2>/dev/null | sed 's/^/github.com /' || true)
    fi
    if [[ -z "$host_lines" ]]; then
        host_lines=$(ssh-keyscan -t ed25519,ecdsa,rsa github.com 2>/dev/null || true)
    fi
    if [[ -n "$host_lines" ]]; then
        printf '%s\n' "$host_lines" >> "$known_hosts"
        chmod 644 "$known_hosts"
        log_info "Seeded github.com host key(s) into known_hosts."
    else
        log_info 'Could not fetch host keys (offline?); the first ssh connection will prompt.'
    fi
fi

log_step 'Done'
log_info 'Test with: ssh -T git@github.com'
