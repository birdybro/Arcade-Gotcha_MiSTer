# DDRAM (FPGA-to-HPS DDR3 bridge)

> Bundle version: 2026-05-18
> Pinned commits: `Template_MiSTer` @ `f35083f3b40d`
> Load with: [30-sdram.md](30-sdram.md), [32-rom-save-state-flows.md](32-rom-save-state-flows.md), [10-emu-top-level.md](10-emu-top-level.md)
> Status mix: [C] [V] [O] [I]

## 1. Purpose & one-line summary

DDRAM is the 1 GB DDR3 attached to the HPS, exposed to the FPGA fabric over the SoC's `f2sdram` Avalon-MM bridge. The `emu` module sees it as a single set of `DDRAM_*` ports — a 64-bit-wide, high-latency, burst-capable memory shared with Linux. Cores use it for large work areas that don't fit in SDRAM: HDMI framebuffers, CD/HDD images, save states, sample banks.

## 2. The contract (must-obey)

- The core drives `DDRAM_CLK`; the framework's `sysmem` block uses this clock for its `ram1_clk` input. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/emu_ports.vh:100 @ f35083f3b40d, archive/github/MiSTer-devel/Template_MiSTer/sys/sys_top.v:615-624 @ f35083f3b40d)
- Data width is 64 bits in both directions (`DDRAM_DIN`, `DDRAM_DOUT`). [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/emu_ports.vh:104,107 @ f35083f3b40d)
- `DDRAM_ADDR` is a 29-bit *word* address — it selects 64-bit words, so the byte address it represents is `{DDRAM_ADDR, 3'b000}`. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/emu_ports.vh:103 @ f35083f3b40d)
- `DDRAM_BE[7:0]` is an active-high byte enable, one bit per byte of the 64-bit word. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/emu_ports.vh:108 @ f35083f3b40d)
- `DDRAM_BURSTCNT[7:0]` is the number of 64-bit beats in the requested transaction; legal values are 1..255 (the underlying Avalon burst-count width). [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/emu_ports.vh:102 @ f35083f3b40d, archive/github/MiSTer-devel/Template_MiSTer/sys/sysmem.sv:14 @ f35083f3b40d)
- `DDRAM_BUSY` is the bridge's `waitrequest`: a cycle in which the master asserts `RD` or `WE` is accepted only when `BUSY` is low on that same cycle. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/sysmem.sv:13 @ f35083f3b40d, archive/github/MiSTer-devel/Template_MiSTer/sys/ddr_svc.sv:73-75 @ f35083f3b40d)
- `DDRAM_DOUT_READY` is the Avalon `readdatavalid` strobe — `DDRAM_DOUT` is valid only on cycles where `DOUT_READY=1`. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/sysmem.sv:16 @ f35083f3b40d)
- Read replies are not in-order with respect to `RD`: the bridge may return data many cycles after the request, and the only timing reference is `DOUT_READY`. [I] (archive/github/MiSTer-devel/Template_MiSTer/sys/ddr_svc.sv:96-103 @ f35083f3b40d)
- `DDRAM_RD` and `DDRAM_WE` are mutually exclusive; the framework conventionally pulses them for one cycle (when `BUSY=0`) per burst command. [V] (archive/github/MiSTer-devel/Template_MiSTer/sys/ddr_svc.sv:73-95 @ f35083f3b40d)
- A core that does not use DDRAM ties `DDRAM_CLK, DDRAM_BURSTCNT, DDRAM_ADDR, DDRAM_DIN, DDRAM_BE, DDRAM_RD, DDRAM_WE` to `'0` (template default). [V] (archive/github/MiSTer-devel/Template_MiSTer/Template.sv:31 @ f35083f3b40d)
- The framework inserts `f2sdram_safe_terminator` between the user logic and the actual `f2sdram` slave; mid-burst reset of an in-flight transaction without that wrapper can leave the bridge in an unrecoverable state. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/f2sdram_safe_terminator.sv:8-41 @ f35083f3b40d, archive/github/MiSTer-devel/Template_MiSTer/sys/sysmem.sv:67-91 @ f35083f3b40d)
- Address allocation between cores and HPS is by convention — the arcade framebuffer reserves the region starting at byte 0x24000000 (`MEM_BASE = 7'b0010010`). [V] (archive/github/MiSTer-devel/Template_MiSTer/sys/arcade_video.v:204,210 @ f35083f3b40d)
- The chip is 1 GB DDR3; `DDRAM_ADDR[28:0]` × 8 bytes covers 4 GB of word address space, so only the lower portion of that space maps to real memory. [I]

## 3. Ports / signals reference

The `emu` module receives the DDRAM port group through `emu_ports.vh`:

```verilog
// archive/github/MiSTer-devel/Template_MiSTer/sys/emu_ports.vh:98-109 @ f35083f3b40d
//High latency DDR3 RAM interface
//Use for non-critical time purposes
output        DDRAM_CLK,
input         DDRAM_BUSY,
output  [7:0] DDRAM_BURSTCNT,
output [28:0] DDRAM_ADDR,
input  [63:0] DDRAM_DOUT,
input         DDRAM_DOUT_READY,
output        DDRAM_RD,
output [63:0] DDRAM_DIN,
output  [7:0] DDRAM_BE,
output        DDRAM_WE,
```

`sys_top.v` wires those `emu` ports to `sysmem`'s `ram1_*` Avalon-MM port group:

```verilog
// archive/github/MiSTer-devel/Template_MiSTer/sys/sys_top.v:1823-1832 @ f35083f3b40d
.DDRAM_CLK(ram_clk),
.DDRAM_ADDR(ram_address),
.DDRAM_BURSTCNT(ram_burstcount),
.DDRAM_BUSY(ram_waitrequest),
.DDRAM_DOUT(ram_readdata),
.DDRAM_DOUT_READY(ram_readdatavalid),
.DDRAM_RD(ram_read),
.DDRAM_DIN(ram_writedata),
.DDRAM_BE(ram_byteenable),
.DDRAM_WE(ram_write),
```

### Ports visible to the core

| Signal | Dir | Width | Clock | Active | Meaning | Driven by | Drives |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `DDRAM_CLK` | out | 1 | — | rising edge | Clock that paces the bridge for this core | `emu` (core) | `sysmem.ram1_clk` |
| `DDRAM_BUSY` | in | 1 | `DDRAM_CLK` | high = stall | Avalon `waitrequest`; transactions are accepted only when low | `sysmem` (terminator output) | core arbiter |
| `DDRAM_BURSTCNT` | out | 8 | `DDRAM_CLK` | unsigned | Number of 64-bit beats in this burst (1..255) | core | `sysmem.ram1_burstcount` |
| `DDRAM_ADDR` | out | 29 | `DDRAM_CLK` | unsigned | 64-bit word address (byte addr = `{ADDR,3'b0}`) | core | `sysmem.ram1_address` |
| `DDRAM_DOUT` | in | 64 | `DDRAM_CLK` | data | Read data; valid only when `DOUT_READY` high | `sysmem` | core read FIFO |
| `DDRAM_DOUT_READY` | in | 1 | `DDRAM_CLK` | high = valid | Avalon `readdatavalid` strobe for `DDRAM_DOUT` | `sysmem` | core |
| `DDRAM_RD` | out | 1 | `DDRAM_CLK` | high = request | Read command; assert with address+burst when `BUSY=0` | core | `sysmem.ram1_read` |
| `DDRAM_DIN` | out | 64 | `DDRAM_CLK` | data | Write data; one beat per write cycle in a burst | core | `sysmem.ram1_writedata` |
| `DDRAM_BE` | out | 8 | `DDRAM_CLK` | high per byte | Byte-enable mask for the current `DDRAM_DIN` beat | core | `sysmem.ram1_byteenable` |
| `DDRAM_WE` | out | 1 | `DDRAM_CLK` | high = request | Write command; hold `WE+DIN+BE` per beat until accepted | core | `sysmem.ram1_write` |

Note: every `DDRAM_*` signal above is a contract port — the framework requires those exact widths and polarities. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/emu_ports.vh:98-109 @ f35083f3b40d)

### `ddr_svc.sv` — a shared-bus read arbiter (framework helper)

`ddr_svc` is the framework's two-channel read arbiter that the HPS-side `sys_top` instantiates on `ram2_*`. It is read-only: `ram_writedata` is tied to 0 and `ram_byteenable` to `8'hFF`. [O] (archive/github/MiSTer-devel/Template_MiSTer/sys/ddr_svc.sv:53,55 @ f35083f3b40d)

```verilog
// archive/github/MiSTer-devel/Template_MiSTer/sys/ddr_svc.sv:23-50 @ f35083f3b40d
module ddr_svc
(
    input         clk,

    input         ram_waitrequest,
    output  [7:0] ram_burstcnt,
    output [28:0] ram_addr,
    input  [63:0] ram_readdata,
    input         ram_read_ready,
    output reg    ram_read,
    output [63:0] ram_writedata,
    output  [7:0] ram_byteenable,
    output reg    ram_write,

    output  [7:0] ram_bcnt,

    input  [31:3] ch0_addr,
    input   [7:0] ch0_burst,
    output [63:0] ch0_data,
    input         ch0_req,
    output        ch0_ready,
    
    input  [31:3] ch1_addr,
    input   [7:0] ch1_burst,
    output [63:0] ch1_data,
    input         ch1_req,
    output        ch1_ready
);
```

| Signal | Dir | Width | Meaning |
| --- | --- | --- | --- |
| `clk` | in | 1 | Shared clock; `sys_top` uses `clk_audio` | [O] |
| `ram_*` | bidir | — | The Avalon-MM master side; wired to a second DDRAM port (`ram2_*` in sysmem) | [O] |
| `ram_bcnt` | out | 8 | Beat counter exposed for debug/clients (sysmem terminator side) | [O] |
| `ch0_addr` / `ch1_addr` | in | 29 ([31:3]) | Byte-address-aligned word address per channel | [C] |
| `ch0_burst` / `ch1_burst` | in | 8 | Per-channel burst length | [C] |
| `ch0_data` / `ch1_data` | out | 64 | Per-channel beat data (one beat held until next `ready`) | [C] |
| `ch0_req` / `ch1_req` | in | 1 | Toggle-edge request — flips when the channel wants a new burst | [C] |
| `ch0_ready` / `ch1_ready` | out | 1 | Single-cycle data-valid strobe per beat returned to that channel | [C] |

`ddr_svc` is *not* a generic core helper; it is the framework's wiring for the HPS audio (ALSA) sniffer + palette read paths on the second `f2sdram` port. The "`// 16-bit version`" comment in its source is stale — the data path is 64-bit. [O] (archive/github/MiSTer-devel/Template_MiSTer/sys/sys_top.v:663-691 @ f35083f3b40d, archive/github/MiSTer-devel/Template_MiSTer/sys/ddr_svc.sv:21,30,33 @ f35083f3b40d)

### `f2sdram_safe_terminator.sv` — bridge-safe reset wrapper

The terminator is parameterized (`DATA_WIDTH`, `BURSTCOUNT_WIDTH`) so the same module serves both the 64-bit `ram1`/`ram2` ports and the 128-bit `vbuf` (framebuffer) port. It exposes a pair of Avalon-MM port groups, master to the actual `f2sdram` slave and slave to the user logic, and finishes any in-flight burst on reset rather than tearing it down. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/f2sdram_safe_terminator.sv:55-87 @ f35083f3b40d, archive/github/MiSTer-devel/Template_MiSTer/sys/sysmem.sv:67-183 @ f35083f3b40d)

## 4. Sequencing & timing

All waveforms are on `DDRAM_CLK` rising edges. `B` = `DDRAM_BUSY`, `R` = `DDRAM_RD`, `W` = `DDRAM_WE`, `V` = `DDRAM_DOUT_READY`.

### Single-beat read

```
clk      |‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_
B        ___________________________________
R        ___/‾‾‾‾‾\__________________________
ADDR     XXX< A >XXXXXXXXXXXXXXXXXXXXXXXXXXX
BURSTCNT XXX< 1 >XXXXXXXXXXXXXXXXXXXXXXXXXXX
V        ________________/‾‾‾‾‾\___________
DOUT     XXXXXXXXXXXXXXXX< D >XXXXXXXXXXXXX
            ^ cycle 1: BUSY low, master asserts RD with ADDR/BURSTCNT=1
                       transaction is accepted this cycle
                                ^ cycles 2..N: variable latency through f2sdram
                                              ^ DOUT_READY pulses with the word
```

Cycle 1 the master asserts `RD=1` while `BUSY=0`; the bridge latches `ADDR` and `BURSTCNT`. The master deasserts `RD` on the next cycle (Avalon convention) and waits. `DOUT_READY` strobes once when the word returns. Latency is not fixed — HPS traffic contends for the DDR3 controller. [I] (archive/github/MiSTer-devel/Template_MiSTer/sys/ddr_svc.sv:73-103 @ f35083f3b40d)

### Burst read (length 2)

```
clk      |‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_
B        _____________________________________
R        ___/‾‾‾‾‾\___________________________
ADDR     XXX< A >XXXXXXXXXXXXXXXXXXXXXXXXXXXXX
BURSTCNT XXX< 2 >XXXXXXXXXXXXXXXXXXXXXXXXXXXXX
V        ________________/‾‾‾‾‾‾‾‾‾‾‾\_______
DOUT     XXXXXXXXXXXXXXXX< D0 >< D1 >XXXXXXX
            ^ single RD command, BURSTCNT=2
                                ^ two consecutive DOUT_READY pulses
```

For bursts >1 only the first beat carries the command; subsequent `DOUT_READY` pulses deliver the remaining beats. `ddr_svc` counts beats via `ram_bcnt` and only returns to `state=0` when `(ram_bcnt + 2) == ram_burst`. [O] (archive/github/MiSTer-devel/Template_MiSTer/sys/ddr_svc.sv:96-103 @ f35083f3b40d)

### Single-beat write

```
clk      |‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_
B        _________________________
W        ___/‾‾‾‾‾\_________________
ADDR     XXX< A >XXXXXXXXXXXXXXXXXX
BURSTCNT XXX< 1 >XXXXXXXXXXXXXXXXXX
DIN      XXX< D >XXXXXXXXXXXXXXXXXX
BE       XXX< E >XXXXXXXXXXXXXXXXXX
            ^ all five (W,ADDR,BURSTCNT,DIN,BE) valid this cycle with BUSY=0
                       write is accepted; bridge swallows the data
```

Single-beat writes — what `arcade_video.v` issues for the framebuffer — drive all of `W/ADDR/BURSTCNT/DIN/BE` valid in one cycle while `BUSY=0`, then deassert `W` next cycle. There is no write-data-ready strobe; the byte enables select which lanes of `DIN` actually mutate memory. [O] (archive/github/MiSTer-devel/Template_MiSTer/sys/arcade_video.v:208-214 @ f35083f3b40d)

### Behavior when `DDRAM_BUSY` is high

```
clk      |‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_
B        _______/‾‾‾‾‾\_____________
W        ___/‾‾‾‾‾‾‾‾‾\_____________
ADDR     XXX< A: held while BUSY >XX
DIN      XXX< D: held while BUSY >XX
BE       XXX< E: held while BUSY >XX
                          ^ accepted only on the cycle BUSY goes low again
```

When `BUSY` is asserted, the master must hold the command, address, and data stable until the cycle on which `BUSY` falls. `ddr_svc` follows this pattern by only clearing `ram_read`/`ram_write` inside an `if(!ram_waitrequest)` block. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/ddr_svc.sv:73-95 @ f35083f3b40d)

### Reset / mid-burst behavior

The safe terminator latches the in-flight burst's `address` and `burstcount` when reset is asserted, then keeps writing dummy beats (with `byteenable = 0`) until the burst counter reaches `burstcount_latch - 1`, after which `terminating` clears. Reads in flight are allowed to drain on their own. Without this wrapper, a reset during a write burst leaves `f2sdram` mis-counted and the next core inherits a stuck bridge. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/f2sdram_safe_terminator.sv:177-242 @ f35083f3b40d)

## 5. Minimal working pattern

A core that does not use DDRAM ties off the port group:

```verilog
// archive/github/MiSTer-devel/Template_MiSTer/Template.sv:31 @ f35083f3b40d
assign {DDRAM_CLK, DDRAM_BURSTCNT, DDRAM_ADDR, DDRAM_DIN, DDRAM_BE, DDRAM_RD, DDRAM_WE} = '0;
```

A core that actively writes DDRAM (here, `arcade_video.v` packing a 32-bit framebuffer pixel into either the high or low half of a 64-bit word):

```verilog
// archive/github/MiSTer-devel/Template_MiSTer/sys/arcade_video.v:208-214 @ f35083f3b40d
assign DDRAM_CLK      = CLK_VIDEO;
assign DDRAM_BURSTCNT = 1;
assign DDRAM_ADDR     = {MEM_BASE, i_fb, ram_addr[22:3]};
assign DDRAM_BE       = ram_addr[2] ? 8'hF0 : 8'h0F;
assign DDRAM_DIN      = {ram_data,ram_data};
assign DDRAM_WE       = ram_wr;
assign DDRAM_RD       = 0;
```

Notes on the write pattern:

- `MEM_BASE = 7'b0010010` places this region at byte address `0x24000000`. [O] (archive/github/MiSTer-devel/Template_MiSTer/sys/arcade_video.v:204 @ f35083f3b40d)
- The byte address is `{MEM_BASE, i_fb, ram_addr[22:3], 3'b0}`; `ram_addr[2]` selects which half of the 64-bit word the 32-bit pixel goes into, and `DDRAM_BE` enables only that half.
- `DDRAM_DIN` duplicates the pixel into both halves so the byte-enable choice is sufficient — the unselected half is masked out.
- `ram_wr` is the user-side `write` strobe that should already be qualified against `DDRAM_BUSY` upstream of this fence.

A correct read consumer (one beat) reads `DDRAM_DOUT` only on the cycle when `DDRAM_DOUT_READY=1`; see the `state=1` branch of `ddr_svc.sv` for the canonical version:

```verilog
// archive/github/MiSTer-devel/Template_MiSTer/sys/ddr_svc.sv:96-103 @ f35083f3b40d
1: begin
        if(ram_read_ready) begin
            ram_bcnt  <= ram_bcnt + 1'd1;
            ram_q[ch] <= ram_readdata;
            ready[ch] <= 1;
            if ((ram_bcnt+2'd2) == ram_burst) state <= 0;
        end
    end
```

## 6. Common variations across cores

- `ddr_svc.sv` is the framework's read-only two-channel arbiter, instantiated by `sys_top` on the second `f2sdram` port and clocked by `clk_audio`. Its `ch0` is wired to ALSA (when `MISTER_DISABLE_ALSA` is not set) and `ch1` to the palette logic; both channels are pure read clients. [O] (archive/github/MiSTer-devel/Template_MiSTer/sys/sys_top.v:663-691 @ f35083f3b40d)
- `arcade_video.v` issues *single-beat writes* with `BURSTCNT=1` and uses byte enables to select 32-bit halves of the 64-bit word; it never reads (`DDRAM_RD = 0`). [O] (archive/github/MiSTer-devel/Template_MiSTer/sys/arcade_video.v:209-214 @ f35083f3b40d)
- The framebuffer "vbuf" port uses a 128-bit data width and 16-bit byte enables instead of 64/8, sharing the same Avalon protocol via a separately-parameterized `f2sdram_safe_terminator`. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/sysmem.sv:33-42,159-183 @ f35083f3b40d)
- `f2sdram_safe_terminator` is inserted on every `f2sdram` port, not optional — `sysmem.sv` instantiates one each for `ram1`, `ram2`, and `vbuf`. Its purpose is to safely drain or stub-complete an in-flight burst on reset rather than tearing it down mid-transaction (also referred to as "terminating" unused or stalled f2sdram traffic in MiSTer commentary). [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/f2sdram_safe_terminator.sv:43-50 @ f35083f3b40d, archive/github/MiSTer-devel/Template_MiSTer/sys/sysmem.sv:67-183 @ f35083f3b40d)
- Cross-core comparison of how NES / SNES / PSX / ao486 actually carve the DDRAM address space (ROM-vs-save-state, CD images, page-tables) — [deferred — reference cores not fetched].

## 7. Anti-patterns

### A.1 Asserting `DDRAM_RD` / `DDRAM_WE` without sampling `DDRAM_BUSY`

- **Symptom:** intermittent dropped or duplicated transactions; the core appears to "skip" some reads/writes and other reads return data for the wrong address.
- **Cause:** Avalon-MM `waitrequest` (mapped to `DDRAM_BUSY`) means "this cycle is not accepted." If the master deasserts `RD`/`WE` while `BUSY` was high, the request never got latched; if it changes `ADDR`/`DIN` mid-stall, a later acceptance commits the wrong values.
- **Fix:** only clear `RD`/`WE` inside an `if(!DDRAM_BUSY)` block, and hold all command/data signals stable until that cycle. The framework's own `ddr_svc.sv` is the reference.
- **Citation:** archive/github/MiSTer-devel/Template_MiSTer/sys/ddr_svc.sv:73-95 @ f35083f3b40d

### A.2 Sampling `DDRAM_DOUT` on `DDRAM_RD` instead of `DDRAM_DOUT_READY`

- **Symptom:** garbage read data, or what looks like a single-cycle read latency in simulation that doesn't hold up on hardware.
- **Cause:** `DDRAM_DOUT_READY` is the only valid-data marker. Read latency through `f2sdram` is variable and depends on HPS contention; assuming a fixed delay from `RD` ignores the bridge's actual behavior.
- **Fix:** treat `DDRAM_DOUT_READY` as a per-beat strobe and consume `DDRAM_DOUT` only on the cycles it is high. For bursts of length N, expect N strobes.
- **Citation:** archive/github/MiSTer-devel/Template_MiSTer/sys/ddr_svc.sv:96-103 @ f35083f3b40d

### A.3 Mis-aligning `DDRAM_BE` against sub-64-bit data

- **Symptom:** writes corrupt neighboring data in the same 64-bit word; reads return data from the wrong byte lane.
- **Cause:** `DDRAM_ADDR` is a 64-bit *word* address. Writing a 32-bit value to byte address `A` requires (a) computing the word address `A>>3`, (b) duplicating or shifting the data into the correct half of `DDRAM_DIN`, and (c) setting `DDRAM_BE` to enable only that half (`8'h0F` for the low 32 bits, `8'hF0` for the high 32 bits). Forgetting any of those three steps writes the wrong lanes.
- **Fix:** use the `arcade_video.v` pattern (duplicate data into both halves, select with `DDRAM_BE` based on the sub-word index).
- **Citation:** archive/github/MiSTer-devel/Template_MiSTer/sys/arcade_video.v:210-212 @ f35083f3b40d

### A.4 Allowing reset to fire mid-burst with the safe terminator removed

- **Symptom:** after switching cores (or after a soft reset), the next core's DDRAM transactions return wrong data, time out, or hang the bridge until full HPS reboot.
- **Cause:** the SoC's `f2sdram` slave does not have a usable per-port reset path; tearing down a write burst mid-stream leaves the controller's internal counter out of sync. Per the wrapper's own header comment, this is exactly what `f2sdram_safe_terminator` exists to prevent.
- **Fix:** never bypass `f2sdram_safe_terminator` when wiring custom logic to the f2sdram port. Feed it a synchronous reset on the same clock as the port.
- **Citation:** archive/github/MiSTer-devel/Template_MiSTer/sys/f2sdram_safe_terminator.sv:8-54 @ f35083f3b40d

### A.5 Bursts longer than the bridge's burst-count width

- **Symptom:** the bridge accepts the first 256 beats and silently drops the rest, or wraps the counter, or hangs.
- **Cause:** `DDRAM_BURSTCNT` is 8 bits wide; the maximum single-transaction burst is 255 beats (counter cannot represent 256+).
- **Fix:** chunk longer transfers into multiple bursts ≤ 255 beats, with separate address/command per chunk.
- **Citation:** archive/github/MiSTer-devel/Template_MiSTer/sys/emu_ports.vh:102 @ f35083f3b40d, archive/github/MiSTer-devel/Template_MiSTer/sys/sysmem.sv:14 @ f35083f3b40d

### A.6 Treating DDRAM as low-latency RAM

- **Symptom:** CPU emulators stall waiting on DDRAM; audio underruns; framebuffer tearing.
- **Cause:** the header comment on the DDRAM port group itself says "*High latency DDR3 RAM interface — use for non-critical time purposes*." The bridge shares the DDR3 controller with Linux; HPS traffic interleaves with FPGA traffic.
- **Fix:** keep latency-critical state in BRAM or SDRAM; use DDRAM only for bulk, prefetchable, or batched work (framebuffers, CD images, save-state blobs).
- **Citation:** archive/github/MiSTer-devel/Template_MiSTer/sys/emu_ports.vh:98-99 @ f35083f3b40d

## 8. Verification

- Wire `DDRAM_RD`, `DDRAM_WE`, `DDRAM_BUSY`, `DDRAM_DOUT_READY`, and `DDRAM_BURSTCNT` to SignalTap (or a simulated bridge model) and confirm every assertion of `RD`/`WE` coincides with `BUSY=0`. Mismatches indicate handshake bugs.
- Count `DDRAM_DOUT_READY` strobes per read command and confirm it equals `DDRAM_BURSTCNT`; a shortfall means the master gave up early.
- For reset-handling, force a `reset_core_req` during a long write burst in simulation and confirm `f2sdram_safe_terminator` continues issuing dummy beats (with `byteenable=0`) until the burst completes.
- On hardware, switching cores while a DDRAM transaction is in flight is the canonical stress test: a missing or misused safe terminator manifests as a wedged DDRAM in the *next* core, not the one being torn down.
- The DDRAM port comment in `emu_ports.vh` ("*Use for non-critical time purposes*") is the in-source guidance for what kind of traffic belongs here.

## 9. Provenance footer

- archive/github/MiSTer-devel/Template_MiSTer/sys/ddr_svc.sv @ f35083f3b40d — used for §2, §3, §4, §5, §6, §7
- archive/github/MiSTer-devel/Template_MiSTer/sys/f2sdram_safe_terminator.sv @ f35083f3b40d — used for §2, §3, §4, §6, §7
- archive/github/MiSTer-devel/Template_MiSTer/sys/sysmem.sv @ f35083f3b40d — used for §2, §3, §6
- archive/github/MiSTer-devel/Template_MiSTer/sys/sys_top.v @ f35083f3b40d — used for §2, §3, §6
- archive/github/MiSTer-devel/Template_MiSTer/sys/emu_ports.vh @ f35083f3b40d — used for §2, §3, §7, §8
- archive/github/MiSTer-devel/Template_MiSTer/sys/arcade_video.v @ f35083f3b40d — used for §2, §5, §6, §7
- archive/github/MiSTer-devel/Template_MiSTer/Template.sv @ f35083f3b40d — used for §2, §5
