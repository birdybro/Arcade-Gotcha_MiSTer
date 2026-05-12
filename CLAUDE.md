# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project context

This repo is a MiSTer FPGA core that targets **Atari's 1973 *Gotcha*** arcade game (reference material — schematics, PCB photos, marquee — lives in `docs/`). It was forked from the [MiSTer Template core](https://github.com/MiSTer-devel/Template_MiSTer), and at the moment the `rtl/` contents are still the unmodified Template demo (`mycore.v` generates a noisy cosine pattern via `lfsr.v` + `cos.sv`). Porting work will replace `rtl/` with a Gotcha hardware re-implementation; the framework wiring in `Template.sv` and `sys/` stays.

### Reference: DICE submodule

`docs/DICE/` is a git submodule of [DirtBagXon/DICE](https://github.com/DirtBagXon/DICE), a Discrete Integrated Circuit Emulator that implements early discrete-logic arcade games (Gotcha has no CPU — it's pure TTL). **`docs/DICE/games/gotcha.cpp`** is the canonical schematic-level reference for porting: it enumerates every chip, net, and connection from the Gotcha PCB. Cross-reference it against `docs/Gotcha-Schematics.pdf` when reimplementing a subsystem. After a fresh clone, run `git submodule update --init docs/DICE` to populate it.

## Toolchain & build

- **Quartus Prime 17.0.2** (Lite or Standard) is required. Do not upgrade — newer versions add no benefit for the DE10-Nano's Cyclone V and introduce project-file incompatibilities that break collaboration. A parallel `Template_Q13.*` project set exists for Quartus 13.
- Open `Template.qpf` in Quartus, then Processing → Start Compilation. The compiled `.rbf` goes to `output_files/` (gitignored).
- `clean.bat` wipes all Quartus-generated temp directories/files. Run before committing if `.qsf` or other tracked files have been polluted.
- There is no test harness, linter, or CI in this repo — verification is FPGA synthesis + running on real MiSTer hardware.

## Renaming the core (do this before serious work)

The core is still named "Template". When renamed (e.g. to `Gotcha`):

- Rename `Template.qpf/.qsf/.sdc/.srf/.sv` → `Gotcha.*` and update `PROJECT_REVISION = "Gotcha"` in the `.qpf`.
- Update the `CONF_STR` first line in `Template.sv` (line ~210) — this string is the OSD menu definition.
- **Add core source files to `files.qip` manually, NOT through the Quartus IDE.** The IDE writes new file entries into `Template.qsf`, which causes drift and merge pain. If Quartus has dumped settings into `.qsf`, revert it and move file entries to `files.qip`.

## Architecture: how a MiSTer core is wired together

A MiSTer core is two layers:

1. **Framework (`sys/`)** — shared infrastructure: HPS bridge (`hps_io.sv`), video scaling (`ascal.vhd`, `scandoubler.v`, `hq2x.sv`, `video_mixer.sv`), audio (`audio_out.v`, `i2s.v`, `spdif.v`, `alsa.sv`), SDRAM/DDRAM controllers, PLLs, and the actual top-level entity **`sys_top`** (set in `Template.qsf`). **Treat `sys/` as read-only** — framework updates overwrite it. The qsf sources `sys/sys.tcl` and `sys/sys_analog.tcl` to pull in framework files.
2. **Core glue (`Template.sv`)** — the `emu` module. `sys_top` instantiates `emu` and provides every external pin (HDMI, SDRAM, DDRAM, audio, SD, USB, ADC, UART). `emu` is where you adapt the actual core (in `rtl/`) to the framework's I/O.

Inside `emu`, the key wiring is:

- **`CONF_STR`** is a string literal that declares the OSD menu (aspect ratio, options, file loaders `F`, savestate slots `S`, reset triggers `T`/`R`). It's passed as a parameter to `hps_io`.
- **`hps_io`** is the bidirectional bridge to the ARM HPS (Linux side). It exposes `status[127:0]` (option bits parsed from `CONF_STR`), `buttons`, `ps2_key`, file loading, and joystick input. Every OSD option becomes a slice of `status`.
- **`pll`** (in `rtl/pll.v`, generated from MegaWizard) produces `clk_sys` from the 50 MHz reference. Multi-clock cores typically expose `outclk_1`, `outclk_2`, etc.
- The core module (currently `mycore`) consumes `clk_sys` and outputs `video`, `HBlank`/`VBlank`/`HSync`/`VSync`, and `ce_pix`. `emu` routes those to `VGA_*` and `CE_PIXEL`, which the framework then scales/converts to HDMI/analog/YC.
- Unused pins (SDRAM, DDRAM, ADC, UART, user port) are assigned to `'Z` or `0` near the top of `emu` — leave those defaults in place until that subsystem is actually used.

## Verilog macros (set in `.qsf` as `VERILOG_MACRO`)

These gate framework features at compile time — most are commented out in `Template.qsf`:

| Macro | Effect |
|---|---|
| `MISTER_FB` | Enable DDR3 framebuffer output from the core |
| `MISTER_FB_PALETTE` | 8-bit indexed palette for the framebuffer |
| `MISTER_DUAL_SDRAM` | Pin out a secondary SDRAM (dual-SDRAM I/O board) |
| `MISTER_DEBUG_NOHDMI` | Drop HDMI modules — faster compile, analog/direct only. **Never ship a release with this.** |
| `MISTER_SMALL_VBUF` | Shrink ASCAL frame buffer to ~1 MB/frame |
| `MISTER_DOWNSCALE_NN` | Nearest-neighbor downscale (no bilinear) |
| `MISTER_DISABLE_ADAPTIVE` | Disable adaptive scanlines |
| `MISTER_DISABLE_YC` / `MISTER_DISABLE_ALSA` | Strip composite/Y-C or ALSA audio to save LEs |

## Release convention

Compiled `.rbf` files are committed to a `releases/` folder (not yet present) named `<core_name>_YYYYMMDD.rbf`. `output_files/` is the Quartus build output and is gitignored — copy the `.rbf` into `releases/` manually for a release.
