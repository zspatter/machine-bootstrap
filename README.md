# machine-bootstrap

[![Test bootstrap scripts](https://github.com/zspatter/machine-bootstrap/actions/workflows/test.yml/badge.svg)](https://github.com/zspatter/machine-bootstrap/actions/workflows/test.yml)

Fresh-machine setup scripts. Not project-specific, and not dotfiles —
those live in `sym-lattice`, a private repo that consumes this one as a
submodule. Each script bootstraps one tool
(or tightly related pair) onto a machine that doesn't have it yet, kept
per-tool and per-platform so each concern stays independently useful.

## Layout

- **`shell/`** — bash scripts for Linux and macOS
- **`powershell/`** — PowerShell scripts for Windows
- **`assets/`** — vendored data consumed by the scripts (currently the
  audio-eq correction files; provenance pinned in `assets/audio-eq/README.md`)

Same tool, same filename stem, one script per platform family. The only
unpaired scripts are the ones whose tool is single-platform by nature:
`setup-wsl.ps1` and `setup-pwsh.ps1` (Windows-only) and `setup-vimr.sh`
(macOS-only).

## One-command chain

**`shell/install-all.sh`** / **`powershell/install-all.ps1`** run every
setup script in order (foundations first: git, uv), deliberately **not**
fail-fast: each script runs independently, failures are recorded, the
chain continues, and a pass/fail summary prints at the end (non-zero exit
if anything failed). A broken browser install can't block the Python
toolchain, and since every script is idempotent, re-running after a fix
only redoes the broken pieces. `setup-wsl.ps1` is excluded from the chain
on purpose — it can require elevation and a reboot, which has no business
mid-way through an unattended run. `setup-audio-eq.sh`/`.ps1` are likewise
excluded on purpose — hardware-scoped (headphone EQ for a specific DAC),
so they belong only on machines that actually have the hardware; run them
by hand there.

## Scripts

- **`setup-wsl.ps1`** (Windows only, no shell counterpart) — enables WSL
  and installs a distro, defaulting to the name `Ubuntu`, Canonical's
  rolling "current LTS" alias (pinning a version number would go stale);
  `-Distro` overrides. If the WSL feature isn't enabled yet it needs an
  elevated session and typically a reboot. First-run unix account
  creation is interactive by design (`--no-launch` + launch it yourself
  once). Not CI-covered: GitHub's Windows runners can't run WSL.
- **`setup-audio-eq.sh`** / **`setup-audio-eq.ps1`** — headphone EQ
  (Sennheiser HD 800 S, oratory1990 target) from the vendored AutoEq file
  in `assets/audio-eq/`, one artifact consumed by both platforms. Linux
  rides PipeWire's builtin `param_eq` (a config drop, no packages, no
  sudo; PipeWire ≥ 1.2 enforced), with EasyEffects behind `--easyeffects`
  for Peace-style GUI tweaking. Windows manages a `Device:`-scoped
  `Include:` block in Equalizer APO's config.txt (elevated shell), parking
  any Peace include to prevent double EQ; `-Peace` flips management back
  to Peace, `-Remove`/`--remove` restore the pre-script state exactly.
  Excluded from the chain on purpose — hardware-scoped, run by hand on
  machines with the DAC. Not CI-covered: needs live PipeWire/APO and the
  hardware. FiiO firmware is deliberately out of scope (Windows-only DFU
  tooling, and flashing has no business in idempotent provisioning).
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
- **`setup-nvim-tooling.sh`** / **`setup-nvim-tooling.ps1`** — everything
  the Neovim config (sym-lattice `dotfiles/vim/nvim`) launches. LSP
  servers: lua-language-server, pyright, bash-language-server, the
  json/yaml servers (vscode-langservers-extracted, yaml-language-server),
  taplo (toml), roslyn-language-server (C#, a dotnet global tool from the
  Azure DevOps feed — needs .NET SDK ≥ 10, installed when absent), and —
  where pwsh exists — PSScriptAnalyzer plus the PowerShell Editor
  Services bundle at a fixed per-OS path the config's `powershell_es`
  setup relies on. Linters/formatters: shellcheck, shfmt, stylua, ruff.
  Treesitter parser toolchain: the tree-sitter CLI (≥ 0.26.1; winget on
  Windows, GitHub release binary elsewhere with an npm fallback for
  old-glibc distros) and a C compiler (MSVC Build Tools via vswhere check
  on Windows, gcc via apt/pacman elsewhere) — nvim 0.12 bundles only
  seven parsers and compiles the rest locally. The config deliberately
  uses no mason.nvim, so this script is where all of it is maintained.
  apt lacks lua-language-server/stylua → GitHub release binaries into
  `~/.local`; pacman and brew package everything.
- **`setup-oh-my-posh.sh`** / **`setup-oh-my-posh.ps1`** — oh-my-posh via
  its official installer (Unix) / winget (Windows). The prompt config in
  the dotfiles repo depends on this binary existing — without it a fresh
  machine comes up with a broken prompt. Fonts live in `setup-fonts`.
- **`setup-fonts.sh`** / **`setup-fonts.ps1`** — the preferred Nerd Font
  families, per-user: JetBrains Mono NF and Fira Code NF (editors,
  ligatures intact), Meslo LGM NF (terminal prompts — the oh-my-posh
  recommendation). Installs a curated 11-face subset rather than the ~186
  size/spacing variants the release zips ship. Skips WSL (fonts render on
  the Windows host).
- **`setup-neovide.sh`** / **`setup-neovide.ps1`** — Neovide, the GUI
  frontend for Neovim (embeds whatever nvim is on PATH, so `setup-nvim`
  is the real prerequisite). winget / brew cask / pacman, AppImage into
  `~/.local/bin` elsewhere. WSL-skips. GUI-specific settings (font,
  animations) live in the nvim config gated on `vim.g.neovide`.
- **`setup-vimr.sh`** (macOS only — no Linux/Windows build exists, so no
  twin; the script self-skips elsewhere) — VimR, the macOS-native Neovim
  GUI, via brew cask. Reads the same deployed nvim config; Neovide stays
  the GUI everywhere else.
- **`setup-pwsh.ps1`** (Windows only, NOT in the chain — it's the rung
  *below* the chain) — PowerShell 7 (x64, MSI, machine-wide) and Windows
  Terminal, written in Windows PowerShell **5.1** syntax because that's
  the only shell a clean machine ships and every other script here
  assumes pwsh 7. Windows bootstrap order from scratch:
  `setup-pwsh.ps1` (from the stock admin 5.1 shell) → open an *elevated*
  pwsh for `setup-windows-elevated.ps1` (it enables sudo — the last
  elevated shell the bootstrap ever needs; thereafter `sudo` covers
  everything) → `install-all.ps1` from a normal shell. `--source winget` and `--architecture x64` are both
  load-bearing (msstore's same-id MSIX lands per-user in WindowsApps;
  x86 pwsh loses System32 to WOW64 redirection — both hit live).
- **`setup-windows-elevated.ps1`** (Windows only, NOT in the chain) —
  the single elevated touchpoint: Windows sudo in inline mode (the
  deliberate alternative to Developer Mode — elevation stays explicit
  and per-command, `sudo symlink-deploy dotfiles`, instead of making
  symlinks globally unprivileged), the OpenSSH Client capability
  (ssh/ssh-add/ssh-keygen are *not* installed by default), the
  ssh-agent service, and NTFS long paths. Run once:
  `sudo pwsh -NoProfile -File powershell\setup-windows-elevated.ps1`
  (plain `sudo <script>.ps1` fails — sudo execs binaries, not scripts).
  Everything else in this repo stays user-scope by design.
  (`setup-wsl.ps1` stays separate — it can require a reboot.)
- **`setup-ssh-github.sh`** / **`setup-ssh-github.ps1`** — generates an
  ed25519 key when absent (passphrase-less, the unattended-bootstrap
  trade — regenerate with `ssh-keygen -p` if wanted), loads it into the
  agent, and registers it with GitHub through an authenticated `gh`
  (prints the key + URL when gh isn't ready). Runs everywhere
  **including WSL** — a WSL environment wants its own key. On Windows it
  depends on the OpenSSH capability from `setup-windows-elevated.ps1`
  but never needs elevation itself.
- **`setup-zed.sh`** / **`setup-zed.ps1`** — the Zed editor. winget /
  brew cask / Zed's official installer script on Linux (downloaded to
  disk first, per house rule). WSL-skips. Zed self-updates in-app.
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

## Updating

**`update-all.sh`** / **`update-all.ps1`** — one-command update sweep
across every package domain the setup scripts installed: system packages
(winget / apt / pacman / brew), uv tools, npm globals, the Roslyn dotnet
tool, PSScriptAnalyzer. Continue-on-error with a summary, like
install-all. Not part of the install chain — run it when you want
updates. Editor-owned updates stay in the editor: `vim.pack.update()`
for nvim plugins (reviewed in its confirm buffer, pinned by the
committed lockfile) and `:TSUpdate` for treesitter parsers. Exempt a
winget package from the sweep with `winget pin add <id>`.

## Package-manager posture (Windows)

Deliberate, not accumulated:

- **winget is primary.** Everything in this repo that can ride winget
  does — it's preinstalled, first-party, and `winget upgrade --all`
  (via `update-all.ps1`) plus `winget pin` for exceptions is a real
  update story. Its old reputation for gaps and clumsy updates is
  mostly pre-2024 vintage.
- **scoop is the designated gap-filler** — user-scope, no UAC,
  exportable manifests; philosophically the closest thing Windows has
  to Homebrew. But it is *not installed until a real gap appears*:
  when a tool isn't on winget, check scoop first, and only then
  consider anything else.
- **chocolatey is retired.** Admin-heavy and its niche predates winget;
  having it, scoop, *and* winget on one machine is exactly the
  accumulated-by-convenience state this policy exists to prevent.

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
  `ubuntu-latest`/`macos-latest`/`windows-latest` plus a pinned
  `ubuntu-22.04` floor (GitHub has no rolling previous-LTS label — bump
  the pin when GitHub retires it), and on
  `debian:stable`/`debian:oldstable`/`kalilinux/kali-rolling`/
  `archlinux:latest` containers — rolling aliases on purpose, so new
  releases roll into the matrix without anyone remembering to bump a
  version. Each leg verifies `uv run python --version` end-to-end and
  re-runs the script to prove idempotency. A dedicated `uv-no-tools`
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

## License

MIT - see [LICENSE](LICENSE).
