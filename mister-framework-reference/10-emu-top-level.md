# Emu Top-Level Module

> Bundle version: 2026-05-18
> Pinned commits: `Template_MiSTer` @ `f35083f3b40d`, `MkDocs_MiSTer` @ `9033bd292fdc`
> Load with: [11-conf-str.md](11-conf-str.md), [12-clocks-resets-plls.md](12-clocks-resets-plls.md), [20-hps-io-overview.md](20-hps-io-overview.md)
> Status mix: [C] [V] [O] [I]

## 1. Purpose & one-line summary

`emu` is the user core's top-level module; its port list is fixed by the framework via `\`include "sys/emu_ports.vh"`. `sys_top.v` instantiates `emu`, hands it `CLK_50M`, `RESET`, the `HPS_BUS` mux, and board-side I/O, and consumes the core's video/audio/memory outputs. A core author writes `<core>.sv` containing `module emu` plus `hps_io`, `pll`, and game logic; the framework owns everything outside it.

## 2. The contract (must-obey)

- The user core's top module **must** be named `emu` and **must** start its port list with `\`include "sys/emu_ports.vh"`. [C] (archive/github/MiSTer-devel/Template_MiSTer/Template.sv:19-22 @ f35083f3b40d)
- `sys_top.v` is the Quartus top-level entity; `emu` is instantiated inside it. [C] (archive/github/MiSTer-devel/Template_MiSTer/Template.qsf:11 @ f35083f3b40d)
- `HPS_BUS` is a 46-bit `inout` and **must** be wired through unchanged to `hps_io`. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/emu_ports.vh:8-9 @ f35083f3b40d)
- The core drives back **only** three slices of `HPS_BUS`: `[37]=ioctl_wait`, `[36]=clk_sys`, `[15:0]=io_dout`; all other bits are consumed. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:184-194 @ f35083f3b40d)
- `RESET` is asynchronous and active-high from `sys_top.v` (sourced from `sysmem_lite.reset_out`, which is driven by HPS `gp_out[31:30]` and the cold-reset button). [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/sys_top.v:601-612 @ f35083f3b40d)
- The PLL module **must** be named `pll` and the instance **must** also be named `pll`; `sys/sys_top.sdc` searches `*|pll|pll_inst|*` to constrain clocks. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/sys_top.sdc:14 @ f35083f3b40d)
- The PLL must live in `rtl/` (not `sys/`) so framework updates do not clobber it. [C] (archive/github/MiSTer-devel/MkDocs_MiSTer/docs/developer/emu.md:13-15 @ 9033bd292fdc)
- `CLK_VIDEO` and `CE_PIXEL` together pace pixels; `CE_PIXEL` must be derived from `CLK_VIDEO`. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/emu_ports.vh:11-16 @ f35083f3b40d)
- `VGA_DE` is the conventional `~(VBlank | HBlank)`; the scaler uses it as the active-pixel window. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/emu_ports.vh:28 @ f35083f3b40d)
- `CLK_VIDEO` must be greater than 40 MHz for all video features to work. [C] (archive/github/MiSTer-devel/MkDocs_MiSTer/docs/developer/emu.md:53 @ 9033bd292fdc)
- If `VIDEO_ARX[12]` or `VIDEO_ARY[12]` is set, `[11:0]` is interpreted as a scaled pixel size, otherwise as an aspect-ratio numerator/denominator. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/emu_ports.vh:18-21 @ f35083f3b40d)
- `CLK_AUDIO` is a framework-provided 24.576 MHz clock; the core consumes it. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/emu_ports.vh:82 @ f35083f3b40d)
- `AUDIO_S=1` declares `AUDIO_L`/`AUDIO_R` as signed; `AUDIO_S=0` declares unsigned. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/emu_ports.vh:82-86 @ f35083f3b40d)
- `AUDIO_MIX[1:0]` selects 0/25%/50%/100% L↔R cross-mixing. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/emu_ports.vh:86 @ f35083f3b40d)
- `USER_OUT` is open-drain; to read `USER_IN[n]` the core **must** drive `USER_OUT[n]=1`. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/emu_ports.vh:145-151 @ f35083f3b40d)
- `LED_POWER[1]`/`LED_DISK[1]=0` lets the system OR its own status onto the LED; `=1` puts the core in sole control. Supplying `2'b00` is the "let the system control" hint. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/emu_ports.vh:71-75 @ f35083f3b40d)
- `BUTTONS[1]=user-button-press`, `BUTTONS[0]=osd-button-press`, both active-high simulated button signals; sys_top ORs them onto the real buttons. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/emu_ports.vh:77-80 @ f35083f3b40d; archive/github/MiSTer-devel/Template_MiSTer/sys/sys_top.v:234 @ f35083f3b40d)
- `OSD_STATUS` is high while the framework OSD is open; cores use it to pause / trigger autosave. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/emu_ports.vh:153 @ f35083f3b40d; archive/github/MiSTer-devel/MkDocs_MiSTer/docs/developer/emu.md:296-302 @ 9033bd292fdc)
- A core that does not use DDRAM **must** tie all DDRAM outputs to `'0` (not `Z`); DDRAM_CLK, DDRAM_BURSTCNT, DDRAM_ADDR, DDRAM_DIN, DDRAM_BE, DDRAM_RD, DDRAM_WE are sourced into the on-chip f2h_sdram bridge. [C] (archive/github/MiSTer-devel/Template_MiSTer/Template.sv:31 @ f35083f3b40d)
- A core that does not use SDRAM **must** tie all SDRAM signals to `'Z`; they go to physical pins on the SDRAM board. [C] (archive/github/MiSTer-devel/Template_MiSTer/Template.sv:30 @ f35083f3b40d)
- `ADC_BUS` is a 4-bit `inout` to an external ADC; cores not using it must drive `'Z`. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/emu_ports.vh:89 @ f35083f3b40d; archive/github/MiSTer-devel/Template_MiSTer/Template.sv:26 @ f35083f3b40d)
- `USER_OUT` defaults to `'1` (all open-drain off / inputs released) when unused. [O] (archive/github/MiSTer-devel/Template_MiSTer/Template.sv:27 @ f35083f3b40d)
- Under `MISTER_DUAL_SDRAM`, secondary SDRAM signals **must** be set to `Z` "ASAP" when `SDRAM2_EN=0`. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/emu_ports.vh:125-127 @ f35083f3b40d)
- DDRAM_BUSY high in any cycle **rejects** a request that cycle; the core may hold RD/WE asserted until BUSY drops. [C] (archive/github/MiSTer-devel/MkDocs_MiSTer/docs/developer/emu.md:208-212 @ 9033bd292fdc)
- The reset-into-core convention is `wire reset = RESET | status[0] | buttons[1];`. [V] (archive/github/MiSTer-devel/MkDocs_MiSTer/docs/developer/emu.md:36-38 @ 9033bd292fdc)
- `CONF_STR` bit `O[0]`/`R[0]`/`T[0]` is conventionally reserved as "Soft Reset". [V] (archive/github/MiSTer-devel/MkDocs_MiSTer/docs/developer/emu.md:34 @ 9033bd292fdc)
- All framework ports use Verilog "input"/"output" direction from `emu`'s perspective; e.g. `output CLK_VIDEO` means the core supplies it to `sys_top`. [I] (archive/github/MiSTer-devel/Template_MiSTer/sys/emu_ports.vh:1-154 @ f35083f3b40d)

## 3. Ports / signals reference

### 3.1 The `\`include` line

```verilog
// archive/github/MiSTer-devel/Template_MiSTer/Template.sv:19-22 @ f35083f3b40d
module emu
(
	`include "sys/emu_ports.vh"
);
```

### 3.2 Verbatim port list (excerpt — unconditional half)

```verilog
// archive/github/MiSTer-devel/Template_MiSTer/sys/emu_ports.vh:1-40 @ f35083f3b40d
//Master input clock
input         CLK_50M,

//Async reset from top-level module.
//Can be used as initial reset.
input         RESET,

//Must be passed to hps_io module
inout  [45:0] HPS_BUS,

//Base video clock. Usually equals to CLK_SYS.
output        CLK_VIDEO,

//Multiple resolutions are supported using different CE_PIXEL rates.
//Must be based on CLK_VIDEO
output        CE_PIXEL,

//Video aspect ratio for HDMI. Most retro systems have ratio 4:3.
//if VIDEO_ARX[12] or VIDEO_ARY[12] is set then [11:0] contains scaled size instead of aspect ratio.
output [12:0] VIDEO_ARX,
output [12:0] VIDEO_ARY,

output  [7:0] VGA_R,
output  [7:0] VGA_G,
output  [7:0] VGA_B,
output        VGA_HS,
output        VGA_VS,
output        VGA_DE,    // = ~(VBlank | HBlank)
output        VGA_F1,
output [1:0]  VGA_SL,
output        VGA_SCALER, // Force VGA scaler
output        VGA_DISABLE, // analog out is off

input  [11:0] HDMI_WIDTH,
input  [11:0] HDMI_HEIGHT,
output        HDMI_FREEZE,
output        HDMI_BLACKOUT,
output        HDMI_BOB_DEINT,
```

### 3.3 Full signal table

Direction is from the core's perspective (input = into emu). "Clock" is the clock under which the signal is sampled/launched (best-known from the framework wiring; "—" = combinational or pin-level). Active level uses H/L; "n/a" for buses. "Driven by" = ultimate source upstream of `sys_top`'s wiring; "Drives" = downstream sink.

| Signal | Dir | Width | Clock | Active | Meaning | Driven by | Drives |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `CLK_50M` | in | 1 | self | rising | 50 MHz master reference [C] | `FPGA_CLK2_50` board pin via `sys_top` | core PLL (`refclk`) |
| `RESET` | in | 1 | async | H | Cold reset from sys_top; can be used as initial reset [C] | `sysmem_lite.reset_out` (driven by `gp_out[31:30]` + cold-reset button) | core reset chain |
| `HPS_BUS` | inout | 46 | mixed | n/a | Framework HPS bridge mux (see §3.4) [C] | `sys_top` packs; core re-drives [37],[36],[15:0] | `hps_io` and `video_calc` inside `hps_io` |
| `CLK_VIDEO` | out | 1 | self | rising | Pixel-rate base clock for the video pipeline [C] | core PLL output (often `clk_sys`) | scaler / HDMI / OSD / VGA |
| `CE_PIXEL` | out | 1 | `CLK_VIDEO` | H | Per-pixel clock-enable on `CLK_VIDEO` [C] | core | scaler / video_mixer |
| `VIDEO_ARX` | out | 13 | `clk_sys` | n/a | Aspect-ratio X numerator, or scaled width if bit[12]=1 [C] | core | HDMI scaler |
| `VIDEO_ARY` | out | 13 | `clk_sys` | n/a | Aspect-ratio Y denominator, or scaled height if bit[12]=1 [C] | core | HDMI scaler |
| `VGA_R` | out | 8 | `CLK_VIDEO` | n/a | Red channel, 8-bit [C] | core | VGA + scaler input |
| `VGA_G` | out | 8 | `CLK_VIDEO` | n/a | Green channel, 8-bit [C] | core | VGA + scaler input |
| `VGA_B` | out | 8 | `CLK_VIDEO` | n/a | Blue channel, 8-bit [C] | core | VGA + scaler input |
| `VGA_HS` | out | 1 | `CLK_VIDEO` | core-set | Horizontal sync [C] | core | VGA + scaler |
| `VGA_VS` | out | 1 | `CLK_VIDEO` | core-set | Vertical sync [C] | core | VGA + scaler |
| `VGA_DE` | out | 1 | `CLK_VIDEO` | H | Active-pixel window, `~(HBlank \| VBlank)` [C] | core | scaler |
| `VGA_F1` | out | 1 | `CLK_VIDEO` | H | Interlace field flag (field 1 indicator) [C] | core | scaler |
| `VGA_SL` | out | 2 | `CLK_VIDEO` | n/a | Scanlines select (0=off, 1..3=intensities) [C] | core | scandoubler/scaler |
| `VGA_SCALER` | out | 1 | `clk_sys` | H | Force HDMI scaler onto the analog VGA output [C] | core | sys_top VGA mux |
| `VGA_DISABLE` | out | 1 | `clk_sys` | H | Disable the analog output entirely (single-SDRAM build only) [C] | core | sys_top VGA mux |
| `HDMI_WIDTH` | in | 12 | `clk_sys` | n/a | Current HDMI active width in pixels (post-scaler) [C] | `sys_top` (cfg-derived) | core layout logic |
| `HDMI_HEIGHT` | in | 12 | `clk_sys` | n/a | Current HDMI active height in pixels (post-scaler) [C] | `sys_top` (cfg-derived) | core layout logic |
| `HDMI_FREEZE` | out | 1 | `clk_sys` | H | Freeze HDMI on last frame (pause artifact suppression) [C] | core | scaler |
| `HDMI_BLACKOUT` | out | 1 | `clk_sys` | H | Black out HDMI output [C] | core | sys_top HDMI mux |
| `HDMI_BOB_DEINT` | out | 1 | `clk_sys` | H | Request bob (line-doubling) deinterlace mode [C] | core | scaler |
| `FB_EN` | out | 1 | `clk_sys` | H | Enable DDR-backed framebuffer video path (only with `MISTER_FB`) [C] | core | sys_top FB mux |
| `FB_FORMAT` | out | 5 | `clk_sys` | n/a | `[2:0]` bpp mode (3=8bpp pal, 4=16bpp, 5=24bpp, 6=32bpp); `[3]` 565/1555; `[4]` RGB/BGR (only with `MISTER_FB`) [C] | core | sys_top FB unpacker |
| `FB_WIDTH` | out | 12 | `clk_sys` | n/a | Framebuffer width in pixels (only with `MISTER_FB`) [C] | core | scaler |
| `FB_HEIGHT` | out | 12 | `clk_sys` | n/a | Framebuffer height in pixels (only with `MISTER_FB`) [C] | core | scaler |
| `FB_BASE` | out | 32 | `clk_sys` | n/a | DDRAM byte address of framebuffer base (only with `MISTER_FB`) [C] | core | sysmem |
| `FB_STRIDE` | out | 14 | `clk_sys` | n/a | Bytes per FB line; 0 = round to 256B (only with `MISTER_FB`) [C] | core | scaler |
| `FB_VBL` | in | 1 | `clk_sys` | H | Scaler vertical-blank pulse for FB-mode sync (only with `MISTER_FB`) [C] | sys_top scaler | core |
| `FB_LL` | in | 1 | `clk_sys` | H | "Low latency" mode flag from cfg bit (only with `MISTER_FB`) [C] | `sys_top` | core |
| `FB_FORCE_BLANK` | out | 1 | `clk_sys` | H | Force-blank the scaler's framebuffer output (only with `MISTER_FB`) [C] | core | scaler |
| `FB_PAL_CLK` | out | 1 | self | rising | Palette RAM clock (only with `MISTER_FB_PALETTE`) [C] | core | FB palette |
| `FB_PAL_ADDR` | out | 8 | `FB_PAL_CLK` | n/a | Palette write/read address (only with `MISTER_FB_PALETTE`) [C] | core | FB palette |
| `FB_PAL_DOUT` | out | 24 | `FB_PAL_CLK` | n/a | Palette write data (only with `MISTER_FB_PALETTE`) [C] | core | FB palette |
| `FB_PAL_DIN` | in | 24 | `FB_PAL_CLK` | n/a | Palette read data (only with `MISTER_FB_PALETTE`) [C] | FB palette | core |
| `FB_PAL_WR` | out | 1 | `FB_PAL_CLK` | H | Palette write strobe (only with `MISTER_FB_PALETTE`) [C] | core | FB palette |
| `LED_USER` | out | 1 | `clk_sys` | H | User-defined activity LED on I/O board (1=on) [C] | core | sys_top LED mux |
| `LED_POWER` | out | 2 | `clk_sys` | n/a | `[1]` override-enable, `[0]` LED state; `2'b00` = let system drive [C] | core | sys_top LED mux |
| `LED_DISK` | out | 2 | `clk_sys` | n/a | Same encoding as `LED_POWER` [C] | core | sys_top LED mux |
| `BUTTONS` | out | 2 | `clk_sys` | H | `[1]`=fake user-button press, `[0]`=fake OSD-button press [C] | core | sys_top button OR |
| `CLK_AUDIO` | in | 1 | self | rising | 24.576 MHz audio clock from `pll_audio` [C] | sys_top `pll_audio` | core audio path |
| `AUDIO_L` | out | 16 | `CLK_AUDIO` | n/a | Left sample (sign per `AUDIO_S`) [C] | core | `audio_out` |
| `AUDIO_R` | out | 16 | `CLK_AUDIO` | n/a | Right sample [C] | core | `audio_out` |
| `AUDIO_S` | out | 1 | `CLK_AUDIO` | H | 1=signed audio, 0=unsigned [C] | core | `audio_out` |
| `AUDIO_MIX` | out | 2 | `CLK_AUDIO` | n/a | 0=no mix, 1=25%, 2=50%, 3=100% (mono) [C] | core | `audio_out` |
| `ADC_BUS` | inout | 4 | external | n/a | LTC2308 ADC SPI bus on the I/O board [C] | core (when used) | I/O-board ADC pins |
| `SD_SCK` | out | 1 | `clk_sys` | rising | Secondary SD card SPI clock [C] | core | SD pin |
| `SD_MOSI` | out | 1 | `clk_sys` | n/a | SD MOSI [C] | core | SD pin |
| `SD_MISO` | in | 1 | `clk_sys` | n/a | SD MISO [C] | SD pin | core |
| `SD_CS` | out | 1 | `clk_sys` | L | SD chip-select [C] | core | SD pin |
| `SD_CD` | in | 1 | `clk_sys` | L | SD card-detect [C] | board / mcp23009 | core |
| `DDRAM_CLK` | out | 1 | self | rising | Clock the f2h_sdram bridge uses; typically the core's main clock [C] | core | `sysmem_lite.ram1_clk` |
| `DDRAM_BUSY` | in | 1 | `DDRAM_CLK` | H | Bridge cannot accept a request this cycle [C] | `sysmem_lite.ram1_waitrequest` | core |
| `DDRAM_BURSTCNT` | out | 8 | `DDRAM_CLK` | n/a | Words in burst (max 128) [C] | core | sysmem |
| `DDRAM_ADDR` | out | 29 | `DDRAM_CLK` | n/a | Word address (64-bit-word granularity) [C] | core | sysmem |
| `DDRAM_DOUT` | in | 64 | `DDRAM_CLK` | n/a | Read data word [C] | sysmem | core |
| `DDRAM_DOUT_READY` | in | 1 | `DDRAM_CLK` | H | 1-cycle pulse per valid `DDRAM_DOUT` [C] | sysmem | core |
| `DDRAM_RD` | out | 1 | `DDRAM_CLK` | H | 1-cycle read request [C] | core | sysmem |
| `DDRAM_DIN` | out | 64 | `DDRAM_CLK` | n/a | Write data [C] | core | sysmem |
| `DDRAM_BE` | out | 8 | `DDRAM_CLK` | H | Byte-enable mask for writes [C] | core | sysmem |
| `DDRAM_WE` | out | 1 | `DDRAM_CLK` | H | 1-cycle write request [C] | core | sysmem |
| `SDRAM_CLK` | out | 1 | self | rising | SDR SDRAM clock to chip [C] | core's SDRAM PLL output | SDRAM pin |
| `SDRAM_CKE` | out | 1 | n/a | H | SDRAM clock-enable [C] | core | SDRAM pin |
| `SDRAM_A` | out | 13 | `SDRAM_CLK` | n/a | SDRAM address [C] | core | SDRAM pin |
| `SDRAM_BA` | out | 2 | `SDRAM_CLK` | n/a | SDRAM bank address [C] | core | SDRAM pin |
| `SDRAM_DQ` | inout | 16 | `SDRAM_CLK` | n/a | SDRAM data bus [C] | core / SDRAM chip | core / SDRAM pin |
| `SDRAM_DQML` | out | 1 | `SDRAM_CLK` | L | SDRAM byte mask, low byte [C] | core | SDRAM pin |
| `SDRAM_DQMH` | out | 1 | `SDRAM_CLK` | L | SDRAM byte mask, high byte [C] | core | SDRAM pin |
| `SDRAM_nCS` | out | 1 | `SDRAM_CLK` | L | SDRAM chip-select [C] | core | SDRAM pin |
| `SDRAM_nCAS` | out | 1 | `SDRAM_CLK` | L | SDRAM column-strobe [C] | core | SDRAM pin |
| `SDRAM_nRAS` | out | 1 | `SDRAM_CLK` | L | SDRAM row-strobe [C] | core | SDRAM pin |
| `SDRAM_nWE` | out | 1 | `SDRAM_CLK` | L | SDRAM write-enable [C] | core | SDRAM pin |
| `SDRAM2_EN` | in | 1 | `clk_sys` | H | Secondary SDRAM present (only with `MISTER_DUAL_SDRAM`) [C] | sys_top (cfg bit) | core |
| `SDRAM2_CLK` | out | 1 | self | rising | Secondary SDRAM clock (only with `MISTER_DUAL_SDRAM`) [C] | core | SDRAM2 pin |
| `SDRAM2_A` | out | 13 | `SDRAM2_CLK` | n/a | Secondary SDRAM address (only with `MISTER_DUAL_SDRAM`) [C] | core | SDRAM2 pin |
| `SDRAM2_BA` | out | 2 | `SDRAM2_CLK` | n/a | Secondary bank address (only with `MISTER_DUAL_SDRAM`) [C] | core | SDRAM2 pin |
| `SDRAM2_DQ` | inout | 16 | `SDRAM2_CLK` | n/a | Secondary SDRAM data bus (only with `MISTER_DUAL_SDRAM`) [C] | core / chip | core / pin |
| `SDRAM2_nCS` | out | 1 | `SDRAM2_CLK` | L | Secondary CS (only with `MISTER_DUAL_SDRAM`) [C] | core | pin |
| `SDRAM2_nCAS` | out | 1 | `SDRAM2_CLK` | L | Secondary CAS (only with `MISTER_DUAL_SDRAM`) [C] | core | pin |
| `SDRAM2_nRAS` | out | 1 | `SDRAM2_CLK` | L | Secondary RAS (only with `MISTER_DUAL_SDRAM`) [C] | core | pin |
| `SDRAM2_nWE` | out | 1 | `SDRAM2_CLK` | L | Secondary WE (only with `MISTER_DUAL_SDRAM`) [C] | core | pin |
| `UART_CTS` | in | 1 | async | core-set | UART clear-to-send (HPS UART side) [C] | sys_top (`uart_rts`) | core |
| `UART_RTS` | out | 1 | async | core-set | UART request-to-send [C] | core | sys_top (`uart_cts`) |
| `UART_RXD` | in | 1 | async | n/a | UART data from HPS [C] | sys_top (`uart_txd`) | core |
| `UART_TXD` | out | 1 | async | n/a | UART data to HPS [C] | core | sys_top (`uart_rxd`) |
| `UART_DTR` | out | 1 | async | core-set | UART data-terminal-ready [C] | core | sys_top (`uart_dsr`) |
| `UART_DSR` | in | 1 | async | core-set | UART data-set-ready [C] | sys_top (`uart_dtr`) | core |
| `USER_IN` | in | 7 | async | n/a | User-port open-drain inputs; read only when corresponding `USER_OUT` bit is 1 [C] | board pins / `USER_IO` | core |
| `USER_OUT` | out | 7 | async | L (open-drain) | User-port open-drain outputs; `0`=pull low, `1`=Hi-Z (and enables read) [C] | core | board pins via sys_top |
| `OSD_STATUS` | in | 1 | `clk_sys` | H | OSD is open / visible [C] | sys_top (`osd_status` from `vga_osd`) | core (pause / autosave) |

### 3.4 HPS_BUS bit-map

`HPS_BUS` carries one named signal per bit between `sys_top.v` and `hps_io`. The core wires `HPS_BUS` straight through; **only** bits `[37]`, `[36]`, and `[15:0]` are driven *out* by the core (`hps_io` sets them). All other bits flow *in* from `sys_top`.

```verilog
// archive/github/MiSTer-devel/Template_MiSTer/sys/sys_top.v:1760-1763 @ f35083f3b40d
	.HPS_BUS({f1, HDMI_TX_VS, 
				 clk_100m, clk_ihdmi,
				 ce_hpix, hde_emu, hhs_fix, hvs_fix, 
				 io_wait, clk_sys, io_fpga, io_uio, io_strobe, io_wide, io_din, io_dout}),
```

```verilog
// archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:184-194 @ f35083f3b40d
wire        io_strobe= HPS_BUS[33];
wire        io_enable= HPS_BUS[34];
wire        fp_enable= HPS_BUS[35];
wire        io_wide  = (WIDE) ? 1'b1 : 1'b0;
wire [15:0] io_din   = HPS_BUS[31:16];
reg  [15:0] io_dout;

assign HPS_BUS[37]   = ioctl_wait;
assign HPS_BUS[36]   = clk_sys;
assign HPS_BUS[32]   = io_wide;
assign HPS_BUS[15:0] = EXT_BUS[32] ? EXT_BUS[15:0] : fp_enable ? fp_dout : io_dout;
```

| Bit | Name in sys_top | Name in hps_io | Dir wrt emu | Producer |
| --- | --- | --- | --- | --- |
| 45 | `f1` | `f1` | in | core's `VGA_F1` looped through sys_top |
| 44 | `HDMI_TX_VS` | `vs_hdmi` | in | HDMI transmitter vsync |
| 43 | `clk_100m` | `clk_100` | in | sysmem 100 MHz clock |
| 42 | `clk_ihdmi` (=`clk_vid`) | `clk_vid` | in | core's `CLK_VIDEO` looped through |
| 41 | `ce_hpix` | `ce_pix` | in | scaler/OSD-tap pixel CE |
| 40 | `hde_emu` | `de` | in | core's `VGA_DE` looped through |
| 39 | `hhs_fix` | `hs` | in | sync-polarity-fixed `VGA_HS` |
| 38 | `hvs_fix` | `vs` | in | sync-polarity-fixed `VGA_VS` |
| 37 | `io_wait` | `ioctl_wait` | **out (from core)** | `hps_io` asserts when core throttles ioctl |
| 36 | `clk_sys` | `clk_sys` | **out (from core)** | core's `clk_sys` — sys_top samples this |
| 35 | `io_fpga` | `fp_enable` | in | RBF/FPGA-config command channel select |
| 34 | `io_uio` | `io_enable` | in | UIO command channel select |
| 33 | `io_strobe` | `io_strobe` | in | 1-cycle strobe per SPI word |
| 32 | `io_wide` | `io_wide` | bidir (parameter) | `hps_io`'s `WIDE` parameter set on the wire |
| 31:16 | `io_din` | `io_din` | in | HPS→FPGA 16-bit payload |
| 15:0 | `io_dout` | `io_dout` | **out (from core)** | FPGA→HPS 16-bit payload |

## 4. Sequencing & timing

### 4.1 Reset chain into emu

```
HPS gp_out[31:30]  ──┐                                                          
                     │ resetd/resetd2 (2-cycle FF on FPGA_CLK2_50)              
                     ▼                                                          
BTN_RESET (I/O bd) ──► btn_r  ──► sysmem_lite.reset_core_req                     
cold-reset button ──► btn_r  ──► sysmem_lite.reset_hps_cold_req                  
                                                                             
sysmem_lite.reset_out ─► wire reset (sys_top) ─► emu.RESET (port)              
                                                                             
emu: wire reset = RESET | status[0] | buttons[1];                              
```

`reset_req` rises on `gp_out[31:30]==1` and clears on `==2`. `reset` is held while the request bit is set and during sysmem startup. `RESET` enters `emu` as an async active-high pulse; the in-core convention OR's it with `status[0]` (CONF_STR-driven soft reset) and `buttons[1]` (OSD-driven user-button) to form the core's local reset.

```verilog
// archive/github/MiSTer-devel/Template_MiSTer/sys/sys_top.v:581-612 @ f35083f3b40d
reg reset_req = 0;
always @(posedge FPGA_CLK2_50) begin
	reg [1:0] resetd, resetd2;
	reg       old_reset;

	//latch the reset
	old_reset <= reset;
	if(~old_reset & reset) reset_req <= 1;

	//special combination to set/clear the reset
	//preventing of accidental reset control
	if(resetd==1) reset_req <= 1;
	if(resetd==2 && resetd2==0) reset_req <= 0;

	resetd  <= gp_out[31:30];
	resetd2 <= resetd;
end

////////////////////  SYSTEM MEMORY & SCALER  /////////////////////////

wire reset;
wire clk_100m;

sysmem_lite sysmem
(
	//Reset/Clock
	.reset_core_req(reset_req),
	.reset_out(reset),
	.clock(clk_100m),

	//DE10-nano has no reset signal on GPIO, so core has to emulate cold reset button.
	.reset_hps_cold_req(btn_r),
```

```verilog
// archive/github/MiSTer-devel/Template_MiSTer/Template.sv:120 @ f35083f3b40d
wire reset = RESET | status[0] | buttons[1];
```

### 4.2 HPS_BUS handshake (per SPI word)

`io_strobe` is the consumer signal seen by the core via `hps_io`. The strobe is gated by `io_uio`/`io_fpga` (channel selects). The core's loopback is `io_wait` (used to throttle ioctl) and `io_dout` (response payload).

```
clk_sys      ‾|_|‾|_|‾|_|‾|_|‾|_|‾|_
io_strobe    __/‾‾‾‾\____________/‾‾
io_din[15:0] ==X<word N>====X<word N+1>=
io_dout[15:0] (core drives next clock)
io_wait      (core may pulse to stall HPS between writes)
                ^ rising strobe = present this word
```

Inside `hps_io`, `io_strobe = ~rack & io_clk` (sys_top derives it from `gp_out`). The core does not need to handshake `io_strobe` other than reading `io_din` on its rising edge. See `20-hps-io-overview.md` for command-level framing.

### 4.3 Video timing

`CLK_VIDEO` and `CE_PIXEL` together pace the RGB/sync outputs. `VGA_DE=1` for each emitted pixel. The scaler resamples this stream to `HDMI_WIDTH × HDMI_HEIGHT` based on `VIDEO_ARX`/`VIDEO_ARY`. Detailed cycle-by-cycle waveforms are in [40-video.md].

```
CLK_VIDEO  ‾|_|‾|_|‾|_|‾|_|‾|_|‾|_
CE_PIXEL   __/‾\___/‾\___/‾\___/‾\
VGA_DE     ____/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾
VGA_R/G/B  XXXX<pix0><pix1><pix2><pix3>
              ^ first valid pixel
```

## 5. Minimal working pattern

The Template instance below is the canonical "smallest correct emu". The block above the divider line is the contract-only boilerplate — every emu needs *this* shape; the lines below the divider are example core glue and are entirely replaceable.

```verilog
// archive/github/MiSTer-devel/Template_MiSTer/Template.sv:19-50 @ f35083f3b40d
module emu
(
	`include "sys/emu_ports.vh"
);

///////// Default values for ports not used in this core /////////

assign ADC_BUS  = 'Z;
assign USER_OUT = '1;
assign {UART_RTS, UART_TXD, UART_DTR} = 0;
assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;
assign {SDRAM_DQ, SDRAM_A, SDRAM_BA, SDRAM_CLK, SDRAM_CKE, SDRAM_DQML, SDRAM_DQMH, SDRAM_nWE, SDRAM_nCAS, SDRAM_nRAS, SDRAM_nCS} = 'Z;
assign {DDRAM_CLK, DDRAM_BURSTCNT, DDRAM_ADDR, DDRAM_DIN, DDRAM_BE, DDRAM_RD, DDRAM_WE} = '0;  

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
```

```verilog
// archive/github/MiSTer-devel/Template_MiSTer/Template.sv:89-120 @ f35083f3b40d
wire forced_scandoubler;
wire   [1:0] buttons;
wire [127:0] status;
wire  [10:0] ps2_key;

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

wire clk_sys;
pll pll
(
	.refclk(CLK_50M),
	.rst(0),
	.outclk_0(clk_sys)
);

wire reset = RESET | status[0] | buttons[1];
```

Notes on the boilerplate (see also `01-glossary.md`):

- `ADC_BUS='Z'` releases the I/O-board ADC pins so the framework's own driver (if any) wins. `USER_OUT='1'` releases the open-drain user port (per §2 rule on `USER_OUT`/`USER_IN`).
- SDRAM is tied to `Z` (chip pins, must float when unused). DDRAM is tied to `'0` (internal bus, must not float).
- The PLL module **and** instance are both named `pll`; do not rename either.

## 6. Common variations across cores

Reference cores (NES, SNES, PSX, ao486, etc.) are not in the archive — only the starter profile is. Direct core-to-core comparisons are **`[deferred — reference cores not fetched]`**. Framework-implied variation points (covered below) are derived from `emu_ports.vh` conditionals and `sys_top.v` wiring.

- **SDRAM in use vs. tied off.** A core that needs SDRAM instantiates its own controller driving the `SDRAM_*` pins; one that does not (e.g. simple 8-bit demo) assigns the whole bus to `'Z` as the Template does. [V] (archive/github/MiSTer-devel/Template_MiSTer/Template.sv:30 @ f35083f3b40d)
- **Dual-SDRAM builds.** Defining `MISTER_DUAL_SDRAM` adds `SDRAM2_*` ports and `SDRAM2_EN`. Cores must tri-state `SDRAM2_*` "ASAP" when `SDRAM2_EN=0`. [V] (archive/github/MiSTer-devel/Template_MiSTer/sys/emu_ports.vh:124-136 @ f35083f3b40d)
- **DDRAM in use vs. tied off.** DDRAM is driven into the on-chip f2h_sdram bridge, so unused signals are tied to `'0`, not `Z`. Cores using DDRAM (e.g. CD-based systems, savestate buffers, scaler framebuffers) drive the full Avalon-MM-style interface. [V] (archive/github/MiSTer-devel/Template_MiSTer/Template.sv:31 @ f35083f3b40d)
- **Framebuffer mode (`MISTER_FB`).** Adds 9 `FB_*` ports for DDR-backed video. Cores not using FB simply leave the macro undefined; cores using it set `FB_EN`, `FB_FORMAT`, `FB_WIDTH/HEIGHT`, `FB_BASE`, `FB_STRIDE` and consume `FB_VBL`/`FB_LL`. [V] (archive/github/MiSTer-devel/Template_MiSTer/sys/emu_ports.vh:40-67 @ f35083f3b40d)
- **Framebuffer palette (`MISTER_FB_PALETTE`).** Nested under `MISTER_FB`; adds the `FB_PAL_*` palette-port group for 8bpp indexed modes. [V] (archive/github/MiSTer-devel/Template_MiSTer/sys/emu_ports.vh:58-66 @ f35083f3b40d)
- **ADC use.** `ADC_BUS` is for cassette-tape inputs and similar analog hooks (LTC2308 SPI). Most cores tie `'Z`; cores wanting audio sampling instantiate the `ltc2308` block from `sys/`. [V] (archive/github/MiSTer-devel/MkDocs_MiSTer/docs/developer/emu.md:156-163 @ 9033bd292fdc)
- **Secondary SD-SPI.** Optional `SD_SCK/MOSI/CS/MISO/CD` group for cores needing a real SD card outside the OSD's mount-slot model (rare). Most cores tie outputs to `'Z`. [V] (archive/github/MiSTer-devel/Template_MiSTer/sys/emu_ports.vh:91-96 @ f35083f3b40d)
- **UART.** Most cores tie `UART_RTS/TXD/DTR = 0`. Cores emulating modems / MIDI / debug UART drive these. [V] (archive/github/MiSTer-devel/Template_MiSTer/Template.sv:28 @ f35083f3b40d; archive/github/MiSTer-devel/MkDocs_MiSTer/docs/developer/emu.md:255-268 @ 9033bd292fdc)
- **User port.** Used by cores that need extra GPIO (light gun, paddles, IO expanders, second player ports on consoles). Most cores tie `USER_OUT='1'`. [V] (archive/github/MiSTer-devel/Template_MiSTer/Template.sv:27 @ f35083f3b40d)
- **Direct vs. scaler video out.** `VGA_SCALER=1` forces the HDMI scaler onto the analog VGA path. `VGA_DISABLE=1` turns the analog path off entirely (only legal in single-SDRAM builds; the port is `\`ifdef`'d out under `MISTER_DUAL_SDRAM` in sys_top, but always present in `emu_ports.vh`). [V] (archive/github/MiSTer-devel/Template_MiSTer/sys/emu_ports.vh:31-32 @ f35083f3b40d; archive/github/MiSTer-devel/Template_MiSTer/sys/sys_top.v:1774-1776 @ f35083f3b40d)
- **CLK_VIDEO ≡ clk_sys vs. a separate pixel clock.** The Template assigns `CLK_VIDEO = clk_sys`. Cores with high pixel clocks (arcade / 480p machines) generate a dedicated PLL output. [O] (archive/github/MiSTer-devel/Template_MiSTer/Template.sv:149 @ f35083f3b40d)
- **Direct-core comparison.** NES / SNES / PSX / ao486 specifics are deferred until reference cores are fetched. **`[deferred — reference cores not fetched]`**

## 7. Anti-patterns

### A.1 Tri-stating DDRAM outputs when not using DDR

- **Symptom:** Synthesis warnings about floating internal nets and/or the HPS f2sdram bridge entering an illegal state; on hardware, occasional core hangs at startup, especially after core-reload (`f2sdram_safe_terminator` exists explicitly because of this hazard).
- **Cause:** DDRAM_* signals go into an on-chip Avalon-MM bridge, **not** an external chip's pins. Tristate values are not legal on an internal port.
- **Fix:** Tie unused DDRAM outputs to `'0` exactly as the Template does: `assign {DDRAM_CLK, DDRAM_BURSTCNT, DDRAM_ADDR, DDRAM_DIN, DDRAM_BE, DDRAM_RD, DDRAM_WE} = '0;`
- **Citation:** archive/github/MiSTer-devel/Template_MiSTer/Template.sv:31 @ f35083f3b40d; archive/github/MiSTer-devel/Template_MiSTer/sys/f2sdram_safe_terminator.sv:1-15 @ f35083f3b40d

### A.2 Renaming the PLL module or instance

- **Symptom:** Quartus compiles but on the hardware nothing runs / clocks are unconstrained; STA shows "unconstrained paths" and the SDC `set_clock_groups` line in `sys_top.sdc` matches nothing.
- **Cause:** `sys_top.sdc` searches `*|pll|pll_inst|altera_pll_i|*[*].*|divclk` to constrain the core PLL. Renaming either the module file (`pll.v`) or the Verilog instance breaks the SDC pattern.
- **Fix:** Keep the module named `pll` and instantiate it as `pll pll (...);`. Use the megawizard to *edit* the existing PLL rather than creating a new differently-named one.
- **Citation:** archive/github/MiSTer-devel/Template_MiSTer/Template.sv:112-118 @ f35083f3b40d; archive/github/MiSTer-devel/Template_MiSTer/sys/sys_top.sdc:14 @ f35083f3b40d; archive/github/MiSTer-devel/MkDocs_MiSTer/docs/developer/emu.md:13-15 @ 9033bd292fdc

### A.3 Reading USER_IN without driving USER_OUT high

- **Symptom:** `USER_IN` bits read as constant 0 (or random/noisy) regardless of the external device.
- **Cause:** `USER_OUT` is open-drain. `0` actively pulls the pin low; `1` releases it to the external pull-up. Reading `USER_IN[n]` while `USER_OUT[n]=0` always reads 0 because the core is holding the line low.
- **Fix:** Set the corresponding `USER_OUT` bit to 1 to release the pin before reading `USER_IN`. The Template default `assign USER_OUT = '1;` releases all bits.
- **Citation:** archive/github/MiSTer-devel/Template_MiSTer/sys/emu_ports.vh:145-151 @ f35083f3b40d; archive/github/MiSTer-devel/Template_MiSTer/Template.sv:27 @ f35083f3b40d

### A.4 Floating the OSD `BUTTONS` output

- **Symptom:** Compilation warnings about uninitialized output, possible accidental "always pressed" if the bits float to 1, or the OSD-button-press simulation feature simply not working.
- **Cause:** `BUTTONS` is an `output [1:0]` that sys_top ORs with the real button signals; leaving it unassigned is illegal Verilog for a module output.
- **Fix:** `assign BUTTONS = 0;` if the core does not simulate button presses (Template default).
- **Citation:** archive/github/MiSTer-devel/Template_MiSTer/Template.sv:48 @ f35083f3b40d; archive/github/MiSTer-devel/Template_MiSTer/sys/sys_top.v:234 @ f35083f3b40d

## 8. Verification

- **Compile sanity.** Quartus 17.0.x must produce no "port not declared" or "missing connection" errors. If any port in `emu_ports.vh` is missing a driver/sink, compile fails. The `srf` file silences known-safe warnings; new red warnings deserve attention.
- **STA / SDC.** After fitting, check the Timing Analyzer reports for unconstrained paths from / to the core's `pll`. If any appear, the PLL was renamed (see Anti-pattern A.2).
- **Reset visibility.** With the core running, opening the OSD and pressing "Reset" (status[0]) should trigger the in-core `reset` wire. Triggering BTN_RESET on the I/O board (or `gp_out[31:30]` from `Main_MiSTer`) should pulse the framework `reset` for several cycles before `emu.RESET` deasserts.
- **OSD symptom: black screen.** Likely a sync polarity or `VGA_DE` issue. Confirm `VGA_DE = ~(HBlank | VBlank)`, that `CLK_VIDEO > 40 MHz` (per §2), and that `CE_PIXEL` pulses every emitted pixel.
- **OSD symptom: garbled HDMI but clean VGA.** Suggests `HDMI_WIDTH`/`HEIGHT` being read before `cfg_set` settles, or `CE_PIXEL` being derived from a different clock than `CLK_VIDEO`. Both are §2 violations.
- **MiSTer.ini flags that surface bugs.**
  - `direct_video=1` bypasses the scaler — if VGA looks fine here but the scaler path is broken, the issue is in the scaler-feeding signals (`HDMI_*`, `VIDEO_ARX/ARY`), not the core's pixel stream.
  - `vga_scaler=1` forces the HDMI scaler onto VGA — useful to isolate analog-vs-digital path bugs.
  - `forced_scandoubler=1` ties `forced_scandoubler` high regardless of OSD; useful for 15 kHz cores being run through a VGA monitor without scaler.
  - `vsync_adjust=2` exposes any drift in your `VGA_VS` rate; if the framework cannot lock, the core's video clock is off-frequency.

## 9. Provenance footer

- archive/github/MiSTer-devel/Template_MiSTer/Template.sv @ f35083f3b40d — used for §2, §3, §5, §6, §7
- archive/github/MiSTer-devel/Template_MiSTer/sys/emu_ports.vh @ f35083f3b40d — used for §2, §3, §6, §7
- archive/github/MiSTer-devel/Template_MiSTer/sys/sys_top.v @ f35083f3b40d — used for §2, §3, §4, §6, §7
- archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv @ f35083f3b40d — used for §2, §3
- archive/github/MiSTer-devel/Template_MiSTer/sys/sys_top.sdc @ f35083f3b40d — used for §2, §7
- archive/github/MiSTer-devel/Template_MiSTer/sys/f2sdram_safe_terminator.sv @ f35083f3b40d — used for §7
- archive/github/MiSTer-devel/Template_MiSTer/Template.qsf @ f35083f3b40d — used for §2
- archive/github/MiSTer-devel/MkDocs_MiSTer/docs/developer/emu.md @ 9033bd292fdc — used for §2, §6, §7
