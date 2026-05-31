# OSD, Menu, and Input

> Bundle version: 2026-05-18
> Pinned commits: `Template_MiSTer` @ `f35083f3b40d`; `Main_MiSTer` @ `136737b4bed4`
> Load with: [20-hps-io-overview.md](20-hps-io-overview.md), [11-conf-str.md](11-conf-str.md), [21-hps-io-ioctl-and-download.md](21-hps-io-ioctl-and-download.md)
> Status mix: `[C]` `[V]` `[I]` (no `[O]` reference cores fetched)

## 1. Purpose & one-line summary

The OSD overlay, input, and pass-through bus surface of `hps_io` is how a MiSTer core reads user input (keyboard, gamepad, analog stick, paddle, spinner, mouse), receives a level signal when the framework menu is open (`OSD_STATUS`), and lets the framework intercept core-adjacent functions (gamma correction, second command channel, UART). The OSD itself is overlaid on the video stream by `sys/osd.v` instantiated in `sys_top.v`, not in the core. A typical core consumes `joystick_0`, `ps2_key`, and `OSD_STATUS`; everything else is optional and can be left dangling.

## 2. The contract (must-obey)

- The core does **not** instantiate `osd.v`; `sys_top.v` instantiates one `osd` for HDMI and one for VGA, both fed from the core's video output downstream of the framework scaler/scanline path. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/sys_top.v:1183-1201 @ f35083f3b40d)
- The core receives a level input `OSD_STATUS` (active high) indicating the framework menu is open; the framework drives it from `osd.osd_status` in `sys_top`. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/emu_ports.vh:153 @ f35083f3b40d)
- `osd.osd_status` is asserted by command `0x40 | mode` (bit `[2]=0` and bit `[3]=0` of the command byte) when the OSD is enabled in menu mode, and cleared by command `0x40` (disable). [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/osd.v:62-77 @ f35083f3b40d)
- The OSD output pipeline introduces 3 `clk_video` cycles of latency on `de/hs/vs/rdout`; the core must tolerate the framework re-timing video for the overlay. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/osd.v:260-284 @ f35083f3b40d)
- `ps2_key[10:0]` decoding: bit `[10]` toggles with every key event, bit `[9]` is press (`1`) or release (`0`), bit `[8]` is the `0xE0` extended-key prefix, bits `[7:0]` are the PS/2 set-2 scancode. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:102-103 @ f35083f3b40d)
- A core must edge-detect `ps2_key[10]` (`old <= ps2_key[10]; if(old != ps2_key[10]) ...`); the bit is a toggle, not a level. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:305-310 @ f35083f3b40d)
- `ps2_mouse[24]` toggles on every mouse event; `[23:16]=Y delta`, `[15:8]=X delta`, `[7:0]=buttons/flags`. The byte order is little-endian assembled across three SPI bytes. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:106 @ f35083f3b40d)
- `ps2_mouse_ext[15:8]` carries reserved/additional button bits; `[7:0]` carries wheel movement. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:107 @ f35083f3b40d)
- `joystick_0..joystick_5` are 32-bit packed-bit registers. Bits `[3:0]` are directional (right, left, down, up) per the SNES-like virtual layout. Bits `[4]` and up are core-defined buttons, mapped by name through `joymapping.cpp` against the `J0` line of `CONF_STR`. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:41-46 @ f35083f3b40d) [I]
- The HPS-side SNES virtual layout uses indices `SYS_BTN_RIGHT=0, LEFT=1, DOWN=2, UP=3, A=4, B=5, X=6, Y=7, L=8, R=9, SELECT=10, START=11`; cores see those bits in `joystick_N`. [C] (archive/github/MiSTer-devel/Main_MiSTer/input.h:37-48 @ 136737b4bed4)
- Joystick 0 and 1 use HPS command bytes `0x02` and `0x03`; joysticks 2..5 use `0x10..0x13`. The FPGA receives the lower 16 bits first then the upper 16 bits on `io_strobe` count 1 and 2. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:352-357 @ f35083f3b40d)
- `joystick_l_analog_N[15:8]` is signed Y (-127..+127), `[7:0]` is signed X (-127..+127). Same layout for `joystick_r_analog_N`. The fabric stores them as `[15:0]` and must be interpreted signed. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:48-61 @ f35083f3b40d)
- The HPS encodes axes as `(char)x, (char)y` two's-complement bytes; reading them as unsigned is a wiring error. [C] (archive/github/MiSTer-devel/Main_MiSTer/input.cpp:2630-2637 @ 136737b4bed4)
- `paddle_N[7:0]` is unsigned 0..255 (no sign bit, no toggle). [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:70-76 @ f35083f3b40d)
- `spinner_N[7:0]` is signed -128..+127 delta; `spinner_N[8]` toggles with every update. The core must detect the toggle to know a new delta is valid. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:78-84 @ f35083f3b40d)
- The spinner write-back is `{~spinner_N[8], io_din[7:0]}` — i.e., the toggle is inverted on every update. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:433-438 @ f35083f3b40d)
- `joystick_N_rumble[15:8]` is the large motor magnitude and `[7:0]` is the small motor magnitude; these are *inputs* to `hps_io` from the core and are polled by HPS via command `0x003F..0x053F`. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:63-68 @ f35083f3b40d)
- `gamma_bus[20:0]` is driven by `hps_io` as `{clk_sys, gamma_en, gamma_wr, gamma_wr_addr[9:0], gamma_value[7:0]}`; `gamma_bus[21]` is sampled back into `hps_io` (read by HPS command `0x32`). The bus is `inout [21:0]` on `hps_io`. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:117 @ f35083f3b40d) (archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:252 @ f35083f3b40d) (archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:333 @ f35083f3b40d)
- A core that needs gamma correction wires `gamma_bus` to `sys/gamma_corr.sv`; the core does not interpret the wires itself. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/gamma_corr.sv:1-25 @ f35083f3b40d) [I]
- `EXT_BUS` is `inout [35:0]`. `hps_io` drives `EXT_BUS[31:16]` from `HPS_BUS[31:16]` (HPS→FPGA data lane), drives `EXT_BUS[35:33]` from `HPS_BUS[35:33]` (strobe/enable/fp_enable), and reads `EXT_BUS[15:0]` back into `HPS_BUS[15:0]` *only* when the core asserts `EXT_BUS[32]` (i.e. the core takes over the readback lane). [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:174-194 @ f35083f3b40d)
- `uart_mode[7:0]` and `uart_speed[31:0]` are output by `hps_io` from HPS command `0x3B`; they convey the user's UART mode (MIDI / RS-232 / ...) and baud rate selection. The actual TX/RXD/RTS/CTS/DTR/DSR pins are routed by `sys_top.v`, not `hps_io`. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:170-171 @ f35083f3b40d) (archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:536-542 @ f35083f3b40d)
- `buttons[1:0]` reflects the I/O board pushbuttons: `[0]` is the OSD button (= F12-equivalent), `[1]` is the user/reset button. Driven by `cfg[1:0]` written by HPS command `0x01`. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:109 @ f35083f3b40d) (archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:197 @ f35083f3b40d)
- `ps2_kbd_clk_in/_data_in` and `ps2_kbd_clk_out/_data_out` (and the mouse equivalents) are only wired live when `hps_io` is instantiated with `PS2DIV>0`; otherwise the outputs are tied to 0. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:550-614 @ f35083f3b40d)
- The OSD enable command (`0x40`/`0x41`) is issued from HPS as `OSD_CMD_ENABLE = 0x41` (turn on with mode bits) and `OSD_CMD_DISABLE = 0x40`. The high nibble selects between OSD-write (`0x20`) and OSD-enable/info (`0x40`) on the wire. [C] (archive/github/MiSTer-devel/Main_MiSTer/osd.cpp:53-55 @ 136737b4bed4) (archive/github/MiSTer-devel/Template_MiSTer/sys/osd.v:73-94 @ f35083f3b40d)

## 3. Ports / signals reference

### 3.1 OSD overlay (lives in `sys/`, not the core)

```verilog
// archive/github/MiSTer-devel/Template_MiSTer/sys/osd.v:4-22 @ f35083f3b40d
module osd
(
	input         clk_sys,
	input         io_osd,
	input         io_strobe,
	input  [15:0] io_din,

	input         clk_video,
	input  [23:0] din,
	input         de_in,
	input         vs_in,
	input         hs_in,
	output [23:0] dout,
	output reg    de_out,
	output reg    vs_out,
	output reg    hs_out,

	output reg    osd_status
);
```

### 3.2 OSD_STATUS as seen by the core

```verilog
// archive/github/MiSTer-devel/Template_MiSTer/sys/emu_ports.vh:153 @ f35083f3b40d
input         OSD_STATUS
```

### 3.3 hps_io input + pass-through port surface

```verilog
// archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:36-175 @ f35083f3b40d
module hps_io #(parameter CONF_STR, CONF_STR_BRAM=0, PS2DIV=0, WIDE=0, VDNUM=1, BLKSZ=2, PS2WE=0, STRLEN=$size(CONF_STR)>>3, F12KEYMOD=0)
(
	input             clk_sys,
	inout      [45:0] HPS_BUS,

	// buttons up to 32
	output reg [31:0] joystick_0,
	output reg [31:0] joystick_1,
	output reg [31:0] joystick_2,
	output reg [31:0] joystick_3,
	output reg [31:0] joystick_4,
	output reg [31:0] joystick_5,

	// analog -127..+127, Y: [15:8], X: [7:0]
	output reg [15:0] joystick_l_analog_0,
	output reg [15:0] joystick_l_analog_1,
	output reg [15:0] joystick_l_analog_2,
	output reg [15:0] joystick_l_analog_3,
	output reg [15:0] joystick_l_analog_4,
	output reg [15:0] joystick_l_analog_5,

	output reg [15:0] joystick_r_analog_0,
	output reg [15:0] joystick_r_analog_1,
	output reg [15:0] joystick_r_analog_2,
	output reg [15:0] joystick_r_analog_3,
	output reg [15:0] joystick_r_analog_4,
	output reg [15:0] joystick_r_analog_5,

	input      [15:0] joystick_0_rumble, // 15:8 - 'large' rumble motor magnitude, 7:0 'small' rumble motor magnitude
	input      [15:0] joystick_1_rumble,
	input      [15:0] joystick_2_rumble,
	input      [15:0] joystick_3_rumble,
	input      [15:0] joystick_4_rumble,
	input      [15:0] joystick_5_rumble,

	// paddle 0..255
	output reg  [7:0] paddle_0,
	output reg  [7:0] paddle_1,
	output reg  [7:0] paddle_2,
	output reg  [7:0] paddle_3,
	output reg  [7:0] paddle_4,
	output reg  [7:0] paddle_5,

	// spinner [7:0] -128..+127, [8] - toggle with every update
	output reg  [8:0] spinner_0,
	output reg  [8:0] spinner_1,
	output reg  [8:0] spinner_2,
	output reg  [8:0] spinner_3,
	output reg  [8:0] spinner_4,
	output reg  [8:0] spinner_5,

	// ps2 keyboard emulation
	output            ps2_kbd_clk_out,
	output            ps2_kbd_data_out,
	input             ps2_kbd_clk_in,
	input             ps2_kbd_data_in,

	input       [2:0] ps2_kbd_led_status,
	input       [2:0] ps2_kbd_led_use,

	output            ps2_mouse_clk_out,
	output            ps2_mouse_data_out,
	input             ps2_mouse_clk_in,
	input             ps2_mouse_data_in,

	// ps2 alternative interface.

	// [8] - extended, [9] - pressed, [10] - toggles with every press/release
	output reg [10:0] ps2_key = 0,

	// [24] - toggles with every event
	output reg [24:0] ps2_mouse = 0,
	output reg [15:0] ps2_mouse_ext = 0, // 15:8 - reserved(additional buttons), 7:0 - wheel movements

	output      [1:0] buttons,
	...
	inout      [21:0] gamma_bus,
	...
	// UART flags
	output reg  [7:0] uart_mode,
	output reg [31:0] uart_speed,

	// for core-specific extensions
	inout      [35:0] EXT_BUS
);
```

### 3.4 Signal table (every signal in scope)

| Signal | Dir | Width | Clock | Active | Meaning | Driven by | Drives |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `OSD_STATUS` | in | 1 | `clk_sys` | high | OSD menu is open. Cores should suppress input-driven gameplay state changes while asserted. [C] | `osd.osd_status` via `sys_top.v` | core logic |
| `osd.io_osd` | in | 1 | `clk_sys` | high | Strobe-window enable for OSD command stream. Decoded inside `sys_top` as `io_ss1 & ~io_ss0` (HDMI) or `io_ss1 & ~io_ss2` (VGA). [C] | `sys_top` | `osd.v` cmd FSM |
| `osd.io_strobe` | in | 1 | `clk_sys` | rising | Per-word strobe on the OSD command stream. [C] | `sys_top` | `osd.v` |
| `osd.io_din[15:0]` | in | 16 | `clk_sys` | level | OSD command/data word. [C] | HPS over SPI | `osd.v` |
| `osd.din[23:0]` | in | 24 | `clk_video` | level | Incoming video pixel (RGB888). [C] | upstream video chain | `osd.v` mixer |
| `osd.de_in/hs_in/vs_in` | in | 1 | `clk_video` | active-high DE; sync polarity normalized upstream | Video timing. [C] | upstream video chain | `osd.v` |
| `osd.dout[23:0]` | out | 24 | `clk_video` | level | Video pixel with OSD overlaid (3 `clk_video`-cycle latency). [C] | `osd.v` mixer | downstream `csync`/output |
| `osd.de_out/hs_out/vs_out` | out | 1 | `clk_video` | matches input | Re-timed video sync. [C] | `osd.v` | `csync`, HDMI/VGA |
| `osd.osd_status` | out reg | 1 | `clk_sys` | high | Mirrors current OSD enable state. Routed to core as `OSD_STATUS`. [C] | `osd.v` | `emu.OSD_STATUS` |
| `joystick_0..joystick_5` | out reg | 32 | `clk_sys` | level | Packed digital buttons; `[3:0]={right,left,down,up}`, `[4..]`=core-defined. [C] | `hps_io` cmd `0x02/0x03/0x10/0x11/0x12/0x13` | core |
| `joystick_l_analog_0..5` | out reg | 16 | `clk_sys` | signed | Left stick: `[15:8]=Y`, `[7:0]=X`, both signed -127..+127. [C] | `hps_io` cmd `0x1a` | core |
| `joystick_r_analog_0..5` | out reg | 16 | `clk_sys` | signed | Right stick: `[15:8]=Y`, `[7:0]=X`, signed -127..+127. [C] | `hps_io` cmd `0x3d` | core |
| `joystick_0_rumble..5_rumble` | in | 16 | `clk_sys` | level | `[15:8]`=large motor, `[7:0]`=small motor; polled by HPS via cmd `0x003F..0x053F`. [C] | core | `hps_io` readback |
| `paddle_0..paddle_5` | out reg | 8 | `clk_sys` | unsigned | 0..255 paddle position. No toggle bit. [C] | `hps_io` cmd `0x1a` w/ sub-idx 15 | core |
| `spinner_0..spinner_5` | out reg | 9 | `clk_sys` | signed delta + toggle | `[7:0]` signed delta -128..+127; `[8]` toggles on every HPS update. Core must edge-detect bit 8. [C] | `hps_io` cmd `0x1a` w/ sub-idx 8..13 | core |
| `ps2_key[10:0]` | out reg | 11 | `clk_sys` | toggle bit | `[10]` toggles on every event; `[9]=pressed`; `[8]=extended (0xE0)`; `[7:0]=PS/2 set-2 scancode`. [C] | `hps_io` cmd `0x05`, latched on `~io_enable` | core |
| `ps2_mouse[24:0]` | out reg | 25 | `clk_sys` | toggle bit | `[24]` toggles on every event; `[23:16]=Y`; `[15:8]=X`; `[7:0]=buttons/flags`. [C] | `hps_io` cmd `0x04` | core |
| `ps2_mouse_ext[15:0]` | out reg | 16 | `clk_sys` | level | `[15:8]`=reserved/additional buttons; `[7:0]`=wheel. [C] | `hps_io` cmd `0x04` | core |
| `ps2_kbd_clk_out/_data_out` | out | 1 | `clk_sys` (PS2 generated internally) | open-drain | Real PS/2 device emulation (clock + data) when `PS2DIV>0`. Tied 0 otherwise. [C] | `ps2_device keyboard` | external PS/2 line |
| `ps2_kbd_clk_in/_data_in` | in | 1 | `clk_sys` | level | PS/2 device→host line (for host writes such as LED commands). [C] | external PS/2 line | `ps2_device keyboard` |
| `ps2_kbd_led_status[2:0]/_led_use[2:0]` | in | 3 each | `clk_sys` | level | Caps/Num/Scroll LED state and "which LEDs the core actually uses". Read by HPS via cmd `0x1f`. [C] | core | `hps_io` readback |
| `ps2_mouse_clk_out/_data_out` | out | 1 | `clk_sys` | open-drain | Real PS/2 mouse device emulation when `PS2DIV>0`. [C] | `ps2_device mouse` | external PS/2 line |
| `ps2_mouse_clk_in/_data_in` | in | 1 | `clk_sys` | level | PS/2 mouse host-to-device line. [C] | external PS/2 line | `ps2_device mouse` |
| `buttons[1:0]` | out | 2 | `clk_sys` | high | `[0]`=OSD button (acts like F12), `[1]`=user/reset button. From I/O board pushbuttons. [C] | `hps_io` cmd `0x01` → `cfg[1:0]` | core |
| `gamma_bus[20:0]` | out (when used) | 21 | `clk_sys` | mixed | `{clk_sys, gamma_en, gamma_wr, gamma_wr_addr[9:0], gamma_value[7:0]}`. Drives `sys/gamma_corr.sv` lookup-table writes. [C] | `hps_io` cmd `0x32`/`0x33` | `gamma_corr` |
| `gamma_bus[21]` | in (when used) | 1 | `clk_sys` | level | Readback bit returned to HPS via cmd `0x32`. Optional. [C] | external gamma chain | `hps_io` |
| `EXT_BUS[31:16]` | passthrough | 16 | `clk_sys` | level | Mirror of `HPS_BUS[31:16]` (= `io_din`). [C] | `hps_io` | core extension |
| `EXT_BUS[35:33]` | passthrough | 3 | `clk_sys` | high | Mirror of `HPS_BUS[35:33]` = `{fp_enable, io_enable, io_strobe}`. [C] | `hps_io` | core extension |
| `EXT_BUS[32]` | in to hps_io | 1 | `clk_sys` | high | When asserted by the core, the core supplies the readback word on `EXT_BUS[15:0]`. [C] | core extension | `hps_io` arbitration |
| `EXT_BUS[15:0]` | in to hps_io | 16 | `clk_sys` | level | Core-driven readback word selected when `EXT_BUS[32]=1`. [C] | core extension | `HPS_BUS[15:0]` |
| `uart_mode[7:0]` | out reg | 8 | `clk_sys` | level | UART mode selector from HPS (MIDI / RS-232 / off / ...). [C] | `hps_io` cmd `0x3B` byte 1 | core |
| `uart_speed[31:0]` | out reg | 32 | `clk_sys` | level | UART baud (bits/s). [C] | `hps_io` cmd `0x3B` bytes 2-3 | core |

> Note: the physical UART pins `UART_TXD/RXD/RTS/CTS/DTR/DSR` are on the `emu` port list (see `emu_ports.vh:138-143`) and are wired by `sys_top.v` directly to the FPGA pins, *not* via `hps_io`. `hps_io` exposes only the user-configured mode/speed. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/emu_ports.vh:138-143 @ f35083f3b40d)

## 4. Sequencing & timing

### 4.1 PS/2 key event delivery (toggle cycle)

```
clk_sys      |‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_
io_enable    ____/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\__________
                  ^ cmd byte=0x05 then up to 4 scancode bytes shifted in
io_strobe    _____|‾|_|‾|_|‾|_|‾|_|‾|_______________ (one rising edge per byte)
ps2_key_raw  ____{ ...left-shift bytes... }<<<latched on cmd byte
ps2_key[10]  ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\__________    (toggles here)
                                            ^ cmd==5 && ~ps2skip on falling io_enable
```

Cycle-by-cycle: HPS asserts `io_enable` (uio chip-select) and shifts the command byte `0x05` plus up to four PS/2 scancode bytes (handling the `0xF0` release prefix and `0xE0` extended prefix) into `ps2_key_raw`. On the **falling edge of `io_enable`** (i.e. `~io_enable && cmd==5`), `hps_io` commits the result: `ps2_key <= {~ps2_key[10], pressed, extended, ps2_key_raw[7:0]}`. The core sees `ps2_key[10]` change exactly once per event. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:258-261 @ f35083f3b40d) (archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:303-310 @ f35083f3b40d)

There is **no level signal** indicating "key is currently down" — the core must edge-detect `ps2_key[10]` and use `ps2_key[9]` (pressed) at the moment of the edge to decide whether to record a press or release. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:102-103 @ f35083f3b40d)

The pause and printscreen keys carry multi-byte sequences and are remapped specially: HPS-side `'hE012E07C` (PrntScr make), `'h7CE0F012` (PrntScr break), and `'hF014F077` (Pause make) are mapped to canonical codes `0x37C`, `0x17C`, `0x377`. Cores should match against the low 9 bits, not the raw sequence. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:307-309 @ f35083f3b40d)

### 4.2 PS/2 mouse event delivery

Similar shape to keyboard: HPS sends cmd `0x04` then 3 bytes (`flags/buttons`, `X delta`, `Y delta`); `ps2_mouse[24]` toggles on falling `io_enable` after a successful 3-byte sequence. Bytes 1..3 of the cycle land in `ps2_mouse[7:0]`, `[15:8]`, `[23:16]`. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:303-304 @ f35083f3b40d) (archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:359-378 @ f35083f3b40d)

### 4.3 Joystick / analog / paddle / spinner update

```
clk_sys     |‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_
io_enable   ____/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\__________
io_strobe   _____|‾|_____|‾|_____|‾|________________
                  ^cmd     ^low16  ^high16
joystick_N  XXXXXXXXXXXXXXXX|<low>|XXXXX|<full>|XXXXXXXXXXXXX
                                          ^ becomes valid after second strobe
```

Digital joysticks are level-driven: `joystick_N` holds the current packed mask as long as HPS does not write a new one. No edge detection is required. Buttons added since the 16→32 transition are also valid on count 2. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:352-357 @ f35083f3b40d)

Analog and paddle/spinner all share command byte `0x1a` (left stick) and `0x3d` (right stick). The first byte selects sub-index: bits `[3:0]` choose stick index 0..5, bits `[7:4]` discriminate paddle/spinner (`15`) vs. analog (`0..5`). The second byte carries the value. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:416-457 @ f35083f3b40d)

Spinner samples must always be acted on by edge-detecting bit `[8]`: even an unchanged delta of zero is signalled by a fresh toggle. Two consecutive identical writes are NOT collapsed because `hps_io` writes `{~spinner_N[8], io_din[7:0]}` unconditionally on every command. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:433-438 @ f35083f3b40d)

### 4.4 OSD command / frame timing

OSD commands arrive on the `io_osd_*` slave selects (`io_ss1 & ~io_ss0` for HDMI, `io_ss1 & ~io_ss2` for VGA). On `~io_osd`, command state resets; on a rising `io_strobe` within `io_osd`, the first word's high nibble selects:

- `0x40 | mode` (`io_din[7:4]==4`): enable/disable OSD. `cmd[0]` is the enable level, `cmd[2]` selects info-mode vs menu mode, and `cmd[3]` selects no-status-update. `osd_status` is updated only on the `~io_osd` edge from the *previous* command. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/osd.v:62-77 @ f35083f3b40d)
- `0x20 | row` (`io_din[7:5]==3'b001`): write 256 bytes into row `cmd[4:0]` of the OSD bitmap; subsequent strobed words land in `osd_buffer[bcnt]`. `io_din[3]` of the cmd byte enables "highres" doubled-vertical mode. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/osd.v:78-94 @ f35083f3b40d)

The video-domain pipeline introduces 3 `clk_video`-cycle latency: `nrdout1` → `rdout2` → `rdout3` → `rdout`. `de/hs/vs` are pipelined alongside in `de1/de2/de3` etc. so the core does not need to match the latency manually — but must produce stable `de_in/hs_in/vs_in` upstream. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/osd.v:260-284 @ f35083f3b40d)

### 4.5 `gamma_bus` handoff

`hps_io` writes the LUT byte stream via cmd `0x33`. For each `0x33` command, three SPI words form one LUT write: address-low (8b), then `{address-high[1:0], value[7:0]}`, then a continuation. The `gamma_wr` bit pulses one `clk_sys` per write; `gamma_corr.sv` latches `gamma_curve[gamma_wr_addr] <= gamma_value` on `gamma_wr`. The cmd `0x32` (one byte `gamma_en`) toggles the enable; cmd `0x32` readback queries `gamma_bus[21]`. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:528-533 @ f35083f3b40d) (archive/github/MiSTer-devel/Template_MiSTer/sys/gamma_corr.sv:24 @ f35083f3b40d)

A core that does **not** use gamma may leave `gamma_bus` unconnected; `hps_io` will still drive its outputs into the void with no effect. [I]

## 5. Minimal working pattern

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

What this shows:

- `HPS_BUS` passes the framework bus through unchanged. The OSD command stream rides on the same bus and is decoded inside `sys_top`'s OSD instance, so the core does not have to forward it.
- `.EXT_BUS()` and `.gamma_bus()` are left empty — both are `inout`s and `hps_io` tolerates leaving them dangling when the core does not need them. This is the canonical "I don't use this" pattern.
- `.ps2_key(ps2_key)` is the canonical keyboard tap. Other unused outputs (joystick analog, paddle, spinner, mouse) default-omit; SystemVerilog `.*` style isn't used here because the Template names individual ports.
- `OSD_STATUS` arrives at the core through `emu_ports.vh`; the Template does not consume it (no input suppression is needed for the random-noise demo core). Cores with gameplay state must consume it (see Anti-patterns). [I]

To use a single digital joystick, add `.joystick_0(joystick_0)` to the same instance and declare `wire [31:0] joystick_0;` at the top alongside `ps2_key`. [I] (archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:41 @ f35083f3b40d)

To use the left analog stick, add `.joystick_l_analog_0(stick_lx_y)` and declare `wire signed [15:0] stick_lx_y;` so comparisons against zero get sign-extended. [I] (archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:48-49 @ f35083f3b40d)

## 6. Common variations across cores

Reference cores (NES, SNES, ao486, etc.) were not fetched in this bundle; cross-core direct comparison is **[deferred — reference cores not fetched]**. Framework-implied variations:

- **Simple single-player core**: wires only `joystick_0`, optionally `ps2_key`, leaves all other inputs and pass-throughs dangling. The Template demonstrates this. [V] (archive/github/MiSTer-devel/Template_MiSTer/Template.sv:94-108 @ f35083f3b40d)
- **Two-player arcade/console core**: wires `joystick_0` and `joystick_1`, often passes both to the same core via a multiplexer keyed on `status` bits. Uses HPS cmd bytes `0x02` and `0x03`. [V] (archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:352-353 @ f35083f3b40d)
- **Up to 6-player arcade core (e.g., Bomberman-class)**: instantiates all six `joystick_0..joystick_5`. Joysticks 0/1 use command bytes `0x02/0x03`; joysticks 2..5 use `0x10..0x13`. The HPS-side `user_io_digital_joystick` switches between the two ranges by index: `(joy<2) ? (UIO_JOYSTICK0+joy) : (UIO_JOYSTICK2+joy-2)`. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:354-357 @ f35083f3b40d) (archive/github/MiSTer-devel/Main_MiSTer/user_io.cpp:1788-1806 @ 136737b4bed4)
- **Analog-aware core (e.g., 3D consoles or N64-class)**: wires `joystick_l_analog_0` (and `_r_` if needed). On the HPS side, N64 has a special range/shape emulation path (`is_n64() ? n64_joy_emu(...)`) before the (char) cast to `user_io_l_analog_joystick`. Other cores get raw -127..+127. [V] (archive/github/MiSTer-devel/Main_MiSTer/input.cpp:2623-2637 @ 136737b4bed4)
- **Paddle/spinner cores (Pong, Arkanoid, Tempest-class)**: wire one or more `paddle_N` or `spinner_N` ports. Paddle is unsigned 0..255 absolute position; spinner is a signed -128..+127 delta with a toggle bit. HPS-side encoding uses cmd `0x1a` sub-index 15, with the sub-sub-index distinguishing paddle 0..5 (indices 0..5) from spinner 0..5 (indices 8..13). [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:426-439 @ f35083f3b40d)
- **PS/2 keyboard/mouse cores (Amiga, ao486, ST, MSX)**: instantiate `hps_io` with `PS2DIV>0` and wire `ps2_kbd_clk_out/_data_out`/`ps2_mouse_clk_out/_data_out` to the actual PS/2 controller block in the core, plus `ps2_kbd_clk_in/_data_in` for host writes (LED commands, mouse host-to-device protocol). Without `PS2DIV>0` these outputs are tied to 0 and only the alternative `ps2_key[10:0]` / `ps2_mouse[24:0]` taps are useful. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:550-614 @ f35083f3b40d)
- **EXT_BUS-using core**: a core that needs a second command channel (e.g., DMA windows for ao486, or large per-frame state for a CPU-emulator core) implements its own command FSM on `EXT_BUS[35:33]` + `EXT_BUS[31:16]`, asserts `EXT_BUS[32]` when it wants to return a word, and drives the word on `EXT_BUS[15:0]`. The Template wires `.EXT_BUS()` to nothing. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:174-194 @ f35083f3b40d)
- **UART-using core (MIDI, SAM Coupé, BBC-class with serial)**: consumes `uart_mode` and `uart_speed` from `hps_io` to configure its internal UART and wires its TX/RX lines to the `UART_TXD/RXD` pins of `emu`. The mode byte selects the personality (e.g., MIDI keeps RS-232 hardware idle); the speed sets the baud divider. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:170-171 @ f35083f3b40d) (archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:536-542 @ f35083f3b40d)
- **Gamma-correcting core**: instantiates `sys/gamma_corr.sv` upstream of the OSD and wires `gamma_bus` from `hps_io` into its `gamma_en/gamma_wr/gamma_wr_addr/gamma_value` inputs. `[deferred — reference cores not fetched]` for which specific cores opt in. [V]
- **Rumble-output core**: drives `joystick_N_rumble[15:0]` with current motor magnitudes; HPS polls the value via cmd `0x003F..0x053F`. The core does not throttle the poll; it just keeps the wires current. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:337-342 @ f35083f3b40d)

## 7. Anti-patterns

### A.1 Treating `ps2_key[10]` as a level (key-currently-down)

- **Symptom:** Holding a key produces continuous key events in the core, or releasing a key never registers; sometimes the same press is processed thousands of times.
- **Cause:** `ps2_key[10]` is a **toggle** that flips on every press *and* every release. It is not "1 while down, 0 while up". Code that reads `if (ps2_key[10] && ps2_key[9])` will fire continuously while the bit happens to be high.
- **Fix:** Edge-detect: `reg old_ks; always @(posedge clk_sys) old_ks <= ps2_key[10]; if(old_ks != ps2_key[10]) ...`. Then act on `ps2_key[9]` (pressed flag) at the edge.
- **Citation:** archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:102-103 @ f35083f3b40d ; archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:303-310 @ f35083f3b40d

### A.2 Forgetting OSD-active input suppression

- **Symptom:** Pressing arrow keys or gamepad directions in the OSD menu causes the player to move in the game underneath, or the OSD's enter/start press also triggers a game action. State saves get corrupted by phantom inputs during navigation.
- **Cause:** The framework keeps streaming `ps2_key`, `joystick_*`, etc., even while the OSD is open. `OSD_STATUS` is the only level signal that says "the menu owns the input right now". Cores that don't gate on it leak menu inputs into gameplay.
- **Fix:** Gate input application (controller polling, key-state writes, edge-detected commits) on `~OSD_STATUS`, or freeze the emulated CPU/timers entirely while `OSD_STATUS` is asserted. The HPS side already partially suppresses keys (it stops passing them after a menu-event sequence), but joystick presses still arrive — explicit gating is the only safe approach.
- **Citation:** archive/github/MiSTer-devel/Template_MiSTer/sys/emu_ports.vh:153 @ f35083f3b40d ; archive/github/MiSTer-devel/Main_MiSTer/user_io.cpp:4197-4222 @ 136737b4bed4

### A.3 Wiring `joystick_l_analog_N` as unsigned

- **Symptom:** "Half" of the analog stick works (one direction moves, the other does nothing or jumps to maximum). At-rest position is interpreted as a strong push. Dead-zone code never triggers.
- **Cause:** The HPS encodes axes as two's-complement bytes via `(char)x, (char)y` in `user_io_l_analog_joystick`. The hps_io output port is `[15:0]` (unsigned by default in Verilog), so wiring `wire [15:0] lx_y` and comparing `lx_y[7:0] > THR` treats `0x80..0xFF` (negative values) as numbers larger than `0x7F` (positive max).
- **Fix:** Declare the consumer as signed: `wire signed [7:0] x = joystick_l_analog_0[7:0]; wire signed [7:0] y = joystick_l_analog_0[15:8];`. Use `$signed(...)` when feeding arithmetic. Compare against signed zero.
- **Citation:** archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:48-49 @ f35083f3b40d ; archive/github/MiSTer-devel/Main_MiSTer/input.cpp:2630-2637 @ 136737b4bed4

### A.4 Trying to instantiate `osd.v` inside the core

- **Symptom:** Duplicate-overlay artifacts (OSD appears twice or in the wrong layer), or compile errors about un-driven `io_osd`/`io_strobe` if the core attempts to hook the OSD into its video pipeline.
- **Cause:** `osd.v` is instantiated by `sys_top.v` once per output (HDMI and VGA), downstream of the core's `VGA_*` outputs and the framework's scaler/scanline path. The core's job ends at `VGA_R/G/B/HS/VS/DE`; the OSD overlay is applied by the framework.
- **Fix:** Drive `VGA_*` cleanly and do not instantiate `osd`. To know the OSD is open, consume `OSD_STATUS`.
- **Citation:** archive/github/MiSTer-devel/Template_MiSTer/sys/sys_top.v:1183-1201 @ f35083f3b40d ; archive/github/MiSTer-devel/Template_MiSTer/sys/sys_top.v:1403-1422 @ f35083f3b40d

## 8. Verification

- **OSD asserted / clear**: open the framework menu (F12 by default, or `LGUI/RGUI`+F12 if `F12KEYMOD=1`); `OSD_STATUS` should go high. Confirm by routing it to `LED_USER` temporarily. Closing the menu should drop it.
- **`ps2_key` toggle**: in simulation, drive `hps_io`'s `io_din` with the byte sequence `0x05` + scancode bytes and pulse `io_strobe`, then drop `io_enable`. Observe `ps2_key[10]` flip exactly once. On hardware, instrument by toggling `LED_USER` on detected edges.
- **Joystick packing**: log `joystick_0` to the SignalTap or to OSD's `Info` overlay; press each button on a known controller in pad-test mode and confirm the bit position matches the `CONF_STR` `J0` line and `SYS_BTN_*` indices.
- **Analog signedness**: rest the stick; `joystick_l_analog_0[15:8]` and `[7:0]` should read close to `0x00`, *not* `0x80`. Push fully right: `[7:0]` should be `0x7F`-ish (or `0x80`-ish for fully left). Wire to OSD `Info` for live inspection.
- **Spinner toggle**: spin once slowly; verify the core ingests every increment by counting toggle edges; static spinner should NOT toggle (the toggle only flips on HPS writes).
- **Gamma path**: set a non-identity gamma in the OSD's gamma curve menu; `gamma_bus[20]` (clk_sys) is always live, but `gamma_en` should go high; LUT load should occur once per curve change. If gamma is enabled and image colors don't shift, suspect missing `sys/gamma_corr.sv` instantiation.
- **EXT_BUS**: drive `EXT_BUS[32]=0` to confirm `hps_io` ignores the core; drive `EXT_BUS[32]=1` with a known constant on `EXT_BUS[15:0]` to confirm HPS reads back the constant.
- **MiSTer.ini flags**: `gamepad_defaults=1` flips between named-mapping and positional-mapping in `joymapping.cpp`; `joystick_dead_zone`, `mouse_throttle`, and `keyrah_mode` change HPS-side processing and can surface bugs that look like fabric-side issues.

## 9. Provenance footer

- `archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv` @ `f35083f3b40d` — used for §2, §3, §4, §6
- `archive/github/MiSTer-devel/Template_MiSTer/sys/osd.v` @ `f35083f3b40d` — used for §2, §3, §4
- `archive/github/MiSTer-devel/Template_MiSTer/sys/emu_ports.vh` @ `f35083f3b40d` — used for §2, §3
- `archive/github/MiSTer-devel/Template_MiSTer/sys/sys_top.v` @ `f35083f3b40d` — used for §2, §7
- `archive/github/MiSTer-devel/Template_MiSTer/sys/gamma_corr.sv` @ `f35083f3b40d` — used for §2, §4
- `archive/github/MiSTer-devel/Template_MiSTer/Template.sv` @ `f35083f3b40d` — used for §5, §6
- `archive/github/MiSTer-devel/Main_MiSTer/osd.cpp` @ `136737b4bed4` — used for §2
- `archive/github/MiSTer-devel/Main_MiSTer/input.cpp` @ `136737b4bed4` — used for §2, §6, §7
- `archive/github/MiSTer-devel/Main_MiSTer/input.h` @ `136737b4bed4` — used for §2
- `archive/github/MiSTer-devel/Main_MiSTer/user_io.cpp` @ `136737b4bed4` — used for §6, §7
- `archive/github/MiSTer-devel/Main_MiSTer/user_io.h` @ `136737b4bed4` — referenced for UIO constants (UIO_JOYSTICK0=0x02, UIO_ASTICK=0x1a, UIO_ASTICK_2=0x3d, UIO_KEYBOARD=0x05, UIO_MOUSE=0x04, UIO_GET_RUMBLE=0x3F)
- `archive/github/MiSTer-devel/Main_MiSTer/joymapping.cpp` @ `136737b4bed4` — used for §2 (SNES virtual button order) and §6 (name-vs-positional default maps)
