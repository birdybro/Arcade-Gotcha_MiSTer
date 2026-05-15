# Gotcha port roadmap

Path from current state (chip-level sync gen, blank 240p signal) to a fully playable Atari Gotcha MiSTer core. Reference netlist: `docs/DICE/games/gotcha.cpp`.

---

## 📍 Resume here — Phase 4 (Coin) written, awaiting hardware verification

**What changed in this commit:**
- New primitives:
  - `rtl/chips/ttl_9602.sv` — dual retriggerable monostable (parameterized pulse widths in clk_sys cycles).  B7 instance: half A = 7.3ms (coin debounce), half B = 728ms (catch one-shot).
  - `rtl/chips/ttl_latch.sv` — DICE's power-on SR latch: pin3 starts LOW, transitions HIGH after ~1µs (32 clk_sys cycles), then active-low SR.  See docs/DICE/chips/latch.cpp for reference.
- `rtl/gotcha.sv`: replaced ATTRACT_n / START / START_n / CATCHOS_n Phase 2 stubs with real signals.  Added 6 chip instances (u_B7 9602, u_K7/u_B6/u_C6/u_C7 7474, u_LATCH).  Re-wired u_D7 inv 1/5/6, u_D6 gates 3/4, u_J5 inv 6.  Added COIN1/START1 input ports to the gotcha module.
- `Arcade-Gotcha.sv`: added OSD entries `T[1],Coin;` and `T[2],Start;`.  COIN1 = ~status[1], START1 = ~status[2] (active-low convention).

**Hardware test 1 (pre-stretcher build) showed timer stuck at 00** — the OSD T-trigger pulse is too brief for B7's 7.3ms debounce, so K7.Q1 never latches and the /PR2=Q=0 path holds ATTRACT permanently HIGH.  Fixed by adding 50ms pulse stretchers for COIN1 and START1 in `Arcade-Gotcha.sv`.

**To verify on hardware:**
1. Compile, load the `.rbf`.
2. Expected boot state: ATTRACT mode active (= 1), play timer frozen, demo-like display.  Open the OSD and click "Coin" — should debounce ~7ms then count one credit.  Click "Start" — ATTRACT should drop to 0, play-timer starts counting up at 1 Hz.  After ~99 seconds the timer rolls over and ATTRACT resumes.
3. Possible failure modes:
   - **Play timer running immediately** → ATTRACT didn't initialize to 1.  Check that `LATCH_pin3` is initialized correctly and that C7 FF2's /PR2=Q goes 0 after the 32-cycle init.  Probe `Q` and `ATTRACT` signals.
   - **Coin click does nothing** → COIN1 not inverted, or B7 half A not firing.  Verify `~status[1]` is fed to COIN1 in emu.sv and that B7's PULSE_A_CYCLES parameter is correct.
   - **Start click does nothing** → B6 FF2 not seeing the rising edge of START1, or COIN_n not asserted to release B6./CLR1.  Check that coin was clicked first (B6 FF1 needs COIN_n=0 briefly to release).
   - **ATTRACT never resumes** → C7 FF2's CK2 = ~L8.QD might not be firing.  Check L8 counter is actually advancing and D7 inv 5 produces the inverted pulse.

**Clock change (post Phase 4):** clk_sys bumped from 14.318 MHz → 28.636 MHz (2×) so the HDMI scaler gets more cycles per pixel.  CE_PIXEL is now CLK_VIDEO/4.  The real 14.318 MHz CLOCK net is recreated as `CLOCK_14M = clk_sys/2` inside gotcha.sv and fed to J6.CP1; the old `CP1_IS_CLK_SYS` ttl_74107 hack was removed.  PLL output, D8 divider, B7 pulse widths, and emu.sv button stretchers were all rescaled for 28.636 MHz.  Confirmed on hardware: HDMI flicker + startup corruption mostly gone.

**Sliver-artifact fix (post clock change):** the self-cascaded `ttl_7493` counters modeled the QA→CKB ripple as a chained per-stage edge detector, adding a 1-clk_sys lag between QA and QB/QC/QD — a wrong counter value sampled on ~every other pixel ("sliver wraparound" on all graphics).  Fixed by adding a `SELF_CASCADE` parameter to `ttl_7493` that models the self-cascaded chip as one atomic 4-bit synchronous counter; set on all four instances (L6, M6, H5, F5).  This fixed it on HDMI but a residual horizontal shift still showed on the sharper analog path — the *inter-nibble* lag (M6 detecting L6.QD a cycle late, J6.FF2 detecting M6.QD another cycle late).

**Inter-nibble fix (synchronous H counter):** `ttl_7493` SELF_CASCADE mode now repurposes `pin1` (CKB) as a synchronous count-enable.  The H counter is now a true synchronous-carry chain: L6, M6 and J6.FF2 all clock on the root `CLK`; M6's count-enable = `L6_tc` (= H1&H2&H4&H8), and J6.FF2's J2/K2 = `H_carry256` (= L6_tc & M6_tc) with CP2 = CLK.  The whole 9-bit H counter now updates atomically on one clk_sys edge.  The V counter (H5/F5/D5.FF1) was left on the simple ripple cascade — its inter-nibble settling happens during the H-reset window (HBLANK) and is never sampled in the visible region.

**M4 decoration flicker fix:** `u_K5` gate 3 pin9 was wired to `B4_Q1_n` (B4 FF1's /Q1) but gotcha.cpp:605 (`CONNECTION("B4", 6,"K5", 9)`) calls for B4 pin 6 = FF2's **/Q2**.  B4 FF1 is part of the V256-clocked B5/B4 frame-rate state machine, so the miswiring injected a frame-parity term into `K5_g3` → M4 → the score-area decoration flipped every frame ("flicker like crazy", visible on analog CRT too, absent in the DICE reference).  B4 FF2's /Q2 is frame-deterministic (playfield FF), so with the correct wiring M4 only evolves via the slow C4/D4 free-run = the smooth ever-changing-maze DICE shows.  Exposed `B4_Q2_n` (u_B4 pin6, previously left unconnected) and rewired `u_K5.pin9` to it.

**Remaining stubs:**
- A10.pin8 = VCC.  B7 half B's TRIG2 input — A10 is in /* Sound */ (Phase 5+).  With this stub, B7 half B's TRIG = START | ~VCC = START — so CATCHOS pulses fire on every START rising edge instead of when A10 triggers them.  Functional enough to verify; will be replaced when /* Sound */ lands.
- D8 still modeled inline as a 25-bit clk_sys divider.

**Next session pick-up: Phase 5+** options:
1. **/* Right Control */ + /* Right Counters */** (lines 697-884): right player joystick movement, position counters, BUMP1, CATCH detect.  Needs joystick input wiring in emu.sv (hps_io's `joystick_0`) and probably a `ttl_555_mono` primitive (B8/C8).
2. **/* Left Control */ + /* Left Counters */** (lines 885-1054): mirror of right player.
3. **/* Sound */** (lines ~1055-end): A10, M4 (chip), M2, D2, J2, K10 — completes the CATCHOS trigger path.

---

## Phase 0 — Sync generator ✓ DONE

H/V counter + HBlank/VBlank/HSync/VSync. Blank-but-valid 240p signal on HDMI.

- Chips instantiated: J6, L6, M6, K6, H4 (gate 1), H6, H5, F5, D5 (FF1), M5 (gates 1-3), F6 (gates 2-3), J5 (gate 2), L5 (gate 2), J4 (gate 4), F4 (FF1).
- Primitives: ttl_7400, ttl_7402, ttl_7404, ttl_7408, ttl_7410, ttl_7430, ttl_7474, ttl_7493, ttl_74107.
- gotcha.cpp lines translated: 326-411.

## Phase 1 — Playfield (maze + border visible) ✓ DONE

Ports `/* Playfield */` (gotcha.cpp lines 456-501). First visible content on screen.

- **New primitives:** ttl_7427 (triple 3-input NOR), ttl_7486 (quad XOR).
- **New chip instances:** u_D6 (7400), u_E6 (7427), u_K5 (7486), u_K4 (7402), u_C5 (7400), u_B4 (74107), u_E4 (7400), u_H8 (7404).
- **Un-stub existing chip gates:** M5 gate 4, J5 gates 4/5, F4 FF2, D5 FF2.
- **Temporary video routing:** route the maze pattern (C5.pin6) directly to the `video` output, since the full F8 NAND combiner depends on Phase 2's score chain.

## Phase 2 — Score + play timer ✓ DONE

Ports `/* Play timer */` (502-534), `/* Playfield mux */` (535-562), `/* Playfield mux part 2 */` (607-695). Adds visible countdown timer and score digits.

## Phase 3 — M4 signal ✓ DONE

Ports `/* M4 */` (568-606).  Replaces the M4=GND stub with the real cross-coupled B4/B5 + cascaded C4/D4 9316 counter chain.  New primitive: ttl_9316.

## Phase 4 — Coin + game state ✓ DONE (awaiting hardware verification)

Ports `/* Coin */` (412-455).  Replaces ATTRACT_n / START / START_n / CATCHOS_n stubs.  New primitives: ttl_9602 (dual one-shot, parameterized pulse widths), ttl_latch (DICE power-on SR latch).  Adds OSD entries for Coin and Start.

- **New primitives:** ttl_9316 (real synchronous counter, distinct from the 7493-wired L6/M6), ttl_7490 (decade counter), ttl_7448 (BCD-to-7-seg), ttl_9602 (dual monostable), ttl_74153 (dual 4-to-1 mux), ttl_74157 (quad 2-to-1 mux).
- **New chip instances:** K8/L8/G8 (7490 play timer chain), J7 (7448 7-seg decoder), J8 (74107), L7/M7 (74153 score muxes), I7 (74157), plus the F8/F7/E7/H7/H8 NAND chain that finally drives the picture.
- **Replace the Phase 1 maze-only video** with the full F8 NAND chain combining maze + score segments per gotcha.cpp lines 1072-1078.

## Phase 3 — Players + joystick input

Ports `/* Right Control */` (697-799), `/* Right counters */` (800-883), `/* Left control */` (885-953), `/* Left counters */` (955-1070), `/* M4 */` (568-606), `/* M1,M3 */` (563-567).

- **New primitives:** ttl_7420 (dual 4-input NAND).
- **New chip instances:** A1 (7402), B2/B3/C2/C3/F2/L2/L3/M2/M3 (7474), D2/K2 (7486), D3/M1 (7402), E1/E2/E4 (7400), B5/J2 (74107), H1 (7404), H2 (7420), E3/F3/J3/H3/G1/D1/L1/K1 (real 9316), M4 (7400), XY (7410), F1 (7402, gates 1/2 for VIDEO1/VIDEO2).
- **Wire P1/P2 joystick inputs** from `hps_io` into the netlist at DICE's JOYSTICK1/2_INPUT positions (lines 717-720, 901-904).
- Player movement, wall collision, bump logic operational. Cross and Square sprites visible and steerable.

## Phase 4 — Coin / Start / catch / attract mode

Ports `/* Coin */` (412-455) and the catch-detection chain (B7 9602, K7 7474, K10 555-mono, A10 7400, BUF1, J10 7400).

- **New primitives:** custom BUFFER (with delay), reuse ttl_9602 from Phase 2.
- **Wire COIN1, START1 inputs** from `hps_io` (status[] bits or button[]).
- Attract mode, coin lockout, catch-os detection, play-timer triggers fully working. Game has a proper round-by-round loop.

## Phase 5 — Full video composition + sound

- Replace Phase 1's temporary maze-direct video with the canonical 3-channel output from `gotcha.cpp` lines 1072-1078: VIDEO pin 1 = F6.pin13 (border/HBLANK gate), pin 2 = F1.pin1 = VIDEO1 (right player), pin 3 = F1.pin4 = VIDEO2 (left player).
- Port `/* Sound */` (1081-1111). Needs analog-flavor models: ttl_555_astable, ttl_555_mono, the custom PROXIMITY block (capacitor RC charging — discretize for FPGA with a simple low-pass + threshold), and the audio mixers.
- Route audio into MiSTer's AUDIO_L/R via Arcade-Gotcha.sv.

## Phase 6 — Polish

- DIP switch / OSD options: play time (POT1 in gotcha.cpp), free play if present.
- If timing slack is tight, tune PLL VCO settings.
- Verify on real DE10-Nano hardware. Capture release .rbf into `releases/<corename>_YYYYMMDD.rbf`.

---

**Current task list (in-flight):** see Claude's TaskList tool — phases above get broken into atomic tasks during execution.
