# Porting Checklist — New MiSTer Core

> Bundle version: 2026-05-18
> Sequential, gated. Do not advance until the prior gate's checks pass.
> Each item cites the topic doc that defines the contract; bracket tags identify the source claim type: `[C]` framework contract (must-obey), `[V]` core convention.

## Gate 1: emu top-level boundary

- [ ] Confirm the top module is named `emu` and its port list opens with `` `include "sys/emu_ports.vh" ``. [C] (`10-emu-top-level.md` §2)
- [ ] Confirm `sys_top.v` is left untouched and `emu` is instantiated inside it (no edits to `sys/`). [C] (`10-emu-top-level.md` §2; `53-core-patterns.md` §2 C.2)
- [ ] Confirm `HPS_BUS` is declared `inout [45:0]` and passed through to `hps_io.HPS_BUS` byte-identically, with no extra drivers from the core. [C] (`10-emu-top-level.md` §2; `20-hps-io-overview.md` §2)
- [ ] Verify only three slices of `HPS_BUS` are driven back from `hps_io`: `[37]=ioctl_wait`, `[36]=clk_sys`, `[15:0]=io_dout`. [C] (`10-emu-top-level.md` §2; `20-hps-io-overview.md` §2)
- [ ] Confirm unused chip-pin outputs (`SDRAM_*`, `ADC_BUS`, `SD_*`) are tied to `'Z` (high-Z) — they reach physical board pins. [C] (`10-emu-top-level.md` §2; `53-core-patterns.md` §2 C.26)
- [ ] Confirm unused DDRAM outputs (`DDRAM_CLK, DDRAM_BURSTCNT, DDRAM_ADDR, DDRAM_DIN, DDRAM_BE, DDRAM_RD, DDRAM_WE`) are tied to `'0` — they feed an on-chip Avalon-MM bridge where tri-state is illegal. [C] (`10-emu-top-level.md` §2; `31-ddram.md` §2; `53-core-patterns.md` §2 C.27)
- [ ] Confirm `USER_OUT` defaults to `'1` for all open-drain bits so reads of `USER_IN` are not held low. [C]/[V] (`10-emu-top-level.md` §2; `53-core-patterns.md` §2 C.28)
- [ ] Confirm every other unused `output` port (UART, `LED_*`, `BUTTONS`, the framework's tie-offs) is driven with `0`. [C] (`53-core-patterns.md` §2 C.29)
- [ ] Confirm `BUTTONS` is explicitly assigned (e.g. `assign BUTTONS = 0;`) — leaving it unassigned is illegal Verilog for a module output. [C] (`10-emu-top-level.md` §2)
- [ ] Confirm `SDRAM2_*` outputs are gated on `SDRAM2_EN` and driven to `'Z` whenever `SDRAM2_EN==0`, even if `MISTER_DUAL_SDRAM` is enabled. [C] (`10-emu-top-level.md` §2; `30-sdram.md` §2)

## Gate 2: Clocks & resets

- [ ] Confirm the user PLL **module** is named `pll` and the **instance** is named `pll` so `sys/sys_top.sdc` constrains it via `*|pll|pll_inst|*`. [C] (`10-emu-top-level.md` §2; `12-clocks-resets-plls.md` §2; `53-core-patterns.md` §2 C.22)
- [ ] Confirm the PLL lives in `rtl/`, not `sys/`, so framework updates don't clobber it. [C] (`10-emu-top-level.md` §2; `53-core-patterns.md` §2 C.3)
- [ ] Confirm the user `pll` is instantiated with `.rst(0)` so `clk_sys` is free-running across warm reset (the framework expects sub-second warm resets). [C] (`12-clocks-resets-plls.md` §2)
- [ ] Confirm `RESET` is treated as asynchronous active-high and synchronized into `clk_sys` before use as an edge-sensitive signal. [C] (`12-clocks-resets-plls.md` §2)
- [ ] Verify the internal reset wire is `wire reset = RESET | status[0] | buttons[1];` (or equivalent combining the same three sources). [V] (`10-emu-top-level.md` §2; `12-clocks-resets-plls.md` §2; `53-core-patterns.md` §2 C.25)
- [ ] Confirm `CLK_VIDEO` is driven from the core's `pll` (typically `clk_sys` for the basic case). [C] (`12-clocks-resets-plls.md` §2)
- [ ] Confirm `CE_PIXEL` is derived from `CLK_VIDEO` and emitted as a 1-cycle clock-enable pulse per valid pixel. [C] (`12-clocks-resets-plls.md` §2; `40-video.md` §2)
- [ ] Confirm `CLK_VIDEO > 40 MHz` so the framework's scandoubler / hq2x / ascal stack works. [C] (`10-emu-top-level.md` §2; `40-video.md` §2)
- [ ] Confirm `CLK_AUDIO` is consumed only as an audio-path clock (DAC, sigma-delta, I²S) and is NOT used to drive core logic. [C] (`12-clocks-resets-plls.md` §2)
- [ ] Confirm `DDRAM_CLK` is driven by the core (typically from a PLL output or `clk_sys`) when DDRAM is used. [C] (`12-clocks-resets-plls.md` §2; `31-ddram.md` §2)

## Gate 3: CONF_STR & hps_io basics

- [ ] Confirm `CONF_STR` is declared as a `localparam` (Verilog string) in the core and passed to `hps_io` via `#(.CONF_STR(CONF_STR))`. [C] (`11-conf-str.md` §2 C.1; `53-core-patterns.md` §2 C.24)
- [ ] Verify the first `CONF_STR` directive is the core title text (terminated by `;;`). [V] (`11-conf-str.md` §2 C.3)
- [ ] Confirm `status[0]` is wired into the reset chain (the `T[0]`/`R[0]` OSD entries only pulse this bit). [C] (`10-emu-top-level.md` §2; `11-conf-str.md` §2 C.4)
- [ ] Confirm only one `O`/`T`/`R` directive occupies any given status bit — overlaps silently overwrite. [C] (`11-conf-str.md` §2 C.8)
- [ ] Confirm `H/D/h/d` indices are in 0..15 (the `status_menumask` is 16 bits wide). [C] (`11-conf-str.md` §2 C.6)
- [ ] Confirm `CONF_STR` prefix order is `[H|D|h|d]{Idx}` then `P{Page}` then the directive (e.g. `d5P1o2,...`, not `P1d5o2,...`). [C] (`11-conf-str.md` §2 C.10)
- [ ] Confirm `v,<n>` is bumped whenever any `O`/`T`/`R` bit assignment changes (additions, deletions, reorderings) — otherwise old saved status replays into the new layout. [C] (`11-conf-str.md` §2 C.14)
- [ ] Confirm non-OSD `CONF_STR` directives (`J`, `jn`, `jp`, `V`, `I`, `DEFMRA`) are placed at the bottom of the string. [C] (`11-conf-str.md` §2 C.16)
- [ ] Verify the `V,...` line uses `` `BUILD_DATE `` from `sys/build_id.tcl` to stamp today's date in the OSD banner. [V] (`11-conf-str.md` §2 C.15; `53-core-patterns.md` §2 C.31)
- [ ] Confirm exactly one `hps_io` is instantiated, with `.HPS_BUS(HPS_BUS)` and the core-type magic word handshake satisfied (`{24'h5CA623, core_type}` = `0xA4` single SDRAM or `0xA8` dual SDRAM). [C] (`20-hps-io-overview.md` §2; `53-core-patterns.md` §2 C.23)
- [ ] Verify `status[127:0]` is consumed only — the framework writes it via command `0x1E`. [C] (`20-hps-io-overview.md` §2)
- [ ] Confirm `status_set` is pulsed (rising-edge) per writeback request, not held as a level. [C] (`20-hps-io-overview.md` §2)
- [ ] Confirm `RTC[63:0]` and `TIMESTAMP[31:0]` are sampled only when their respective `[64]`/`[32]` toggle bits change. [C] (`20-hps-io-overview.md` §2)
- [ ] Confirm `OSD_STATUS` is consumed by the core (input gating, pause, autosave triggers) — the core MUST NOT instantiate `osd.v`. [C] (`10-emu-top-level.md` §2; `23-osd-menu-and-input.md` §2)
- [ ] Confirm `ps2_key[10]` is edge-detected (it is a toggle, not a level) and `ps2_mouse[24]` / `spinner_N[8]` toggles likewise. [C] (`23-osd-menu-and-input.md` §2)
- [ ] Confirm `joystick_l_analog_N` / `joystick_r_analog_N` are interpreted as signed 8-bit halves, not unsigned. [C] (`23-osd-menu-and-input.md` §2)

## Gate 4: File loading & mounts

- [ ] Confirm `ioctl_download` is treated as a level: edge-detect both rising (assert load-reset) and falling (release reset, begin operation). [C] (`21-hps-io-ioctl-and-download.md` §2 Rule 1; `32-rom-save-state-flows.md` §2.1)
- [ ] Confirm `ioctl_wr` is used as a one-cycle write strobe, never as a level enable. [C] (`21-hps-io-ioctl-and-download.md` §2 Rule 2)
- [ ] Confirm `ioctl_wait` is driven high whenever the write target (SDRAM, decompressor, …) is not ready to accept the next word. [C] (`21-hps-io-ioctl-and-download.md` §2 Rule 9; `32-rom-save-state-flows.md` §2.1)
- [ ] Confirm `ioctl_addr` is consumed as a 27-bit free-running counter within a transfer (does not wrap, does not segment) and is demultiplexed via `ioctl_index`. [C] (`21-hps-io-ioctl-and-download.md` §2 Rule 4)
- [ ] Confirm `ioctl_index == 0` is reserved for `boot.rom` and `ioctl_index == 255` is reserved for the cheat blob — do not reuse these slots. [C] (`21-hps-io-ioctl-and-download.md` §2 Rule 10; `32-rom-save-state-flows.md` §2.4)
- [ ] Confirm `ioctl_index` / `ioctl_file_ext` are sampled on the rising edge of `ioctl_download` (the HPS guarantees them stable then). [C] (`21-hps-io-ioctl-and-download.md` §2 Rule 11; `32-rom-save-state-flows.md` §2.1)
- [ ] Confirm `ioctl_upload_req` is core-driven: pulse it (≥1 `clk_sys` cycle) when save-RAM goes dirty, and present the bank id on `ioctl_upload_index`. [C] (`21-hps-io-ioctl-and-download.md` §2 Rule 13; `32-rom-save-state-flows.md` §2.2)
- [ ] Confirm `sd_rd[n]` and `sd_wr[n]` are held as levels and de-asserted only on the rising edge of `sd_ack[n]`. [C] (`22-hps-io-mount-and-sd.md` §2)
- [ ] Confirm `img_size` and `img_readonly` are latched into per-slot registers on the `img_mounted[n]` pulse (they are valid only that cycle). [C] (`22-hps-io-mount-and-sd.md` §2)
- [ ] Confirm `sd_lba` is driven as a sector number (LBA), not a byte offset. [C] (`22-hps-io-mount-and-sd.md` §2)
- [ ] Confirm `sd_wr[n]` is gated on `~img_readonly` so writes to read-only mounts do not silently appear to succeed. [C] (`22-hps-io-mount-and-sd.md` §2)
- [ ] Confirm sector burst sizing satisfies `(sd_blk_cnt+1) * (1 << (BLKSZ+7)) <= 16384`. [C] (`22-hps-io-mount-and-sd.md` §2)

## Gate 5: Memory placement

- [ ] Confirm `SDRAM_DQ` is `inout` and every other primary-SDRAM signal is `output`; `SDRAM_nCS/nRAS/nCAS/nWE` are active-low. [C] (`30-sdram.md` §2)
- [ ] Confirm the core supplies its own SDRAM controller (none exists in `sys/`); copy or adapt from a reference core targeting similar topology. [C] (`30-sdram.md` §2; `30-sdram.md` §7 A.1)
- [ ] Confirm the SDRAM controller's last stage on every `SDRAM_*` output is a registered driver (required by `sys/sys.tcl`'s `FAST_*_REGISTER ON` settings). [C] (`30-sdram.md` §2; `53-core-patterns.md` §7 A.4)
- [ ] Confirm the SDRAM controller issues `AUTO_REFRESH` at ≤ 7.81 µs cadence (8192 refreshes per 64 ms). [C]/[V] (`30-sdram.md` §7 A.5)
- [ ] Confirm secondary-SDRAM (when `MISTER_DUAL_SDRAM`) does NOT reference `SDRAM2_DQML`, `SDRAM2_DQMH`, or `SDRAM2_CKE` — they do not exist in the pin map. [C] (`30-sdram.md` §2)
- [ ] Confirm `DDRAM_ADDR[28:0]` is a 64-bit *word* address; byte address is `{DDRAM_ADDR, 3'b000}`. [C] (`31-ddram.md` §2)
- [ ] Confirm `DDRAM_BURSTCNT` is held in 1..255 (no bursts longer than 255 beats). [C] (`31-ddram.md` §2)
- [ ] Confirm `DDRAM_RD`/`DDRAM_WE` are only cleared when `!DDRAM_BUSY`, and `ADDR`/`DIN`/`BE` are held stable across stalls. [C] (`31-ddram.md` §2)
- [ ] Confirm `DDRAM_DOUT` is consumed only on cycles where `DDRAM_DOUT_READY=1` (read latency is variable). [C] (`31-ddram.md` §2)
- [ ] Confirm the `f2sdram_safe_terminator` is NOT bypassed when wiring custom logic to the f2sdram port. [C] (`31-ddram.md` §2)
- [ ] Confirm latency-critical state (CPU registers, audio sample buffers) lives in BRAM or SDRAM — DDRAM is high-latency. [C] (`31-ddram.md` §2)
- [ ] Confirm ROM load reset is held across the entire `ioctl_download` level — do NOT advance internal state past reset until the falling edge. [V] (`32-rom-save-state-flows.md` §2.1)
- [ ] Confirm save-state writes are ordered: payload → size word (`base+4`) → change detector (`base+0`). [C]/[I] (`32-rom-save-state-flows.md` §2.3)
- [ ] Confirm save-state "slot has data" detection keys off `header[1] != 0` (size word), NOT off the change detector. [C] (`32-rom-save-state-flows.md` §2.3)
- [ ] Confirm `SS<base>:<size>` in `CONF_STR` falls strictly inside `[0x20000000, 0x40000000)` and `size <= 128 MB`. [C] (`32-rom-save-state-flows.md` §2.3)
- [ ] Confirm every array intended to land in M10K BRAM is read through a synchronous register (`always_ff @(posedge clk) q <= mem[addr];`) and has NO asynchronous reset on the output register — combinational reads or async reset force MLAB/logic. [V] (`33-bram.md` §2)
- [ ] Confirm the BRAM shape matches the access topology: single-port for shared-master scratch/ROMs, SDP (inferred via two `always` blocks) when one master writes and another reads, TDP (explicit `altsyncram` with `operation_mode="BIDIR_DUAL_PORT"`) only when both ports need read + write. [V]/[O] (`33-bram.md` §2, §3.1)
- [ ] For two-clock SDP BRAM (e.g. `clk_sys` writer, `clk_vid` reader), confirm the array is annotated `(* ramstyle = "no_rw_check" *)` and the writer/reader never address the same word in the same cycle by construction. [V] (`33-bram.md` §2, §5.2)
- [ ] Confirm every `$readmemh`/`.mif`/`.hex` initialization file is resolvable on Quartus's `SEARCH_PATH` (project root by default) and that the elaboration log shows a "Loaded file …" line for each one. [V] (`33-bram.md` §2)
- [ ] Confirm the design's inferred + instantiated M10K usage stays within the 5CSEBA6U23I7 device's 553-block budget — audit the Fitter Resource Summary's `M10K blocks` row and the per-RAM detail table. [C] (`33-bram.md` §2, §7)
- [ ] Confirm the read-during-write assumption is explicit: for inferred SDP rely on `no_rw_check` (writer/reader collisions impossible by construction), for the TDP `altsyncram` set `read_during_write_mode_port_a/b` deliberately (`"NEW_DATA_NO_NBE_READ"` for same-port R+W; cross-port collisions remain undefined and must be partitioned away). [O] (`33-bram.md` §2, §4.3)
- [ ] Confirm tiny arrays (2–4 entries) and small ROMs are forced out of M10K with `(* ramstyle = "logic" *)` or `(* romstyle = "MLAB" *)` so they do not each consume a full 10 Kibit block. [V] (`33-bram.md` §2)

## Gate 6: Video out

- [ ] Confirm `VGA_HS` and `VGA_VS` are positive-polarity pulses (active-high during sync). [C] (`40-video.md` §2)
- [ ] Confirm `VGA_DE = ~(HBlank | VBlank)` and is high only during active pixels. [C] (`40-video.md` §2)
- [ ] Confirm `VGA_R/G/B/HS/VS/DE` update only on cycles where `CE_PIXEL` is high. [C] (`40-video.md` §2)
- [ ] Confirm `VGA_R/G/B` are 8-bit unsigned at the emu boundary. [C] (`40-video.md` §2)
- [ ] Confirm `VGA_F1` is driven per interlaced field (or tied to 0 for non-interlaced). [C]/[V] (`40-video.md` §2)
- [ ] Confirm `VIDEO_ARX[12]` / `VIDEO_ARY[12]` selects scaled-pixel mode (1) vs aspect-ratio mode (0) per intent. [C] (`10-emu-top-level.md` §2; `40-video.md` §2)
- [ ] Confirm `VGA_SL`, `VGA_F1`, `VGA_SCALER`, `VGA_DISABLE`, `HDMI_FREEZE`, `HDMI_BLACKOUT`, `HDMI_BOB_DEINT` are all driven (use Template defaults if not exposing them in OSD). [V] (`40-video.md` §2)
- [ ] If using `video_mixer` / `arcade_video`, confirm `LINE_LENGTH` ≥ the core's active pixel width per line. [C] (`40a-video-pipeline.md` §2)
- [ ] If using `arcade_video`, confirm `clk_video > 40 MHz` AND `clk_video ≥ 4 × ce_pix`. [C] (`40a-video-pipeline.md` §2)
- [ ] If advertising gamma in `CONF_STR`, confirm `video_mixer`/`arcade_video` is instantiated with `GAMMA=1` (so `gamma_bus[21]` is driven high, the presence ack). [C] (`40a-video-pipeline.md` §2)
- [ ] If using `video_freak`, confirm it is fed the pre-scandoubler `VGA_DE` (from `video_mixer.VGA_DE` or before). [C] (`40a-video-pipeline.md` §2)
- [ ] Confirm `CE_PIXEL` is a single-cycle pulse (not held wide). [C] (`40-video.md` §2; `40a-video-pipeline.md` §2)

## Gate 7: Audio out

- [ ] Confirm `AUDIO_L` and `AUDIO_R` are driven 16-bit-wide at the emu boundary. [C] (`41-audio.md` §2)
- [ ] Confirm `AUDIO_S = 1` if the core's samples are signed two's-complement; `AUDIO_S = 0` for offset-binary. [C] (`41-audio.md` §2)
- [ ] Confirm `AUDIO_L` and `AUDIO_R` are held stable for at least two `clk_audio` cycles between updates (driven from a sample-rate-clocked register, not combinationally on `clk_audio`). [C] (`41-audio.md` §2)
- [ ] Confirm `AUDIO_MIX` is driven from a 2-bit OSD option (the framework does not generate it). [C] (`41-audio.md` §2)
- [ ] Verify real per-channel samples are fed on `AUDIO_L`/`AUDIO_R` (not `AUDIO_L = AUDIO_R`), so `aud_mix_top`'s cross-channel blender works. [V] (`41-audio.md` §7 A.3)
- [ ] Confirm the framework IIR filter is left in series (do not bypass for chiptune cores — ship `*_afilter.cfg` instead). [C]/[V] (`41-audio.md` §2; `41-audio.md` §7 A.4)
- [ ] Confirm `MISTER_DISABLE_ALSA` is set ONLY when intentionally disabling Linux audio (e.g. dual-SDRAM cores). [C] (`41-audio.md` §7 A.5)

## Gate 8: Build & first power-on

- [ ] Confirm Quartus version is **17.0.x** (17.0.2 recommended); the `.qsf` records `LAST_QUARTUS_VERSION "17.0.2 Standard Edition"`. [C] (`50-build-quartus.md` §2; `53-core-patterns.md` §2 C.11)
- [ ] Confirm target device is `5CSEBA6U23I7` (Cyclone V SoC, 672-pin UFBGA, speed grade 7) and `sys/sys.tcl` is sourced from the `.qsf` — do NOT override Device via the IDE. [C] (`50-build-quartus.md` §2; `53-core-patterns.md` §2 C.14)
- [ ] Confirm Quartus `TOP_LEVEL_ENTITY` is `sys_top` (NOT `emu`). [C] (`50-build-quartus.md` §2; `53-core-patterns.md` §2 C.1)
- [ ] Confirm all user RTL is listed in `files.qip` — NOT in `<core>.qsf`. The `.qsf` header warns "Do not add files to project in Quartus IDE!" [C] (`50-build-quartus.md` §2; `53-core-patterns.md` §2 C.4)
- [ ] Confirm `<core>.qsf` sources, in order: `sys/sys.tcl`, `sys/sys_analog.tcl`, `files.qip`. [C] (`53-core-patterns.md` §2 C.6)
- [ ] Confirm `sys/sys.qip` and `pll_q*.qip` are NOT hand-edited (let `$quartus(version)` select the variant). [C] (`50-build-quartus.md` §2)
- [ ] Confirm `GENERATE_RBF_FILE ON` so `output_files/<revision>.rbf` is produced. [C] (`50-build-quartus.md` §2)
- [ ] Confirm `sys/build_id.tcl` is registered as `PRE_FLOW_SCRIPT_FILE` via `sys/sys.qip` so `build_id.v` regenerates per compile. [C] (`50-build-quartus.md` §2)
- [ ] Before tagging a release, delete `build_id.v` (or run `clean.bat`) and re-compile to refresh the date stamp. [V] (`50-build-quartus.md` §7 A.5)
- [ ] Before bring-up, simulate at the `emu` boundary (or `video_mixer.sv` output) — drop `ascal.vhd` and all VHDL from the TB. [V] (`51-simulation.md` §7 A.1, A.4)
- [ ] Before bring-up, hold reset for ≥ 1 µs of simulated time in the TB so a stubbed PLL `locked` does not release reset prematurely. [V] (`51-simulation.md` §7 A.2)
- [ ] On hardware: confirm OSD opens via F12 (or `LGUI/RGUI`+F12 with `F12KEYMOD=1`) — `OSD_STATUS` goes high. [V] (`23-osd-menu-and-input.md` §8)
- [ ] On hardware: confirm `ps2_key[10]` edge-detect fires exactly once per key press and once per release. [V] (`23-osd-menu-and-input.md` §8)
- [ ] On hardware: confirm joystick bit positions match the `CONF_STR` `J0` line and `SYS_BTN_*` ordering (right=0, left=1, down=2, up=3, A=4, B=5, X=6, Y=7, L=8, R=9, SELECT=10, START=11). [V] (`23-osd-menu-and-input.md` §8)
- [ ] On hardware: confirm analog stick at rest reads ≈ 0x00 (signed), NOT 0x80 (unsigned mis-wire). [V] (`23-osd-menu-and-input.md` §8)
- [ ] On hardware: confirm the `.rbf` file in `releases/` is named `<core_name>_YYYYMMDD.rbf` matching what the menu loads. [V] (`53-core-patterns.md` §2 C.8, C.10)
