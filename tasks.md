# Gotcha port roadmap

Path from current state (chip-level sync gen, blank 240p signal) to a fully playable Atari Gotcha MiSTer core. Reference netlist: `docs/DICE/games/gotcha.cpp`.

---

## 📍 Resume here — Phase 6 (Left player) written; Phase 5 right-player deadlock still open

**Status (2026-05-30):** Phase 6 (Left player) is fully translated and lints clean — see the "Phase 6 — Left player" section below for what was added.  Phase 5 debug hacks are reverted (clean tree).  The right-player power-on deadlock (below) is **still unresolved** — the left player mirrors the same comparator structure so it may show the same bug on hardware.  Both Phase 5 + Phase 6 are uncommitted.  Next options: (a) hardware-test the two-player build, (b) chase the spawn-in-wall comparator/maze bug, (c) start Phase 7 (Sound).

---

### Original Phase 5 debug notes (runaway sprite, joystick dead)

Phase 5 (Right player, `/* Right Control */` + `/* Right Counters */`, gotcha.cpp 697-884) is fully written but **NOT yet committed**.  On hardware the right player sprite runs across the screen continuously and the joystick has no visible effect.

**Debug hacks REVERTED (2026-05-30):** the RGB-split video output is back to the single monochrome `video` bus (`(F6_pin13 | VIDEO1 | VIDEO2) ? 8'hFF : 8'h00` in gotcha.sv, `VGA_R=VGA_G=VGA_B=video` in Arcade-Gotcha.sv) and `u_B8.pin4 (/RST)` is back to VCC.  Tree is clean for commit once a real fix lands.

**Translation audit (2026-05-30) — Right player is faithful to DICE.**  Cross-checked every CONNECTION in gotcha.cpp 697-884 against the sv: B2/B3/C2 direction-memory FFs, the A/B/C/D load values (A=E4.3, B=D3.4, C=B3.Q2, D=D2.8), E3/F3/G1/D1 counters and their load/count/MR wiring, K4 (correctly a 7402, not 7400), E4_g6 = NAND(K4_g3, ATTRACT_n) = `B8|HLD1` in play mode, and the CATCHOS path all match.  **No translation error found in the motion path.**  Conclusion: the bug is NOT a missing or mis-wired chip in this section.

**Sound/Phase 7 will NOT fix this.**  `CATCHOS = B7.10` (9602 Q, idles LOW) only gates `PRES` (E5), which only fires during a catch event — it is *not* a per-frame reset.  Sprite position is held entirely by the A/B/C/D load values from the direction-memory FFs, so the A10 stub is irrelevant to the scroll.  The only unimplemented right-side connection is **K4 gate 2** (`nc_K4_g2`, involves M2/ATTRACT — Sound) which does not touch the motion path.

**Root cause = power-on deadlock, not missing logic.**  The mechanism is confirmed by the audited logic: at power-on the B2/B3/C2 FFs latch a direction that drives VIDEO1 onto a maze wall → BUMP1 falls → B8 retriggers continuously → E4_g6 (= B8|HLD1) pins HIGH → B2/B3 never see a clock edge → joystick can't redirect → stays on the wall.  Deadlock.

**DICE-init re-verification (2026-05-30):** checked DICE's power-on path (`chip.cpp Chip::initialize()`, `chips/latch.cpp`, `chips/7474.cpp`, `chips/555mono.cpp`).
- DICE FF internal state nodes (i1/i2) power up at **0** — identical to our FPGA FF reset.  The LATCH only power-on-resets the ATTRACT/game-state logic (J5.13), not the player FFs.
- DICE settles the whole combinational net to a DC fixed point at init (recursive initialize), all FF outputs 0 — same DC state our continuous `assign`s reach.
- Spawn load values are therefore identical in both: E3=9, G1=10.
- 7474 async truth table and 555 retrigger behavior both match our primitives.
- **Conclusion: init is NOT the divergence — both sims start byte-identical.**  The only way DICE plays while we deadlock is that *our* spawn cell overlaps a MAZE wall while DICE's sits in a corridor.  → The fault is in **MAZE geometry or the VIDEO1 H/V position comparator** (the E3/F3/G1/D1 → H2/F2/J2/E2 → F1 match chain), NOT initialization and NOT a missing chip.

**Faithfulness gap found (not the root cause):** `ttl_7474`/`ttl_74107` apply async `/PR`//`CLR` only on `posedge clk_sys`; DICE applies them continuously.  ~35ns latency — worth fixing for tight preset-feedback loops but does not explain a permanent deadlock.

**Fix direction:** audit the maze pattern (C5/E6/K5/K4 playfield chain) and the VIDEO1 position-match chain against DICE at the spawn cell — find why VIDEO1 lands on a wall.  Not more chip translation; not init.

**Symptoms on hardware:**
- Right player sprite (`VIDEO1` = F1.pin1) scrolls fast right-to-left at the top of the screen, slow vertical drift.
- Joystick reaches the gotcha module (round-1 debug confirmed) but has no visible effect on the sprite.

**Diagnostic rounds run so far** (R = `F6_pin13`, G = `VIDEO1`, B = varies):
1. `B = |STICK1[3:0]` → blue flashed when stick pressed: joystick reaches the netlist. ✓
2. confirmed the runaway character is GREEN: it's `VIDEO1`, not a maze artifact. ✓
3. `B = B2_Q1` → blue stuck solid HIGH, no stick response: B2.Q1 preset-locked.
4. `B = B8.pin3` → blue flickering fast: B8 (the 555 monostable, 90ms) is retriggering rapidly.
5. **(uncommitted, awaiting test)** `u_B8.pin4 (/RST) = GND` to disable B8; B re-aimed at `B2_Q1`.  If B2.Q1 now moves with the joystick, the B8 retrigger lockup is the proximate cause.

**Hypothesised mechanism:** sprite drawn at maze-colliding positions from power-on → BUMP1 (= NAND(MAZE, VIDEO1, VIDEO1)) falls constantly → B8 keeps retriggering and pins its output HIGH → E4_g6 = B8.pin3 | HLD1 stays HIGH → the B2/B3/C2 direction-memory FFs (clocked by E4_g6 rising) never clock → the load values into E3/F3/G1/D1 are frozen at the power-on defaults (A=1, B=0, C=0, D=1 → E3 loads 9, G1 loads 10) → V-match drifts per frame and the sprite stays mispositioned.  **Deadlock loop.**

**Next steps (pick up here):**
1. Wait for the user's report on round 5.
2. If blue responds to the stick: B8 lockup confirmed.  Real fix has to address *why* VIDEO1 fires at colliding positions in the first place.  My on-paper analysis says VIDEO1 should hit at H≈450 stably per scanline; the actual scrolling means something is off.  Candidates:
   - Translation error somewhere in the E3/F3/G1/D1/F1/H2/J2/E2 chain (re-walk the H-match conditions).
   - The J2 FF2 sync conversion (CP2=CLK_n, J/K=F3_RCO&E3_RCO) — audited twice but worth one more pass.
   - Power-on initial-state mismatch: the schematic relies on FFs powering up to random values, real silicon hits a good state by chance, simulation always lands deterministically in the bad state.
3. If blue is *still* stuck: C3 clear path isn't releasing.  VRESET_n (= H6.Q2) should pulse LOW for ~1 line/frame; if it's not, C3.Q2 never clears and the preset chain stays locked.  Probe VRESET_n on a debug channel.
4. **Before committing**: revert the `u_B8.pin4` back to VCC and re-merge the video output to `(F6_pin13 | VIDEO1 | VIDEO2) ? 8'hFF : 8'h00` in gotcha.sv (and the matching `wire [7:0] video` in Arcade-Gotcha.sv).  Then commit Phase 5 + the real fix.

**Other context:** Phases 0-4 + clock/counter timing fixes were pushed at `96a4986`.  Phase 5 + ttl_555_mono are the only uncommitted code.  After Phase 5 lands: Phase 6 = Left player, Phase 7 = Sound, Phase 8 = polish (see below).

---

## Phase 4 (Coin) — done, see history below

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

## Phase 4 — Coin + game state ✓ DONE

Ports `/* Coin */` (412-455).  Replaces ATTRACT_n / START / START_n / CATCHOS_n stubs.  New primitives: ttl_9602 (dual one-shot, parameterized pulse widths), ttl_latch (DICE power-on SR latch).  Coin/Start later moved from OSD triggers to joystick buttons (`J1,Coin,Start;`, joystick_0[4]/[5]).

## Phase 5 — Right player ✓ DONE (awaiting hardware verification)

Ports `/* Right Control */` + `/* Right Counters */` (697-884).  New primitive: ttl_555_mono.  20 new chip instances; STICK1 joystick input; VIDEO1 OR'd into the picture.  J2 FF2 converted to a synchronous toggle (CP2=CLK_n + J2_carry enable) per the propagation-delay audit.

---

## Remaining work

### Phase 6 — Left player ✓ DONE (2026-05-30, awaiting hardware verification)
Ported `/* Left control */` (885-954) + `/* Left counters */` (955-1059) — the mirror of the Right player.  18 new chip instances (no new primitive files needed — all types already existed):
- **Control:** K3 (7402, ↔D3), M1 (7402, joystick ↔A1), L3 (7474, ↔C3), M3/M2/L2 (7474 dir-memory ↔B2/B3/C2), K2 (7486 XOR ↔D2), u_M4 (7400 chip ↔E4 — note: distinct from the `M4` *net* = H4.6), L4 (7402, only g2 used; g1/3/4 are Sound), C8 (ttl_555_mono 82k/1µF, collision one-shot ↔B8).
- **Counters:** J3/H3 (9316 horizontal ↔E3/F3), L1/K1 (9316 vertical ↔G1/D1), J1 (7410 ↔E2/match), J2 FF1 un-stubbed as the left "X" carry toggle (same CLK_n + carry-enable sync conversion as FF2; /CLR1=PRES), XY (7410 right-wall collision fix), J10 (7400), K10 (ttl_555_mono 100k/1µF ≈110ms reset one-shot).
- **Shared chips un-stubbed:** K4 g2 (→M2 /PR1), H1 inv1/3/5, H2 g1, F1 g2 (→VIDEO2) + g4, E1 g2 (→L1/K1 /PE), J2 FF1.
- **emu.sv:** added `STICK2 = joystick_1[3:0]`, declared/wired `joystick_1` into hps_io.
- **Schematic vs DICE speed-hack:** used the real `J1.9 = MAZE` (commented line 1028), not DICE's `CLK_GATE1` optimization.  Kept `XY` (DICE notes it's needed for right-wall collisions).
- **Verified:** `verilator --lint-only` elaborates clean (22 modules, no errors).
- **Still stubbed (Sound, Phase 7):** M4-chip g1/g2 → AUDIO, L4 g1 (E8.3), A10, D2 g1/g4 (PROXIMITY/LOG1).  `/* M1,M3 */` (563-566) done in Phase 2.
- **NOTE:** the left player shares the Right player's comparator structure, so if the right-player spawn-in-wall deadlock is a geometry/comparator bug, the left player will exhibit it too.  Hardware test will tell.

### Phase 7 — Sound
Ports `/* Sound */` (~1055-end): A10 (7400 — feeds B7 half B's CATCHOS trigger; replaces the `A10_pin8_stub`), M2/D2-gate1/J2-FF1, K10 (ttl_555_mono), the PROXIMITY custom block (RC cap charge — discretize as a low-pass + threshold), and the audio mixers.  Route audio into `AUDIO_L/R` in Arcade-Gotcha.sv.  Also lets D8 become the real POT1-driven 555 astable instead of the inline clk divider.

### Phase 8 — Polish
- 3-channel colour video instead of monochrome OR.
- DIP / OSD options: play time (POT1), etc.
- Tune PLL VCO if timing slack is tight.
- Capture release `.rbf` into `releases/<corename>_YYYYMMDD.rbf`.

---

**Current task list (in-flight):** see Claude's TaskList tool — phases above get broken into atomic tasks during execution.
