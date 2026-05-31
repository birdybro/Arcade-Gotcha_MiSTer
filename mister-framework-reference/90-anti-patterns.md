# Anti-Patterns

> Bundle version: 2026-05-18
> Synthesized from §7 sections of topic docs 10-53.

Each entry follows: **Symptom → Cause → Fix → Citation**. The `**From:**` line records the source doc(s); where two docs raised the same anti-pattern, both are listed and the clearer phrasing is preserved.

Subsystem prefixes: `T` = top-level & framework boundary, `H` = HPS bridge, `M` = memory, `V` = video & audio, `B` = build / simulate / MRA, `X` = cross-core patterns.

## Top-level & framework boundary

### T.1 Tri-stating DDRAM outputs when not using DDR

- **Symptom:** Synthesis warnings about floating internal nets and/or the HPS f2sdram bridge entering an illegal state; on hardware, occasional core hangs at startup, especially after core-reload (`f2sdram_safe_terminator` exists explicitly because of this hazard).
- **Cause:** `DDRAM_*` signals go into an on-chip Avalon-MM bridge, **not** an external chip's pins. Tristate values are not legal on an internal port.
- **Fix:** Tie unused DDRAM outputs to `'0` exactly as the Template does: `assign {DDRAM_CLK, DDRAM_BURSTCNT, DDRAM_ADDR, DDRAM_DIN, DDRAM_BE, DDRAM_RD, DDRAM_WE} = '0;`
- **Citation:** archive/github/MiSTer-devel/Template_MiSTer/Template.sv:31 @ f35083f3b40d; archive/github/MiSTer-devel/Template_MiSTer/sys/f2sdram_safe_terminator.sv:1-15 @ f35083f3b40d
- **From:** `10-emu-top-level.md` §7 A.1

### T.2 Renaming the PLL module or instance

- **Symptom:** Quartus compiles but on hardware nothing runs / clocks are unconstrained; STA shows "unconstrained paths" and the SDC `set_clock_groups` line in `sys_top.sdc` matches nothing.
- **Cause:** `sys_top.sdc` searches `*|pll|pll_inst|altera_pll_i|*[*].*|divclk` to constrain the core PLL. Renaming either the module file (`pll.v`) or the Verilog instance breaks the SDC pattern.
- **Fix:** Keep the module named `pll` and instantiate it as `pll pll (...);`. Use the MegaWizard to *edit* the existing PLL rather than creating a new differently-named one.
- **Citation:** archive/github/MiSTer-devel/Template_MiSTer/Template.sv:112-118 @ f35083f3b40d; archive/github/MiSTer-devel/Template_MiSTer/sys/sys_top.sdc:14 @ f35083f3b40d; archive/github/MiSTer-devel/MkDocs_MiSTer/docs/developer/emu.md:13-15 @ 9033bd292fdc
- **From:** `10-emu-top-level.md` §7 A.2

### T.3 Reading USER_IN without driving USER_OUT high

- **Symptom:** `USER_IN` bits read as constant 0 (or random/noisy) regardless of the external device.
- **Cause:** `USER_OUT` is open-drain. `0` actively pulls the pin low; `1` releases it to the external pull-up. Reading `USER_IN[n]` while `USER_OUT[n]=0` always reads 0 because the core is holding the line low.
- **Fix:** Set the corresponding `USER_OUT` bit to 1 to release the pin before reading `USER_IN`. The Template default `assign USER_OUT = '1;` releases all bits.
- **Citation:** archive/github/MiSTer-devel/Template_MiSTer/sys/emu_ports.vh:145-151 @ f35083f3b40d; archive/github/MiSTer-devel/Template_MiSTer/Template.sv:27 @ f35083f3b40d
- **From:** `10-emu-top-level.md` §7 A.3

### T.4 Floating the `BUTTONS` output

- **Symptom:** Compilation warnings about uninitialized output; possible accidental "always pressed" if bits float to 1, or the OSD-button-press simulation feature simply not working.
- **Cause:** `BUTTONS` is an `output [1:0]` that sys_top ORs with the real button signals; leaving it unassigned is illegal Verilog for a module output.
- **Fix:** `assign BUTTONS = 0;` if the core does not simulate button presses (Template default).
- **Citation:** archive/github/MiSTer-devel/Template_MiSTer/Template.sv:48 @ f35083f3b40d; archive/github/MiSTer-devel/Template_MiSTer/sys/sys_top.v:234 @ f35083f3b40d
- **From:** `10-emu-top-level.md` §7 A.4

### T.5 Status bit overlap between two CONF_STR directives

- **Symptom:** Two OSD options visibly track each other; toggling one changes the other. Core misbehaves because two semantically different settings share storage.
- **Cause:** Two CONF_STR directives target the same bit (or overlapping ranges) in `status`. The framework does not warn; the last write to that bit wins. The Status Bit Map comment block exists precisely to prevent this.
- **Fix:** Maintain the Status Bit Map header. When adding `O[bit]`/`O[hi:lo]`, update the grid. Never reuse a bit across two `O`/`T`/`R` directives.
- **Citation:** archive/github/MiSTer-devel/MkDocs_MiSTer/docs/developer/conf_str.md:9,14-35 @ 9033bd292fdc
- **From:** `11-conf-str.md` §7 A.1

### T.6 Missing `v,<n>` bump after an incompatible CONF_STR change

- **Symptom:** Users boot a new build of a previously-installed core and see settings land in unexpected bit positions ("TV Mode" defaults to PAL where it used to be NTSC, "Aspect" is wrong). Visible only on machines that previously ran an older build of the same core; fresh installs are fine.
- **Cause:** The HPS persists the `status[]` snapshot between core launches. A CONF_STR change that moves option bits (additions, deletions, range edits, reorderings) without bumping the `v,<n>` integer means the HPS replays the old snapshot into the new bit layout — silently.
- **Fix:** Whenever any `O`/`T`/`R` bit assignment changes, increment the integer after `v,`. Range 0–99. Forcing defaults on first start with the new layout is the only correct cure.
- **Citation:** archive/github/MiSTer-devel/Template_MiSTer/Template.sv:83-85 @ f35083f3b40d
- **From:** `11-conf-str.md` §7 A.2; `53-core-patterns.md` §7 A.5

### T.7 Forgetting to wire `status[0]` into the reset chain

- **Symptom:** The OSD "Reset" entry does nothing — the core keeps running.
- **Cause:** `T[0],Reset;` and `R[0],Reset and close OSD;` only pulse `status[0]`. The framework does not auto-route this bit; the core must combine it into its own reset.
- **Fix:** Wire `wire reset = RESET | status[0] | buttons[1];` (or equivalent) into the core's reset chain exactly as `Template.sv` does.
- **Citation:** archive/github/MiSTer-devel/Template_MiSTer/Template.sv:120 @ f35083f3b40d; archive/github/MiSTer-devel/MkDocs_MiSTer/docs/developer/conf_str.md:37 @ 9033bd292fdc
- **From:** `11-conf-str.md` §7 A.3

### T.8 Inverted `H` vs `h` (or `D` vs `d`) polarity

- **Symptom:** Menu items appear when they should be hidden (or vice versa). Affected items often "blink" — visible when an option toggles to the wrong state.
- **Cause:** Confusing uppercase vs lowercase polarity. Uppercase (`H`/`D`) hides/disables when `menumask[Index]==1`; lowercase (`h`/`d`) hides/disables when `menumask[Index]==0`.
- **Fix:** Cross-check `Template.sv`'s idiom: `d0...F1,BIN` and `H0...O[10]` use the same `menumask[0]` bit but show the file slot when the option is set and hide the alternate option in the same state. If your menumask bit is inverted relative to the intent, flip the prefix case rather than re-wiring the source bit.
- **Citation:** archive/github/MiSTer-devel/MkDocs_MiSTer/docs/developer/conf_str.md:45-46,57-58 @ 9033bd292fdc; archive/github/MiSTer-devel/Template_MiSTer/Template.sv:70-71 @ f35083f3b40d
- **From:** `11-conf-str.md` §7 A.4

### T.9 Wrong CONF_STR prefix ordering (`P{#}d{X}...` instead of `d{X}P{#}...`)

- **Symptom:** OSD never hides the option, or never reaches the intended page. Compiles clean; silently wrong at runtime.
- **Cause:** The CONF_STR parser expects visibility prefix first, then page prefix, then the directive. `P1d5o2,...` is parsed wrong; `d5P1o2,...` is correct.
- **Fix:** Order every prefixed directive as `[H|D|h|d]{Idx}` then `P{Page}` then `O|T|R|F|S{...}`.
- **Citation:** archive/github/MiSTer-devel/MkDocs_MiSTer/docs/developer/conf_str.md:64 @ 9033bd292fdc
- **From:** `11-conf-str.md` §7 A.5

### T.10 Over-wide `status_menumask` index

- **Symptom:** `H{Index}` / `D{Index}` with `Index > 15` silently never fires (item never hides/disables).
- **Cause:** `status_menumask` is only 16 bits wide in `hps_io`. Indices outside 0..15 are not reachable.
- **Fix:** Keep `H/D/h/d` indices in 0..15. If more visibility groups are needed, route the desired status bit through to one of the 16 menumask bits via `.status_menumask({...})` in the `hps_io` instantiation.
- **Citation:** archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:122 @ f35083f3b40d
- **From:** `11-conf-str.md` §7 A.6

### T.11 Treating `RESET` as synchronous to `clk_sys`

- **Symptom:** Intermittent or board-specific reset failures: state machines sometimes don't reset cleanly, registers latch metastable values, or reset-deassert glitches re-fire one cycle later.
- **Cause:** `emu_ports.vh:4-6` documents `RESET` as async. It is generated in the `FPGA_CLK2_50` domain but propagated through `sysmem_lite` with no synchronizer guarantee at the `emu` boundary. Connecting it directly to a `posedge clk_sys` `always` block as an edge-sensitive signal violates the contract; deassertion can violate setup on `clk_sys` flops.
- **Fix:** Synchronize `RESET` into `clk_sys` with a two-flop synchronizer before use as a level (or as an async-clear input to flops that only need the asynchronous assert path). Or: combine it with `status[0] | buttons[1]` into a `reset` wire that drives a dedicated reset distribution synchronizer per clock domain.
- **Citation:** archive/github/MiSTer-devel/Template_MiSTer/sys/emu_ports.vh:4-6 @ f35083f3b40d; archive/github/MiSTer-devel/Template_MiSTer/sys/sys_top.v:582-597 @ f35083f3b40d
- **From:** `12-clocks-resets-plls.md` §7 A.1

### T.12 Resetting the user `pll` on warm reset

- **Symptom:** Every OSD reset causes a multi-millisecond freeze where the core appears hung; SDRAM/DDRAM resync; visible pixel-clock disturbance even though the framework "intends" only a soft reset.
- **Cause:** Connecting `.rst(reset_req)` or `.rst(RESET)` to the user `pll` violates Template's `.rst(0)` convention. The framework expects `clk_sys` to be free-running so warm reset is sub-second; bouncing the PLL costs the entire lock time (~100 µs to 10 ms depending on configuration) plus downstream re-synchronization.
- **Fix:** Hardwire user `pll.rst = 0` per Template. If a deliberate clock-tree restart is required, drive only the downstream synchronous reset, not the PLL reset.
- **Citation:** archive/github/MiSTer-devel/Template_MiSTer/Template.sv:113-118 @ f35083f3b40d
- **From:** `12-clocks-resets-plls.md` §7 A.3

### T.13 Using `clk_audio` for core logic

- **Symptom:** Core logic that runs on `clk_audio` (24.576 MHz) misses timing in cores expecting >24 MHz operation; cross-domain to `clk_sys` introduces latency that breaks frame timing; audio glitches when `clk_audio` and `clk_sys` race.
- **Cause:** `CLK_AUDIO` is a fixed 24.576 MHz framework-supplied clock intended for audio sample emission only. It is in a different clock domain from `clk_sys` and the framework never synchronizes them.
- **Fix:** Confine `clk_audio` to the audio sample emission path (DAC, sigma-delta, I²S writer); generate any required audio-tap CE pulses on `clk_sys` and cross sample-rate streams with proper CDC (handshake or async FIFO).
- **Citation:** archive/github/MiSTer-devel/Template_MiSTer/sys/emu_ports.vh:82 @ f35083f3b40d; archive/github/MiSTer-devel/Template_MiSTer/sys/sys_top.v:1572-1577 @ f35083f3b40d
- **From:** `12-clocks-resets-plls.md` §7 A.4

## HPS bridge

### H.1 Driving `HPS_BUS` instead of passing it through

- **Symptom:** HPS-side `Main_MiSTer` reports core magic mismatch on startup, OSD never opens, or status updates are ignored.
- **Cause:** Treating `HPS_BUS` as a regular wire bundle and reassembling it inside `emu`. `HPS_BUS` is `inout [45:0]` with bidirectional bits, and `sys_top` already builds the precise concatenation. Re-driving bits collides with `hps_io`'s assignments to `[37]`, `[36]`, `[32]`, `[15:0]`.
- **Fix:** Pass the `HPS_BUS` emu port to `hps_io.HPS_BUS` by name, unchanged. The only legal additional consumer is the optional `EXT_BUS` block.
- **Citation:** archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:38,177-194 @ f35083f3b40d; archive/github/MiSTer-devel/Template_MiSTer/sys/sys_top.v:1760-1763 @ f35083f3b40d
- **From:** `20-hps-io-overview.md` §7 A.1

### H.2 Treating `status_set` as a level

- **Symptom:** Core writes `status_in` once, but the OSD reflects only a single update or appears to "stutter" when the core attempts repeated writebacks.
- **Cause:** `status_set` is rising-edge sampled into `old_status_set`. Holding it high indefinitely increments `stflg` once and never again. Pulsing it too fast (faster than the HPS `check_status_change` poll loop) can also drop intermediate writes — the HPS only sees the latest `status_req`.
- **Fix:** Toggle `status_set` low-then-high for each new request, and budget for HPS polling latency (tens of milliseconds). For OSD-driven values, prefer letting the user change them through the menu (cmd `0x1E` write path) rather than pushing from the core.
- **Citation:** archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:283-287 @ f35083f3b40d; archive/github/MiSTer-devel/Main_MiSTer/user_io.cpp:2554-2569 @ 136737b4bed4
- **From:** `20-hps-io-overview.md` §7 A.2

### H.3 Holding `ioctl_wait` low when the core can't accept data

- **Symptom:** ROM downloads corrupt at high bus speeds; the HPS streams data faster than the core consumes it. Random bytes missing from the ROM image when SDRAM is busy (refresh cycles, contention with display fetch); CRC mismatch on the core side vs HPS-reported file_crc.
- **Cause:** `ioctl_wait` is driven directly onto `HPS_BUS[37]` and is the only handshake the HPS honors during the `FIO_FILE_TX_DAT` data stream. `ioctl_wr` is a single `clk_sys` pulse; the next strobe arrives whenever the HPS sends the next byte over SPI, which may be before the SDRAM controller has accepted the previous write. Tying `ioctl_wait` low when busy lets the HPS race ahead.
- **Fix:** Assert `ioctl_wait` high whenever the downstream consumer (SDRAM controller, decompressor, etc.) is not ready for the next `ioctl_wr` byte/word. For controllers that can always accept one byte per `clk_sys`, tie `ioctl_wait = 1'b0`.
- **Citation:** archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:191,632-634 @ f35083f3b40d; archive/github/MiSTer-devel/Template_MiSTer/sys/sys_top.v:238,256-263 @ f35083f3b40d
- **From:** `20-hps-io-overview.md` §7 A.3; `32-rom-save-state-flows.md` §7 A.1

### H.4 Sampling `RTC[63:0]` without watching `RTC[64]`

- **Symptom:** Core reads garbage time-of-day on first frame, or sees half-updated BCD fields.
- **Cause:** `RTC[63:0]` is filled 16 bits per `io_strobe` (cmd `0x22`), so intermediate cycles expose partial state. `RTC[64]` only toggles when the whole transfer completes on `io_enable` deassert.
- **Fix:** Latch `RTC[63:0]` into a core-side register only on transitions of `RTC[64]`. Same pattern applies to `TIMESTAMP[32]`.
- **Citation:** archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:164,167,311-312,499,505 @ f35083f3b40d
- **From:** `20-hps-io-overview.md` §7 A.4

### H.5 Treating `ioctl_wr` as a level

- **Symptom:** Every byte of the ROM gets written to the same address, or the ROM emerges with garbage repeated. Simulation shows `ioctl_wr` "stays high".
- **Cause:** `ioctl_wr` is a one-cycle `clk_sys` pulse (`ioctl_wr <= wr; wr <= 0;`). Code that uses `if (ioctl_wr) addr <= addr + 1;` together with a level-sensitive memory write fires once per valid word — but using it as a level-enable for a multi-cycle handshake will not.
- **Fix:** Use `ioctl_wr` strictly as a one-cycle write-enable in the `clk_sys` domain. Treat `ioctl_download` as the level signal that frames the entire transfer; treat `ioctl_wr` as the per-word strobe.
- **Citation:** archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:632-634,693 @ f35083f3b40d
- **From:** `21-hps-io-ioctl-and-download.md` §7 A.1

### H.6 Reading `ioctl_addr` on the falling edge of `ioctl_download` as "last byte address"

- **Symptom:** ROM size reported by the core is off by one, or post-load logic that uses `ioctl_addr` as the high-water mark indexes one past the last valid byte.
- **Cause:** When the HPS sends the end-of-transfer `FIO_FILE_TX` (byte 0), `hps_io` does one final `ioctl_addr <= ioctl_addr + step` in the same cycle it clears `ioctl_download`. The post-falling-edge value is "number of words written", not "address of the last word".
- **Fix:** Either (a) latch `ioctl_addr` on `ioctl_wr` (last write address) instead of on the falling edge of `ioctl_download`, or (b) subtract one step when reading `ioctl_addr` after the transfer.
- **Citation:** archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:676-680 @ f35083f3b40d
- **From:** `21-hps-io-ioctl-and-download.md` §7 A.2

### H.7 Assuming `ioctl_addr` wraps or restarts within a transfer

- **Symptom:** Loading a file larger than the core's RAM corrupts data near the wrap point, or a multi-section ROM is misaligned.
- **Cause:** `ioctl_addr` is a free-running 27-bit counter inside a single transfer; it does not wrap to 0, does not segment, and does not announce ROM-region boundaries. The HPS-side composite/multi-part logic (e.g. MRA) issues separate transfers with separate start addresses.
- **Fix:** Treat each `ioctl_download` pulse as one contiguous region. Use `ioctl_index` to demultiplex sub-files. Mask `ioctl_addr` only with bits sufficient for the target memory (and validate that the file fits).
- **Citation:** archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:671-683,688 @ f35083f3b40d
- **From:** `21-hps-io-ioctl-and-download.md` §7 A.3

### H.8 Using `ioctl_index == 0` as the "my custom slot" sentinel

- **Symptom:** Loading a custom file from an F-slot also matches `boot.rom` autoload; or a core misroutes `boot.rom` into a save-RAM region.
- **Cause:** `ioctl_index == 0` is reserved for `boot.rom` by convention; `Main_MiSTer` autoloads `boot.rom` from the core's home directory with index 0 at startup. Custom slots should use a non-zero F-slot index (`[5:0]` >= 1).
- **Fix:** Reserve `ioctl_index == 0` for `boot.rom` (or leave it unhandled). Encode custom F-slots starting at `[5:0] = 1` (`boot1.rom` uses `[5:0]=0, [15:6]=1` per framework convention).
- **Citation:** archive/github/MiSTer-devel/Main_MiSTer/user_io.cpp:1586-1590,2664 @ 136737b4bed4; archive/github/MiSTer-devel/MkDocs_MiSTer/docs/developer/hps_io.md:208,234 @ 9033bd292fdc
- **From:** `21-hps-io-ioctl-and-download.md` §7 A.4

### H.9 Forgetting to act on the rising/falling edge of `ioctl_download`

- **Symptom:** Core continues running normally during ROM load and sees half-written ROM; or the core stays in reset after load completes; or — on the direct-DDRAM path — the core fetches uninitialized DDRAM as code.
- **Cause:** `ioctl_download` is a level. A core that only edge-detects it for "go to reset" and never edge-detects the falling edge for "release reset" will hang. On the direct-DDRAM path the HPS's `shmem_map`+`read()` loop runs entirely between rising and falling edges with no per-byte signaling, so the data is not guaranteed present in memory until the falling edge.
- **Fix:** Detect both edges (`ioctl_download` rising → assert internal load-reset; `ioctl_download` falling, possibly one cycle later → release reset and begin normal operation). Apply for both SPI-streaming and direct-DDRAM paths.
- **Citation:** archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:638,676-680 @ f35083f3b40d; archive/github/MiSTer-devel/Main_MiSTer/user_io.cpp:2818-2840,2880 @ 136737b4bed4
- **From:** `21-hps-io-ioctl-and-download.md` §7 A.5; `32-rom-save-state-flows.md` §7 A.3

### H.10 Not de-asserting `sd_rd`/`sd_wr` after `sd_ack`

- **Symptom:** First sector seems to work, then the core loops on the same sector forever or fires a second spurious transfer immediately.
- **Cause:** Treating `sd_rd` as a pulse. The HPS polls the **level** every iteration of `user_io_poll`. If the core keeps `sd_rd[n]` high after `sd_ack` falls, the HPS reads the (now-old) `sd_lba` again on the next poll and re-issues the transfer.
- **Fix:** Latch the rising edge of `sd_ack[n]` and clear `sd_rd[n]`/`sd_wr[n]` on it. `sd_card.sv` shows the canonical pattern: a 3-stage `ack` shift register, deassert request on `~ack[2] & ack[1]`, advance LBA on `ack[2] & ~ack[1]`.
- **Citation:** archive/github/MiSTer-devel/Template_MiSTer/sys/sd_card.sv:190-197 @ f35083f3b40d
- **From:** `22-hps-io-mount-and-sd.md` §7 A.1

### H.11 Writing through a read-only mount

- **Symptom:** Core thinks the write succeeded (sees `sd_ack` rise and fall normally); next read of the same LBA returns old data; user reports save loss.
- **Cause:** The HPS opened the file `O_RDONLY` (because the underlying filesystem is read-only, the file is in a zipped MRA, or the file was marked read-only at mount time). It still ACKs the transfer to keep the protocol honest but never calls `FileWriteAdv`. The core ignored `img_readonly`.
- **Fix:** Latch `img_readonly` on the `img_mounted` pulse. Gate `sd_wr[n]` assertion on `~img_readonly` (or surface a write-protect error to the emulated machine).
- **Citation:** archive/github/MiSTer-devel/Main_MiSTer/user_io.cpp:2119-2211 @ 136737b4bed4; archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:129,462 @ f35083f3b40d
- **From:** `22-hps-io-mount-and-sd.md` §7 A.2

### H.12 Treating `sd_lba` as a byte offset

- **Symptom:** Image content appears scrambled at 512× the expected stride; small images read OK but large ones address beyond EOF.
- **Cause:** `sd_lba` is a logical block address. The HPS converts to byte offset internally as `lba * blksz`. Drivers that compute "address = sector * 512" and then load `sd_lba <= address` shift the data by a factor of `blksz`.
- **Fix:** Drive `sd_lba` with the sector number directly. If the emulated machine has a byte-granular cursor, divide by `blksz` before assigning.
- **Citation:** archive/github/MiSTer-devel/Main_MiSTer/user_io.cpp:3298 @ 136737b4bed4
- **From:** `22-hps-io-mount-and-sd.md` §7 A.3

### H.13 Ignoring the `img_mounted` one-cycle window for `img_size`

- **Symptom:** Core reads `img_size` at any later time and gets stale data from a previous mount, then walks off the end of the new image.
- **Cause:** `img_size` is only guaranteed valid on the same cycle `img_mounted[n]` is high — it is updated by the 0x1d command and re-overwritten by the next mount. The framework does not preserve per-slot sizes.
- **Fix:** Latch `img_size` (and `img_readonly`) into a per-slot register on the `img_mounted[n]` pulse.
- **Citation:** archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:128-130,461-466 @ f35083f3b40d
- **From:** `22-hps-io-mount-and-sd.md` §7 A.4

### H.14 Treating `ps2_key[10]` as a level (key-currently-down)

- **Symptom:** Holding a key produces continuous key events in the core, or releasing a key never registers; sometimes the same press is processed thousands of times.
- **Cause:** `ps2_key[10]` is a **toggle** that flips on every press *and* every release. It is not "1 while down, 0 while up". Code that reads `if (ps2_key[10] && ps2_key[9])` fires continuously while the bit happens to be high.
- **Fix:** Edge-detect: `reg old_ks; always @(posedge clk_sys) old_ks <= ps2_key[10]; if(old_ks != ps2_key[10]) ...`. Then act on `ps2_key[9]` (pressed flag) at the edge.
- **Citation:** archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:102-103 @ f35083f3b40d; archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:303-310 @ f35083f3b40d
- **From:** `23-osd-menu-and-input.md` §7 A.1

### H.15 Forgetting OSD-active input suppression

- **Symptom:** Pressing arrow keys or gamepad directions in the OSD menu causes the player to move in the game underneath, or the OSD's enter/start press also triggers a game action. State saves get corrupted by phantom inputs during navigation.
- **Cause:** The framework keeps streaming `ps2_key`, `joystick_*`, etc., even while the OSD is open. `OSD_STATUS` is the only level signal that says "the menu owns the input right now". Cores that don't gate on it leak menu inputs into gameplay.
- **Fix:** Gate input application (controller polling, key-state writes, edge-detected commits) on `~OSD_STATUS`, or freeze the emulated CPU/timers entirely while `OSD_STATUS` is asserted. The HPS side already partially suppresses keys but joystick presses still arrive — explicit gating is the only safe approach.
- **Citation:** archive/github/MiSTer-devel/Template_MiSTer/sys/emu_ports.vh:153 @ f35083f3b40d; archive/github/MiSTer-devel/Main_MiSTer/user_io.cpp:4197-4222 @ 136737b4bed4
- **From:** `23-osd-menu-and-input.md` §7 A.2

### H.16 Wiring `joystick_l_analog_N` as unsigned

- **Symptom:** "Half" of the analog stick works (one direction moves, the other does nothing or jumps to maximum). At-rest position is interpreted as a strong push. Dead-zone code never triggers.
- **Cause:** The HPS encodes axes as two's-complement bytes via `(char)x, (char)y` in `user_io_l_analog_joystick`. The `hps_io` output port is `[15:0]` (unsigned by default in Verilog), so comparing `lx_y[7:0] > THR` treats `0x80..0xFF` (negative values) as numbers larger than `0x7F` (positive max).
- **Fix:** Declare the consumer as signed: `wire signed [7:0] x = joystick_l_analog_0[7:0]; wire signed [7:0] y = joystick_l_analog_0[15:8];`. Use `$signed(...)` when feeding arithmetic. Compare against signed zero.
- **Citation:** archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:48-49 @ f35083f3b40d; archive/github/MiSTer-devel/Main_MiSTer/input.cpp:2630-2637 @ 136737b4bed4
- **From:** `23-osd-menu-and-input.md` §7 A.3

### H.17 Trying to instantiate `osd.v` inside the core

- **Symptom:** Duplicate-overlay artifacts (OSD appears twice or in the wrong layer), or compile errors about un-driven `io_osd`/`io_strobe` if the core attempts to hook the OSD into its video pipeline.
- **Cause:** `osd.v` is instantiated by `sys_top.v` once per output (HDMI and VGA), downstream of the core's `VGA_*` outputs and the framework's scaler/scanline path. The core's job ends at `VGA_R/G/B/HS/VS/DE`; the OSD overlay is applied by the framework.
- **Fix:** Drive `VGA_*` cleanly and do not instantiate `osd`. To know the OSD is open, consume `OSD_STATUS`.
- **Citation:** archive/github/MiSTer-devel/Template_MiSTer/sys/sys_top.v:1183-1201 @ f35083f3b40d; archive/github/MiSTer-devel/Template_MiSTer/sys/sys_top.v:1403-1422 @ f35083f3b40d
- **From:** `23-osd-menu-and-input.md` §7 A.4

## Memory

### M.1 Looking for an SDRAM controller under `sys/`

- **Symptom:** Engineer searches `Template_MiSTer/sys/` for `sdram.v`/`sdram_ctrl.sv`, finds nothing, assumes the repository is broken or the framework is incomplete.
- **Cause:** SDRAM is core-private. `sys/` exposes only pad-level ports plus pin/IO-standard assignments. There is no shared controller because timing, byte-mask policy, and clocking differ per system being emulated.
- **Fix:** Copy a controller from a reference core (NES, SNES, Genesis, etc.) that targets a similar topology, or write one. Wire its ports to the `SDRAM_*` ports inherited from `emu_ports.vh`.
- **Citation:** archive/github/MiSTer-devel/Template_MiSTer/sys/emu_ports.vh:111-136 @ f35083f3b40d; absence of `sdram*.v` under archive/github/MiSTer-devel/Template_MiSTer/sys/ @ f35083f3b40d
- **From:** `30-sdram.md` §7 A.1

### M.2 Driving SDRAM2 without gating on `SDRAM2_EN`

- **Symptom:** Core works on hardware with the dual-SDRAM daughter board installed but corrupts memory or fails timing on builds where the board is absent or single-mode is selected at runtime.
- **Cause:** `SDRAM2_EN` (driven by `io_dig` from `sys_top.v`) reports whether the secondary daughter board is electrically present. Cores that hard-drive `SDRAM2_*` outputs assume the board is there.
- **Fix:** Gate every `SDRAM2_*` output behind `SDRAM2_EN`; tri-state (`'Z`) when low, as required by the `emu_ports.vh` comment.
- **Citation:** archive/github/MiSTer-devel/Template_MiSTer/sys/emu_ports.vh:126-127 @ f35083f3b40d; archive/github/MiSTer-devel/Template_MiSTer/sys/sys_top.v:1855 @ f35083f3b40d
- **From:** `30-sdram.md` §7 A.2

### M.3 Referencing `SDRAM2_DQML`, `SDRAM2_DQMH`, or `SDRAM2_CKE`

- **Symptom:** `error: unknown port SDRAM2_DQML` at elaboration when porting a single-SDRAM controller to the secondary bus.
- **Cause:** The secondary port set is reduced — no DQM pins and no CKE. The hardware pin map (`sys_dual_sdram.tcl`) does not assign these signals to any FPGA pad.
- **Fix:** Either word-align every secondary-bus write (so no byte-mask is needed) or use the primary bus for byte-granular traffic. Treat `SDRAM2_CKE` as permanently asserted at the daughter-board level.
- **Citation:** archive/github/MiSTer-devel/Template_MiSTer/sys/emu_ports.vh:128-135 @ f35083f3b40d; archive/github/MiSTer-devel/Template_MiSTer/sys/sys_dual_sdram.tcl:4-41 @ f35083f3b40d
- **From:** `30-sdram.md` §7 A.3

### M.4 Sharing SDRAM between core and HPS

- **Symptom:** Engineer plans to land ROMs into SDRAM from `Main_MiSTer` over the HPS bus; finds no f2h/AXI path to SDRAM and no DMA target.
- **Cause:** The DE10-Nano SDR SDRAM module is physically wired to FPGA-side pins only — `sys_top.v` declares the ports as top-level FPGA pads, never inside an HPS bridge. The HPS uses DDR3 (DDRAM) for shared memory, not SDR.
- **Fix:** Deliver ROM/data through `ioctl_*` into the core, then have the core's own SDRAM controller write it to SDRAM. For shared HPS↔FPGA memory, use DDRAM (see `31-ddram.md`).
- **Citation:** archive/github/MiSTer-devel/Template_MiSTer/sys/sys_top.v:46-57 @ f35083f3b40d
- **From:** `30-sdram.md` §7 A.4

### M.5 Ignoring SDRAM auto-refresh

- **Symptom:** Core boots cleanly, runs for seconds, then accumulates random one-bit data errors that spread over time. Most pronounced on hot days or under high traffic load.
- **Cause:** SDR DRAM cells leak; the chip requires 8192 auto-refresh commands per 64 ms (tREFI ≈ 7.81 µs). A controller that never issues `AUTO_REFRESH` loses data even though every individual transaction looks correct.
- **Fix:** Build a refresh counter that asserts every ~7 µs (slightly faster than tREFI for headroom), precharges all banks, issues `AUTO_REFRESH`, then resumes normal traffic.
- **Citation:** archive/github/MiSTer-devel/Hardware_MiSTer/README.md:33 @ bbd361962005 (chip ID — refresh interval is from the `AS4C32M16` datasheet)
- **From:** `30-sdram.md` §7 A.5

### M.6 Asserting `DDRAM_RD` / `DDRAM_WE` without sampling `DDRAM_BUSY`

- **Symptom:** Intermittent dropped or duplicated transactions; the core appears to "skip" some reads/writes and other reads return data for the wrong address.
- **Cause:** Avalon-MM `waitrequest` (mapped to `DDRAM_BUSY`) means "this cycle is not accepted." If the master deasserts `RD`/`WE` while `BUSY` was high, the request never got latched; if it changes `ADDR`/`DIN` mid-stall, a later acceptance commits the wrong values.
- **Fix:** Only clear `RD`/`WE` inside an `if(!DDRAM_BUSY)` block, and hold all command/data signals stable until that cycle. The framework's own `ddr_svc.sv` is the reference.
- **Citation:** archive/github/MiSTer-devel/Template_MiSTer/sys/ddr_svc.sv:73-95 @ f35083f3b40d
- **From:** `31-ddram.md` §7 A.1

### M.7 Sampling `DDRAM_DOUT` on `DDRAM_RD` instead of `DDRAM_DOUT_READY`

- **Symptom:** Garbage read data, or what looks like a single-cycle read latency in simulation that doesn't hold up on hardware.
- **Cause:** `DDRAM_DOUT_READY` is the only valid-data marker. Read latency through `f2sdram` is variable and depends on HPS contention; assuming a fixed delay from `RD` ignores the bridge's actual behavior.
- **Fix:** Treat `DDRAM_DOUT_READY` as a per-beat strobe and consume `DDRAM_DOUT` only on the cycles it is high. For bursts of length N, expect N strobes.
- **Citation:** archive/github/MiSTer-devel/Template_MiSTer/sys/ddr_svc.sv:96-103 @ f35083f3b40d
- **From:** `31-ddram.md` §7 A.2

### M.8 Mis-aligning `DDRAM_BE` against sub-64-bit data

- **Symptom:** Writes corrupt neighboring data in the same 64-bit word; reads return data from the wrong byte lane.
- **Cause:** `DDRAM_ADDR` is a 64-bit word address. Writing a 32-bit value to byte address `A` requires (a) computing the word address `A>>3`, (b) duplicating or shifting the data into the correct half of `DDRAM_DIN`, and (c) setting `DDRAM_BE` to enable only that half (`8'h0F` low 32 bits, `8'hF0` high 32 bits). Forgetting any of those three steps writes the wrong lanes.
- **Fix:** Use the `arcade_video.v` pattern (duplicate data into both halves, select with `DDRAM_BE` based on the sub-word index).
- **Citation:** archive/github/MiSTer-devel/Template_MiSTer/sys/arcade_video.v:210-212 @ f35083f3b40d
- **From:** `31-ddram.md` §7 A.3

### M.9 Allowing reset to fire mid-burst with the safe terminator removed

- **Symptom:** After switching cores (or after a soft reset), the next core's DDRAM transactions return wrong data, time out, or hang the bridge until full HPS reboot.
- **Cause:** The SoC's `f2sdram` slave does not have a usable per-port reset path; tearing down a write burst mid-stream leaves the controller's internal counter out of sync. Per the wrapper's own header comment, this is exactly what `f2sdram_safe_terminator` exists to prevent.
- **Fix:** Never bypass `f2sdram_safe_terminator` when wiring custom logic to the f2sdram port. Feed it a synchronous reset on the same clock as the port.
- **Citation:** archive/github/MiSTer-devel/Template_MiSTer/sys/f2sdram_safe_terminator.sv:8-54 @ f35083f3b40d
- **From:** `31-ddram.md` §7 A.4

### M.10 DDRAM bursts longer than the bridge's burst-count width

- **Symptom:** The bridge accepts the first 256 beats and silently drops the rest, or wraps the counter, or hangs.
- **Cause:** `DDRAM_BURSTCNT` is 8 bits wide; the maximum single-transaction burst is 255 beats (counter cannot represent 256+).
- **Fix:** Chunk longer transfers into multiple bursts ≤ 255 beats, with separate address/command per chunk.
- **Citation:** archive/github/MiSTer-devel/Template_MiSTer/sys/emu_ports.vh:102 @ f35083f3b40d; archive/github/MiSTer-devel/Template_MiSTer/sys/sysmem.sv:14 @ f35083f3b40d
- **From:** `31-ddram.md` §7 A.5

### M.11 Treating DDRAM as low-latency RAM

- **Symptom:** CPU emulators stall waiting on DDRAM; audio underruns; framebuffer tearing.
- **Cause:** The header comment on the DDRAM port group itself says "*High latency DDR3 RAM interface — use for non-critical time purposes*." The bridge shares the DDR3 controller with Linux; HPS traffic interleaves with FPGA traffic.
- **Fix:** Keep latency-critical state in BRAM or SDRAM; use DDRAM only for bulk, prefetchable, or batched work (framebuffers, CD images, save-state blobs).
- **Citation:** archive/github/MiSTer-devel/Template_MiSTer/sys/emu_ports.vh:98-99 @ f35083f3b40d
- **From:** `31-ddram.md` §7 A.6

### M.12 Bumping the save-state change detector before the payload commits

- **Symptom:** Save-states reload as corrupted memory; OSD says "Saving" right after a save command, but the resulting `.ss` contains stale or partial data.
- **Cause:** The HPS polls `*(uint32_t*)base[i]` (the change detector) on a ~1 s cadence and flushes the slot on a delta. If the RTL state machine writes the change detector before all payload + size words have actually landed in DDRAM, the flush captures an incomplete state.
- **Fix:** Order writes payload → size word (`base+4`) → change detector (`base+0`). If the DDRAM controller reorders writes, insert an explicit drain/fence before bumping the detector.
- **Citation:** archive/github/MiSTer-devel/Main_MiSTer/user_io.cpp:1971-2008 @ 136737b4bed4; archive/github/MiSTer-devel/MkDocs_MiSTer/docs/developer/savestates.md:13-21 @ 9033bd292fdc
- **From:** `32-rom-save-state-flows.md` §7 A.2

### M.13 Reusing `ioctl_index == 255` for a non-cheat purpose

- **Symptom:** Cheats reset the wrong region; or vice versa — toggling a cheat overwrites part of the core's NVRAM.
- **Cause:** Index 255 is the framework convention for the cheat blob; `cheats_init` issues a 2-byte zero download against it at every ROM open, and `cheats_send` re-issues the full enabled blob on every toggle. A core's own custom slot at 255 will be silently clobbered by `cheats_init` even before the user enables any cheat.
- **Fix:** Reserve `ioctl_index == 255` for cheats. If the core does not support cheats, simply ignore `ioctl_download` when `ioctl_index == 255`. Use a different F-slot index for any custom payload.
- **Citation:** archive/github/MiSTer-devel/Main_MiSTer/cheats.cpp:147-152,378-385 @ 136737b4bed4
- **From:** `32-rom-save-state-flows.md` §7 A.4

### M.14 Treating "save-RAM upload" as HPS-driven

- **Symptom:** Save-RAM never reaches disk despite the OSD save command; or the core repeatedly transmits the same save bytes without HPS ever picking them up.
- **Cause:** `ioctl_upload_req` is **core-driven, not HPS-driven**. The HPS does not initiate uploads unprompted — it polls opcode `0x3C` while the OSD is open and only starts an upload after a latched rising edge of `ioctl_upload_req`. A core that waits for `ioctl_upload` to rise before signaling dirty save data deadlocks.
- **Fix:** Pulse `ioctl_upload_req` (≥1 `clk_sys` cycle) whenever save-RAM transitions from clean to dirty, and present the save bank id on `ioctl_upload_index`. The HPS reads both via opcode `0x3C` on the next OSD open; subsequently `ioctl_upload` rises and the core serves `ioctl_din` indexed by `ioctl_addr`.
- **Citation:** archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:151-155,289-290,335 @ f35083f3b40d
- **From:** `32-rom-save-state-flows.md` §7 A.5

### M.15 Treating "slot is occupied" as "change detector is non-FFFFFFFF"

- **Symptom:** Core attempts to restore from a slot that the user never saved into; payload is all zeros and the core deserializes garbage.
- **Cause:** `process_ss(rom_name)` zero-fills each slot via `memset(base[i], 0, len)` and then sets the change detector to `0xFFFFFFFF`. If the matching `<rom>_<i+1>.ss` file does not exist, the slot's size word stays at zero and the payload is all zeros, but the change detector is `0xFFFFFFFF` — not zero. A core that gates "this slot has a payload" only on the change detector incorrectly concludes an empty slot is restorable.
- **Fix:** Key "slot has data" off `header[1] != 0` (size word non-zero). The size word is loaded from the on-disk file when the slot was previously saved; for empty slots it remains zero after the memset.
- **Citation:** archive/github/MiSTer-devel/Main_MiSTer/user_io.cpp:1923-1944 @ 136737b4bed4; archive/github/MiSTer-devel/MkDocs_MiSTer/docs/developer/savestates.md:23-27 @ 9033bd292fdc
- **From:** `32-rom-save-state-flows.md` §7 A.6

### M.16 Combinational read — silently falls back to MLAB/logic

- **Symptom:** A memory the engineer expected to use M10K does not appear in the Fitter Resource Summary's M10K column; logic utilization jumps; timing closure fails for the read path; OSD-side BRAM count stays the same as before the new array was added.
- **Cause:** The read path is combinational (`assign q = mem[addr];` or `q = mem[addr]` in a non-clocked `always_comb`). Quartus only infers M10K when the read result is captured in a synchronous register clocked by the same clock that owns the write side (or the read side, for SDP). Combinational reads are mapped to MLAB or pure LUT-RAM regardless of depth.
- **Fix:** Wrap the read in a `posedge clk` always block: `always_ff @(posedge clk) q <= mem[addr];` and accept the one-cycle latency.
- **Citation:** archive/github/MiSTer-devel/Template_MiSTer/sys/hq2x.sv:260-265 @ f35083f3b40d (the correct registered-read pattern); archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:1029-1038 @ f35083f3b40d (registered read with `$readmemh`).
- **From:** `33-bram.md` §7 A.1

### M.17 Asynchronous reset on the inferred RAM's output — defeats M10K inference

- **Symptom:** Quartus's Compilation Report shows the array implemented as MLAB or logic. Synthesis warnings mention "RAM logic ... has incompatible reset" or "not inferred as block RAM because of asynchronous reset".
- **Cause:** The M10K output register supports synchronous clear only. Any `always_ff @(posedge clk or posedge rst) if (rst) q <= 0;` style on an inferred RAM cancels M10K targeting.
- **Fix:** Use synchronous reset, or — more commonly — do not reset the RAM data path at all (let the writer overwrite stale values). For initial contents, use `$readmemh` or an `initial` block. The framework's `altsyncram` instances set `outdata_aclr_a/b = "NONE"`.
- **Citation:** archive/github/MiSTer-devel/Template_MiSTer/sys/sd_card.sv:132-133 @ f35083f3b40d (explicit `outdata_aclr = "NONE"`); Intel/Altera Cyclone V Device Handbook, Embedded Memory Blocks — reset modes.
- **From:** `33-bram.md` §7 A.2

### M.18 Long shift register silently consuming M10K — `ramstyle="logic"` missing

- **Symptom:** M10K block count balloons after adding a multi-stage delay line or pixel-pipeline shift register; the count grows by far more than the obvious BRAMs would predict; the design fails to fit.
- **Cause:** Quartus recognizes a chain like `reg [W-1:0] sr[0:N-1];` with `sr[i] <= sr[i-1]` as a shift register and offers to implement it in M10K via the "Shift Register Inference" pass. For longish chains (depth > ~6), each instance consumes a full M10K block.
- **Fix:** Annotate the array declaration with `(* ramstyle = "logic" *)` (Verilog/SV) or VHDL `ATTRIBUTE ramstyle OF sig : SIGNAL IS "logic"`. The framework does exactly this in three ascal signals: `o_hfrac`, `o_hpixq`, `o_div`/`o_dir`.
- **Citation:** archive/github/MiSTer-devel/Template_MiSTer/sys/ascal.vhd:519 @ f35083f3b40d (with the comment `-- avoid blockram shift register`); archive/github/MiSTer-devel/Template_MiSTer/sys/ascal.vhd:544,552 @ f35083f3b40d.
- **From:** `33-bram.md` §7 A.3

### M.19 Tiny array left to default — wastes an M10K block

- **Symptom:** Total M10K count is higher than rough budgeting expected. The Resource Section breakdown shows several small-but-real BRAMs whose product (depth × width) is a tiny fraction of 10 Kibit each.
- **Cause:** A 2-entry × 40-bit accumulator or 4-entry × 16-bit ring buffer is large enough to trigger Quartus's automatic BRAM inference but small enough that the M10K block is > 99% empty. Each such block reduces the design's M10K budget by one.
- **Fix:** Annotate with `(* ramstyle = "logic" *)`. The framework does this in `iir_filter.v` (2 × 40 bits) and `hps_io.sv` (8 × `1<<PS2_FIFO_BITS`).
- **Citation:** archive/github/MiSTer-devel/Template_MiSTer/sys/iir_filter.v:178 @ f35083f3b40d; archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:731 @ f35083f3b40d.
- **From:** `33-bram.md` §7 A.4

### M.20 Small ROM left to default — gets M10K instead of MLAB

- **Symptom:** Same as M.19 but for read-only initialization data: a 64- or 256-entry lookup table costs a full M10K block when MLAB would suffice.
- **Cause:** Without an explicit attribute Quartus picks M10K for any read-only array with synchronous read; MLAB targeting is opt-in.
- **Fix:** Add `(* romstyle = "MLAB" *)` on the array declaration. The framework's HQ2x rule table (6 × 256 entries) uses exactly this pattern.
- **Citation:** archive/github/MiSTer-devel/Template_MiSTer/sys/hq2x.sv:35 @ f35083f3b40d.
- **From:** `33-bram.md` §7 A.5

### M.21 `$readmemh` with a relative path that Quartus cannot find

- **Symptom:** Synthesis warning "could not find file `<name>.hex` in any search path"; the ROM is silently inferred with X (or 0) contents; the core boots but behaves as if the table is empty.
- **Cause:** `$readmemh("data.hex", rom)` is resolved against Quartus's project search path (project directory + `SEARCH_PATH` entries in the `.qsf`). A nested subdirectory or a forgotten `SEARCH_PATH` assignment leaves the file invisible to elaboration. The framework's `confstr_rom` reads `"cfgstr.hex"` (bare filename) because the build emits `cfgstr.hex` into the project root.
- **Fix:** Either put the file at the project root or add `set_global_assignment -name SEARCH_PATH <dir>` to the `.qsf`. Always inspect the Quartus elaboration log for "Loaded file ..." messages corresponding to each `$readmemh`.
- **Citation:** archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:1031-1033 @ f35083f3b40d.
- **From:** `33-bram.md` §7 A.6

### M.22 Exceeding the device's 553 M10K blocks — silent fallback then logic

- **Symptom:** Fitter Report shows `M10K blocks: 553 / 553` (100%) and then a sudden swell in ALM utilization; or the fit fails with "Cannot place memory block" errors. Cores that worked in simulation refuse to bitstream.
- **Cause:** The DE10-Nano part has 553 M10K blocks. When the design's inferred BRAMs exceed that count, Quartus first tries to retarget large memories to MLAB (more LUTs per bit) and finally to pure logic; at some point placement runs out of room.
- **Fix:** Audit the Resource Summary's per-module BRAM count; convert large work RAMs to SDRAM/DDRAM (see `30-sdram.md`, `31-ddram.md`); move small ROMs to MLAB (`romstyle="MLAB"`); force tiny arrays to logic (`ramstyle="logic"`).
- **Citation:** archive/github/MiSTer-devel/Template_MiSTer/sys/sys.tcl:2 @ f35083f3b40d (DE10-Nano part identification); Intel/Altera Cyclone V Device Handbook, Embedded Memory Blocks — M10K count per the Cyclone V Device Handbook for 5CSEBA6.
- **From:** `33-bram.md` §7 A.7

## Video & audio

### V.1 Updating `VGA_R/G/B` without `CE_PIXEL` gating

- **Symptom:** Random pixel scrambling on HDMI; analog VGA looks correct on a CRT but the scaler shows torn columns or shifted pixels. Scaler shows tearing, duplicated columns, or scrambled output; OSD overlay misaligns; `pll_hdmi_adj` cannot converge (`led_locked` stays low).
- **Cause:** A pipeline register that processes `CLK_VIDEO`-domain data was clocked by `posedge CLK_VIDEO` without gating its enable on `CE_PIXEL`. Downstream `sys_top.v` mixer/OSD/scaler assume one valid sample per `CE_PIXEL` pulse, and they advance their own pointers on that strobe; advancing data without the strobe produces extra "ghost" pixels.
- **Fix:** Register `VGA_R/G/B` and only update inside `if (CE_PIXEL) begin ... end`. Or set `CLK_VIDEO` itself to the actual pixel rate (and tie `CE_PIXEL = 1'b1`). The Template's cheap pattern (`CLK_VIDEO = clk_sys`, `CE_PIXEL = ce_pix`) is the canonical reference.
- **Citation:** archive/github/MiSTer-devel/Template_MiSTer/sys/video_mixer.sv:206-216 @ f35083f3b40d; archive/github/MiSTer-devel/Template_MiSTer/sys/emu_ports.vh:14-16 @ f35083f3b40d; archive/github/MiSTer-devel/Template_MiSTer/Template.sv:149-150 @ f35083f3b40d
- **From:** `12-clocks-resets-plls.md` §7 A.2; `40-video.md` §7 A.1

### V.2 `VGA_DE` not equal to `~(HBlank | VBlank)`

- **Symptom:** ascal detects wrong image size; cropping looks off; `video_freak` aspect collapses to 0; HDMI shows partial image or stretched borders.
- **Cause:** Either DE is asserted during blanking, or DE lags HS/VS by an unexpected delay so the scaler's auto-window detection (`iauto=1`, `ascal.vhd:193`) measures the wrong active rectangle.
- **Fix:** Drive `assign VGA_DE = ~(HBlank | VBlank);` directly, or use `video_cleaner` to retime DE alongside RGB so it matches the visible window exactly. Make `HBlank` and `VBlank` positive-polarity and aligned to the same pixel cadence as the RGB stream.
- **Citation:** archive/github/MiSTer-devel/Template_MiSTer/sys/emu_ports.vh:28 @ f35083f3b40d; archive/github/MiSTer-devel/Template_MiSTer/Template.sv:152 @ f35083f3b40d
- **From:** `40-video.md` §7 A.2

### V.3 `VIDEO_ARX`/`VIDEO_ARY` scaled-size mode without setting bit [12]

- **Symptom:** Image is sized to a 12-bit "aspect ratio" of e.g. 800/600 → ascal computes a huge stretched image; OSD says aspect 4:3 (because the framework decodes [11:0] as a numerator/denominator pair).
- **Cause:** A core computed an absolute scaled pixel size (e.g. for integer scaling) and wrote it to `VIDEO_ARX[11:0]` without setting `VIDEO_ARX[12]` (or `VIDEO_ARY[12]`) to flag scaled-size mode.
- **Fix:** When delivering an absolute scaled size, set bit [12]: `VIDEO_ARX = {1'b1, width};` `VIDEO_ARY = {1'b1, height};`. `video_freak` does this automatically when `SCALE != 0`. For aspect ratio, both bit [12] stay 0 and [11:0] is the integer ratio.
- **Citation:** archive/github/MiSTer-devel/Template_MiSTer/sys/emu_ports.vh:18-21 @ f35083f3b40d; archive/github/MiSTer-devel/Template_MiSTer/sys/video_freak.sv:313-320 @ f35083f3b40d
- **From:** `40-video.md` §7 A.3

### V.4 Treating `sys_top` as a simple HDMI mux

- **Symptom:** Changing `VGA_HS`/`VGA_VS` polarity "fixes" analog but jitters HDMI OSD; or expectation that the analog 6-bit truncation also applies to HDMI.
- **Cause:** Treating `sys_top` as if it routes the core's analog `VGA_*` to both DACs. ascal is a deep reformatter: it crosses into `clk_hdmi`, scales, deinterlaces, polyphase-filters, writes DDR3, reads back, and never re-uses the analog DAC's 6-bit value. Analog and HDMI are independent sinks fed by the same `VGA_*` source.
- **Fix:** Drive `VGA_HS`/`VGA_VS` positive-polarity pulses always (the contract). Do not depend on `sys_top`'s analog-side inversions when reasoning about HDMI. Test both outputs independently.
- **Citation:** archive/github/MiSTer-devel/Template_MiSTer/sys/sys_top.v:714-820 (ascal instance), 1521-1525 (analog DAC inversion) @ f35083f3b40d
- **From:** `40-video.md` §7 A.4; `40a-video-pipeline.md` §7 A.4

### V.5 `ce_pix` held multiple cycles wide

- **Symptom:** Each source pixel rendered 2-3 times; framebuffer mode shows duplicated columns; ascal sees twice the source width.
- **Cause:** `CE_PIXEL` is a clock-enable PULSE (1 cycle per valid pixel), not a clock divider. Downstream samplers (scandoubler line 72, gamma_corr lines 37-38) are rising-edge-sensitive on `ce_pix`.
- **Fix:** Generate `CE_PIXEL` as a 1-cycle pulse per pixel. If you have a wider pulse, AND it with the inverse of a prior copy: `assign CE_PIXEL = ce_pix & ~ce_pix_d`.
- **Citation:** archive/github/MiSTer-devel/Template_MiSTer/sys/scandoubler.v:71-72 @ f35083f3b40d; archive/github/MiSTer-devel/Template_MiSTer/sys/gamma_corr.sv:37-38 @ f35083f3b40d
- **From:** `40-video.md` §7 A.5

### V.6 `CLK_VIDEO` under 40 MHz feeding scandoubler / Hq2x

- **Symptom:** Black bars between scandoubled lines; HQ2x produces garbled scaled pixels; or scandoubler passes through source unchanged.
- **Cause:** `scandoubler.v` computes `pixsz4 = pix_len >> 2` and asserts `ce_x4i` at offsets `pixsz4`, `pixsz2`, `pixsz2+pixsz4`. With `clk_vid < 4×ce_pix`, `pixsz` is 0/1/2 and the 4× cadence collapses. Framework documentation explicitly requires > 40 MHz.
- **Fix:** Add a PLL output that runs `CLK_VIDEO` at a multiple of `ce_pix × 4` and ≥ 40 MHz. For 5–6 MHz pixel clocks pick `clk_video = 48 MHz` and gate with `CE_PIXEL`. For a native 25 MHz pixel core, drive `CLK_VIDEO = 50 MHz` and `CE_PIXEL = 1` (or alternate).
- **Citation:** archive/github/MiSTer-devel/Template_MiSTer/sys/scandoubler.v:65-90 @ f35083f3b40d; archive/github/MiSTer-devel/MkDocs_MiSTer/docs/developer/emu.md:53 @ 9033bd292fdc
- **From:** `40a-video-pipeline.md` §7 A.1

### V.7 `video_freak` placed before `video_mixer`

- **Symptom:** Crop window does not match HDMI; ARX/ARY math sees scandoubled line counts; integer-scale modes produce wrong output sizes.
- **Cause:** `video_freak` measures `hsize`/`vsize` from `VGA_DE_IN`, which it expects to be the source DE before the scandoubler doubles it. Wiring scandoubled DE into `VGA_DE_IN` breaks the per-frame counters.
- **Fix:** Feed `video_freak.VGA_DE_IN` from the pre-scandoubler DE (or from `video_mixer.VGA_DE`, since that gates per `CE_PIXEL`). Read the `video_freak` per-frame counters with the same `CE_PIXEL` rate that the upstream mixer emits.
- **Citation:** archive/github/MiSTer-devel/Template_MiSTer/sys/video_freak.sv:55-71, 122 @ f35083f3b40d
- **From:** `40a-video-pipeline.md` §7 A.2

### V.8 Wiring `gamma_bus` without reading bit [21]

- **Symptom:** `hps_io` silently disables OSD gamma options; gamma menu does nothing.
- **Cause:** `video_mixer.sv:109,133` drives `gamma_bus[21]=1` only when `GAMMA=1`. `hps_io` uses this bit as the presence ack. If a core instantiates `video_mixer` with `GAMMA=0` but the OSD `CONF_STR` still advertises gamma options, the OSD will accept the user input but no LUT writes flow through.
- **Fix:** Set `GAMMA=1` when instantiating `video_mixer`/`arcade_video` if you advertise gamma in `CONF_STR`. Conversely, drop the gamma `CONF_STR` options when `GAMMA=0`.
- **Citation:** archive/github/MiSTer-devel/Template_MiSTer/sys/video_mixer.sv:108-137 @ f35083f3b40d
- **From:** `40a-video-pipeline.md` §7 A.3

### V.9 `AUDIO_S = 0` with signed two's-complement samples

- **Symptom:** Silence on power-up replaced by a loud thump that decays over ~1-2 seconds, then heavy DC bias on quiet passages. Headphones may pop. The DC blocker eventually settles.
- **Cause:** `audio_out.sv:217-218` does `{~is_signed ^ cl[15], cl[14:0]}`. With `is_signed=0` and a signed core sample, the MSB is XOR-inverted: `0x0000` becomes `0x8000` (−32768), turning silence into the negative rail.
- **Fix:** Set `AUDIO_S = 1` if the core's samples are signed two's-complement (the modern convention). Otherwise convert your samples to offset-binary (`sample + 16'h8000`) and keep `AUDIO_S = 0`.
- **Citation:** archive/github/MiSTer-devel/Template_MiSTer/sys/audio_out.sv:217-218 @ f35083f3b40d
- **From:** `41-audio.md` §7 A.1

### V.10 Updating `AUDIO_L/R` on every `CLK_AUDIO` edge

- **Symptom:** Total silence on I²S, S/PDIF, and analog jacks even though the core's internal sample counter is incrementing.
- **Cause:** `audio_out` waits for `cl1 == cl2` (two consecutive `clk` cycles with the same value) before committing `cl <= cl2`. If the core feeds new samples on every `CLK_AUDIO` edge (e.g. by combinationally routing a free-running DSP at `clk_audio` to `AUDIO_L`), the synchroniser never sees agreement.
- **Fix:** Drive `AUDIO_L/R` from a register that updates only on the core's sample-rate clock enable (typically 44.1/48 kHz, or your DSP rate divided down). Hold the previous value between updates.
- **Citation:** archive/github/MiSTer-devel/Template_MiSTer/sys/audio_out.sv:164-174 @ f35083f3b40d
- **From:** `41-audio.md` §7 A.2

### V.11 Hardcoding `AUDIO_L = AUDIO_R` and ignoring `AUDIO_MIX`

- **Symptom:** Stereo cores sound spatially correct but users with mono speakers/headphones complain that some content vanishes; OSD mix option has no effect.
- **Cause:** Tying both channels to one stream defeats `aud_mix_top`'s cross-channel blender — there is no opposite-channel content for case 1/2/3 to fold in, so the option becomes a no-op.
- **Fix:** Feed real per-channel samples on `AUDIO_L`/`AUDIO_R`, expose `AUDIO_MIX` from a 2-bit OSD option (`O[bit:bit]`), and let `aud_mix_top` perform the blend.
- **Citation:** archive/github/MiSTer-devel/Template_MiSTer/sys/audio_out.sv:281-341 @ f35083f3b40d
- **From:** `41-audio.md` §7 A.3

### V.12 Skipping the framework filter for chiptune cores

- **Symptom:** S/PDIF and HDMI audio sound buzzy with stair-step artefacts above ~10 kHz; analog jack sounds harsher than expected.
- **Cause:** Square-wave generators output values that change instantaneously at the core's sample rate. Without the framework's 3-tap IIR LPF (default `LPF20000.txt`, ≈20 kHz Fc), images of the sample rate alias into the audio band when the chain upsamples to 48/96 kHz.
- **Fix:** Do not bypass the framework filter. If a custom curve is desired, ship a `*_afilter.cfg` and a matching `*.txt` (format per `LPF20000.txt`) so the HPS loads coefficients into `acx/acy*` over `UIO_SET_AFILTER`.
- **Citation:** archive/github/MiSTer-devel/Template_MiSTer/sys/iir_filter.v:22-52 @ f35083f3b40d; archive/github/MiSTer-devel/Main_MiSTer/LPF20000.txt:1-27 @ 136737b4bed4; archive/github/MiSTer-devel/Main_MiSTer/audio.cpp:39-119 @ 136737b4bed4
- **From:** `41-audio.md` §7 A.4

### V.13 Forgetting the `MISTER_DISABLE_ALSA` gate

- **Symptom:** Build succeeds but ALSA-from-HPS audio (system bell, MT32-pi over USB-audio, web-radio plugins) is silent; some boards report fitter errors on `alsa_l/alsa_r` nets.
- **Cause:** The `alsa` module and the SPI master in `sys_top.v:1619-1657` are inside `` `ifndef MISTER_DISABLE_ALSA ``. If a core forces the macro on for an unrelated reason, those nets are floating.
- **Fix:** Only set `MISTER_DISABLE_ALSA` when intentionally disabling Linux audio (e.g. dual-SDRAM cores that need the SPI master for something else).
- **Citation:** archive/github/MiSTer-devel/Template_MiSTer/sys/sys_top.v:1603-1657 @ f35083f3b40d
- **From:** `41-audio.md` §7 A.5

## Build, simulate, MRA

### B.1 Adding files via Quartus IDE instead of `files.qip`

- **Symptom:** Files are added "successfully" but later builds fail to find them, or `<core>.qsf` swells with hundreds of lines of duplicated settings, or `git diff` of `<core>.qsf` is enormous and impossible to review. New sources appear under random sections of `<core>.qsf`; subsequent framework updates that rewrite the `.qsf` lose them.
- **Cause:** The Quartus IDE's file-add dialog writes `set_global_assignment -name SYSTEMVERILOG_FILE <path>` lines into `<core>.qsf`, not `files.qip`. On subsequent saves Quartus "spits" all settings (defaults, pin assignments, etc.) from sourced Tcl back into `<core>.qsf`, turning it into a noisy mess. The framework expects user sources to live in `files.qip` and `<core>.qsf` to remain a near-verbatim copy of `Template.qsf`.
- **Fix:** Edit `files.qip` by hand. Add one `set_global_assignment -name VERILOG_FILE rtl/<new>.v` (or `SYSTEMVERILOG_FILE`/`VHDL_FILE`) line per source. Re-open the Quartus project to pick up the new files. If `<core>.qsf` is polluted, revert to the upstream `Template.qsf` and migrate any user-meaningful changes (e.g. uncommented `VERILOG_MACRO` lines) by hand.
- **Citation:** archive/github/MiSTer-devel/Template_MiSTer/Template.qsf:5-7 @ f35083f3b40d; archive/github/MiSTer-devel/Template_MiSTer/files.qip:1-5 @ f35083f3b40d; archive/github/MiSTer-devel/Template_MiSTer/Readme.md:20-24 @ f35083f3b40d
- **From:** `50-build-quartus.md` §7 A.1; `53-core-patterns.md` §7 A.3

### B.2 Forgetting to bump `files.qip` after adding RTL

- **Symptom:** New module compiles in isolation in a separate simulation flow but Quartus reports `Error: Verilog HDL syntax error … undefined symbol` or `Can't elaborate top-level user hierarchy`. Synthesis silently skips the new module.
- **Cause:** Source not listed in `files.qip` (or any other `.qip` sourced by `.qsf`) is never seen by `quartus_map`. The IDE shows the file as "present" because it was opened in the editor, but presence in the editor does not equal presence in the project manifest.
- **Fix:** Add the file to `files.qip` (or to a `<sub>.qip` already referenced by `files.qip`). After editing `files.qip`, close and reopen the project, or run `Processing → Update Memory Initialization File` to refresh the file list.
- **Citation:** archive/github/MiSTer-devel/Template_MiSTer/files.qip:1-5 @ f35083f3b40d
- **From:** `50-build-quartus.md` §7 A.2

### B.3 Targeting the wrong Cyclone V part

- **Symptom:** Fitter fails with "Cannot place pin … because the I/O standard is not supported on this device" or "Device has no matching package/pin" errors against `SDRAM_*`, `HDMI_TX_*`, or `HPS_*` instances. Pin assignments from `sys/sys.tcl` are rejected.
- **Cause:** A user manually changed the device in Quartus → Assignments → Device, overriding `sys/sys.tcl:2`. The DE10-Nano part is `5CSEBA6U23I7` (672-pin UFBGA, speed grade 7); any other Cyclone V variant will not match the pin map in `sys.tcl` + `sys_analog.tcl` + `sys_dual_sdram.tcl` and the `HPS_LOCATION` assignments in `Template.qsf:212-214`.
- **Fix:** Do not change the device. If a build mysteriously fails on pin assignments, restore `sys/sys.tcl` from upstream and remove any conflicting `set_global_assignment -name DEVICE …` from the `.qsf`.
- **Citation:** archive/github/MiSTer-devel/Template_MiSTer/sys/sys.tcl:1-5 @ f35083f3b40d; archive/github/MiSTer-devel/Template_MiSTer/Template.qsf:212-214 @ f35083f3b40d
- **From:** `50-build-quartus.md` §7 A.3

### B.4 Mixing Q13 and Q17 PLL `.qip` files

- **Symptom:** "Entity `altera_pll` is multiply defined" or "Cannot resolve PLL output `outclk_0`" elaboration errors. PLL inferred but downstream clocks dead at runtime.
- **Cause:** Hand-editing `sys.qip` or `pll_q17.qip`/`pll_q13.qip` to load the wrong variant for the active Quartus version. The version selector at `sys.qip:1` is supposed to pick exactly one of `pll_q17.qip` or `pll_q13.qip`; bypassing it by manually listing both pulls in two incompatible PLL IP cores at once.
- **Fix:** Do not edit `sys/sys.qip` or the `pll_q*.qip` files. Let `$quartus(version)` resolve the selector. If a core needs a custom PLL frequency, regenerate `rtl/pll.v`+`rtl/pll.qip` from MegaWizard and recompile on Q17.
- **Citation:** archive/github/MiSTer-devel/Template_MiSTer/sys/sys.qip:1 @ f35083f3b40d; archive/github/MiSTer-devel/Template_MiSTer/sys/pll_q17.qip:1 @ f35083f3b40d; archive/github/MiSTer-devel/Template_MiSTer/sys/pll_q13.qip:1 @ f35083f3b40d
- **From:** `50-build-quartus.md` §7 A.4

### B.5 Not bumping `build_id` and shipping a stale `.rbf`

- **Symptom:** Released `.rbf` reports an outdated build date in the OSD About / version readout. Users believe they have an older build than they do, or the same date stamp appears in two distinct releases.
- **Cause:** `sys/build_id.tcl` rewrites `build_id.v` only when the date string differs; same-day re-compiles preserve the existing macro. If the released `.rbf` is produced from an unclean tree (e.g. forgot to re-run the compile after a fix), the embedded date is yesterday's.
- **Fix:** Always do a fresh compile before tagging a release. Optionally `del build_id.v` (or `rm build_id.v`) before the final compile so the next pre-flow regenerates it from today's clock. The `clean.bat` script already removes `build_id.v` for full rebuilds.
- **Citation:** archive/github/MiSTer-devel/Template_MiSTer/sys/build_id.tcl:5-26 @ f35083f3b40d; archive/github/MiSTer-devel/Template_MiSTer/clean.bat:18 @ f35083f3b40d
- **From:** `50-build-quartus.md` §7 A.5

### B.6 Simulating `ascal.vhd` (full HDMI scaler) in the testbench

- **Symptom:** Simulation throughput collapses to a few hundred Hz of `clk_sys`; a single frame takes minutes to hours.
- **Cause:** `ascal.vhd` is a large adaptive scaler with internal frame buffers and polyphase filters; it executes orders of magnitude more events per `clk_sys` tick than `emu` itself, and is VHDL (incompatible with free Verilator).
- **Fix:** Drop `ascal.vhd` from the TB build. Observe video at the pre-scaler boundary (`VGA_R/G/B/HS/VS/DE` from `emu`, or `video_mixer.sv`'s output). Frame-compare at that interface, not at HDMI output.
- **Citation:** archive/github/MiSTer-devel/Template_MiSTer/sys/ascal.vhd:1-30 @ 9033bd292fdc
- **From:** `51-simulation.md` §7 A.1

### B.7 Treating PLLs as instantaneous (zero-cycle lock) in simulation

- **Symptom:** Reset releases before the core's internal clocks would have stabilised in hardware; downstream synchronous logic exhibits TB-only behaviour that disappears in the bitstream.
- **Cause:** `sys/pll_*.v` are Altera megafunction wrappers; in simulation they are replaced by a behavioural clock generator, and the `locked` output is tied high immediately. Reset deassertion gated on `locked` fires earlier in TB than in hardware.
- **Fix:** Either drive `clk_sys` with a small but realistic startup delay before deasserting reset (≥ 1 µs of simulated time), or hold reset for a fixed cycle count that mirrors the hardware sequence. Do not gate TB reset on a stubbed PLL `locked`.
- **Citation:** archive/github/MiSTer-devel/Template_MiSTer/sys/pll_audio.v, sys/pll_hdmi.v (megafunction wrappers, not behavioural models) @ f35083f3b40d
- **From:** `51-simulation.md` §7 A.2

### B.8 Modeling the SDRAM controller as zero-latency RAM in simulation

- **Symptom:** Core works under TB, fails on hardware with corrupted ROM reads or scrambled video tiles; sometimes only at specific PLL frequencies.
- **Cause:** The real SDRAM controller has multi-cycle CAS latency, refresh cycles, and arbitration between multiple ports. A behavioural stub that returns data combinatorially on `addr` hides timing assumptions in the core.
- **Fix:** Use a behavioural SDRAM model that mimics CAS latency (typically 2–3 cycles) and busy/ready handshake. At minimum, return data on the second cycle after `req`. Where possible, simulate against the actual `sdram.v` from the core's `rtl/`.
- **Citation:** archive/github/MiSTer-devel/Template_MiSTer/Template.sv:30 @ f35083f3b40d (SDRAM pin set tie-off in the template)
- **From:** `51-simulation.md` §7 A.3

### B.9 Trusting Verilator to compile every `sys/` file

- **Symptom:** Verilator emits `error: Unsupported: SystemVerilog 2005/...` on `sys/f2sdram_safe_terminator.sv`, `sys/yc_out.sv`, or VHDL `sys/ascal.vhd` / `sys/pll_hdmi_adj.vhd`.
- **Cause:** Verilator is Verilog/SystemVerilog only and has version-dependent gaps in SV interface, packed-struct, and `always_comb` corner cases. VHDL files cannot be processed at all.
- **Fix:** Build the TB only against the modules the test exercises. Drop all VHDL. Pin a recent Verilator (≥ 4.2x) for SV interface support. For mixed-language sims use ModelSim/Questa; for pure-SV cores Verilator is preferred for speed.
- **Citation:** File listing of archive/github/MiSTer-devel/Template_MiSTer/sys/ @ f35083f3b40d shows `.v`, `.sv`, and `.vhd` mixed
- **From:** `51-simulation.md` §7 A.4

### B.10 Wrong MRA `<part>` order

- **Symptom:** ROM looks correct in size and MD5 may even match if you regenerated it, but the core jumps to garbage, shows wrong tiles, or hangs at boot.
- **Cause:** Parts are concatenated in document order and the core's address decoder is hardcoded to specific offsets. Swapping two `<part>` lines moves every byte after the swap by the size delta.
- **Fix:** Take part order from the upstream `mame/src/mame/drivers/*.cpp` `ROM_LOAD` sequence (or copy from a known-good MRA for the same hardware). Verify with the `<rom md5>` against a trusted reference.
- **Citation:** archive/github/MiSTer-devel/Main_MiSTer/support/arcade/mra_loader.cpp:853-880 @ 136737b4bed4
- **From:** `52-mra-and-arcade.md` §7 A.1

### B.11 `<part repeat="N">` treated as iteration count

- **Symptom:** Inline fill region is the wrong size; later parts misaligned by a small offset; "ROM #0: file_finish: 0xN bytes sent" log line shows wrong total.
- **Cause:** `repeat` is the total byte length to emit, not the number of times to repeat the literal. `<part repeat="3">FF</part>` emits 3 bytes; `<part repeat="0x4000">FF</part>` emits 16384 bytes. The literal `FF` is the fill pattern, replayed as needed.
- **Fix:** Use the byte count you actually want. For non-`FF` fills, the literal can be a multi-byte sequence — `<part repeat="0x10">DEADBEEF</part>` emits 16 bytes by truncating the 4-byte pattern.
- **Citation:** archive/github/MiSTer-devel/MkDocs_MiSTer/docs/developer/mra.md:124 @ 9033bd292fdc; archive/github/MiSTer-devel/Main_MiSTer/support/arcade/mra_loader.cpp:584-586,900-934 @ 136737b4bed4
- **From:** `52-mra-and-arcade.md` §7 A.2

### B.12 MRA DIP `<dip bits>` overlapping a CONF_STR `O[..]` bit

- **Symptom:** Changing one OSD option silently flips another; status bits drift; behaviour depends on which OSD entry was touched last.
- **Cause:** CONF_STR `O[N]` writes the framework `status[N]` word; `<dip bits="N">` writes the same numeric bit but in a *different* word that arrives on `ioctl_index=254`. If the core wires both into the same destination register or if the developer chose the same bit index, the two channels race.
- **Fix:** Reserve disjoint bit ranges in your core. Common convention: `status[31:0]` for CONF_STR options, MRA DIPs land in their own `sw[8]` register array gated on `ioctl_index==254`. Do not redeclare the same setting in both layers.
- **Citation:** archive/github/MiSTer-devel/Main_MiSTer/support/arcade/mra_loader.cpp:120-130 @ 136737b4bed4; archive/github/MiSTer-devel/MkDocs_MiSTer/docs/developer/mra.md:132-138 @ 9033bd292fdc
- **From:** `52-mra-and-arcade.md` §7 A.3

### B.13 No ZIP-list fallback when MAME renames files

- **Symptom:** Existing MRA stops loading after a MAME version bump; "file not found" error referencing a file name that does still exist (under a different ZIP).
- **Cause:** MAME renames its ZIPs across versions (e.g. `puckman.zip` ↔ `pacman.zip`). A `<rom zip="pacman.zip">` with no fallback fails when the user has the older ZIP name.
- **Fix:** Use the pipe-list form `<rom zip="puckman.zip|pacman.zip">`. The loader walks left-to-right and uses the first ZIP that resolves the part. Also set `<part crc="...">` so the loader can pick the right file by CRC even if MAME renamed a single ROM inside the ZIP.
- **Citation:** archive/github/MiSTer-devel/Main_MiSTer/support/arcade/mra_loader.cpp:882-921 @ 136737b4bed4
- **From:** `52-mra-and-arcade.md` §7 A.4

### B.14 MRA `map` without an `<interleave>` parent

- **Symptom:** ROM image is sparse / mostly zeros / the core indexes correct bytes but they read as 0xFF or 0x00; size of `romdata[]` is unexpectedly large.
- **Cause:** A `<part map=>` outside `<interleave>` triggers the "8-stream pre-sized" path: the loader replicates `romlen[0]` into `romlen[1..7]` once at parse time, but each `map` byte still lands at its own lane offset. Without sibling parts filling the other lanes, those bytes stay as whatever was already in `romdata[]` (often unmapped/zero or the previous data's tail).
- **Fix:** Wrap byte-multiplexed parts in `<interleave output="N">` with `N` matching the total lane width. For a single-lane copy without interleaving, omit `map` entirely.
- **Citation:** archive/github/MiSTer-devel/Main_MiSTer/support/arcade/mra_loader.cpp:600-609,749-774 @ 136737b4bed4
- **From:** `52-mra-and-arcade.md` §7 A.5

## Cross-core patterns

### X.1 Editing files in `sys/`

- **Symptom:** Local fixes / experiments work in the current build. Then a framework update is pulled (or `Template_MiSTer` is re-synced) and every change in `sys/` is silently erased; bugs return; cores may stop compiling.
- **Cause:** `sys/` is shared verbatim across all cores in the MiSTer-devel organization. The framework's update process is a directory copy, not a merge. Any local change to `sys/hps_io.sv`, `sys/sys_top.v`, `sys/video_mixer.sv`, etc. will be lost on next sync.
- **Fix:** If the core genuinely needs a tweak to framework behaviour, either (a) configure it via an existing `VERILOG_MACRO` and `hps_io` parameter (e.g. `VDNUM`, `BLKSZ`, `WIDE`, `PS2DIV`, `CONF_STR_BRAM`), or (b) raise it upstream so it lands in the framework for everyone. Never patch `sys/`. The `Readme.md` is explicit: "Basically it's prohibited to change any files in this folder. Framework updates may erase any customization in this folder."
- **Citation:** archive/github/MiSTer-devel/Template_MiSTer/Readme.md:14 @ f35083f3b40d
- **From:** `53-core-patterns.md` §7 A.1

### X.2 Starting from a blank Quartus project instead of `Template_MiSTer`

- **Symptom:** Various combinations of: `sys_top` not found; unconstrained clocks; PLL never locks; HDMI pixel clock disappears; `sys/sys.tcl` complains about missing IO standards; build fails halfway through with cryptic Tcl errors; or compile succeeds but the `.rbf` does nothing on hardware.
- **Cause:** The MiSTer framework is not a Quartus IP catalogue plug-in — it is a *project layout* with very specific entry points (`TOP_LEVEL_ENTITY sys_top`, `source sys/sys.tcl`, `source sys/sys_analog.tcl`, `source files.qip`), generated artifacts (`build_id.v`, `jtag.cdf`), per-Quartus-version PLL dispatch (`pll_q[regexp].qip`), and dozens of pin assignments. Re-creating these from a blank project takes longer than just copying `Template_MiSTer`, and missing any one of them produces an opaque failure.
- **Fix:** Start by copying the entire `Template_MiSTer` directory tree. Rename project files (`Template.qpf`, `Template.qsf`, `Template.srf`, `Template.sdc`, `Template.sv` → `<core_name>.*`), then search-and-replace the literal "Template" inside those files. Trim `files.qip` to remove the Template demo RTL. Compile *before* adding your own RTL to confirm the project still builds.
- **Citation:** archive/github/MiSTer-devel/Template_MiSTer/Readme.md:8-22 @ f35083f3b40d; archive/github/MiSTer-devel/Template_MiSTer/Template.qsf:11,76-78 @ f35083f3b40d; archive/github/MiSTer-devel/MkDocs_MiSTer/docs/developer/porting.md:8-23 @ 9033bd292fdc
- **From:** `53-core-patterns.md` §7 A.2

### X.3 Importing a non-MiSTer SDRAM controller

- **Symptom:** SDRAM reads/writes work for some access patterns and corrupt for others; ghosting on burst boundaries; timing closure fails or barely passes; warning about combinatorial logic on `SDRAM_*` pad paths being retimed unexpectedly.
- **Cause:** MiSTer's `sys/sys.tcl` pins every `SDRAM_*` signal at `FAST_OUTPUT_REGISTER ON`, `FAST_INPUT_REGISTER ON` (on `SDRAM_DQ`), and `FAST_OUTPUT_ENABLE_REGISTER ON` (on `SDRAM_DQ`). It also sets `ALLOW_SYNCH_CTRL_USAGE OFF` to forbid synchronous-control implementation of the IOEs. A controller designed for a different board (e.g. a generic `sdram.v` from a MiST core, a SoC dev-board reference design, or a verilog-hdl repo) typically expects the synthesizer to insert IO registers itself and may carry combinatorial logic into the pad path. On MiSTer, that logic gets retimed into the IOE flip-flop, breaking the controller's internal timing assumptions.
- **Fix:** Use a MiSTer-style SDRAM controller — one whose last stage on every `SDRAM_*` output is a flip-flop in the user logic (so the IOE register is the second one and timing is predictable), and whose `SDRAM_DQ` tri-state enable is driven by a single dedicated register (so `FAST_OUTPUT_ENABLE_REGISTER ON` has a single legal IOE to inhabit). Reference cores carry their own `rtl/sdram.v` matching this pattern; do not paste in a controller from a non-MiSTer project. If a port is required, audit every output for combinatorial paths and convert them to registered drivers before bring-up.
- **Citation:** archive/github/MiSTer-devel/Template_MiSTer/sys/sys.tcl:53-98 @ f35083f3b40d
- **From:** `53-core-patterns.md` §7 A.4
