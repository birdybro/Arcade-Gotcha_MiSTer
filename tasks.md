# Gotcha port roadmap

Path from current state (chip-level sync gen, blank 240p signal) to a fully playable Atari Gotcha MiSTer core. Reference netlist: `docs/DICE/games/gotcha.cpp`.

---

## 📍 Resume here — 2026-05-12 evening

**Last commit:** `fdab336` (Phase 1: playfield maze + border).

**To verify on hardware before continuing:**
1. Open `Arcade-Gotcha.qpf` in Quartus 17.0.2, compile (Processing → Start Compilation), and load the resulting `.rbf` onto the DE10-Nano (or use jtag.cdf via USB blaster).
2. Watch HDMI output for the Gotcha **maze grid + border pattern** in white on black. The pattern should be stable per-frame; shape comes from C5.pin6 in `rtl/gotcha.sv` (= `C5_g2` net, "MAZE INK").
3. Possible failure modes worth noting before reporting:
   - **Totally black screen** → playfield chain not producing any active signal. Likely cause: `F4_Q2_w` never sets (V64 edge detection issue) or `B4_Q2` stuck. Probe these signals via SignalTap or temporary VGA channel split.
   - **Solid white screen** → reset stuck low, or polarity inverted somewhere. Check `H6_Q1`/`H6_Q2` reset latches still produce correct H/V counter wrap behavior.
   - **Pattern flickers/jitters** → likely an edge-detect race in `ttl_74107` D5 FF2 or B4 FF2 (CP2 timing). Compare with gotcha.cpp's POS_EDGE vs NEG_EDGE behavior.
   - **Wrong shape but stable** → translation bug in one of the chip instantiations. Diff `rtl/gotcha.sv` chip-by-chip against gotcha.cpp lines 456-501.
4. Sync gen (Phase 0) was already verified to produce valid 240p. If Phase 1 broke that (screen rolls or no signal at all), the regression is most likely in the modified `u_M5`, `u_J5`, `u_F4`, or `u_D5` instantiations.

**Next session pick-up:**
- If Phase 1 looks good → start **Phase 2** (score + play timer). First step: write `rtl/chips/ttl_9316.sv` (real synchronous counter, distinct from the 7493-wired L6/M6), then `ttl_7490`, `ttl_7448`, `ttl_9602`, `ttl_74153`, `ttl_74157`.
- If Phase 1 needs fixing → start by isolating which signal in the playfield chain is broken (suggest splitting video into R/G/B with different signals like `C5_g1`, `C5_g3`, `C5_g2` to see which subchain works).

---

## Phase 0 — Sync generator ✓ DONE

H/V counter + HBlank/VBlank/HSync/VSync. Blank-but-valid 240p signal on HDMI.

- Chips instantiated: J6, L6, M6, K6, H4 (gate 1), H6, H5, F5, D5 (FF1), M5 (gates 1-3), F6 (gates 2-3), J5 (gate 2), L5 (gate 2), J4 (gate 4), F4 (FF1).
- Primitives: ttl_7400, ttl_7402, ttl_7404, ttl_7408, ttl_7410, ttl_7430, ttl_7474, ttl_7493, ttl_74107.
- gotcha.cpp lines translated: 326-411.

## Phase 1 — Playfield (maze + border visible)

Ports `/* Playfield */` (gotcha.cpp lines 456-501). First visible content on screen.

- **New primitives:** ttl_7427 (triple 3-input NOR), ttl_7486 (quad XOR).
- **New chip instances:** u_D6 (7400), u_E6 (7427), u_K5 (7486), u_K4 (7402), u_C5 (7400), u_B4 (74107), u_E4 (7400), u_H8 (7404).
- **Un-stub existing chip gates:** M5 gate 4, J5 gates 4/5, F4 FF2, D5 FF2.
- **Temporary video routing:** route the maze pattern (C5.pin6) directly to the `video` output, since the full F8 NAND combiner depends on Phase 2's score chain.

## Phase 2 — Score + play timer

Ports `/* Play timer */` (502-534), `/* Playfield mux */` (535-562), `/* Playfield mux part 2 */` (607-695). Adds visible countdown timer and score digits.

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
