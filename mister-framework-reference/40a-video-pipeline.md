# 40a — Video pipeline (framework-internal modules)

> Bundle version: 2026-05-18
> Pinned commits: `Template_MiSTer @ f35083f3b40d`, `MkDocs_MiSTer @ 9033bd292fdc`
> Load with: [40-video.md](40-video.md), [12-clocks-resets-plls.md](12-clocks-resets-plls.md), [41-audio.md](41-audio.md)
> Status mix: `[C]`, `[V]`, `[O]`, `[I]`
>
> NOTE: This file is the split companion to `40-video.md`. The emu-boundary contract (`VGA_*`, `VIDEO_ARX/ARY`, `HDMI_*`, `CLK_VIDEO`/`CE_PIXEL`) lives in `40-video.md`. **This file** covers the `sys/` framework's internal video modules and their order in the analog and HDMI chains.

## 1. Purpose & one-line summary

The framework converts the core's emu-boundary RGB+sync into two independent sinks. The HDMI chain runs (in order): `s_fix` polarity-fix → `video_freezer` (sync regen) → `gamma_corr` (optional) → `scandoubler/Hq2x` (optional) → `ascal` (clock-domain crossing into `clk_hdmi`, polyphase scale, DDR3 framebuffer, deinterlace) → `shadowmask` → `osd` → `vga_out` (RGB→YPbPr) → `altddio_out`. The analog VGA chain runs: `s_fix` → `scanlines` → `osd` → `yc_out` (optional) or `vga_out` → 6-bit truncate to IO board DAC. Most cores never touch these modules directly; they instantiate either `video_mixer` (a wrapper around `s_fix`+`video_freezer`+`gamma_corr`+`scandoubler`) or `arcade_video` (which wraps `video_mixer` with RGB-bit-depth expansion and `fx`-to-`{hq2x,sl}` mapping).

## 2. The contract (must-obey)

Pipeline ordering (framework side)
- HDMI chain order is fixed in `sys_top.v`: emu RGB → (core wrapper: `s_fix` + `video_freezer` + `gamma_corr` + `scandoubler/Hq2x`) → ascal (clock domain crossing) → `shadowmask` → `osd` → `vga_out` → DDIO. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/sys_top.v:714-1338 @ f35083f3b40d)
- Analog chain order is fixed: post-mixer RGB → `scanlines` (gated by `VGA_SL`) → `osd` → either `vga_out` (RGB or YPbPr) or `yc_out` (composite/S-Video) → 6-bit truncation → analog DAC. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/sys_top.v:1383-1525 @ f35083f3b40d)

Module parameter contracts
- `video_mixer` parameter `LINE_LENGTH` MUST be ≥ the core's active pixel width per line, because the scandoubler line buffer is sized to it. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/video_mixer.sv:21 @ f35083f3b40d)
- `video_mixer` `HALF_DEPTH=1` accepts 4-bit-per-channel RGB and replicates to 8-bit at output; `GAMMA=1` upgrades the mid-pipe to 8-bit. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/video_mixer.sv:62-64 @ f35083f3b40d)
- `arcade_video` parameter `DW` selects packed RGB width (6/8/9/12/18/24); the wrapper auto-expands to 8-bit per channel and sets the inner `HALF_DEPTH = (DW != 24)`. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/arcade_video.v:29,81-112,118 @ f35083f3b40d)
- `arcade_video` requires `clk_video > 40 MHz` and `clk_video ≥ 4 × ce_pix`. [C] (archive/github/MiSTer-devel/MkDocs_MiSTer/docs/developer/arcade_video.md:16 @ 9033bd292fdc)
- `scandoubler` parameter `LENGTH` is the line length; `HALF_DEPTH` matches `video_mixer`'s. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/scandoubler.v:22 @ f35083f3b40d)

Gamma bus protocol
- The `gamma_bus[21:0]` is a bidirectional control word from `hps_io` carrying `clk_sys` (bit 20), `gamma_en` (bit 19), `gamma_wr` (bit 18), 10-bit `gamma_wr_addr` (bits 17:8), and 8-bit `gamma_value` (bits 7:0); bit [21] is the presence-ack driven by the core when gamma is wired up. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/gamma_corr.sv:1-20, video_mixer.sv:109,133 @ f35083f3b40d)
- Cores that do not consume the gamma bus MUST leave `gamma_bus` unconnected; `video_mixer` drives `gamma_bus[21]=0` when `GAMMA=0` so `hps_io` knows the core opted out. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/video_mixer.sv:133 @ f35083f3b40d)

ascal interface contracts
- ascal has 5 clock domains: `i_clk` (input video), `o_clk` (output video), `avl_clk` (Avalon DDR3), `poly_clk` (polyphase coefficient writes), `pal1_clk`/`pal2_clk` (palette writes). [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/ascal.vhd:32-38 @ f35083f3b40d)
- ascal `i_ce` is rising-edge-sensitive and follows the same 1-cycle pulse contract as `CE_PIXEL`. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/ascal.vhd:144 @ f35083f3b40d)
- ascal `format[1:0]` selects scaler output format: 00 = 16bpp 565, 01 = 24bpp, 10 = 32bpp (default 01 = 24bpp in sys_top). [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/ascal.vhd:229 @ f35083f3b40d)
- ascal `mode[4:0]` encodes `{!lowlat, filter_idx, 2'b00}` in `sys_top`; bit [3] is single-buffer/triple-buffer, bits [2:0] select filter (0=Nearest, 1=Bilinear, 2=SharpBilinear, 3=Bicubic, 4=Polyphase). [I] (archive/github/MiSTer-devel/Template_MiSTer/sys/ascal.vhd:78-92, sys/sys_top.v:791 @ f35083f3b40d)

video_freak contract
- `video_freak` SHOULD be placed AFTER `video_mixer` (or anywhere after the core's DE timing settles); it consumes `VGA_DE_IN` and produces a windowed `VGA_DE` plus `VIDEO_ARX/ARY` with bit [12] set when `SCALE != 0`. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/video_freak.sv:122,313-320 @ f35083f3b40d)

## 3. Ports / signals reference

### 3.1 `video_mixer.sv` (analog VGA mixer + sync regen)

```verilog
// archive/github/MiSTer-devel/Template_MiSTer/sys/video_mixer.sv:19-60 @ f35083f3b40d
module video_mixer
#(
    parameter LINE_LENGTH  = 768,
    parameter HALF_DEPTH   = 0,
    parameter GAMMA        = 0
)
(
    input            CLK_VIDEO,
    output reg       CE_PIXEL,
    input            ce_pix,
    input            scandoubler,
    input            hq2x,
    inout     [21:0] gamma_bus,
    input [DWIDTH:0] R, G, B,
    input            HSync, VSync, HBlank, VBlank,
    input            HDMI_FREEZE,
    output           freeze_sync,
    output reg [7:0] VGA_R, VGA_G, VGA_B,
    output reg       VGA_VS, VGA_HS, VGA_DE
);
```

| Signal | Dir | Width | Clock | Active | Meaning | Driven by | Drives |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `LINE_LENGTH` (param) | — | int | — | n/a | Active pixels per line for scandoubler buffer | core instantiation | `scandoubler LENGTH` |
| `HALF_DEPTH` (param) | — | int | — | n/a | 0=8bpp, 1=4bpp replicated to 8bpp at out | core instantiation | downstream width |
| `GAMMA` (param) | — | int | — | n/a | 0 = bypass, 1 = include `gamma_corr` | core instantiation | gamma_bus[21] |
| `CLK_VIDEO` | in | 1 | self | — | Pixel-domain clock | core | internal |
| `CE_PIXEL` | out | 1 | `CLK_VIDEO` | high pulse | Output CE (×2 when scandoubler, ×4 when hq2x, else passthrough) | mixer | core |
| `ce_pix` | in | 1 | `CLK_VIDEO` | high pulse | Input pixel CE | core | scandoubler / reg path |
| `scandoubler` | in | 1 | static | high | Engage scandoubler | core | scandoubler enable |
| `hq2x` | in | 1 | static | high | Use HQ2x instead of plain doubler | core | scandoubler `hq2x` |
| `gamma_bus` | inout | 22 | `clk_sys` (bit 20) | — | LUT write bus from `hps_io` | hps_io | gamma_corr |
| `R/G/B` | in | 4 or 8 | `CLK_VIDEO` | — | Core RGB (width = `HALF_DEPTH ? 4 : 8`) | core | gamma → scandoubler |
| `HSync/VSync` | in | 1 | `CLK_VIDEO` | positive | Sync from core | core | freezer/scandoubler |
| `HBlank/VBlank` | in | 1 | `CLK_VIDEO` | positive | Blanking from core | core | freezer/scandoubler |
| `HDMI_FREEZE` | in | 1 | `CLK_VIDEO` | high | Force analog RGB to 0 while freezer synthesizes sync | core | RGB mux + freezer |
| `freeze_sync` | out | 1 | `CLK_VIDEO` | toggle | Toggles each synthetic V-sync during freeze | freezer | optional |
| `VGA_R/G/B` | out | 8 | `CLK_VIDEO` | — | Mixed analog RGB | mixer | core's `VGA_R/G/B` |
| `VGA_HS/VS/DE` | out | 1 | `CLK_VIDEO` | DE high; HS/VS positive | Mixed sync/DE | mixer | core's `VGA_HS/VS/DE` |

### 3.2 `video_freezer.sv` (sync lock + freeze synth)

```verilog
// archive/github/MiSTer-devel/Template_MiSTer/sys/video_freezer.sv:21-37 @ f35083f3b40d
module video_freezer (
    input  clk,
    output sync,
    input  freeze,
    input  hs_in, vs_in, hbl_in, vbl_in,
    output hs_out, vs_out, hbl_out, vbl_out
);
```

| Signal | Dir | Width | Clock | Active | Meaning | Driven by | Drives |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `clk` | in | 1 | self | — | Pixel clock | `CLK_VIDEO` | counters |
| `freeze` | in | 1 | `clk` | high | Hold last measured period and emit synthetic sync | `HDMI_FREEZE` | sync_lock |
| `sync` | out | 1 | `clk` | toggle | Toggles each new V-sync during freeze | sync_lock | optional |
| `hs_in/vs_in/hbl_in/vbl_in` | in | 1 | `clk` | positive | Source sync/blanking | video_mixer | sync_lock |
| `hs_out/vs_out/hbl_out/vbl_out` | out | 1 | `clk` | positive | Passthrough or synthesized when `freeze=1` | sync_lock | gamma/scandoubler |

The `sync_lock #(WIDTH)` submodule (lines 80-143) measures `f_len`, `s_len`, `de_start`, `de_end` while not frozen and replays them while frozen. [I] (archive/github/MiSTer-devel/Template_MiSTer/sys/video_freezer.sv:80-143 @ f35083f3b40d)

### 3.3 `video_cleaner.sv` (polarity normalize + DE align)

```verilog
// archive/github/MiSTer-devel/Template_MiSTer/sys/video_cleaner.sv:12-47 @ f35083f3b40d
module video_cleaner (
    input            clk_vid, input ce_pix,
    input      [7:0] R, G, B,
    input            HSync, VSync, HBlank, VBlank,
    input            DE_in,
    input            interlace, f1,
    output reg [7:0] VGA_R, VGA_G, VGA_B,
    output reg       VGA_VS, VGA_HS,
    output           VGA_DE,
    output reg       HBlank_out, VBlank_out,
    output reg       DE_out
);
```

| Signal | Dir | Width | Clock | Active | Meaning | Driven by | Drives |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `clk_vid` | in | 1 | self | — | Pixel clock | `CLK_VIDEO` | internal |
| `ce_pix` | in | 1 | `clk_vid` | high pulse | Pixel CE | core | retiming |
| `R/G/B` | in | 8 | `clk_vid` | — | Source RGB | core | retimed |
| `HSync/VSync` | in | 1 | `clk_vid` | either | Source sync (`s_fix` auto-detects polarity) | core | inverter |
| `HBlank/VBlank` | in | 1 | `clk_vid` | positive | Blanking | core | DE align |
| `DE_in` | in | 1 | `clk_vid` | high | Optional DE input | core | retimed `DE_out` |
| `interlace`, `f1` | in | 1 | `clk_vid` | high | Interlace flags (alter VS/VBlank align) | core | branch select |
| `VGA_R/G/B/HS/VS` | out | 8/1/1 | `clk_vid` | positive | Cleaned RGB + positive sync | cleaner | downstream |
| `VGA_DE` | out | 1 | `clk_vid` | high | `~(HBlank_out \| VBlank_out)` | comb | downstream |
| `HBlank_out/VBlank_out` | out | 1 | `clk_vid` | high | DE-aligned blanking | cleaner | downstream |
| `DE_out` | out | 1 | `clk_vid` | high | DE retimed alongside RGB | cleaner | downstream |

### 3.4 `video_freak.sv` (crop / aspect / integer scale)

```verilog
// archive/github/MiSTer-devel/Template_MiSTer/sys/video_freak.sv:16-33 @ f35083f3b40d
module video_freak (
    input             CLK_VIDEO, CE_PIXEL, VGA_VS,
    input      [11:0] HDMI_WIDTH, HDMI_HEIGHT,
    output            VGA_DE,
    output reg [12:0] VIDEO_ARX, VIDEO_ARY,
    input             VGA_DE_IN,
    input      [11:0] ARX, ARY, CROP_SIZE,
    input       [4:0] CROP_OFF, // -16..+15
    input       [2:0] SCALE     // 0=normal, 1=V-int, 2..4=HV-int variants
);
```

| Signal | Dir | Width | Clock | Active | Meaning | Driven by | Drives |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `CLK_VIDEO`, `CE_PIXEL`, `VGA_VS` | in | 1 | self | high | Pixel domain + frame timing | core | counters |
| `HDMI_WIDTH/HEIGHT` | in | 12 | sys clock | — | Current HDMI active resolution | sys_top | integer-scale calc |
| `VGA_DE_IN` | in | 1 | `CLK_VIDEO` | high | Source DE | core / mixer | crop window |
| `ARX/ARY` | in | 12 | static | — | Source aspect ratio | core (`status`) | aspect calc |
| `CROP_SIZE` | in | 12 | static | — | Vertical crop target (0 = no crop) | core (`status`) | vsize calc |
| `CROP_OFF` | in | 5 | signed -16..+15 | — | Vertical crop offset | core (`status`) | voff calc |
| `SCALE` | in | 3 | static | — | Integer-scale mode | core (`status`) | `video_scale_int` |
| `VGA_DE` | out | 1 | `CLK_VIDEO` | high | DE masked by crop window | comb | core's `VGA_DE` |
| `VIDEO_ARX/ARY` | out | 13 | `CLK_VIDEO` | — | Final aspect or scaled-size (bit [12] set when integer-scaled) | scaler | core's `VIDEO_ARX/ARY` |

### 3.5 `scandoubler.v` (+ HQ2x integration)

```verilog
// archive/github/MiSTer-devel/Template_MiSTer/sys/scandoubler.v:22-47 @ f35083f3b40d
module scandoubler #(parameter LENGTH, parameter HALF_DEPTH) (
    input             clk_vid,
    input             hq2x,
    input             ce_pix,
    input             hs_in, vs_in, hb_in, vb_in,
    input  [DWIDTH:0] r_in, g_in, b_in,
    output            ce_pix_out,
    output reg        hs_out,
    output            vs_out, hb_out, vb_out,
    output [DWIDTH:0] r_out, g_out, b_out
);
```

| Signal | Dir | Width | Clock | Active | Meaning | Driven by | Drives |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `LENGTH` (param) | — | int | — | — | Line length in pixels for buffer sizing | parent | line RAM |
| `HALF_DEPTH` (param) | — | int | — | — | 0=8bpp, 1=4bpp per channel | parent | width math |
| `clk_vid` | in | 1 | self | — | Pixel clock (≥ 40 MHz, ≥ 4× ce_pix) | `CLK_VIDEO` | counters |
| `hq2x` | in | 1 | static | high | Use HQ2x instead of plain doubler | parent | output CE mux |
| `ce_pix` | in | 1 | `clk_vid` | high pulse | Input pixel CE | parent | edge detect |
| `hs_in/vs_in/hb_in/vb_in` | in | 1 | `clk_vid` | positive | Source sync/blank | parent | line state |
| `r_in/g_in/b_in` | in | 4 or 8 | `clk_vid` | — | Source RGB | parent | line buffer |
| `ce_pix_out` | out | 1 | `clk_vid` | high pulse | Output CE (×2 input, ×4 when hq2x) | scandoubler | parent |
| `hs_out/vs_out/hb_out/vb_out` | out | 1 | `clk_vid` | positive | Retimed sync/blank at 2× line rate | scandoubler | parent |
| `r_out/g_out/b_out` | out | 4 or 8 | `clk_vid` | — | Doubled-line RGB | scandoubler | parent |

### 3.6 `Hq2x` (instantiated by scandoubler)

```verilog
// archive/github/MiSTer-devel/Template_MiSTer/sys/hq2x.sv:13-28 @ f35083f3b40d
module Hq2x #(parameter LENGTH, parameter HALF_DEPTH) (
    input             clk,
    input             ce_in,
    input  [DWIDTH:0] inputpixel,
    input             mono, disable_hq2x,
    input             reset_frame, reset_line,
    input             ce_out,
    input       [1:0] read_y,
    input             hblank,
    output [DWIDTH:0] outpixel
);
```

| Signal | Dir | Width | Clock | Active | Meaning | Driven by | Drives |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `LENGTH`/`HALF_DEPTH` (params) | — | int | — | — | As scandoubler | parent | line RAM |
| `clk` | in | 1 | self | — | Pixel clock | `clk_vid` | internal |
| `ce_in/ce_out` | in | 1 | `clk` | high | 4× input/output CE | scandoubler | scheduler |
| `inputpixel` | in | 4 or 8×3 | `clk` | — | One source pixel | scandoubler | line buffer |
| `mono` | in | 1 | `clk` | high | Monochrome interpretation of HALF_DEPTH pixel | parent | h2rgb/rgb2h |
| `disable_hq2x` | in | 1 | `clk` | high | Pass through (no blend) | parent | blender mux |
| `reset_frame/reset_line` | in | 1 | `clk` | high | Frame/line restart | parent | offs/cyc |
| `read_y` | in | 2 | `clk` | — | Which of 4 doubled-line pixels to read | scandoubler | output buf |
| `hblank` | in | 1 | `clk` | high | Reset output read pointer | scandoubler | read_x |
| `outpixel` | out | 4 or 8×3 | `clk` | — | One output pixel | hq2x | scandoubler |

### 3.7 `gamma_corr.sv` (24-bit LUT, time-multiplexed)

```verilog
// archive/github/MiSTer-devel/Template_MiSTer/sys/gamma_corr.sv:1-20 @ f35083f3b40d
module gamma_corr (
    input             clk_sys, clk_vid, ce_pix,
    input             gamma_en, gamma_wr,
    input       [9:0] gamma_wr_addr,
    input       [7:0] gamma_value,
    input             HSync, VSync, HBlank, VBlank,
    input      [23:0] RGB_in,
    output reg        HSync_out, VSync_out, HBlank_out, VBlank_out,
    output reg [23:0] RGB_out
);
```

| Signal | Dir | Width | Clock | Active | Meaning | Driven by | Drives |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `clk_sys` | in | 1 | self | — | HPS-side write clock for LUT | `gamma_bus[20]` | LUT write port |
| `clk_vid` | in | 1 | self | — | Pixel-side read clock | `CLK_VIDEO` | LUT read port |
| `ce_pix` | in | 1 | `clk_vid` | high pulse | Pixel CE | parent | sequencer |
| `gamma_en` | in | 1 | `clk_sys` | high | Apply LUT (else passthrough) | `gamma_bus[19]` | output mux |
| `gamma_wr` | in | 1 | `clk_sys` | high | LUT write strobe | `gamma_bus[18]` | LUT write |
| `gamma_wr_addr` | in | 10 | `clk_sys` | — | LUT address (R/G/B in [9:8], index in [7:0]) | `gamma_bus[17:8]` | LUT addr |
| `gamma_value` | in | 8 | `clk_sys` | — | LUT data byte | `gamma_bus[7:0]` | LUT data |
| `HSync/VSync/HBlank/VBlank` | in | 1 | `clk_vid` | positive | Sync/blank passthrough | parent | delay regs |
| `RGB_in` | in | 24 | `clk_vid` | — | RGB888 input | parent | LUT index |
| `*_out` | out | 1 / 24 | `clk_vid` | positive | Aligned outputs | gamma_corr | parent |

### 3.8 `scanlines.v` (analog scanline darken)

```verilog
// archive/github/MiSTer-devel/Template_MiSTer/sys/scanlines.v:1-13 @ f35083f3b40d
module scanlines #(parameter v2=0) (
    input             clk,
    input       [1:0] scanlines,
    input      [23:0] din,
    input             hs_in, vs_in,
    input             de_in, ce_in,
    output reg [23:0] dout,
    output reg        hs_out, vs_out,
    output reg        de_out, ce_out
);
```

| Signal | Dir | Width | Clock | Active | Meaning | Driven by | Drives |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `v2` (param) | — | int | — | — | 1 = cycle through 0..N pattern per line, 0 = XOR alternation (sys_top uses 0) | parent | line counter |
| `clk` | in | 1 | self | — | Pixel clock | `clk_vid` | counters |
| `scanlines` | in | 2 | `clk` | — | 0=off, 1=25%, 2=50%, 3=75% darken | `VGA_SL` | scaling |
| `din` | in | 24 | `clk` | — | RGB888 input | OSD/mixer | scaled RGB |
| `hs_in/vs_in/de_in/ce_in` | in | 1 | `clk` | — | Sync/blank/CE | upstream | delay chain |
| `dout` | out | 24 | `clk` | — | Scanline-attenuated RGB | scanlines | OSD |
| `hs_out/vs_out/de_out/ce_out` | out | 1 | `clk` | — | 3-cycle delayed pass | scanlines | OSD |

### 3.9 `shadowmask.sv` (HDMI-side mask LUT)

```verilog
// archive/github/MiSTer-devel/Template_MiSTer/sys/shadowmask.sv:1-18 @ f35083f3b40d
module shadowmask (
    input             clk, clk_sys,
    input             cmd_wr,
    input      [15:0] cmd_in,
    input      [23:0] din,
    input             hs_in, vs_in, de_in,
    input             brd_in,
    input             enable,
    output reg [23:0] dout,
    output reg        hs_out, vs_out, de_out
);
```

| Signal | Dir | Width | Clock | Active | Meaning | Driven by | Drives |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `clk` | in | 1 | self | — | HDMI pixel clock | `clk_hdmi` | pixel pipe |
| `clk_sys` | in | 1 | self | — | HPS-side command clock | `clk_sys` | LUT write |
| `cmd_wr` | in | 1 | `clk_sys` | high pulse | Mask config command strobe | sys_top (h3E) | LUT/regs |
| `cmd_in` | in | 16 | `clk_sys` | — | Command word (opcode in [15:13]) | sys_top | LUT/regs |
| `din` | in | 24 | `clk` | — | HDMI RGB input | ascal | multiplier |
| `hs_in/vs_in/de_in` | in | 1 | `clk` | positive | Sync/DE | ascal | delay chain |
| `brd_in` | in | 1 | `clk` | high | Border/active flag from ascal | ascal | pattern reset |
| `enable` | in | 1 | `clk` | high | Master enable | `~LFB_EN` | LUT mux |
| `dout` | out | 24 | `clk` | — | Mask-modulated RGB | shadowmask | OSD |
| `hs_out/vs_out/de_out` | out | 1 | `clk` | positive | Delayed sync/DE | shadowmask | OSD |

### 3.10 `vga_out.sv` (RGB ↔ YPbPr)

```verilog
// archive/github/MiSTer-devel/Template_MiSTer/sys/vga_out.sv:1-19 @ f35083f3b40d
module vga_out (
    input         clk,
    input         ypbpr_en,
    input         hsync, vsync, csync, de,
    input  [23:0] din,
    output [23:0] dout,
    output reg    hsync_o, vsync_o, csync_o, de_o
);
```

| Signal | Dir | Width | Clock | Active | Meaning | Driven by | Drives |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `clk` | in | 1 | self | — | Pixel clock | `clk_vid` or `clk_hdmi` | matrix regs |
| `ypbpr_en` | in | 1 | `clk` | high | When 1, output `{Pr,Y,Pb}`; else RGB passthrough | sys_top (`ypbpr_en`) | output mux |
| `hsync/vsync/csync/de` | in | 1 | `clk` | positive | Sync from OSD output | OSD | delayed sync |
| `din` | in | 24 | `clk` | — | RGB888 input | OSD | matrix |
| `dout` | out | 24 | `clk` | — | RGB or `{Pr,Y,Pb}` | vga_out | analog DAC |
| `hsync_o/vsync_o/csync_o/de_o` | out | 1 | `clk` | positive | Aligned sync/DE | vga_out | analog DAC |

### 3.11 `yc_out.sv` (NTSC/PAL Luma+Chroma encoder)

```verilog
// archive/github/MiSTer-devel/Template_MiSTer/sys/yc_out.sv:28-48 @ f35083f3b40d
module yc_out (
    input         clk,
    input  [39:0] PHASE_INC,
    input         PAL_EN, CVBS,
    input  [16:0] COLORBURST_RANGE,
    input         hsync, vsync, csync, de,
    input  [23:0] din,
    output [23:0] dout,
    output reg    hsync_o, vsync_o, csync_o, de_o
);
```

| Signal | Dir | Width | Clock | Active | Meaning | Driven by | Drives |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `clk` | in | 1 | self | — | Sample clock for sub-carrier NCO | `clk_vid` | NCO |
| `PHASE_INC` | in | 40 | `clk` | — | Sub-carrier NCO phase increment | sys_top config (HPS) | NCO |
| `PAL_EN` | in | 1 | `clk` | high | PAL mode (phase flip every line) | sys_top config | NCO control |
| `CVBS` | in | 1 | `clk` | high | Composite mode (luma+chroma summed; C channel forced 0) | sys_top config | encoder |
| `COLORBURST_RANGE` | in | 17 | `clk` | — | Start/end sample count for the burst | sys_top config | burst gate |
| `hsync/vsync/csync/de` | in | 1 | `clk` | positive | Sync/DE | OSD output | delay chain |
| `din` | in | 24 | `clk` | — | RGB888 input | OSD output | matrix |
| `dout` | out | 24 | `clk` | — | `{C, Y, 8'd0}` (Chroma in [23:16], Luma in [15:8]) | yc_out | analog DAC |
| `hsync_o/vsync_o/csync_o/de_o` | out | 1 | `clk` | positive | Aligned sync/DE | yc_out | analog DAC |

### 3.12 `ascal.vhd` (HDMI scaler, DDR3 framebuffer)

```vhdl
-- archive/github/MiSTer-devel/Template_MiSTer/sys/ascal.vhd:134-257 @ f35083f3b40d
PORT (
    -- Input video (clock domain i_clk)
    i_r, i_g, i_b : IN  unsigned(7 DOWNTO 0);
    i_hs, i_vs, i_fl, i_de, i_ce : IN std_logic;
    i_clk : IN std_logic;
    -- Output video (clock domain o_clk)
    o_r, o_g, o_b : OUT unsigned(7 DOWNTO 0);
    o_hs, o_vs, o_de, o_vbl, o_brd : OUT std_logic;
    o_ce, o_clk : IN std_logic;
    o_border : IN unsigned(23 DOWNTO 0);
    -- Framebuffer mode (MISTER_FB)
    o_fb_ena : IN std_logic;
    o_fb_hsize, o_fb_vsize : IN natural;
    o_fb_format : IN unsigned(5 DOWNTO 0);
    o_fb_base : IN unsigned(31 DOWNTO 0);
    o_fb_stride : IN unsigned(13 DOWNTO 0);
    -- 8bpp palette (two write ports)
    pal1_clk, pal1_wr, pal_n, pal2_clk, pal2_wr : IN std_logic;
    pal1_dw : IN unsigned(47 DOWNTO 0); pal1_a : IN unsigned(6 DOWNTO 0);
    pal2_dw : IN unsigned(23 DOWNTO 0); pal2_a : IN unsigned(7 DOWNTO 0);
    pal1_dr : OUT unsigned(47 DOWNTO 0); pal2_dr : OUT unsigned(23 DOWNTO 0);
    -- Low-lag tuning
    o_lltune : OUT unsigned(15 DOWNTO 0);
    -- Window / output timing
    iauto : IN std_logic;
    himin, himax, vimin, vimax : IN natural;
    i_hdmax, i_vdmax : OUT natural;
    run, freeze : IN std_logic;
    mode : IN unsigned(4 DOWNTO 0);
    bob_deint : IN std_logic;
    htotal, hsstart, hsend, hdisp, hmin, hmax : IN natural;
    vtotal, vsstart, vsend, vdisp, vmin, vmax : IN natural;
    vrr : IN std_logic; vrrmax : IN natural; swblack : IN std_logic;
    format : IN unsigned(1 DOWNTO 0);
    -- Polyphase coefficient writes
    poly_clk : IN std_logic; poly_dw : IN unsigned(9 DOWNTO 0);
    poly_a : IN unsigned(FRAC+3 DOWNTO 0); poly_wr : IN std_logic;
    -- Avalon master (DDR3 framebuffer)
    avl_clk, avl_waitrequest, avl_readdatavalid : IN std_logic;
    avl_readdata : IN std_logic_vector(N_DW-1 DOWNTO 0);
    avl_burstcount : OUT std_logic_vector(7 DOWNTO 0);
    avl_writedata : OUT std_logic_vector(N_DW-1 DOWNTO 0);
    avl_address : OUT std_logic_vector(N_AW-1 DOWNTO 0);
    avl_write, avl_read : OUT std_logic;
    avl_byteenable : OUT std_logic_vector(N_DW/8-1 DOWNTO 0);
    reset_na : IN std_logic
);
```

Key generics (with contract impact for cores):

| Generic | sys_top value | Meaning |
| --- | --- | --- |
| `RAMBASE` | `32'h2000_0000` | DDR3 base for ascal framebuffer pool |
| `RAMSIZE` | `0x00800000` (8 MB) or `0x00200000` (2 MB w/ `MISTER_SMALL_VBUF`) | Per-buffer; ×3 for triple-buffer |
| `INTER` | `true` | Autodetect interlaced + deinterlace |
| `PALETTE` / `PALETTE2` | `true` / conditional | Enable 8bpp framebuffer palette ports |
| `ADAPTIVE` | `true` (unless `MISTER_DISABLE_ADAPTIVE`) | Adaptive polyphase filter |
| `DOWNSCALE_NN` | `false` (or `true` w/ `MISTER_DOWNSCALE_NN`) | Nearest-neighbor downscale |
| `FRAC` | 8 | Polyphase sub-pixel bits |
| `OHRES` | 2304 | Max output horizontal resolution (line buffer sizing) |
| `IHRES` | 2048 | Max input horizontal resolution (line buffer sizing) |
| `N_DW` | 128 | Avalon data bus width |
| `N_AW` | 28 | Avalon address bus width |
| `N_BURST` | 256 (2048 in `MENU_CORE`) | DDR burst size (bytes) |

ascal `mode[4:0]` decomposition (sys_top usage): `{!lowlat, LFB_EN ? LFB_FLT : |scaler_flt, 2'b00}` — bit [4] selects single vs triple buffer; bits [3:0] select interpolation. [I] (archive/github/MiSTer-devel/Template_MiSTer/sys/sys_top.v:791 @ f35083f3b40d)

### 3.13 `arcade_video.v` (wrapper around `video_mixer`)

```verilog
// archive/github/MiSTer-devel/Template_MiSTer/sys/arcade_video.v:29-53 @ f35083f3b40d
module arcade_video #(parameter WIDTH=320, DW=8, GAMMA=1) (
    input         clk_video, ce_pix,
    input[DW-1:0] RGB_in,
    input         HBlank, VBlank, HSync, VSync,
    output        CLK_VIDEO, CE_PIXEL,
    output  [7:0] VGA_R, VGA_G, VGA_B,
    output        VGA_HS, VGA_VS, VGA_DE,
    output  [1:0] VGA_SL,
    input   [2:0] fx,
    input         forced_scandoubler,
    inout  [21:0] gamma_bus
);
```

| Signal | Dir | Width | Clock | Active | Meaning | Driven by | Drives |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `WIDTH` (param) | — | int | — | — | Active pixel width (sets `LINE_LENGTH=WIDTH+4`) | core | mixer |
| `DW` (param) | — | int | — | — | Packed RGB width (6/8/9/12/18/24); auto-expand to 8-bit/channel | core | RGB mapper |
| `GAMMA` (param) | — | int | — | — | Engage `gamma_corr` | core | mixer |
| `clk_video/ce_pix` | in | 1 | self / `clk_video` | high | Core pixel domain (≥ 4× `ce_pix`, > 40 MHz) | core | mixer |
| `RGB_in` | in | `DW` | `clk_video` | — | Packed RGB | core | RGB expand |
| `HBlank/VBlank/HSync/VSync` | in | 1 | `clk_video` | positive | Sync/blank | core | mixer |
| `fx[2:0]` | in | 3 | static | — | 0=off, 1=HQ2x, 2..4=scandoubler+scanline 25/50/75% | core (`status`) | mixer `hq2x` + `VGA_SL` |
| `forced_scandoubler` | in | 1 | static | high | Force scandoubler (from `hps_io`) | core | mixer |
| `gamma_bus` | inout | 22 | mixed | — | LUT bus | hps_io | gamma_corr |
| `CLK_VIDEO/CE_PIXEL/VGA_*` | out | as above | `CLK_VIDEO` | — | Mixed emu-boundary video | mixer | core's emu outputs |

`screen_rotate` (same file, lines 168-329) is a DDR3 framebuffer writer used for vertical arcade games when HDMI rotation is desired; it writes raw `{B,G,R}` to DDR3 at `MEM_BASE=7'b0010010` and exposes `FB_*` ports — covered by the `MISTER_FB` framebuffer flow. [V] (archive/github/MiSTer-devel/Template_MiSTer/sys/arcade_video.v:168-329 @ f35083f3b40d)

## 4. Sequencing & timing

### 4.1 video_mixer internal pipeline

```
ce_pix ─────────┐
                ▼
[freezer] hs/vs/hb/vb passthrough OR sync-lock synth when HDMI_FREEZE=1
                │
                ▼
[gamma_corr]  (if GAMMA=1) — time-multiplexed 3-color LUT, +1 ce_pix latency
                │
                ▼
[scandoubler] (if scandoubler=1) — measures line len, emits ce_x2 or ce_x4
                │  ┌── Hq2x (if hq2x=1) — 9-cell pattern LUT, 4-cycle pipeline
                │  │
                ▼  ▼
        rt/gt/bt = scandoubler ? sd : gamma
        CE_PIXEL  = scandoubler ? ce_pix_sd
                  : fs_osc ? (~old_ce & ce_pix)  // edge of source CE
                  : ce_pix
                │
                ▼
[reg @CLK_VIDEO, if(CE_PIXEL)] VGA_R/G/B/HS/VS/DE
```

(archive/github/MiSTer-devel/Template_MiSTer/sys/video_mixer.sv:67-218 @ f35083f3b40d)

### 4.2 video_freak aspect-resize cycle

```
on (VGA_VS rising, CE_PIXEL):
   vtot ← vcpt        // measure source line count
   vcrop ← (CROP_SIZE >= vcpt) ? 0 : CROP_SIZE

each subsequent CE_PIXEL during active:
   hcpt++ on VGA_DE_IN
   vcpt++ on VGA_DE_IN falling edge
   if (vcpt == 0) hsize ← hcpt   // measure source line width

multi-cycle math (vcalc state, sys_umul / sys_udiv):
   ARXG ← ARX × vtot
   ARYG ← ARY × vcrop
   shift left until top bit set
   arxo ← ARXG[23:12]
   aryo ← ARYG[23:12]

video_scale_int:
   div HDMI_HEIGHT / vsize  → integer vertical factor
   mul vsize × factor       → oheight
   choose narrow/wide horizontal integer width based on SCALE mode
   VIDEO_ARX ← {1'b1, computed_width}   // bit [12] set = scaled size
   VIDEO_ARY ← {1'b1, oheight}
```

The math runs once per frame after vsync; output ARX/ARY is stable through the active frame. (archive/github/MiSTer-devel/Template_MiSTer/sys/video_freak.sv:46-138, 173-322 @ f35083f3b40d)

### 4.3 Scandoubler line cadence

The scandoubler measures `pix_len` between consecutive `ce_pix` rising edges, then emits `ce_x4i` at three offsets within each measured pixel period so a single source line becomes two output lines (or four logical phases of the HQ2x pixel grid). `clk_vid > 40 MHz` is mandatory because `pixsz4 = pix_len >> 2` collapses to 0/1 otherwise. (archive/github/MiSTer-devel/Template_MiSTer/sys/scandoubler.v:51-90 @ f35083f3b40d)

### 4.4 ascal clock-domain crossing

```
i_clk (= clk_ihdmi = clk_vid)      o_clk (= clk_hdmi)
   |                                   |
   i_ce edge → input pipeline          o_ce ← scaler_out (paced by HDMI)
   |                                   |
   write RGB into line buffer          read filtered RGB from line buffer
   |  ↘                                |  ↗
   |   write framebuffer (Avalon)      |  read framebuffer (Avalon)
   |       on avl_clk                  |
   |                                   |
   detect i_vs → start new frame       emit o_vs, o_hs, o_de
   produce i_hdmax, i_vdmax            consume htotal, hsstart, hsend,
                                        hdisp, hmin, hmax, vtotal, ...
```

The Avalon write port runs at `avl_clk` (DDR3 controller clock); ascal arbitrates writes from `i_clk` and reads to `o_clk` through internal FIFOs. (archive/github/MiSTer-devel/Template_MiSTer/sys/ascal.vhd:32-38 @ f35083f3b40d)

## 5. Minimal working pattern

### 5.1 Arcade wrapper (arcade_video around video_mixer)

```verilog
// archive/github/MiSTer-devel/Template_MiSTer/sys/arcade_video.v:118-143 @ f35083f3b40d
video_mixer #(.LINE_LENGTH(WIDTH+4), .HALF_DEPTH(DW!=24), .GAMMA(GAMMA)) video_mixer
(
    .CLK_VIDEO(CLK_VIDEO),
    .ce_pix(CE),
    .CE_PIXEL(CE_PIXEL),

    .scandoubler(scandoubler),
    .hq2x(fx==1),
    .gamma_bus(gamma_bus),

    .R((DW!=24) ? R[7:4] : R),
    .G((DW!=24) ? G[7:4] : G),
    .B((DW!=24) ? B[7:4] : B),

    .HSync (HS),
    .VSync (VS),
    .HBlank(HBL),
    .VBlank(VBL),

    .VGA_R(VGA_R),
    .VGA_G(VGA_G),
    .VGA_B(VGA_B),
    .VGA_VS(VGA_VS),
    .VGA_HS(VGA_HS),
    .VGA_DE(VGA_DE)
);
```

```verilog
// archive/github/MiSTer-devel/Template_MiSTer/sys/arcade_video.v:114-117 @ f35083f3b40d
assign VGA_SL  = sl[1:0];
wire [2:0] sl = fx ? fx - 1'd1 : 3'd0;
wire scandoubler = fx || forced_scandoubler;
```

Notes:
- `fx[2:0]` (typically from CONF_STR `O[5:3]`) maps to `{hq2x, sl}`: `fx=1` engages HQ2x; `fx=2..4` engage scandoubler with scanline weight 1/2/3 (25/50/75%).
- `arcade_video` sync-fixes `HSync/VSync` (lines 57-77) and re-samples blanking on the rising `ce_pix` edge, so video_mixer's input is always positive-polarity and 1-cycle CE-aligned.

### 5.2 video_freak integration (cropping + integer scale)

Pattern from MkDocs documentation:
```verilog
// archive/github/MiSTer-devel/MkDocs_MiSTer/docs/developer/video_freak.md:5-23 @ 9033bd292fdc
video_freak video_freak (
    .CLK_VIDEO(CLK_VIDEO), .CE_PIXEL(CE_PIXEL), .VGA_VS(VGA_VS),
    .HDMI_WIDTH(HDMI_WIDTH), .HDMI_HEIGHT(HDMI_HEIGHT),
    .VGA_DE(VGA_DE),         // freak masks DE to crop window
    .VIDEO_ARX(VIDEO_ARX), .VIDEO_ARY(VIDEO_ARY),
    .VGA_DE_IN(vga_de_mixer),  // raw DE from video_mixer
    .ARX(status_arx), .ARY(status_ary),
    .CROP_SIZE(status_crop_lines), .CROP_OFF(status_crop_off),
    .SCALE(status_scale_mode)
);
```

Notes:
- `video_freak` is placed AFTER `video_mixer` (or anywhere after the core's DE timing settles). Its `VGA_DE_IN` is the mixer's `VGA_DE`; its `VGA_DE` is the value forwarded out the emu boundary.
- `VIDEO_ARX/ARY` outputs from `video_freak` always have bit [12] set when `SCALE != 0` (integer mode).

## 6. Common variations across cores

Direct cross-core comparison is `[deferred — reference cores not fetched]`. Framework-implied variations:

- `video_mixer` with `HALF_DEPTH=0, GAMMA=0`: 8-bit-per-channel passthrough, scandoubler/hq2x only. [V] (archive/github/MiSTer-devel/Template_MiSTer/sys/video_mixer.sv:62-64 @ f35083f3b40d)
- `video_mixer` with `HALF_DEPTH=1, GAMMA=1`: 4-bit input expanded internally, gamma LUT engaged; upstream RGB stays at 12-bit total. Common for 8-bit / early-16-bit consoles whose native palette is ≤ 5 bpp. [V] (archive/github/MiSTer-devel/Template_MiSTer/sys/video_mixer.sv:91-101 @ f35083f3b40d)
- `arcade_video` wrapper: collapses `video_mixer` + RGB expansion + `fx`-to-`{hq2x,sl}` mapping into a single instance for arcade cores with packed RGB (`DW=6/8/9/12/18/24`). [V] (archive/github/MiSTer-devel/Template_MiSTer/sys/arcade_video.v:29-145 @ f35083f3b40d)
- `screen_rotate` framebuffer rotation: writes RGB into DDR3 at `MEM_BASE`, exposes `FB_*` ports so ascal reads back rotated. Bypasses the `i_r/g/b` HDMI path entirely. Used for vertical arcade games. [V] (archive/github/MiSTer-devel/Template_MiSTer/sys/arcade_video.v:168-329 @ f35083f3b40d)
- ascal `mode[4]` direct vs triple buffer: `lowlat=1` selects direct single-buffer (lower latency, possible tearing); `lowlat=0` selects triple-buffer (no tearing, +1 frame latency). sys_top reflects user choice. [V] (archive/github/MiSTer-devel/Template_MiSTer/sys/sys_top.v:329,791 @ f35083f3b40d)
- `MISTER_SMALL_VBUF`: reduces per-buffer DDR3 allocation from 8 MB to 2 MB. Lower max output resolution but frees DDR3. [V] (archive/github/MiSTer-devel/Template_MiSTer/sys/sys_top.v:717-721 @ f35083f3b40d)
- `MISTER_DISABLE_ADAPTIVE`: removes adaptive polyphase filter; smaller LUT, fewer features. [V] (archive/github/MiSTer-devel/Template_MiSTer/sys/sys_top.v:729-731 @ f35083f3b40d)
- `MISTER_DOWNSCALE_NN`: forces nearest-neighbor downscale instead of bilinear. [V] (archive/github/MiSTer-devel/Template_MiSTer/sys/sys_top.v:732-734 @ f35083f3b40d)
- YC composite/S-Video output: `yc_out.sv` encodes OSD-mixed RGB into NTSC/PAL luma+chroma at the analog DAC, selected by `yc_en` (HPS-side config). Independent of HDMI. [V] (archive/github/MiSTer-devel/Template_MiSTer/sys/yc_out.sv:28-232, sys/sys_top.v:1435-1452 @ f35083f3b40d)
- Analog scanlines weight: `VGA_SL[1:0]` from `status` selects 0/25/50/75% darken; framework `scanlines` module is the only consumer. [V] (archive/github/MiSTer-devel/Template_MiSTer/sys/sys_top.v:1383-1399 @ f35083f3b40d)
- HDMI shadow mask: framework-side, configured by HPS command 0x3E (`sys_top.v:503`); the core only sees it as a static pipeline stage. Disabled when `LFB_EN` is asserted. [V] (archive/github/MiSTer-devel/Template_MiSTer/sys/sys_top.v:1159-1178 @ f35083f3b40d)
- Per-core cross-comparison (NES, SNES, PSX, ao486 etc.) — `[deferred — reference cores not fetched]`.

## 7. Anti-patterns

### A.1 CLK_VIDEO under 40 MHz feeding scandoubler / hq2x

- **Symptom:** Black bars between scandoubled lines; HQ2x produces garbled scaled pixels; or scandoubler passes through source unchanged.
- **Cause:** `scandoubler.v` computes `pixsz4 = pix_len >> 2` and asserts `ce_x4i` at offsets `pixsz4`, `pixsz2`, `pixsz2+pixsz4`. With `clk_vid < 4×ce_pix`, `pixsz` is 0/1/2 and the 4× cadence collapses. Framework documentation explicitly requires > 40 MHz.
- **Fix:** Add a PLL output that runs `CLK_VIDEO` at a multiple of `ce_pix × 4` and ≥ 40 MHz. For 5–6 MHz pixel clocks pick `clk_video = 48 MHz` and gate with `CE_PIXEL`. For a native 25 MHz pixel core, drive `CLK_VIDEO = 50 MHz` and `CE_PIXEL = 1` (or alternate).
- **Citation:** archive/github/MiSTer-devel/Template_MiSTer/sys/scandoubler.v:65-90 @ f35083f3b40d; archive/github/MiSTer-devel/MkDocs_MiSTer/docs/developer/emu.md:53 @ 9033bd292fdc.

### A.2 video_freak placed before video_mixer

- **Symptom:** Crop window does not match HDMI; ARX/ARY math sees scandoubled line counts; integer-scale modes produce wrong output sizes.
- **Cause:** `video_freak` measures `hsize`/`vsize` from `VGA_DE_IN`, which it expects to be the source DE before the scandoubler doubles it. Wiring `video_freak` before `video_mixer` doesn't break here, but wiring scandoubled DE into `VGA_DE_IN` does.
- **Fix:** Feed `video_freak.VGA_DE_IN` from the pre-scandoubler DE (or from `video_mixer.VGA_DE`, since that gates per `CE_PIXEL`). Read the `video_freak` per-frame counters with the same `CE_PIXEL` rate that the upstream mixer emits.
- **Citation:** archive/github/MiSTer-devel/Template_MiSTer/sys/video_freak.sv:55-71, 122 @ f35083f3b40d.

### A.3 Wiring gamma_bus without reading bit [21]

- **Symptom:** `hps_io` silently disables OSD gamma options; gamma menu does nothing.
- **Cause:** `video_mixer.sv:109,133` drives `gamma_bus[21]=1` only when `GAMMA=1`. `hps_io` uses this bit as the presence ack. If a core instantiates `video_mixer` with `GAMMA=0` but the OSD CONF_STR still advertises gamma options, the OSD will accept the user input but no LUT writes flow through.
- **Fix:** Set `GAMMA=1` when instantiating `video_mixer`/`arcade_video` if you advertise gamma in CONF_STR. Conversely, drop the gamma CONF_STR options when `GAMMA=0`.
- **Citation:** archive/github/MiSTer-devel/Template_MiSTer/sys/video_mixer.sv:108-137 @ f35083f3b40d.

### A.4 Assuming sys_top is a simple HDMI mux

- **Symptom:** Changing analog sync polarity "fixes" analog but jitters HDMI OSD; or expectation that the analog 6-bit truncation also applies to HDMI.
- **Cause:** ascal is a deep reformatter (clock-cross to `clk_hdmi`, scale, deinterlace, polyphase, DDR3 framebuffer). Analog and HDMI are independent sinks fed by the same `VGA_*` source.
- **Fix:** Drive emu `VGA_HS`/`VGA_VS` positive-polarity always. Test both sinks independently.
- **Citation:** archive/github/MiSTer-devel/Template_MiSTer/sys/sys_top.v:714-820 (ascal instance), 1521-1525 (analog DAC inversion) @ f35083f3b40d.

## 8. Verification

- **Scandoubler smoke test:** With `forced_scandoubler=1` in `MiSTer.ini`, analog output must show 31 kHz; without, must show 15 kHz. HQ2x option must change line-doubling visibly (sharp edges vs naive replication).
- **Gamma test:** Open OSD, change gamma value; confirm the RGB output curve changes by sampling a known test pattern. With `GAMMA=0` the option should not be advertised.
- **Aspect-ratio (video_freak) test:** With `SCALE=2`/`3`/`4` (integer modes), confirm `VIDEO_ARX[12]=1` and `VIDEO_ARY[12]=1`. With `SCALE=0`, both bits [12] should be 0.
- **Shadow mask test:** Apply a shadow-mask preset via OSD; confirm HDMI output gains the mask pattern, but analog VGA output is unaffected. (Mask is HDMI-side only.)
- **YC output test:** Enable `yc_en` and `pal_en` in HPS config; confirm the analog jack emits PAL composite/S-Video instead of RGB.
- **MISTER_FB framebuffer test:** Bring `FB_EN=1`, write a known RGB pattern into DDR3 at `FB_BASE`, set `FB_FORMAT`/`FB_STRIDE`/`FB_WIDTH`/`FB_HEIGHT` correctly, and confirm the HDMI image matches without driving any `VGA_R/G/B`.

## 9. Provenance footer

- archive/github/MiSTer-devel/Template_MiSTer/sys/video_mixer.sv @ f35083f3b40d — used for §2 (gamma_bus, parameters), §3.1, §4.1, §6, §7 (A.3)
- archive/github/MiSTer-devel/Template_MiSTer/sys/video_freezer.sv @ f35083f3b40d — used for §3.2
- archive/github/MiSTer-devel/Template_MiSTer/sys/video_cleaner.sv @ f35083f3b40d — used for §3.3
- archive/github/MiSTer-devel/Template_MiSTer/sys/video_freak.sv @ f35083f3b40d — used for §2 (placement rule), §3.4, §4.2, §5.2, §7 (A.2)
- archive/github/MiSTer-devel/Template_MiSTer/sys/scandoubler.v @ f35083f3b40d — used for §2 (parameters), §3.5, §4.3, §7 (A.1)
- archive/github/MiSTer-devel/Template_MiSTer/sys/hq2x.sv @ f35083f3b40d — used for §3.6
- archive/github/MiSTer-devel/Template_MiSTer/sys/gamma_corr.sv @ f35083f3b40d — used for §2 (bus encoding), §3.7, §7 (A.3)
- archive/github/MiSTer-devel/Template_MiSTer/sys/scanlines.v @ f35083f3b40d — used for §3.8, §6
- archive/github/MiSTer-devel/Template_MiSTer/sys/shadowmask.sv @ f35083f3b40d — used for §3.9, §6
- archive/github/MiSTer-devel/Template_MiSTer/sys/vga_out.sv @ f35083f3b40d — used for §3.10
- archive/github/MiSTer-devel/Template_MiSTer/sys/yc_out.sv @ f35083f3b40d — used for §3.11, §6
- archive/github/MiSTer-devel/Template_MiSTer/sys/ascal.vhd @ f35083f3b40d — used for §2 (clock domains, mode encoding, format), §3.12, §4.4
- archive/github/MiSTer-devel/Template_MiSTer/sys/arcade_video.v @ f35083f3b40d — used for §2 (DW handling, clock requirement), §3.13, §5.1, §6 (screen_rotate)
- archive/github/MiSTer-devel/Template_MiSTer/sys/sys_top.v @ f35083f3b40d — used for §2 (chain order), §3.9 (cmd_wr 0x3E), §3.12 (ascal generics in context), §4.4, §6, §7 (A.4)
- archive/github/MiSTer-devel/MkDocs_MiSTer/docs/developer/arcade_video.md @ 9033bd292fdc — used for §2 (clk_video requirement), §3.13 (rationale)
- archive/github/MiSTer-devel/MkDocs_MiSTer/docs/developer/video_freak.md @ 9033bd292fdc — used for §5.2 (instantiation pattern)
- archive/github/MiSTer-devel/MkDocs_MiSTer/docs/developer/video_mixer.md @ 9033bd292fdc — used for §3.1 (port descriptions corroboration)
- archive/github/MiSTer-devel/MkDocs_MiSTer/docs/developer/emu.md @ 9033bd292fdc — used for §7 (A.1: 40 MHz scandoubler clock requirement)
