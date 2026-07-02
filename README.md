# machine-bootstrap

Fresh-machine setup scripts. Not project-specific, and not dotfiles — see
[sym-lattice](../sym-lattice) for that. Each script bootstraps one tool
(or tightly related set of tools) onto a machine that doesn't have it yet.

Kept as separate per-tool, per-platform scripts rather than one unified
script — the shells, package managers, and tool-specific quirks differ
enough between platforms that a single script would mostly be branching
logic anyway, and it keeps each concern independently useful (you don't
need the Python tooling to just want `gh`).

## Scripts

- **`setup-python-env.ps1`** (Windows, PowerShell) — installs `pyenv-win`
  and sets a global latest-release Python via `pyenv global`. Supports
  `-Scope System` and `-Scope User` — see below. No `direnv` here — see
  further below.
- **`setup-python-env.sh`** (Linux/macOS, bash) — installs build deps
  (apt, pacman, or Homebrew — see below), clones real `pyenv`, sets a
  global latest-release Python, installs `direnv` and hooks it into shell
  init files. Supports `--system` (shared) and `--user` (per-account)
  scope — see below.
- **`setup-gh-cli.ps1`** / **`setup-gh-cli.sh`** — installs the GitHub CLI
  (`gh`). Install-only, deliberately: `gh auth login` is an interactive
  OAuth/browser flow (or needs a pre-existing `$GH_TOKEN`) that a bootstrap
  script has no business trying to automate. No scope concept here (unlike
  the Python scripts) — `gh` is just a single shared binary, no per-user
  version proliferation to manage.

All scripts are safe to re-run.

## `--system` vs `--user` scope (Linux/macOS only)

`setup-python-env.sh` auto-detects scope: run as root (`sudo`) it installs
**system-wide**; run as a normal user it installs **per-user**. Override
explicitly with `--system` or `--user`.

- **`--user`** (default when not root): everything lives under
  `$HOME/.pyenv`, wired into that account's own `.bashrc`/`.zshrc`. Matches
  the original behavior — only the invoking account gets it.
- **`--system`** (default when root): `pyenv` lives under a shared root
  (`/opt/pyenv` by default, override via `$SYSTEM_PYENV_ROOT`), wired into
  system-wide shell init — `/etc/profile.d/*.sh` + `/etc/zsh/zshenv` on
  Linux, `/etc/zshenv` + `/etc/bashrc` on macOS. Any account created
  *after* this runs picks up `pyenv`, the global Python, and the `direnv`
  hook automatically on next login — no per-user setup needed. This is the
  mode for the "one admin account, one everyday account" pattern: run it
  once as the admin account and the everyday account inherits it for free.

  The shared root stays root-owned; the script `chmod -R a+rX,go-w`s it, so
  everyday (non-root) accounts can read and execute anything already
  installed — run any installed Python, create venvs, `pyenv local` between
  installed versions — but can't `pyenv install` a new version or
  `pyenv global` a different default. Only root can do that. This falls out
  of the permission model for free; there's no separate group or ACL setup.
  (The `go-w` isn't decorative — `a+rX` alone is purely additive and won't
  strip a stray group/other write bit left over from the umask that created
  the files; CI caught a real case of this on one runner image before
  `go-w` was added. See Notes below.)

  On macOS, Homebrew refuses to run as root, so under `--system` the script
  delegates `brew` calls to `$SUDO_USER` rather than running them as root.

## Linux package manager support

`install_build_deps_linux` detects `apt-get` or `pacman` and dispatches
accordingly; anything else prints a message and continues (pyenv install
will then fail without build tools, same as before this existed). `ensure_direnv`
follows the same detection. Covers Debian/Ubuntu/Kali (apt) and
Arch/CachyOS (pacman). pacman installs always use `-Syu`, never a bare
`-S`/`-Sy` — Arch explicitly treats installing against a freshly-synced
database on top of stale local packages as an unsupported "partial
upgrade" that can break the system.

## git

All three platforms ensure `git` is present:

- **Linux**: `git` is in the apt/pacman package lists in
  `install_build_deps_apt`/`install_build_deps_pacman`. Not optional --
  `ensure_pyenv` needs it for `git clone`/`git pull` on real pyenv, so
  without it the script would fail on a genuinely fresh machine. CI has a
  dedicated `linux-no-git` job proving this: every other Linux CI job
  pre-installs git for `actions/checkout` itself, which incidentally also
  satisfies the script's own need, so none of them actually exercised this
  path until this job existed (it fetches the repo via a plain tarball
  instead, and asserts git is genuinely absent before running the script).
- **macOS**: no separate install needed — Xcode Command Line Tools
  (already installed by `install_build_deps_macos` if missing) provides
  `git` too.
- **Windows**: `Ensure-Git` installs via `winget` if `git` isn't already
  on PATH. Unlike the bootstrap Python, this is best-effort, not a hard
  dependency — nothing later in `setup-python-env.ps1` actually needs
  git (`pyenv-win` installs via `pip`), it's here because cloning
  `sym-lattice` (or anything else) in the first place needs it, and it's
  a near-universal requirement for a dev machine regardless.

## `-Scope System` vs `-Scope User` (Windows)

Same idea as `--system`/`--user` on the Unix side. `setup-python-env.ps1`
auto-detects scope from the current session's elevation: run elevated
("Run as Administrator") it installs **system-wide**; run normally it
installs **per-user**. Override explicitly with `-Scope System` or
`-Scope User`. Requesting `-Scope System` from a non-elevated session
throws immediately rather than silently falling back.

- **`-Scope User`** (default, not elevated): `pyenv-win` lives under
  `$HOME\.pyenv`, with `User`-scope env vars/PATH. Matches the original
  behavior.
- **`-Scope System`** (default, elevated): `pyenv-win` lives under
  `C:\ProgramData\pyenv\pyenv-win`, with `Machine`-scope env vars/PATH.
  Same "one admin account sets it up, everyday account inherits it" idea
  as the Unix side — any account created afterward gets `pyenv` and the
  global Python without rerunning anything. The shared root's ACL is
  reset via .NET `Get-Acl`/`Set-Acl` (not `icacls.exe` — see Notes below
  for why): every existing item gets its ACL explicitly rebuilt from
  scratch (SYSTEM and Administrators get Full Control, `BUILTIN\Users`
  gets Read & Execute only, all by well-known SID so it isn't
  locale-dependent), and directory ACEs are inheritable so files/folders
  `pyenv install` creates *afterward* automatically pick up the same
  grants — everyday accounts can use whatever's installed but can't
  `pyenv install`/`pyenv global` without an elevated session, mirroring
  the `chmod -R a+rX,go-w` behavior on Linux/macOS. The install itself is
  CI-verified end-to-end under `-Scope System`; the specific "an
  everyday account really can't write here" claim isn't — see Notes.

  The bootstrap Python (the throwaway copy used only to get a `pip` for
  installing `pyenv-win` itself) stays per-user regardless of `-Scope` —
  it's discarded after that one `pip install` call, so there's nothing to
  gain from installing it system-wide.

## Why no direnv on Windows

direnv's automatic per-directory Python venv activation (the `layout pyenv`
stdlib function) hardcodes a POSIX `bin/` venv layout and evaluates
`.envrc` via bash internally, regardless of which shell hooks it. Windows
venvs put the interpreter in `Scripts\`, not `bin/`, so `layout pyenv`
silently fails to activate anything there — confirmed by reading direnv's
stdlib source directly. `pyenv-win` already reads `.python-version`
per-directory on its own (no direnv needed for that part), and venv
activation on Windows is manual either way, via
`.venv\Scripts\Activate.ps1` each session. Since direnv can't close that
gap on native Windows, it isn't installed there. It's still installed and
hooked on the Linux/macOS side, where `layout pyenv` works correctly.

## Scope boundary

This is not about per-project `.python-version` / `.envrc` — that's handled
per-repo elsewhere. This is only about getting the tooling itself onto a
fresh machine.

## Notes / known issues

- **Windows only:** `pyenv-win`'s version list (`pyenv update`, install
  list) is broken on hardened Windows 11 builds — `pyenv-update.vbs` calls
  `CreateObject("htmlfile")`, which Windows Script Host blocks as an
  anti-malware measure. This is a WSH policy block, not a missing COM
  registration (`regsvr32 mshtml.dll` does not fix it). Upstream fixes
  ([pyenv-win#724](https://github.com/pyenv-win/pyenv-win/pull/724),
  [#729](https://github.com/pyenv-win/pyenv-win/pull/729)) aren't merged.
  `setup-python-env.ps1` works around this by fetching the version list
  directly from python.org and merging it into `.versions_cache.xml`,
  every run.
- **CI** (`.github/workflows/test.yml`) runs both scopes on Windows
  (`-Scope User`/`System`), macOS (`--user`/`--system`), native
  `ubuntu-22.04`/`ubuntu-24.04`, and `debian:11`/`debian:12`/
  `kalilinux/kali-rolling`/`archlinux:latest` containers (the last one
  exercising the pacman branch) — the container jobs also create a fresh
  user account after the `--system` run and confirm it inherits
  `pyenv`/Python/`direnv` with no setup, and every `--system`/`system` job
  (Linux, macOS, *and* Windows, via a real `New-LocalUser` standard
  account — see below) asserts a non-privileged account genuinely can't
  write to the shared root, not just that the happy path works. A
  dedicated `linux-no-git` job proves the script can bootstrap onto a
  machine with no git at all, fetching the repo via a plain tarball
  instead of `actions/checkout` (every other Linux job pre-installs git
  for checkout's own sake, which incidentally masks whether the script
  provides it itself). `gh-cli`/`gh-cli-distros` cover `setup-gh-cli`
  across all three platforms plus the apt-repo-with-GPG-key and pacman
  install paths specifically. Also runs weekly (Monday mornings UTC,
  `schedule:` trigger) with no code change required to catch drift in
  things this repo doesn't control — a new Python release, runner image
  updates, python.org's listing format, winget/brew package changes.
  GitHub emails on failure for scheduled runs by default.
- **`pyenv init -` auto-rehashes on every shell start, which breaks under
  `--system`** — its output always includes an implicit `pyenv rehash`
  unless `--no-rehash` is passed, and once the permission lockdown above
  actually works, that rehash correctly fails for every non-root account
  (it needs to write to the shared shims dir). Caught via CI: fixed by
  passing `--no-rehash` in the shell blocks `ensure_pyenv` writes whenever
  `SCOPE=system` (not needed under `--user`, where the account owns its
  own root and the rehash is harmless). Without this, every non-root user
  would see a `pyenv: cannot rehash: ... isn't writable` message on every
  new shell under `--system` — cosmetic-but-alarming at best in an
  interactive shell, a hard failure in anything running under `set -e`.
- **`chmod -R a+rX` alone was a real bug, not just theoretical** — first
  version of the `--system` permission lockdown used `chmod -R a+rX`
  only. CI caught this for real: on one runner image the ambient umask had
  already left the shared root group/other-writable before the chmod ran,
  and since `a+rX` is purely additive (never strips existing bits), a
  non-root account could still write and `pyenv rehash` there. Fixed with
  `chmod -R a+rX,go-w`, verified in CI with an explicit "non-root write
  must fail" assertion.
- **The Windows ACL code went through several real, CI-caught bugs before
  landing on `Get-Acl`/`Set-Acl`** — worth recording the sequence, since
  each one looked plausible until CI proved otherwise:
  1. A single `icacls /inheritance:r` + multiple `/grant:r` + `/T` call
     (the direct Unix-lockdown analog) produced a file with a *genuinely
     empty DACL* — `/T` didn't reliably propagate the grants to every
     recursed child.
  2. Splitting that into two separate `icacls` calls hit a persistent
     "Access is denied" (exit 5) on a freshly `pip`-extracted file.
     Assumed transient (e.g. AV scanning a just-written file) and wrapped
     in retry-with-backoff — but it failed identically on all 5 retries
     within 4 seconds, ruling that out.
  3. Switched to .NET `Get-Acl`/`Set-Acl`, walking every item explicitly
     instead of trusting `icacls`'s `/T` recursion or its exit codes. This
     got further, but used non-inheritable ACEs on the theory that
     explicitly walking every *existing* item made inheritance
     unnecessary — wrong for items created *afterward*: `pyenv install`
     itself then failed ("core_d component MSI ... Permission denied")
     writing into the now-locked-down tree.
  4. Final fix: directory ACEs need `(OI)(CI)`-equivalent inheritance
     flags so new files/folders created later by `pyenv install`
     automatically inherit the right permissions, while every existing
     item still gets its ACL explicitly reset directly (not relying on
     recursion). This is what's in the script now, and it's what's
     actually CI-verified — `-Scope System` completes a full real
     `pyenv install`/`pyenv global` end-to-end.

  The remaining gap — a second, non-admin account genuinely can't write
  to the shared root — is now also closed: the `windows` CI job creates a
  real `New-LocalUser` standard account (lands in `Users`, not
  `Administrators`, matching the ACE the lockdown actually grants) and
  runs a write attempt as that account via `Start-Process -Credential`,
  asserting it fails. Same shape of proof as the Linux `ciuser` checks.
- **macOS path is otherwise CI-verified** (both scopes pass), but only on
  whatever macOS version `macos-latest` currently is — hasn't been run by
  hand on other macOS versions.
- **`/etc/bashrc` on macOS is best-effort** — Apple no longer guarantees a
  default `~/.bash_profile` sources it. If a user's bash setup doesn't
  source `/etc/bashrc`, they won't pick up the system-wide hook in bash;
  zsh (the macOS default since Catalina) is unaffected, since `/etc/zshenv`
  is always read.
