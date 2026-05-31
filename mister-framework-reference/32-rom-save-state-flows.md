# 32 - ROM, Save-RAM, Save-State, and Cheat Flows

> Bundle version: 2026-05-18
> Pinned commits: `Main_MiSTer @ 136737b4bed4`, `Template_MiSTer @ f35083f3b40d`, `MkDocs_MiSTer @ 9033bd292fdc`
> Load with: [21-hps-io-ioctl-and-download.md](21-hps-io-ioctl-and-download.md), [22-hps-io-mount-and-sd.md](22-hps-io-mount-and-sd.md), [30-sdram.md](30-sdram.md), [31-ddram.md](31-ddram.md), [11-conf-str.md](11-conf-str.md)
> Status mix: [C] [V] [O] [I]

> Source note: this is a **data-flow doc**, not a module reference. §3 maps actors and the messages crossing each boundary; for the `ioctl_*` port-level contract see `21 §3`, and for `sd_*` mount-channel signals see `22 §3`. Reference-core RTL is not in the archive snapshot; §6 marks per-core RTL variations as deferred and documents HPS-observable variations under `[O]`.

## 1. Purpose & one-line summary

This document covers the four end-to-end data flows that move user content between disk on the HPS, the FPGA fabric, and back: ROM image delivery, save-RAM (battery-backed cartridge SRAM) persistence, save-state slot save/restore, and cheat-code injection. Each flow uses a different combination of the same primitives (`ioctl_download`/`ioctl_upload`, S-slot mounts, direct DDRAM `shmem_map`, and SPI status polls), so the contract here is the *ordering* and *which primitive to use*, not the wire-level mechanics of any one primitive.

## 2. The contract (must-obey)

### 2.1 ROM load — two HPS code paths share the same `ioctl_download` signal

- ROM-load entry point on the HPS is `user_io_file_tx(name, index, opensave, mute, composite, load_addr)`; F-slot OSD selections call this via the `CONF_STR` parser. [C] (archive/github/MiSTer-devel/Main_MiSTer/user_io.cpp:2640-2895 @ 136737b4bed4; archive/github/MiSTer-devel/Main_MiSTer/user_io.cpp:911-941 @ 136737b4bed4)
- The HPS issues `FIO_FILE_INDEX` then `FIO_FILE_INFO` then `FIO_FILE_TX` (start=0xFF) **before** any data is delivered; the core sees `ioctl_index` and `ioctl_file_ext` stable on the rising edge of `ioctl_download`. [C] (archive/github/MiSTer-devel/Main_MiSTer/user_io.cpp:2664-2676 @ 136737b4bed4; archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:663-684 @ f35083f3b40d)
- **SPI-streaming path** (used when `load_addr == 0`): each chunk is sent via `user_io_file_tx_data` → `FIO_FILE_TX_DAT`; the core latches data on `ioctl_wr` pulses with `ioctl_addr` running from 0. [C] (archive/github/MiSTer-devel/Main_MiSTer/user_io.cpp:2843-2860 @ 136737b4bed4; archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:686-699 @ f35083f3b40d)
- **Direct-DDRAM path** (used when `0x20000000 <= load_addr < 0x40000000`): HPS `shmem_map`s the FPGA-visible DDRAM window and writes the file in 256 KB `read()` chunks straight into RAM; `ioctl_download` is still asserted around the operation but **no `ioctl_wr` pulses fire** and `ioctl_dout`/`ioctl_addr` are not exercised. [C] (archive/github/MiSTer-devel/Main_MiSTer/user_io.cpp:2818-2840 @ 136737b4bed4)
- The direct-DDRAM gate is `load_addr` derived from the `CONF_STR` `F<i>,<ext>[,<symbol>][,<hex_load_addr>]` 4th sub-field; an address outside `[0x20000000, 0x40000000)` falls back to the SPI-streaming path. [C] (archive/github/MiSTer-devel/Main_MiSTer/user_io.cpp:922-931 @ 136737b4bed4)
- A core that wants its ROM via direct-DDRAM must treat `ioctl_download` as the *only* signal of an active ROM load (no `ioctl_wr`); it should hold internal reset across the level and read the ROM out of DDRAM (or the SDRAM-shared shmem window) only after the falling edge. [I] (archive/github/MiSTer-devel/Main_MiSTer/user_io.cpp:2818-2840,2880 @ 136737b4bed4)
- `user_io_set_download(1, load_addr ? bytes2send : 0)` passes the total byte count to `hps_io` in the optional 3rd/4th bytes of the start command; that count is not used by `hps_io` to terminate the transfer — the trailing `FIO_FILE_TX` with byte 0 is the canonical end marker. [C] (archive/github/MiSTer-devel/Main_MiSTer/user_io.cpp:2027-2038,2676,2880 @ 136737b4bed4)
- When the start command carries those optional bytes, they land directly in `ioctl_addr[15:0]` and `ioctl_addr[26:16]` at the rising edge of `ioctl_download`; on the direct-DDRAM path the core can therefore sample `ioctl_addr` once on the rising edge to learn the total ROM size in bytes without needing a side channel. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:668-683 @ f35083f3b40d)
- A core must not advance internal state past reset until the falling edge of `ioctl_download`, because partial ROM contents are visible to the core mid-stream (especially on the direct-DDRAM path where the full window is mapped before any byte is read from disk). [V] (archive/github/MiSTer-devel/Main_MiSTer/user_io.cpp:2818-2840 @ 136737b4bed4; archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:638,678 @ f35083f3b40d)
- A core whose write-target accepts one word per `clk_sys` cycle must drive `ioctl_wait = 0` (constant); a core whose target may stall (e.g. SDRAM refresh, DDRAM contention) must assert `ioctl_wait` until the prior `ioctl_dout`/`ioctl_addr` is consumed, otherwise the next `io_strobe` arrives before the write completes. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:191 @ f35083f3b40d; archive/github/MiSTer-devel/Template_MiSTer/sys/sys_top.v:259 @ f35083f3b40d)
- After `user_io_file_tx` finishes the data phase it calls `user_io_set_download(0)` once; this sends `FIO_FILE_TX` byte 0 and `hps_io` deasserts `ioctl_download` and performs one final `ioctl_addr` increment in the same cycle (see `21 §2 rule 8`). [C] (archive/github/MiSTer-devel/Main_MiSTer/user_io.cpp:2880 @ 136737b4bed4; archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:676-680 @ f35083f3b40d)

### 2.2 Save-RAM persistence — two flavors

- **Mount-channel save-RAM (default)**: when `user_io_file_tx` is called with `opensave=1`, after the data phase the HPS calls `FileGenerateSavePath(rom_name, savefile_path)` and `user_io_file_mount(savefile_path, 0, 1)`; save RAM rides the **S0 mount slot** with `pre=1` (auto-create on write). [C] (archive/github/MiSTer-devel/Main_MiSTer/user_io.cpp:2873-2877 @ 136737b4bed4; archive/github/MiSTer-devel/Main_MiSTer/file_io.cpp:927-955 @ 136737b4bed4)
- `opensave` is set when the `CONF_STR` slot grammar requests it; `parse_config` propagates the flag into `user_io_file_tx`. [C] (archive/github/MiSTer-devel/Main_MiSTer/user_io.cpp:911,915,941 @ 136737b4bed4)
- Save-RAM file path is `<root>/saves/<CoreName>/<basename>.sav` (extension replaced or appended); save subdir is created on demand. [C] (archive/github/MiSTer-devel/Main_MiSTer/file_io.cpp:927-955 @ 136737b4bed4)
- Block-level mount semantics for the S0 slot (LBA, `sd_buff_*`, `img_mounted`/`img_size`) are defined in [22-hps-io-mount-and-sd.md](22-hps-io-mount-and-sd.md); persistence of writes back to the `.sav` file is implicit in the framework's read-write open with `O_SYNC`. [C] (archive/github/MiSTer-devel/Main_MiSTer/user_io.cpp:2120 @ 136737b4bed4)
- **Upload-request save-RAM (cartridge NVRAM / EEPROM)**: the core asserts `ioctl_upload_req` (rising-edge latched into `hps_io`'s `upload_req` flag); the HPS reads opcode `0x3C` *while the OSD is open* and, on a non-zero reply, initiates `user_io_set_upload(1)` → `user_io_file_rx_data` → `user_io_set_upload(0)`. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:289-290,335 @ f35083f3b40d; see 21 §2 rule 13)
- During upload the core presents save-RAM bytes on `ioctl_din[DW:0]` indexed by `ioctl_addr`; `ioctl_rd` pulses once per accepted word. [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:638,686-698 @ f35083f3b40d)
- `ioctl_upload_index[7:0]` is the bank identifier the core supplies; the HPS reads it together with the request flag (`io_dout <= {ioctl_upload_index, 8'd1}` on opcode `0x3C`). [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:153,335 @ f35083f3b40d)
- The `0x3C` poll only fires when the OSD is open — cores that need eager save-back must keep dirty data buffered until the user opens the OSD or shut-down event. [I] (archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:335 @ f35083f3b40d)
- A separate command, `UIO_CHK_UPLOAD = 0x3C`, can also be polled via `spi_uio_cmd` on the regular UIO stream; C64/C128 use this in `user_io_poll` rather than `ioctl_upload_req`. [O] (archive/github/MiSTer-devel/Main_MiSTer/user_io.h:70 @ 136737b4bed4; archive/github/MiSTer-devel/Main_MiSTer/user_io.cpp:3745-3749 @ 136737b4bed4)

### 2.3 Save-states — DDRAM-resident, change-detector triggered

- The save-state region is opt-in via the `CONF_STR` token `SS<base>:<size>` where `base`+`size` lie strictly inside `[0x20000000, 0x40000000)` and `size <= 128 MB`; out-of-range values disable the feature. [C] (archive/github/MiSTer-devel/Main_MiSTer/user_io.cpp:703-727 @ 136737b4bed4; archive/github/MiSTer-devel/MkDocs_MiSTer/docs/developer/savestates.md:7-9 @ 9033bd292fdc)
- The HPS allocates **exactly four slots**, contiguous in DDRAM: slot `i` lives at `ss_base + i*ss_size`. Adding more slots is not a core-side option. [C] (archive/github/MiSTer-devel/Main_MiSTer/user_io.cpp:1922-1962 @ 136737b4bed4; archive/github/MiSTer-devel/MkDocs_MiSTer/docs/developer/savestates.md:3 @ 9033bd292fdc)
- The first 64 bits of each slot are *control*: `[31:0]` is the *change detector*, `[63:32]` is the *savestate size* in 32-bit words (excluding the control header). [C] (archive/github/MiSTer-devel/MkDocs_MiSTer/docs/developer/savestates.md:13-21 @ 9033bd292fdc; archive/github/MiSTer-devel/Main_MiSTer/user_io.cpp:1980-1981 @ 136737b4bed4)
- On core launch (ROM-load with `opensave`), the HPS `shmem_map`s the four-slot region, zero-fills it, loads any existing slot files from disk, and **forces every change-detector word to `0xFFFFFFFF`** so the next core-side write is detected as a change. [C] (archive/github/MiSTer-devel/Main_MiSTer/user_io.cpp:1923-1962 @ 136737b4bed4; archive/github/MiSTer-devel/MkDocs_MiSTer/docs/developer/savestates.md:17 @ 9033bd292fdc)
- The core saves a state by (a) writing the payload, (b) writing the size word `[63:32]`, then (c) writing the change detector `[31:0]` to a new value. The HPS polls each slot's change detector at 1000 ms cadence; on a delta it flushes `(size+2)*4` bytes from DDRAM to disk. [C] (archive/github/MiSTer-devel/Main_MiSTer/user_io.cpp:1971-2008 @ 136737b4bed4; archive/github/MiSTer-devel/MkDocs_MiSTer/docs/developer/savestates.md:13-31 @ 9033bd292fdc)
- The write-back order matters: the change detector must be updated **after** the payload and the size word, or the HPS may flush a half-written state. [I] (archive/github/MiSTer-devel/Main_MiSTer/user_io.cpp:1980-1988 @ 136737b4bed4; archive/github/MiSTer-devel/MkDocs_MiSTer/docs/developer/savestates.md:14-17 @ 9033bd292fdc)
- The change-detector value is persisted in the file but **not re-read on restore**; it resets to `0xFFFFFFFF` on every core launch, so an unchanged-then-relaunched state still triggers exactly one flush on the next legitimate write. [C] (archive/github/MiSTer-devel/MkDocs_MiSTer/docs/developer/savestates.md:17 @ 9033bd292fdc; archive/github/MiSTer-devel/Main_MiSTer/user_io.cpp:1958 @ 136737b4bed4)
- The save-state file path is `<root>/savestates/<CoreName>/<basename>_<N>.ss` for slots 2-4; slot 1 prefers `_1.ss` and falls back to the un-suffixed `.ss` on load. [C] (archive/github/MiSTer-devel/Main_MiSTer/file_io.cpp:957-985 @ 136737b4bed4; archive/github/MiSTer-devel/Main_MiSTer/user_io.cpp:1936-1944,1992 @ 136737b4bed4)
- The polling `process_ss(0)` runs from `user_io_poll`, so the save-state monitor is alive only while the main loop is alive (no separate thread). [C] (archive/github/MiSTer-devel/Main_MiSTer/user_io.cpp:3753 @ 136737b4bed4)
- GBA defaults to `ss_base = 0x3E000000, ss_size = 0x100000` even without `SS` in `CONF_STR`. [O] (archive/github/MiSTer-devel/Main_MiSTer/user_io.cpp:1053-1056 @ 136737b4bed4)

### 2.4 Cheats — index 255 over the SPI-streaming path

- The cheat blob is a contiguous byte array of `enabled_cheats * cheat_unit_size` bytes; default `cheat_unit_size = 16` and `cheat_max_active = 128`, so `CHEAT_SIZE = 128 * 16` is the framework upper bound. [C] (archive/github/MiSTer-devel/Main_MiSTer/cheats.cpp:64-71 @ 136737b4bed4)
- The cheat blob is delivered via the regular ioctl-download path with `ioctl_index = 255`: `user_io_set_index(255)` → `user_io_set_download(1)` → `user_io_file_tx_data(buff, pos)` → `user_io_set_download(0)`. [V] (archive/github/MiSTer-devel/Main_MiSTer/cheats.cpp:378-385 @ 136737b4bed4)
- Cheats are re-sent on every toggle (enable/disable) and reset to zero at `cheats_init` (a 2-byte download of `0x0000`). [V] (archive/github/MiSTer-devel/Main_MiSTer/cheats.cpp:147-152,456-459 @ 136737b4bed4)
- N64 is the explicit deviation — its cheat engine runs on the HPS side against an RDRAM `shmem_map` at `0x30000000`, so the cheat blob is **not** delivered via ioctl. [O] (archive/github/MiSTer-devel/Main_MiSTer/cheats.cpp:146-152,375-378 @ 136737b4bed4; archive/github/MiSTer-devel/Main_MiSTer/support/n64/n64.cpp:1411-1414,1445-1456 @ 136737b4bed4)
- Arcade cores use `cheats_init_arcade(unit_size, max_active)` to pre-load cheats from MRA; the same `user_io_set_index(255)` delivery applies. [V] (archive/github/MiSTer-devel/Main_MiSTer/cheats.cpp:99-134 @ 136737b4bed4)
- The cheat record format on the framework side is opaque (the HPS reads cheat files verbatim from a `<root>/cheats/<CoreName>/<crc>.zip` and concatenates the enabled entries); the core must define and decode its own per-unit semantics. [I] (archive/github/MiSTer-devel/Main_MiSTer/cheats.cpp:154-196,348-385 @ 136737b4bed4)

### 2.5 Ordering across all flows

- For an OSD ROM load triggered from an F-slot, the canonical order at the HPS is: (i) `cheats_init(zero, romcrc)` resets the cheat blob if applicable, (ii) `user_io_file_tx(...)` runs the ROM load (with optional direct-DDRAM placement), (iii) inside `user_io_file_tx`: `process_ss(name)` (re-initializes savestate DDRAM and loads existing slot files), (iv) `user_io_file_mount(<basename>.sav, 0, 1)` (save-RAM mount), and (v) `user_io_set_download(0)` (drops `ioctl_download`). [C] (archive/github/MiSTer-devel/Main_MiSTer/user_io.cpp:2640-2880 @ 136737b4bed4; archive/github/MiSTer-devel/Main_MiSTer/cheats.cpp:137-152 @ 136737b4bed4)
- `process_ss` is called **inside** `user_io_file_tx` while `ioctl_download` is high; the savestate DDRAM region is therefore guaranteed to be set up before the core is allowed to leave its load-reset state. [C] (archive/github/MiSTer-devel/Main_MiSTer/user_io.cpp:2781 @ 136737b4bed4)
- The save-RAM mount happens **after** the ROM data phase but **before** `set_download(0)`, so a core that uses both should not consume save-RAM contents until the falling edge of `ioctl_download`. [I] (archive/github/MiSTer-devel/Main_MiSTer/user_io.cpp:2873-2880 @ 136737b4bed4)

## 3. Process map (actors and the messages between them)

§3 here is a process diagram, not a port table. For port-level signal definitions see `21 §3` (ioctl_*) and `22 §3` (sd_*).

### 3.1 Actors

| Actor | Side | Role |
| --- | --- | --- |
| OSD / UI | HPS userspace | Triggers `parse_config` actions on file selection; opens menu for save-back. [C] |
| `Main_MiSTer` (`user_io`/`cheats`/`file_io`) | HPS userspace | Owns `user_io_file_tx`, `process_ss`, `cheats_send`, `user_io_file_mount`, and `shmem_map` for direct DDRAM placement. [C] |
| SPI bus | HW boundary | Carries `FIO_*` opcodes and the UIO command/status stream. [C] |
| `hps_io` (FPGA `sys/`) | FPGA fabric | Decodes `FIO_*` into `ioctl_*` ports; latches `ioctl_upload_req` rising edge. [C] |
| Core loader (per-core) | FPGA fabric | Routes `ioctl_*` writes into SDRAM/DDRAM/BRAM; holds core in reset while `ioctl_download` is high. [V] |
| SDRAM / DDRAM controllers | FPGA fabric | Accept ROM bytes; serve save-RAM/save-state DDRAM region back to HPS via `f2sdram`. See 30/31. [C] |
| Save / savestate files | HPS fs (`/media/fat/saves`, `/media/fat/savestates`) | Disk-side persistence. [C] |

### 3.2 ROM load — SPI-streaming path

```
OSD selects F-slot ROM
        |
        v
  parse_config (HPS)                       [user_io.cpp:911-941]
        |
        | user_io_file_tx(name, idx, opensave, 0, 0, 0)
        v
+----------------------+
| user_io_file_tx (HPS)|  -- SPI:FIO_FILE_INDEX --> [hps_io]
|                      |  -- SPI:FIO_FILE_INFO  --> [hps_io] -> ioctl_index, ioctl_file_ext
|                      |  -- SPI:FIO_FILE_TX(0xFF) -> [hps_io] -> ioctl_download <= 1, ioctl_addr <= 0
|  loop: read 4 KB     |
|   from file          |
|   -> spi_write       |  -- SPI:FIO_FILE_TX_DAT(buf,N) -> [hps_io]
|                      |                                        \--> per word:
|                      |                                              ioctl_dout, ioctl_wr pulse,
|                      |                                              ioctl_addr += step
|                      |                                              [core: latch into SDRAM/BRAM]
|  loop end            |
|   -> set_download(0) |  -- SPI:FIO_FILE_TX(0x00) -> [hps_io] -> ioctl_download <= 0
+----------------------+
        |
        | (if opensave) process_ss(name)             [user_io.cpp:2781]
        |   - shmem_map ss_base..ss_base+4*ss_size
        |   - load existing _N.ss into DDRAM
        |   - force change-detector words to 0xFFFFFFFF
        |
        | (if opensave) FileGenerateSavePath + user_io_file_mount(savefile, 0, 1)
        |                                            [user_io.cpp:2873-2877]
        v
core's loader sees the falling edge of ioctl_download and releases internal reset.
```

Flow source: [C] (archive/github/MiSTer-devel/Main_MiSTer/user_io.cpp:2640-2895 @ 136737b4bed4; archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:618-704 @ f35083f3b40d)

### 3.3 ROM load — direct-DDRAM path (large ROMs, `F<i>,...,<load_addr>`)

```
OSD selects F-slot with hex load_addr in [0x20000000, 0x40000000)
        |
        v
  parse_config (HPS) extracts load_addr        [user_io.cpp:922-931]
        |
        v
+----------------------+
| user_io_file_tx (HPS)|  -- SPI:FIO_FILE_INDEX/INFO --> [hps_io] -> ioctl_index, ioctl_file_ext
|                      |  -- SPI:FIO_FILE_TX(0xFF, size16, size16) --> ioctl_download <= 1
|                      |
|  shmem_map(fpga_mem( |
|     load_addr),      |
|     bytes2send) ----------------> [HPS-DDRAM bridge / f2sdram] <----> [FPGA fabric sees ROM bytes at load_addr]
|                      |
|  loop: read 256 KB   |
|       direct into    |
|       mapped DDRAM   |  (NO SPI data flows; no ioctl_wr pulses)
|  shmem_unmap         |
|                      |
|   -> set_download(0) |  -- SPI:FIO_FILE_TX(0x00) --> ioctl_download <= 0
+----------------------+
        |
        v
core's loader sees ioctl_download go high then low with NO ioctl_wr pulses.
Reads ROM from DDRAM (or SDRAM-shared shmem region) only after the falling edge.
```

Flow source: [C] (archive/github/MiSTer-devel/Main_MiSTer/user_io.cpp:2818-2840 @ 136737b4bed4; archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:668-683 @ f35083f3b40d)

### 3.4 Save-RAM persistence — mount-channel flavor (S0 slot)

```
After ROM load:
  HPS calls FileGenerateSavePath(rom, savefile)        [file_io.cpp:927]
  HPS calls user_io_file_mount(savefile, 0, pre=1)     [user_io.cpp:2082-2213]
        |
        | -- SPI:UIO_SET_SDINFO (size64) ---------------+
        | -- SPI:UIO_SET_SDSTAT (slot 0 mask, RO bit) --+--> [hps_io] -> img_mounted[0]=1, img_size, img_readonly
        v
core latches img_size on img_mounted[0]=1 (one-cycle pulse).
Subsequent sector read/write traffic via sd_lba[0]/sd_rd[0]/sd_wr[0]/sd_buff_* (see 22 §3, §4).
Writes from the core propagate to the .sav file because user_io_file_mount opened it O_RDWR|O_SYNC.
                                                        [user_io.cpp:2120]
```

Flow source: [C] (archive/github/MiSTer-devel/Main_MiSTer/user_io.cpp:2082-2213 @ 136737b4bed4)

### 3.5 Save-RAM persistence — upload-request flavor (NVRAM/cart)

```
Core has dirty save-RAM:
  pulse ioctl_upload_req >=1 clk_sys cycle
        |
        v
  hps_io latches rising edge into upload_req (sticky bit)
                                                        [hps_io.sv:289-290]
        ... user opens OSD ...
        v
HPS polls opcode 0x3C while OSD active:
        |
        | -- SPI:cmd 0x3C --> [hps_io] -> io_dout = {ioctl_upload_index, 8'd1}, upload_req <= 0
        |
        v
  Main_MiSTer sees flag, prepares save buffer of correct size for ioctl_upload_index
        |
        | -- SPI:FIO_FILE_INDEX (bank) --> ioctl_index
        | -- SPI:FIO_FILE_TX(0xAA) ----> ioctl_upload <= 1, ioctl_addr <= 0
        |
        | -- SPI:FIO_FILE_TX_DAT (read) --> per word: ioctl_addr increments first,
        |                                            ioctl_din sampled, ioctl_rd pulses
        | ...
        | -- SPI:FIO_FILE_TX(0x00) -> ioctl_upload <= 0
        v
HPS writes buffer to .sav (or core-defined file path).
```

Flow source: [C] (archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:289-290,335,668-704 @ f35083f3b40d)

### 3.6 Save-state save/restore — DDRAM-resident, polling

```
At ROM-load time (inside user_io_file_tx):
  process_ss(rom_name)                                   [user_io.cpp:2781,1903-1966]
        - for i in 0..3:
            shmem_map(ss_base + i*ss_size, ss_size) into base[i]
            zero-fill the slot
            if <rom>_<i+1>.ss exists on disk, read it into base[i]
            base[i][0] = 0xFFFFFFFF      (force change-detect re-trigger)

Steady state (per user_io_poll iteration, ~constantly):
  process_ss(0)                                          [user_io.cpp:3753,1971-2008]
        - throttled to 1000 ms cadence
        - for i in 0..3:
            curcnt = ((uint32_t*)base[i])[0]
            size   = ((uint32_t*)base[i])[1]
            if curcnt != ss_cnt[i]:
                ss_cnt[i] = curcnt
                size_bytes = (size + 2) * 4
                if 0 < size_bytes <= ss_size:
                    write base[i] to <rom>_<i+1>.ss (O_CREAT|O_TRUNC|O_RDWR|O_SYNC)

Core side (RTL — illustrative, [I]):
  When user selects "save state to slot i" in core OSD:
        1. write payload to ss_base + i*ss_size + 8.. (skip 8-byte header)
        2. write size-in-words to ss_base + i*ss_size + 4
        3. LAST: bump ss_base + i*ss_size + 0 to a new value (e.g. ++)
  When user selects "load state from slot i":
        1. read size-in-words from header[1]
        2. read payload from ss_base + i*ss_size + 8..
```

Flow source: [C] HPS side (archive/github/MiSTer-devel/Main_MiSTer/user_io.cpp:1903-2008,3753 @ 136737b4bed4; archive/github/MiSTer-devel/MkDocs_MiSTer/docs/developer/savestates.md:13-21 @ 9033bd292fdc). Core side: [I] (synthesized from the savestates.md contract).

### 3.7 Cheat injection — index 255 download (or HPS-side RDRAM patch for N64)

```
On ROM open:
  cheats_init(rom_path, romcrc)                          [cheats.cpp:137-197]
        - clear active list
        - if NOT N64: user_io_set_index(255); set_download(1); file_tx_data({0,0},2); set_download(0)
        - search for <root>/cheats/<CoreName>/*.zip whose entries match rom_path/crc
        - populate cheat menu

On user toggle in OSD:
  cheats_toggle()                                        [cheats.cpp:387-460]
        - lazy-load selected cheat file into cheats[i].cheatData
        - call cheats_send()

cheats_send():                                           [cheats.cpp:348-385]
  for each enabled cheat -> memcpy into buff
  loaded = pos / cheat_unit_size
  if N64: n64_cheats_send(buff, loaded)   [HPS-side patch via shmem(0x30000000)]
  else:    user_io_set_index(255);
           user_io_set_download(1);
           user_io_file_tx_data(buff, pos ? pos : 2);
           user_io_set_download(0);
```

Flow source: [V] for the index-255 convention (archive/github/MiSTer-devel/Main_MiSTer/cheats.cpp:137-197,348-385 @ 136737b4bed4); [O] for N64 deviation (archive/github/MiSTer-devel/Main_MiSTer/support/n64/n64.cpp:1411-1471 @ 136737b4bed4).

## 4. Sequencing & timing

§4 zooms in on the moments where the four flows interlock; for cycle-level `ioctl_*` waveforms see `21 §4.1` (download), `21 §4.2` (upload), and `22 §4` (mount block IO).

### 4.1 Composite ROM-load sequence (HPS view)

```
Time (HPS) ---->

user_io_file_tx() called
  |
  +--[A] user_io_set_index(idx)
  +--[B] user_io_file_info(ext)            -> ioctl_file_ext stable
  +--[C] user_io_set_download(1, size_or_0) -> ioctl_download <= 1
  |        \-- core: rising edge -> assert internal load-reset
  |
  +--[D] data phase
  |        |---- SPI-streaming: chunked file_tx_data() loop (per-word ioctl_wr)
  |        |---- OR direct-DDRAM: shmem_map + read() loop (no ioctl_wr)
  |
  +--[E] (snes/sgb only) snes_get_header / snes_get_mirrored_rom + header tx
  |
  +--[F] (if ss_base && opensave) process_ss(name)
  |        \-- shmem_map savestate region, force change-detector to 0xFFFFFFFF
  |
  +--[G] (if opensave) FileGenerateSavePath + user_io_file_mount(savefile, 0, 1)
  |        \-- core: img_mounted[0] pulses, latch img_size/img_readonly
  |
  +--[H] user_io_set_download(0)            -> ioctl_download <= 0
           \-- core: falling edge -> release load-reset, begin normal exec
```

The save-RAM mount [G] is intentionally inside the `ioctl_download==1` window, so the core can re-arm any "wait for save-RAM ready" handshake on the falling edge at [H]. [I]

### 4.2 Save-state DDRAM update cycle (core side)

```
clk_sys           |‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_
                     T0  T1  T2  T3  T4  T5  T6                T_last

user "save" cmd   ___/‾‾\__________________________________________________
internal sm       IDLE  WRITE_PAYLOAD........................... WRITE_HDR  DONE
DDRAM addr        ===payload bytes at base+8..======   base+4    base+0
DDRAM wdata       ===payload data===================  size_words new_cnt

T_last: write of base+0 (change detector) is THE LAST write.
        HPS process_ss() will read this value on its next 1000ms tick
        and, on a delta, flush (size+2)*4 bytes to .ss file.

If a write of base+0 ever races ahead of the payload/size, HPS may
flush a half-written state to disk (anti-pattern A.2).
```

### 4.3 Save-state restore (HPS view, at next core launch)

```
process_ss(rom_name) called inside user_io_file_tx [F]:
  for i in 0..3:
    base[i] = shmem_map(ss_base + i*ss_size, ss_size)
    memset(base[i], 0, ss_size)                  -> core sees zeroed slot
    fp = open(<rom>_<i+1>.ss)
    if fp open: read up to ss_size bytes into base[i]
                -> core sees its previously-persisted payload + header[1]=size
    ((uint32_t*)base[i])[0] = 0xFFFFFFFF         -> force first-write detect
                                                   on the next core update

ss_cnt[i] = 0xFFFFFFFF in HPS local state, so a subsequent change to
header[0] (by the core) is always a delta.
```

### 4.4 Upload-request poll cadence

```
core: dirty edge -> ioctl_upload_req <= 1 (1 clk_sys cycle min)
                           \-- hps_io: posedge clk_sys -> upload_req <= 1 (sticky)

user opens OSD ->  HPS begins polling opcode 0x3C (only while OSD active)
                           \-- on hit, hps_io: io_dout = {upload_index, 8'd1}; upload_req <= 0
HPS: read upload_index -> issue user_io_set_upload(1) for that bank
                           \-- ioctl_upload <= 1, ioctl_addr <= 0
                                ... per-word ioctl_rd pulses ...
                           \-- ioctl_upload <= 0
HPS: write buffer to .sav (or .nv etc.)
```

The OSD-only nature of the 0x3C poll is implicit (other commands in the same `casex` are also OSD-driven); cores with frequent save-RAM dirty events should still batch them across OSD opens. [I] (archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:328-339 @ f35083f3b40d)

## 5. Minimal working pattern

Two patterns. Both are **synthesized** from the contracts above and from `21 §5`; reference-core RTL is not in the snapshot, so they are marked `[I]`.

### 5.1 Routing ioctl-streamed ROM into an SDRAM write port

```verilog
// SYNTHESIZED — see archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:145-157,632-704 @ f35083f3b40d
// "Latch ioctl_addr/ioctl_dout into an SDRAM controller write port on each ioctl_wr."
// The SDRAM controller is assumed to have a write strobe (`rom_wr`), address bus (`rom_addr`),
// and data bus (`rom_din`), and to be busy-back-pressured via `rom_busy`.

wire        ioctl_download;
wire        ioctl_wr;
wire [26:0] ioctl_addr;
wire  [7:0] ioctl_dout;     // WIDE=0 byte mode
wire [15:0] ioctl_index;
reg         ioctl_wait;

wire is_rom_load = ioctl_download & (ioctl_index[5:0] == 6'd0);    // F0 / boot.rom

// SDRAM write-port wires (defined by your SDRAM controller; see 30-sdram.md)
reg  [24:0] rom_addr;
reg   [7:0] rom_din;
reg         rom_wr;
wire        rom_busy;

always @(posedge clk_sys) begin
    rom_wr <= 1'b0;
    if (is_rom_load && ioctl_wr) begin
        rom_addr <= ioctl_addr[24:0];   // truncate to your SDRAM map size
        rom_din  <= ioctl_dout;
        rom_wr   <= 1'b1;
    end
end

// Back-pressure: while the SDRAM controller is busy, hold off the next strobe.
assign ioctl_wait = rom_busy;

// Hold the core under load-reset while ioctl_download is active and one cycle after.
reg ioctl_download_d;
always @(posedge clk_sys) ioctl_download_d <= ioctl_download;
wire rom_load_active = ioctl_download | ioctl_download_d;
```

### 5.2 Save-state register-file write to the DDRAM control header

```verilog
// SYNTHESIZED — see archive/github/MiSTer-devel/MkDocs_MiSTer/docs/developer/savestates.md:13-21 @ 9033bd292fdc
// "Sequence a savestate write so the change detector is updated LAST."
// Assumes ddram_wr_addr / ddram_wr_data / ddram_wr go to the DDRAM controller's write port.
// `ss_slot_base` is `ss_base + slot * ss_size` (computed at core-start from the SS<...> CONF_STR fields,
// or hardcoded if the core uses a fixed layout).

reg  [2:0] ss_state;
reg [31:0] payload_addr;
reg [31:0] ss_size_words;          // count of 32b words excluding header
reg [31:0] ss_change_cnt;          // monotonically increases on each save

localparam SS_IDLE        = 3'd0;
localparam SS_WRITE_PAY   = 3'd1;
localparam SS_WRITE_SIZE  = 3'd2;
localparam SS_WRITE_CNT   = 3'd3;
localparam SS_DONE        = 3'd4;

always @(posedge clk_sys) begin
    ddram_wr <= 1'b0;
    case (ss_state)
      SS_WRITE_PAY: begin
          // Stream each 4-byte word of the snapshot to ss_slot_base + 8 + offs.
          // When the final payload word has been written, advance.
          if (payload_done) ss_state <= SS_WRITE_SIZE;
      end
      SS_WRITE_SIZE: begin
          ddram_wr_addr <= ss_slot_base + 32'd4;
          ddram_wr_data <= ss_size_words;
          ddram_wr      <= 1'b1;
          ss_state      <= SS_WRITE_CNT;
      end
      SS_WRITE_CNT: begin
          // CRITICAL ORDER: change detector LAST, after the size word has committed.
          ddram_wr_addr <= ss_slot_base + 32'd0;
          ddram_wr_data <= ss_change_cnt + 32'd1;
          ddram_wr      <= 1'b1;
          ss_change_cnt <= ss_change_cnt + 32'd1;
          ss_state      <= SS_DONE;
      end
    endcase
end
```

The HPS-side polling loop reads `[31:0]` (the change detector); on a delta it flushes `(size_words + 2) * 4` bytes to the `.ss` file. Cite `user_io.cpp:1971-2008` and `savestates.md` for the contract. [C]

## 6. Common variations across cores

[deferred — reference cores not fetched]

Per the brief, no per-core RTL is in the snapshot. The framework-side HPS code does, however, distinguish several cases by core identity (`is_snes()`, `is_n64()`, `is_megacd()`, `is_c64()`, `is_psx()`, etc.). The following variations are observable from `Main_MiSTer/user_io.cpp`, `cheats.cpp`, and the per-system `support/<sys>/*.cpp` files and are labeled `[O]`. RTL-side equivalents await reference-core retrieval and are `[I]`.

### 6.1 ROM-load classes

- **Single linear ROM, SPI-streaming**: `Template_MiSTer`-style cores. F-slot with no `load_addr` → entire file delivered via `ioctl_wr` to a core-local write port. [I]
- **Single linear ROM, direct-DDRAM**: large-ROM cores (e.g. SNES, GBA path) declare `F0,...,<load_addr>` with `load_addr` in `[0x20000000, 0x40000000)`. HPS bypasses SPI for the data phase and writes directly into the DDRAM map. Core sees `ioctl_download` level only. [C] (archive/github/MiSTer-devel/Main_MiSTer/user_io.cpp:2818-2840 @ 136737b4bed4)
- **Composite header + ROM (SNES `SNES_FILE_*`)**: SNES dispatches on extension; for `.SMC`/`.SFC`/`.BIN` it pre-pends a 512-byte synthesized header before the ROM data, then sends the mirrored ROM in 4 KB chunks; `.BS` and `.SPC` use bespoke pre-roll sequences. [O] (archive/github/MiSTer-devel/Main_MiSTer/user_io.cpp:2682-2773 @ 136737b4bed4; archive/github/MiSTer-devel/Main_MiSTer/support/snes/snes.cpp:420-467 @ 136737b4bed4)
- **Multi-part MRA arcade**: MRA loader walks an XML manifest and issues many small `user_io_file_tx_a`-style transfers under one composite "load" event; per-part `ioctl_index` and pre-computed offsets demux the sub-files. RTL side: a single `ioctl_download` window may not exist — see [52-mra-and-arcade.md] (out of this doc's scope) for the MRA loader semantics. [I]
- **Multi-file mount-driven cores (megacd, pcecd, psx)**: ROM stream is replaced by a series of `mcd_load_rom`/`pcecd_load_rom` style calls (each one its own `user_io_file_tx` with a sub-index `<i> << 6`) plus an S-slot CD image mount; the CD image is streamed lazily via the mount channel. [O] (archive/github/MiSTer-devel/Main_MiSTer/support/megacd/megacd.cpp:105-117,160-176 @ 136737b4bed4; archive/github/MiSTer-devel/Main_MiSTer/user_io.cpp:968-987 @ 136737b4bed4)

### 6.2 Save-RAM classes

- **S0 mount-channel saves (default)**: most cores. `opensave=1` → `.sav` mounted on S0. [I]
- **Upload-request NVRAM/cart saves**: cores with `ioctl_upload_req` (NES PRG-RAM, GBA SRAM, etc.). Save bytes round-trip via `ioctl_din`/`ioctl_rd`; HPS picks up via opcode `0x3C`. [I] (archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:289-290,335 @ f35083f3b40d)
- **`UIO_CHK_UPLOAD` polled saves (C64/C128 EasyFlash)**: HPS calls `spi_uio_cmd(UIO_CHK_UPLOAD)` from `user_io_poll`; on a non-zero reply, the core executes a save-back via `user_io_file_rx_data` against `ioctl_index = 99`. [O] (archive/github/MiSTer-devel/Main_MiSTer/user_io.cpp:3745-3749 @ 136737b4bed4; archive/github/MiSTer-devel/Main_MiSTer/support/c64/c64.cpp:1127-1161 @ 136737b4bed4)
- **MegaCD "fake-download" save trigger**: `mcd_mount_save` wraps the actual `user_io_file_mount` in a `user_io_set_index(5)` + `set_download(1)` ... `set_download(0)` envelope. The download signals on `ioctl_index == 5` are a *side-channel* to inform the core that the save-RAM mount has changed, not a data transfer. [O] (archive/github/MiSTer-devel/Main_MiSTer/support/megacd/megacd.cpp:89-103 @ 136737b4bed4)

### 6.3 Save-state classes

- **No save-state**: core omits `SS<base>:<size>` from `CONF_STR`; `ss_base == 0` and `process_ss` is a no-op. [C] (archive/github/MiSTer-devel/Main_MiSTer/user_io.cpp:1911 @ 136737b4bed4)
- **Explicit `SS` declaration**: cores parse `SS<base>:<size>` and lay out their own DDRAM-resident savestate region of `4 * ss_size` bytes. [C] (archive/github/MiSTer-devel/Main_MiSTer/user_io.cpp:703-727 @ 136737b4bed4)
- **GBA implicit default**: GBA gets `ss_base = 0x3E000000, ss_size = 0x100000` even without `SS` in `CONF_STR` — likely because GBA's `CONF_STR` predates the `SS` token and is special-cased in the HPS. [O] (archive/github/MiSTer-devel/Main_MiSTer/user_io.cpp:1053-1056 @ 136737b4bed4)

### 6.4 Cheat classes

- **SPI-delivered cheats (default)**: every supported core except N64 receives the cheat blob on `ioctl_index == 255` via the SPI-streaming download path. [V] (archive/github/MiSTer-devel/Main_MiSTer/cheats.cpp:378-385 @ 136737b4bed4)
- **HPS-resident N64 cheat engine**: `n64_cheats_send` stores the blob in HPS memory; `n64_poll` runs the cheat opcodes against `shmem_map(0x30000000, RAM_SIZE)` to patch RDRAM directly. The core never sees a cheat blob via ioctl. [O] (archive/github/MiSTer-devel/Main_MiSTer/cheats.cpp:374-377 @ 136737b4bed4; archive/github/MiSTer-devel/Main_MiSTer/support/n64/n64.cpp:1411-1471 @ 136737b4bed4)
- **Arcade MRA-driven cheats**: built up from MRA via `cheats_add_arcade` and finalized with `cheats_finalize_arcade`; delivery is still the SPI-streaming path. [O] (archive/github/MiSTer-devel/Main_MiSTer/cheats.cpp:99-134 @ 136737b4bed4)
- **No-cheat cores**: no cheat zip under `<root>/cheats/<CoreName>/`; `cheats_init` returns early but still resets the core's cheat blob to a 2-byte zero download. [V] (archive/github/MiSTer-devel/Main_MiSTer/cheats.cpp:146-152,168-172 @ 136737b4bed4)

### 6.5 Per-core RTL variation table (deferred)

| Concern | Single-ROM core (e.g. NES) | Direct-DDRAM core (e.g. SNES) | Multi-part MRA core | Save-state core (e.g. SNES, GBA) | Cheat-supporting core |
| --- | --- | --- | --- | --- | --- |
| `ioctl_wr` accept path | Yes — SDRAM write | No — DDRAM written off-FPGA | Yes per sub-file | n/a | Yes — at `ioctl_index==255` |
| `ioctl_download` role | Window for ROM data | Window for "rom_loading" reset only | One window per part, or one composite | n/a | Same |
| `ioctl_upload` role | Optional (save-RAM) | Optional (save-RAM) | Optional | n/a | Unused |
| `ioctl_upload_req` source | NVRAM dirty | NVRAM dirty | NVRAM dirty | n/a | Unused |
| DDRAM map region | None (or save-RAM mirror) | ROM image + save mirror | Per-part placement | `[ss_base, ss_base + 4*ss_size)` | n/a |
| Mount slot S0 | `.sav` (if `opensave`) | `.sav` (if `opensave`) | n/a (loader uses index sub-files) | `.sav` (if also save-RAM) | n/a |

All cells marked above are inferred from the HPS-side flow; per-core RTL has not been verified against an archived source tree. [I]

## 7. Anti-patterns

### A.1 Latching ROM data without honoring `ioctl_wait`

- **Symptom:** Random bytes missing from the ROM image when SDRAM is busy (refresh cycles, contention with display fetch). CRC mismatch on the core side vs. HPS-reported file_crc.
- **Cause:** The core's write target is not always ready in the same cycle `ioctl_wr` pulses. `ioctl_wr` is a single `clk_sys` pulse; the next strobe arrives whenever the HPS sends the next byte over SPI, which may be before the SDRAM controller has accepted the previous write.
- **Fix:** Drive `ioctl_wait` high while the write target is busy. The framework gates `io_strobe` inside `sys_top.v:259` whenever `ioctl_wait` is asserted on `HPS_BUS[37]`. For controllers that can always accept one byte per `clk_sys`, tie `ioctl_wait = 1'b0`.
- **Citation:** `archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:191,632-634 @ f35083f3b40d`; `archive/github/MiSTer-devel/Main_MiSTer/user_io.cpp:2040-2046 @ 136737b4bed4`

### A.2 Bumping the save-state change detector before the payload commits

- **Symptom:** Save-states reload as corrupted memory; OSD says "Saving" right after a save command, but the resulting `.ss` contains stale or partial data.
- **Cause:** The HPS polls `*(uint32_t*)base[i]` (the change detector) on a ~1 s cadence and flushes the slot on a delta. If the RTL state machine writes the change detector before all payload + size words have actually landed in DDRAM, the flush captures an incomplete state.
- **Fix:** Order writes payload → size word (`base+4`) → change detector (`base+0`). If the DDRAM controller reorders writes, insert an explicit drain/fence before bumping the detector.
- **Citation:** `archive/github/MiSTer-devel/Main_MiSTer/user_io.cpp:1971-2008 @ 136737b4bed4`; `archive/github/MiSTer-devel/MkDocs_MiSTer/docs/developer/savestates.md:13-21 @ 9033bd292fdc`

### A.3 Releasing the core from reset before `ioctl_download` falls

- **Symptom:** Core boots into a partial ROM, dies inside the loader, or — on the direct-DDRAM path — fetches uninitialized DDRAM as code.
- **Cause:** ROM data is not guaranteed present in the core's memory until the HPS has finished its data phase. On the SPI-streaming path the last `ioctl_wr` pulse may lag the call site that triggered the load; on the direct-DDRAM path, the HPS's `shmem_map`+`read()` loop runs entirely between rising and falling edges of `ioctl_download` with no per-byte signaling.
- **Fix:** Use `ioctl_download` as a level-true load-reset. Latch a one-cycle-delayed copy and only release internal reset on the falling edge of either. Apply this for both SPI and direct-DDRAM paths.
- **Citation:** `archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:638,676-680 @ f35083f3b40d`; `archive/github/MiSTer-devel/Main_MiSTer/user_io.cpp:2818-2840,2880 @ 136737b4bed4`

### A.4 Reusing `ioctl_index == 255` for a non-cheat purpose

- **Symptom:** Cheats reset the wrong region; or vice versa — toggling a cheat overwrites part of the core's NVRAM.
- **Cause:** Index 255 is the framework convention for the cheat blob; `cheats_init` issues a 2-byte zero download against it at every ROM open, and `cheats_send` re-issues the full enabled blob on every toggle. A core's own custom slot at 255 will be silently clobbered by `cheats_init` even before the user enables any cheat.
- **Fix:** Reserve `ioctl_index == 255` for cheats. If the core does not support cheats, simply ignore `ioctl_download` when `ioctl_index == 255`. Use a different F-slot index for any custom payload.
- **Citation:** `archive/github/MiSTer-devel/Main_MiSTer/cheats.cpp:147-152,378-385 @ 136737b4bed4`

### A.5 Treating "save-RAM upload" as HPS-driven

- **Symptom:** Save-RAM never reaches disk despite the OSD save command; or the core repeatedly transmits the same save bytes without HPS ever picking them up.
- **Cause:** `ioctl_upload_req` is **core-driven, not HPS-driven**. The HPS does not initiate uploads unprompted — it polls opcode `0x3C` while the OSD is open and only starts an upload after a latched rising-edge of `ioctl_upload_req`. A core that waits for `ioctl_upload` to rise before signaling dirty save data will deadlock.
- **Fix:** Pulse `ioctl_upload_req` (≥1 `clk_sys` cycle) whenever save-RAM transitions from clean to dirty, and present the save bank id on `ioctl_upload_index`. The HPS reads both via opcode `0x3C` on the next OSD open; subsequently `ioctl_upload` rises and the core serves `ioctl_din` indexed by `ioctl_addr`.
- **Citation:** `archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:151-155,289-290,335 @ f35083f3b40d`

### A.6 Treating "slot is occupied" as "change detector is non-FFFFFFFF"

- **Symptom:** Core attempts to restore from a slot that the user never saved into; payload is all zeros and the core deserializes garbage.
- **Cause:** `process_ss(rom_name)` zero-fills each slot via `memset(base[i], 0, len)` and then sets the change detector to `0xFFFFFFFF`. If the matching `<rom>_<i+1>.ss` file does not exist, the slot's size word stays at zero and the payload is all zeros, but the change detector is `0xFFFFFFFF` — not zero. A core that gates "this slot has a payload" only on the change detector will incorrectly conclude an empty slot is restorable. (Note: the `savestates.md` note saying "otherwise will contain random data" is outdated; the current code zero-fills.)
- **Fix:** Key "slot has data" off `header[1] != 0` (size word non-zero). The size word is loaded from the on-disk file when the slot was previously saved; for empty slots it remains zero after the memset.
- **Citation:** `archive/github/MiSTer-devel/Main_MiSTer/user_io.cpp:1923-1944 @ 136737b4bed4`; `archive/github/MiSTer-devel/MkDocs_MiSTer/docs/developer/savestates.md:23-27 @ 9033bd292fdc`

## 8. Verification

- **ROM round-trip:** load a small known ROM via an F-slot, then have the core compute CRC32 over its accepted bytes and surface the result via a status bit; compare to the `CRC32: %08X` printed by `user_io_file_tx` at end-of-load. (archive/github/MiSTer-devel/Main_MiSTer/user_io.cpp:2867 @ 136737b4bed4)
- **Direct-DDRAM bring-up:** declare an F-slot with a hex load_addr in `[0x20000000, 0x40000000)`, watch the HPS console for `Load to address 0x...` and confirm there are *no* `FIO_FILE_TX_DAT` strobes on the SPI logic analyzer. Core CRC must match the on-disk file (read from DDRAM after the falling edge). (archive/github/MiSTer-devel/Main_MiSTer/user_io.cpp:2662,2818-2840 @ 136737b4bed4)
- **Save-RAM via mount:** load a ROM with `opensave=1`, write data through the core to the S0 mount, exit the core, re-launch, and confirm the `.sav` file persists (`/media/fat/saves/<Core>/<basename>.sav`). Block-IO traffic detail in `22-hps-io-mount-and-sd.md`. (archive/github/MiSTer-devel/Main_MiSTer/user_io.cpp:2873-2877 @ 136737b4bed4)
- **Save-RAM via upload-req:** in simulation, pulse `ioctl_upload_req`, drive `ioctl_upload_index = 8'h00`, open the OSD, and confirm a `cmd 0x3C` packet on the SPI returns `{0x00, 0x01}`. Then issue the upload sequence from the HPS side (`user_io_set_upload(1)` ... `user_io_set_upload(0)`) and check that `ioctl_rd` pulses on each word. (archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv:289-290,335,696-698 @ f35083f3b40d; archive/github/MiSTer-devel/Main_MiSTer/user_io.cpp:2048-2067 @ 136737b4bed4)
- **Savestate end-to-end:** declare `SS3E000000:1000` (or core-appropriate values), implement payload+size+change-detector write order on the core side, save state through OSD, exit core, re-launch ROM, observe the previously-persisted slot contents in DDRAM after `process_ss` initialization. HPS console prints `process_ss: read N bytes from file: ...`. (archive/github/MiSTer-devel/Main_MiSTer/user_io.cpp:1953-1955 @ 136737b4bed4)
- **Cheats:** enable a known cheat in the OSD; on the core side, verify a write transaction with `ioctl_index == 255` and the expected payload length (`enabled_count * cheat_unit_size`). Toggle the cheat off and verify a second transaction with a smaller (or zero-length 2-byte) payload. (archive/github/MiSTer-devel/Main_MiSTer/cheats.cpp:348-385 @ 136737b4bed4)
- **N64 cheat regression:** confirm that on N64 *no* `ioctl_index == 255` traffic occurs and the cheat patch instead lands in RDRAM via `shmem_map(0x30000000, ...)`. (archive/github/MiSTer-devel/Main_MiSTer/support/n64/n64.cpp:1411-1471 @ 136737b4bed4)
- **MiSTer.ini knobs:** these flows are not influenced by `direct_video`, `vrr_mode`, `vga_scaler`, or `forced_scandoubler`; flow-level symptoms usually trace to `CONF_STR` (extension routing, `SS` range, `F`/`S` slot grammar) — see [11-conf-str.md](11-conf-str.md) and `21 §8`.

## 9. Provenance footer

- `archive/github/MiSTer-devel/Main_MiSTer/user_io.cpp @ 136737b4bed4` — `user_io_file_tx` (ROM loader, SPI-streaming + direct-DDRAM), `user_io_file_mount` (save-RAM mount), `process_ss` (savestate setup + polling), `parse_config` (`SS`/`F<i>,<load_addr>` parsing), `user_io_poll` (`UIO_CHK_UPLOAD`, `process_ss(0)`); used for §2, §3, §4, §6, §7, §8.
- `archive/github/MiSTer-devel/Main_MiSTer/user_io.h @ 136737b4bed4` — `UIO_CHK_UPLOAD` constant, `process_ss`/`user_io_file_tx` prototypes; used for §2.2, §6.2.
- `archive/github/MiSTer-devel/Main_MiSTer/file_io.cpp @ 136737b4bed4` — `FileSave`/`FileLoad`, `FileGenerateSavePath`, `FileGenerateSavestatePath`; used for §2.2, §2.3, §3.4.
- `archive/github/MiSTer-devel/Main_MiSTer/cheats.cpp @ 136737b4bed4` — `cheats_init`, `cheats_send`, `cheats_toggle`, `cheats_init_arcade`, `CHEAT_SIZE`, index 255 convention; used for §2.4, §3.7, §6.4, §7 (A.4), §8.
- `archive/github/MiSTer-devel/Main_MiSTer/cheats.h @ 136737b4bed4` — cheats public API surface; used for §2.4.
- `archive/github/MiSTer-devel/Template_MiSTer/sys/hps_io.sv @ f35083f3b40d` — `ioctl_*` port block, FIO state machine, `upload_req` rising-edge latch and `0x3C` reply; used for §2.1, §2.2, §3.5, §4.4, §7 (A.1, A.5).
- `archive/github/MiSTer-devel/Template_MiSTer/sys/sys_top.v @ f35083f3b40d` — `io_wait` strobe gate at line 259; used for §2.1, §7 (A.1).
- `archive/github/MiSTer-devel/MkDocs_MiSTer/docs/developer/savestates.md @ 9033bd292fdc` — change-detector / size-word contract, four-slot rule, on-disk format; used for §2.3, §5.2, §7 (A.2, A.6).
- `archive/github/MiSTer-devel/Main_MiSTer/support/snes/snes.cpp @ 136737b4bed4` — `snes_get_mirrored_rom` (mirroring padding before SPI tx), MSU bus around `user_io_set_index(idx)+set_download(1)`; used for §6.1.
- `archive/github/MiSTer-devel/Main_MiSTer/support/megacd/megacd.cpp @ 136737b4bed4` — `mcd_mount_save` fake-download index 5, `mcd_load_rom` sub-file ROM transfers; used for §6.1, §6.2.
- `archive/github/MiSTer-devel/Main_MiSTer/support/n64/n64.cpp @ 136737b4bed4` — `n64_cheats_send` HPS-side cheat engine via `shmem_map(0x30000000)`; used for §2.4, §6.4, §8.
- `archive/github/MiSTer-devel/Main_MiSTer/support/c64/c64.cpp @ 136737b4bed4` — `c64_save_cart` (EasyFlash polled-upload variant using `UIO_CHK_UPLOAD` + `user_io_set_upload(1)` + `ioctl_index = 99`); used for §6.2.
