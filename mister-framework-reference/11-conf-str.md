# CONF_STR — Core Configuration String Grammar

> Bundle version: 2026-05-18
> Pinned commits: `Template_MiSTer` @ `f35083f3b40d`, `MkDocs_MiSTer` @ `9033bd292fdc`
> Load with: [10-emu-top-level.md](10-emu-top-level.md), [20-hps-io-overview.md](20-hps-io-overview.md)
> Status mix: [C] [V] [O] [I]

## 1. Purpose & one-line summary

`CONF_STR` is the compile-time SystemVerilog string parameter the core passes to `hps_io`. The HPS reads it over SPI to render the OSD, allocate status bits, and bind file/mount slots to ioctl indexes. Editing this string is the only way the core advertises menu options, ROM slots, mount points, and the core version banner.

## 2. The contract (must-obey)

- C.1. `CONF_STR` is a `localparam` (Verilog string) whose bytes the framework reads byte-by-byte via SPI command `0x14`; `STRLEN` defaults to `$size(CONF_STR)>>3`. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:35,248,391 @ f35083f3b40d)
- C.2. Each directive is terminated by a semicolon `;`; lines are concatenated in declaration order. [C] (archive/github/MiSTer-devel/MkDocs_MiSTer/docs/developer/conf_str.md:7 @ 9033bd292fdc)
- C.3. The first directive is the core title (text before the first `;;`); a `;;` empty trailing field is conventional in the title line. [V] (archive/github/MiSTer-devel/Template_MiSTer/Template.sv:59 @ f35083f3b40d)
- C.4. `status[0]` is reserved as Soft Reset; cores must wire it into their reset chain. [C] (archive/github/MiSTer-devel/MkDocs_MiSTer/docs/developer/conf_str.md:37 @ 9033bd292fdc)
- C.5. `status` is 128 bits wide and is the sole consumer of `O`, `T`, `R` directives; the OSD writes whole 16-bit chunks via command `0x1e`. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:119,469-480 @ f35083f3b40d)
- C.6. `status_menumask` is 16 bits wide and is the sole input the OSD reads via command `0x2E`; only indices `0..15` are valid for `H/D/h/d` prefixes. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:122,522 @ f35083f3b40d)
- C.7. Two indexing forms exist: legacy alphanumeric digits `0-9A-V` addressing bits `0..31` (case toggles upper/lower 32-bit half), and modern bracket form `[bit]` or `[high:low]` reaching all 128 status bits. [C] (archive/github/MiSTer-devel/MkDocs_MiSTer/docs/developer/conf_str.md:18-35,60 @ 9033bd292fdc)
- C.8. Only one option may occupy a given status bit; conflicts silently overwrite. [C] (archive/github/MiSTer-devel/MkDocs_MiSTer/docs/developer/conf_str.md:9 @ 9033bd292fdc)
- C.9. `H{Index}` and `D{Index}` (uppercase) hide/disable the option when `menumask[Index]` IS set; `h{Index}` and `d{Index}` (lowercase) hide/disable when `menumask[Index]` is NOT set. [C] (archive/github/MiSTer-devel/MkDocs_MiSTer/docs/developer/conf_str.md:45-46,57-58 @ 9033bd292fdc)
- C.10. Prefix order for a single directive must be the visibility prefix (`H`/`D`/`h`/`d`) first, then the page prefix (`P{#}`), then the directive itself; `P1d5o2,...` is parsed wrong, `d5P1o2,...` is correct. [C] (archive/github/MiSTer-devel/MkDocs_MiSTer/docs/developer/conf_str.md:64 @ 9033bd292fdc)
- C.11. Lowercase directives `o`, `t`, `r` are equivalent to uppercase `O`, `T`, `R` with 32 added to the (legacy-digit) status bit index; the bracket form supersedes this. [C] (archive/github/MiSTer-devel/MkDocs_MiSTer/docs/developer/conf_str.md:73 @ 9033bd292fdc)
- C.12. `T{Index}` produces a one-cycle pulse on `status[Index]` when the OSD entry is selected; `R{Index}` has identical semantics but also closes the OSD afterward. [C] (archive/github/MiSTer-devel/MkDocs_MiSTer/docs/developer/conf_str.md:65,70 @ 9033bd292fdc)
- C.13. `F{Index}` and `S{Slot}` produce ioctl/mount events; transport details are owned by [21-hps-io-ioctl-and-download.md](21-hps-io-ioctl-and-download.md) and [22-hps-io-mount-and-sd.md](22-hps-io-mount-and-sd.md). [C] (archive/github/MiSTer-devel/MkDocs_MiSTer/docs/developer/conf_str.md:48-54,66-69 @ 9033bd292fdc)
- C.14. `v,<n>` is a config version 0–99; bumping it forces all status bits to default on first start after an incompatible CONF_STR change. [C] (archive/github/MiSTer-devel/Template_MiSTer/Template.sv:83-85 @ f35083f3b40d)
- C.15. `V,{Version String}` sets the core name + version banner shown when the core is loaded; idiomatic placement uses `` `BUILD_DATE `` from `sys/build_id.tcl`. [C] (archive/github/MiSTer-devel/MkDocs_MiSTer/docs/developer/conf_str.md:82 @ 9033bd292fdc), [V] (archive/github/MiSTer-devel/Template_MiSTer/Template.sv:86 @ f35083f3b40d), (archive/github/MiSTer-devel/Template_MiSTer/sys/build_id.tcl:5-27 @ f35083f3b40d)
- C.16. Non-OSD directives (`J`, `jn`, `jp`, `V`, `I`, `DEFMRA`) must appear at the bottom of `CONF_STR`. [C] (archive/github/MiSTer-devel/MkDocs_MiSTer/docs/developer/conf_str.md:77 @ 9033bd292fdc)
- C.17. `[ARC1]` / `[ARC2]` are option tokens nested inside an `O[high:low],Aspect ratio,...` directive that mark the two custom aspect ratios driven by `MiSTer.ini` `custom_aspect_ratio_*`. [C] (archive/github/MiSTer-devel/Template_MiSTer/Template.sv:61 @ f35083f3b40d)
- C.18. The string is stored either in distributed logic (default) or in BRAM (`CONF_STR_BRAM=1`); both paths return identical bytes for SPI command `0x14`. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:243-250,1022-1040 @ f35083f3b40d)
- C.19. The legacy Status Bit Map comment block in MkDocs only documents bits 0–63 over a 32-char alphanumeric grid (two halves of 32 bits each, case = upper/lower); bits 64–127 are reachable only via the bracket form. [I] (archive/github/MiSTer-devel/MkDocs_MiSTer/docs/developer/conf_str.md:14-35 @ 9033bd292fdc) cross-checked against (archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:119,469-480 @ f35083f3b40d)

## 3. Ports / signals reference

`hps_io`'s declaration of every CONF_STR-driven port:

```verilog
// archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:35-122 @ f35083f3b40d
module hps_io #(parameter CONF_STR, CONF_STR_BRAM=0, PS2DIV=0, WIDE=0, VDNUM=1, BLKSZ=2, PS2WE=0, STRLEN=$size(CONF_STR)>>3, F12KEYMOD=0)
(
	input             clk_sys,
	inout      [45:0] HPS_BUS,
	...
	output      [1:0] buttons,
	output            forced_scandoubler,
	output            direct_video,
	...
	output reg [127:0] status,
	input      [127:0] status_in,
	input              status_set,
	input       [15:0] status_menumask,
```

The byte-serve fabric:

```verilog
// archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:242-250 @ f35083f3b40d
wire [7:0] conf_byte;
generate
	if(CONF_STR_BRAM) begin
		confstr_rom #(CONF_STR, STRLEN) confstr_rom(.*, .conf_addr(byte_cnt - 1'd1));
	end
	else begin
		assign conf_byte = CONF_STR[{(STRLEN - byte_cnt),3'b000} +:8];
	end
endgenerate
```

Status write path (SPI cmd `0x1e`):

```verilog
// archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:468-480 @ f35083f3b40d
// status, 128bit version
'h1e: if(!byte_cnt[MAX_W:4]) begin
			case(byte_cnt[3:0])
				1: status[15:00]   <= io_din;
				2: status[31:16]   <= io_din;
				3: status[47:32]   <= io_din;
				4: status[63:48]   <= io_din;
				5: status[79:64]   <= io_din;
				6: status[95:80]   <= io_din;
				7: status[111:96]  <= io_din;
				8: status[127:112] <= io_din;
			endcase
		end
```

Menu mask read path (SPI cmd `0x2E`):

```verilog
// archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:521-522 @ f35083f3b40d
//menu mask
'h2E: if(byte_cnt == 1) io_dout <= status_menumask;
```

### Signal table

| Signal | Dir | Width | Clock | Active | Meaning | Driven by | Drives |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `CONF_STR` (parameter) | in | string | n/a | n/a | Compile-time menu/file/mount/version definition. [C] | core `localparam` | SPI cmd `0x14` byte stream + `confstr_rom`. [C] (hps_io.sv:35,248,391 @ f35083f3b40d) |
| `CONF_STR_BRAM` (param) | in | 1 | n/a | high | If 1, store string in inferred BRAM; if 0, distributed logic. [C] | core | `confstr_rom` instantiation. [C] (hps_io.sv:243-250 @ f35083f3b40d) |
| `status` | out | 128 | `clk_sys` | per-bit | OSD-written option bits; consumed by core. [C] | OSD via SPI `0x1e` | core combinational/sequential logic. [C] (hps_io.sv:119,469-480 @ f35083f3b40d) |
| `status[0]` | out | 1 | `clk_sys` | high | Reserved Soft Reset bit. [C] | `T[0]`/`R[0]` directives | core reset chain. [C] (conf_str.md:37 @ 9033bd292fdc; Template.sv:120 @ f35083f3b40d) |
| `status_menumask` | in | 16 | `clk_sys` | per-bit | Visibility mask read by OSD; gates `H/D/h/d` prefixed directives. [C] | core | OSD render decisions via SPI `0x2E`. [C] (hps_io.sv:122,522 @ f35083f3b40d) |
| `status_set` | in | 1 | `clk_sys` | rising edge | Toggle to push `status_in` back to the HPS (savestate / preset). [C] | core | `stflg` increment, HPS read via `0x29`. [C] (hps_io.sv:121,283-287,332,508-518 @ f35083f3b40d) |
| `status_in` | in | 128 | `clk_sys` | data | Status snapshot the core wants persisted when `status_set` toggles. [C] | core | HPS via `0x29` reads. [C] (hps_io.sv:120,286,508-518 @ f35083f3b40d) |
| `ioctl_index[7:0]` | out | 8 | `clk_sys` | per-`F` slot | Encodes file slot index: bits `[5:0]` = `F` index, bits `[7:6]` = extension index. [C] | `F<i>,<ext>` directive on file selection | core load logic — see [21-hps-io-ioctl-and-download.md](21-hps-io-ioctl-and-download.md). [C] (conf_str.md:48-54 @ 9033bd292fdc; hps_io.sv:147 @ f35083f3b40d) |
| `img_mounted` | out | `VDNUM` | `clk_sys` | one-shot | Pulses bit `n` when `S{n},...` mount completes. [C] | `S<i>,<ext>` directive on file selection | core mount logic — see [22-hps-io-mount-and-sd.md](22-hps-io-mount-and-sd.md). [C] (hps_io.sv:128,460-463 @ f35083f3b40d; conf_str.md:66-69 @ 9033bd292fdc) |
| `buttons` | out | 2 | `clk_sys` | high | `buttons[0]`=user button, `buttons[1]`=OSD soft reset; not driven by CONF_STR but consumed alongside `status[0]`. [C] | sys_top board IO via `cfg[1:0]` | core reset chain. [C] (hps_io.sv:109,197 @ f35083f3b40d) |
| `forced_scandoubler` | out | 1 | `clk_sys` | high | `cfg[4]` mirror; not a CONF_STR directive but commonly combined with `O` aspect ratio. [C] | sys_top via `cfg` register | core video chain. [C] (hps_io.sv:110,200 @ f35083f3b40d) |

### Grammar reference table

Every directive that appears in the corpus (Template.sv + MkDocs):

| Directive | Syntax | Produces | Consumed by | Notes |
| --- | --- | --- | --- | --- |
| Title | `<Title>;;` first line | OSD title banner. [C] | OSD render | Double `;;` leaves the V-suffix slot empty until `V,...` directive. [V] (Template.sv:59 @ f35083f3b40d) |
| Separator | `-;` or `-,<text>;` | Visual divider / static OSD label. [C] | OSD render | Static text uses `-, <text>;`. [V] (Template.sv:67 @ f35083f3b40d) |
| Page def | `P{#},{Title};` | Sub-page header for page `#`. [C] | OSD pager | `#` is 1-based. [V] (Template.sv:73 @ f35083f3b40d) |
| Page prefix | `P{#}<directive>` | Places the prefixed directive on page `#`. [C] | OSD pager | Must follow `H/D/h/d` and precede `O/T/R/F/S`. [C] (conf_str.md:64 @ 9033bd292fdc) |
| Option (bracket) | `O[hi:lo],{Name},{opt0},{opt1},...;` or `O[bit],...` | Allocates `status[hi:lo]` (or `status[bit]`); OSD selects an option index. [C] | core logic via `status[]` | Modern form; reaches all 128 bits. [C] (Template.sv:61-62 @ f35083f3b40d) |
| Option (digit) | `O{D1}[{D2}],{Name},{opts};` where `D` ∈ `0-9A-V` | Allocates `status` bits; uppercase `O` = bits 0–31, lowercase `o` = bits 32–63. [C] | core logic via `status[]` | Legacy; restricted to 64 bits. [C] (conf_str.md:60,73 @ 9033bd292fdc) |
| Toggle | `T[bit],{Name};` (or `T{D}` / `t{D}`) | Pulses `status[bit]` on selection. [C] | core (typically Reset) | Pulse width is framework-side; not visible in hps_io.sv RTL — relies on docs. [C] (conf_str.md:70 @ 9033bd292fdc; Template.sv:81 @ f35083f3b40d) |
| Reset + close OSD | `R[bit],{Name};` (or `R{D}` / `r{D}`) | Same as `T` but closes OSD after. [C] | core (typically Reset) | Idiomatic to wire both `T[0]` and `R[0]` to the same bit. [C] (conf_str.md:65 @ 9033bd292fdc; Template.sv:81-82 @ f35083f3b40d) |
| File slot | `F[S][#],{Ext}[,{Text}][,{Address}];` | Triggers an ioctl download with `ioctl_index[5:0]=#` and `ioctl_index[7:6]=ext_idx`. [C] | core download logic — see 21 | `S` = also produce a save mount; `{Ext}` is 3-char extensions concatenated (e.g. `BINGEN`). [C] (conf_str.md:48-54 @ 9033bd292fdc) |
| File remember | `FC[#],{Ext}[,{Text}][,{Address}];` | Like `F` but the HPS remembers the chosen file. [C] | core | (conf_str.md:55 @ 9033bd292fdc) |
| Mount slot | `S{Slot},{Ext}[,{Text}];` | Mounts an image as a virtual disk; pulses `img_mounted[Slot]`. [C] | core mount logic — see 22 | `Slot` ∈ 0..3 by docs; up to `VDNUM-1` by `hps_io` parameterization. [C] (conf_str.md:66-69 @ 9033bd292fdc; hps_io.sv:128 @ f35083f3b40d) |
| Cheat | `C[,{Text}];` | Enables an OSD cheat menu entry. [C] | core/HPS cheat path | Not used by Template.sv. [C] (conf_str.md:43 @ 9033bd292fdc) |
| Cheat (arcade) | `CHEAT;` | DIP-style cheat exposure for arcade cores. [C] | MRA / cheat path | (conf_str.md:44 @ 9033bd292fdc) |
| DIP | `DIP;` | Displays the DIP menu from the MRA. [C] | arcade MRA loader | Arcade cores only. [C] (conf_str.md:47 @ 9033bd292fdc) |
| Hide (capital) | `H{Index}<directive>` | Hides directive when `status_menumask[Index]==1`. [C] | OSD via `0x2E` read | `Index` ∈ 0..15 only. [C] (conf_str.md:57 @ 9033bd292fdc; hps_io.sv:122 @ f35083f3b40d) |
| Hide (lower) | `h{Index}<directive>` | Hides directive when `status_menumask[Index]==0`. [C] | OSD | (conf_str.md:58 @ 9033bd292fdc) |
| Disable (capital) | `D{Index}<directive>` | Disables (greyed) when `status_menumask[Index]==1`. [C] | OSD | (conf_str.md:45 @ 9033bd292fdc) |
| Disable (lower) | `d{Index}<directive>` | Disables when `status_menumask[Index]==0`. [C] | OSD | (conf_str.md:46 @ 9033bd292fdc; Template.sv:70 @ f35083f3b40d) |
| Aspect token | `[ARC1]` / `[ARC2]` (inside `O` opts) | Marks the two custom-aspect option indices fed by `MiSTer.ini`. [C] | OSD aspect logic | Appears only in the Aspect ratio `O` directive. [C] (Template.sv:61 @ f35083f3b40d) |
| Config version | `v,{n};` | Bumping `n` invalidates persisted status on next load. [C] | HPS settings store | `n` ∈ 0..99. [C] (Template.sv:83-85 @ f35083f3b40d) |
| Version banner | `V,{string}` | OSD core-name suffix shown after the title. [C] | OSD render | Idiom: `` "V,v",`BUILD_DATE `` from `sys/build_id.tcl`. [C] (conf_str.md:82 @ 9033bd292fdc; Template.sv:86 @ f35083f3b40d; build_id.tcl:5-27 @ f35083f3b40d) |
| Joystick lock | `J[1],{B1}[,{B2},...];` | Declares joystick button names; `J1` locks keyboard to joystick mode. [C] | menu core | Up to 12 buttons. [C] (conf_str.md:79 @ 9033bd292fdc) |
| jn map | `jn,{SNES_B1},...;` | Default name-based button mapping. [C] | menu core | (conf_str.md:80 @ 9033bd292fdc) |
| jp map | `jp,{SNES_B1},...;` | Default position-based mapping; used when `gamepad_defaults=1`. [C] | menu core | (conf_str.md:81,86-117 @ 9033bd292fdc) |
| Info lines | `I,INFO1,INFO2,...;` | OSD info-banner lines (top-left corner). [C] | OSD info renderer | Up to 255 lines. [C] (conf_str.md:83 @ 9033bd292fdc) |
| Default MRA | `DEFMRA,{name.mra};` | Picks the MRA used when the core is loaded via USB blaster. [C] | HPS loader | Debug-only path. [C] (conf_str.md:84 @ 9033bd292fdc) |

## 4. Sequencing & timing

CONF_STR is purely a compile-time blob plus three runtime SPI exchanges. There is no edge-rate handshake to draw; the relevant temporal events are:

```
Boot:          HPS opens core .rbf  ->  HPS issues SPI cmd 0x14 in a loop
                                       (one byte per io_strobe, byte_cnt=1..STRLEN)
                                       hps_io returns CONF_STR[byte_cnt-1].
                                       HPS parses the string; renders OSD.

OSD option:    User edits an O[..] entry
               -> HPS sends SPI cmd 0x1e with 8 x 16-bit words
                  -> hps_io writes status[15:00], status[31:16], ... status[127:112]
                  -> core sees new status[] on next clk_sys.

OSD trigger:   User selects T[idx] or R[idx]
               -> HPS sets status[idx] high for one cycle (framework-side)
                  -> core treats as one-shot pulse (e.g. soft reset)
                  -> for R[..], OSD also closes.

Menumask:      Core changes status_menumask[15:0]
               -> HPS polls SPI cmd 0x2E
                  -> hps_io returns status_menumask
                  -> OSD re-evaluates H/D/h/d visibility on next render pass.

Status push:   Core toggles status_set with status_in valid
               -> hps_io increments stflg and latches status_req <= status_in
               -> HPS polls cmd 0x29 byte 0 (returns {4'hA, stflg}); on change reads bytes 1..8
                  to persist the snapshot (savestates / presets).
```

```
clk_sys   |‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_
io_enable __/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\__
io_strobe ____/‾\___/‾\___/‾\___/‾\___
              ^byte_cnt=1   ^=2   ^=3   ...
                cmd=0x14: io_dout <= CONF_STR[STRLEN-byte_cnt]
```

Cycle-by-cycle: when `io_enable` rises, `byte_cnt` resets to 0 (hps_io.sv:314). The first `io_strobe` latches `cmd = io_din` (line 326). Subsequent strobes increment `byte_cnt` (line 323); for `cmd=='h14`, `io_dout[7:0]` is updated with `conf_byte` while `byte_cnt <= STRLEN` (line 391). When `io_enable` falls, `cmd` and `byte_cnt` clear.

The CONF_STR-affecting commands and their byte-count semantics:

| SPI cmd | Direction | Bytes | Purpose | RTL |
| --- | --- | --- | --- | --- |
| `0x14` | HPS reads | STRLEN | Read CONF_STR bytes (1..STRLEN). | hps_io.sv:391 |
| `0x1e` | HPS writes | 16 (8 words × 2 bytes) | Write `status[127:0]`. | hps_io.sv:469-480 |
| `0x29` byte 0 | HPS reads | 1 | Read `{4'hA, stflg}` (poll). | hps_io.sv:332 |
| `0x29` bytes 1..8 | HPS reads | 16 | Read `status_req[127:0]`. | hps_io.sv:508-518 |
| `0x2E` | HPS reads | 2 | Read `status_menumask`. | hps_io.sv:522 |

Detailed transport mechanics are owned by [20-hps-io-overview.md](20-hps-io-overview.md).

## 5. Minimal working pattern

Template.sv's CONF_STR block and the `hps_io` instantiation it feeds:

```verilog
// archive/github/MiSTer-devel/Template_MiSTer/Template.sv:57-108 @ f35083f3b40d
`include "build_id.v" 
localparam CONF_STR = {
	"Template;;",
	"-;",
	"O[122:121],Aspect ratio,Original,Full Screen,[ARC1],[ARC2];",
	"O[2],TV Mode,NTSC,PAL;",
	"O[4:3],Noise,White,Red,Green,Blue;",
	"-;",
	"P1,Test Page 1;",
	"P1-;",
	"P1-, -= Options in page 1 =-;",
	"P1-;",
	"P1O[5],Option 1-1,Off,On;",
	"d0P1F1,BIN;",
	"H0P1O[10],Option 1-2,Off,On;",
	"-;",
	"P2,Test Page 2;",
	"P2-;",
	"P2-, -= Options in page 2 =-;",
	"P2-;",
	"P2S0,DSK;",
	"P2O[7:6],Option 2,1,2,3,4;",
	"-;",
	"-;",
	"T[0],Reset;",
	"R[0],Reset and close OSD;",
	"v,0;", // [optional] config version 0-99. 
	        // If CONF_STR options are changed in incompatible way, then change version number too,
			  // so all options will get default values on first start.
	"V,v",`BUILD_DATE 
};

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
```

The matching reset wiring (Soft Reset contract, C.4 + C.12):

```verilog
// archive/github/MiSTer-devel/Template_MiSTer/Template.sv:120 @ f35083f3b40d
wire reset = RESET | status[0] | buttons[1];
```

And the matching status consumer for the Aspect ratio `O[122:121]` directive:

```verilog
// archive/github/MiSTer-devel/Template_MiSTer/Template.sv:52-55 @ f35083f3b40d
wire [1:0] ar = status[122:121];

assign VIDEO_ARX = (!ar) ? 12'd4 : (ar - 1'd1);
assign VIDEO_ARY = (!ar) ? 12'd3 : 12'd0;
```

## 6. Common variations across cores

Direct core-to-core diffs are `[deferred — reference cores not fetched]`. The variations below are demonstrated by productions present in Template.sv plus framework-implied limits:

- Variation V.1: Aspect ratio with `[ARC1]`/`[ARC2]` markers. Template.sv uses `"O[122:121],Aspect ratio,Original,Full Screen,[ARC1],[ARC2];"` to allocate `status[122:121]` and tag the two custom aspect ratios fed from `MiSTer.ini`. Cores without custom aspect support omit the bracket markers. [O] (archive/github/MiSTer-devel/Template_MiSTer/Template.sv:61 @ f35083f3b40d)
- Variation V.2: Paged + visibility-gated file slot. `"d0P1F1,BIN;"` combines three prefixes in order `d0` → `P1` → `F1`. The file slot appears on page 1 only when `status_menumask[0]` is 0; the same `menumask[0]` is wired to `status[5]` via `.status_menumask({status[5]})`, so toggling option `O[5]` on/off shows/hides the file slot. [O] (archive/github/MiSTer-devel/Template_MiSTer/Template.sv:70,105 @ f35083f3b40d)
- Variation V.3: Inverse-polarity hide on the same menumask bit. `"H0P1O[10],Option 1-2,Off,On;"` hides Option 1-2 when `status_menumask[0]` is 1. The opposite polarity to V.2 means option `O[5]` toggling will swap which of the two entries is visible. This is the canonical demonstration that lowercase (`d`/`h`) and uppercase (`D`/`H`) are inverse on the same index. [O] (archive/github/MiSTer-devel/Template_MiSTer/Template.sv:71,105 @ f35083f3b40d)
- Variation V.4: Mount slot on a sub-page. `"P2S0,DSK;"` places mount slot 0 on page 2 with `.DSK` extension. Mount slots can also appear on the main page (no `P{#}` prefix). [O] (archive/github/MiSTer-devel/Template_MiSTer/Template.sv:77 @ f35083f3b40d)
- Variation V.5: Twin Reset entries. Template.sv wires both `"T[0],Reset;"` and `"R[0],Reset and close OSD;"` to the same `status[0]` bit; the user gets two menu items pulsing the same Soft Reset. Cores may keep only one. [O] (archive/github/MiSTer-devel/Template_MiSTer/Template.sv:81-82 @ f35083f3b40d)
- Variation V.6: Status-bit width. Modern cores use `O[high:low]` and reach all 128 bits of `status`. Cores predating the bracket form are capped at 64 bits (32 via uppercase, 32 via lowercase). SNES-class cores that need >64 bits must use the bracket form. [I] (archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:119 @ f35083f3b40d), (archive/github/MiSTer-devel/MkDocs_MiSTer/docs/developer/conf_str.md:14-35,60,73 @ 9033bd292fdc)
- Variation V.7: BRAM vs distributed CONF_STR. `hps_io #(.CONF_STR_BRAM(1))` shifts CONF_STR storage from distributed logic into an inferred BRAM (`confstr_rom`). Useful for very long CONF_STR strings; default is distributed. [O] (archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:243-250,1022-1040 @ f35083f3b40d)
- Variation V.8: Version banner. Idiomatic `"V,v",`BUILD_DATE` injects the YYMMDD build stamp from `sys/build_id.tcl`. Cores may instead hard-code a version string (e.g. `"V,v1.10";`) or omit `V` entirely. [O] (archive/github/MiSTer-devel/Template_MiSTer/Template.sv:86 @ f35083f3b40d), [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/build_id.tcl:5-27 @ f35083f3b40d)

## 7. Anti-patterns

### A.1 Status bit overlap between two directives

- **Symptom:** Two OSD options visibly track each other; toggling one changes the other. Core misbehaves because two semantically different settings share storage.
- **Cause:** Two CONF_STR directives target the same bit (or overlapping ranges) in `status`. The framework does not warn; the last write to that bit wins. The Status Bit Map comment block exists precisely to prevent this.
- **Fix:** Maintain the Status Bit Map header. When adding `O[bit]`/`O[hi:lo]`, update the grid. Never reuse a bit across two `O`/`T`/`R` directives.
- **Citation:** archive/github/MiSTer-devel/MkDocs_MiSTer/docs/developer/conf_str.md:9,14-35 @ 9033bd292fdc

### A.2 Missing `v,<n>` bump after an incompatible CONF_STR change

- **Symptom:** Existing users boot a new core build and see settings land in the wrong bit positions (e.g. "TV Mode" is now PAL by default, "Aspect" is wrong). Visible only on machines that previously ran an older build of the same core.
- **Cause:** CONF_STR options were moved to different bits without bumping `v,<n>`. The HPS replays the saved status bytes into the new bit layout.
- **Fix:** Whenever any `O`/`T`/`R` bit assignment changes (additions, deletions, range edits, reorderings), increment the integer after `v,`. Range 0–99. This forces defaults on first start with the new layout.
- **Citation:** archive/github/MiSTer-devel/Template_MiSTer/Template.sv:83-85 @ f35083f3b40d

### A.3 Forgetting to wire `status[0]` into the reset chain

- **Symptom:** The OSD "Reset" entry does nothing — the core keeps running.
- **Cause:** `T[0],Reset;` and `R[0],Reset and close OSD;` only pulse `status[0]`. The framework does not auto-route this bit; the core must combine it into its own reset.
- **Fix:** Wire `wire reset = RESET | status[0] | buttons[1];` (or equivalent) into the core's reset chain exactly as Template.sv does.
- **Citation:** archive/github/MiSTer-devel/Template_MiSTer/Template.sv:120 @ f35083f3b40d; archive/github/MiSTer-devel/MkDocs_MiSTer/docs/developer/conf_str.md:37 @ 9033bd292fdc

### A.4 Inverted `H` vs `h` (or `D` vs `d`) polarity

- **Symptom:** Menu items appear when they should be hidden (or vice versa). Affected items often "blink" — visible when an option toggles to the wrong state.
- **Cause:** Confusing uppercase vs lowercase polarity. Uppercase (`H`/`D`) hides/disables when `menumask[Index]==1`; lowercase (`h`/`d`) hides/disables when `menumask[Index]==0`.
- **Fix:** Always cross-check Template.sv's idiom: `d0...F1,BIN` and `H0...O[10]` use the SAME `menumask[0]` bit but show the file slot when the option is set and hide the alternate option in the same state. If your menumask bit is inverted relative to the intent, flip the prefix case rather than re-wiring the source bit.
- **Citation:** archive/github/MiSTer-devel/MkDocs_MiSTer/docs/developer/conf_str.md:45-46,57-58 @ 9033bd292fdc; archive/github/MiSTer-devel/Template_MiSTer/Template.sv:70-71 @ f35083f3b40d

### A.5 Wrong prefix ordering (`P{#}d{X}...` instead of `d{X}P{#}...`)

- **Symptom:** OSD never hides the option, or never reaches the intended page. Compiles clean; silently wrong at runtime.
- **Cause:** The CONF_STR parser expects visibility prefix first, then page prefix, then the directive. `P1d5o2,...` is parsed wrong; `d5P1o2,...` is correct.
- **Fix:** Order every prefixed directive as `[H|D|h|d]{Idx}` then `P{Page}` then `O|T|R|F|S{...}`.
- **Citation:** archive/github/MiSTer-devel/MkDocs_MiSTer/docs/developer/conf_str.md:64 @ 9033bd292fdc

### A.6 Over-wide `status_menumask` index

- **Symptom:** `H{Index}` / `D{Index}` with `Index > 15` silently never fires (item never hides/disables).
- **Cause:** `status_menumask` is only 16 bits wide in `hps_io`. Indices outside 0..15 are not reachable.
- **Fix:** Keep `H/D/h/d` indices in 0..15. If you need more visibility groups, route the desired status bit through to one of the 16 menumask bits via `.status_menumask({...})` in the `hps_io` instantiation.
- **Citation:** archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:122 @ f35083f3b40d

## 8. Verification

- Compile-time: `STRLEN = $size(CONF_STR)>>3` must be > 0; a syntax error in CONF_STR appears as a Quartus packed-array sizing error or as an unparseable OSD at runtime. [I] (hps_io.sv:35 @ f35083f3b40d)
- OSD smoke test: load the core, open OSD. Title from the first line must appear; `V,...` suffix must show today's `BUILD_DATE` if you use the idiomatic version line. Missing title means CONF_STR did not parse.
- Status round-trip: set every `O[..]` option to a non-default value, toggle `T[0]` (Reset). Confirm `status[0]` pulse drives `reset` (e.g. core re-initialises). Then reboot the FPGA and confirm settings persist (or get cleared, if you just bumped `v,`).
- Menumask: change the source bit that feeds `status_menumask`. Confirm the matching `H/D/h/d` directives toggle visibility/enablement in the OSD.
- File and mount slots: pick a `F{#},EXT` entry — confirm the file dialog filters on `EXT`. Pick an `S{#},EXT` entry — confirm `img_mounted[#]` pulses for the core to observe. Transport-level checks belong in [21-hps-io-ioctl-and-download.md](21-hps-io-ioctl-and-download.md) and [22-hps-io-mount-and-sd.md](22-hps-io-mount-and-sd.md).
- `MiSTer.ini` knobs to surface bugs: `custom_aspect_ratio_1=…`, `custom_aspect_ratio_2=…` (verifies `[ARC1]`/`[ARC2]`); `gamepad_defaults=1` (switches `jn` → `jp`); the OSD info banner appears when `I,...` is present.

## 9. Provenance footer

- archive/github/MiSTer-devel/Template_MiSTer/Template.sv @ f35083f3b40d — used for §2, §3, §5, §6, §7
- archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv @ f35083f3b40d — used for §2, §3, §4, §6, §7
- archive/github/MiSTer-devel/Template_MiSTer/sys/build_id.tcl @ f35083f3b40d — used for §2, §3, §6
- archive/github/MiSTer-devel/MkDocs_MiSTer/docs/developer/conf_str.md @ 9033bd292fdc — used for §2, §3, §6, §7
