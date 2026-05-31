# hps_io — HPS↔FPGA Bridge Overview

> Bundle version: 2026-05-18
> Pinned commits: `Template_MiSTer` @ `f35083f3b40d`, `Main_MiSTer` @ `136737b4bed4`, `MkDocs_MiSTer` @ `9033bd292fdc`
> Load with: [11-conf-str.md](./11-conf-str.md), [21-hps-io-ioctl-and-download.md](./21-hps-io-ioctl-and-download.md), [22-hps-io-mount-and-sd.md](./22-hps-io-mount-and-sd.md), [23-osd-menu-and-input.md](./23-osd-menu-and-input.md)
> Status mix: [C] [V]

> Errata vs upstream docs: `MkDocs_MiSTer/docs/developer/hps_io.md` at `9033bd292fdc` shows `HPS_BUS[48:0]` (49 bits) and `status[63:0]`. The pinned RTL at `Template_MiSTer/sys/hps_io.sv @ f35083f3b40d` declares `HPS_BUS[45:0]` (46 bits) and `status[127:0]`. This doc follows the pinned RTL.

## 1. Purpose & one-line summary

`hps_io` is the framework module that multiplexes every HPS↔FPGA control exchange — joystick, OSD status, config string, RTC, info popups, gamma table, UART config, sdram size, plus the deferred ioctl/SD/PS2 sub-protocols — onto a single shared command bus driven by the SPI link from `Main_MiSTer`. A core instantiates exactly one `hps_io` and wires the framework-supplied `HPS_BUS` port through unchanged from `emu`'s top. The other docs in this `20-23` range cover the deferred sub-protocols: `21` covers `ioctl_*`, `22` covers `img_*`/`sd_*`, `23` covers OSD/PS2/joystick.

## 2. The contract (must-obey)

- The `HPS_BUS` port is declared `inout [45:0]` (46 bits) in the framework RTL; `emu` must pass it through to `hps_io` byte-identically. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:38 @ f35083f3b40d)
- `sys_top.v` constructs the 46-bit bundle as `{f1, HDMI_TX_VS, clk_100m, clk_ihdmi, ce_hpix, hde_emu, hhs_fix, hvs_fix, io_wait, clk_sys, io_fpga, io_uio, io_strobe, io_wide, io_din, io_dout}` MSB→LSB. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/sys_top.v:1760-1763 @ f35083f3b40d)
- Bit `[33]` is the `io_strobe` rising-edge marker; on each `io_strobe` pulse, `hps_io` advances `byte_cnt` and consumes the 16-bit word on `[31:16]` (`io_din`). [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:184-188,320-323 @ f35083f3b40d)
- Bit `[34]` is `io_enable` (active high; asserted while `~io_ss1 & io_ss2`, the UIO chip select). When it deasserts, `hps_io` resets `cmd`, `byte_cnt`, `sd_ack`, `io_dout`, `ps2skip`, and `img_mounted`. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:303-319 @ f35083f3b40d)
- Bit `[35]` is `fp_enable` (active high; asserted while `~io_ss1 & io_ss0`, the FPGA chip select). It selects the file-IO command block (`FIO_FILE_TX` family) and gates `fp_dout` onto `[15:0]`. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:184-194,624-704 @ f35083f3b40d)
- Bits `[31:16]` are `io_din` (HPS→FPGA word) and bits `[15:0]` are `io_dout` (FPGA→HPS word), driven by `hps_io` per: `EXT_BUS[32] ? EXT_BUS[15:0] : fp_enable ? fp_dout : io_dout`. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:194 @ f35083f3b40d)
- Bit `[32]` is `io_wide`, driven by `hps_io` from the `WIDE` parameter; the HPS uses it to choose 8- vs 16-bit transfer width for the ioctl and SD data paths. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:187,193 @ f35083f3b40d)
- Bit `[36]` is `clk_sys`, driven by `hps_io` back onto the shared bus for sys_top consumers. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:192 @ f35083f3b40d)
- Bit `[37]` is `ioctl_wait`, driven by `hps_io` from the core's `ioctl_wait` input and consumed by sys_top as `io_wait` to throttle SPI handshake. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:191 @ f35083f3b40d; archive/github/MiSTer-devel/Template_MiSTer/sys/sys_top.v:238,256-263 @ f35083f3b40d)
- Bits `[45:38]` carry video-pipeline observables `{f1, vs_hdmi, clk_100, clk_vid, ce_pix, de, hs, vs}` (sys_top→hps_io only), wired into the internal `video_calc` measurement block. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:222-230 @ f35083f3b40d)
- The command byte is the first 16-bit word after `io_enable` rises; `byte_cnt==0` latches `cmd <= io_din`. Subsequent words in the same `io_enable` window are command-specific payload. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:325-326 @ f35083f3b40d)
- The `status` output is 128 bits wide, latched from the 8 × 16-bit payload of command `0x1E` (`UIO_SET_STATUS2`). The core reads it; the framework writes it. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:119,468-480 @ f35083f3b40d; archive/github/MiSTer-devel/Main_MiSTer/user_io.h:40 @ 136737b4bed4)
- A core requests a status writeback by pulsing `status_set` (rising-edge sampled). `hps_io` increments an internal 4-bit flag `stflg` and latches the desired bits into `status_req`; on poll command `0x29` (`UIO_GET_STATUS`) the HPS observes `{4'hA, stflg}` and reads the 8 × 16-bit `status_req`. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:283-287,332,508-519 @ f35083f3b40d; archive/github/MiSTer-devel/Main_MiSTer/user_io.cpp:2554-2569 @ 136737b4bed4)
- `status_menumask[15:0]` is returned to the HPS verbatim on command `0x2E` (`UIO_GET_OSDMASK`) and drives the `H<bit>` / `h<bit>` show/hide gates in `CONF_STR`. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:522 @ f35083f3b40d; archive/github/MiSTer-devel/Main_MiSTer/user_io.h:56 @ 136737b4bed4)
- `buttons[1:0]` is `cfg[1:0]` where `cfg` is loaded by command `0x01` (`UIO_BUT_SW`); bit `[0]` is the OSD-menu button, bit `[1]` is the user reset button (active high). [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:196-199,351 @ f35083f3b40d; archive/github/MiSTer-devel/Main_MiSTer/user_io.h:141-142 @ 136737b4bed4; archive/github/MiSTer-devel/Main_MiSTer/user_io.cpp:3022 @ 136737b4bed4)
- `forced_scandoubler` is `cfg[4]`; `direct_video` is `cfg[10]`. Both follow `CONF_STR` flags managed by the HPS. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:200,202 @ f35083f3b40d)
- `RTC[64:0]` is filled from command `0x22` (`UIO_RTC`): 4 × 16-bit words load `RTC[63:0]` (BCD seconds/minutes/hours/day/month/year/weekday/flags); bit `[64]` toggles when the transfer completes (on `io_enable` deassert with `cmd==0x22`). The core treats `RTC[64]` as a "new data" pulse. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:164,311,499 @ f35083f3b40d; archive/github/MiSTer-devel/Main_MiSTer/user_io.cpp:1082-1087 @ 136737b4bed4)
- `TIMESTAMP[32:0]` is filled by command `0x24` (Unix seconds since 1970-01-01); `TIMESTAMP[32]` toggles on completion. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:167,312,505 @ f35083f3b40d; archive/github/MiSTer-devel/Main_MiSTer/user_io.cpp:1094-1097 @ 136737b4bed4)
- `hps_io` has no dedicated reset port. Core-side reset is conventionally `RESET | status[0] | buttons[1]`. The internal `hps_io` state self-clears on every `io_enable` falling edge. [V] (archive/github/MiSTer-devel/Template_MiSTer/Template.sv:120 @ f35083f3b40d; archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:303-319 @ f35083f3b40d)
- `gamma_bus[20:0]` is driven by `hps_io` as `{clk_sys, gamma_en, gamma_wr, gamma_wr_addr[9:0], gamma_value[7:0]}`; bit `[21]` is an input from the gamma module (back-pressure / response). The core must pass `gamma_bus` to `gamma_corr` or tie it off (default: blank `gamma_bus()` connection). [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:117,252-256,333 @ f35083f3b40d)
- `EXT_BUS[31:16]` and `EXT_BUS[35:33]` are continuous passthroughs of `HPS_BUS[31:16]` and `HPS_BUS[35:33]`; `EXT_BUS[32]` is an arbitration input — when high, the user's EXT_BUS handler drives `HPS_BUS[15:0]` instead of `hps_io`. Unused EXT_BUS is left unconnected; the LSBs default to `io_dout`. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:177-178,194 @ f35083f3b40d)
- The HPS will not communicate with the core until the core-type magic word `{24'h5CA623, core_type}` is read back from `gp_out[31]==1` poll; `core_type` is `0xA4` (single SDRAM) or `0xA8` (dual SDRAM). [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/sys_top.v:272-285 @ f35083f3b40d)

## 3. Ports / signals reference

The module header below shows only the in-scope (non-deferred) ports. `ioctl_*` / `img_*` / `sd_*` / `ps2_*` / `joystick_*` / `paddle_*` / `spinner_*` / `*_rumble` are documented in neighbor docs `21` / `22` / `23`.

```verilog
// archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:35-175 @ f35083f3b40d
module hps_io #(parameter CONF_STR, CONF_STR_BRAM=0, PS2DIV=0, WIDE=0, VDNUM=1, BLKSZ=2, PS2WE=0, STRLEN=$size(CONF_STR)>>3, F12KEYMOD=0)
(
    input             clk_sys,
    inout      [45:0] HPS_BUS,
    // ... joystick / paddle / spinner / ps2  (deferred to 23)
    output      [1:0] buttons,
    output            forced_scandoubler,
    output            direct_video,
    input             video_rotated,
    input             new_vmode,
    inout      [21:0] gamma_bus,
    output reg [127:0] status,
    input      [127:0] status_in,
    input              status_set,
    input       [15:0] status_menumask,
    input             info_req,
    input       [7:0] info,
    // ... img_* / sd_*  (deferred to 22)
    // ... ioctl_*       (deferred to 21)
    output reg [15:0] sdram_sz,
    output reg [64:0] RTC,
    output reg [32:0] TIMESTAMP,
    output reg  [7:0] uart_mode,
    output reg [31:0] uart_speed,
    inout      [35:0] EXT_BUS
);
```

### 3.a Bus / clock / framework

| Signal | Dir | Width | Clock | Active | Meaning | Driven by | Drives |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `clk_sys` | in | 1 | self | rising | System clock for all hps_io state (must match the core's `clk_sys`). [C] | core PLL | every internal `always @(posedge clk_sys)` |
| `HPS_BUS` | inout | 46 | `clk_sys` | mixed | 46-bit shared bus: see §2. [C] | sys_top concat at `sys_top.v:1760-1763` | hps_io decoder + video_calc |
| `EXT_BUS` | inout | 36 | `clk_sys` | mixed | Tap into the command bus for core-specific extensions (e.g. TurboGrafx16 CD). Lower 16 bits driven by core when `EXT_BUS[32]` high; upper bits are passthrough of `HPS_BUS` slices. [C] | core (optional) | core |

### 3.b OSD / buttons / video framing

| Signal | Dir | Width | Clock | Active | Meaning | Driven by | Drives |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `buttons` | out | 2 | `clk_sys` | high | `[0]` OSD/menu button, `[1]` user/reset button. Mirror of `cfg[1:0]` from `UIO_BUT_SW`. [C] | hps_io | core reset / OSD logic |
| `forced_scandoubler` | out | 1 | `clk_sys` | high | `cfg[4]` — user has selected forced scandoubler in OSD or `MiSTer.ini`. [C] | hps_io | core video scandouble |
| `direct_video` | out | 1 | `clk_sys` | high | `cfg[10]` — direct video (HDMI as VGA via adapter). [C] | hps_io | core video routing |
| `video_rotated` | in | 1 | `clk_sys` | high | Core reports it has rotated the framebuffer; surfaces in `video_calc` parameter `1`. [V] | core | hps_io video_calc |
| `new_vmode` | in | 1 | `clk_sys` | toggle | Core toggles to force the framework to renotify the HPS that the resolution has changed. [C] | core | hps_io video_calc |

### 3.c Status / OSD-menu plumbing

| Signal | Dir | Width | Clock | Active | Meaning | Driven by | Drives |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `status` | out | 128 | `clk_sys` | level | Each bit maps to a `CONF_STR` `O[bit]` option. Loaded by command `0x1E`. [C] | hps_io | core |
| `status_in` | in | 128 | `clk_sys` | level | Desired status value when the core wants to write back to the OSD (e.g. autosave state, default value). Captured on rising edge of `status_set`. [C] | core | hps_io `status_req` |
| `status_set` | in | 1 | `clk_sys` | rising | Pulse to request the HPS pull a new status from `status_in` via `UIO_GET_STATUS` (cmd `0x29`). [C] | core | hps_io |
| `status_menumask` | in | 16 | `clk_sys` | level | Per-bit show/hide mask for `CONF_STR` `H<n>` / `h<n>` rules. Returned via cmd `0x2E`. [C] | core | hps_io |
| `info_req` | in | 1 | `clk_sys` | rising | Pulse to request HPS display the `info` string number from the `CONF_STR I` entries. [C] | core | hps_io |
| `info` | in | 8 | `clk_sys` | level | Info-string index latched on rising edge of `info_req`. [C] | core | hps_io |

### 3.d Per-board / housekeeping

| Signal | Dir | Width | Clock | Active | Meaning | Driven by | Drives |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `sdram_sz` | out | 16 | `clk_sys` | level | `[15]` valid, `[1:0]` size: 0=none, 1=32 MB, 2=64 MB, 3=128 MB. `[14]` debug; `[8]` phase up/down; `[7:0]` shift amount. Loaded by cmd `0x31` from `MiSTer.ini`. [C] | hps_io | core SDRAM controller |
| `RTC` | out | 65 | `clk_sys` | mixed | `[63:0]` MSM6242B BCD layout (seconds, minutes, hour, day, month, year, weekday, flags); `[64]` toggles after a fresh update. Loaded by cmd `0x22`. [C] | hps_io | core RTC consumer |
| `TIMESTAMP` | out | 33 | `clk_sys` | mixed | `[31:0]` Unix epoch seconds; `[32]` toggles after update. Loaded by cmd `0x24`. [C] | hps_io | core |
| `uart_mode` | out | 8 | `clk_sys` | level | UART mode flags from `UIO_SET_UART` (cmd `0x3B`). [C] | hps_io | core UART |
| `uart_speed` | out | 32 | `clk_sys` | level | UART baud rate from `UIO_SET_UART`. [C] | hps_io | core UART |
| `gamma_bus` | inout | 22 | `clk_sys` | mixed | `[20:0]` = `{clk_sys, gamma_en, gamma_wr, gamma_wr_addr[9:0], gamma_value[7:0]}` driven by hps_io; `[21]` from gamma module. Pass through to `sys/gamma_corr.sv` or leave unconnected. [C] | hps_io (lower) / gamma block (upper) | gamma_corr |

## 4. Sequencing & timing

Every HPS-driven exchange follows the same envelope:

1. HPS asserts UIO chip select (`io_ss2`), which sys_top decodes as `io_uio = ~io_ss1 & io_ss2`, asserting `HPS_BUS[34]` (`io_enable`).
2. HPS clocks the first 16-bit word; sys_top pulses `io_strobe` on `HPS_BUS[33]` for one `clk_sys`.
3. `hps_io` latches `cmd <= io_din` on `byte_cnt==0`, returns any immediate read-response word in `io_dout`, then advances `byte_cnt`.
4. For each subsequent strobe, `hps_io` consumes/produces a 16-bit payload word selected by `cmd` and `byte_cnt`.
5. HPS deasserts the chip select; sys_top drops `io_enable`. On that falling edge, `hps_io` resets `cmd`, `byte_cnt`, `sd_ack`, `io_dout`, and applies any defer-until-deassert side effects (e.g. toggling `RTC[64]` for cmd `0x22`, `TIMESTAMP[32]` for cmd `0x24`, latching `ps2_key` for cmd `0x05`).

### 4.a `UIO_SET_STATUS2` (0x1E) — status word write

```
clk_sys     |‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_
io_enable   ___/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\__
io_strobe   ________/‾\_____/‾\_____/‾\_____/‾\_____/‾\_____/‾\_____/‾\_____/‾\______
io_din      ----<0x1E>--<W0>----<W1>----<W2>----<W3>----<W4>----<W5>----<W6>----<W7>--
byte_cnt    0       1       2       3       4       5       6       7       8       0
                                                                                  ^reset
status      stale................................................................<NEW>
                                                                                  ^applied
```

- HPS code (Main_MiSTer):

```cpp
// archive/github/MiSTer-devel/Main_MiSTer/user_io.cpp:572-575 @ 136737b4bed4
spi_uio_cmd_cont(UIO_SET_STATUS2);
for (uint32_t i = 0; i < sizeof(cur_status); i += 2) spi_w((cur_status[i + 1] << 8) | cur_status[i]);
DisableIO();
```

- FPGA dispatch:

```verilog
// archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:469-480 @ f35083f3b40d
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

### 4.b `UIO_GET_STATUS` (0x29) — core requests OSD writeback

When the core pulses `status_set`, `hps_io` increments `stflg` (4-bit). The HPS polls cmd `0x29` (one byte) and sees the high nibble `0xA0` set when there is a new request; the low nibble is the latest `stflg`.

```verilog
// archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:283-287 @ f35083f3b40d
old_status_set <= status_set;
if(~old_status_set & status_set) begin
    stflg <= stflg + 1'd1;
    status_req <= status_in;
end
```

```verilog
// archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:332,508-519 @ f35083f3b40d
'h29: io_dout <= {4'hA, stflg};      // byte_cnt==0 response
// ...
//status set
'h29: if(!byte_cnt[MAX_W:4]) begin
        case(byte_cnt[3:0])
            1: io_dout <= status_req[15:00];
            // ... bytes 2..8 stream out status_req[31:16] ... status_req[127:112]
        endcase
    end
```

```cpp
// archive/github/MiSTer-devel/Main_MiSTer/user_io.cpp:2554-2569 @ 136737b4bed4
static void check_status_change()
{
    static u_int8_t last_status_change = 0;
    char stchg = spi_uio_cmd_cont(UIO_GET_STATUS);
    if ((stchg & 0xF0) == 0xA0 && last_status_change != (stchg & 0xF))
    {
        last_status_change = (stchg & 0xF);
        for (uint i = 0; i < sizeof(cur_status); i += 2)
        {
            uint16_t x = spi_w(0);
            cur_status[i] = (char)x;
            cur_status[i + 1] = (char)(x >> 8);
        }
        DisableIO();
        user_io_status_set("[0]", 0);
    }
    else { DisableIO(); }
}
```

### 4.c Buttons exchange (`UIO_BUT_SW`, 0x01)

```cpp
// archive/github/MiSTer-devel/Main_MiSTer/user_io.cpp:3022 @ 136737b4bed4
spi_uio_cmd16(UIO_BUT_SW, map);
```

The 16-bit `map` carries the `BUTTON1` / `BUTTON2` (`[1:0]`) plus the `CONF_*` config flags (csync_en, forced_scandoubler, ypbpr_en, etc.). On the FPGA side:

```verilog
// archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:351 @ f35083f3b40d
'h01: cfg <= io_din;
```

`buttons[1:0] = cfg[1:0]` (combinational), `forced_scandoubler = cfg[4]`, `direct_video = cfg[10]`.

### 4.d RTC write (`UIO_RTC`, 0x22)

Four 16-bit words load `RTC[63:0]` in low-to-high order. The "new data" toggle (`RTC[64]`) is applied at `io_enable` deassert, not during the data stream, so cores see all 64 bits update atomically.

```verilog
// archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:311 @ f35083f3b40d
if(cmd == 'h22) RTC[64] <= ~RTC[64];
// ...
// archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:499 @ f35083f3b40d
'h22: RTC[(byte_cnt-6'd1)<<4 +:16] <= io_din;
```

## 5. Minimal working pattern

Verbatim from `Template_MiSTer/Template.sv` — the smallest legal `hps_io` instance for a core that needs status bits, OSD button, forced-scandoubler, and PS/2 key events. (Block-device, ioctl, and OSD/PS2 lines are tied off by parameter defaults / unconnected ports; see neighbor docs to expand.)

```verilog
// archive/github/MiSTer-devel/Template_MiSTer/Template.sv:89-108 @ f35083f3b40d
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

The conventional reset wiring downstream:

```verilog
// archive/github/MiSTer-devel/Template_MiSTer/Template.sv:120 @ f35083f3b40d
wire reset = RESET | status[0] | buttons[1];
```

## 6. Common variations across cores

- `MISTER_DUAL_SDRAM` define in `sys_top.v` flips the published core-type magic from `0xA4` to `0xA8`. The HPS checks this to enable second-SDRAM autosense and routes `SDRAM2_EN` to `io_dig`. The `emu` ports `SDRAM2_*` are then wired through — but `hps_io`'s own port set is unchanged. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/sys_top.v:272-285,1846-1856 @ f35083f3b40d)
- `MISTER_FB` define gates the `emu`-side framebuffer ports (`FB_EN`, `FB_FORMAT`, `FB_WIDTH`, `FB_HEIGHT`, `FB_BASE`, `FB_STRIDE`, `FB_VBL`, `FB_LL`, `FB_FORCE_BLANK`). These are emu/sys_top wiring, not `hps_io` ports — `hps_io` is unchanged — but the framework's HPS-IO command set in `sys_top.v` (commands `0x2F` `UIO_SET_FBUF`, etc.) is part of the same SPI link. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/sys_top.v:1738-1754,1790-1809 @ f35083f3b40d)
- `MISTER_FB_PALETTE` (nested under `MISTER_FB`) adds palette-RAM ports `FB_PAL_*` to the emu interface; still no change to `hps_io` ports. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/sys_top.v:1739-1745,1801-1807 @ f35083f3b40d)
- `MISTER_DEBUG_NOHDMI` removes the HDMI-side OSD / HPS-IO chip-select path and forces `direct_video = 1`, but `hps_io`'s port wiring is unchanged; only sys_top's `io_osd_hdmi` decoding is gated out. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/sys_top.v:247-249,291-297 @ f35083f3b40d)
- `MISTER_DISABLE_ADAPTIVE`, `MISTER_DISABLE_YC`, `MISTER_DISABLE_ALSA`, `MISTER_DOWNSCALE_NN`, `MISTER_SMALL_VBUF` toggles in `sys_top.v` configure scaler/audio/video features outside `hps_io`. None alter `hps_io`'s port list. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/sys_top.v:399,519,678,711-737 @ f35083f3b40d)
- `WIDE=1` parameter on `hps_io` widens `ioctl_dout`/`sd_buff_*` to 16 bits and reflects via `HPS_BUS[32]` so the HPS uses 16-bit SPI words for those paths. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:180-187 @ f35083f3b40d)
- `VDNUM=N` parameter (1..10 per the module header comment) sets the number of virtual block devices visible to the OSD. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:27,35,182 @ f35083f3b40d)
- `F12KEYMOD=1` requires the user to press F12 together with a GUI modifier to raise the OSD; the core can then receive raw F12 keystrokes. Returned to HPS via cmd `0x43` (`UIO_GET_F12_MOD`). [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:30-32,35,336 @ f35083f3b40d; archive/github/MiSTer-devel/Main_MiSTer/user_io.cpp:1731 @ 136737b4bed4)
- Cross-core differences (NES vs SNES vs PSX vs ao486 etc. parameterization of `WIDE`, `VDNUM`, `BLKSZ`, `PS2WE`, `F12KEYMOD`) [deferred — reference cores not fetched].

## 7. Anti-patterns

### A.1 Driving `HPS_BUS` instead of passing it through

- **Symptom:** HPS-side `Main_MiSTer` reports core magic mismatch on startup, OSD never opens, or status updates are ignored.
- **Cause:** Treating `HPS_BUS` as a regular wire bundle and reassembling it inside `emu`. `HPS_BUS` is `inout [45:0]` with bidirectional bits, and `sys_top` already builds the precise concatenation. Re-driving bits collides with `hps_io`'s assignments to `[37]`, `[36]`, `[32]`, `[15:0]`.
- **Fix:** Pass the `HPS_BUS` emu port to `hps_io.HPS_BUS` by name, unchanged. The only legal additional consumer is the optional `EXT_BUS` block.
- **Citation:** `archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:38,177-194 @ f35083f3b40d`; `archive/github/MiSTer-devel/Template_MiSTer/sys/sys_top.v:1760-1763 @ f35083f3b40d`

### A.2 Treating `status_set` as a level

- **Symptom:** Core writes status_in once, but the OSD reflects only a single update or appears to "stutter" when the core attempts repeated writebacks.
- **Cause:** `status_set` is rising-edge sampled into `old_status_set`. Holding it high indefinitely increments `stflg` once and never again. Pulsing it too fast (faster than the HPS `check_status_change` poll loop, called every poll iteration) can also drop intermediate writes — the HPS only sees the latest `status_req`.
- **Fix:** Toggle `status_set` low-then-high for each new request, and budget for the HPS polling latency (tens of milliseconds). For OSD-driven values, prefer letting the user change them through the menu (cmd `0x1E` write path) rather than pushing from the core.
- **Citation:** `archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:283-287 @ f35083f3b40d`; `archive/github/MiSTer-devel/Main_MiSTer/user_io.cpp:2554-2569 @ 136737b4bed4`

### A.3 Holding `ioctl_wait` low when the core can't accept data

- **Symptom:** ROM downloads corrupt at high bus speeds; the HPS streams data faster than the core consumes it.
- **Cause:** `ioctl_wait` is driven directly onto `HPS_BUS[37]` and is the only handshake the HPS honors during the `FIO_FILE_TX_DAT` data stream. Tying it low when busy lets the HPS race ahead.
- **Fix:** Assert `ioctl_wait` high whenever the downstream consumer (SDRAM controller, decompressor, etc.) is not ready for the next `ioctl_wr` byte/word. The ioctl path is the subject of `21-hps-io-ioctl-and-download.md`; this anti-pattern is included here because `ioctl_wait` is the only ioctl signal that physically lives on `HPS_BUS`.
- **Citation:** `archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:191 @ f35083f3b40d`; `archive/github/MiSTer-devel/Template_MiSTer/sys/sys_top.v:238,256-263 @ f35083f3b40d`

### A.4 Sampling `RTC[63:0]` without watching `RTC[64]`

- **Symptom:** Core reads garbage time-of-day on first frame, or sees half-updated BCD fields.
- **Cause:** `RTC[63:0]` is filled 16 bits per `io_strobe` (cmd `0x22`), so intermediate cycles expose partial state. `RTC[64]` only toggles when the whole transfer completes on `io_enable` deassert.
- **Fix:** Latch `RTC[63:0]` into a core-side register only on transitions of `RTC[64]`. Same pattern applies to `TIMESTAMP[32]`.
- **Citation:** `archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:164,167,311-312,499,505 @ f35083f3b40d`

## 8. Verification

- **Confirm bus pass-through.** Quartus warnings of the form `bus width mismatch` on the `.HPS_BUS(HPS_BUS)` connection mean the local `emu` HPS_BUS declaration disagrees with the framework's 46-bit assumption. Re-include `sys/emu_ports.vh` unchanged.
- **Magic word visible to HPS.** In simulation, drive `gp_out[31] = 0` (sys_top:283 selects `core_magic` instead of `gp_in`) and verify the readback is `{24'h5CA623, 8'hA4}` (or `0xA8` for dual SDRAM).
- **Status round-trip.** Open the OSD, toggle an `O[n]` option, and verify `status[n]` changes one frame later. Use `MiSTer.ini`'s `bootcore_timeout=0` plus a known `CONF_STR` slot.
- **Buttons.** Verify that pressing the front-panel reset button raises `buttons[1]` (level high while pressed), and that the OSD-toggle button raises `buttons[0]` while the menu is open. Long-press behavior is governed by `Main_MiSTer` in `user_io.cpp:3000-3024`.
- **RTC.** Power on with the optional RTC board absent; the HPS falls back to NTP-derived time. Confirm BCD ordering with a simulated `cmd 0x22` write that sets year 0x26, month 0x05, day 0x18 and observe `RTC[47:24]`.
- **status_set / OSD writeback.** Pulse `status_set` once per second from the core; the OSD-displayed value should update within ~1 poll period (~25 ms on default schedule). If never updated, scope the `0x29` poll on the SPI line.
- **`MiSTer.ini` flags that surface bugs:** `forced_scandoubler=1` exercises `cfg[4]`; `direct_video=1` exercises `cfg[10]`; `vga_scaler=1` exercises `cfg[2]` (handled by sys_top, but observable as missing scanlines if hps_io is broken).

## 9. Provenance footer

- `archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv @ f35083f3b40d` — §2 (contract bits), §3 (ports), §4 (cmd `0x01`/`0x1E`/`0x22`/`0x24`/`0x29`/`0x2E`/`0x43` dispatch), §5 (parameter defaults), §6 (parameters), §7 (anti-patterns).
- `archive/github/MiSTer-devel/Template_MiSTer/sys/sys_top.v @ f35083f3b40d` — §2 (HPS_BUS concat, chip-select decode, core_magic), §6 (`MISTER_DUAL_SDRAM`, `MISTER_FB`, `MISTER_DEBUG_NOHDMI`, scaler toggles), §7 (`io_wait` consumer), §8 (magic word check).
- `archive/github/MiSTer-devel/Template_MiSTer/Template.sv @ f35083f3b40d` — §5 (minimal instance), §2 (conventional reset).
- `archive/github/MiSTer-devel/Main_MiSTer/user_io.h @ 136737b4bed4` — §2 (UIO command-byte IDs, `BUTTON*` / `CONF_*` bit mapping, core-type magic).
- `archive/github/MiSTer-devel/Main_MiSTer/user_io.cpp @ 136737b4bed4` — §2 (status request poll), §4 (cmd `0x01`/`0x1E`/`0x22`/`0x24`/`0x29` HPS-side issuers).
- `archive/github/MiSTer-devel/Main_MiSTer/spi.cpp @ 136737b4bed4` — §4 (chip-select / strobe helpers `spi_uio_cmd*`, `EnableIO`/`DisableIO`).
- `archive/github/MiSTer-devel/Main_MiSTer/spi.h @ 136737b4bed4` — §4 (SPI primitive declarations).
- `archive/github/MiSTer-devel/MkDocs_MiSTer/docs/developer/hps_io.md @ 9033bd292fdc` — errata reference (header notes the staleness of the upstream doc against the pinned RTL).
