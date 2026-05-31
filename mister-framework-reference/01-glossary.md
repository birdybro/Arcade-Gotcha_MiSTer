# Glossary

> Bundle version: 2026-05-18
> Phase 3 integration: terms surfaced by topic docs 10–53 plus anti-patterns / porting checklist have been folded in.

## Hardware

- **DE10-Nano** — Terasic dev board (Intel/Altera Cyclone V SoC) that is the canonical MiSTer host.
- **HPS** — Hard Processor System: the dual-core ARM Cortex-A9 on the Cyclone V SoC. Runs Linux. Hosts `Main_MiSTer`.
- **FPGA fabric** — The programmable logic side of the Cyclone V SoC. Hosts the `emu` module and `sys/` framework.
- **SDRAM** — SDR SDRAM module(s) on the MiSTer SDRAM expansion board, connected to FPGA only. Current `SDRAM_xsds` board: 64 MB single / 128 MB dual (one `AS4C32M16SB-7TCN` chip per bus). Older `SDRAM_xs` / `SDRAM_xsd` boards: 32 MB single / 64 MB dual.
- **DDRAM (FPGA-to-HPS DDR)** — The 1 GB DDR3 memory attached to the HPS, accessed from the FPGA via the HPS f2sdram bridge.
- **RBF** — Raw Binary File: the FPGA bitstream emitted by Quartus Assembler (`output_files/<revision>.rbf` when `GENERATE_RBF_FILE ON`) and loaded by `Main_MiSTer` at core launch. Released as `<core>_YYYYMMDD.rbf` under `releases/`.
- **mt32pi** — Optional Raspberry Pi running the mt32-pi firmware, bridged to the FPGA via the User I/O port (MIDI + I2C + I²S). Cores that want MT-32 / SoundFont MIDI instantiate `sys/mt32pi.sv` themselves; the framework does not wire it.

## Framework

- **`emu`** — The user core's top-level module. Declared in `Template.sv`. Receives ports from `sys/emu_ports.vh`.
- **`sys_top.v`** — The framework's outer wrapper. Wires HPS↔FPGA bridges, video, audio, board IO, then instantiates `emu`.
- **`sys/` framework** — The directory of framework Verilog/VHDL that every core inherits unchanged. Examples: `hps_io.sv`, `ddr_svc.sv`, `video_mixer.sv`, `ascal.vhd`, `osd.v`, `sd_card.sv`.
- **`Main_MiSTer`** — The HPS-side C++ binary (`MiSTer` ELF). Drives the SPI bus and the HPS f2h bridge to the FPGA framework.
- **`f2sdram_safe_terminator`** — `sys/f2sdram_safe_terminator.sv`: parameterised wrapper inserted on every `f2sdram` Avalon-MM port (ram1, ram2, vbuf). On reset it latches the in-flight burst's address/count and writes dummy beats (with `byteenable=0`) until the burst completes, so a mid-burst tear-down does not leave the bridge wedged for the next core.
- **`arcade_video`** — `sys/arcade_video.v`: optional wrapper around `video_mixer` for arcade cores. Auto-expands packed RGB (`DW` = 6/8/9/12/18/24) to 8-bit/channel, fixes HS/VS polarity, and maps `fx[2:0]` to `{hq2x, VGA_SL}` (1 = HQ2x, 2..4 = scandoubler + 25/50/75 % scanlines). Contract: `clk_video > 40 MHz` and `≥ 4 × ce_pix`.
- **HDMI freezer (`video_freezer`)** — `sys/video_freezer.sv`: synthesises HS/VS while `HDMI_FREEZE=1` is held so a CRT does not drop sync. Used inside `video_mixer` to keep the analog path quiet during pause / autosave.

## Bridges & buses

- **HPS_BUS** — The 46-bit (`inout [45:0]`) framework-internal bus between `sys_top.v` and `hps_io`, passed through `emu` unchanged. Carries the SPI command word, strobes, channel selects, `clk_sys`, `ioctl_wait`, and video-pipeline observables. Upstream MkDocs lists 49 bits but the pinned RTL is 46.
- **SPI bus** — The physical/logical bus between `Main_MiSTer` (HPS) and `hps_io` (FPGA). Used for commands, status, file delivery.
- **ioctl path** — The file-delivery path through `hps_io` exposing `ioctl_download`/`ioctl_wr`/`ioctl_addr`/`ioctl_dout` to the core.
- **EXT_BUS** — A pass-through bus offered by `hps_io` for cores that want a second command channel.
- **f2sdram bridge** — The Cyclone V SoC's FPGA-to-HPS-DDR3 bridge presented to the fabric as an Avalon-MM slave. Three ports are wired by `sys/sysmem.sv`: `ram1` (64-bit, the `DDRAM_*` core port), `ram2` (64-bit, framework `ddr_svc`/ALSA/palette), `vbuf` (128-bit, scaler framebuffer). Every port goes through `f2sdram_safe_terminator`.
- **gamma_bus** — `inout [21:0]` between `hps_io` and `sys/gamma_corr.sv`: `[20]=clk_sys`, `[19]=gamma_en`, `[18]=gamma_wr`, `[17:8]=wr_addr`, `[7:0]=value`; `[21]` is the presence ack driven high only when a `video_mixer`/`arcade_video` with `GAMMA=1` consumes the bus.

## Signals & concepts

- **`status[127:0]`** — The framework status word. Each bit maps to a `CONF_STR` option `O[bit]`. The OSD writes bits; the core reads them.
- **`CONF_STR`** — A compile-time string parameter to `hps_io` describing menu options, file slots, mount slots, and version.
- **CE-domain** — A clock-enable-paced operation. The framework uses one `clk_sys` and gates per-pixel/per-sample with `CE_PIXEL`, `ce_audio`, etc.
- **`CLK_VIDEO` / `CE_PIXEL`** — The video clock and the clock-enable pulse that marks a valid pixel.
- **`RESET`** — Framework-supplied async active-high reset to `emu`, sourced from `sysmem_lite.reset_out` (warm reset via HPS `gp_out[31:30]` or cold-reset button). The in-core convention is `wire reset = RESET | status[0] | buttons[1];`.
- **`cold_reset`** — Not an `emu` port. "Cold reset" in this framework means FPGA reconfiguration; HPS-side only. The on-board cold-reset button drives `sysmem_lite.reset_hps_cold_req` to re-trigger the HPS reconfig flow.
- **`forced_scandoubler`** — Output of `hps_io` (= `cfg[4]`); set by the OSD or `MiSTer.ini`'s `forced_scandoubler=1`. Cores feed it to `video_mixer`/`arcade_video` to engage the scandoubler even when not requested per-option.
- **`direct_video`** — Output of `hps_io` (= `cfg[10]`); when high, `sys_top` bypasses the HDMI scaler and drives `HDMI_TX_CLK` from the core's `clk_vid`, exposing analog timing through the HDMI connector (with an HDMI-to-VGA adapter).
- **`new_vmode`** — Input to `hps_io` the core toggles to notify the HPS that its video resolution has changed (so the HPS re-reads `video_calc` and reconfigures the scaler).
- **`OSD_STATUS`** — Input to `emu` (active high) indicating the framework OSD is open; cores use it to pause emulation, trigger autosave, and gate gameplay-affecting input.
- **`change-detector`** — The 32-bit word at byte 0 of each save-state slot. The HPS polls it every ~1 s; a delta triggers a flush of `(size+2)*4` bytes to `<rom>_<N>.ss`. Core convention: write payload, then size word at `+4`, then change detector at `+0` last.
- **scaler** — The framework's HDMI upscaler. Implemented by `ascal.vhd` and wrappers.
- **ascal** — `sys/ascal.vhd`: the framework's adaptive HDMI scaler. Crosses from `clk_vid` to `clk_hdmi`, performs polyphase scaling, optional deinterlace and triple-buffer, and writes/reads a DDR3 framebuffer via the f2sdram bridge. Driven by the HDMI PLL (`sys/pll_hdmi.v`) whose fractional M is closed-loop-tuned by `sys/pll_hdmi_adj.vhd`. See `40a-video-pipeline.md`.

## Storage

- **ROM image** — Game/system ROM delivered from HPS to FPGA via the ioctl path.
- **`F<i>` slot** — `CONF_STR` directive `F[S]<i>,<ext>[,<text>][,<addr>]` that allocates ioctl file-slot index `i` (low 6 bits of `ioctl_index`). Selecting the entry in the OSD triggers an `ioctl_download` with `ioctl_index[5:0]==i`. `<addr>` in `[0x20000000, 0x40000000)` invokes the direct-DDRAM path (HPS `shmem_map`s the region; no `ioctl_wr` pulses fire).
- **Mount slot** — A file the OSD mounts as a "disk" (`S0`, `S1`, ...). Block IO via `sd_lba`/`sd_buff_*`.
- **`S<i>` slot** — `CONF_STR` directive `S<i>,<ext>[,<text>]` that allocates virtual-disk slot `i` (0..`VDNUM-1`). Selecting the entry pulses `img_mounted[i]` with `img_size`/`img_readonly` valid that cycle; thereafter the core issues `sd_rd`/`sd_wr` against `sd_lba[i]`.
- **`ioctl_upload_req`** — Core-driven (rising-edge) request that save-RAM be persisted; `hps_io` latches it and replies to opcode `0x3C` (UIO_CHK_UPLOAD) the next time the OSD opens. The HPS then issues `user_io_set_upload(1)` and reads `ioctl_din` indexed by `ioctl_addr`.
- **UIO_CHK_UPLOAD (0x3C)** — UIO opcode the HPS polls (only while the OSD is open) to learn that `ioctl_upload_req` fired. Reply: `{ioctl_upload_index, 8'd1}`; reading clears the latch. Also pollable via `spi_uio_cmd` on the regular UIO stream — used by C64/C128 `EasyFlash` save-back outside the standard `ioctl_upload_req` path.
- **EasyFlash** — Commodore 64/128 flash-cartridge format whose save-back uses the polled `UIO_CHK_UPLOAD` path with `ioctl_index = 99` rather than `ioctl_upload_req`. Driven from `Main_MiSTer/support/c64/c64.cpp`.
- **MRA** — XML file describing an arcade ROM set: which files to load, where, byte ordering, DIP defaults. Parsed by `Main_MiSTer/support/arcade/mra_loader.cpp`.
- **`<rom>` element** — Top-level MRA element with attributes `index=`/`zip=`/`md5=`/`address=`. Each `<rom>` becomes one ioctl download stream tagged with `ioctl_index`. `index=0` is the main game ROM; `index=254` is reserved for the DIP word; `index=255` is reserved for cheats.
- **`<part>` element** — Child of `<rom>` or `<interleave>`. File reference (with `name`/`zip`/`crc`/`offset`/`length`/`map`) or inline hex (with optional `repeat=`). Parts are concatenated into `romdata[]` in document order, then any `<patch>` siblings overwrite, then MD5 is checked, then the buffer is streamed via ioctl.
- **Save-state slot** — One of four contiguous DDRAM regions allocated by the HPS at `ss_base + i*ss_size` when `CONF_STR` carries `SS<base>:<size>`. First 64 bits are control: `[31:0]` change detector, `[63:32]` size in 32-bit words.

## Memory primitives

- **BRAM (Block RAM)** — Cyclone V FPGA on-chip block memory; the third memory tier alongside SDRAM and DDRAM. On the DE10-Nano the substrate is the M10K block. Cores and `sys/` modules infer BRAM from RTL idioms (synchronous read, no async output reset); the framework does not export BRAM ports.
- **M10K** — The Cyclone V Embedded Memory Block primitive: 10 240 bits each, with per-port byte-write granularity and legal per-port widths of 1, 2, 4, 5, 8, 10, 16, 20, 32, 40 bits. The DE10-Nano's `5CSEBA6U23I7` part contains 553 M10K blocks total.
- **MLAB** — Memory Logic Array Block: small distributed RAM built from ALMs, used by Quartus as the fallback target when a memory is too small for M10K or when inference fails. Opt-in via `(* romstyle = "MLAB" *)` for small ROMs.
- **Single-port RAM** — One BRAM shape: one shared address bus, one write-enable, one read-data register. `altsyncram` `operation_mode = "SINGLE_PORT"`. Inference idiom: one `always_ff` with `if(we) m[a]<=d; q<=m[a];`.
- **SDP (simple dual-port)** — One BRAM shape: one write port, one independent read port. Supports two independent clocks and mixed widths. `altsyncram` `operation_mode = "DUAL_PORT"`. Inference idiom: two separate `always_ff` blocks (one per port). The canonical line-buffer / gamma-LUT / FIFO shape in MiSTer.
- **TDP (true dual-port)** — One BRAM shape: two ports, each independently R+W, each with its own clock. `altsyncram` `operation_mode = "BIDIR_DUAL_PORT"`. The framework instantiates TDP explicitly only in `sys/sd_card.sv` (`sdbuf`); inference is generally not used.
- **`altsyncram`** — Quartus megafunction (`lpm_type = "altsyncram"`) for explicit Cyclone V memory-block instantiation. Used in `sys/sd_card.sv` for the SD-sector TDP buffer; for SDP/single-port the framework prefers RTL inference.
- **`ramstyle`** — Quartus synthesis attribute placed on an array declaration to steer BRAM inference: `"no_rw_check"` (M10K, ignore read/write collision protection — used when collisions are impossible by construction); `"logic"` (force ALMs, opt OUT of M10K and MLAB). Spelled `(* ramstyle = "..." *)` in Verilog/SV; VHDL uses `ATTRIBUTE ramstyle ... IS "..."`.
- **`romstyle`** — Quartus synthesis attribute for read-only arrays: `"MLAB"` forces a small ROM into MLAB rather than M10K. Used on `hq2x.sv`'s `hqTable` (6 × 256).
- **read-during-write (RDW)** — Behaviour of a BRAM port when a read and a write target the same address in the same cycle. For inferred SDP it is "don't care"; for TDP `altsyncram` it is selected per port via `read_during_write_mode_port_a/b` ∈ {`"NEW_DATA_NO_NBE_READ"`, `"OLD_DATA"`, `"DONT_CARE"`}. Cross-port collisions in TDP are always undefined.
- **`.mif` / `.hex`** — Quartus memory initialization files. `.mif` is the Altera Memory Initialization File format consumed by `altsyncram` `init_file`. `.hex` is plain Intel-HEX consumed by `$readmemh(...)`. Both are resolved against Quartus's project `SEARCH_PATH`; the framework ships only `sys/pll_cfg/pll_cfg.mif` (used by the PLL-reconfig IP).
- **5CSEBA6U23I7** — The DE10-Nano's Cyclone V SoC part number (Cyclone V SE, FPGA fabric + dual ARM Cortex-A9 HPS, 672-pin UFBGA, industrial temperature, speed grade 7). Contains 553 M10K blocks and is identified by `sys/sys.tcl`.

## Verilog macros / build switches

- **`MISTER_FB`** — Enables the DDR-backed framebuffer video path; adds 9 `FB_*` ports to `emu` (`FB_EN`, `FB_FORMAT`, `FB_WIDTH/HEIGHT`, `FB_BASE`, `FB_STRIDE`, `FB_VBL`, `FB_LL`, `FB_FORCE_BLANK`). Used by GBA, NeoGeo, the system menu, and `screen_rotate` arcade rotation.
- **`MISTER_FB_PALETTE`** — Nested under `MISTER_FB`; adds the 5-port `FB_PAL_*` palette group for 8bpp indexed framebuffer modes.
- **`MISTER_DUAL_SDRAM`** — Adds the `SDRAM2_*` port set and `SDRAM2_EN` input; mutually exclusive with the analog VGA/audio/SDIO pins (sourcing `sys/sys_dual_sdram.tcl` re-pins those signals). Flips the core-type magic word from `0xA4` to `0xA8`.
- **`MISTER_DEBUG_NOHDMI`** — Development-only: elides the HDMI PLL, scaler, and shadowmask; analog VGA is the only output. Must not be enabled in releases.
- **`MISTER_SMALL_VBUF`** — Reduces per-buffer ascal allocation from 8 MB to 2 MB; lowers max output resolution but frees DDR3.
- **`MISTER_DISABLE_ADAPTIVE`** — Disables ascal's adaptive polyphase filter; smaller LUT, fewer features.
- **`MISTER_DOWNSCALE_NN`** — Forces ascal nearest-neighbour downscale instead of bilinear.
- **`MISTER_DISABLE_YC`** — Removes the `yc_out.sv` composite/S-Video encoder from the analog chain.
- **`MISTER_DISABLE_ALSA`** — Removes `sys/alsa.sv` and the HPS PCM SPI master; cores that don't mix HPS-side audio (system bell, MT32-pi over USB-audio) save resources at the cost of those features.

## Tooling

- **Quartus 17.0.x** — The supported (recommended 17.0.2 Standard or Lite) toolchain. `Template.qsf` records `LAST_QUARTUS_VERSION "17.0.2 Standard Edition"`. Newer Quartus versions are not supported by the framework.
- **Quartus 13.0sp1 / 13.1** — Legacy toolchain supported via the `_Q13` project family (`Template_Q13.qpf/.qsf/.srf`). `sys/sys.qip` line 1 dispatches `pll_q[regexp]\.qip` so the same `sys/` tree builds under either toolchain.

## Conventions

- **`[C] [V] [O] [I]`** — Claim labels: contract, convention, observed, inference. See `00-INDEX.md`.
