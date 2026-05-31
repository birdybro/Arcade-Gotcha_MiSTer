# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project context

This repo is a MiSTer FPGA core that targets **Atari's 1973 *Gotcha*** arcade game (reference material — schematics, PCB photos, marquee — lives in `docs/`). Forked from the [MiSTer Template core](https://github.com/MiSTer-devel/Template_MiSTer). The core has been renamed from Template to Arcade-Gotcha (qpf/qsf/sdc/srf/sv) and an initial **chip-level netlist port** is in progress in `rtl/`.

### Reference: DICE submodule

`docs/DICE/` is a git submodule of [DirtBagXon/DICE](https://github.com/DirtBagXon/DICE), a Discrete Integrated Circuit Emulator that implements early discrete-logic arcade games (Gotcha has no CPU — it's pure TTL). **`docs/DICE/games/gotcha.cpp`** is the canonical schematic-level reference for porting: it enumerates every chip, net, and connection from the Gotcha PCB. Cross-reference it against `docs/Gotcha-Schematics.pdf` when reimplementing a subsystem. After a fresh clone, run `git submodule update --init docs/DICE` to populate it.

## Toolchain & build

- **Quartus Prime 17.0.2** (Lite or Standard) is required. Do not upgrade — newer versions add no benefit for the DE10-Nano's Cyclone V and introduce project-file incompatibilities that break collaboration.
- Open `Arcade-Gotcha.qpf` in Quartus, then Processing → Start Compilation. The compiled `.rbf` goes to `output_files/` (gitignored).
- `clean.bat` wipes all Quartus-generated temp directories/files. Run before committing if `.qsf` or other tracked files have been polluted.
- There is no test harness or CI in this repo — final verification is FPGA synthesis + running on real MiSTer hardware. For fast iteration, `verilator --lint-only --top-module gotcha rtl/gotcha.sv rtl/chips/ttl_*.sv` (suppress `-Wno-WIDTH -Wno-UNOPTFLAT -Wno-CASEINCOMPLETE`) catches connectivity/syntax/comb-loop errors before a Quartus run. The `emu` wrapper (`Arcade-Gotcha.sv`) can't be linted standalone — it needs `sys/`.

## Reference docs

Two local reference trees (added 2026-05; consult them when touching the relevant area):

- **`mister-framework-reference/`** — the MiSTer framework contracts: `emu` top-level, `CONF_STR`, clocks/PLLs, `hps_io`, video, **audio** (the `AUDIO_L/R/S/MIX` stability-synchroniser contract), build/sim. Use before wiring anything to the framework boundary.
- **`hdl-coding-guidelines/`** — synthesizable-SV + Cyclone V guidelines: registers/comb blocks, FSMs, memory/DSP inference, timing/SDC, and a numbered **`90-anti-patterns.md`** (e.g. #3 combinational feedback loop, #4 inferred latch). Consult when adding non-trivial RTL.

Each tree has a `00-INDEX.md`. These already shaped the Phase 7 audio code (registered `AUDIO`, clocked SR latch instead of cross-coupled gates).

## files.qip discipline

**Add core source files to `files.qip` manually, NOT through the Quartus IDE.** The IDE writes new file entries into `Arcade-Gotcha.qsf` instead, which causes drift and merge pain. If Quartus has dumped settings into `.qsf`, revert it and move any file entries to `files.qip`. The current `files.qip` lists `Arcade-Gotcha.sv`, `rtl/gotcha.sv`, and each `rtl/chips/ttl_*.sv` primitive explicitly.

## Roadmap & live status: `tasks.md`

`tasks.md` is the porting roadmap and working-state tracker — read it at the start of a session. It holds the phase breakdown (Phase 0 sync-gen → Phase 8 polish), a **"📍 Resume here"** block describing whatever subsystem is mid-debug (current symptoms, diagnostic rounds already run, hypothesised mechanism, next steps), and per-phase "what changed / how to verify on hardware / failure modes" notes. CLAUDE.md stays high-level and stable; `tasks.md` is where in-flight and per-commit detail lives. Update its Resume-here block as debugging progresses, and check uncommitted working-tree changes against it (debug hacks like RGB-split video or a disabled chip are often left in the tree and must be reverted before committing).

## Architecture: how a MiSTer core is wired together

A MiSTer core is three layers, and the Gotcha port preserves all three:

1. **Framework (`sys/`)** — shared infrastructure: HPS bridge (`hps_io.sv`), video scaling (`ascal.vhd`, `scandoubler.v`, `hq2x.sv`, `video_mixer.sv`), audio (`audio_out.v`, `i2s.v`, `spdif.v`, `alsa.sv`), SDRAM/DDRAM controllers, PLLs, and the actual top-level entity **`sys_top`** (set in `Arcade-Gotcha.qsf`). **Treat `sys/` as read-only** — framework updates overwrite it. The qsf sources `sys/sys.tcl` and `sys/sys_analog.tcl` to pull in framework files.
2. **Core glue (`Arcade-Gotcha.sv`)** — the `emu` module. `sys_top` instantiates `emu` and provides every external pin (HDMI, SDRAM, DDRAM, audio, SD, USB, ADC, UART). `emu` is where you adapt the actual core (in `rtl/`) to the framework's I/O. It instantiates `gotcha` (the netlist top) and the `pll`.
3. **Core (`rtl/gotcha.sv` + `rtl/chips/ttl_*.sv`)** — the chip-level netlist. `rtl/gotcha.sv` is a structural translation of `docs/DICE/games/gotcha.cpp`: each 74xx chip in the original Atari PCB has a corresponding `ttl_*` primitive instance with **pin-numbered ports** (`pin1`, `pin2`, ...) mirroring the DIP package. Chip instance names are prefixed with `u_` (e.g. `u_J6`, `u_L6`, `u_H4`) so they don't collide with signal nets like `H4` or `M1` that share the same letters; the schematic designator after `u_` still matches the PCB position. Net names (CLK, H1..H256, V1..V256, ...) match the schematic verbatim. Translation is mechanical: read a `CONNECTION(SRC, "X", n)` line in gotcha.cpp, wire `.pinN(SRC)` on `ttl_<type>` with instance name `u_X`.

### Chip-level porting conventions

- **HDL language:** SystemVerilog (`.sv`). Use `logic`, `always_ff`, `always_comb`. Don't write plain Verilog `.v` for new files.
- **Clock model:** A single `clk_sys` domain at **28.63636 MHz** (2× the netlist's 14.31818 MHz CLOCK). clk_sys is run at 2× so the MiSTer HDMI scaler gets more cycles per pixel — with `ce_pix` at the 7.159 MHz pixel rate this puts `CE_PIXEL` at `CLK_VIDEO/4`. The real 14.31818 MHz CLOCK net is recreated inside `rtl/gotcha.sv` as `CLOCK_14M` (a `clk_sys/2` toggle) and fed to J6's CP1 pin. Every TTL flip-flop primitive (`ttl_7474`, `ttl_7493`, `ttl_74107`) uses `always_ff @(posedge clk_sys)` and **edge-detects its chip clock pin** via a `pin_prev` register — including J6 now that it sees a real divided CLOCK net (the old `CP1_IS_CLK_SYS` parameter hack has been removed). Any `clk_sys`-cycle-count constants (the D8 ~1 Hz divider, B7 9602 pulse widths, the emu.sv button stretchers) are sized for 28.636 MHz — rescale them if the PLL frequency changes again.
- **Mislabeled chips in `gotcha.cpp`:** L6 and M6 are declared `CHIP("9316")` but wired with the 7493 pinout (CLK on pin 14, R0 on pins 1-3, QA→CKB self-cascade). They are 7493s functionally — instantiate `ttl_7493` for these. F5 and H5 are correctly declared 7493 and follow the same pattern. The real 9316 chips in gotcha.cpp (C4, D1, D4, E3, F3, G1, H3, J3, K1, L1) use the standard 9316 pinout (CLK on pin 2) — `ttl_9316` exists for these (used by C4/D4 so far).
- **`ttl_7493` SELF_CASCADE + synchronous H counter:** All four Gotcha 7493s are wired as 4-bit binary counters. Modeling the QA→CKB self-cascade as a chained per-stage edge detector adds a spurious 1-`clk_sys` lag between QA and QB/QC/QD — a wrong counter value sampled on ~every other pixel ("sliver wraparound"). `ttl_7493` therefore takes a `SELF_CASCADE` parameter; **all four instances (L6, M6, H5, F5) set `SELF_CASCADE(1)`**, modeling the chip as one atomic 4-bit synchronous counter. In `SELF_CASCADE` mode `pin1` (CKB) is repurposed as a **synchronous count-enable**. The H counter goes one step further to kill *inter-nibble* lag too: L6, M6 and J6.FF2 all clock on the root `CLK`, with M6's count-enable = `L6_tc` (L6 at 15) and J6.FF2's J2/K2 = `H_carry256` (= `L6_tc & M6_tc`) — a proper synchronous carry chain, so the whole 9-bit H counter updates on one `clk_sys` edge. The V counter (H5/F5/D5.FF1) keeps the simpler nibble-ripple cascade because its inter-nibble settling lands inside the H-reset window (HBLANK) and is never sampled in the visible region. General rule for this port: never chain edge-detected derived clocks where one synchronous counter does the job.
- **Reference flow when adding a subsystem:** open `docs/DICE/games/gotcha.cpp`, find the `/* SectionName */` block, list the chips, add primitives for any chip types not yet in `rtl/chips/`, then translate each `CONNECTION(SRC, "CHIP", pin)` line into a `.pinN(SRC)` wire in `rtl/gotcha.sv`. Net `#define`s in gotcha.cpp (e.g. `#define H1 "L6", 12`) become Verilog wire aliases. **`CONNECTION(a, b)` just nets two pins together — it is not directional;** the output pin drives, input pins receive. Always check the chip's pinout to know which side is the output.
- **Propagation-delay audit (do this for every section):** the schematic relies on transparent propagation delay — ripple counters, chip outputs used as other chips' clocks. A naive per-chip edge detector turns sub-ns ripple into full-`clk_sys`-cycle lag → visible artifacts. When a chip's clock pin is driven by another chip's output, ask whether it should be one atomic synchronous update. Counter chains: clock every stage from the root clock, gate upper stages with the lower stages' terminal count (`ttl_7493` `SELF_CASCADE`+`pin1` enable; `ttl_9316` RCO→CEP). A 74107 toggle-FF clocked off a ripple can be made synchronous by clocking CP from the root clock (or its inverse, to match edge sense) and gating J/K with the carry condition — see J6.FF2 (H256) and J2.FF2 (Right player). Single-stage edge detection of a *settled* combinational signal is fine and is the correct pattern; only *chained* edge detection is the problem.

Inside `emu`, the key wiring is:

- **`CONF_STR`** is a string literal that declares the OSD menu (aspect ratio, options, file loaders `F`, savestate slots `S`, reset triggers `T`/`R`). It's passed as a parameter to `hps_io`.
- **`hps_io`** is the bidirectional bridge to the ARM HPS (Linux side). It exposes `status[127:0]` (option bits parsed from `CONF_STR`), `buttons`, `ps2_key`, file loading, and joystick input. Every OSD option becomes a slice of `status`.
- **`pll`** (in `rtl/pll.v`, generated from MegaWizard) produces `clk_sys` from the 50 MHz reference. Multi-clock cores typically expose `outclk_1`, `outclk_2`, etc.
- The core module (currently `mycore`) consumes `clk_sys` and outputs `video`, `HBlank`/`VBlank`/`HSync`/`VSync`, and `ce_pix`. `emu` routes those to `VGA_*` and `CE_PIXEL`, which the framework then scales/converts to HDMI/analog/YC.
- Unused pins (SDRAM, DDRAM, ADC, UART, user port) are assigned to `'Z` or `0` near the top of `emu` — leave those defaults in place until that subsystem is actually used.

## Verilog macros (set in `.qsf` as `VERILOG_MACRO`)

These gate framework features at compile time — most are commented out in `Arcade-Gotcha.qsf`:

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
