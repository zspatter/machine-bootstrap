# machine-bootstrap

Fresh-machine setup scripts. Not project-specific, and not dotfiles — see
[sym-lattice](../sym-lattice) for that. Each script bootstraps one tool
(or tightly related pair) onto a machine that doesn't have it yet, kept
per-tool and per-platform so each concern stays independently useful.

## Scripts

- **`setup-uv.sh`** / **`setup-uv.ps1`** — installs [uv](https://docs.astral.sh/uv/)
  via its official standalone installer, then a current default Python
  (`uv python install --default`, so bare `python`/`python3` resolve; the
  `--default` flag is experimental upstream, so the scripts fall back to a
  plain managed install if it ever changes — `uv run`/`uv venv`/`uvx` are
  identical either way).
- **`setup-git.sh`** / **`setup-git.ps1`** — installs git. apt/pacman on
  Linux, Xcode Command Line Tools on macOS, winget on Windows. uv itself
  doesn't need git (prebuilt downloads, no repo clone), but cloning
  sym-lattice or anything else does.
- **`setup-gh-cli.sh`** / **`setup-gh-cli.ps1`** — installs the GitHub CLI
  (`gh`). Install-only, deliberately: `gh auth login` is an interactive
  OAuth/browser flow (or needs a pre-existing `$GH_TOKEN`) that a bootstrap
  script has no business automating. Linux apt path adds GitHub's own repo
  with a GPG-verified keyring per their official docs; Arch has
  `github-cli` in its official repos.
- **`setup-cli-tools.sh`** / **`setup-cli-tools.ps1`** — a curated bundle
  of small zero-config tools: jq, ripgrep, fd, fzf, bat, zoxide. One
  list-driven script rather than a pair per tool, since they all share
  the same shape; adding one later is a one-line change. On Debian/Ubuntu
  the script aliases `fdfind`→`fd` and `batcat`→`bat` in `~/.local/bin`
  (Debian package-name collisions), so dotfiles referencing the real
  names work identically across distros.
- **`setup-nvim.sh`** / **`setup-nvim.ps1`** — Neovim. Linux installs the
  official release tarball into `~/.local` (distro packages, especially
  Debian stable, are often too old for the modern plugin ecosystem — same
  prebuilt-binary reasoning as uv); re-running updates to latest. Windows
  uses winget, which stays current. A foreign nvim already on PATH is
  left alone. Config is the dotfiles repo's job, not this one's.
- **`setup-oh-my-posh.sh`** / **`setup-oh-my-posh.ps1`** — oh-my-posh via
  its official installer (Unix) / winget (Windows). The prompt config in
  the dotfiles repo depends on this binary existing — without it a fresh
  machine comes up with a broken prompt. Nerd Font installation is out of
  scope (`oh-my-posh font install` covers it interactively).
- **`setup-obsidian.sh`** / **`setup-obsidian.ps1`** — Obsidian, app only.
  winget on Windows, brew cask on macOS, the official GitHub-release
  `.deb` on Debian-family (Obsidian has no apt repo), `pacman` on Arch.
  The Linux script refuses to run under WSL (a Linux GUI app there is
  almost never what you want — use the Windows script on the host).
  Vault setup is personal data and deliberately lives in sym-lattice's
  onboarding, not in this public repo.
- **`setup-vscode.sh`** / **`setup-vscode.ps1`** — VS Code. winget /
  brew cask / Microsoft's official apt repo. Arch gets `code` (the
  open-source build in official repos — Microsoft's proprietary build is
  AUR-only, which these scripts don't manage; marketplace/telemetry
  differ). WSL-skips: use Windows VS Code + Remote-WSL there.
- **`setup-zen-browser.sh`** / **`setup-zen-browser.ps1`** — Zen Browser.
  winget / brew cask; Linux has no repo at all, so the official release
  tarball goes into `~/.local` nvim-style with a `.desktop` entry
  (re-run to update — tarball installs don't self-update). WSL-skips.
- **`setup-librewolf.sh`** / **`setup-librewolf.ps1`** — LibreWolf.
  winget / brew cask (`--no-quarantine` per their docs) / the officially
  recommended `extrepo` path on Debian-family. AUR-only on Arch, so the
  script points at your AUR helper there rather than pretending.
  WSL-skips.
- **`setup-claude-desktop.sh`** / **`setup-claude-desktop.ps1`** — the
  Claude Desktop app. winget / brew cask / Anthropic's official signed
  apt repo (Linux support is beta, Debian-family only — the script
  self-skips elsewhere and points at the CLI). WSL-skips.
- **`setup-claude-code.sh`** / **`setup-claude-code.ps1`** — Claude Code
  (the CLI) via the official native installer, which auto-updates in the
  background (the winget/brew/apt alternatives don't by default). Works
  everywhere including WSL. Install-only: auth is an interactive browser
  login, same boundary as `setup-gh-cli`.

All scripts are safe to re-run (CI verifies this for the uv pair on every
run).

## Why uv (and why the pyenv scripts were retired)

This repo originally bootstrapped `pyenv`/`pyenv-win` + `direnv`. That was
replaced wholesale in July 2026:

- **Prebuilt, not compiled.** uv ships standalone Python builds — installs
  take seconds and need zero build dependencies. pyenv compiled from
  source: minutes per install, plus a per-distro build-deps package list to
  maintain (with real drift, e.g. Ubuntu's ncurses dev-package rename).
- **One tool, all platforms.** pyenv and pyenv-win are separate codebases
  with separate failure modes; essentially all of this repo's hard-won
  workaround code (pyenv-win's WSH-blocked version list, shared-root ACL
  lockdown, `pyenv init` rehash interactions) was platform-split fallout.
  The full saga is preserved in this repo's git history, pre-pivot.
- **`uv run` replaces both activation and direnv.** `uv run <cmd>`
  transparently uses the project's pinned interpreter/venv with no
  activation step, identically on Windows and Unix — which also erased the
  old asymmetry (direnv auto-activation on Unix vs. manual `Activate.ps1`
  on Windows) that this repo previously had to document around. direnv is
  no longer installed; per-directory env vars are out of scope here.
- **`.python-version` carries over.** uv reads the same per-project pin
  files pyenv used, and auto-downloads the pinned version on first
  `uv run` in the project.

**No system/shared scope.** The pyenv scripts grew a `--system`/`-Scope
System` mode (shared root, permission lockdown so non-admin accounts could
use but not modify it). That was deliberately *not* ported: uv is per-user
by design, and with per-account setup costing seconds instead of a
compile, the shared install loses its motivation. For a multi-account
machine, run the script once per account — or note that any account with
uv on PATH auto-downloads a project's pinned Python on first `uv run`,
which is the better "new account inherits tooling" story anyway.

## Scope boundary

This is not about per-project `.python-version` / `pyproject.toml` —
that's handled per-repo. This is only about getting the tooling itself
onto a fresh machine. Updates afterward are uv's own job: `uv self update`
and `uv python upgrade`.

## Notes

- **CI** (`.github/workflows/test.yml`): the uv pair runs on native
  `ubuntu-22.04`/`ubuntu-24.04`/`macos-latest`/`windows-latest`, plus
  `debian:11`/`debian:12`/`kalilinux/kali-rolling`/`archlinux:latest`
  containers, each verifying `uv run python --version` end-to-end and
  re-running the script to prove idempotency. A dedicated `uv-no-tools`
  job starts from a container with no git at all (repo fetched by plain
  tarball) to prove `setup-git.sh` genuinely provides git and `setup-uv.sh`
  needs nothing beyond curl. `gh-cli` jobs cover all three platforms plus
  the apt-repo-with-GPG-key and pacman paths. Everything also runs weekly
  (Monday mornings UTC) to catch drift in things this repo doesn't
  control; GitHub emails on failure for scheduled runs by default.
- **Installer hygiene**: both uv installers are downloaded to a temp file
  and executed from disk rather than piped directly into `sh`/`iex` —
  same trust either way, but inspection-friendly and immune to executing
  a truncated stream.
- **macOS Xcode CLT**: `setup-git.sh` on macOS triggers the Command Line
  Tools GUI prompt and can't wait on it — confirm the dialog and re-run.
  On CI runners git is preinstalled, so this path is only exercised on
  real fresh Macs.
- **Windows + [uv#19622](https://github.com/astral-sh/uv/issues/19622)**:
  on some Windows machines (observed live on a hardened Windows 11 build,
  even into a brand-new install dir), `uv python install` exits 2 with
  "Missing expected target directory for Python minor version link" while
  the interpreter itself lands fine and `uv run` works normally. The
  abort also leaves *unstamped* trampoline shims in `~\.local\bin` (uv
  writes a placeholder exe, then stamps the interpreter path into it; the
  error lands between those steps), which would shadow any real `python`
  later on PATH with a broken one. `setup-uv.ps1` handles both: it trusts
  a functional check (`uv run --no-project python --version`) over the
  exit code, and removes any shim that doesn't run. Net effect on
  affected machines: uv-managed flows (`uv run`, `uvx`, `uv venv`) are
  fully functional, but the bare `python`/`python3` shims aren't
  available until the upstream bug is fixed.
