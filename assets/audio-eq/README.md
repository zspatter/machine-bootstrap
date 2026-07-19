# audio-eq assets

Vendored EQ correction for Sennheiser HD 800 S (oratory1990 measurement,
AutoEq harman target). Consumed by `shell/setup-audio-eq.sh` on Linux and by
Equalizer APO on Windows. Pinned here deliberately: AutoEq regenerates its
results over time, and provisioning must not depend on the network or on a
moving upstream.

## Files

| file | consumer |
|---|---|
| `hd800s-oratory1990-parametric.txt` | PipeWire `param_eq` (Linux, default mode) and Equalizer APO (Windows, via `Include:`) |
| `hd800s-oratory1990-easyeffects.json` | EasyEffects (Linux, `--easyeffects` mode). Not vendored yet; export from https://autoeq.app (HD 800 S, oratory1990, EasyEffects format) |

## Provenance

- Source: jaakkopasanen/AutoEq, `results/oratory1990/over-ear/Sennheiser HD 800 S/`
- Fetched: 2026-07-18 (master)
- sha256 (parametric txt): `cd66132568a826b705bf4d245c0494e78259c6d252fdf40e693cb49f463a913d`
- Content: Preamp -6.2 dB + 10 filters (LSC/PK/HSC)

## Rules

1. **Line 1 of the txt must be the `Preamp:` line.** PipeWire's parser reads the
   preamp only from line 1 and silently drops a non-preamp first line. The
   setup script enforces this; don't reorder the file.
2. **LF line endings only.** The script rejects CRLF.
3. **Regenerate the txt and the EasyEffects json together**, from the same
   AutoEq state, or the two Linux modes drift apart. Update the hash and fetch
   date above when you do.
4. The preamp is applied by `param_eq` itself (as a 0 Hz high-shelf); do not
   add a separate gain stage.

## Windows

Provisioned by `powershell/setup-audio-eq.ps1` (elevated shell). Equalizer APO is
the engine and consumes the same txt; Peace is only an editor for APO's config.

    setup-audio-eq.ps1            # default: Device-scoped Include of the txt
    setup-audio-eq.ps1 -Peace     # Peace-managed mode (one-time GUI import)
    setup-audio-eq.ps1 -Remove    # restore pre-script config.txt exactly
    setup-audio-eq.ps1 -Status

Direct mode marker-comments any `Include: Peace.txt` line to prevent double
EQ; `-Peace` and `-Remove` restore it. A one-time backup lands next to
config.txt. APO hot-reloads on save, so changes apply live. First-time APO
install stays manual by nature: installer, Configurator (bind the FiiO
endpoint), reboot, then re-run the script.

## Deliberately out of scope

macOS. PipeWire and EasyEffects are Linux-only; a Mac would need a third
engine on CoreAudio (SoundSource ships AutoEq corrections natively). Revisit
only if a Mac actually joins the fleet.

FiiO DAC firmware. FiiO's updaters are Windows-only DFU tools, and firmware
flashing is rare, interactive, and brick-capable, which makes it wrong for
idempotent provisioning on any OS. Flash from the Windows side of the dual
boot when needed. The DAC itself needs no Linux setup (USB Audio Class 2,
driverless).

## Notes

- If EasyEffects is ever run as a Flatpak instead of the deb, the preset must
  be **copied** (not symlinked) into
  `~/.var/app/com.github.wwmm.easyeffects/config/easyeffects/output/`;
  the sandbox cannot follow links into the repo.
- Optional PipeWire nicety, unrelated to EQ: `default.clock.allowed-rates`
  lets the graph follow source sample rates instead of resampling to 48 kHz.
