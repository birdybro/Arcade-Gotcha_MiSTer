# SDRAM (Core-Private SDR)

> Bundle version: 2026-05-18
> Pinned commits: `Template_MiSTer` `f35083f3b40d`, `Hardware_MiSTer` `bbd361962005`, `MkDocs_MiSTer` `9033bd292fdc`
> Load with: [31-ddram.md](31-ddram.md), [32-rom-save-state-flows.md](32-rom-save-state-flows.md), [12-clocks-resets-plls.md](12-clocks-resets-plls.md)
> Status mix: [C] [V] [I]

## 1. Purpose & one-line summary

SDRAM is the core-private SDR DRAM module attached to the FPGA via the SDRAM daughter board; the framework wires pin-level signals only and does NOT supply a controller, so each core instantiates its own controller against the pad-registered ports exposed through `emu_ports.vh`. The HPS has no path to this memory — its only client is the FPGA core. SDRAM is required for cores that need low-latency, deterministic timing typical of retro EDO/SRAM-class buses.

## 2. The contract (must-obey)

- Primary-SDRAM port set is 11 signals: `SDRAM_A[12:0]`, `SDRAM_BA[1:0]`, `SDRAM_DQ[15:0]`, `SDRAM_DQML`, `SDRAM_DQMH`, `SDRAM_nCS`, `SDRAM_nRAS`, `SDRAM_nCAS`, `SDRAM_nWE`, `SDRAM_CLK`, `SDRAM_CKE`. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/emu_ports.vh:112-122 @ f35083f3b40d)
- `SDRAM_DQ` is bidirectional `inout`; all other primary-SDRAM signals are unidirectional `output` driven by the core. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/emu_ports.vh:112-122 @ f35083f3b40d)
- Control signals `SDRAM_nCS`, `SDRAM_nRAS`, `SDRAM_nCAS`, `SDRAM_nWE` are active-low (leading `n` prefix is the framework's polarity tag). [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/emu_ports.vh:119-122 @ f35083f3b40d)
- `SDRAM_A` is 13 bits wide and `SDRAM_BA` is 2 bits wide, sized for a 16-bit-wide x4-bank x 8192-row x 1024-column SDR device. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/emu_ports.vh:114-115 @ f35083f3b40d)
- `SDRAM_DQML`/`SDRAM_DQMH` are byte-mask outputs gating the low and high bytes of `SDRAM_DQ` respectively. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/emu_ports.vh:117-118 @ f35083f3b40d)
- The core drives `SDRAM_CLK` itself; the framework does NOT supply or constrain a phase-shifted clock — `clk_ram`/4× shift is a per-core PLL convention, not a framework contract. [V] (archive/github/MiSTer-devel/Template_MiSTer/sys/emu_ports.vh:112 @ f35083f3b40d)
- All `SDRAM_*` pads are placed at fixed Cyclone V locations with IO_STANDARD `3.3-V LVTTL` and `MAXIMUM CURRENT` drive strength. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/sys.tcl:53-94 @ f35083f3b40d)
- All `SDRAM_*` outputs are pad-registered: `FAST_OUTPUT_REGISTER ON`, `FAST_INPUT_REGISTER ON` on `SDRAM_DQ[*]`, and `FAST_OUTPUT_ENABLE_REGISTER ON` on `SDRAM_DQ[*]` — the controller's last DQ stage is the IOE flip-flop and any combinatorial logic on the pad path will be retimed into the IOE. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/sys.tcl:95-97 @ f35083f3b40d)
- `ALLOW_SYNCH_CTRL_USAGE OFF` is set on `*|SDRAM_*` to forbid synchronous-control implementation of these IOs, locking output enable to a dedicated OE register. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/sys.tcl:98 @ f35083f3b40d)
- A core that does not use SDRAM MUST drive every `SDRAM_*` output and the `SDRAM_DQ` inout to high-Z to avoid contention with the physical bus. [C] (archive/github/MiSTer-devel/Template_MiSTer/Template.sv:30 @ f35083f3b40d)
- When `MISTER_DUAL_SDRAM` is defined the secondary-SDRAM port set is REDUCED — 8 signals only: `SDRAM2_A[12:0]`, `SDRAM2_BA[1:0]`, `SDRAM2_DQ[15:0]`, `SDRAM2_nCS`, `SDRAM2_nRAS`, `SDRAM2_nCAS`, `SDRAM2_nWE`, `SDRAM2_CLK`. There is NO `SDRAM2_DQML`, `SDRAM2_DQMH`, or `SDRAM2_CKE`. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/emu_ports.vh:128-135 @ f35083f3b40d)
- `SDRAM2_EN` is an INPUT to the core driven by `io_dig` from `sys_top.v`; the core MUST tri-state every `SDRAM2_*` output as soon as `SDRAM2_EN == 0` because the secondary daughter board may be physically absent. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/emu_ports.vh:126-127 @ f35083f3b40d, archive/github/MiSTer-devel/Template_MiSTer/sys/sys_top.v:1855 @ f35083f3b40d)
- Enabling the secondary SDRAM requires sourcing `sys/sys_dual_sdram.tcl` from the project `.qsf`; that script sets `VERILOG_MACRO "MISTER_DUAL_SDRAM=1"` and assigns the SDRAM2 pin locations. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/sys_dual_sdram.tcl:51 @ f35083f3b40d)
- `MISTER_DUAL_SDRAM` is mutually exclusive with the analog VGA/Audio/SDIO/board-IO port group: `sys_top.v` gates the analog ports under `\`ifndef MISTER_DUAL_SDRAM`. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/sys_top.v:70-96 @ f35083f3b40d)
- The SDRAM daughter board populates 16 of the secondary `SDRAM2_DQ` pins; the `.tcl` enumerates `SDRAM2_DQ[0..7]` and `SDRAM2_DQ[8..15]` explicitly, so the secondary path is also 16-bit wide. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/sys_dual_sdram.tcl:4-20 @ f35083f3b40d)
- The reference SDR chip family is `AS4C32M16SB-7TCN`: 32M × 16 bits = 64 MB per device, 7 ns CL3 timing class. [C] (archive/github/MiSTer-devel/Hardware_MiSTer/README.md:33 @ bbd361962005)
- The SDR SDRAM daughter board ("SDRAM_xsds") provides 128 MB of SDR SDRAM total — two 64 MB chips, one on each bus when `MISTER_DUAL_SDRAM` is enabled. [C] (archive/github/MiSTer-devel/Hardware_MiSTer/README.md:10-14 @ bbd361962005)
- The SDRAM daughter board is mandatory for the MiSTer platform: many cores require it for memory regions that exceed ≈512 KB or that need timing tighter than DDR3 can satisfy. [C] (archive/github/MiSTer-devel/Hardware_MiSTer/README.md:13-14 @ bbd361962005)

## 3. Ports / signals reference

### 3.1 Primary SDRAM — `sys_top.v` top-level

```verilog
// archive/github/MiSTer-devel/Template_MiSTer/sys/sys_top.v:46-57 @ f35083f3b40d
	//////////// SDR ///////////
	output [12:0] SDRAM_A,
	inout  [15:0] SDRAM_DQ,
	output        SDRAM_DQML,
	output        SDRAM_DQMH,
	output        SDRAM_nWE,
	output        SDRAM_nCAS,
	output        SDRAM_nRAS,
	output        SDRAM_nCS,
	output  [1:0] SDRAM_BA,
	output        SDRAM_CLK,
	output        SDRAM_CKE,
```

### 3.2 Secondary SDRAM — `sys_top.v` top-level (conditional)

```verilog
// archive/github/MiSTer-devel/Template_MiSTer/sys/sys_top.v:59-69 @ f35083f3b40d
`ifdef MISTER_DUAL_SDRAM
	////////// SDR #2 //////////
	output [12:0] SDRAM2_A,
	inout  [15:0] SDRAM2_DQ,
	output        SDRAM2_nWE,
	output        SDRAM2_nCAS,
	output        SDRAM2_nRAS,
	output        SDRAM2_nCS,
	output  [1:0] SDRAM2_BA,
	output        SDRAM2_CLK,
```

### 3.3 Core-side ports (from `emu_ports.vh`)

```verilog
// archive/github/MiSTer-devel/Template_MiSTer/sys/emu_ports.vh:111-136 @ f35083f3b40d
//SDRAM interface with lower latency
output        SDRAM_CLK,
output        SDRAM_CKE,
output [12:0] SDRAM_A,
output  [1:0] SDRAM_BA,
inout  [15:0] SDRAM_DQ,
output        SDRAM_DQML,
output        SDRAM_DQMH,
output        SDRAM_nCS,
output        SDRAM_nCAS,
output        SDRAM_nRAS,
output        SDRAM_nWE,

`ifdef MISTER_DUAL_SDRAM
//Secondary SDRAM
//Set all output SDRAM_* signals to Z ASAP if SDRAM2_EN is 0
input         SDRAM2_EN,
output        SDRAM2_CLK,
output [12:0] SDRAM2_A,
output  [1:0] SDRAM2_BA,
inout  [15:0] SDRAM2_DQ,
output        SDRAM2_nCS,
output        SDRAM2_nCAS,
output        SDRAM2_nRAS,
output        SDRAM2_nWE,
`endif
```

### 3.4 Signal table

Primary SDRAM (always present). Direction is relative to the `emu` core.

| Signal | Dir | Width | Clock | Active | Meaning | Driven by | Drives |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `SDRAM_CLK` | out | 1 | self | rising | DRAM clock; core-generated. [C] | core PLL (via `emu`) | pad → daughter-board SDRAM `CLK` |
| `SDRAM_CKE` | out | 1 | `SDRAM_CLK` | high | Clock-enable; tied high in normal operation. [C] | core controller | SDRAM `CKE` |
| `SDRAM_A` | out | 13 | `SDRAM_CLK` | n/a | Multiplexed row/column address (13 row bits, 10 column bits). [C] | core controller | SDRAM `A[12:0]` |
| `SDRAM_BA` | out | 2 | `SDRAM_CLK` | n/a | Bank select (4 banks). [C] | core controller | SDRAM `BA[1:0]` |
| `SDRAM_DQ` | inout | 16 | `SDRAM_CLK` | n/a | Bidirectional 16-bit data bus. IOE pad-registered (`FAST_INPUT_REGISTER` ON). [C] | core during write / SDRAM during read | SDRAM `DQ[15:0]` |
| `SDRAM_DQML` | out | 1 | `SDRAM_CLK` | low | Low-byte mask: 0 = byte enabled. [C] | core controller | SDRAM `LDQM` |
| `SDRAM_DQMH` | out | 1 | `SDRAM_CLK` | low | High-byte mask: 0 = byte enabled. [C] | core controller | SDRAM `UDQM` |
| `SDRAM_nCS` | out | 1 | `SDRAM_CLK` | low | Chip-select. [C] | core controller | SDRAM `CS#` |
| `SDRAM_nRAS` | out | 1 | `SDRAM_CLK` | low | Row-address strobe. [C] | core controller | SDRAM `RAS#` |
| `SDRAM_nCAS` | out | 1 | `SDRAM_CLK` | low | Column-address strobe. [C] | core controller | SDRAM `CAS#` |
| `SDRAM_nWE` | out | 1 | `SDRAM_CLK` | low | Write-enable. [C] | core controller | SDRAM `WE#` |

Secondary SDRAM (only when `MISTER_DUAL_SDRAM` is defined). NOTE the reduced port set: no `DQML`, no `DQMH`, no `CKE`.

| Signal | Dir | Width | Clock | Active | Meaning | Driven by | Drives |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `SDRAM2_EN` | in | 1 | async | high | Daughter-board presence detect. Core MUST tri-state all `SDRAM2_*` outputs when low. [C] | `sys_top.v` (`io_dig`) | core controller (gate enable) |
| `SDRAM2_CLK` | out | 1 | self | rising | Secondary-DRAM clock; core-generated. [C] | core PLL (via `emu`) | secondary SDRAM `CLK` |
| `SDRAM2_A` | out | 13 | `SDRAM2_CLK` | n/a | Multiplexed row/column address. [C] | core controller | secondary SDRAM `A[12:0]` |
| `SDRAM2_BA` | out | 2 | `SDRAM2_CLK` | n/a | Bank select. [C] | core controller | secondary SDRAM `BA[1:0]` |
| `SDRAM2_DQ` | inout | 16 | `SDRAM2_CLK` | n/a | Bidirectional 16-bit data bus. [C] | core during write / SDRAM during read | secondary SDRAM `DQ[15:0]` |
| `SDRAM2_nCS` | out | 1 | `SDRAM2_CLK` | low | Chip-select. [C] | core controller | secondary SDRAM `CS#` |
| `SDRAM2_nRAS` | out | 1 | `SDRAM2_CLK` | low | Row-address strobe. [C] | core controller | secondary SDRAM `RAS#` |
| `SDRAM2_nCAS` | out | 1 | `SDRAM2_CLK` | low | Column-address strobe. [C] | core controller | secondary SDRAM `CAS#` |
| `SDRAM2_nWE` | out | 1 | `SDRAM2_CLK` | low | Write-enable. [C] | core controller | secondary SDRAM `WE#` |

Reduced-port consequence: a controller targeting the secondary bus cannot drive byte-masked writes via a DQM pin (the byte mask must be emulated via word-aligned read-modify-write or skipped) and cannot exit/enter clock-suspend via `CKE`. [I] (archive/github/MiSTer-devel/Template_MiSTer/sys/emu_ports.vh:128-135 @ f35083f3b40d)

## 4. Sequencing & timing

The framework does not specify SDRAM command timing — every controller is per-core. The DRAM chip family does. The following values are inferred from the referenced part `AS4C32M16SB-7TCN` ([I]: not in any cited framework file).

```
SDR-SDRAM AS4C32M16SB-7TCN (32M × 16 bits = 64 MB, 4 banks)
  Geometry: BA = 2 bits, row = 13 bits (8192), col = 10 bits (1024)
  Sanity check: 4 banks × 8192 rows × 1024 cols × 16 bits = 64 MB
  Rated speed grade: -7 → tCK_min = 7.0 ns (≈142 MHz max CL3)
  Typical MiSTer operating clock: 100 MHz or 96 MHz (core-defined)

  Refresh: 8192 refreshes per 64 ms → average tREFI ≈ 7.81 µs
  Typical per-cycle timings (CL3, -7 grade):
    tRCD ≈ 3 cycles (row → column delay)
    tRP  ≈ 3 cycles (precharge to next active)
    tRC  ≈ 9 cycles (row cycle, active → active same bank)
    tWR  ≈ 2 cycles (write recovery)
    CAS latency = 2 or 3 cycles
```

[I] (inference; chip identified in archive/github/MiSTer-devel/Hardware_MiSTer/README.md:33 @ bbd361962005)

Canonical pipeline for a single 16-bit read (CL=2, no overlap):

```
clk_ram      _|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_
cmd          NOP   ACT   NOP   READ  NOP   NOP   NOP
SDRAM_BA     ---   BANK  ---   BANK  ---   ---   ---
SDRAM_A      ---   ROW   ---   COL   ---   ---   ---
SDRAM_DQ     Z     Z     Z     Z     Z     DATA  Z
                   ^ACT                  ^DATA valid (CL=2 from READ)
```

Refresh slot (auto-refresh every ≈ tREFI):

```
cmd          PRECHG-ALL  NOP   NOP   AUTO_REF   NOP   NOP   NOP   NOP   IDLE
                                     ^ all banks must be closed before this
```

Reset sequence at power-on (per JEDEC SDR convention; observed in all retro SDR controllers):

```
CKE=0 for ≥ 100 µs, then CKE=1
NOP cycles for ≥ 100 µs
PRECHARGE ALL
2× AUTO_REFRESH
LOAD MODE REGISTER (program CL, burst length, sequential/interleave)
```

The `FAST_OUTPUT_REGISTER`/`FAST_INPUT_REGISTER` placement (sys.tcl:95-97) means the registered DQ value is available on the output of the IOE flip-flop one `SDRAM_CLK` cycle after the controller posts it — controllers must account for this single-cycle pad-register stage when computing CAS-data return cycles. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/sys.tcl:95-97 @ f35083f3b40d)

## 5. Minimal working pattern

Template_MiSTer ships with NO SDRAM controller; the unused-port idiom is to tri-state every signal. The clean way for a new core that does NOT consume SDRAM:

```verilog
// archive/github/MiSTer-devel/Template_MiSTer/Template.sv:30 @ f35083f3b40d
assign {SDRAM_DQ, SDRAM_A, SDRAM_BA, SDRAM_CLK, SDRAM_CKE, SDRAM_DQML, SDRAM_DQMH, SDRAM_nWE, SDRAM_nCAS, SDRAM_nRAS, SDRAM_nCS} = 'Z;
```

For a core that DOES use SDRAM, the framework-provided ports are wired top-to-bottom from `sys_top.v` into the `emu` instance — copy the port block verbatim into the core's controller wrapper and let synthesis collapse pad registers:

```verilog
// archive/github/MiSTer-devel/Template_MiSTer/sys/sys_top.v:1834-1856 @ f35083f3b40d
	.SDRAM_DQ(SDRAM_DQ),
	.SDRAM_A(SDRAM_A),
	.SDRAM_DQML(SDRAM_DQML),
	.SDRAM_DQMH(SDRAM_DQMH),
	.SDRAM_BA(SDRAM_BA),
	.SDRAM_nCS(SDRAM_nCS),
	.SDRAM_nWE(SDRAM_nWE),
	.SDRAM_nRAS(SDRAM_nRAS),
	.SDRAM_nCAS(SDRAM_nCAS),
	.SDRAM_CLK(SDRAM_CLK),
	.SDRAM_CKE(SDRAM_CKE),

`ifdef MISTER_DUAL_SDRAM
	.SDRAM2_DQ(SDRAM2_DQ),
	.SDRAM2_A(SDRAM2_A),
	.SDRAM2_BA(SDRAM2_BA),
	.SDRAM2_nCS(SDRAM2_nCS),
	.SDRAM2_nWE(SDRAM2_nWE),
	.SDRAM2_nRAS(SDRAM2_nRAS),
	.SDRAM2_nCAS(SDRAM2_nCAS),
	.SDRAM2_CLK(SDRAM2_CLK),
	.SDRAM2_EN(io_dig),
`endif
```

Inside `emu` the SDRAM2 outputs must be conditioned on `SDRAM2_EN`:

```verilog
// pattern derived from emu_ports.vh:126-127 comment @ f35083f3b40d
wire sdram2_ok = SDRAM2_EN;
assign SDRAM2_CLK = sdram2_ok ? ctrl_sdram2_clk : 1'bZ;
assign SDRAM2_A   = sdram2_ok ? ctrl_sdram2_a   : 13'bZ;
assign SDRAM2_BA  = sdram2_ok ? ctrl_sdram2_ba  : 2'bZ;
assign SDRAM2_DQ  = sdram2_ok ? ctrl_sdram2_dq  : 16'bZ;
assign SDRAM2_nCS = sdram2_ok ? ctrl_sdram2_ncs : 1'bZ;
// ... etc for nRAS, nCAS, nWE
```

The actual controller body (state machine that drives `nCS`/`nRAS`/`nCAS`/`nWE` per command, sequences refresh, manages banks/rows, etc.) is core-private code and is NOT supplied by the framework.

## 6. Common variations across cores

- The framework offers two topologies: single-SDRAM (default) and dual-SDRAM (when the project `.qsf` sources `sys/sys_dual_sdram.tcl`, which sets `MISTER_DUAL_SDRAM=1`). [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/sys_dual_sdram.tcl:51 @ f35083f3b40d)
- Enabling `MISTER_DUAL_SDRAM` re-purposes the analog VGA/audio/SDIO/LED/button pins of the I/O board for the secondary SDRAM module — those analog ports disappear from the `sys_top.v` interface when the macro is set. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/sys_top.v:59-96 @ f35083f3b40d)
- Dual-SDRAM is documented as experimental and is mutually exclusive with the AV Board (which uses the same I/O Board GPIO bank for analog VGA/audio). [C] (archive/github/MiSTer-devel/Hardware_MiSTer/README.md:4-5 @ bbd361962005)
- The supported daughter boards are `SDRAM_xs` (single chip), `SDRAM_xsd` (alternative single-chip layout), and `SDRAM_xsds` (dual chip, populated for `MISTER_DUAL_SDRAM`). [C] (archive/github/MiSTer-devel/Hardware_MiSTer/Addons/SDRAM_xs/ @ bbd361962005, archive/github/MiSTer-devel/Hardware_MiSTer/Addons/SDRAM_xsd/ @ bbd361962005, archive/github/MiSTer-devel/Hardware_MiSTer/Addons/SDRAM_xsds/ @ bbd361962005)
- The reference chip on current daughter boards is `AS4C32M16SB-7TCN` (32M × 16 = 64 MB per chip), giving 64 MB single / 128 MB dual on the latest hardware. Older `SDRAM_xs` boards using 32 MB chips remain in the wild and remain electrically compatible at the pin level. [C] (archive/github/MiSTer-devel/Hardware_MiSTer/README.md:33 @ bbd361962005) [I] (older-chip variant)
- Per-core controller flavour — single-port / dual-port, burst length, CAS latency, refresh policy, byte-mask handling, clock rate, PLL phase-shift between `clk_sys` and `clk_ram` — `[deferred — reference cores not fetched]`.
- Per-core SDRAM2 usage policy — whether the secondary bus stores ROM, work RAM, video memory, or is unused — `[deferred — reference cores not fetched]`.

## 7. Anti-patterns

### A.1 Looking for a controller under `sys/`

- **Symptom:** Engineer searches `Template_MiSTer/sys/` for `sdram.v`/`sdram_ctrl.sv`, finds nothing, assumes the repository is broken or the framework is incomplete.
- **Cause:** SDRAM is core-private. `sys/` exposes only pad-level ports plus pin/IO-standard assignments. There is no shared controller because timing, byte-mask policy, and clocking differ per system being emulated.
- **Fix:** Copy a controller from a reference core (NES, SNES, Genesis, etc.) that targets a similar topology, or write one. Wire its ports to the `SDRAM_*` ports inherited from `emu_ports.vh`.
- **Citation:** archive/github/MiSTer-devel/Template_MiSTer/sys/emu_ports.vh:111-136 @ f35083f3b40d (ports exist) and absence of `sdram*.v` under archive/github/MiSTer-devel/Template_MiSTer/sys/ @ f35083f3b40d.

### A.2 Driving SDRAM2 without gating on `SDRAM2_EN`

- **Symptom:** Core works on hardware with the dual-SDRAM daughter board installed but corrupts memory or fails timing on builds where the board is absent or single-mode is selected at runtime.
- **Cause:** `SDRAM2_EN` (driven by `io_dig` from `sys_top.v`) reports whether the secondary daughter board is electrically present. Cores that hard-drive `SDRAM2_*` outputs assume the board is there.
- **Fix:** Gate every `SDRAM2_*` output behind `SDRAM2_EN`; tri-state (`'Z`) when low, as required by the `emu_ports.vh` comment.
- **Citation:** archive/github/MiSTer-devel/Template_MiSTer/sys/emu_ports.vh:126-127 @ f35083f3b40d, archive/github/MiSTer-devel/Template_MiSTer/sys/sys_top.v:1855 @ f35083f3b40d.

### A.3 Referencing `SDRAM2_DQML`, `SDRAM2_DQMH`, or `SDRAM2_CKE`

- **Symptom:** `error: unknown port SDRAM2_DQML` at elaboration when porting a single-SDRAM controller to the secondary bus.
- **Cause:** The secondary port set is REDUCED — no DQM pins and no CKE. The hardware pin map (`sys_dual_sdram.tcl`) does not assign these signals to any FPGA pad.
- **Fix:** Either word-align every secondary-bus write (so no byte-mask is needed) or use the primary bus for byte-granular traffic. Treat `SDRAM2_CKE` as permanently asserted at the daughter-board level.
- **Citation:** archive/github/MiSTer-devel/Template_MiSTer/sys/emu_ports.vh:128-135 @ f35083f3b40d, archive/github/MiSTer-devel/Template_MiSTer/sys/sys_dual_sdram.tcl:4-41 @ f35083f3b40d.

### A.4 Sharing SDRAM between core and HPS

- **Symptom:** Engineer plans to land ROMs into SDRAM from `Main_MiSTer` over the HPS bus; finds no f2h/AXI path to SDRAM and no DMA target.
- **Cause:** The DE10-Nano SDR SDRAM module is physically wired to FPGA-side pins only — `sys_top.v` declares the ports as top-level FPGA pads, never inside an HPS bridge. The HPS uses DDR3 (DDRAM) for shared memory, not SDR.
- **Fix:** Deliver ROM/data through `ioctl_*` into the core, then have the core's own SDRAM controller write it to SDRAM. For shared HPS↔FPGA memory, use DDRAM (see `31-ddram.md`).
- **Citation:** archive/github/MiSTer-devel/Template_MiSTer/sys/sys_top.v:46-57 @ f35083f3b40d (SDRAM_* are top-level FPGA pads, not bridges).

### A.5 Ignoring auto-refresh

- **Symptom:** Core boots cleanly, runs for seconds, then accumulates random one-bit data errors that spread over time. Most pronounced on hot days or under high traffic load.
- **Cause:** SDR DRAM cells leak; the chip requires 8192 auto-refresh commands per 64 ms (tREFI ≈ 7.81 µs). A controller that never issues `AUTO_REFRESH` will lose data even though every individual transaction looks correct.
- **Fix:** Build a refresh counter that asserts every ~7 µs (slightly faster than tREFI to leave headroom), precharges all banks, issues `AUTO_REFRESH`, then resumes normal traffic.
- **Citation:** archive/github/MiSTer-devel/Hardware_MiSTer/README.md:33 @ bbd361962005 (chip identification — refresh interval is from the `AS4C32M16` datasheet, not the archive).

## 8. Verification

- Use [MemTest_MiSTer](https://github.com/MiSTer-devel/MemTest_MiSTer) — the official SDRAM quality utility — to confirm the daughter board itself is sound before debugging a core controller. The `Hardware_MiSTer/README.md` notes this is the canonical test.
- In simulation, model SDRAM with a behavioural model (the AS4C32M16 vendor model or an equivalent JEDEC SDR model) clocked off `SDRAM_CLK`; verify command sequencing for reset, mode-register-load, refresh, read, write, and write-with-DQM combinations.
- On hardware, the failure modes that point at SDRAM are: garbled tile/sprite pixels (incomplete refresh or wrong CL), ROM checksum failures after long idle periods (refresh missing), drifting boot behaviour (clock phase outside the chip's setup/hold window).
- `MISTER.INI` provides no SDRAM-specific knobs; misbehaviour is debugged via OSD memory-test cores, JTAG / SignalTap on the `SDRAM_*` pads, or `MemTest_MiSTer` swap.
- For the dual-SDRAM path, confirm `SDRAM2_EN` is being driven high by `io_dig` (probe `sys_top.v` line 1855) before suspecting the controller.

## 9. Provenance footer

- archive/github/MiSTer-devel/Template_MiSTer/sys/sys_top.v @ f35083f3b40d — used for §2 (port declarations, polarity, dual-SDRAM gating), §3.1, §3.2, §5 (instance wiring), §6, §7
- archive/github/MiSTer-devel/Template_MiSTer/sys/emu_ports.vh @ f35083f3b40d — used for §2 (contract), §3.3 (core-side port block), §3.4 (tables), §7 (A.2, A.3)
- archive/github/MiSTer-devel/Template_MiSTer/sys/sys.tcl @ f35083f3b40d — used for §2 (pad properties, IO standard, FAST_*_REGISTER), §4 (pad-register cycle), §7
- archive/github/MiSTer-devel/Template_MiSTer/sys/sys_dual_sdram.tcl @ f35083f3b40d — used for §2 (`MISTER_DUAL_SDRAM` macro, SDRAM2 pin map), §3.2, §6 (topology), §7 (A.3)
- archive/github/MiSTer-devel/Template_MiSTer/Template.sv @ f35083f3b40d — used for §2 (Z-tri-state requirement), §5 (minimal pattern)
- archive/github/MiSTer-devel/Hardware_MiSTer/README.md @ bbd361962005 — used for §1, §2 (chip family, board capacity, mandatory daughter board), §4 (chip family for inferred timings), §6 (board variants), §7 (A.5), §8
- archive/github/MiSTer-devel/Hardware_MiSTer/Addons/SDRAM_xs/ @ bbd361962005 — used for §6 (board variants)
- archive/github/MiSTer-devel/Hardware_MiSTer/Addons/SDRAM_xsd/ @ bbd361962005 — used for §6 (board variants)
- archive/github/MiSTer-devel/Hardware_MiSTer/Addons/SDRAM_xsds/ @ bbd361962005 — used for §6 (dual-SDRAM board variant)
