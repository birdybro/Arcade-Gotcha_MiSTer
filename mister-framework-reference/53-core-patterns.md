# 53 — Cross-Cutting Core Patterns

> Bundle version: 2026-05-18
> Pinned commits: `Template_MiSTer` @ `f35083f3b40d`, `MkDocs_MiSTer` @ `9033bd292fdc`
> Load with: [10-emu-top-level.md](10-emu-top-level.md), [11-conf-str.md](11-conf-str.md), [12-clocks-resets-plls.md](12-clocks-resets-plls.md), [20-hps-io-overview.md](20-hps-io-overview.md), [30-sdram.md](30-sdram.md), [31-ddram.md](31-ddram.md), `91-porting-checklist.md` (planned, not yet written)
> Status mix: [C] [V] [O] [I]
>
> Scope note: this doc collects the cross-cutting framework-level patterns that span every topic doc in this bundle. Per-port details, per-protocol contracts, and per-subsystem grammar live in their dedicated docs (10–52). Reference-core RTL (NES, SNES, PSX, ao486, etc.) is NOT in the archive snapshot, so per-core RTL comparisons in §6 are marked `[deferred — reference cores not fetched]`; framework-implied variation axes are concrete and citable from `Template_MiSTer`.

## 1. Purpose & one-line summary

A MiSTer core is a directory tree (`sys/` + `rtl/` + a couple of project files) whose top-level entity is the framework's `sys_top.v`, which instantiates the user's `emu` module — the only piece the core author writes from scratch. This document synthesizes the cross-cutting patterns that every core obeys regardless of subsystem: layout conventions, the `sys/`-is-frozen rule, Quartus version lock-in, Verilog-macro feature gates, tie-off discipline (chip pins float to `Z`, internal bridges tie to `'0`, open-drain releases to `'1`), the canonical `emu → hps_io + pll + mycore` instance graph, and the small ordered porting timeline that maps existing RTL onto this skeleton.

## 2. The contract (must-obey)

### Project layout

- C.1. The Quartus top-level entity is **`sys_top`** (in `sys/sys_top.v`), not the core's `emu`; `Template.qsf` asserts `TOP_LEVEL_ENTITY sys_top`. [C] (archive/github/MiSTer-devel/Template_MiSTer/Template.qsf:11 @ f35083f3b40d)
- C.2. `sys/` is the framework directory and is **frozen** — framework updates may erase any customization, so cores must include it byte-identically from `Template_MiSTer`. [C] (archive/github/MiSTer-devel/Template_MiSTer/Readme.md:14 @ f35083f3b40d)
- C.3. `rtl/` holds the user RTL; the per-core PLL (`rtl/pll.v` + `rtl/pll.qip`) **must live in `rtl/`**, not `sys/`, so framework updates do not clobber it. [C] (archive/github/MiSTer-devel/Template_MiSTer/Readme.md:30 @ f35083f3b40d; archive/github/MiSTer-devel/MkDocs_MiSTer/docs/developer/emu.md:13-15 @ 9033bd292fdc)
- C.4. The core's file inventory **must** be declared in `files.qip`, not in `.qsf`; Quartus IDE's "add file" dialog writes to `.qsf` and that is the wrong path. [C] (archive/github/MiSTer-devel/Template_MiSTer/Template.qsf:1-9,78 @ f35083f3b40d; archive/github/MiSTer-devel/Template_MiSTer/Readme.md:24 @ f35083f3b40d)
- C.5. `.qsf` settings are not where the file list lives; the comment block at the top of `Template.qsf` explicitly warns that adding files via the IDE will "mess this file." [C] (archive/github/MiSTer-devel/Template_MiSTer/Template.qsf:5-7 @ f35083f3b40d)
- C.6. `<core>.qsf` sources three things in order: `sys/sys.tcl` (board/pin/IO standards), `sys/sys_analog.tcl` (analog VGA/audio pin assignments), and `files.qip` (the per-core file list). [C] (archive/github/MiSTer-devel/Template_MiSTer/Template.qsf:76-78 @ f35083f3b40d)
- C.7. The optional `<core>.srf` (Severity-Reduction File) silences known-safe Quartus warnings; it is the recommended way to keep the message log readable. [V] (archive/github/MiSTer-devel/Template_MiSTer/Readme.md:21 @ f35083f3b40d)
- C.8. Release artifacts are placed in `releases/` as `<core_name>_YYYYMMDD.rbf` (YYYYMMDD = build date). [V] (archive/github/MiSTer-devel/Template_MiSTer/Readme.md:16 @ f35083f3b40d)
- C.9. Output `.rbf` is emitted because `Template.qsf` sets `GENERATE_RBF_FILE ON`; the project output directory is `output_files/`. [C] (archive/github/MiSTer-devel/Template_MiSTer/Template.qsf:18-19 @ f35083f3b40d)
- C.10. The `.rbf` name on disk **must** match the name the menu reads; the MiSTer menu loads `<core_name>_YYYYMMDD.rbf` from `releases/`. [V] (archive/github/MiSTer-devel/Template_MiSTer/Readme.md:16 @ f35083f3b40d)

### Tool version & device

- C.11. Cores **must** be developed in Quartus **17.0.x** (Lite or Standard); `Template.qsf` records `LAST_QUARTUS_VERSION "17.0.2 Standard Edition"`. [C] (archive/github/MiSTer-devel/Template_MiSTer/Template.qsf:16 @ f35083f3b40d; archive/github/MiSTer-devel/Template_MiSTer/Readme.md:47-49 @ f35083f3b40d)
- C.12. An alternate Quartus 13.1 build is supported via the `_Q13` project family (`Template_Q13.qpf/.qsf/.srf`); `Template_Q13.qsf` records `LAST_QUARTUS_VERSION 13.1`. [V] (archive/github/MiSTer-devel/Template_MiSTer/Template_Q13.qsf:16 @ f35083f3b40d)
- C.13. The framework dispatches the PLL IP set per Quartus version through `sys/sys.qip:1`, which evaluates `pll_q[regexp $quartus(version)].qip` at compile time; `pll_q13.qip` chains to the 13.1 PLL IPs (`pll.13.qip`, `pll_hdmi.13.qip`, `pll_audio.13.qip`) and `pll_q17.qip` chains to the 17.0 set. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/sys.qip:1 @ f35083f3b40d; archive/github/MiSTer-devel/Template_MiSTer/sys/pll_q17.qip:1-4 @ f35083f3b40d; archive/github/MiSTer-devel/Template_MiSTer/sys/pll_q13.qip:1-4 @ f35083f3b40d)
- C.14. Target device is fixed: `5CSEBA6U23I7` (Cyclone V SoC, UFBGA-672, speed grade 7); `sys/sys.tcl` writes the assignment. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/sys.tcl:1-5 @ f35083f3b40d)

### Verilog macro feature gates

- C.15. Feature toggles are passed as Quartus `VERILOG_MACRO` assignments in `<core>.qsf`; nine macros are recognized by the framework (see §3.4 table). [C] (archive/github/MiSTer-devel/Template_MiSTer/Template.qsf:53-74 @ f35083f3b40d; archive/github/MiSTer-devel/Template_MiSTer/Readme.md:36-45 @ f35083f3b40d)
- C.16. `MISTER_FB` extends `emu_ports.vh` with the 9-port `FB_*` group (DDR-backed framebuffer); the conditional is `` `ifdef MISTER_FB `` in `sys/emu_ports.vh`. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/emu_ports.vh:40 @ f35083f3b40d)
- C.17. `MISTER_FB_PALETTE` is nested under `MISTER_FB` and adds the 5-port `FB_PAL_*` group for 8bpp indexed modes. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/emu_ports.vh:58 @ f35083f3b40d)
- C.18. `MISTER_DUAL_SDRAM` adds the `SDRAM2_*` port group and `SDRAM2_EN` input; defining it requires sourcing `sys/sys_dual_sdram.tcl` from `.qsf` (which also re-pins the analog/audio/SDIO ports). [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/emu_ports.vh:124-136 @ f35083f3b40d; archive/github/MiSTer-devel/Template_MiSTer/sys/sys_dual_sdram.tcl:51 @ f35083f3b40d)
- C.19. `MISTER_DEBUG_NOHDMI` elides the HDMI PLL/scaler; permitted only in development (the `Template.qsf` comment "do not enable DEBUG_NOHDMI in release!"). [C] (archive/github/MiSTer-devel/Template_MiSTer/Template.qsf:58-59 @ f35083f3b40d; archive/github/MiSTer-devel/Template_MiSTer/sys/sys_top.v:997-1018 @ f35083f3b40d)
- C.20. The remaining macros (`MISTER_DOWNSCALE_NN`, `MISTER_DISABLE_ADAPTIVE`, `MISTER_SMALL_VBUF`, `MISTER_DISABLE_YC`, `MISTER_DISABLE_ALSA`) tune scaler / video-path / audio-path resource budgets and are listed in the `<core>.qsf` template as commented-out toggles. [C] (archive/github/MiSTer-devel/Template_MiSTer/Template.qsf:62-74 @ f35083f3b40d)

### emu module and instance graph

- C.21. The user core's top module is **always** `module emu` with port list `` `include "sys/emu_ports.vh" ``; `sys_top.v` instantiates exactly one `emu`. [C] (archive/github/MiSTer-devel/Template_MiSTer/Template.sv:19-22 @ f35083f3b40d) — see [10-emu-top-level.md](10-emu-top-level.md).
- C.22. The user PLL **module** is named `pll` and the **instance** is also named `pll`; `sys/sys_top.sdc` searches `*|pll|pll_inst|*` to constrain it. [C] (archive/github/MiSTer-devel/Template_MiSTer/Template.sv:113-118 @ f35083f3b40d; archive/github/MiSTer-devel/Template_MiSTer/sys/sys_top.sdc:14 @ f35083f3b40d) — see [10-emu-top-level.md §7](10-emu-top-level.md).
- C.23. Inside `emu`, exactly one `hps_io` is instantiated with `.HPS_BUS(HPS_BUS)` passed through unchanged from the `emu` port; the instance is conventionally named `hps_io` matching the module name. [C] (archive/github/MiSTer-devel/Template_MiSTer/Template.sv:94-108 @ f35083f3b40d) — see [20-hps-io-overview.md](20-hps-io-overview.md).
- C.24. `CONF_STR` is a `localparam` declared in the core's `.sv` and passed to `hps_io` via `#(.CONF_STR(CONF_STR))`. [C] (archive/github/MiSTer-devel/Template_MiSTer/Template.sv:58-87,94 @ f35083f3b40d) — see [11-conf-str.md](11-conf-str.md).
- C.25. The reset chain into the core is conventionally `wire reset = RESET | status[0] | buttons[1];`. [V] (archive/github/MiSTer-devel/Template_MiSTer/Template.sv:120 @ f35083f3b40d; archive/github/MiSTer-devel/MkDocs_MiSTer/docs/developer/emu.md:36-38 @ 9033bd292fdc)

### Tie-off discipline

- C.26. Unused **chip-pin** outputs (`SDRAM_*`, `ADC_BUS`, `SD_*`) must be driven `'Z` (high-Z) because they connect to physical board pins. [C] (archive/github/MiSTer-devel/Template_MiSTer/Template.sv:26,29-30 @ f35083f3b40d)
- C.27. Unused **internal-bridge** outputs (`DDRAM_*` group) must be driven `'0` because they feed the on-chip Avalon-MM `f2sdram` bridge — a tri-state value on an internal bus is illegal. [C] (archive/github/MiSTer-devel/Template_MiSTer/Template.sv:31 @ f35083f3b40d) — see [10-emu-top-level.md §7](10-emu-top-level.md), [31-ddram.md](31-ddram.md).
- C.28. **Open-drain** outputs (`USER_OUT[6:0]`) must be driven `'1` to release the line for pull-up; `'0` actively sinks. [C] (archive/github/MiSTer-devel/Template_MiSTer/Template.sv:27 @ f35083f3b40d; archive/github/MiSTer-devel/Template_MiSTer/sys/emu_ports.vh:145-151 @ f35083f3b40d) — see [10-emu-top-level.md §7 A.3](10-emu-top-level.md).
- C.29. Other unused `output` ports (UART, LED_*, BUTTONS, the framework's video / audio tie-offs) must be driven `0` because Verilog requires every module `output` to be driven. [C] (archive/github/MiSTer-devel/Template_MiSTer/Template.sv:28,33-48 @ f35083f3b40d)

### Versioning & build metadata

- C.30. `sys/build_id.tcl` regenerates `build_id.v` on every compile, defining the macro `` `BUILD_DATE `` to a `YYMMDD` string; the core `` `include`s it before `CONF_STR`. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/build_id.tcl:5-27 @ f35083f3b40d; archive/github/MiSTer-devel/Template_MiSTer/Template.sv:57 @ f35083f3b40d)
- C.31. The idiomatic `V,...` line is `"V,v",` `` `BUILD_DATE ``, stamping today's build date into the OSD title bar. [V] (archive/github/MiSTer-devel/Template_MiSTer/Template.sv:86 @ f35083f3b40d) — see [11-conf-str.md C.15](11-conf-str.md).
- C.32. The CONF_STR `v,<n>` directive (an integer 0–99) bumps the saved-status compatibility tag; any incompatible CONF_STR bit-layout change requires bumping this number. [C] (archive/github/MiSTer-devel/Template_MiSTer/Template.sv:83-85 @ f35083f3b40d) — see [11-conf-str.md §7 A.2](11-conf-str.md).

### Coding style (project-wide)

- C.33. Indent with **tabs**, not spaces; the upstream guidance is "tabs are more compatible and will be easier for everyone to work with" and ships in `principles.md`. [V] (archive/github/MiSTer-devel/MkDocs_MiSTer/docs/developer/principles.md:1-5 @ 9033bd292fdc)
- C.34. Active-low signals carry the `_n` suffix (e.g. `hold_n`, `cs_n`, `wp_n`); the convention is uniform across `sys/` and reference cores. [V] (archive/github/MiSTer-devel/MkDocs_MiSTer/docs/developer/principles.md:144-157 @ 9033bd292fdc; archive/github/MiSTer-devel/Template_MiSTer/sys/emu_ports.vh:119-122 @ f35083f3b40d)
- C.35. `(* multstyle = "logic" *)` may be applied to a module / variable / binary expression to force logic instead of DSP/BRAM inference when the DSP/BRAM budget is exhausted. [V] (archive/github/MiSTer-devel/MkDocs_MiSTer/docs/developer/principles.md:159-169 @ 9033bd292fdc)

## 3. Ports / signals reference

This topic does not own a port-list (every cross-cutting port already lives in its dedicated doc — see 10, 11, 12, 20, 30, 31, 40, 41). What follows is the **universally common scaffolding** every core builds: one row per cross-cutting pattern, with the citation for its canonical instance in `Template_MiSTer`.

### 3.1 The four mandatory blocks inside `module emu`

```verilog
// archive/github/MiSTer-devel/Template_MiSTer/Template.sv:19-120 @ f35083f3b40d
module emu
(
    `include "sys/emu_ports.vh"     // (1) framework port list
);
// (2) default tie-offs for unused ports
assign ADC_BUS  = 'Z;
assign USER_OUT = '1;
assign {UART_RTS, UART_TXD, UART_DTR} = 0;
assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;
assign {SDRAM_DQ, SDRAM_A, SDRAM_BA, SDRAM_CLK, SDRAM_CKE, SDRAM_DQML,
        SDRAM_DQMH, SDRAM_nWE, SDRAM_nCAS, SDRAM_nRAS, SDRAM_nCS} = 'Z;
assign {DDRAM_CLK, DDRAM_BURSTCNT, DDRAM_ADDR, DDRAM_DIN, DDRAM_BE,
        DDRAM_RD, DDRAM_WE} = '0;
// ... (other tie-offs: VGA_SL, HDMI_*, AUDIO_*, LED_*, BUTTONS) ...

// (3) CONF_STR + hps_io
`include "build_id.v"
localparam CONF_STR = { /* ... */ };

hps_io #(.CONF_STR(CONF_STR)) hps_io
(
    .clk_sys(clk_sys),
    .HPS_BUS(HPS_BUS),
    /* ... */
);

// (4) per-core PLL
wire clk_sys;
pll pll
(
    .refclk(CLK_50M),
    .rst(0),
    .outclk_0(clk_sys)
);

// reset distribution
wire reset = RESET | status[0] | buttons[1];
```

| # | Pattern | Always present? | Citation |
| --- | --- | --- | --- |
| 1 | `` `include "sys/emu_ports.vh" `` after `module emu (` | Yes [C] | `Template.sv:19-22 @ f35083f3b40d` |
| 2 | Default tie-offs for every unused output port | Yes [C] | `Template.sv:24-48 @ f35083f3b40d` |
| 3 | `localparam CONF_STR = { ... }` + `hps_io #(.CONF_STR(CONF_STR)) hps_io (...)` | Yes [C] | `Template.sv:58-108 @ f35083f3b40d` |
| 4 | `pll pll ( .refclk(CLK_50M), .rst(0), .outclk_0(clk_sys), ... )` | Yes [C] | `Template.sv:112-118 @ f35083f3b40d` |
| 5 | `wire reset = RESET \| status[0] \| buttons[1];` | Convention [V] | `Template.sv:120 @ f35083f3b40d` |
| 6 | `assign CLK_VIDEO = clk_sys; assign CE_PIXEL = <core ce_pix>;` | Convention [V] | `Template.sv:149-150 @ f35083f3b40d` |
| 7 | `assign VGA_DE = ~(HBlank \| VBlank);` and positive-polarity HS/VS | Convention [V] | `Template.sv:152-154 @ f35083f3b40d` |
| 8 | `act_cnt` activity counter on `clk_sys` driving `LED_USER` | Convention [V] | `Template.sv:159-161 @ f35083f3b40d` |

### 3.2 Tie-off pattern by port class

The three port classes have **three different idle values** — confusing them is a common bring-up bug.

| Port class | Idle value | Reason | Examples | Citation |
| --- | --- | --- | --- | --- |
| External chip pin (input or `inout`) | `'Z` | Releases pin to its physical pull-up / external driver | `SDRAM_*`, `ADC_BUS`, `SD_SCK/MOSI/CS` | `Template.sv:26,29-30 @ f35083f3b40d` |
| Internal Avalon-MM bridge port | `'0` | Bridge inside the SoC — tri-state is illegal | `DDRAM_*` (CLK, BURSTCNT, ADDR, DIN, BE, RD, WE) | `Template.sv:31 @ f35083f3b40d` |
| Open-drain pin output | `'1` | `0` actively pulls low; `1` releases for pull-up | `USER_OUT[6:0]` | `Template.sv:27 @ f35083f3b40d` |
| Regular pin output | `0` | Plain `output`, must be driven | `UART_RTS/TXD/DTR`, `LED_*`, `BUTTONS`, `VGA_*` tie-offs | `Template.sv:28,33-48 @ f35083f3b40d` |

### 3.3 Directory & filename conventions

| Path | What it contains | Edit-able? | Citation |
| --- | --- | --- | --- |
| `sys/` | Framework Verilog/VHDL/Tcl shared verbatim across all cores | **No** [C] | `Readme.md:14 @ f35083f3b40d` |
| `rtl/` | User RTL; per-core PLL **must** live here | Yes [C] | `Readme.md:14-15,30 @ f35083f3b40d` |
| `releases/` | Output `.rbf` named `<core>_YYYYMMDD.rbf` | Yes (output) [V] | `Readme.md:16 @ f35083f3b40d` |
| `<core>.qpf` | Quartus project file; only `PROJECT_REVISION` is edited per core | Minimal [V] | `Readme.md:19 @ f35083f3b40d` |
| `<core>.qsf` | Quartus settings — sources `sys/sys.tcl`, `sys/sys_analog.tcl`, `files.qip`; carries `VERILOG_MACRO` toggles | Yes (settings only) [C] | `Template.qsf:1-9,53-78 @ f35083f3b40d` |
| `<core>.sdc` | Optional extra timing constraints | Yes [V] | `Readme.md:22 @ f35083f3b40d` |
| `<core>.srf` | Optional warning suppression | Yes [V] | `Readme.md:21 @ f35083f3b40d` |
| `<core>.sv` | The `module emu` glue: CONF_STR + `hps_io` + `pll` + user RTL wiring | Yes [C] | `Template.sv @ f35083f3b40d`; `Readme.md:23 @ f35083f3b40d` |
| `files.qip` | The canonical list of core source files | Yes (this is the only legal place to add files) [C] | `files.qip @ f35083f3b40d`; `Readme.md:24 @ f35083f3b40d` |
| `build_id.v` | Auto-generated by `sys/build_id.tcl` on every compile; defines `` `BUILD_DATE `` | **Generated** [C] | `sys/build_id.tcl:5-27 @ f35083f3b40d` |
| `clean.bat` | Windows batch — purges Quartus temp files | Optional [V] | `Readme.md:25 @ f35083f3b40d` |
| `jtag.cdf` | Generated on compile by `sys/sys.tcl`'s `generateCDF` proc; never committed | **Generated** [V] | `Readme.md:27 @ f35083f3b40d` |

### 3.4 VERILOG_MACRO feature gates

These are the nine macros recognized by the framework. Each is enabled by uncommenting a `set_global_assignment -name VERILOG_MACRO "<NAME>=1"` line in `<core>.qsf`.

| Macro | Effect | Adds emu ports? | Build-tree side effects | Citation |
| --- | --- | --- | --- | --- |
| `MISTER_FB` | DDR-backed framebuffer video path | Yes — `FB_EN, FB_FORMAT, FB_WIDTH, FB_HEIGHT, FB_BASE, FB_STRIDE, FB_VBL, FB_LL, FB_FORCE_BLANK` [C] | `sys_top.v` instantiates ascal FB-mode | `emu_ports.vh:40-56 @ f35083f3b40d`; `Template.qsf:53 @ f35083f3b40d` |
| `MISTER_FB_PALETTE` | 8bpp indexed mode palette | Yes — `FB_PAL_CLK/ADDR/DOUT/DIN/WR` [C] | Requires `MISTER_FB=1` | `emu_ports.vh:58-66 @ f35083f3b40d`; `Template.qsf:56 @ f35083f3b40d` |
| `MISTER_DUAL_SDRAM` | Second SDR SDRAM module on the dual board | Yes — `SDRAM2_EN, SDRAM2_CLK/A/BA/DQ/nCS/nCAS/nRAS/nWE` [C] | Sourcing `sys/sys_dual_sdram.tcl` from `.qsf` re-pins analog ports | `emu_ports.vh:124-136 @ f35083f3b40d`; `sys_dual_sdram.tcl:51 @ f35083f3b40d` |
| `MISTER_DEBUG_NOHDMI` | Disable HDMI PLL & ascal | No | Faster compile; analog only [C] | `sys_top.v:997-1018 @ f35083f3b40d`; `Template.qsf:58-59 @ f35083f3b40d` |
| `MISTER_DOWNSCALE_NN` | Ascal nearest-neighbour downscale | No | Image quality / resource trade [C] | `Template.qsf:61-62 @ f35083f3b40d`; `Readme.md:42 @ f35083f3b40d` |
| `MISTER_DISABLE_ADAPTIVE` | Disable adaptive scanline filter | No | Resource trade [C] | `Template.qsf:64-65 @ f35083f3b40d`; `Readme.md:43 @ f35083f3b40d` |
| `MISTER_SMALL_VBUF` | Use 1 MB per frame for scaler | No | Frees ~21 MB DDR3 [C] | `Template.qsf:67-68 @ f35083f3b40d`; `Readme.md:41 @ f35083f3b40d` |
| `MISTER_DISABLE_YC` | Disable composite/YC output | No | Saves resources [C] | `Template.qsf:70-71 @ f35083f3b40d` |
| `MISTER_DISABLE_ALSA` | Disable ALSA audio mixing from HPS | No | Saves resources [C] | `Template.qsf:73-74 @ f35083f3b40d` |

## 4. Sequencing & timing

This doc has no per-cycle waveform — those live in 10–52. The sequence that **is** cross-cutting is the **porting timeline**: the ordered set of steps that takes a working RTL outside MiSTer to a working core inside it. Each step maps to the topic doc that owns its details.

```
Step 0 — copy the Template_MiSTer tree as the starting point.
   |
   v
Step 1 — Rename the project files (qpf/qsf/srf/sv/.sdc) to <core_name>.*
         and replace every literal "Template" / "zxspectrum" with the new core
         name inside those files. NEVER start from a blank Quartus project.
         (See Readme.md:8-22; primary deliverable is a project that still
         compiles before any RTL changes.)
   |
   v
Step 2 — Edit files.qip: remove Template's example RTL (lfsr.v, cos.sv,
         mycore.v) and add your core's RTL files. Do NOT use Quartus IDE's
         "Add Files" dialog — it writes to <core>.qsf and the .qsf will get
         "spit" full of garbage on the next IDE round-trip.
         [-> see 53 §7 A.3, Readme.md:20-21,24]
   |
   v
Step 3 — Generate the per-core PLL: open the MegaWizard in Quartus, edit
         rtl/pll.v in place. Keep both module name and instance name as
         "pll" so sys_top.sdc constrains it. Pick a clk_sys frequency that
         divides cleanly to all core CE rates (CPU, audio, pixel).
         [-> see 10-emu-top-level.md §7 A.2, 12-clocks-resets-plls.md §2]
   |
   v
Step 4 — Wire the existing top-level entity's ports into emu's expected
         port list. Rename the top entity to "emu" if not already.
         [-> see 10-emu-top-level.md §3]
   |
   v
Step 5 — Add the four mandatory blocks (§3.1 above):
         (a) tie-offs for every unused output port (§3.2 table)
         (b) localparam CONF_STR with at minimum the title, T[0]/R[0] reset,
             v,<n>, and V,<build_date>
         (c) hps_io instantiation with HPS_BUS passed through
         (d) pll instantiation deriving clk_sys from CLK_50M
         [-> see 11-conf-str.md, 20-hps-io-overview.md]
   |
   v
Step 6 — Drive CLK_VIDEO / CE_PIXEL / VGA_R/G/B/HS/VS/DE from the core's
         pixel generator. CLK_VIDEO must be > 40 MHz. VGA_DE must equal
         ~(HBlank | VBlank). HS/VS must be positive-polarity pulses.
         [-> see 40-video.md §2]
   |
   v
Step 7 — Drive AUDIO_L/R/S/MIX. AUDIO_L/R are 16-bit; AUDIO_S declares
         their sign. CLK_AUDIO is a framework-supplied 24.576 MHz input.
         [-> see 41-audio.md §2]
   |
   v
Step 8 — If the core needs ROMs, wire the ioctl path: ioctl_download,
         ioctl_index, ioctl_addr, ioctl_dout, ioctl_wr; hold internal
         reset across the download level. F-slot entries in CONF_STR.
         [-> see 21-hps-io-ioctl-and-download.md, 32-rom-save-state-flows.md]
   |
   v
Step 9 — If the core uses SDRAM, instantiate a MiSTer-style SDRAM
         controller against the SDRAM_* pins (pad-registered, three-clock
         IOE; do NOT bring in a generic sdram.v from a non-MiSTer project).
         [-> see 30-sdram.md, 53 §7 A.4]
   |
   v
Step 10 — If the core needs disk images, declare S-slot(s) in CONF_STR;
          handle img_mounted, sd_lba, sd_buff_* read/write.
          [-> see 22-hps-io-mount-and-sd.md]
   |
   v
Step 11 — Add OSD options as CONF_STR O[bit] directives; consume status[]
          bits. Wire status_menumask if any H/D/h/d directives are present.
          Bump v,<n> on every incompatible CONF_STR change.
          [-> see 11-conf-str.md §6, §7]
   |
   v
Step 12 — Compile; verify the .rbf appears in releases/ named
          <core>_YYYYMMDD.rbf; copy to MiSTer SD card, load from menu.
          [-> see 91-porting-checklist.md (forward ref)]
   |
   v
Step 13 — Bring-up debug: OSD opens? VGA stable? HDMI scaler locks?
          Audio sane? Use MiSTer.ini knobs (direct_video=1, vga_scaler=1,
          forced_scandoubler=1, vsync_adjust=2) to isolate path bugs.
          [-> see 10-emu-top-level.md §8]
```

The ordering is **prescriptive** for new porters: skipping ahead (e.g. wiring CONF_STR before the project compiles in Step 1) tends to compound errors. Step 0 (copy `Template_MiSTer`) is the most-skipped step and produces the most-painful debug cycles — see §7 A.2.

## 5. Minimal working pattern

The "checklist core skeleton" — every emu starts here, then grows. This is the smallest correct `module emu` that compiles, OSD-loads, and emits silence + black: the **four mandatory blocks** (§3.1) plus minimum video/audio idle drivers. Everything below is verbatim from `Template_MiSTer/Template.sv`; comments mark each pattern.

```verilog
// archive/github/MiSTer-devel/Template_MiSTer/Template.sv:19-120 @ f35083f3b40d
module emu
(
    `include "sys/emu_ports.vh"        // PATTERN 1: framework port list
);

///////// Default values for ports not used in this core /////////

// PATTERN 2a: tri-state chip pins
assign ADC_BUS  = 'Z;
assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;
assign {SDRAM_DQ, SDRAM_A, SDRAM_BA, SDRAM_CLK, SDRAM_CKE, SDRAM_DQML, SDRAM_DQMH, SDRAM_nWE, SDRAM_nCAS, SDRAM_nRAS, SDRAM_nCS} = 'Z;

// PATTERN 2b: release open-drain
assign USER_OUT = '1;

// PATTERN 2c: zero internal-bridge outputs (NOT tri-state)
assign {DDRAM_CLK, DDRAM_BURSTCNT, DDRAM_ADDR, DDRAM_DIN, DDRAM_BE, DDRAM_RD, DDRAM_WE} = '0;

// PATTERN 2d: zero regular outputs
assign {UART_RTS, UART_TXD, UART_DTR} = 0;
assign VGA_SL = 0;
assign VGA_F1 = 0;
assign VGA_SCALER  = 0;
assign VGA_DISABLE = 0;
assign HDMI_FREEZE = 0;
assign HDMI_BLACKOUT = 0;
assign HDMI_BOB_DEINT = 0;
assign AUDIO_S = 0;
assign AUDIO_L = 0;
assign AUDIO_R = 0;
assign AUDIO_MIX = 0;
assign LED_DISK = 0;
assign LED_POWER = 0;
assign BUTTONS = 0;

//////////////////////////////////////////////////////////////////

// PATTERN 3a: localparam CONF_STR with title, reset, v,n, V,banner
`include "build_id.v"
localparam CONF_STR = {
    "Template;;",                         // title (must be first directive)
    "-;",
    "T[0],Reset;",                        // soft reset trigger
    "R[0],Reset and close OSD;",          // soft reset + close OSD
    "v,0;",                               // CONF_STR compat version 0..99
    "V,v",`BUILD_DATE                     // build banner (YYMMDD)
};

wire forced_scandoubler;
wire   [1:0] buttons;
wire [127:0] status;
wire  [10:0] ps2_key;

// PATTERN 3b: exactly one hps_io, HPS_BUS passed through unchanged
hps_io #(.CONF_STR(CONF_STR)) hps_io
(
    .clk_sys(clk_sys),
    .HPS_BUS(HPS_BUS),
    .EXT_BUS(),
    .gamma_bus(),

    .forced_scandoubler(forced_scandoubler),

    .buttons(buttons),
    .status(status),
    .status_menumask({status[5]}),

    .ps2_key(ps2_key)
);

///////////////////////   CLOCKS   ///////////////////////////////

// PATTERN 4: per-core PLL, module name == instance name == "pll"
wire clk_sys;
pll pll
(
    .refclk(CLK_50M),
    .rst(0),
    .outclk_0(clk_sys)
);

// PATTERN 5: conventional reset chain
wire reset = RESET | status[0] | buttons[1];
```

A real core then adds (cf. `Template.sv:122-162`):
- `O[..]` directives inside `CONF_STR` for menu options,
- A `mycore mycore (...)` instance taking `clk_sys`/`reset` and producing pixels + sound,
- `assign CLK_VIDEO = clk_sys;` and `assign CE_PIXEL = ce_pix;`,
- `assign VGA_DE = ~(HBlank | VBlank);`, `VGA_HS = HSync;`, `VGA_VS = VSync;` and RGB assignments,
- An activity counter on `clk_sys` driving `LED_USER`.

## 6. Common variations across cores

Direct RTL diffs between reference cores (NES, SNES, PSX, ao486, etc.) are **`[deferred — reference cores not fetched]`**. The framework-implied variation axes below are concrete and citable from `Template_MiSTer` + the framework's own conditionals.

### 6.1 Memory configuration

- V.1. **Single-SDRAM vs Dual-SDRAM.** Defining `MISTER_DUAL_SDRAM` adds the `SDRAM2_*` port group and `SDRAM2_EN` input. Cores must tri-state `SDRAM2_*` "ASAP" when `SDRAM2_EN=0` because the secondary daughter board may be physically absent. Enabling dual-SDRAM also **mutually excludes** the analog VGA/audio/SDIO port group (sys_top gates them under `` `ifndef MISTER_DUAL_SDRAM ``). [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/emu_ports.vh:124-136 @ f35083f3b40d; archive/github/MiSTer-devel/Template_MiSTer/sys/sys_dual_sdram.tcl:51 @ f35083f3b40d) — see [30-sdram.md §2](30-sdram.md).
- V.2. **No SDRAM at all.** Simple 8-bit cores (Template demo) tri-state the whole SDRAM bus and never instantiate a controller. [V] (archive/github/MiSTer-devel/Template_MiSTer/Template.sv:30 @ f35083f3b40d)
- V.3. **DDRAM in use vs tied off.** DDRAM goes to the on-chip f2sdram bridge; unused ports tie to `'0`, **not `Z`**. Cores using DDRAM (CD-based systems, savestate buffers, scaler framebuffers) drive the full Avalon-MM interface. [V] (archive/github/MiSTer-devel/Template_MiSTer/Template.sv:31 @ f35083f3b40d) — see [31-ddram.md](31-ddram.md).

### 6.2 Video configuration

- V.4. **`MISTER_FB` on vs off.** Defining `MISTER_FB` extends the port list with 9 `FB_*` ports for DDR-backed video. Cores using FB drive `FB_EN`, `FB_FORMAT`, `FB_WIDTH`, `FB_HEIGHT`, `FB_BASE`, `FB_STRIDE` and consume `FB_VBL`/`FB_LL`; cores not using FB leave the macro undefined and the ports do not exist. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/emu_ports.vh:40-67 @ f35083f3b40d) — see [40-video.md](40-video.md), [40a-video-pipeline.md](40a-video-pipeline.md).
- V.5. **`MISTER_FB_PALETTE` (nested).** Adds the 5-port `FB_PAL_*` group for 8bpp indexed modes. Requires `MISTER_FB=1`. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/emu_ports.vh:58-66 @ f35083f3b40d)
- V.6. **CLK_VIDEO ≡ clk_sys vs separate pixel clock.** Template assigns `CLK_VIDEO = clk_sys`. Cores with high pixel clocks (arcade / 480p systems) generate a dedicated PLL output. [O] (archive/github/MiSTer-devel/Template_MiSTer/Template.sv:149 @ f35083f3b40d)
- V.7. **`MISTER_DISABLE_YC` / `MISTER_DISABLE_ALSA`.** Disable composite/YC output and ALSA-from-HPS audio respectively to free fabric and DDR3 resources; both are pure resource trades. [C] (archive/github/MiSTer-devel/Template_MiSTer/Template.qsf:70-74 @ f35083f3b40d)
- V.8. **Arcade vs console framing.** Arcade cores typically use `arcade_video` (wraps `video_mixer` with `fx`-to-`{hq2x, sl}` mapping and bit-depth expansion); console cores use `video_mixer` directly. Arcade cores also tend to drive `CHEAT;` and `DIP;` CONF_STR directives backed by an MRA XML file. [V] (archive/github/MiSTer-devel/Template_MiSTer/sys/arcade_video.v:1-30 @ f35083f3b40d) — see [40a-video-pipeline.md](40a-video-pipeline.md). Per-core RTL diffs: **`[deferred — reference cores not fetched]`**.

### 6.3 Toolchain variant

- V.9. **Quartus 17.0.x vs 13.1.** The `_Q13` project family (`Template_Q13.qpf/.qsf/.srf`) targets Quartus 13.1; PLL IPs dispatch via the `pll_q[regexp]\.qip` mechanism in `sys/sys.qip:1`. 17.0.x is the recommended target. [V] (archive/github/MiSTer-devel/Template_MiSTer/Template_Q13.qsf:16 @ f35083f3b40d; archive/github/MiSTer-devel/Template_MiSTer/sys/sys.qip:1 @ f35083f3b40d)
- V.10. **lite vs full Quartus.** The framework supports both Quartus Lite and Standard. `Template.qsf` records the Standard edition string; Lite is functionally identical for MiSTer cores. [V] (archive/github/MiSTer-devel/Template_MiSTer/Template.qsf:16 @ f35083f3b40d; archive/github/MiSTer-devel/Template_MiSTer/Readme.md:48 @ f35083f3b40d)
- V.11. **`MISTER_DEBUG_NOHDMI`.** Development-only macro that elides the HDMI PLL and scaler chain. Speeds compile, halves resource usage; **must not** be left enabled in releases (the `.qsf` comment is explicit). [C] (archive/github/MiSTer-devel/Template_MiSTer/Template.qsf:58-59 @ f35083f3b40d)

### 6.4 Per-core RTL differences (deferred)

The following per-core variations require reference-core RTL to document concretely:

- ROM-load strategy: SPI-streamed via `ioctl_*` vs direct-DDRAM `shmem_map`. **`[deferred — reference cores not fetched]`** (background in [32-rom-save-state-flows.md §2.1](32-rom-save-state-flows.md)).
- Save-state inclusion (the `SS<base>:<size>` CONF_STR token and per-core change-detector wiring). **`[deferred — reference cores not fetched]`** (mechanics in [32-rom-save-state-flows.md §2.3](32-rom-save-state-flows.md)).
- Per-core `sdram.v` controller differences (NES vs SNES vs PSX). **`[deferred — reference cores not fetched]`** (pin-level contract in [30-sdram.md](30-sdram.md)).
- Custom helpers reused across cores (e.g. cycle-accurate CPU cores, sound chip emulations). **`[deferred — reference cores not fetched]`**.
- CONF_STR layout patterns (paged options, save-state slots, MRA-backed DIP menus). **`[deferred — reference cores not fetched]`** (grammar in [11-conf-str.md](11-conf-str.md)).

## 7. Anti-patterns

### A.1 Editing files in `sys/`

- **Symptom:** Local fixes / experiments work in the current build. Then a framework update is pulled (or `Template_MiSTer` is re-synced) and every change in `sys/` is silently erased; bugs return; cores may stop compiling.
- **Cause:** `sys/` is shared verbatim across all cores in the MiSTer-devel organization. The framework's update process is a directory copy, not a merge. Any local change to `sys/hps_io.sv`, `sys/sys_top.v`, `sys/video_mixer.sv`, etc. will be lost on next sync.
- **Fix:** If the core genuinely needs a tweak to framework behaviour, **either** (a) configure it via an existing `VERILOG_MACRO` (§3.4 table) and `hps_io` parameter (e.g. `VDNUM`, `BLKSZ`, `WIDE`, `PS2DIV`, `CONF_STR_BRAM`), **or** (b) raise it upstream so it lands in the framework for everyone. Never patch `sys/`. The `Readme.md` is explicit: "Basically it's prohibited to change any files in this folder. Framework updates may erase any customization in this folder."
- **Citation:** archive/github/MiSTer-devel/Template_MiSTer/Readme.md:14 @ f35083f3b40d

### A.2 Starting from a blank Quartus project instead of `Template_MiSTer`

- **Symptom:** Various combinations of: `sys_top` not found; unconstrained clocks; PLL never locks; HDMI pixel clock disappears; `sys/sys.tcl` complains about missing IO standards; build fails halfway through with cryptic Tcl errors; or compile succeeds but the `.rbf` does nothing on hardware.
- **Cause:** The MiSTer framework is not a Quartus IP catalogue plug-in — it is a *project layout* with very specific entry points (`TOP_LEVEL_ENTITY sys_top`, `source sys/sys.tcl`, `source sys/sys_analog.tcl`, `source files.qip`), generated artifacts (`build_id.v`, `jtag.cdf`), per-Quartus-version PLL dispatch (`pll_q[regexp]\.qip`), and dozens of pin assignments. Re-creating these from a blank project takes longer than just copying `Template_MiSTer`, and missing **any one** of them produces an opaque failure.
- **Fix:** Start by copying the entire `Template_MiSTer` directory tree. Rename project files (`Template.qpf`, `Template.qsf`, `Template.srf`, `Template.sdc`, `Template.sv` → `<core_name>.*`), then search-and-replace the literal "Template" inside those files. Trim `files.qip` to remove the Template demo RTL. Compile *before* adding your own RTL to confirm the project still builds.
- **Citation:** archive/github/MiSTer-devel/Template_MiSTer/Readme.md:8-22 @ f35083f3b40d; archive/github/MiSTer-devel/Template_MiSTer/Template.qsf:11,76-78 @ f35083f3b40d; archive/github/MiSTer-devel/MkDocs_MiSTer/docs/developer/porting.md:8-23 @ 9033bd292fdc

### A.3 Adding files via Quartus IDE's "Add Files" dialog

- **Symptom:** Files are added "successfully" but later builds fail to find them, or `<core>.qsf` swells with hundreds of lines of duplicated settings, or `git diff` of `<core>.qsf` is enormous and impossible to review.
- **Cause:** The Quartus IDE's file-add dialog writes `set_global_assignment -name SYSTEMVERILOG_FILE <path>` lines into **`<core>.qsf`**, not `files.qip`. Worse, on subsequent saves, Quartus "spits" all settings (defaults, pin assignments, etc.) from sourced Tcl back into `<core>.qsf`, turning it into a noisy mess.
- **Fix:** Edit `files.qip` by hand. Add one line per RTL file in the project — e.g. `set_global_assignment -name SYSTEMVERILOG_FILE rtl/mycore.v`. Re-open the Quartus project to pick up the new files. If `<core>.qsf` grows unexpectedly, revert it to a clean version against git and re-add only the user-meaningful changes (e.g. uncomenting a `VERILOG_MACRO` line). The `Template.qsf` comment block at the top is unambiguous: "WARNING WARNING WARNING: Do not add files to project in Quartus IDE! It will mess this file! Add the files manually to files.qip file."
- **Citation:** archive/github/MiSTer-devel/Template_MiSTer/Template.qsf:1-9 @ f35083f3b40d; archive/github/MiSTer-devel/Template_MiSTer/files.qip:1-5 @ f35083f3b40d; archive/github/MiSTer-devel/Template_MiSTer/Readme.md:20-24 @ f35083f3b40d

### A.4 Importing a non-MiSTer SDRAM controller

- **Symptom:** SDRAM reads/writes work for some access patterns and corrupt for others; ghosting on burst boundaries; timing closure fails or barely passes; warning about combinatorial logic on `SDRAM_*` pad paths being retimed unexpectedly.
- **Cause:** MiSTer's `sys/sys.tcl` pins every `SDRAM_*` signal at `FAST_OUTPUT_REGISTER ON`, `FAST_INPUT_REGISTER ON` (on `SDRAM_DQ`), and `FAST_OUTPUT_ENABLE_REGISTER ON` (on `SDRAM_DQ`). It also sets `ALLOW_SYNCH_CTRL_USAGE OFF` to forbid synchronous-control implementation of the IOEs. A controller designed for a different board (e.g. a generic `sdram.v` from a MiST core, a SoC dev-board reference design, or a verilog-hdl repo) typically expects the synthesizer to insert IO registers itself and may carry combinatorial logic into the pad path. On MiSTer, that logic gets *retimed into the IOE flip-flop*, breaking the controller's internal timing assumptions.
- **Fix:** Use a MiSTer-style SDRAM controller — one whose last stage on every `SDRAM_*` output is a flip-flop in the user logic (so the IOE register is the second one and timing is predictable), and whose `SDRAM_DQ` tri-state enable is driven by a single dedicated register (so `FAST_OUTPUT_ENABLE_REGISTER ON` has a single legal IOE to inhabit). Reference cores carry their own `rtl/sdram.v` matching this pattern; do not paste in a controller from a non-MiSTer project. If a port is required, audit every output for combinatorial paths and convert them to registered drivers before bring-up.
- **Citation:** archive/github/MiSTer-devel/Template_MiSTer/sys/sys.tcl:53-98 @ f35083f3b40d; cross-ref [30-sdram.md §2](30-sdram.md).

### A.5 Forgetting to bump `v,<n>` after a CONF_STR layout change

- **Symptom:** Users boot a new build of a previously-installed core and see settings land in unexpected bit positions — "TV Mode" defaults to PAL where it used to be NTSC, "Aspect" is wrong, etc. Visible only on machines that previously ran an older build (fresh installs are fine).
- **Cause:** The HPS persists the `status[]` snapshot between core launches. A CONF_STR change that **moves** option bits (additions, deletions, range edits, reorderings) without bumping the `v,<n>` integer means the HPS replays the old snapshot into the new bit layout — silently.
- **Fix:** Whenever any `O`/`T`/`R` bit assignment changes, increment the integer after `v,`. Range 0–99. Forcing defaults on first start with the new layout is the only correct cure. This anti-pattern is documented in detail in [11-conf-str.md §7 A.2](11-conf-str.md); restated here because the failure spans CONF_STR (the cause) and persistent settings management (the symptom).
- **Citation:** archive/github/MiSTer-devel/Template_MiSTer/Template.sv:83-85 @ f35083f3b40d; cross-ref [11-conf-str.md §7 A.2](11-conf-str.md).

## 8. Verification

This doc has no per-protocol verification — that lives in 10–52. The cross-cutting checks are:

- **Project rebuild from a clean tree.** After every framework re-sync (copy `Template_MiSTer/sys/`), do a clean compile (delete `output_files/`, `db/`, `incremental_db/`, run `clean.bat`). A successful clean compile from a fresh `sys/` confirms no local edits exist in `sys/` (A.1).
- **`files.qip` is the only file inventory.** `grep -l '^set_global_assignment -name .*VERILOG_FILE' <core>.qsf` should return zero matches (excluding the `source files.qip` and `source sys/*.tcl` lines). If your `.qsf` has accumulated `VERILOG_FILE` lines, the IDE has been editing it (A.3); revert and move the lines into `files.qip`.
- **PLL constraint match.** Open the Timing Analyzer after a fit; check `Reports → Diagnostic → Unconstrained Paths`. Zero unconstrained paths from/to `*|pll|pll_inst|*` confirms the user PLL is correctly named (cross-ref [10-emu-top-level.md §7 A.2](10-emu-top-level.md)).
- **`.rbf` artifact name.** After a build, `releases/<core_name>_YYYYMMDD.rbf` should exist with today's date. The build date is regenerated each compile via `sys/build_id.tcl`, so it auto-tracks the calendar.
- **OSD title shows build date.** Open the OSD on the running core. The title bar should show `<title> v<YYMMDD>` where `<YYMMDD>` is today (or build day). This confirms `` `BUILD_DATE `` is wired into the `V,...` line of CONF_STR (§2 C.30, C.31).
- **Default tie-offs are visible.** Synthesis report after a fresh compile should show **no warnings** about unused / undriven outputs in `emu`. Each unused output should be assigned exactly one of `'Z`, `'0`, `'1`, or `0` per the §3.2 table.
- **Verilog macro audit.** `grep VERILOG_MACRO <core>.qsf` should show only the macros you intentionally enabled. `MISTER_DEBUG_NOHDMI` must be commented out for releases.
- **MiSTer.ini isolation knobs** (cross-cutting):
  - `direct_video=1` bypasses the HDMI scaler; isolate scaler-feeding bugs from pixel-stream bugs.
  - `vga_scaler=1` forces the HDMI scaler onto the analog VGA path; isolate analog-vs-digital bugs.
  - `forced_scandoubler=1` ties `forced_scandoubler` high regardless of OSD; useful for 15 kHz cores being run through a VGA monitor.
  - `vsync_adjust=2` exposes drift in `VGA_VS` rate; if the framework cannot lock, the core's video clock is off-frequency (cross-ref [10-emu-top-level.md §8](10-emu-top-level.md)).

## 9. Provenance footer

- archive/github/MiSTer-devel/Template_MiSTer/Template.sv @ f35083f3b40d — used for §2, §3, §5, §7
- archive/github/MiSTer-devel/Template_MiSTer/Template.qsf @ f35083f3b40d — used for §2, §3, §6, §7, §8
- archive/github/MiSTer-devel/Template_MiSTer/Template_Q13.qsf @ f35083f3b40d — used for §2, §6
- archive/github/MiSTer-devel/Template_MiSTer/Readme.md @ f35083f3b40d — used for §2, §3, §4, §7
- archive/github/MiSTer-devel/Template_MiSTer/files.qip @ f35083f3b40d — used for §2, §3, §7
- archive/github/MiSTer-devel/Template_MiSTer/sys/emu_ports.vh @ f35083f3b40d — used for §2, §3, §6
- archive/github/MiSTer-devel/Template_MiSTer/sys/sys_top.sdc @ f35083f3b40d — used for §2
- archive/github/MiSTer-devel/Template_MiSTer/sys/sys.tcl @ f35083f3b40d — used for §2, §7
- archive/github/MiSTer-devel/Template_MiSTer/sys/sys.qip @ f35083f3b40d — used for §2, §6
- archive/github/MiSTer-devel/Template_MiSTer/sys/sys_dual_sdram.tcl @ f35083f3b40d — used for §2, §6
- archive/github/MiSTer-devel/Template_MiSTer/sys/pll_q17.qip @ f35083f3b40d — used for §2
- archive/github/MiSTer-devel/Template_MiSTer/sys/pll_q13.qip @ f35083f3b40d — used for §2
- archive/github/MiSTer-devel/Template_MiSTer/sys/sys_top.v @ f35083f3b40d — used for §2
- archive/github/MiSTer-devel/Template_MiSTer/sys/build_id.tcl @ f35083f3b40d — used for §2, §3
- archive/github/MiSTer-devel/Template_MiSTer/sys/arcade_video.v @ f35083f3b40d — used for §6
- archive/github/MiSTer-devel/MkDocs_MiSTer/docs/developer/porting.md @ 9033bd292fdc — used for §7
- archive/github/MiSTer-devel/MkDocs_MiSTer/docs/developer/principles.md @ 9033bd292fdc — used for §2
- archive/github/MiSTer-devel/MkDocs_MiSTer/docs/developer/emu.md @ 9033bd292fdc — used for §2
- mister-context/10-emu-top-level.md §2, §3, §7, §8 — referenced as cross-link
- mister-context/11-conf-str.md §6, §7 — referenced as cross-link
- mister-context/12-clocks-resets-plls.md §2 — referenced as cross-link
- mister-context/20-hps-io-overview.md — referenced as cross-link
- mister-context/21-hps-io-ioctl-and-download.md — referenced as cross-link
- mister-context/22-hps-io-mount-and-sd.md — referenced as cross-link
- mister-context/30-sdram.md §2 — referenced as cross-link
- mister-context/31-ddram.md — referenced as cross-link
- mister-context/32-rom-save-state-flows.md §2.1, §2.3 — referenced as cross-link
- mister-context/40-video.md §2 — referenced as cross-link
- mister-context/40a-video-pipeline.md — referenced as cross-link
- mister-context/41-audio.md §2 — referenced as cross-link
- mister-context/91-porting-checklist.md — forward reference (not yet written at this commit)
