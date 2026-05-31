# 22 - hps_io Mount Slots & SD Block IO

> Bundle version: 2026-05-18
> Pinned commits: Template_MiSTer @ f35083f3b40d, Main_MiSTer @ 136737b4bed4
> Load with: [20-hps-io-overview.md](20-hps-io-overview.md), [21-hps-io-ioctl-and-download.md](21-hps-io-ioctl-and-download.md), [11-conf-str.md](11-conf-str.md), [32-rom-save-state-flows.md](32-rom-save-state-flows.md)
> Status mix: [C] [V] [O] [I]

## 1. Purpose & one-line summary

The `S<index>` mount slot system exposes user-selected files (floppies, hard disks, CDs) to the core as block devices. Unlike the `F<index>` ROM path (a one-shot linear stream delivered through `ioctl_*` — see [21-hps-io-ioctl-and-download.md](21-hps-io-ioctl-and-download.md)), mounts stay live: the core issues per-sector read/write requests against `sd_lba`/`sd_rd`/`sd_wr` and the HPS services them on demand. Each mount survives until ejected or replaced from the OSD.

## 2. The contract (must-obey)

- `hps_io` is parameterized with `VDNUM` (1..10) declaring the number of mount slots; `VD = VDNUM - 1` is the vector top index for slot-vector signals. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:35,182 @ f35083f3b40d)
- `BLKSZ` parameter sets the block (sector) size as `128 << BLKSZ` bytes; default `BLKSZ=2` is 512 B; legal range is 0..7 giving 128..16384 B. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:28,35 @ f35083f3b40d)
- A mount is announced by a one-cycle pulse on `img_mounted[n]` after the HPS sends image info; the bit is auto-cleared the next cycle `io_enable` is low. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:318,461 @ f35083f3b40d)
- `img_size` (64-bit byte count) and `img_readonly` are valid only on the cycle the matching `img_mounted` bit is asserted; the core must latch them at that moment. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:128-130,461-466 @ f35083f3b40d)
- An empty mount (image ejected) is signaled by `img_mounted` pulsing with `img_size == 0`; `img_mounted` defaults to 1 on slot 0 if the HPS sends a zero slot mask. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:461 @ f35083f3b40d)
- `sd_rd[n]` and `sd_wr[n]` are level signals: the core asserts and **holds** until it sees `sd_ack[n]` rise, then de-asserts. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/sd_card.sv:190-197 @ f35083f3b40d)
- `sd_ack[n]` is asserted by `hps_io` when the HPS issues `UIO_SECTOR_RD` (0x17) or `UIO_SECTOR_WR` (0x18) for slot `n`, and is cleared automatically when `io_enable` falls (transfer complete). [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:315,331 @ f35083f3b40d)
- `sd_lba` is per-slot: indexed as `sd_lba[VDNUM]` and addresses sectors (not bytes); on disk it maps to byte offset `lba * blksz`. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:133 @ f35083f3b40d; archive/github/MiSTer-devel/Main_MiSTer/user_io.cpp:3298 @ 136737b4bed4)
- `sd_buff_din` is per-slot (`sd_buff_din[VDNUM]`); during a write the framework reads from the slot identified by the in-flight `UIO_SECTOR_WR` index (`sdn_ack`). [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:142,412 @ f35083f3b40d)
- `sd_buff_dout` and `sd_buff_addr` are shared across slots; only the slot whose `sd_ack` is asserted should consume them. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:140-141,295-296,405 @ f35083f3b40d)
- `sd_buff_wr` is a one-cycle pulse per accepted byte (or 16-bit word in WIDE mode) of an incoming sector; `sd_buff_addr` auto-increments after the pulse. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:295-297 @ f35083f3b40d)
- `sd_blk_cnt[n]` (6 bits, per slot) reports `blocks_minus_one`; total burst bytes `(sd_blk_cnt+1) * (1 << (BLKSZ+7))` must be `<= 16384`. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:134 @ f35083f3b40d)
- `img_readonly` is sourced from `io_din[7]` of the mount command (`UIO_SET_SDSTAT`, 0x1c); HPS sets bit 0x80 when the file cannot be opened read-write. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:462 @ f35083f3b40d; archive/github/MiSTer-devel/Main_MiSTer/user_io.cpp:2119,2211 @ 136737b4bed4)
- The HPS polls `UIO_GET_SDSTAT` (0x16) and picks the slot to service via a round-robin priority encoder over `sd_rd | sd_wr`. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:204-215,329 @ f35083f3b40d)
- Mount notification is byte-ordered: HPS first sends `UIO_SET_SDINFO` (0x1d, the 64-bit size) **then** `UIO_SET_SDSTAT` (0x1c, the slot mask + RO flag). Reordering breaks the contract because `img_size` must be valid on the cycle `img_mounted` is high. [C] (archive/github/MiSTer-devel/Main_MiSTer/user_io.cpp:2188-2211 @ 136737b4bed4)
- The UIO command codes referenced above (0x16 GET_SDSTAT, 0x17 SECTOR_RD, 0x18 SECTOR_WR, 0x1c SET_SDSTAT, 0x1d SET_SDINFO) are defined in `user_io.h`. [C] (archive/github/MiSTer-devel/Main_MiSTer/user_io.h:33-39 @ 136737b4bed4)

See also: the S-slot `CONF_STR` grammar (`S<i>,...`) that declares slot indices on the OSD side is covered in [11-conf-str.md](11-conf-str.md) and is out of scope here.

## 3. Ports / signals reference

```verilog
// archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:127-143 @ f35083f3b40d
	// SD config
	output reg [VD:0] img_mounted,  // signaling that new image has been mounted
	output reg        img_readonly, // mounted as read only. valid only for active bit in img_mounted
	output reg [63:0] img_size,     // size of image in bytes. valid only for active bit in img_mounted

	// SD block level access
	input      [31:0] sd_lba[VDNUM],
	input       [5:0] sd_blk_cnt[VDNUM], // number of blocks-1, total size ((sd_blk_cnt+1)*(1<<(BLKSZ+7))) must be <= 16384!
	input      [VD:0] sd_rd,
	input      [VD:0] sd_wr,
	output reg [VD:0] sd_ack,

	// SD byte level access. Signals for 2-PORT altsyncram.
	output reg [AW:0] sd_buff_addr,
	output reg [DW:0] sd_buff_dout,
	input      [DW:0] sd_buff_din[VDNUM],
	output reg        sd_buff_wr,
```

Width derivation: `DW = WIDE ? 15 : 7`, `AW = WIDE ? 12 : 13`, `VD = VDNUM-1`. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:180-182 @ f35083f3b40d)

| Signal | Dir | Width | Clock | Active | Meaning | Driven by | Drives |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `img_mounted[VD:0]` | output | `VDNUM` | `clk_sys` | high, one-cycle | Slot-mask pulse: image just mounted (or ejected if `img_size==0`) | `hps_io` (UIO_SET_SDSTAT) | core (latch size/RO) [C] |
| `img_readonly` | output | 1 | `clk_sys` | high | Mount is read-only; valid only with active `img_mounted` bit | `hps_io` (io_din[7] of cmd 0x1c) | core [C] |
| `img_size[63:0]` | output | 64 | `clk_sys` | n/a | Image size in bytes; valid only on `img_mounted` cycle | `hps_io` (UIO_SET_SDINFO) | core [C] |
| `sd_lba[VDNUM]` | input | 32 each | `clk_sys` | n/a | Per-slot logical block address (sectors, not bytes) | core | `hps_io` -> HPS via UIO_GET_SDSTAT [C] |
| `sd_blk_cnt[VDNUM]` | input | 6 each | `clk_sys` | n/a | Per-slot multi-sector count minus one; total bytes `<= 16384` | core | `hps_io` -> HPS [C] |
| `sd_rd[VD:0]` | input | `VDNUM` | `clk_sys` | high, level | Per-slot read request; hold until `sd_ack[n]` rises | core | `hps_io` (status poll) [C] |
| `sd_wr[VD:0]` | input | `VDNUM` | `clk_sys` | high, level | Per-slot write request; hold until `sd_ack[n]` rises | core | `hps_io` (status poll) [C] |
| `sd_ack[VD:0]` | output | `VDNUM` | `clk_sys` | high, level | Per-slot transfer-in-progress acknowledge; rises on UIO_SECTOR_RD/WR start, falls when `io_enable` drops | `hps_io` | core (release `sd_rd`/`sd_wr`, advance LBA) [C] |
| `sd_buff_addr[AW:0]` | output | `AW+1` (14 narrow / 13 WIDE) | `clk_sys` | n/a | Index within current sector buffer; auto-increments | `hps_io` | core RAM port [C] |
| `sd_buff_dout[DW:0]` | output | `DW+1` (8 narrow / 16 WIDE) | `clk_sys` | n/a | Data from HPS to core, paired with `sd_buff_wr` | `hps_io` | core RAM [C] |
| `sd_buff_din[VDNUM]` | input | `DW+1` each | `clk_sys` | n/a | Per-slot data from core to HPS during write; routed by `sdn_ack` | core | `hps_io` -> HPS [C] |
| `sd_buff_wr` | output | 1 | `clk_sys` | high, one-cycle | Write-strobe for incoming sector data | `hps_io` | core RAM [C] |

The framework round-robins between simultaneously requesting slots using `sd_rrb`, so no slot can starve another. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:204-215 @ f35083f3b40d)

The HPS-side mount entry point is `user_io_file_mount(name, index, pre, pre_size)`; an empty `name` ejects the slot. [C] (archive/github/MiSTer-devel/Main_MiSTer/user_io.cpp:2082-2213 @ 136737b4bed4)

The polling that drives sectors lives in `user_io_poll` and dispatches via `UIO_SECTOR_RD`/`UIO_SECTOR_WR` with the slot index OR-ed into the upper byte (`(disk+1) << 8`). [C] (archive/github/MiSTer-devel/Main_MiSTer/user_io.cpp:3172-3414 @ 136737b4bed4)

## 4. Sequencing & timing

### 4.1 Mount / unmount (slot `n`)

```
clk_sys     |‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_
                                              <-- HPS sends UIO_SET_SDINFO (cmd 0x1d), 4x16b size words
img_size       <-- prior --><----- new 64b size value valid here ----->
                                              <-- HPS sends UIO_SET_SDSTAT (cmd 0x1c), io_din[VD:0]=slot mask, io_din[7]=RO
img_mounted[n] ________________________/‾‾‾‾‾‾\__________________________
img_readonly   <-- prior -------------><--- RO flag valid here ---->
                                              ^^^ core MUST latch img_size & img_readonly on this cycle ^^^
                                                  next ~io_enable clears img_mounted (auto)
```

`img_mounted` pulse is exactly the active span of byte_cnt==1 within the 0x1c command; the de-assertion path is `~io_enable -> img_mounted <= 0`. Eject is the same waveform with `img_size==0`. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:318,461 @ f35083f3b40d)

### 4.2 Single-sector read (core wants sector `lba` from slot `n`)

```
clk_sys     |‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_
sd_lba[n]   ===lba valid throughout the operation==============================
sd_rd[n]    ____/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\__________________________
                ^ core asserts
                  ... HPS polls UIO_GET_SDSTAT (0x16); sees sd_rd[n]; reads back lba (cmd words 2,3) ...
                  ... HPS reads the file from disk into local buffer ...
                  ... HPS streams sector data via UIO_SECTOR_RD (0x17 | (n+1)<<8) ...
sd_ack[n]   _________________________/‾‾‾‾‾‾‾‾‾‾‾‾\___________________________
                                     ^ EnableIO + spi_w(UIO_SECTOR_RD|ack) sets sd_ack
sd_buff_addr 0  0  0  0  0  0  0  0  0  1  2  3  4  ... 511   (auto-increment)
sd_buff_dout XX XX XX XX XX XX XX XX <D0 D1 D2 D3 ...   D511> XX XX
sd_buff_wr   ____________________________/‾\_/‾\_/‾\_...   /‾\____________
                                              one pulse per byte
                                                                    ^ DisableIO -> ~io_enable -> sd_ack falls
                                                                      core de-asserts sd_rd on rising-of-ack edge
                                                                      sd_card.sv increments sd_lba on falling-of-ack edge
```

Read narration:
1. Core asserts `sd_rd[n]=1` with `sd_lba[n]` valid.
2. HPS polls 0x16, sees `{sd_wr[sdn], sd_rd[sdn]}` non-zero in the status word, reads `sd_lba[sdn][15:0]` then `sd_lba[sdn][31:16]` over the next two SPI words. (`hps_io.sv:329,396-399`)
3. HPS reads the file from the host filesystem (or CHD, or generated data) into its own buffer.
4. HPS issues `UIO_SECTOR_RD | ack` where `ack = (disk+1) << 8`; the 0x0X17 command sets `sd_ack <= disk_mask` (`hps_io.sv:331`). The core can now consume data on `sd_buff_addr/sd_buff_dout/sd_buff_wr`.
5. HPS streams the sector via `spi_block_write`; `sd_buff_wr` pulses once per byte/word; `sd_buff_addr` auto-increments. (`user_io.cpp:3412-3413`, `hps_io.sv:295-296,405`)
6. HPS calls `DisableIO`, dropping `io_enable`. `sd_ack` falls. (`hps_io.sv:315`)
7. Core (or `sd_card.sv`) sees rising-of-ack -> de-asserts `sd_rd`; falling-of-ack -> may advance `sd_lba` and start the next sector. (`sd_card.sv:193-197`)

### 4.3 Single-sector write (core wants to write sector `lba` to slot `n`)

```
clk_sys     |‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_
sd_lba[n]   ===lba valid throughout the operation============================
sd_buff_din[n] ===<entire sector content readable; sd_buff_addr indexes it>====
sd_wr[n]    ____/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\______________________
                ^ core asserts
                  ... HPS polls 0x16, reads lba, allocates disk space ...
                  ... HPS issues UIO_SECTOR_WR (0x18) | ack ...
sd_ack[n]   _________________________/‾‾‾‾‾‾‾‾‾‾‾‾\_______________________
sd_buff_addr 0  0  0  0  0  0  0  0  0  1  2  3  ... 511  (auto-increment on dout read)
                                     ^ each SPI word advances addr, core presents next sd_buff_din[n] byte
                                                                 ^ DisableIO -> sd_ack falls
                                                                   sd_card.sv: rising-of-ack -> sd_wr<=0
```

Write narration:
1. Core asserts `sd_wr[n]=1` with `sd_lba[n]` valid and the **entire sector already addressable** through `sd_buff_din[n]` (HPS reads the buffer; the core must respond with the correct byte for any `sd_buff_addr` it sees in the next several cycles).
2. HPS polls 0x16 same as read.
3. HPS issues `UIO_SECTOR_WR | ack` (0x18 with disk index in upper byte). `sd_ack <= disk_mask`.
4. HPS reads sector bytes from the core via 0x0X18 SPI reads. Each SPI word increments `sd_buff_addr`; the core re-drives `sd_buff_din[sdn_ack]` to match. (`hps_io.sv:410-413`)
5. `DisableIO` -> `sd_ack` falls. Core de-asserts `sd_wr`.

## 5. Minimal working pattern (using `sd_card.sv`)

The framework ships `sd_card.sv`: an SPI SD-card emulator. The core sees a virtual SD card on `(ss, sck, mosi, miso)`; `sd_card.sv` translates that traffic into the framework block-IO contract above. Use this when porting a system that natively talks SPI/SD (Apple II, MSX SD adapters, etc.).

```verilog
// archive/github/MiSTer-devel/Template_MiSTer/sys/sd_card.sv:28-54 @ f35083f3b40d
module sd_card #(parameter WIDE = 0, OCTAL=0)
(
	input             clk_sys,
	input             reset,

	input             sdhc,
	input             img_mounted,
	input      [63:0] img_size,

	output reg [31:0] sd_lba,
	output reg        sd_rd,
	output reg        sd_wr,
	input             sd_ack,

	input      [AW:0] sd_buff_addr,
	input      [DW:0] sd_buff_dout,
	output     [DW:0] sd_buff_din,
	input             sd_buff_wr,

	// SPI interface
	input             clk_spi,

	input             ss,
	input             sck,
	input      [SW:0] mosi,
	output reg [SW:0] miso
);
```

Wire-up sketch (single slot, narrow bus, `VDNUM=1`):

```verilog
wire        img_mounted;
wire        img_readonly;
wire [63:0] img_size;

wire [31:0] sd_lba_card;
wire        sd_rd_card, sd_wr_card;
wire        sd_ack_card;
wire [13:0] sd_buff_addr;
wire  [7:0] sd_buff_dout, sd_buff_din_card;
wire        sd_buff_wr;

hps_io #(.CONF_STR(CONF_STR), .VDNUM(1)) hps_io
(
	.clk_sys(clk_sys),
	.HPS_BUS(HPS_BUS),

	.img_mounted (img_mounted),
	.img_readonly(img_readonly),
	.img_size    (img_size),

	.sd_lba      ('{sd_lba_card}),       // arrayed input
	.sd_blk_cnt  ('{6'd0}),              // 1 block per transfer
	.sd_rd       (sd_rd_card),
	.sd_wr       (sd_wr_card),
	.sd_ack      (sd_ack_card),

	.sd_buff_addr(sd_buff_addr),
	.sd_buff_dout(sd_buff_dout),
	.sd_buff_din ('{sd_buff_din_card}),  // arrayed input
	.sd_buff_wr  (sd_buff_wr)
	// ... other hps_io ports ...
);

sd_card sd_card
(
	.clk_sys     (clk_sys),
	.reset       (reset),
	.sdhc        (1'b1),
	.img_mounted (img_mounted),
	.img_size    (img_size),

	.sd_lba      (sd_lba_card),
	.sd_rd       (sd_rd_card),
	.sd_wr       (sd_wr_card),
	.sd_ack      (sd_ack_card),

	.sd_buff_addr(sd_buff_addr),
	.sd_buff_dout(sd_buff_dout),
	.sd_buff_din (sd_buff_din_card),
	.sd_buff_wr  (sd_buff_wr),

	.clk_spi     (clk_spi),
	.ss          (core_ss),
	.sck         (core_sck),
	.mosi        (core_mosi),
	.miso        (core_miso)
);
```

`sd_card.sv` handles the `sd_rd`/`sd_ack`/`sd_lba`/`sd_buff_*` dance internally — including holding `sd_rd` until the ack edge and advancing the LBA on ack-fall. (archive/github/MiSTer-devel/Template_MiSTer/sys/sd_card.sv:190-197 @ f35083f3b40d)

The wire-up sketch above is illustrative scaffolding synthesized from the port lists in `hps_io.sv` and `sd_card.sv`; only the verbatim `sd_card` port block (lines 28-54) is quoted from source. [I]

## 6. Common variations across cores

- **Direct `sd_lba`/`sd_rd`/`sd_wr` use (no `sd_card.sv`):** cores whose host system never spoke SPI/SD natively (Amiga floppies, Atari ST WD1772, IDE/HDF emulation, NES/SNES disk system, etc.) drive the framework block-IO signals directly from a per-controller state machine. This is the dominant pattern. `[V] [deferred - reference cores not fetched]`
- **Multi-slot:** `VDNUM` is bumped to 2..4 to expose multiple drives. Slot 0 is `S0`, slot 1 is `S1`, etc. The framework round-robins between slots that simultaneously assert `sd_rd`/`sd_wr`. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:204-215 @ f35083f3b40d)
- **CD-ROM raw sector mode:** `Main_MiSTer/user_io.cpp:3182-3185` hard-codes special block sizes when the running core is PSX (`blksz = 2352` on slot 1) or CDI (`blksz = CDI_CDIC_BUFFER_SIZE`, which is the raw frame plus subcode). The core must report the matching `sd_blk_cnt` and pace data accordingly. [V] (archive/github/MiSTer-devel/Main_MiSTer/user_io.cpp:3182-3185 @ 136737b4bed4)
- **CHD-backed CDs (PSX, MegaCD, Saturn, PCECD, CDI, 3DO):** the HPS side opens the image through libchdr (`cdrom_parse` in `ide_cdrom.cpp:1657`, plus per-system `support/<sys>/<sys>.cpp` plumbing), but the FPGA-side block protocol is unchanged. The core never sees CHD-vs-raw differences. [V] (archive/github/MiSTer-devel/Main_MiSTer/ide_cdrom.cpp:1657-1686 @ 136737b4bed4)
- **IDE/CD over `ide.cpp` (ao486, MegaCD on some configurations):** `ide_open(unit, filename)` decides per-mount whether the file is HDD or CD, then routes to `ide_img_mount` or `cdrom_parse`. The CD/HDD distinction is HPS-side; the FPGA still sees vanilla block IO. [V] (archive/github/MiSTer-devel/Main_MiSTer/ide.cpp:1091-1126 @ 136737b4bed4)
- **Cross-core direct comparison (Minimig vs. PSX vs. SNES floppy):** `[deferred - reference cores not fetched]`. The repos for individual cores were not in this archive snapshot. [I]
- **Sector size other than 512:** `BLKSZ` parameter overrides the default; e.g., a core mounting raw audio frames could set `BLKSZ=4` for 2048 B blocks. No reference core verified in this snapshot. `[I] [deferred - reference cores not fetched]`

## 7. Anti-patterns

### A.1 Not de-asserting `sd_rd`/`sd_wr` after `sd_ack`

- **Symptom:** First sector seems to work, then the core loops on the same sector forever or fires a second spurious transfer immediately.
- **Cause:** Treating `sd_rd` as a pulse. The HPS polls the **level** every iteration of `user_io_poll`. If the core keeps `sd_rd[n]` high after `sd_ack` falls, the HPS will read the (now-old) `sd_lba` again on the next poll and re-issue the transfer.
- **Fix:** Latch the rising edge of `sd_ack[n]` and clear `sd_rd[n]`/`sd_wr[n]` on it. `sd_card.sv` shows the canonical pattern: a 3-stage `ack` shift register, de-assert request on `~ack[2] & ack[1]`, advance LBA on `ack[2] & ~ack[1]`.
- **Citation:** archive/github/MiSTer-devel/Template_MiSTer/sys/sd_card.sv:190-197 @ f35083f3b40d

### A.2 Writing through a read-only mount

- **Symptom:** Core thinks the write succeeded (sees `sd_ack` rise and fall normally); next read of the same LBA returns old data; user reports save loss.
- **Cause:** The HPS opened the file `O_RDONLY` (because the underlying filesystem is read-only, the file is in a zipped MRA, or the file was marked read-only at mount time). It still ACKs the transfer to keep the protocol honest but never calls `FileWriteAdv`. The core ignored `img_readonly`.
- **Fix:** Latch `img_readonly` on the `img_mounted` pulse. Gate `sd_wr[n]` assertion on `~img_readonly` (or surface a write-protect error to the emulated machine).
- **Citation:** archive/github/MiSTer-devel/Main_MiSTer/user_io.cpp:2119-2211 @ 136737b4bed4; archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:129,462 @ f35083f3b40d

### A.3 Treating `sd_lba` as a byte offset

- **Symptom:** Image content appears scrambled at 512x the expected stride; small images read OK but large ones address beyond EOF.
- **Cause:** `sd_lba` is a logical block address. The HPS converts to byte offset internally as `lba * blksz`. Drivers that compute "address = sector * 512" and then load `sd_lba <= address` shift the data by a factor of `blksz`.
- **Fix:** Drive `sd_lba` with the sector number directly. If the emulated machine has a byte-granular cursor, divide by `blksz` before assigning.
- **Citation:** archive/github/MiSTer-devel/Main_MiSTer/user_io.cpp:3298 @ 136737b4bed4

### A.4 Ignoring the `img_mounted` one-cycle window for `img_size`

- **Symptom:** Core reads `img_size` at any later time and gets stale data from a previous mount, then walks off the end of the new image.
- **Cause:** `img_size` is only guaranteed valid on the same cycle `img_mounted[n]` is high — it is updated by the 0x1d command and re-overwritten by the next mount. The framework does not preserve per-slot sizes.
- **Fix:** Latch `img_size` (and `img_readonly`) into a per-slot register on the `img_mounted[n]` pulse.
- **Citation:** archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:128-130,461-466 @ f35083f3b40d

## 8. Verification

- **Mount visibility:** When a file is selected from the OSD, `Main_MiSTer` prints `Mount <path> as read-write on N slot` (or `read-only`); confirm in the console output (`MiSTer.log` or stderr). [O] (archive/github/MiSTer-devel/Main_MiSTer/user_io.cpp:2181 @ 136737b4bed4)
- **Empty mount / eject:** Look for `Eject image from N slot` in the log; on the FPGA side `img_mounted[n]` will pulse with `img_size==0`. [O] (archive/github/MiSTer-devel/Main_MiSTer/user_io.cpp:2176 @ 136737b4bed4)
- **Activity LED:** `diskled_on()` fires on every read/write that hits the file. If the user mounts an image and the LED never blinks, the core probably never asserts `sd_rd`/`sd_wr` (check `CONF_STR` slot declaration and slot routing).
- **Simulation:** Stimulate `img_mounted`, `img_size` as a one-cycle pulse, then drive `sd_rd`/`sd_wr` from the core. Use `sd_card.sv` testbenches in the Template; on a real bring-up, hook `signaltap`/`ila` on `sd_rd`, `sd_wr`, `sd_ack`, `sd_lba`, `sd_buff_wr` to verify the handshake.
- **MiSTer.ini flags:** None directly relevant; debug usually goes via the `Main_MiSTer` `printf` in `user_io_poll`.

## 9. Provenance footer

- archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv @ f35083f3b40d - port declarations (§3), command handlers (§2, §4), VDNUM/BLKSZ parameters (§2), round-robin slot arbiter (§3)
- archive/github/MiSTer-devel/Template_MiSTer/sys/sd_card.sv @ f35083f3b40d - SPI SD-card emulator instance for §5; ack-edge handshake reference for §2 and §7
- archive/github/MiSTer-devel/Main_MiSTer/user_io.cpp @ 136737b4bed4 - `user_io_file_mount` (§3), `user_io_poll` SD dispatch loop (§3, §4), CD-ROM block size selection (§6), readonly flag (§7)
- archive/github/MiSTer-devel/Main_MiSTer/user_io.h @ 136737b4bed4 - UIO_* command codes (§2, §4)
- archive/github/MiSTer-devel/Main_MiSTer/ide.cpp @ 136737b4bed4 - `ide_open` HDD/CD dispatcher (§6)
- archive/github/MiSTer-devel/Main_MiSTer/ide_cdrom.cpp @ 136737b4bed4 - `cdrom_parse` and raw-frame size constants (§6)
