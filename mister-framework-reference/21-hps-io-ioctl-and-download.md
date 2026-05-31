# hps_io — ioctl Download / Upload Path

> Bundle version: 2026-05-18
> Pinned commits: `Template_MiSTer @ f35083f3b40d`, `Main_MiSTer @ 136737b4bed4`, `MkDocs_MiSTer @ 9033bd292fdc`
> Load with: [20-hps-io-overview.md](20-hps-io-overview.md), [22-hps-io-mount-and-sd.md](22-hps-io-mount-and-sd.md), [32-rom-save-state-flows.md](32-rom-save-state-flows.md)
> Status mix: [C] [V] [I]

> Source note: the brief listed `Main_MiSTer/file_io.cpp` and `file_io.h` as primary inputs, but those files contain no ioctl logic (verified by grep). All HPS-side ioctl primitives live in `Main_MiSTer/user_io.cpp` and `user_io.h`. This doc cites the actual source. Reference per-core RTL was not in the archive snapshot, so §6 is deferred per brief.

## 1. Purpose & one-line summary

The ioctl path is the unidirectional file-delivery channel from `Main_MiSTer` (HPS) into the FPGA fabric, exposed by `hps_io` as `ioctl_download` plus a write strobe and incrementing address. Cores receive ROM bytes (or any file from a `CONF_STR` `F<index>` slot) here, and may optionally read back save data on the `ioctl_upload` path. The path covers boot ROMs, OSD-loaded files, MRA arcade sets, and NVRAM/SRAM save-back; mount-slot block IO (`S<index>`) and SDRAM placement strategy are handled elsewhere.

## 2. The contract (must-obey)

- Rule 1. `ioctl_download` and `ioctl_upload` are mutually exclusive level signals; the framework drives `{ioctl_upload, ioctl_download} <= req_io;` from a single 2-bit decode (`0xFF`→download, `0xAA`→upload, `0`→stop). [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:638 @ f35083f3b40d)
- Rule 2. `ioctl_wr` is a single-cycle pulse in the `clk_sys` domain, valid for exactly one cycle per delivered word (`wr <= 0` next cycle). [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:632-634,693 @ f35083f3b40d)
- Rule 3. `ioctl_rd` is a single-cycle pulse in `clk_sys` requesting the next upload word from `ioctl_din`. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:632,697 @ f35083f3b40d)
- Rule 4. `ioctl_addr` is 27 bits wide. In `WIDE=0` (byte) mode it increments by 1 per word; in `WIDE=1` (16-bit) mode it increments by 2 per word. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:149,180-181,688 @ f35083f3b40d)
- Rule 5. `ioctl_addr` is reset to 0 by the FIO_FILE_TX start command (byte 0 = `0xFF` or `0xAA`) before any data; subsequent FIO_FILE_TX bytes 1-2 may optionally load a non-zero start address. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:672-682 @ f35083f3b40d)
- Rule 6. For a download (`req_io[0]=1`), the first `FIO_FILE_TX_DAT` word writes at `ioctl_addr=0` without incrementing first (`skip_add` masks the bump for the first word); each subsequent word increments first then writes. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:639,688-694 @ f35083f3b40d)
- Rule 7. For an upload (`req_io[0]=0`), `skip_add` is not set, so the first `FIO_FILE_TX_DAT` increments `ioctl_addr` before sampling `ioctl_din`; the core must therefore present the word for the starting `ioctl_addr` value the moment `ioctl_upload` rises. [I] (archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:639,688,696 @ f35083f3b40d)
- Rule 8. At end-of-transmission the HPS sends `FIO_FILE_TX` with first byte = 0; if `ioctl_download` is currently high, `hps_io` performs one final `ioctl_addr` increment in the same cycle it deasserts `ioctl_download`. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:676-680 @ f35083f3b40d)
- Rule 9. `ioctl_wait`, when asserted by the core, propagates onto `HPS_BUS[37]` and gates `io_strobe` inside `sys_top.v`, stalling the HPS bus until deasserted. Use it as back-pressure when the core's RAM target is busy. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:191 @ f35083f3b40d; archive/github/MiSTer-devel/Template_MiSTer/sys/sys_top.v:259 @ f35083f3b40d)
- Rule 10. `ioctl_index` is 16 bits: `[5:0]` is the F-slot or boot-rom sub-index, `[15:6]` is the extension index derived from the matched `CONF_STR` extension list. boot.rom maps to `ioctl_index == 0`; boot1.rom maps to `{6'd1, 6'd0} == 16'h40`. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:665 @ f35083f3b40d; archive/github/MiSTer-devel/Main_MiSTer/user_io.cpp:1586-1590 @ 136737b4bed4; archive/github/MiSTer-devel/MkDocs_MiSTer/docs/developer/hps_io.md:208,234 @ 9033bd292fdc)
- Rule 11. `ioctl_index` is set by `FIO_FILE_INDEX` (`0x55`) and latched before `FIO_FILE_TX`; HPS always emits the index sequence before the start byte. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:620,663-666 @ f35083f3b40d; archive/github/MiSTer-devel/Main_MiSTer/user_io.cpp:2011-2017,2664-2676 @ 136737b4bed4)
- Rule 12. `ioctl_file_ext` is 32 bits and holds up to four upper-cased ASCII bytes of the file extension, written via `FIO_FILE_INFO` (`0x56`) before the FIO_FILE_TX start. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:621,654-661 @ f35083f3b40d; archive/github/MiSTer-devel/Main_MiSTer/user_io.cpp:2069-2080 @ 136737b4bed4)
- Rule 13. `ioctl_upload_req` is sampled by `hps_io` on its rising edge into a latched `upload_req` flag, which the HPS reads via opcode `0x3C` when the OSD is open. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:289-290,335 @ f35083f3b40d)
- Rule 14. `ioctl_upload_index` is 8 bits and is reported to the HPS together with the upload-request flag; cores use it to identify which save bank changed. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:153,335 @ f35083f3b40d)
- Rule 15. Data width of `ioctl_dout` and `ioctl_din` is byte-wide by default and 16-bit when `WIDE=1`; both follow `DW = WIDE ? 15 : 7`. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:150,154,180,692 @ f35083f3b40d)
- Rule 16. All ioctl outputs are registered in the `clk_sys` domain and change only on `posedge clk_sys`; cores must sample them on the same `clk_sys` rising edge. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:624,632 @ f35083f3b40d)

## 3. Ports / signals reference

```verilog
// archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:145-157 @ f35083f3b40d
	// ARM -> FPGA download
	output reg        ioctl_download = 0, // signal indicating an active download
	output reg [15:0] ioctl_index,        // menu index used to upload the file
	output reg        ioctl_wr,
	output reg [26:0] ioctl_addr,         // in WIDE mode address will be incremented by 2
	output reg [DW:0] ioctl_dout,
	output reg        ioctl_upload = 0,   // signal indicating an active upload
	input             ioctl_upload_req,   // request to save (must be supported on HPS side for specific core)
	input       [7:0] ioctl_upload_index,
	input      [DW:0] ioctl_din,
	output reg        ioctl_rd,
	output reg [31:0] ioctl_file_ext,
	input             ioctl_wait,
```

`DW` resolves to `7` for byte mode and `15` for 16-bit mode (`localparam DW = (WIDE) ? 15 : 7;`).
[C] (archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:180 @ f35083f3b40d)

| Signal | Dir | Width | Clock | Active | Meaning | Driven by | Drives |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `ioctl_download` | out (hps_io→core) | 1 | `clk_sys` | high level | A file transfer HPS→FPGA is in progress. [C] | `hps_io` state machine | core write-target enable |
| `ioctl_upload` | out (hps_io→core) | 1 | `clk_sys` | high level | A read-back transfer FPGA→HPS is in progress. [C] | `hps_io` state machine | core read-source mux |
| `ioctl_wr` | out (hps_io→core) | 1 | `clk_sys` | high 1-cycle pulse | `ioctl_dout` and `ioctl_addr` are valid this cycle; core latches them. [C] | `hps_io` (`wr` registered) | core ROM/RAM write-enable |
| `ioctl_rd` | out (hps_io→core) | 1 | `clk_sys` | high 1-cycle pulse | Framework just sampled `ioctl_din` at `ioctl_addr` for the upload word. [C] | `hps_io` | core read-side increment / progress |
| `ioctl_addr` | out (hps_io→core) | 27 | `clk_sys` | n/a | Word address relative to start of file. Reset to 0 at `FIO_FILE_TX` start. Step = 1 (byte mode) or 2 (`WIDE=1`). [C] | `hps_io` | core ROM/RAM address bus |
| `ioctl_dout` | out (hps_io→core) | 8 or 16 | `clk_sys` | data | Word delivered from HPS, valid with `ioctl_wr`. [C] | `hps_io` | core write-data bus |
| `ioctl_din` | in (core→hps_io) | 8 or 16 | `clk_sys` | data | Core's read-back word, sampled by `hps_io` on `FIO_FILE_TX_DAT` during upload. [C] | core save-RAM read port | `hps_io` upload buffer |
| `ioctl_index` | out (hps_io→core) | 16 | `clk_sys` | n/a | `[5:0]` F-slot or boot index, `[15:6]` extension subindex. Stable across whole transfer. [C] | `hps_io` (`FIO_FILE_INDEX`) | core routing logic |
| `ioctl_upload_req` | in (core→hps_io) | 1 | `clk_sys` | rising edge | Core requests an NVRAM save-back; HPS reads when OSD is open. [C] | core save-dirty flag | `hps_io` upload-request latch |
| `ioctl_upload_index` | in (core→hps_io) | 8 | `clk_sys` | n/a | Identifies which save bank the request refers to. [C] | core | `hps_io` opcode `0x3C` reply |
| `ioctl_file_ext` | out (hps_io→core) | 32 | `clk_sys` | n/a | Four-byte upper-cased extension of the file being transferred; stable across the transfer. [C] | `hps_io` (`FIO_FILE_INFO`) | core ext-based routing |
| `ioctl_wait` | in (core→hps_io) | 1 | `clk_sys` | high level | Back-pressure: core not ready; framework pauses HPS strobes via `HPS_BUS[37]→io_wait` in `sys_top.v`. [C] | core busy flag | `sys_top` strobe gate |

## 4. Sequencing & timing

### 4.1 ROM download — start, mid-stream, end

```
clk_sys          |‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_
                    A   B   C   D   E   F   G   H   I   J   K   L   M

ioctl_index      ===<idx>==================================================  (latched at A: FIO_FILE_INDEX 0x55, io_din=<idx>)
ioctl_file_ext   ===<ext>==================================================  (latched at B: FIO_FILE_INFO 0x56 sequence)
ioctl_download   ___________/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\______  (rises at C end: FIO_FILE_TX cmd, io_din[7:0]=0xFF)
ioctl_addr       =0=========0===========1===========2===========3===========0=  (in WIDE=0; step 2 in WIDE=1)
ioctl_dout       ==========<d0>========<d1>========<d2>========<d3>=========
ioctl_wr         __________/‾\_________/‾\_________/‾\_________/‾\__________
ioctl_wait       ______________________________________________________________  (held low; assert to pause)

                            ^C: end of FIO_FILE_TX header. ioctl_addr<=0, ioctl_download<=1.
                              ^D: first FIO_FILE_TX_DAT word. skip_add=1 prevents pre-increment;
                                   write at addr 0, ioctl_wr pulses.
                                        ^F,H,J: subsequent words; pre-increment then ioctl_wr pulse.
                                                                ^L: FIO_FILE_TX cmd with io_din[7:0]==0;
                                                                    one final addr bump, then ioctl_download<=0.
```

Notes:
- The `ioctl_addr` increment on the closing FIO_FILE_TX (`if(ioctl_download) ioctl_addr <= ioctl_addr + ...`) means the address visible immediately after the falling edge of `ioctl_download` is `total_words` (count) not `last_word_addr` (`total_words - 1`). [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:677-679 @ f35083f3b40d)
- `ioctl_wr` is one `clk_sys` cycle wide; the core's write target must be edge- or pulse-triggered, not level-gated. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:632-634 @ f35083f3b40d)
- HPS pacing: each `FIO_FILE_TX_DAT` opcode and each data word arrive via an SPI burst (`spi_write` inside `user_io_file_tx_data`); the FPGA sees `io_strobe` per word, and one word per strobe is delivered. [C] (archive/github/MiSTer-devel/Main_MiSTer/user_io.cpp:2040-2046 @ 136737b4bed4)

### 4.2 NVRAM upload — save-RAM read-back

```
clk_sys          |‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_

ioctl_upload_req _____/‾‾‾‾‾‾‾‾‾‾‾\_________________________________________  (core asserts when save data dirty)
                       ^ rising edge latched into hps_io.upload_req
                                          (HPS polls 0x3C while OSD open; reads ioctl_upload_index)
ioctl_index      ===========<save_idx>=====================================  (HPS issues FIO_FILE_INDEX again)
ioctl_upload     _______________________/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\______  (rises at A: FIO_FILE_TX cmd with byte=0xAA)
ioctl_addr       =====================0===========1===========2===========3=  (no skip_add for uploads → first word pre-increments to 1)
ioctl_din        ====================<read_word_for_current_addr>==========  (core presents continuously)
ioctl_rd         _____________________/‾\_________/‾\_________/‾\__________  (pulses on each FIO_FILE_TX_DAT)

                                      ^A: ioctl_addr<=0, ioctl_upload<=1, skip_add stays 0.
                                        ^B: first DAT: ioctl_addr bumps to 1 BEFORE the read is sampled.
                                              (consequence: the byte the HPS receives first corresponds to
                                               whatever ioctl_din presented at ioctl_addr==1 the cycle the DAT arrived.)
```

Asymmetric `skip_add` for download vs. upload is explicit in the RTL (`skip_add <= req_io[0]` — only set when downloading).
[C] (archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:639,688-689,696-697 @ f35083f3b40d)

The end-of-upload sequence mirrors §4.1: HPS sends `FIO_FILE_TX` with byte 0, which clears `ioctl_upload`. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:678-679 @ f35083f3b40d)

### 4.3 HPS-side command sequence

The HPS C++ wrappers for the cycle above are:

```cpp
// archive/github/MiSTer-devel/Main_MiSTer/user_io.cpp:2011-2058 @ 136737b4bed4
void user_io_set_index(unsigned char index)        { EnableFpga(); spi8(FIO_FILE_INDEX); spi8(index); DisableFpga(); }
void user_io_set_aindex(uint16_t index)            { EnableFpga(); spi8(FIO_FILE_INDEX); spi_w(index); DisableFpga(); }
void user_io_set_download(unsigned char en, int a) { EnableFpga(); spi8(FIO_FILE_TX); spi8(en?0xff:0); if(en && a){spi_w(a); spi_w(a>>16);} DisableFpga(); }
void user_io_file_tx_data(const uint8_t *p, uint32_t n) { EnableFpga(); spi8(FIO_FILE_TX_DAT); spi_write(p,n,fio_size); DisableFpga(); }
void user_io_set_upload(unsigned char en, int a)   { EnableFpga(); spi8(FIO_FILE_TX); spi8(en?0xaa:0); if(en && a){spi_w(a); spi_w(a>>16);} DisableFpga(); }
void user_io_file_rx_data(uint8_t *p, uint32_t n)  { EnableFpga(); spi8(FIO_FILE_TX_DAT); spi_read(p,n,fio_size); DisableFpga(); }
```

Opcodes (declared in `user_io.h`):

```
FIO_FILE_TX     = 0x53   // start/stop of a transfer; direction byte 0xFF=download, 0xAA=upload, 0=end
FIO_FILE_TX_DAT = 0x54   // one or more data words within a transfer
FIO_FILE_INDEX  = 0x55   // set ioctl_index
FIO_FILE_INFO   = 0x56   // set ioctl_file_ext (two 16-bit words = four ASCII bytes)
```
[C] (archive/github/MiSTer-devel/Main_MiSTer/user_io.h:81-84 @ 136737b4bed4; archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:618-621 @ f35083f3b40d)

## 5. Minimal working pattern

The framework `Template_MiSTer` repo does not contain a minimal core that wires `ioctl_*` for ROM load — every cited reference core has been removed from the archive snapshot. The following pattern is synthesized from the `hps_io` port contract above. It is marked `[I]` and should be cross-checked against an actual core.

```verilog
// SYNTHESIZED from hps_io contract — see hps_io.sv:145-157,632-704 @ f35083f3b40d
// Pattern: load a single ROM via an F-slot (F1) into on-chip RAM and present
// it to the core. Replace `rom` with SDRAM/DDRAM placement for large ROMs
// (see 32-rom-save-state-flows.md).

wire        ioctl_download;
wire        ioctl_wr;
wire [26:0] ioctl_addr;
wire  [7:0] ioctl_dout;      // WIDE=0 byte mode
wire [15:0] ioctl_index;
reg         ioctl_wait;

// Optional: only accept the F-slot we expect (F1 in the CONF_STR -> low 6 bits == 1)
wire is_rom_load = ioctl_download & (ioctl_index[5:0] == 6'd1);

// On-chip ROM target (small example; real cores typically write to SDRAM/DDRAM)
reg [7:0] rom [0:(1<<16)-1];
always @(posedge clk_sys) begin
    if (is_rom_load && ioctl_wr) begin
        rom[ioctl_addr[15:0]] <= ioctl_dout;
    end
end

// Hold the core in reset while the download is active (and one cycle after)
reg ioctl_download_d;
always @(posedge clk_sys) ioctl_download_d <= ioctl_download;
wire rom_load_active = ioctl_download | ioctl_download_d;

// Tie back-pressure to 0 if RAM can always accept the word
assign ioctl_wait = 1'b0;
```

For the save-back side, a parallel block:

```verilog
// Save-RAM read-back via ioctl_upload (synthesized)
reg [7:0] sram [0:(1<<13)-1];
reg  [7:0] ioctl_din_r;
always @(posedge clk_sys) ioctl_din_r <= sram[ioctl_addr[12:0]];
wire [7:0] ioctl_din = ioctl_din_r;

// Request a save when the core marks SRAM dirty:
reg ioctl_upload_req;
wire [7:0] ioctl_upload_index = 8'd0;   // identifies which bank
// pulse ioctl_upload_req for >=1 clk_sys cycle when dirty; hps_io latches the rising edge
```

Wiring at the `hps_io` instance is identical to the port list in §3; the core simply ties each declared signal to its named port. [I]

## 6. Common variations across cores

[deferred — reference cores not fetched]

Per the brief, no per-core RTL was included in the archive snapshot. The framework-side contract permits the following classes of variation, each marked [I] until verified against a real core:

- ROM-only (write-only) cores wire `ioctl_din`/`ioctl_upload`/`ioctl_upload_req`/`ioctl_upload_index` to constants and ignore `ioctl_rd`. [I]
- Cores with save-back (NVRAM/SRAM/EEPROM) wire all signals and drive `ioctl_upload_req` on a dirty flag. [I]
- Multi-ROM cores use `ioctl_index[5:0]` to demultiplex sub-files inside one OSD load (e.g. arcade MRA, multi-boot), routing to different memories. [I]
- Cores with `WIDE=1` (`hps_io #(... .WIDE(1))`) see 16-bit `ioctl_dout`/`ioctl_din` and `ioctl_addr` increments of 2. [I] (archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:180-181,688 @ f35083f3b40d)
- Cores using extension-based routing (e.g. `.SMC` vs `.BS` vs `.SPC`) read `ioctl_index[15:6]` to dispatch; the HPS picks that subindex from the matching extension list in `CONF_STR` (see [11-conf-str.md](11-conf-str.md)). [I] (archive/github/MiSTer-devel/Main_MiSTer/user_io.cpp:4287-4316 @ 136737b4bed4)

## 7. Anti-patterns

### A.1 Treating `ioctl_wr` as a level

- **Symptom:** Every byte of the ROM gets written to the same address, or the ROM emerges with garbage repeated. Simulation shows `ioctl_wr` "stays high".
- **Cause:** `ioctl_wr` is a one-cycle `clk_sys` pulse (`ioctl_wr <= wr; wr <= 0;`). Code that uses `if (ioctl_wr) addr <= addr + 1;` together with a level-sensitive memory write will fire once per valid word — but using it as a level-enable for a multi-cycle handshake will not.
- **Fix:** Use `ioctl_wr` strictly as a one-cycle write-enable in the `clk_sys` domain. Treat `ioctl_download` as the level signal that frames the entire transfer; treat `ioctl_wr` as the per-word strobe.
- **Citation:** `archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:632-634,693 @ f35083f3b40d`

### A.2 Reading `ioctl_addr` on the falling edge of `ioctl_download` as "last byte address"

- **Symptom:** ROM size reported by the core is off by one, or post-load logic that uses `ioctl_addr` as the high water mark indexes one past the last valid byte.
- **Cause:** When the HPS sends the end-of-transfer `FIO_FILE_TX` (byte 0), `hps_io` does one final `ioctl_addr <= ioctl_addr + step` in the same cycle it clears `ioctl_download`. The post-falling-edge value is "number of words written", not "address of the last word".
- **Fix:** Either (a) latch `ioctl_addr` on `ioctl_wr` (last write address) instead of on the falling edge of `ioctl_download`, or (b) subtract one step when reading `ioctl_addr` after the transfer.
- **Citation:** `archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:676-680 @ f35083f3b40d`

### A.3 Assuming `ioctl_addr` wraps or restarts within a transfer

- **Symptom:** Loading a file larger than the core's RAM corrupts data near the wrap point, or a multi-section ROM is mis-aligned.
- **Cause:** `ioctl_addr` is a free-running 27-bit counter inside a single transfer; it does not wrap to 0, does not segment, and does not announce ROM-region boundaries. The HPS-side composite/multi-part logic (e.g. MRA) issues separate transfers with separate start addresses.
- **Fix:** Treat each `ioctl_download` pulse as one contiguous region. Use `ioctl_index` to demultiplex sub-files. Mask `ioctl_addr` only with bits sufficient for the target memory (and validate that the file fits).
- **Citation:** `archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:671-683,688 @ f35083f3b40d`

### A.4 Using `ioctl_index == 0` as the "my custom slot" sentinel

- **Symptom:** Loading a custom file from an F-slot also matches boot.rom autoload; or a core misroutes boot.rom into a save-RAM region.
- **Cause:** `ioctl_index == 0` is reserved for boot.rom by convention; `Main_MiSTer` autoloads `boot.rom` from the core's home directory with index 0 at startup. Custom slots should use a non-zero F-slot index (`[5:0]` >= 1).
- **Fix:** Reserve `ioctl_index == 0` for boot.rom (or leave unhandled). Encode custom F-slots starting at `[5:0] = 1` (boot1.rom uses `[5:0]=0, [15:6]=1` per the framework convention).
- **Citation:** `archive/github/MiSTer-devel/Main_MiSTer/user_io.cpp:1586-1590,2664 @ 136737b4bed4`; `archive/github/MiSTer-devel/MkDocs_MiSTer/docs/developer/hps_io.md:208,234 @ 9033bd292fdc`

### A.5 Forgetting to act on the rising/falling edge of `ioctl_download`

- **Symptom:** Core continues running normally during ROM load and sees half-written ROM; or the core stays in reset after load completes.
- **Cause:** `ioctl_download` is a level. A core that only edge-detects it for "go to reset" and never edge-detects the falling edge for "release reset" will hang.
- **Fix:** Detect both edges (`ioctl_download` rising → assert internal load-reset; `ioctl_download` falling, possibly one cycle later, → release reset and begin normal operation).
- **Citation:** `archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:638,678-679 @ f35083f3b40d`

## 8. Verification

- **Simulation:** Drive `HPS_BUS` from a testbench that mirrors the `user_io_set_index → user_io_file_info → user_io_set_download(1) → user_io_file_tx_data*N → user_io_set_download(0)` sequence. Confirm that `ioctl_wr` pulses exactly N times, `ioctl_addr` ranges 0..N-1 (or 0..2N-2 in `WIDE=1`), and `ioctl_download` deasserts one cycle after the final increment.
- **Back-pressure:** Force the core to assert `ioctl_wait` for several `clk_sys` cycles mid-transfer and confirm `io_strobe` stops (HPS-side stall). Path: `ioctl_wait → HPS_BUS[37] → io_wait → strobe gate` in `sys_top.v:259`. (archive/github/MiSTer-devel/Template_MiSTer/sys/sys_top.v:259 @ f35083f3b40d)
- **Bring-up signal:** Drop the OSD with the FPGA running and load a small ROM via an F-slot; watch the `Loading` progress message in `Main_MiSTer` (`ProgressMessage(...)` inside `user_io_file_tx`) — if it advances to "Done" then the FPGA acked every strobe. (archive/github/MiSTer-devel/Main_MiSTer/user_io.cpp:2624,2631 @ 136737b4bed4)
- **CRC check:** `user_io_file_tx` accumulates `file_crc` on the HPS side. A core can compute its own CRC32 on `ioctl_wr` and compare via a debug status bit to confirm exact byte sequence and ordering. (archive/github/MiSTer-devel/Main_MiSTer/user_io.cpp:2679 @ 136737b4bed4)
- **Save-back smoke:** Pulse `ioctl_upload_req`, open the OSD, and confirm the HPS receives the request (opcode `0x3C` returns the latched index). Then trigger an HPS-side `user_io_set_upload(1)` + `user_io_file_rx_data` + `user_io_set_upload(0)` and verify `ioctl_rd` pulses on each word. (archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:289-290,335 @ f35083f3b40d; archive/github/MiSTer-devel/Main_MiSTer/user_io.cpp:2048-2067 @ 136737b4bed4)
- **MiSTer.ini knobs:** `bootcore`, `bootcore_timeout`, and `direct_video` do not influence the ioctl path; symptoms there are usually `CONF_STR` extension mismatch (see [11-conf-str.md](11-conf-str.md)) or core-side address aliasing.

## 9. Provenance footer

- `archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv @ f35083f3b40d` — port block, FIO state machine, addr/skip_add/upload_req logic; used for §2, §3, §4.1, §4.2, §7.
- `archive/github/MiSTer-devel/Template_MiSTer/sys/sys_top.v @ f35083f3b40d` — `io_wait` strobe gate; used for §2 (rule 9), §8.
- `archive/github/MiSTer-devel/Main_MiSTer/user_io.cpp @ 136737b4bed4` — `user_io_set_index`, `user_io_set_download`, `user_io_set_upload`, `user_io_file_tx_data`, `user_io_file_rx_data`, `user_io_file_info`, `user_io_file_tx`, `user_io_ext_idx`, boot.rom autoload; used for §2 (rule 10, 11, 12), §4.3, §6, §7 (A.4), §8.
- `archive/github/MiSTer-devel/Main_MiSTer/user_io.h @ 136737b4bed4` — FIO opcode constants `0x53/0x54/0x55/0x56`; used for §4.3.
- `archive/github/MiSTer-devel/MkDocs_MiSTer/docs/developer/hps_io.md @ 9033bd292fdc` — `ioctl_index` `[15:6]`/`[5:0]` split and boot.rom convention; used for §2 (rule 10), §7 (A.4).
- Brief-listed but unused: `Main_MiSTer/file_io.cpp`, `Main_MiSTer/file_io.h` (no ioctl logic; flagged at top of file).
