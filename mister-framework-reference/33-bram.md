# 33 — BRAM (On-Chip Block RAM)

> Bundle version: 2026-05-18
> Pinned commits: `Template_MiSTer @ f35083f3b40d`, `MkDocs_MiSTer @ 9033bd292fdc`
> Load with: [30-sdram.md](30-sdram.md), [31-ddram.md](31-ddram.md), [32-rom-save-state-flows.md](32-rom-save-state-flows.md), [40a-video-pipeline.md](40a-video-pipeline.md)
> Status mix: [C] [V] [O] [I]

> Source notes:
> - This is a **synthesis-inference contract** with Quartus, not a framework-side contract. The framework does not export "BRAM ports"; cores and `sys/` modules infer BRAM from RTL idioms.
> - Brief-listed `audio_out.sv` and `spdif.v` contain **no direct BRAM declarations** — `audio_out` only instantiates submodules (registered state only) and `spdif.v` is purely flop-based. They appear in the §3 consumer table marked accordingly.
> - Brief-listed `iir_filter.v` declares its only array as `(* ramstyle = "logic" *)` — i.e. an explicit *opt-out* of BRAM. It is documented here as a negative example.
> - Brief-listed `scandoubler.v` has no line buffer directly — it instantiates `Hq2x`, whose `hq2x_buf` submodule (`hq2x.sv`) is the actual BRAM consumer.
> - DDR3 framebuffer / scaler architecture is deferred to `40a-video-pipeline.md`; only BRAM-relevant ascal aspects are cited.
> - Reference-core RTL is not in the archive snapshot; §6 marks per-core RTL variations as `[deferred — reference cores not fetched]`.

## 1. Purpose & one-line summary

BRAM is the FPGA's on-chip block memory — the third memory tier alongside SDRAM (off-chip SDR) and DDRAM (HPS-side DDR3). On the DE10-Nano's Cyclone V SoC FPGA (5CSEBA6U23I7) the BRAM substrate is the M10K block (10 Kibit each). Cores and `sys/` modules use it for line buffers, sector buffers, character/coefficient ROMs, FIFOs, register files, and any small fast-access memory whose timing or two-port topology rules out SDRAM/DDRAM.

## 2. The contract (must-obey)

BRAM is inferred from RTL by Quartus, not wired from the framework. The rules below are the idioms that reliably land in M10K blocks. Violation does not break the build — it silently falls back to MLAB (LUT-RAM) or pure logic, blowing the resource budget.

- The DE10-Nano part is Cyclone V `5CSEBA6U23I7`; that part contains **553 M10K blocks**, each 10 Kibit (10 240 bits). [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/sys.tcl:2 @ f35083f3b40d) [I] (Intel/Altera Cyclone V Device Handbook, Memory section, for the 5CSEBA6 die)
- Each M10K block is 10 240 bits and supports byte-write granularity (per-port byte enables); legal per-port data widths are 1, 2, 4, 5, 8, 10, 16, 20, 32, and 40 bits depending on the configuration. [I] (Intel/Altera Cyclone V Device Handbook, Embedded Memory Blocks)
- An array declared as `reg [W-1:0] mem[0:N-1]` is inferred as block RAM only when its read path is registered with a synchronous read (`q <= mem[addr]` inside `always @(posedge clk)`). [V] (archive/github/MiSTer-devel/Template_MiSTer/sys/hq2x.sv:260-265 @ f35083f3b40d, archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:1029-1038 @ f35083f3b40d)
- A combinational read path (`assign q = mem[addr];`) DOES NOT infer M10K — Quartus implements it as MLAB or distributed memory regardless of size. [I] (Quartus inference rules; absence of any combinational-read inferred-RAM in the archive)
- An asynchronous reset on the output register of an inferred RAM disables the M10K target (only synchronous clear is supported on the M10K output register). [I] (Intel/Altera Cyclone V Device Handbook, Embedded Memory Blocks)
- The framework convention is `(* ramstyle = "no_rw_check" *)` on the array declaration when the writer and reader never collide (read-during-write hazard is don't-care); this attribute tells Quartus to ignore implicit RAM-conflict resolution and pick the smallest M10K footprint. [V] (archive/github/MiSTer-devel/Template_MiSTer/sys/osd.v:36 @ f35083f3b40d, archive/github/MiSTer-devel/Template_MiSTer/sys/gamma_corr.sv:22,84-86 @ f35083f3b40d, archive/github/MiSTer-devel/Template_MiSTer/sys/ascal.vhd:337,383,391,460-461,496,500-507,1023-1025 @ f35083f3b40d)
- The framework convention to **opt out** of BRAM is `(* ramstyle = "logic" *)` (Verilog/SystemVerilog) or VHDL attribute `ramstyle ... IS "logic"`; this forces ALMs/MLABs and is reserved for tiny arrays where M10K would be wasted. [V] (archive/github/MiSTer-devel/Template_MiSTer/sys/iir_filter.v:178 @ f35083f3b40d, archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:731 @ f35083f3b40d, archive/github/MiSTer-devel/Template_MiSTer/sys/ascal.vhd:519,544,552 @ f35083f3b40d)
- The framework convention for a small ROM that should live in MLAB rather than M10K is `(* romstyle = "MLAB" *)`. [V] (archive/github/MiSTer-devel/Template_MiSTer/sys/hq2x.sv:35 @ f35083f3b40d)
- ROM contents may be initialized from a `.hex` file via `$readmemh("file.hex", arr)` in an `initial` block; the framework uses this to fall back when the `CONF_STR` parameter is empty (`hps_io`'s `confstr_rom`). [V] (archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:1031-1036 @ f35083f3b40d)
- ROM contents may also be initialized inline by `initial begin arr = '{ ... }; end` (SystemVerilog array literal) — preferred when the values are short, fixed, and code-visible. [V] (archive/github/MiSTer-devel/Template_MiSTer/sys/hq2x.sv:36-55 @ f35083f3b40d)
- `.mif` and `.hex` initialization files are resolved against Quartus's project search path; the framework only ships `pll_cfg.mif` under `sys/pll_cfg/` (referenced by the PLL-reconfig IP, not by user-side BRAM). [V] (archive/github/MiSTer-devel/Template_MiSTer/sys/pll_cfg/pll_cfg.v:31 @ f35083f3b40d)
- For two-clock-domain BRAM the framework convention is **simple-dual-port (SDP)** with one write port on `clk_sys` and one read port on the consumer's clock (e.g. `clk_vid`); cores must accept the inherent one-cycle read latency of the M10K output register. [V] (archive/github/MiSTer-devel/Template_MiSTer/sys/gamma_corr.sv:22-25,84-86,95-101 @ f35083f3b40d)
- For arbitrated dual-write topologies (e.g. SD-card sector buffer accessed by `clk_sys` and `clk_spi` both reading and writing), the framework uses an explicit `altsyncram` primitive with `operation_mode = "BIDIR_DUAL_PORT"` rather than relying on inference. [O] (archive/github/MiSTer-devel/Template_MiSTer/sys/sd_card.sv:88-141 @ f35083f3b40d)
- The framework convention is to disable RAM power-up content (`power_up_uninitialized = "FALSE"`) on `altsyncram` so the block boots with deterministic zeros. [O] (archive/github/MiSTer-devel/Template_MiSTer/sys/sd_card.sv:136 @ f35083f3b40d)
- Read-during-write semantics for the framework's primitive instance are `"NEW_DATA_NO_NBE_READ"` on both ports — a same-cycle read of a written address returns the new data only for bytes whose byte-enable was high. [O] (archive/github/MiSTer-devel/Template_MiSTer/sys/sd_card.sv:137-138 @ f35083f3b40d)
- Output registers on the framework's TDP instance are `outdata_reg_a = "UNREGISTERED"` / `outdata_reg_b = "UNREGISTERED"`, trading the second pipeline register for one cycle of latency; M10K still infers because the input/address stage is registered. [O] (archive/github/MiSTer-devel/Template_MiSTer/sys/sd_card.sv:134-135 @ f35083f3b40d)
- Long shift registers (depth > 4 or so) are inferred as M10K-backed shift-register chains by default; the framework forces them to ALMs with `ramstyle "logic"` and the explanatory comment `-- avoid blockram shift register`. [V] (archive/github/MiSTer-devel/Template_MiSTer/sys/ascal.vhd:519,544,552 @ f35083f3b40d)
- A BRAM with both write and read on the same clock can be SDP using a single inferred `always_ff` block in which write and read are independent statements; this is the canonical line-buffer idiom. [V] (archive/github/MiSTer-devel/Template_MiSTer/sys/hq2x.sv:260-265 @ f35083f3b40d)
- The framework never relies on a specific power-on data pattern for inferred BRAM; cores that need known initial contents must use `$readmemh`/`initial` or an `altsyncram` with `init_file` (not used in `sys/`). [I] (no `init_file` references in `sys/*` outside `pll_cfg`)
- A user-implementable BRAM cell can be 1-bit wide on the port (legal M10K width), but the block still allocates a full 10 Kibit; very narrow + shallow arrays are silently mapped to MLAB to save M10K count. [I] (Intel/Altera Cyclone V Device Handbook, Embedded Memory Blocks)

## 3. Ports / signals reference

BRAM has no framework "port set" — instead the contract has three **shapes** corresponding to `altsyncram`'s `operation_mode` values and the equivalent inferred idioms. The framework's BRAM consumers are listed in §3.2.

### 3.1 The three BRAM shapes

| Shape | Write ports | Read ports | Clocks | Supported widths (per port) | Typical use | `altsyncram operation_mode` | Inference idiom |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Single-port | 1 | 1 (shared with write address) | 1 | 1/2/4/5/8/10/16/20/32/40 | Mode-register ROMs, scratch buffer with one master | `SINGLE_PORT` | `always_ff @(posedge clk) begin if (we) m[a]<=d; q<=m[a]; end` [V] |
| Simple-dual-port (SDP) | 1 | 1 (independent address) | 1 or 2 | Independent per port (mixed-width OK) | Line buffers, FIFOs, control-plane LUTs (e.g. gamma) | `DUAL_PORT` | `always_ff @(posedge wclk) if(we) m[wa]<=d;` + `always_ff @(posedge rclk) q<=m[ra];` [V] |
| True-dual-port (TDP) | 2 | 2 (each port independent R+W) | 1 or 2 (one per port) | Independent per port (mixed-width OK) | Sector buffers, frame buffers shared by two masters | `BIDIR_DUAL_PORT` | Explicit `altsyncram` primitive instance with `clock0`/`clock1`, `data_a`/`data_b`, `wren_a`/`wren_b`, `q_a`/`q_b` [O] |

Notes:
- All shapes are `[C]` `altsyncram` modes that Cyclone V M10K supports natively.
- The framework infers single-port and SDP from idiomatic always blocks; the only TDP in `sys/` is the explicit `altsyncram sdbuf` instance in `sd_card.sv`.
- Mixed-width ports allow e.g. an 8-bit writer and 32-bit reader on the same array (common in audio FIFOs and packed-pixel framebuffers); the inferred form requires two array declarations with the same backing memory and the explicit `altsyncram` form sets `width_a` / `width_b` independently. [I] (Intel/Altera Cyclone V Device Handbook, Mixed-Width Mode)
- Read-during-write semantics differ by mode: SDP defaults to "don't care"; TDP supports `NEW_DATA`, `OLD_DATA`, or `DONT_CARE`, but cross-port collisions in TDP are not protected and produce undefined data. [I] (Intel/Altera Cyclone V Device Handbook, Read-During-Write Behavior)

### 3.2 Framework BRAM consumers

| Module | Shape | Anchor line(s) | Width × depth | Purpose |
| --- | --- | --- | --- | --- |
| `sys/hps_io.sv` — `confstr_rom` | Single-port ROM | hps_io.sv:1029-1038 | 8 × `STRLEN` | CONF_STR delivered as memory; init via `$readmemh("cfgstr.hex")` or array-literal init [V] |
| `sys/hps_io.sv` — PS/2 `fifo` | n/a — `ramstyle="logic"` | hps_io.sv:731 | 8 × (1<<PS2_FIFO_BITS) | Tiny PS/2 byte FIFO; deliberately forced to ALMs [V] |
| `sys/osd.v` | SDP, 2 clocks | osd.v:36, 94, 251 | 8 × 4096 (or 5120 in MENU_CORE) | Character/overlay buffer; write `clk_sys` (line 94), read `clk_video` (line 251) [V] |
| `sys/gamma_corr.sv` — `gamma_curve` | SDP, 2 clocks | gamma_corr.sv:22-25 | 8 × 768 | Combined RGB gamma LUT; write `clk_sys`, read `clk_vid` [V] |
| `sys/gamma_corr.sv` — `gamma_curve_{r,g,b}` (`gamma_fast`) | SDP, 2 clocks | gamma_corr.sv:84-86,95-117 | 8 × 256 × 3 | Per-channel gamma LUT [V] |
| `sys/shadowmask.sv` — `mask_lut` | SDP, 2 clocks | shadowmask.sv:27, 76, 129 | 11 × 256 | Pixel shadowmask LUT; write `clk_sys`, read `clk` [V] |
| `sys/hq2x.sv` — `hqTable` | Single-port ROM (forced MLAB) | hq2x.sv:35-55 | 6 × 256 | HQ2x rule table; `romstyle="MLAB"` because depth is small [V] |
| `sys/hq2x.sv` — `hq2x_buf.ram` (instantiated as `hq2x_in` × 2, `hq2x_out`) | SDP, 1 clock | hq2x.sv:260-265 | (`DWIDTH+1`) × `NUMWORDS` | Line buffers for HQ2x upscaler; same-clock SDP [V] |
| `sys/sd_card.sv` — `sdbuf` | TDP, 2 clocks | sd_card.sv:88-141 | 8/16 × N | SD sector buffer shared by `clk_sys` and `clk_spi`; explicit `altsyncram` primitive [O] |
| `sys/scandoubler.v` | n/a — delegates to `Hq2x` | scandoubler.v:103-117 | (see hq2x.sv) | No direct BRAM; instantiates `Hq2x` which owns the line buffers [V] |
| `sys/audio_out.sv` | n/a — no direct BRAM | audio_out.sv (full file) | — | Pure flop pipeline; only submodule state. No FIFO BRAM. [V] |
| `sys/spdif.v` | n/a — no direct BRAM | spdif.v (full file) | — | Pure flop bit-encoder; no buffer storage. [V] |
| `sys/iir_filter.v` — `intreg` | n/a — `ramstyle="logic"` | iir_filter.v:178 | 40 × 2 | Tap state; explicitly forced to ALMs (too small for M10K) [V] |
| `sys/ascal.vhd` — `i_dpram`/`o_dpram` (Avalon block FIFOs) | SDP, 2 clocks | ascal.vhd:382-383, 495-496 | `N_DW` × (2·BLEN) | DDR3 burst staging FIFOs at the scaler's input/output [V] |
| `sys/ascal.vhd` — `o_line0..3`, `o_linf0..3` (line buffers) | SDP, 2 clocks | ascal.vhd:497-507 | pixel × OHRESL/OHRESM | Scaler output line buffers (post-polyphase) [V] |
| `sys/ascal.vhd` — `pal1_mem`/`pal2_mem` (palette RAM) | SDP, 2 clocks | ascal.vhd:460-461 | `N_DW` × N | Indexed-mode palette for framebuffer cores [V] |
| `sys/ascal.vhd` — `o_h_poly_mem`/`o_v_poly_mem`/`o_a_poly_mem` | SDP, 1 clock | ascal.vhd:1020-1025 | 40 × 2^FRAC | Polyphase coefficient ROMs [V] |
| `sys/mt32pi.sv` — `lcd_data` | Single-port | mt32pi.sv:149 | 8 × 1024 | mt32-pi LCD framebuffer [V] |

## 4. Sequencing & timing

BRAM timing is per-shape. All three shapes share the same fundamental rule: **the read result for cycle N's address appears at the output register on cycle N+1** (one cycle of synchronous-read latency). The framework's primitives use `outdata_reg_* = "UNREGISTERED"`, i.e. the M10K output register is the *only* register stage — no extra pipeline cycle.

### 4.1 Single-port write/read cycle

A single-port BRAM has one address bus and one write-enable per cycle.

```
clk      __|‾‾|__|‾‾|__|‾‾|__|‾‾|__|‾‾|__
we       __/‾‾‾‾‾‾\___________________
addr     XXXX  A0  XX  A0  XXXXXXXXXXX
data     XXXX  D0  XXXXXXXXXXXXXXXXXX
q        XXXXXXXXXXXX  ????  D0  ????
                       ^^^^         ^
                  read latency: q reflects mem[A0] one clk after addr is sampled.
                  During the write cycle, q is undefined (or = D0 with NEW_DATA
                  read-during-write mode; depends on synthesis attribute).
```

### 4.2 SDP with two clocks (the scandoubler / line-buffer / gamma pattern)

Writer on `clk_w`, reader on `clk_r`. The two clocks are usually unrelated (e.g. `clk_sys` and `clk_vid`). M10K guarantees read coherency only on the read clock domain — writes from the other domain race the reader.

```
clk_w    __|‾‾|__|‾‾|__|‾‾|__|‾‾|__|‾‾|________________________
we       __/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\__________________________________
waddr    XXX  A0      A1      A2  XXXXXXXXXXXXXXXXXXXXXXXXXXXXX
wdata    XXX  D0      D1      D2  XXXXXXXXXXXXXXXXXXXXXXXXXXXXX

clk_r           __|‾|__|‾|__|‾|__|‾|__|‾|__|‾|__|‾|__|‾|__
raddr           XXXX  A0      A1      A2  XXXXXXXXXXXXX
q               XXXXXXXXXXX   D0      D1?     D2          <-- one clk_r tick of
                                                              latency; "?" because
                                                              A1's data was being
                                                              written when read
                                                              fired (race).
```

Read-during-write on a *different* clock is **undefined** for inferred SDP — the framework's `(* ramstyle = "no_rw_check" *)` annotation tells Quartus the writer/reader never collide (the consumer designs around this). [V] (archive/github/MiSTer-devel/Template_MiSTer/sys/gamma_corr.sv:22 @ f35083f3b40d)

### 4.3 TDP with two clocks (the SD-card buffer pattern)

Both ports can read and write independently. Each port has its own clock, address, data-in, write-enable, and data-out. Cross-port writes to the same address are unsafe (output is undefined). For `sdbuf` in `sd_card.sv` the two ports are partitioned by `sd_buf`/`spi_buf` selectors so the two clocks never address the same word.

```
clk_sys (port A) __|‾|__|‾|__|‾|__|‾|__
wren_a              __/‾‾‾\___________
address_a           XX  Ax  XXXXXXXXXX
data_a              XX  Dx  XXXXXXXXXX
q_a                 XXXXXX  Ax_read   <-- 1 clk_sys cycle after address_a settles

clk_spi (port B)  ____|‾|____|‾|____|‾|__
wren_b               __/‾‾‾\___________
address_b            XX  Ay  XXXXXXXXX
data_b               XX  Dy  XXXXXXXXX
q_b                  XXXXXX  Ay_read  <-- 1 clk_spi cycle after address_b settles
```

The framework's `read_during_write_mode_port_a/b = "NEW_DATA_NO_NBE_READ"` means a same-port simultaneous read+write returns the new data (only for byte-enable-asserted bytes); cross-port collisions remain undefined. [O] (archive/github/MiSTer-devel/Template_MiSTer/sys/sd_card.sv:137-138 @ f35083f3b40d)

### 4.4 Reset behavior

The M10K block ignores any asynchronous reset on its output register. The framework's primitive sets `outdata_aclr_a/b = "NONE"` — any reset of the data-out path must be implemented downstream of the BRAM by the consumer logic. [O] (archive/github/MiSTer-devel/Template_MiSTer/sys/sd_card.sv:132-133 @ f35083f3b40d)

## 5. Minimal working patterns

Three patterns, each verbatim from a `sys/` consumer.

### 5.1 Single-port ROM initialized from `.hex`

```verilog
// archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:1022-1040 @ f35083f3b40d
module confstr_rom #(parameter CONF_STR, STRLEN)
(
	input      clk_sys,
	input      [$clog2(STRLEN+1)-1:0] conf_addr,
	output reg [7:0] conf_byte
);

reg [7:0] rom[STRLEN];

initial begin
	if( CONF_STR=="" )
		$readmemh("cfgstr.hex",rom);
	else
		for(int i = 0; i < STRLEN; i++) rom[i] = CONF_STR[((STRLEN-i)*8)-1 -:8];
end

always @ (posedge clk_sys) conf_byte <= rom[conf_addr];

endmodule
```

Key elements that drive M10K inference: array `rom`, synchronous read register `conf_byte`, single clock, no asynchronous reset, no write path (read-only).

### 5.2 SDP with clock-domain crossing — `gamma_corr.sv`

```verilog
// archive/github/MiSTer-devel/Template_MiSTer/sys/gamma_corr.sv:22-25 @ f35083f3b40d
(* ramstyle="no_rw_check" *) reg [7:0] gamma_curve[768];

always @(posedge clk_sys) if (gamma_wr) gamma_curve[gamma_wr_addr] <= gamma_value;
always @(posedge clk_vid) gamma <= gamma_curve[gamma_index];
```

Key elements: distinct write clock (`clk_sys`) and read clock (`clk_vid`); separate `always` blocks; `no_rw_check` attribute because the writer never collides with the reader by construction (writes happen during gamma-table reload, reads during pixel processing). The output `gamma` is a register, not a wire.

### 5.3 SDP same-clock line buffer — `hq2x.sv` (the canonical line buffer)

```verilog
// archive/github/MiSTer-devel/Template_MiSTer/sys/hq2x.sv:250-267 @ f35083f3b40d
module hq2x_buf #(parameter NUMWORDS, parameter AWIDTH, parameter DWIDTH)
(
	input                 clock,
	input      [DWIDTH:0] data,
	input      [AWIDTH:0] rdaddress,
	input      [AWIDTH:0] wraddress,
	input                 wren,
	output reg [DWIDTH:0] q
);

reg [DWIDTH:0] ram[0:NUMWORDS-1];

always_ff@(posedge clock) begin
	if(wren) ram[wraddress] <= data;
	q <= ram[rdaddress];
end

endmodule
```

Key elements: separate write/read addresses on the same clock; single `always_ff`; registered `q`. Quartus targets M10K with `new-data` read-during-write semantics by default.

### 5.4 TDP — explicit `altsyncram` primitive from `sd_card.sv`

```verilog
// archive/github/MiSTer-devel/Template_MiSTer/sys/sd_card.sv:88-141 @ f35083f3b40d
altsyncram sdbuf
(
	.clock0    (clk_sys),
	.address_a ({sd_buf,sd_buff_addr}),
	.data_a    (sd_buff_dout),
	.wren_a    (sd_ack & sd_buff_wr),
	.q_a       (sd_buff_din),

	.clock1    (clk_spi),
	.address_b ({spi_buf,buffer_ptr}),
	.data_b    (buffer_din),
	.wren_b    (buffer_wr),
	.q_b       (buffer_dout),

	.aclr0(1'b0),
	.aclr1(1'b0),
	.addressstall_a(1'b0),
	.addressstall_b(1'b0),
	.byteena_a(1'b1),
	.byteena_b(1'b1),
	.clocken0(1'b1),
	.clocken1(1'b1),
	.clocken2(1'b1),
	.clocken3(1'b1),
	.eccstatus(),
	.rden_a(1'b1),
	.rden_b(1'b1)
);
defparam
	sdbuf.numwords_a = 1<<(AW+3),
	sdbuf.widthad_a  = AW+3,
	sdbuf.width_a    = DW+1,
	sdbuf.numwords_b = 2048,
	sdbuf.widthad_b  = 11,
	sdbuf.width_b    = 8,
	sdbuf.address_reg_b = "CLOCK1",
	sdbuf.clock_enable_input_a = "BYPASS",
	sdbuf.clock_enable_input_b = "BYPASS",
	sdbuf.clock_enable_output_a = "BYPASS",
	sdbuf.clock_enable_output_b = "BYPASS",
	sdbuf.indata_reg_b = "CLOCK1",
	sdbuf.intended_device_family = "Cyclone V",
	sdbuf.lpm_type = "altsyncram",
	sdbuf.operation_mode = "BIDIR_DUAL_PORT",
	sdbuf.outdata_aclr_a = "NONE",
	sdbuf.outdata_aclr_b = "NONE",
	sdbuf.outdata_reg_a = "UNREGISTERED",
	sdbuf.outdata_reg_b = "UNREGISTERED",
	sdbuf.power_up_uninitialized = "FALSE",
	sdbuf.read_during_write_mode_port_a = "NEW_DATA_NO_NBE_READ",
	sdbuf.read_during_write_mode_port_b = "NEW_DATA_NO_NBE_READ",
	sdbuf.width_byteena_a = 1,
	sdbuf.width_byteena_b = 1,
	sdbuf.wrcontrol_wraddress_reg_b = "CLOCK1";
```

Key elements: two clocks (`clock0`, `clock1`), two complete R+W port sets, mixed widths permitted (`width_a` ≠ `width_b`), `operation_mode = "BIDIR_DUAL_PORT"`, no async clear, no power-up init, NEW_DATA same-port read-during-write.

### 5.5 The opt-out pattern (force to ALMs)

```verilog
// archive/github/MiSTer-devel/Template_MiSTer/sys/iir_filter.v:178 @ f35083f3b40d
(* ramstyle = "logic" *) reg [39:0] intreg[2];
```

For arrays so small that an M10K block would be > 99% wasted — here a 2-entry × 40-bit register file — `ramstyle="logic"` forces ALMs. The PS/2 FIFO in `hps_io.sv:731` (`reg [7:0] fifo[1<<PS2_FIFO_BITS]`) uses the same pattern.

## 6. Common variations across cores

Per-core BRAM topology (sprite caches, tile RAM, sample ROMs, work RAM sized to fit M10K vs. spill to SDRAM/DDRAM) is `[deferred — reference cores not fetched]`. The variations below are framework-implied, observable within `sys/` and `Template_MiSTer`.

- **Line-buffer width**: `hq2x_in` allocates line buffers at `(DWIDTH+1)` bits × `LENGTH` where `DWIDTH` is 11 for `HALF_DEPTH=1` and 23 for `HALF_DEPTH=0` — i.e. 12-bit-wide or 24-bit-wide line buffers per pixel. `hq2x_out` allocates the output buffer at `(DWIDTH1*4-1)` bits × `LENGTH*2`, i.e. 4× the per-pixel width because four neighbor pixels are packed per word. [V] (archive/github/MiSTer-devel/Template_MiSTer/sys/hq2x.sv:32-33,101-115,126-141 @ f35083f3b40d)
- **ROM init style**: `confstr_rom` uses `$readmemh("cfgstr.hex", rom)` so the build-time CONF_STR can be regenerated as a hex file; `hq2x`'s rule table uses an inline `initial begin hqTable = '{ ... }; end` array literal because the values are fixed by the HQ2x algorithm and version-controlled in RTL. [V] (archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:1031-1036 @ f35083f3b40d; archive/github/MiSTer-devel/Template_MiSTer/sys/hq2x.sv:36-55 @ f35083f3b40d)
- **Storage attribute selection**: most LUT-style ROMs use no explicit `ramstyle` (Quartus picks M10K); the HQ2x rule table is annotated `(* romstyle = "MLAB" *)` because depth=256 × width=6 is a wasteful M10K target (1 block = 10 240 bits, this table needs 1 536 bits). [V] (archive/github/MiSTer-devel/Template_MiSTer/sys/hq2x.sv:35 @ f35083f3b40d)
- **`gamma_corr` vs. `gamma_fast`**: the slower variant uses a single 768-entry table indexed by `{channel, value}` (multiplexed across three pixel cycles); the `gamma_fast` variant uses three parallel 256-entry tables, trading one M10K block for three to halve the per-pixel latency. [V] (archive/github/MiSTer-devel/Template_MiSTer/sys/gamma_corr.sv:22 vs. 84-86 @ f35083f3b40d)
- **TDP vs. SDP**: `sd_card.sv` uses an explicit TDP `altsyncram` primitive because both `clk_sys` and `clk_spi` masters need read-and-write access to the sector buffer; `gamma_corr.sv` uses inferred SDP because `clk_sys` only writes and `clk_vid` only reads. [O] (archive/github/MiSTer-devel/Template_MiSTer/sys/sd_card.sv:88-141 @ f35083f3b40d; archive/github/MiSTer-devel/Template_MiSTer/sys/gamma_corr.sv:22-25 @ f35083f3b40d)
- **Opt-out granularity**: `iir_filter.v` opts a 2 × 40-bit register file out of BRAM; `hps_io.sv` opts an 8-wide PS/2 FIFO of `1<<PS2_FIFO_BITS` entries out of BRAM; `ascal.vhd` opts long shift registers (`o_hfrac`, `o_hpixq`, `o_div`/`o_dir`) out of BRAM with the explanatory comment `-- avoid blockram shift register`. [V] (archive/github/MiSTer-devel/Template_MiSTer/sys/iir_filter.v:178, sys/hps_io.sv:731, sys/ascal.vhd:519,544,552 @ f35083f3b40d)
- **`ascal.vhd` line-buffer multiplicity**: the scaler keeps four output line buffers (`o_line0..3`) and four "first-line" mirrors (`o_linf0..3`) all annotated `ramstyle "no_rw_check"`. The reason — four lines worth of polyphase taps — is structural to ascal, not core-specific. [V] (archive/github/MiSTer-devel/Template_MiSTer/sys/ascal.vhd:497-507 @ f35083f3b40d)
- **CONF_STR storage parameter `CONF_STR_BRAM`**: `hps_io` accepts a parameter that toggles whether the CONF_STR sits in a BRAM-inferred ROM (`confstr_rom`) or in a build-time string constant baked into logic. Default = 1 (BRAM); cores tight on M10K can set it to 0. [V] (archive/github/MiSTer-devel/MkDocs_MiSTer/docs/developer/hps_io.md:25 @ 9033bd292fdc)
- **Per-core BRAM consumers** (sprite caches, palette RAMs, sample lookup tables, tile maps, CPU register files implemented as M10K rather than ALMs) — `[deferred — reference cores not fetched]`.

## 7. Anti-patterns

### A.1 Combinational read — silently falls back to MLAB/logic

- **Symptom:** A memory the engineer expected to use M10K does not appear in the Fitter Resource Summary's M10K column; logic utilization jumps; timing closure fails for the read path; OSD-side BRAM count stays the same as before the new array was added.
- **Cause:** The read path is combinational (`assign q = mem[addr];` or `q = mem[addr]` in a non-clocked `always_comb`). Quartus only infers M10K when the read result is captured in a synchronous register clocked by the same clock that owns the write side (or the read side, for SDP). Combinational reads are mapped to MLAB or pure LUT-RAM regardless of depth.
- **Fix:** Wrap the read in a `posedge clk` always block: `always_ff @(posedge clk) q <= mem[addr];` and accept the one-cycle latency.
- **Citation:** archive/github/MiSTer-devel/Template_MiSTer/sys/hq2x.sv:260-265 @ f35083f3b40d (the correct registered-read pattern); archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:1029-1038 @ f35083f3b40d (registered read with `$readmemh`).

### A.2 Asynchronous reset on the inferred RAM's output — defeats M10K inference

- **Symptom:** Quartus's Compilation Report shows the array implemented as MLAB or logic. Synthesis warnings mention "RAM logic ... has incompatible reset" or "not inferred as block RAM because of asynchronous reset".
- **Cause:** The M10K output register supports synchronous clear only. Any `always_ff @(posedge clk or posedge rst) if (rst) q <= 0;` style on an inferred RAM cancels M10K targeting.
- **Fix:** Use synchronous reset, or — more commonly — do not reset the RAM data path at all (let the writer overwrite stale values). For initial contents, use `$readmemh` or an `initial` block. The framework's `altsyncram` instances set `outdata_aclr_a/b = "NONE"`.
- **Citation:** archive/github/MiSTer-devel/Template_MiSTer/sys/sd_card.sv:132-133 @ f35083f3b40d (explicit `outdata_aclr = "NONE"`); [I] (Intel/Altera Cyclone V Device Handbook, Embedded Memory Blocks — reset modes).

### A.3 Long shift register silently consuming M10K — `ramstyle="logic"` missing

- **Symptom:** M10K block count balloons after adding a multi-stage delay line or pixel-pipeline shift register; the count grows by far more than the obvious BRAMs would predict; the design fails to fit.
- **Cause:** Quartus recognizes a chain like `reg [W-1:0] sr[0:N-1];` with `sr[i] <= sr[i-1]` as a shift register and offers to implement it in M10K via the "Shift Register Inference" pass. For longish chains (depth > ~6), each instance consumes a full M10K block.
- **Fix:** Annotate the array declaration with `(* ramstyle = "logic" *)` (Verilog/SV) or VHDL `ATTRIBUTE ramstyle OF sig : SIGNAL IS "logic"`. The framework does exactly this in three ascal signals: `o_hfrac`, `o_hpixq`, `o_div`/`o_dir`.
- **Citation:** archive/github/MiSTer-devel/Template_MiSTer/sys/ascal.vhd:519 @ f35083f3b40d (with the comment `-- avoid blockram shift register`); archive/github/MiSTer-devel/Template_MiSTer/sys/ascal.vhd:544,552 @ f35083f3b40d.

### A.4 Tiny array left to default — wastes an M10K block

- **Symptom:** Total M10K count is higher than rough budgeting expected. The Resource Section breakdown shows several small-but-real BRAMs whose product (depth × width) is a tiny fraction of 10 Kibit each.
- **Cause:** A 2-entry × 40-bit accumulator or 4-entry × 16-bit ring buffer is large enough to trigger Quartus's automatic BRAM inference but small enough that the M10K block is > 99% empty. Each such block reduces the design's M10K budget by one.
- **Fix:** Annotate with `(* ramstyle = "logic" *)`. The framework does this in `iir_filter.v` (2 × 40 bits) and `hps_io.sv` (8 × `1<<PS2_FIFO_BITS`).
- **Citation:** archive/github/MiSTer-devel/Template_MiSTer/sys/iir_filter.v:178 @ f35083f3b40d; archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:731 @ f35083f3b40d.

### A.5 Small ROM left to default — gets M10K instead of MLAB

- **Symptom:** Same as A.4 but for read-only initialization data: a 64- or 256-entry lookup table costs a full M10K block when MLAB would suffice.
- **Cause:** Without an explicit attribute Quartus picks M10K for any read-only array with synchronous read; MLAB targeting is opt-in.
- **Fix:** Add `(* romstyle = "MLAB" *)` on the array declaration. The framework's HQ2x rule table (6 × 256 entries) uses exactly this pattern.
- **Citation:** archive/github/MiSTer-devel/Template_MiSTer/sys/hq2x.sv:35 @ f35083f3b40d.

### A.6 `$readmemh` with a relative path that Quartus cannot find

- **Symptom:** Synthesis warning "could not find file `<name>.hex` in any search path"; the ROM is silently inferred with X (or 0) contents; the core boots but behaves as if the table is empty.
- **Cause:** `$readmemh("data.hex", rom)` is resolved against Quartus's project search path (project directory + `SEARCH_PATH` entries in the `.qsf`). A nested subdirectory or a forgotten `SEARCH_PATH` assignment leaves the file invisible to elaboration. The framework's `confstr_rom` reads `"cfgstr.hex"` (bare filename) because the build emits `cfgstr.hex` into the project root.
- **Fix:** Either put the file at the project root or add `set_global_assignment -name SEARCH_PATH <dir>` to the `.qsf`. Always inspect the Quartus elaboration log for "Loaded file ..." messages corresponding to each `$readmemh`.
- **Citation:** archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:1031-1033 @ f35083f3b40d.

### A.7 Exceeding the device's 553 M10K blocks — silent fallback then logic

- **Symptom:** Fitter Report shows `M10K blocks: 553 / 553` (100%) and then a sudden swell in ALM utilization; or the fit fails with "Cannot place memory block" errors. Cores that worked in simulation refuse to bitstream.
- **Cause:** The DE10-Nano part has 553 M10K blocks. When the design's inferred BRAMs exceed that count, Quartus first tries to retarget large memories to MLAB (more LUTs per bit) and finally to pure logic; at some point placement runs out of room.
- **Fix:** Audit the Resource Summary's per-module BRAM count; convert large work RAMs to SDRAM/DDRAM (see `30-sdram.md`, `31-ddram.md`); move small ROMs to MLAB (`romstyle="MLAB"`); force tiny arrays to logic (`ramstyle="logic"`).
- **Citation:** archive/github/MiSTer-devel/Template_MiSTer/sys/sys.tcl:2 @ f35083f3b40d (DE10-Nano part identification); [I] M10K count per the Cyclone V Device Handbook for 5CSEBA6.

## 8. Verification

- **Quartus Fitter Resource Summary**: the canonical place to see BRAM utilization. After a successful Fitter run, open `output_files/<revision>.fit.summary` or the in-IDE "Compilation Report → Fitter → Resource Section → Resource Usage Summary". Quartus 17.0.x reports `M10K blocks` as an explicit row with a `used / 553` ratio for the 5CSEBA6U23I7 part. The "Total block memory bits" row gives the raw bit count. [I] (concept matches Quartus 17.0.x report layout; exact label string may vary)
- **Per-RAM detail**: "Compilation Report → Fitter → RAM Summary" (Quartus 17.0.x) lists every inferred and instantiated RAM with its width, depth, M10K count, and the source file/line. This is where to look for an array that didn't infer the way the engineer expected.
- **Synthesis log warnings**: Quartus Analysis & Synthesis emits one warning per inferred RAM, naming the source line and the chosen implementation (M10K / MLAB / logic). A missing M10K target shows up as either an absence (the RAM does not appear at all in the RAM Summary) or as a "Implemented as MLAB" / "as logic" note.
- **`$readmemh` confirmation**: search the elaboration log for "Loaded file <name>.hex"; if the message is absent the file was not found and the ROM is uninitialized.
- **Power-on contents**: an M10K block boots with whatever `initial` / `$readmemh` set (else zero); cores that depend on a specific power-on pattern should never rely on the bus default — set explicitly.
- **Simulation**: ModelSim/Questa simulate inferred RAMs as ordinary arrays; the actual M10K topology (output register, read-during-write semantics) is only realized post-synthesis. Use the `RTL Viewer` and `Technology Map Viewer` to confirm the inferred block primitive after synthesis.
- **SignalTap**: probe the registered `q` output to verify the one-cycle read latency in hardware; for TDP `altsyncram`, probe both `q_a` and `q_b` to catch cross-port hazards that simulation may miss.
- **MISTER.INI**: provides no BRAM-specific knobs; symptoms of BRAM mis-inference are debugged in the Fitter Report and on SignalTap, not from the OSD.

## 9. Provenance footer

- archive/github/MiSTer-devel/Template_MiSTer/sys/sys.tcl @ f35083f3b40d — used for §2 (DE10-Nano part identification)
- archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv @ f35083f3b40d — used for §2 (single-port ROM idiom, `ramstyle="logic"` opt-out), §3.2 (`confstr_rom`, PS/2 fifo), §5.1 (verbatim `confstr_rom`), §7 (A.1, A.4, A.6)
- archive/github/MiSTer-devel/Template_MiSTer/sys/gamma_corr.sv @ f35083f3b40d — used for §2 (SDP-with-CDC convention, `ramstyle="no_rw_check"`), §3.2 (gamma curves), §5.2 (verbatim SDP-with-CDC), §6 (`gamma_corr` vs. `gamma_fast`)
- archive/github/MiSTer-devel/Template_MiSTer/sys/hq2x.sv @ f35083f3b40d — used for §2 (`romstyle="MLAB"`, registered-read SDP), §3.2 (`hqTable`, `hq2x_buf`), §5.3 (verbatim `hq2x_buf` SDP same-clock), §6 (line-buffer width derivation; ROM init style), §7 (A.5)
- archive/github/MiSTer-devel/Template_MiSTer/sys/sd_card.sv @ f35083f3b40d — used for §2 (TDP `altsyncram`, `power_up_uninitialized`, read-during-write, `outdata_aclr`), §3.2 (`sdbuf`), §4.3 (TDP timing), §4.4 (no async clear), §5.4 (verbatim `altsyncram`), §6 (TDP vs. SDP), §7 (A.2)
- archive/github/MiSTer-devel/Template_MiSTer/sys/scandoubler.v @ f35083f3b40d — used for §3.2 (no direct BRAM; delegates to `Hq2x`)
- archive/github/MiSTer-devel/Template_MiSTer/sys/osd.v @ f35083f3b40d — used for §2 (`ramstyle="no_rw_check"`), §3.2 (`osd_buffer`)
- archive/github/MiSTer-devel/Template_MiSTer/sys/shadowmask.sv @ f35083f3b40d — used for §3.2 (`mask_lut`)
- archive/github/MiSTer-devel/Template_MiSTer/sys/audio_out.sv @ f35083f3b40d — used for §3.2 (no direct BRAM)
- archive/github/MiSTer-devel/Template_MiSTer/sys/spdif.v @ f35083f3b40d — used for §3.2 (no direct BRAM)
- archive/github/MiSTer-devel/Template_MiSTer/sys/iir_filter.v @ f35083f3b40d — used for §2 (`ramstyle="logic"` opt-out), §3.2 (`intreg`), §5.5 (opt-out pattern), §7 (A.4)
- archive/github/MiSTer-devel/Template_MiSTer/sys/ascal.vhd @ f35083f3b40d — used for §2 (`no_rw_check`, opt-out shift registers), §3.2 (ascal line buffers, palette, polyphase coefficients), §6 (line-buffer multiplicity), §7 (A.3)
- archive/github/MiSTer-devel/Template_MiSTer/sys/mt32pi.sv @ f35083f3b40d — used for §3.2 (`lcd_data`)
- archive/github/MiSTer-devel/Template_MiSTer/sys/pll_cfg/pll_cfg.v @ f35083f3b40d — used for §2 (`.mif` initialization reference)
- archive/github/MiSTer-devel/Template_MiSTer/Template.qsf @ f35083f3b40d — used for §2 (Quartus 17.0.x toolchain version)
- archive/github/MiSTer-devel/Template_MiSTer/Template.sdc @ f35083f3b40d — used for §1/§8 (no BRAM-specific SDC content; verified empty)
- archive/github/MiSTer-devel/MkDocs_MiSTer/docs/developer/hps_io.md @ 9033bd292fdc — used for §6 (`CONF_STR_BRAM` parameter)
- archive/github/MiSTer-devel/MkDocs_MiSTer/docs/developer/principles.md @ 9033bd292fdc — used for §2/§7 (general guidance on `multstyle`/`ramstyle` attributes)
- Intel/Altera Cyclone V Device Handbook (Embedded Memory Blocks chapter) — used for §2 (M10K block count = 553 for 5CSEBA6, per-port width set, async-reset rules), §3.1 (supported widths, mixed-width, read-during-write semantics), §7 (A.2, A.7)
