//============================================================================
//  Atari Gotcha (1973) - chip-level FPGA port
//
//  This module is a structural translation of docs/DICE/games/gotcha.cpp into
//  SystemVerilog. Each 74xx chip in the original PCB has a corresponding
//  ttl_* primitive instance. Net names (CLK, H1..H256, V1..V256, ...) and
//  chip designators (J6, L6, K6, ...) mirror the Atari schematic.
//
//  Current scope:
//    - Phase 0: H/V counter + sync gen (gotcha.cpp 326-411).
//    - Phase 1: playfield maze + border (gotcha.cpp 456-501).
//    - Phase 2: play timer + catch counter + score digit muxes + the F8
//               NAND combiner that produces the final picture signal
//               (gotcha.cpp 502-561, 608-694).
//    - Phase 3: M4 player-state signal (gotcha.cpp 568-606).
//    - Phase 4: /* Coin */ — ATTRACT / START / COIN / Q signals + LATCH
//               power-on reset (gotcha.cpp 412-455).  Replaces the Phase 2
//               stubs.
//    Right/Left player movement, /* Sound */: TBD (Phases 5+).
//
//  Remaining stubs:
//    - A10.pin8 = VCC.  Feeds B7 half B's TRIG2 input.  A10 is a 7400 in
//      /* Sound */ that goes LOW briefly each play-time cycle to trigger
//      CATCHOS.  Without /* Sound */ translated, B7 half B retriggers only
//      from START rising edges (TRIG = START | ~VCC = START).
//  D8 (a 555 astable producing ~1 Hz from RC=(297k,2k,5µF) in gotcha.cpp:11)
//  is modeled here as an explicit clk_sys divider down to ~1 Hz.
//
//  Clock model: clk_sys runs at 28.63636 MHz (2x the netlist's 14.31818 MHz
//  CLOCK net) so the MiSTer HDMI scaler has more cycles per pixel — with
//  CE_PIXEL at the 7.159 MHz pixel rate this gives CE_PIXEL = CLK_VIDEO/4.
//  The real CLOCK net is recreated as CLOCK_14M = clk_sys/2 and fed to J6.CP1.
//  Every ttl_* primitive edge-detects its clock pin against clk_sys.
//
//  Note on chip relabel: L6 and M6 are declared CHIP("L6",9316) in gotcha.cpp
//  but wired with 7493 pinout (CLK on pin 14, R0 on pins 1-3, QA on pin 12,
//  QA->CKB self-cascade). They function as 7493 ripple counters and are
//  instantiated as ttl_7493 here. F5 and H5 are correctly labeled 7493 in
//  gotcha.cpp and use the same pattern.
//============================================================================

module gotcha (
    input  logic        clk_sys,
    input  logic        reset,

    // Player button inputs from emu.sv (active-LOW to match DICE COIN_INPUT /
    // START_INPUT convention: 0 when pressed, 1 when released).
    input  logic        COIN1,
    input  logic        START1,

    // Right player joystick (STICK1).  Active-HIGH direction bits from
    // emu.sv: [0]=Right, [1]=Left, [2]=Down, [3]=Up (MiSTer joystick layout).
    input  logic [3:0]  STICK1,

    // Left player joystick (STICK2) — same [0]=R [1]=L [2]=D [3]=U layout.
    input  logic [3:0]  STICK2,

    output logic        ce_pix,
    output logic        HBlank,
    output logic        HSync,
    output logic        VBlank,
    output logic        VSync,

    output logic [7:0]  video,
    output logic signed [15:0] audio        // mono PCM (signed), Phase 7
);

    // ------------------------------------------------------------------
    // Power rails
    // ------------------------------------------------------------------
    wire VCC = 1'b1;
    wire GND = 1'b0;

    // ------------------------------------------------------------------
    // Signal aliases for cross-phase nets:
    // M4: real, produced by H4 gate 2 in /* M4 */ (Phase 3).
    // ATTRACT_n, START, START_n: real (Phase 4) — produced by the /* Coin */ chain.
    // CATCHOS / CATCHOS_n: B7 9602 half B; its /2TR is now driven by the A10
    //   CATCHOS latch (Phase 7 /* Sound */) instead of the old VCC stub.

    // ------------------------------------------------------------------
    // Net declarations (names mirror gotcha.cpp #defines)
    // ------------------------------------------------------------------
    wire        CLK, CLK_n;                              // J6 FF1 outputs
    wire        H1,  H2,  H4,  H8;                       // L6 outputs
    wire        H16, H32, H64, H128;                     // M6 outputs
    wire        H256, H256_n;                            // J6 FF2 outputs

    // H counter synchronous-carry terminal counts.  L6/M6/J6.FF2 all clock on
    // the root CLK; the upper nibbles are gated by these so the whole 9-bit H
    // counter increments atomically with no inter-nibble ripple lag.
    wire        L6_tc       = H1  & H2  & H4  & H8;      // L6 at 15
    wire        M6_tc       = H16 & H32 & H64 & H128;    // M6 at 15
    wire        H_carry256  = L6_tc & M6_tc;             // H[7:0] == 255 -> toggle H256
    wire        V1,  V2,  V4,  V8;                       // H5 outputs
    wire        V16, V32, V64, V128;                     // F5 outputs
    wire        V256, V256_n;                            // D5 FF1 outputs

    wire        K6_out;                                  // H=455 detect
    wire        H4_g1_out;                               // V=261 detect
    wire        H6_Q1, H6_Q1_n;                          // H reset latch
    wire        H6_Q2, H6_Q2_n;                          // V reset latch

    wire        M5_g1_out;                               // ~(H16 & H64)
    wire        HBLANK_w, HBLANK_n_w;                    // M5 NAND-latch outputs
    wire        VBLANK_w, VBLANK_n_w;                    // F6 NOR-latch outputs

    wire        J5_g1_out;                               // ~H64 (gate 1, Phase 2)
    wire        J5_g2_out;                               // ~H64 (gate 2, HSync)
    wire        J5_g3_out;                               // ~V32 (gate 3, Phase 2)
    wire        L5_g2_out;                               // ~(H32 & ~H64)
    wire        J4_g4_out;                               // ~H64 & HBLANK
    wire        HSYNC_w, HSYNC_n_w;                      // F4 FF1 outputs

    // Playfield (Phase 1) internal nets
    wire        D6_g2;                                   // ~(H4 & H8)
    wire        M5_g4;                                   // ~(H32 & H64)
    wire        F4_Q2_w, F4_Q2_n_w;                      // F4 FF2 (V64 latch)
    wire        E6_g2;                                   // ~(D6_g2 | F4_Q2_n_w | M5_g4)
    wire        K5_g1;                                   // H16 ^ H256
    wire        K4_g1;                                   // ~(K5_g1 | H128)
    wire        C5_g1;                                   // ~(E6_g2 & K4_g1)
    wire        B4_Q2;                                   // FF2 of B4 (J=1 K=0)
    wire        E4_g4;                                   // ~(B4_Q2 & V2)
    wire        J5_g5;                                   // ~V4
    wire        K4_g4;                                   // ~(V256_n | ~V4)
    wire        J5_g4;                                   // ~K4_g4
    wire        C5_g4;                                   // ~(E4_g4 & J5_g4)
    wire        D5_Q2_w, D5_Q2_n_w;                      // D5 FF2 Q/_Q (CP2=C5_g1 toggle)
    wire        C5_g3;                                   // ~(D5_Q2_w & C5_g4)
    wire        C5_g2;                                   // ~(C5_g1 & C5_g3) = MAZE INK
    wire        H8_inv5;                                 // ~C5_g2 (Phase 1, feeds F8.pin1)

    // Phase 2 internal nets
    wire        D8_out;                                  // ~1 Hz play-timer tick
    wire        K8_QA, K8_QB, K8_QC, K8_QD;              // K8 7490 outputs (units of seconds)
    wire        L8_QA, L8_QB, L8_QC, L8_QD;              // L8 7490 outputs (tens of seconds)
    wire        G8_QA, G8_QB, G8_QC, G8_QD;              // G8 7490 outputs (catch counter low)
    wire        J8_Q1, J8_Q1_n, J8_Q2, J8_Q2_n;          // J8 74107 outputs (catch counter high)

    wire        K5_g2_out;                               // H32 XOR ~V32 (Phase 2 K5 gate 2)
    wire        L5_g3_out;                               // ~(D5./Q2 & B1.pin8)  - drives J7./BI
    wire        L5_g4_out;                               // ~(H128 & H256) - drives B1.pin12
    wire        E6_g1_out;                               // ~(V4 | V8 | ~H16)
    wire        E6_g3_out;                               // ~(H8 | H4 | ~H16)
    wire        D7_pin6;                                 // ~H16
    wire        H8_inv3;                                 // ~V16
    wire        H8_inv4;                                 // ~E7.pin8
    wire        F6_pin1;                                 // ~(D7_pin6 | D6_g2) — F6 gate 1
    wire        F6_pin13;                                // ~(HBLANK | D6_g1) — VIDEO[1]
    wire        D6_g1;                                   // ~(CATCHOS_n & F8_pin8)
    wire        J4_g1;                                   // CLK_n & F8_pin8 = MAZE

    wire        L7_pin7, L7_pin9;                        // L7 74153 mux outputs (score low/high nibble byte 1)
    wire        M7_pin7, M7_pin9;                        // M7 74153 mux outputs (score low/high nibble byte 2)
    wire        I7_pin4, I7_pin7, I7_pin9, I7_pin12;     // I7 74157 quad mux outputs (4-bit BCD to J7)
    wire        B1_pin8;                                 // 4-input NAND, drives I7 SEL + L5 gate 3
    wire        J7_pin9,  J7_pin10, J7_pin11;            // J7 7448 segment outputs: e, d, c
    wire        J7_pin12, J7_pin13, J7_pin14, J7_pin15;  //                          b, a, g, f

    wire        E7_pin8;                                 // ~(V4 & V8 & H16)
    wire        E7_pin12;                                // ~(J7.pin13 & H8_pin6 & E6.pin12)
    wire        F7_pin6;                                 // ~(J7.pin12 & F6.pin1 & H8.pin6)
    wire        F7_pin8;                                 // ~(J7.pin10 & H8.pin8 & V16)
    wire        F7_pin12;                                // ~(J7.pin14 & H8.pin8 & H8.pin6)
    wire        H7_pin6;                                 // ~(J7.pin11 & F6.pin1 & V16)
    wire        H7_pin8;                                 // ~(J7.pin9  & V16 & E6.pin8)
    wire        H7_pin12;                                // ~(J7.pin15 & E6.pin8 & H8.pin6)
    wire        F8_pin8;                                 // 8-input NAND combiner output

    // Phase 4 /* Coin */ section nets
    wire        COIN;                                    // D7.pin2 = ~COIN1 (active-high)
    wire        COIN_n;                                  // D7.pin12 = COIN1 (active-low, double-inverted)
    wire        D7_pin10;                                // ~L8.QD (D7 inv 5 output)
    wire        ATTRACT;                                 // C7.pin9 (Q2 of C7 FF2)
    wire        ATTRACT_n;                               // C7.pin8 (/Q2)
    wire        START;                                   // B6.pin5 (Q1 of B6 FF1)
    wire        START_n;                                 // B6.pin6 (/Q1)
    wire        Q;                                       // J5.pin12 = ~LATCH.pin3 (sound/coin gate)
    wire        K7_Q1, K7_Q1_n;                          // K7 FF1 (coin-debounced)
    wire        B6_Q2, B6_Q2_n;                          // B6 FF2
    wire        C6_Q1, C6_Q1_n;                          // C6 FF1
    wire        C6_Q2, C6_Q2_n;                          // C6 FF2
    wire        C7_Q2_unused;                            // C7 FF1 Q1 (unused)
    wire        C7_Q2_n_unused;                          // C7 FF1 /Q1 (unused)
    wire        B7_pin6;                                 // B7 half A Q (unused)
    wire        B7_pin7;                                 // B7 half A /Q -> K7.CK1
    wire        B7_CATCHOS;                              // B7 half B Q  (= CATCHOS)
    wire        B7_CATCHOS_n;                            // B7 half B /Q (= CATCHOS_n)
    wire        LATCH_pin3;                              // LATCH output → J5 inv 6
    wire        D6_g3;                                   // ~(C6./Q1 & START)  → C7./CLR2
    wire        D6_g4;                                   // ~(ATTRACT & C6.Q1) → LATCH.pin1 (SET)

    // Alias: CATCHOS_n net used by Phase 2 mux chain comes from B7 half B.
    wire        CATCHOS_n = B7_CATCHOS_n;

    // Phase 3 /* M4 */ section nets
    wire        B4_Q1, B4_Q1_n;                          // B4 FF1 outputs (Phase 3)
    wire        B4_Q2_n;                                 // B4 FF2 /Q2 — drives K5 gate 3 (gotcha.cpp:605)
    wire        B5_Q1, B5_Q1_n;                          // B5 FF1
    wire        B5_Q2, B5_Q2_n;                          // B5 FF2
    wire [3:0]  C4_Q;                                    // C4 9316 outputs {Q3,Q2,Q1,Q0}
    wire        C4_RCO;                                  // C4 terminal count
    wire [3:0]  D4_Q;                                    // D4 9316 outputs
    wire        D4_RCO;                                  // D4 terminal count
    wire        E4_g3;                                   // ~(C4_RCO & D4_RCO) → both /PE
    wire        L5_g1;                                   // ~(H32 & H256)
    wire        K5_g3;                                   // V256 XOR B4./Q1
    wire        M4;                                      // = H4 gate 2 output (Phase 3)

    // Phase 5 /* Right Control */ + /* Right Counters */ section nets
    wire        BUMP1;                                   // H4 gate 3 = ~(MAZE & VIDEO1 & VIDEO1)
    wire        VIDEO1;                                  // F1 gate 1 — right player picture
    wire        VIDEO2;                                  // F1 gate 2 — left player (Phase 6: stubbed to 0)
    wire        CATCH_n;                                 // E1 gate 1 = ~(VIDEO1 & VIDEO2)
    wire        OO;                                      // E1 gate 4 = ~(~PRES & START)
    wire        PRES;                                    // E5 8-input NAND
    wire        A_sig;                                   // E4 gate 1 = ~(VRESET & B2.Q1)   ("A")
    wire        B_sig;                                   // D3 gate 2 = ~(VRESET_n | D2.pin6) ("B")
    wire        D_sig;                                   // D2 gate 3 XOR                    ("D")
    wire        J_sig;                                   // E2 gate 2 = ~(~L & G1.Q0)        ("J")
    wire        HLD1;                                    // E2 gate 3 = ~(J4.g2 & E3.RCO)
    wire        E1_pin8;                                 // E1 gate 3 = ~(G1.RCO & D1.RCO) → G1/D1 /PE
    wire        VRESET   = H6_Q2_n;                      // H6.pin8  (active-high V reset)
    wire        VRESET_n = H6_Q2;                        // H6.pin9  (active-low  V reset)
    wire        E4_g6;                                   // E4 gate 2 = ~(K4.g3 & ATTRACT_n)
    // "C" = B3_Q2, "L" = G1_Q[1], "M" = E3_Q[2], "S" = B5_Q2, "Y" = J2_Q2_n,
    // "MAZE" = J4_g1, "M1" = J5_g3_out, "M2" = H8_inv3 — used directly below.

    wire        D3_pin1,  D3_pin10, D3_pin13;            // D3 7402 NOR gate outputs (g2 = B_sig)
    wire        H1_pin4,  H1_pin8,  H1_pin12;            // H1 7404 inverter outputs
    wire        C3_Q1, C3_Q1_n, C3_Q2, C3_Q2_n;         // C3 7474
    wire        A1_pin1, A1_pin4, A1_pin10, A1_pin13;    // A1 7402 NOR (joystick gates)
    wire        B2_Q1, B2_Q1_n, B2_Q2, B2_Q2_n;         // B2 7474
    wire        B3_Q1, B3_Q1_n, B3_Q2, B3_Q2_n;         // B3 7474
    wire        C2_Q1, C2_Q1_n, C2_Q2, C2_Q2_n;         // C2 7474
    wire        D2_pin6;                                 // D2 7486 gate 2 XOR (D_sig = gate 3)
    wire        B8_pin3;                                 // B8 555 monostable output
    wire        J4_g2, J4_g3;                            // J4 7408 gates 2, 3 (Phase 5)
    wire        K4_g3;                                   // K4 7402 gate 3 = ~(B8 | HLD1)

    wire [3:0]  E3_Q;       wire E3_RCO;                 // E3 9316 right-H position low
    wire [3:0]  F3_Q;       wire F3_RCO;                 // F3 9316 right-H position high
    wire [3:0]  G1_Q;       wire G1_RCO;                 // G1 9316 right-V position low
    wire [3:0]  D1_Q;       wire D1_RCO;                 // D1 9316 right-V position high
    wire        J2_Q1, J2_Q1_n;                          // J2 74107 FF1 (Sound — stubbed)
    wire        J2_Q2, J2_Q2_n;                          // J2 74107 FF2; /Q2 = "Y"
    wire        J2_carry;                                // F3_RCO & E3_RCO (sync toggle-enable)
    wire        E2_pin3, E2_pin11;                       // E2 7400 NAND gate outputs (pin8 = HLD1)
    wire        F2_Q1, F2_Q1_n, F2_Q2, F2_Q2_n;         // F2 7474
    wire        H2_pin8;                                 // H2 7420 gate 2
    wire        B1_g1;                                   // B1 7420 gate 1 = VVIDEO1_n

    // Phase 6 /* Left Control */ + /* Left Counters */ section nets.
    //   Mirror of the Right player: K3↔D3, M1↔A1, M3↔B2, M2↔B3, L2↔C2,
    //   L3↔C3, K2↔D2, u_M4(chip)↔E4, C8↔B8, J3↔E3, H3↔F3, L1↔G1, K1↔D1,
    //   J2.FF1↔J2.FF2, J1↔E2.  H1/H2/F1/E1/K4 are shared chips (gates un-stubbed).
    wire        BUMP2;                                   // J1 gate3 = ~(MAZE & ~F1.13 & VIDEO2)
    wire        E_sig;                                   // M4-chip gate3 = ~(M3.Q2 & VRESET)  ("E")
    wire        M4c_pin11;                               // M4-chip gate4 = left dir strobe (= C8|HLD2 in play)
    wire        HLD2;                                    // J1 gate1 (pin12) = left H load-enable
    wire        OO2;                                     // J10 gate2 (pin6) = left counters /MR
    wire        C8_pin3;                                 // C8 555 monostable output (left collision)
    wire        K10_pin3;                                // K10 555 monostable output (left reset one-shot)
    wire        L4_pin4;                                 // L4 7402 gate2 = ~(C8 | HLD2)

    wire        K3_pin1, K3_pin4, K3_pin10, K3_pin13;    // K3 7402 NOR (K3.10 = "F" load value)
    wire        L3_Q1, L3_Q1_n, L3_Q2, L3_Q2_n;         // L3 7474 (mirror C3)
    wire        M1_pin1, M1_pin4, M1_pin10, M1_pin13;    // M1 7402 (left joystick gates)
    wire        M3_Q1, M3_Q1_n, M3_Q2, M3_Q2_n;         // M3 7474 (left H dir memory)
    wire        M2_Q1, M2_Q1_n, M2_Q2, M2_Q2_n;         // M2 7474 (left V dir memory)
    wire        L2_Q1, L2_Q1_n, L2_Q2, L2_Q2_n;         // L2 7474
    wire        K2_pin3, K2_pin6, K2_pin8, K2_pin11;     // K2 7486 XOR (K2.3="K", K2.6="H")
    wire        H1_pin2, H1_pin6, H1_pin10;              // H1 inverters 1/3/5 (left)

    wire [3:0]  J3_Q;       wire J3_RCO;                 // J3 9316 left-H position low
    wire [3:0]  H3_Q;       wire H3_RCO;                 // H3 9316 left-H position high
    wire [3:0]  L1_Q;       wire L1_RCO;                 // L1 9316 left-V position low
    wire [3:0]  K1_Q;       wire K1_RCO;                 // K1 9316 left-V position high
    wire        J2_carry_L;                              // H3_RCO & J3_RCO (sync toggle-enable, FF1)
    wire        J1_pin6;                                 // J1 7410 gate2 -> F1.6 (VIDEO2)
    wire        H2_g1_out;                               // H2 7420 gate1 -> F1.5 (VIDEO2)
    wire        E1_pin6;                                 // E1 7400 gate2 = ~(L1.RCO & K1.RCO) -> L1/K1 /PE
    wire        F1_pin13;                                // F1 7402 gate4 = ~(K2.11 | K2.3)
    wire        XY_pin8;                                 // XY 7410 gate3 (right-wall collision fix)
    wire        J10_pin3, J10_pin8;                      // J10 7400 gate outputs
    wire        nc_L4_pin10, nc_L4_pin13;               // L4 gates 3,4 unused (sound)
    wire        nc_XY_pin6, nc_XY_pin12;                 // XY 7410 gates 1,2 unused
    wire        nc_J10_g4;                               // J10 7400 gate 4 unused

    // Phase 7 /* Sound */ section nets (gotcha.cpp lines 1052-1111).
    wire        A10_pin8;                                // CATCHOS latch output (-> B7 /2TR)
    wire        D2_pin3;                                 // D2 g1 = Y ^ J2.Q1   -> PROXIMITY in[0]
    wire        D2_pin11;                                // D2 g4 = K1.Q3 ^ D1.Q3 -> PROXIMITY in[1]
    wire        E8_pin3;                                 // E8 555 astable output (proximity oscillator)
    wire        L4_pin1;                                 // L4 g1 = ~(E8.3 | ATTRACT)  -> M4.1
    wire        M4c_pin3;                                // M4-chip g1 = ~(L4.1 & V8)  -> AUDIO (proximity)
    wire        M4c_pin6;                                // M4-chip g2 = ~(V8 & CATCHOS) -> AUDIO (catch)

    // Stubs for chip gates not yet wired in any phase
    // (no remaining J5 inverter stubs)
    // (no remaining J4 stubs — gates 2,3 now wired in Phase 5)
    // (no remaining H4 stubs — gate 3 now wired in Phase 5)
    wire        nc_F1_g3;                                // F1 7402 gate 3 unused
    wire        K4_g2_out;                               // K4 7402 gate 2 = ~(M2.Q2 | ATTRACT) -> M2 /PR1
    // (no remaining D6 stubs)
    wire        nc_K5_g4;
    wire        nc_H8_inv1, nc_H8_inv2, nc_H8_inv6;
    wire        nc_D7_pin4, nc_D7_pin8;

    // ==================================================================
    // CLOCK_14M - the netlist's master CLOCK net (gotcha.cpp CLOCK_14_318_MHZ).
    //   clk_sys runs at 28.636 MHz (2x the netlist clock) to give the MiSTer
    //   HDMI scaler more headroom — CE_PIXEL ends up at CLK_VIDEO/4.  Here we
    //   divide clk_sys by 2 to recreate the real 14.31818 MHz CLOCK square
    //   wave that J6.CP1 expects.  Every ttl_* primitive edge-detects its
    //   clock pin against clk_sys, so feeding J6 a real divided CLOCK net is
    //   accurate (and lets us drop the old CP1_IS_CLK_SYS hack).
    // ==================================================================
    logic CLOCK_14M = 1'b0;
    always_ff @(posedge clk_sys) CLOCK_14M <= ~CLOCK_14M;

    // ==================================================================
    // D8 - 555 astable stub.  Original part: 555 with RC=(297kΩ, 2kΩ, 5µF)
    //      → f = 1.44 / ((R1+2R2)*C) ≈ 0.957 Hz.  We round to exactly 1 Hz
    //      by toggling a flop every clk_sys/2 = 14318180 clk_sys cycles.
    //      pin4 = ATTRACT_n; when low, D8 is held in reset.  Output is
    //      what gotcha.cpp calls D8.pin3 (= K8.CKA).
    // ==================================================================
    localparam int D8_HALF_PERIOD = 25'd14_318_180;     // clk_sys = 28.636 MHz
    logic [24:0] d8_counter = '0;
    logic        d8_q       = 1'b0;
    always_ff @(posedge clk_sys) begin
        if (!ATTRACT_n) begin
            d8_counter <= '0;
            d8_q       <= 1'b0;
        end else if (d8_counter == D8_HALF_PERIOD - 1) begin
            d8_counter <= '0;
            d8_q       <= ~d8_q;
        end else begin
            d8_counter <= d8_counter + 25'd1;
        end
    end
    assign D8_out = d8_q;

    // ==================================================================
    // J6 - 74107 dual JK FF
    //   FF1: CP1 = CLOCK_14M (14.318 MHz), J=K=VCC -> Q1 toggles on each
    //        CLOCK_14M negedge, giving CLK = 14.318 / 2 = 7.159 MHz.
    //   FF2 (H256): structurally the schematic clocks CP2 from M6.QD (H128)
    //        with J=K=VCC.  To keep the 9-bit H counter atomic (no ripple
    //        lag), CP2 is instead the root CLK and J2=K2=H_carry256 — so
    //        H256 toggles on the same CLK negedge that rolls L6 and M6 over
    //        when H[7:0] == 255.  Functionally identical, but L6/M6/H256 all
    //        update on one clk_sys edge.  /CLR2 = H6.Q1 unchanged.
    // ==================================================================
    ttl_74107 u_J6 (
        .clk_sys (clk_sys),
        .pin1    (VCC),          // J1
        .pin2    (CLK_n),        // /Q1
        .pin3    (CLK),          // Q1
        .pin4    (VCC),          // K1
        .pin5    (H256),         // Q2
        .pin6    (H256_n),       // /Q2
        .pin8    (H_carry256),   // J2 <- H[7:0]==255 (synchronous carry)
        .pin9    (CLK),          // CP2 <- root CLK
        .pin10   (H6_Q1),        // /CLR2 <- H6.Q1
        .pin11   (H_carry256),   // K2 <- H[7:0]==255
        .pin12   (CLOCK_14M),    // CP1 <- master 14.318 MHz CLOCK net
        .pin13   (VCC)           // /CLR1
    );

    // ==================================================================
    // L6 - 7493 H counter low nibble (SELF_CASCADE atomic 4-bit counter)
    //   CKA = CLK, count-enable (pin1) = VCC (always counts), R0 = H6./Q1.
    // ==================================================================
    ttl_7493 #(.SELF_CASCADE(1)) u_L6 (
        .clk_sys (clk_sys),
        .pin1    (VCC),          // count-enable (always)
        .pin2    (H6_Q1_n),      // R0(1)
        .pin3    (H6_Q1_n),      // R0(2)
        .pin8    (H4),           // QC
        .pin9    (H2),           // QB
        .pin11   (H8),           // QD
        .pin12   (H1),           // QA
        .pin14   (CLK)           // CKA
    );

    // ==================================================================
    // M6 - 7493 H counter high nibble (SELF_CASCADE atomic 4-bit counter)
    //   CKA = CLK (root clock, NOT L6.QD), count-enable (pin1) = L6_tc, so M6
    //   increments on the same CLK negedge as L6 whenever L6 is at 15.  No
    //   inter-nibble ripple lag.  R0 = H6./Q1.
    // ==================================================================
    ttl_7493 #(.SELF_CASCADE(1)) u_M6 (
        .clk_sys (clk_sys),
        .pin1    (L6_tc),        // count-enable <- L6 terminal count
        .pin2    (H6_Q1_n),
        .pin3    (H6_Q1_n),
        .pin8    (H64),
        .pin9    (H32),
        .pin11   (H128),
        .pin12   (H16),
        .pin14   (CLK)           // CKA <- root CLK (was L6.QD)
    );

    // ==================================================================
    // K6 - 7430 8-input NAND, H=455 detector
    //   inputs: H1, H2, H4, H64, H128, H256 (+ VCC on pin 2 and 12)
    //   output (pin8) goes LOW when H = 1+2+4+64+128+256 = 455
    // ==================================================================
    ttl_7430 u_K6 (
        .pin1  (H1),
        .pin2  (VCC),
        .pin3  (H128),
        .pin4  (H64),
        .pin5  (H2),
        .pin6  (H4),
        .pin8  (K6_out),
        .pin11 (H256),
        .pin12 (VCC)
    );

    // ==================================================================
    // H4 - 7410 triple 3-input NAND
    //   Gate 1 (pins 1,2,13 -> 12): V=261 detect: ~(V256 & V1 & V4).
    //   Gate 2 (pins 3,4,5 -> 6, Phase 3 /* M4 */): pin3=K5_g3, pin4=L5_g1,
    //     pin5=D4.QD -> pin6 = M4 = ~(K5_g3 & L5_g1 & D4.QD).
    //   Gate 3 (pins 9,10,11 -> 8, Phase 5 /* Right Control */):
    //     pin9=MAZE, pin10=VIDEO1, pin11=VIDEO1 -> pin8 = BUMP1.
    // ==================================================================
    ttl_7410 u_H4 (
        .pin1  (V256),  .pin2  (V1),     .pin13 (V4),     .pin12 (H4_g1_out),
        .pin3  (K5_g3), .pin4  (L5_g1),  .pin5  (D4_Q[3]),.pin6  (M4),
        .pin9  (J4_g1), .pin10 (VIDEO1), .pin11 (VIDEO1), .pin8  (BUMP1)
    );

    // ==================================================================
    // H6 - 7474 dual D-FF: H reset latch (FF1) + V reset latch (FF2)
    // ==================================================================
    ttl_7474 u_H6 (
        .clk_sys (clk_sys),
        .pin1    (VCC),         // /CLR1
        .pin2    (K6_out),      // D1
        .pin3    (CLK),         // CK1
        .pin4    (VCC),         // /PR1
        .pin5    (H6_Q1),       // Q1
        .pin6    (H6_Q1_n),     // /Q1
        .pin8    (H6_Q2_n),     // /Q2
        .pin9    (H6_Q2),       // Q2
        .pin10   (VCC),         // /PR2
        .pin11   (H6_Q1_n),     // CK2 <- /Q1
        .pin12   (H4_g1_out),   // D2
        .pin13   (VCC)          // /CLR2
    );

    // ==================================================================
    // H5 - 7493 V counter low nibble (SELF_CASCADE atomic 4-bit counter)
    //   count-enable (pin1) = VCC.  The V counter keeps the simple
    //   nibble-ripple cascade (F5.CKA = H5.QD) — its ≤2-clk_sys inter-nibble
    //   settling happens during the H reset window (HBLANK), so it's never
    //   sampled in the visible region.  Only the H counter needs the fully
    //   synchronous carry.
    // ==================================================================
    ttl_7493 #(.SELF_CASCADE(1)) u_H5 (
        .clk_sys (clk_sys),
        .pin1    (VCC),          // count-enable (always)
        .pin2    (H6_Q2_n),
        .pin3    (H6_Q2_n),
        .pin8    (V4),
        .pin9    (V2),
        .pin11   (V8),
        .pin12   (V1),
        .pin14   (H6_Q1_n)
    );

    // ==================================================================
    // F5 - 7493 V counter high nibble (SELF_CASCADE atomic 4-bit counter)
    //   count-enable (pin1) = VCC, CKA = H5.QD (V8).  See H5 note.
    // ==================================================================
    ttl_7493 #(.SELF_CASCADE(1)) u_F5 (
        .clk_sys (clk_sys),
        .pin1    (VCC),          // count-enable (always)
        .pin2    (H6_Q2_n),
        .pin3    (H6_Q2_n),
        .pin8    (V64),
        .pin9    (V32),
        .pin11   (V128),
        .pin12   (V16),
        .pin14   (V8)
    );

    // ==================================================================
    // D5 - 74107 dual JK FF
    //   FF1 (V256), FF2 (Playfield D5.Q2 toggle).  Phase 2 wires the /Q2
    //   output (pin6) to L5.pin9 for the score-digit blanking logic.
    // ==================================================================
    ttl_74107 u_D5 (
        .clk_sys (clk_sys),
        .pin1    (VCC),          // J1
        .pin2    (V256_n),       // /Q1
        .pin3    (V256),         // Q1
        .pin4    (VCC),          // K1
        .pin5    (D5_Q2_w),      // Q2
        .pin6    (D5_Q2_n_w),    // /Q2 — Phase 2: drives L5.pin9
        .pin8    (VCC),          // J2
        .pin9    (C5_g1),        // CP2
        .pin10   (H6_Q1),        // /CLR2
        .pin11   (VCC),          // K2
        .pin12   (V128),         // CP1
        .pin13   (H6_Q2)         // /CLR1
    );

    // ==================================================================
    // M5 - 7400 quad NAND, HBLANK NAND-latch + playfield H32&H64 gate
    // ==================================================================
    ttl_7400 u_M5 (
        .pin1  (H16),
        .pin2  (H64),
        .pin3  (M5_g1_out),
        .pin4  (M5_g1_out),
        .pin5  (HBLANK_w),
        .pin6  (HBLANK_n_w),
        .pin9  (HBLANK_n_w),
        .pin10 (H6_Q1),
        .pin8  (HBLANK_w),
        .pin12 (H32), .pin13 (H64), .pin11 (M5_g4)
    );

    // ==================================================================
    // F6 - 7402 quad NOR, VBLANK NOR-latch + Phase 2 video gates
    //   Gate 1 (Phase 2): pin2=D7.pin6=~H16, pin3=D6_g2 -> pin1 = ~(~H16 | ~(H4&H8))
    //                     pin1 feeds H7 and F7 in the F8 combiner chain.
    //   Gate 2 (Phase 0): VBLANK NOR-latch with H6./Q2.
    //   Gate 3 (Phase 0): VBLANK NOR-latch with V16.
    //   Gate 4 (Phase 2): pin11=HBLANK, pin12=D6.pin3 -> pin13 = VIDEO[1] output
    //                     (~(HBLANK | D6_g1) — the canonical Gotcha video pin).
    // ==================================================================
    ttl_7402 u_F6 (
        .pin1  (F6_pin1),  .pin2 (D7_pin6),  .pin3 (D6_g2),
        .pin4  (VBLANK_n_w),
        .pin5  (VBLANK_w),
        .pin6  (H6_Q2_n),
        .pin8  (V16),
        .pin9  (VBLANK_n_w),
        .pin10 (VBLANK_w),
        .pin11 (HBLANK_w), .pin12 (D6_g1),   .pin13 (F6_pin13)
    );

    // ==================================================================
    // J5 - 7404 hex inverter
    //   Gate 1 (pin1 -> pin2):  ~H64 (Phase 2, drives B1.pin10)
    //   Gate 2 (pin3 -> pin4):  ~H64 (Phase 0, HSync timing)
    //   Gate 3 (pin5 -> pin6):  ~V32 (Phase 2, drives K5 gate 2 + I7.pin3)
    //   Gate 4 (pin9 -> pin8):  ~K4_g4 (Phase 1)
    //   Gate 5 (pin11 -> pin10): ~V4 (Phase 1, B4 reset + K4 input)
    //   Gate 6 (pin13 -> pin12): ~LATCH.pin3 = Q signal (Phase 4 /* Coin */)
    // ==================================================================
    ttl_7404 u_J5 (
        .pin1  (H64),       .pin2  (J5_g1_out),
        .pin3  (H64),       .pin4  (J5_g2_out),
        .pin5  (V32),       .pin6  (J5_g3_out),
        .pin9  (K4_g4),     .pin8  (J5_g4),
        .pin11 (V4),        .pin10 (J5_g5),
        .pin13 (LATCH_pin3),.pin12 (Q)
    );

    // ==================================================================
    // L5 - 7400 quad NAND
    //   Gate 1 (Phase 3 /* M4 */): pin1=H32, pin2=H256 -> pin3 = ~(H32 & H256) = L5_g1.
    //                              Drives H4 gate 2 input (= M4 path).
    //   Gate 2 (pin4=H32, pin5=~H64 -> pin6): ~(H32 & ~H64) for HSync.
    //   Gate 3 (pin9=D5./Q2, pin10=B1.pin8 -> pin8): drives J7./BI (digit blank gate).
    //   Gate 4 (pin12=H128, pin13=H256 -> pin11): ~(H128 & H256) drives B1.pin12.
    // ==================================================================
    ttl_7400 u_L5 (
        .pin1  (H32),       .pin2  (H256),        .pin3  (L5_g1),
        .pin4  (H32),       .pin5  (J5_g2_out),   .pin6  (L5_g2_out),
        .pin9  (D5_Q2_n_w), .pin10 (B1_pin8),     .pin8  (L5_g3_out),
        .pin12 (H128),      .pin13 (H256),        .pin11 (L5_g4_out)
    );

    // ==================================================================
    // J4 - 7408 quad AND
    //   Gate 1 (pin1=CLK_n, pin2=F8.pin8 -> pin3 = MAZE).  Phase 2.
    //   Gate 2 (Phase 5): pin4=F3.RCO, pin5=J2./Q2(Y) -> pin6 = J4_g2.
    //   Gate 3 (Phase 5): pin9=B2./Q2, pin10=ATTRACT_n -> pin8 = J4_g3
    //                     (drives B2 FF1 /PR1).
    //   Gate 4 (pin12=~H64, pin13=HBLANK -> pin11 = J4_g4_out): HSync FF /CLR.
    // ==================================================================
    ttl_7408 u_J4 (
        .pin1  (CLK_n),     .pin2  (F8_pin8),  .pin3  (J4_g1),
        .pin4  (F3_RCO),    .pin5  (J2_Q2_n),  .pin6  (J4_g2),
        .pin9  (B2_Q2_n),   .pin10 (ATTRACT_n),.pin8  (J4_g3),
        .pin12 (J5_g2_out), .pin13 (HBLANK_w), .pin11 (J4_g4_out)
    );

    // ==================================================================
    // F4 - 7474 dual D-FF (HSync + V64 latch).  Unchanged from Phase 0/1.
    // ==================================================================
    ttl_7474 u_F4 (
        .clk_sys (clk_sys),
        .pin1    (J4_g4_out),    // /CLR1
        .pin2    (L5_g2_out),    // D1
        .pin3    (H2),           // CK1
        .pin4    (VCC),          // /PR1
        .pin5    (HSYNC_w),      // Q1
        .pin6    (HSYNC_n_w),    // /Q1 = HSYNC_n
        .pin8    (F4_Q2_n_w),    // /Q2
        .pin9    (F4_Q2_w),      // Q2
        .pin10   (VCC),          // /PR2
        .pin11   (V64),          // CK2
        .pin12   (VCC),          // D2
        .pin13   (H6_Q2)         // /CLR2
    );

    // ==================================================================
    // ========== /* Playfield */  (gotcha.cpp lines 456-501) ===========
    // ==================================================================

    // D6 - 7400 quad NAND
    //   Gate 1 (Phase 2): pin1=CATCHOS_n, pin2=F8.pin8 -> pin3 = D6_g1.
    //                     Routed via F6 gate 4 to produce VIDEO[1].
    //   Gate 2 (Phase 1): pin4=H4, pin5=H8 -> pin6 = D6_g2 = ~(H4&H8).
    //   Gate 3 (Phase 4 /* Coin */): pin9=C6./Q1, pin10=START -> pin8 = D6_g3.
    //                                Drives C7./CLR2 — clears ATTRACT when
    //                                START is pressed during the right C6 state.
    //   Gate 4 (Phase 4 /* Coin */): pin12=ATTRACT, pin13=C6.Q1 -> pin11 = D6_g4.
    //                                Drives LATCH.pin1 (SET) — sets Q signal
    //                                during attract+C6 condition.
    ttl_7400 u_D6 (
        .pin1  (CATCHOS_n), .pin2  (F8_pin8), .pin3  (D6_g1),
        .pin4  (H4),        .pin5  (H8),      .pin6  (D6_g2),
        .pin9  (C6_Q1_n),   .pin10 (START),   .pin8  (D6_g3),
        .pin12 (ATTRACT),   .pin13 (C6_Q1),   .pin11 (D6_g4)
    );

    // E6 - 7427 triple 3-input NOR
    //   Gate 1 (Phase 2): pin1=V4, pin2=V8, pin13=~H16 -> pin12 = E6_g1_out.
    //   Gate 2 (Phase 1): D6_g2, F4./Q2, M5_g4 -> pin6 = E6_g2.
    //   Gate 3 (Phase 2): pin9=H8, pin10=H4, pin11=~H16 -> pin8 = E6_g3_out.
    ttl_7427 u_E6 (
        .pin1  (V4),       .pin2  (V8),       .pin13 (D7_pin6),  .pin12 (E6_g1_out),
        .pin3  (D6_g2),    .pin4  (F4_Q2_n_w),.pin5  (M5_g4),    .pin6  (E6_g2),
        .pin9  (H8),       .pin10 (H4),       .pin11 (D7_pin6),  .pin8  (E6_g3_out)
    );

    // K5 - 7486 quad XOR
    //   Gate 1 (Phase 1): pin1=H16, pin2=H256 -> pin3 = K5_g1.
    //   Gate 2 (Phase 2): pin4=H32, pin5=~V32 -> pin6 = K5_g2_out = H32 XOR ~V32.
    //   Gate 3 (Phase 3 /* M4 */): pin9=B4./Q2, pin10=V256 -> pin8 = K5_g3 = B4./Q2 XOR V256.
    //     NOTE: pin9 is B4's FF2 /Q2 (gotcha.cpp:605 "B4",6), NOT FF1's /Q1.  FF2 is
    //     the frame-deterministic playfield FF; using FF1 here injected a frame-parity
    //     term that made the M4 decoration flicker every frame.
    //   Gate 4 (Phase 4 /* Right Control */) stubbed.
    ttl_7486 u_K5 (
        .pin1  (H16),       .pin2  (H256),      .pin3  (K5_g1),
        .pin4  (H32),       .pin5  (J5_g3_out), .pin6  (K5_g2_out),
        .pin9  (B4_Q2_n),   .pin10 (V256),      .pin8  (K5_g3),
        .pin12 (GND),       .pin13 (GND),       .pin11 (nc_K5_g4)
    );

    // K4 - 7402 quad NOR
    //   Gate 1 (Phase 1): ~(H128 | K5_g1) = K4_g1.
    //   Gate 3 (Phase 5): pin8=B8.pin3, pin9=HLD1 -> pin10 = K4_g3.
    //   Gate 4 (Phase 1): ~(V256_n | ~V4)  = K4_g4.
    //   Gate 2 still stubbed.
    ttl_7402 u_K4 (
        .pin1  (K4_g1),    .pin2  (H128),     .pin3  (K5_g1),
        .pin4  (K4_g2_out),.pin5  (M2_Q2),    .pin6  (ATTRACT),  // g2: ~(M2.Q2|ATTRACT) -> M2 /PR1
        .pin8  (B8_pin3),  .pin9  (HLD1),     .pin10 (K4_g3),
        .pin11 (V256_n),   .pin12 (J5_g5),    .pin13 (K4_g4)
    );

    // C5 - 7400 quad NAND, all four gates form the maze-ink chain.
    ttl_7400 u_C5 (
        .pin1  (E6_g2),    .pin2  (K4_g1),    .pin3  (C5_g1),
        .pin4  (C5_g1),    .pin5  (C5_g3),    .pin6  (C5_g2),
        .pin9  (D5_Q2_w),  .pin10 (C5_g4),    .pin8  (C5_g3),
        .pin12 (J5_g4),    .pin13 (E4_g4),    .pin11 (C5_g4)
    );

    // B4 - 74107 dual JK FF.
    //   FF1 (Phase 3 /* M4 */): J1=B5./Q2, K1=VCC, CP1=V256, /CLR1=VCC.
    //                           Q1 (pin3) → B5 FF2 J2, /Q1 (pin6) → K5 gate 3.
    //   FF2 (Phase 1 playfield): J2=VCC, K2=GND, CP2=F4./Q2, /CLR2=~V4.
    ttl_74107 u_B4 (
        .clk_sys (clk_sys),
        .pin1    (B5_Q2_n),     // J1
        .pin2    (B4_Q1_n),     // /Q1
        .pin3    (B4_Q1),       // Q1
        .pin4    (VCC),         // K1
        .pin5    (B4_Q2),       // Q2
        .pin6    (B4_Q2_n),     // /Q2 -> K5 gate 3
        .pin8    (VCC),         // J2
        .pin9    (F4_Q2_n_w),   // CP2
        .pin10   (J5_g5),       // /CLR2 = ~V4
        .pin11   (GND),         // K2
        .pin12   (V256),        // CP1
        .pin13   (VCC)          // /CLR1
    );

    // E4 - 7400 quad NAND
    //   Gate 1 (Phase 5): pin1=VRESET, pin2=B2.Q1 -> pin3 = A_sig.
    //   Gate 2 (Phase 5): pin4=K4.g3, pin5=ATTRACT_n -> pin6 = E4_g6
    //                     (drives the CK pins of B2/B3/C2 FFs).
    //   Gate 3 (Phase 3 /* M4 */): pin9=C4.RCO, pin10=D4.RCO -> pin8 = E4_g3.
    //   Gate 4 (Phase 1 playfield): ~(B4.Q2 & V2) = E4_g4.
    ttl_7400 u_E4 (
        .pin1  (VRESET),  .pin2  (B2_Q1),   .pin3  (A_sig),
        .pin4  (K4_g3),   .pin5  (ATTRACT_n),.pin6 (E4_g6),
        .pin9  (C4_RCO),  .pin10 (D4_RCO),  .pin8  (E4_g3),
        .pin12 (B4_Q2),   .pin13 (V2),      .pin11 (E4_g4)
    );

    // H8 - 7404 hex inverter
    //   Inv 3 (Phase 2): pin5=V16    -> pin6  = ~V16        (H8_inv3)
    //   Inv 4 (Phase 2): pin9=E7.p8  -> pin8  = ~E7.pin8    (H8_inv4)
    //   Inv 5 (Phase 1): pin11=C5_g2 -> pin10 = ~C5_g2      (H8_inv5, F8.pin1)
    //   Inv 1, 2, 6 stubbed.
    ttl_7404 u_H8 (
        .pin1  (GND),    .pin2  (nc_H8_inv1),
        .pin3  (GND),    .pin4  (nc_H8_inv2),
        .pin5  (V16),    .pin6  (H8_inv3),
        .pin9  (E7_pin8),.pin8  (H8_inv4),
        .pin11 (C5_g2),  .pin10 (H8_inv5),
        .pin13 (GND),    .pin12 (nc_H8_inv6)
    );

    // ==================================================================
    // ============ /* M4 */ (gotcha.cpp lines 568-606) =================
    // Cross-coupled B4/B5 state machine clocked by V256 (once per frame),
    // feeding two cascaded 9316 counters (C4, D4) clocked by HSYNC_n_w.
    // The whole chain produces the M4 signal at H4 gate 2 — a periodic
    // pulse derived from the player-right position that gates the score
    // mux's decorative pattern in I7 (Phase 2).
    // ==================================================================

    // B5 - 74107 dual JK FF (M4 state machine)
    //   FF1: CP1=V256, J=K=VCC, /CLR=VCC.  Toggles each V256 negedge.
    //   FF2: CP2=V256, J=B4.Q1, K=VCC, /CLR=VCC.
    ttl_74107 u_B5 (
        .clk_sys (clk_sys),
        .pin1    (VCC),         // J1
        .pin2    (B5_Q1_n),     // /Q1
        .pin3    (B5_Q1),       // Q1
        .pin4    (VCC),         // K1
        .pin5    (B5_Q2),       // Q2
        .pin6    (B5_Q2_n),     // /Q2
        .pin8    (B4_Q1),       // J2
        .pin9    (V256),        // CP2
        .pin10   (VCC),         // /CLR2
        .pin11   (VCC),         // K2
        .pin12   (V256),        // CP1
        .pin13   (VCC)          // /CLR1
    );

    // C4 - 9316 sync binary counter (low nibble of M4 timer)
    //   Loads {1, 0, B5./Q2, B5.Q2} when /PE asserted by E4_g3 — i.e., the
    //   counter starts each cycle from value 9 or 10 depending on B5.Q2.
    //   Counts up on HSYNC_n_w rising edges (= once per line) while
    //   VBLANK_n_w is high (CET=1 during active video).
    ttl_9316 u_C4 (
        .clk_sys (clk_sys),
        .pin1    (VCC),         // /MR (no clear)
        .pin2    (HSYNC_n_w),   // CP
        .pin3    (B5_Q2),       // P0
        .pin4    (B5_Q2_n),     // P1
        .pin5    (GND),         // P2
        .pin6    (VCC),         // P3
        .pin7    (VCC),         // CEP
        .pin9    (E4_g3),       // /PE
        .pin10   (VBLANK_n_w),  // CET
        .pin11   (C4_Q[3]),     // Q3
        .pin12   (C4_Q[2]),     // Q2
        .pin13   (C4_Q[1]),     // Q1
        .pin14   (C4_Q[0]),     // Q0
        .pin15   (C4_RCO)       // TC
    );

    // D4 - 9316 sync binary counter (high nibble of M4 timer)
    //   Loads 0000 when /PE=0.  Cascaded with C4 via CEP = C4.RCO.
    ttl_9316 u_D4 (
        .clk_sys (clk_sys),
        .pin1    (VCC),         // /MR
        .pin2    (HSYNC_n_w),   // CP
        .pin3    (GND),         // P0
        .pin4    (GND),         // P1
        .pin5    (GND),         // P2
        .pin6    (GND),         // P3
        .pin7    (C4_RCO),      // CEP <- C4 carry
        .pin9    (E4_g3),       // /PE
        .pin10   (VCC),         // CET
        .pin11   (D4_Q[3]),     // Q3 -> H4 gate 2 input (M4)
        .pin12   (D4_Q[2]),
        .pin13   (D4_Q[1]),
        .pin14   (D4_Q[0]),
        .pin15   (D4_RCO)
    );

    // ==================================================================
    // ========== /* Play timer */ (gotcha.cpp lines 502-534) ===========
    // ==================================================================

    // K8 - 7490 play timer units (counts D8 ticks 0..9 once per second)
    ttl_7490 u_K8 (
        .clk_sys (clk_sys),
        .pin14   (D8_out),       // CKA
        .pin1    (K8_QA),        // CKB <- QA (self-cascade)
        .pin12   (K8_QA),        // QA
        .pin9    (K8_QB),        // QB
        .pin8    (K8_QC),        // QC
        .pin11   (K8_QD),        // QD
        .pin2    (START),        // R0_1
        .pin3    (START),        // R0_2
        .pin6    (GND),          // R9_1
        .pin7    (GND)           // R9_2
    );

    // L8 - 7490 play timer tens (clocked by K8.QD = ones rollover)
    ttl_7490 u_L8 (
        .clk_sys (clk_sys),
        .pin14   (K8_QD),
        .pin1    (L8_QA),
        .pin12   (L8_QA),
        .pin9    (L8_QB),
        .pin8    (L8_QC),
        .pin11   (L8_QD),
        .pin2    (START),
        .pin3    (START),
        .pin6    (GND),
        .pin7    (GND)
    );

    // G8 - 7490 catch counter low digit (clocked by CATCHOS_n - one-shot from B7)
    ttl_7490 u_G8 (
        .clk_sys (clk_sys),
        .pin14   (CATCHOS_n),
        .pin1    (G8_QA),
        .pin12   (G8_QA),
        .pin9    (G8_QB),
        .pin8    (G8_QC),
        .pin11   (G8_QD),
        .pin2    (START),
        .pin3    (START),
        .pin6    (GND),
        .pin7    (GND)
    );

    // J8 - 74107 catch counter high digit (toggles every G8.QD rollover, FF1
    //      drives FF2 via self-cascade pin3 -> pin9).
    ttl_74107 u_J8 (
        .clk_sys (clk_sys),
        .pin1    (VCC),          // J1
        .pin2    (J8_Q1_n),
        .pin3    (J8_Q1),
        .pin4    (VCC),          // K1
        .pin5    (J8_Q2),
        .pin6    (J8_Q2_n),
        .pin8    (VCC),          // J2
        .pin9    (J8_Q1),        // CP2 <- Q1 self-cascade
        .pin10   (START_n),      // /CLR2
        .pin11   (VCC),          // K2
        .pin12   (G8_QD),        // CP1
        .pin13   (START_n)       // /CLR1
    );

    // ==================================================================
    // ========== /* Playfield mux */ (gotcha.cpp lines 536-561) ========
    // ==================================================================

    // L7 - 74153 dual 4-to-1, picks one of {K8,L8,G8,J8} bit-A/bit-B per
    //      {H256, H32}.  Both enables tied to GND (always active).
    ttl_74153 u_L7 (
        .pin1  (GND),                                                   // /G1
        .pin15 (GND),                                                   // /G2
        .pin14 (H32),                                                   // SEL A
        .pin2  (H256),                                                  // SEL B
        .pin6  (J8_Q1), .pin5 (G8_QA), .pin4 (L8_QA), .pin3 (K8_QA),    // mux1 C0..C3
        .pin7  (L7_pin7),                                               // 1Y
        .pin10 (J8_Q2), .pin11 (G8_QB), .pin12 (L8_QB), .pin13 (K8_QB), // mux2 C0..C3
        .pin9  (L7_pin9)                                                // 2Y
    );

    // M7 - 74153 dual 4-to-1, picks bit-C/bit-D of the same counter row.
    //      C0 inputs are GND because J8's Q-bits beyond Q1/Q2 don't exist.
    ttl_74153 u_M7 (
        .pin1  (GND),
        .pin15 (GND),
        .pin14 (H32),
        .pin2  (H256),
        .pin6  (GND),   .pin5 (G8_QC), .pin4 (L8_QC), .pin3 (K8_QC),
        .pin7  (M7_pin7),
        .pin10 (GND),   .pin11 (G8_QD),.pin12 (L8_QD),.pin13 (K8_QD),
        .pin9  (M7_pin9)
    );

    // ==================================================================
    // ====== /* Playfield mux part 2 */ (gotcha.cpp lines 608-694) =====
    // ==================================================================

    // D7 - 7404 hex inverter.
    //   Inv 1 (Phase 4): pin1=COIN1 button → pin2 = COIN = ~COIN1 (active-high)
    //   Inv 3 (Phase 2): pin5=H16        → pin6 = ~H16 (digit decoder mask)
    //   Inv 5 (Phase 4): pin11=L8.QD     → pin10 = D7_pin10 (~L8.QD)
    //   Inv 6 (Phase 4): pin13=COIN      → pin12 = COIN_n (double-inverted button)
    //   Inv 2, 4 stubbed.
    ttl_7404 u_D7 (
        .pin1  (COIN1),  .pin2  (COIN),
        .pin3  (GND),    .pin4  (nc_D7_pin4),
        .pin5  (H16),    .pin6  (D7_pin6),
        .pin9  (GND),    .pin8  (nc_D7_pin8),
        .pin11 (L8_QD),  .pin10 (D7_pin10),
        .pin13 (COIN),   .pin12 (COIN_n)
    );

    // B1 - 7420 dual 4-input NAND.
    //   Gate 1 (Phase 5 /* Right Counters */): pin1=pin2=D1.RCO, pin4=G1.Q2,
    //     pin5=G1.Q3 -> pin6 = B1_g1 = VVIDEO1_n (feeds F1 gate 1 -> VIDEO1).
    //   Gate 2 (Phase 2): pin9=F4./Q2, pin10=~H64, pin12=L5_g4_out, pin13=V32
    //     -> pin8 = B1_pin8 (I7 BCD-source select).
    ttl_7420 u_B1 (
        .pin1  (D1_RCO), .pin2  (D1_RCO), .pin4 (G1_Q[2]), .pin5 (G1_Q[3]), .pin6 (B1_g1),
        .pin9  (F4_Q2_n_w), .pin10 (J5_g1_out), .pin12 (L5_g4_out), .pin13 (V32),
        .pin8  (B1_pin8)
    );

    // I7 - 74157 quad 2-to-1 mux.  SEL = B1.pin8.  When SEL=0 picks the
    //      counter mux outputs (L7/M7) — i.e., a BCD digit.  When SEL=1
    //      picks a {~V32, ~V16, H32^~V32, M4} pattern — a decorative
    //      stripe used outside the score windows.
    ttl_74157 u_I7 (
        .pin1  (B1_pin8),                                               // SEL
        .pin15 (GND),                                                   // /G strobe
        .pin2  (L7_pin7), .pin3  (J5_g3_out), .pin4  (I7_pin4),         // mux 1: 1A,1B,1Y
        .pin5  (L7_pin9), .pin6  (H8_inv3),   .pin7  (I7_pin7),         // mux 2: 2A,2B,2Y
        .pin11 (M7_pin7), .pin10 (K5_g2_out), .pin9  (I7_pin9),         // mux 3: 3A,3B,3Y
        .pin14 (M7_pin9), .pin13 (M4),        .pin12 (I7_pin12)         // mux 4: 4A,4B,4Y
    );

    // J7 - 7448 BCD-to-7-segment.
    //   BCD = {I7.pin12, I7.pin9, I7.pin7, I7.pin4} = {D,C,B,A}
    //   /LT = VCC, /RBI = H32, /BI = L5_g3_out (per-pixel digit blanking).
    ttl_7448 u_J7 (
        .pin3  (VCC),                                       // /LT
        .pin4  (L5_g3_out),                                 // /BI  <- L5.pin8
        .pin5  (H32),                                       // /RBI
        .pin7  (I7_pin4),                                   // A
        .pin1  (I7_pin7),                                   // B
        .pin2  (I7_pin9),                                   // C
        .pin6  (I7_pin12),                                  // D
        .pin13 (J7_pin13), .pin12 (J7_pin12), .pin11 (J7_pin11),  // a,b,c
        .pin10 (J7_pin10), .pin9  (J7_pin9),  .pin15 (J7_pin15),  // d,e,f
        .pin14 (J7_pin14)                                   // g
    );

    // ==================================================================
    // F8 NAND-combiner chain (E7/F7/H7 each contribute three NANDs).
    // gotcha.cpp lines 644-687.  The chain produces a single MAZE+SCORE
    // composite that becomes the picture once gated by HBLANK in F6.g4.
    // ==================================================================

    // E7 - 7410 triple 3-input NAND
    //   Gate 1 (Phase 2): J7.pin13(a), H8.pin6(~V16... actually H8 inv3 for V16
    //                     row select within the seg digit), E6.pin12 -> pin12.
    //   Gate 2 unused in Phase 2 (Phase 3 sound section).
    //   Gate 3 (Phase 2): pin9=V4, pin10=V8, pin11=H16 -> pin8 = ~(V4&V8&H16).
    ttl_7410 u_E7 (
        .pin1  (H8_inv3), .pin2  (J7_pin13), .pin13 (E6_g1_out), .pin12 (E7_pin12),
        .pin3  (GND),     .pin4  (GND),      .pin5  (GND),       .pin6  (),
        .pin9  (V4),      .pin10 (V8),       .pin11 (H16),       .pin8  (E7_pin8)
    );

    // F7 - 7410 triple 3-input NAND
    //   Gate 1: pin1=J7.pin14(g), pin2=H8.pin6(~V16 inv4), pin13=H8.pin8(inv4) -> pin12.
    //   Gate 2: pin3=H8.pin6, pin4=F6.pin1, pin5=J7.pin12(b) -> pin6.
    //   Gate 3: pin9=J7.pin10(d), pin10=V16, pin11=H8.pin8 -> pin8.
    ttl_7410 u_F7 (
        .pin1  (J7_pin14), .pin2  (H8_inv3),  .pin13 (H8_inv4),  .pin12 (F7_pin12),
        .pin3  (H8_inv3),  .pin4  (F6_pin1),  .pin5  (J7_pin12), .pin6  (F7_pin6),
        .pin9  (J7_pin10), .pin10 (V16),      .pin11 (H8_inv4),  .pin8  (F7_pin8)
    );

    // H7 - 7410 triple 3-input NAND
    //   Gate 1: pin1=H8.pin6, pin2=J7.pin15(f), pin13=E6.pin8 -> pin12.
    //   Gate 2: pin3=V16, pin4=F6.pin1, pin5=J7.pin11(c) -> pin6.
    //   Gate 3: pin9=J7.pin9(e), pin10=V16, pin11=E6.pin8 -> pin8.
    ttl_7410 u_H7 (
        .pin1  (H8_inv3),  .pin2  (J7_pin15), .pin13 (E6_g3_out), .pin12 (H7_pin12),
        .pin3  (V16),      .pin4  (F6_pin1),  .pin5  (J7_pin11),  .pin6  (H7_pin6),
        .pin9  (J7_pin9),  .pin10 (V16),      .pin11 (E6_g3_out), .pin8  (H7_pin8)
    );

    // F8 - 7430 8-input NAND, final maze+score combiner.
    //   Inputs: H8_inv5 (~maze), and seven gate outputs from E7/F7/H7
    //   carrying the active-high segment-row signals.  Output F8.pin8 is
    //   LOW when all 8 inputs are HIGH — i.e., when the segment + maze +
    //   stripe should all be lit.
    ttl_7430 u_F8 (
        .pin1  (H8_inv5),  .pin2  (F7_pin8),  .pin3  (F7_pin6),
        .pin4  (H7_pin6),  .pin5  (H7_pin12), .pin6  (H7_pin8),
        .pin11 (F7_pin12), .pin12 (E7_pin12),
        .pin8  (F8_pin8)
    );

    // ==================================================================
    // ============ /* Coin */ (gotcha.cpp lines 412-455) ===============
    // Generates ATTRACT, START, COIN, and the Q gate from the coin-input
    // button + start-button + a power-on LATCH.  Replaces the Phase 2
    // stubs for ATTRACT_n / START / START_n / CATCHOS_n.
    // ==================================================================

    // B7 - 9602 dual retriggerable one-shot.
    //   Half A (Phase 4): TRIG1=GND, TRIG2=COIN_n, /RST=VCC.
    //                     Fires ~7.3ms pulse on rising COIN.  /Q (pin7) → K7.CK1.
    //   Half B (Phase 4): TRIG1=START, TRIG2=A10.pin8 (stubbed VCC until /* Sound */),
    //                     /RST=ATTRACT_n.  Fires ~728ms pulse — the CATCHOS one-shot.
    //                     With A10.pin8 stubbed HIGH, TRIG=START|~VCC=START, so for now
    //                     the pulse will fire whenever START rises.  Once /* Sound */
    //                     is wired, A10 will gate this properly.
    // Pulse widths from gotcha.cpp:14 b7_desc(47k,0.5µF,47k,50µF) → 7.3ms / 728ms
    // at clk_sys=28.63636 MHz → 209000 / 20864000 cycles.
    ttl_9602 #(
        .PULSE_A_CYCLES(32'd209_000),
        .PULSE_B_CYCLES(32'd20_864_000)
    ) u_B7 (
        .clk_sys (clk_sys),
        .pin3    (VCC),            // /1RST
        .pin4    (GND),             // 1TR
        .pin5    (COIN_n),          // /1TR
        .pin6    (B7_pin6),         // 1Q (unused)
        .pin7    (B7_pin7),         // /1Q → K7.CK1
        .pin11   (A10_pin8),         // /2TR = A10 CATCHOS latch Q (Phase 7)
        .pin12   (START),           // 2TR
        .pin13   (ATTRACT_n),       // /2RST
        .pin10   (B7_CATCHOS),      // 2Q  = CATCHOS
        .pin9    (B7_CATCHOS_n)     // /2Q = CATCHOS_n
    );

    // K7 - 7474 dual D-FF.  FF1 (Phase 4 /* Coin */): latches "coin was held
    //   through B7's debounce window".  FF2 unused in /* Coin */.
    //     FF1: D = COIN, CK = B7.pin7 (= /Q of half A, rises at pulse end),
    //          /CLR = COIN (clears when no coin held), /PR = VCC.
    ttl_7474 u_K7 (
        .clk_sys (clk_sys),
        .pin1    (COIN),         // /CLR1 = COIN (held HIGH while coin pressed)
        .pin2    (COIN),         // D1
        .pin3    (B7_pin7),      // CK1
        .pin4    (VCC),          // /PR1
        .pin5    (K7_Q1),        // Q1
        .pin6    (K7_Q1_n),      // /Q1
        .pin8    (),             // /Q2 unused
        .pin9    (),             // Q2 unused
        .pin10   (VCC),          // /PR2
        .pin11   (GND),          // CK2 unused
        .pin12   (GND),          // D2 unused
        .pin13   (VCC)           // /CLR2 unused
    );

    // LATCH - DICE power-on SR latch.  Initially Q=0, rises to 1 ~1µs after
    //   reset, then SR-latches: pin1=/SET=D6_g4 (= ~(ATTRACT & C6.Q1)),
    //   pin2=/RESET=K7./Q1 (= ~K7.Q1).  Output pin3 feeds J5 inv 6 → Q.
    ttl_latch u_LATCH (
        .clk_sys (clk_sys),
        .pin1    (D6_g4),        // /SET
        .pin2    (K7_Q1_n),      // /RESET
        .pin3    (LATCH_pin3)
    );

    // B6 - 7474 dual D-FF.  Generates START / START_n state machine.
    //     FF1 (START): D = B6.Q2 (cross-feedback from FF2), CK = V256,
    //                  /CLR = COIN_n, /PR = VCC.
    //     FF2:         D = ATTRACT, CK = START1 (button), /CLR = B6./Q1, /PR = VCC.
    ttl_7474 u_B6 (
        .clk_sys (clk_sys),
        .pin1    (COIN_n),       // /CLR1
        .pin2    (B6_Q2),        // D1
        .pin3    (V256),         // CK1
        .pin4    (VCC),          // /PR1
        .pin5    (START),        // Q1 (= "B6", 5)
        .pin6    (START_n),      // /Q1 (= "B6", 6)
        .pin8    (B6_Q2_n),      // /Q2
        .pin9    (B6_Q2),        // Q2
        .pin10   (VCC),          // /PR2
        .pin11   (START1),       // CK2 (= raw start button)
        .pin12   (ATTRACT),      // D2
        .pin13   (START_n)       // /CLR2 = /Q1 self-feedback (= START_n)
    );

    // C6 - 7474 dual D-FF.  Attract-mode helper state machine.
    //     FF1: D = C6.Q2, CK = ATTRACT, /CLR = K7./Q1, /PR = Q.
    //     FF2: D = VCC,  CK = ATTRACT, /CLR = K7./Q1, /PR = VCC.
    //   On rising edge of ATTRACT both FFs update; the resulting C6.Q1/Q2
    //   pattern gates the LATCH set and the START-clears-ATTRACT path.
    ttl_7474 u_C6 (
        .clk_sys (clk_sys),
        .pin1    (K7_Q1_n),      // /CLR1
        .pin2    (C6_Q2),        // D1
        .pin3    (ATTRACT),      // CK1
        .pin4    (Q),            // /PR1
        .pin5    (C6_Q1),        // Q1
        .pin6    (C6_Q1_n),      // /Q1
        .pin8    (C6_Q2_n),      // /Q2
        .pin9    (C6_Q2),        // Q2
        .pin10   (VCC),          // /PR2
        .pin11   (ATTRACT),      // CK2
        .pin12   (VCC),          // D2
        .pin13   (K7_Q1_n)       // /CLR2
    );

    // C7 - 7474 dual D-FF.  FF2 generates ATTRACT/ATTRACT_n.  FF1 unused.
    //     FF2: D = VCC, CK = D7.pin10 (= ~L8.QD, fires when play-timer tens
    //                rolls 9→0), /PR = Q (LATCH-derived), /CLR = D6.pin8 (D6_g3).
    //   Initial state: Q=1 (LATCH starts low → J5 inv6 outputs Q=1 → /PR2=1).
    //   Wait, /PR is active-LOW.  Q=0 (post-init LATCH high → J5 outputs 0) →
    //                /PR2=0 → forces ATTRACT=1 (attract on at power-on).
    ttl_7474 u_C7 (
        .clk_sys (clk_sys),
        .pin1    (VCC),          // /CLR1 (FF1 unused)
        .pin2    (GND),          // D1
        .pin3    (GND),          // CK1
        .pin4    (VCC),          // /PR1
        .pin5    (C7_Q2_unused), // Q1 unused
        .pin6    (C7_Q2_n_unused),
        .pin8    (ATTRACT_n),    // /Q2 = ATTRACT_n
        .pin9    (ATTRACT),      // Q2  = ATTRACT
        .pin10   (Q),            // /PR2 = Q signal (forces ATTRACT=1 when Q=0)
        .pin11   (D7_pin10),     // CK2 = ~L8.QD (rises when L8 rolls over)
        .pin12   (VCC),          // D2
        .pin13   (D6_g3)         // /CLR2 = D6 gate 3 output
    );

    // ==================================================================
    // ===== /* Right Control */ + /* Right Counters */ ==================
    // ===== (gotcha.cpp lines 697-884) ==================================
    // Right player: joystick (STICK1) gated by player-speed S drives a pair
    // of D-FF "direction memories" (B2/B3/C2) whose outputs feed two cascaded
    // 9316 position counters — E3/F3 (horizontal) and G1/D1 (vertical).  When
    // the counters reach the player's screen position the F1 NOR fires
    // VIDEO1.  BUMP1 (player↔maze collision) gates the B8 90ms one-shot.
    // ==================================================================

    // D3 - 7402 quad NOR
    //   g1: pin2=ATTRACT,  pin3=B3.Q1   -> pin1  = D3_pin1  -> B3 FF2 /PR2
    //   g2: pin5=VRESET_n, pin6=D2.pin6 -> pin4  = B_sig ("B") -> E3.P1
    //   g3: pin8=J,        pin9=BUMP1   -> pin10 = D3_pin10 -> C3 FF2 CK2
    //   g4: pin11=BUMP1,   pin12=~J     -> pin13 = D3_pin13 -> C3 FF1 CK1
    ttl_7402 u_D3 (
        .pin1  (D3_pin1),  .pin2  (ATTRACT),  .pin3  (B3_Q1),
        .pin4  (B_sig),    .pin5  (VRESET_n), .pin6  (D2_pin6),
        .pin8  (J_sig),    .pin9  (BUMP1),    .pin10 (D3_pin10),
        .pin11 (BUMP1),    .pin12 (H1_pin4),  .pin13 (D3_pin13)
    );

    // H1 - 7404 hex inverter.  Right: Inv 2 J->~J, Inv 4 PRES->~PRES, Inv 6 L->~L.
    //   Left (Phase 6): Inv 1 K->~K (-> K3.6), Inv 3 L1.Q3->~ (-> J1.5),
    //   Inv 5 F1.13->~ (-> J1.10).
    ttl_7404 u_H1 (
        .pin1  (K2_pin3),  .pin2  (H1_pin2),
        .pin3  (J_sig),    .pin4  (H1_pin4),
        .pin5  (L1_Q[3]),  .pin6  (H1_pin6),
        .pin9  (PRES),     .pin8  (H1_pin8),
        .pin11 (F1_pin13), .pin10 (H1_pin10),
        .pin13 (G1_Q[1]),  .pin12 (H1_pin12)
    );

    // C3 - 7474 dual D-FF.  Both FFs D=VCC, /PR=VCC, /CLR=VRESET_n.
    //   FF1 CK = D3_pin13 (BUMP1/~J edge);  FF2 CK = D3_pin10 (J/BUMP1 edge).
    ttl_7474 u_C3 (
        .clk_sys (clk_sys),
        .pin1  (VRESET_n), .pin2  (VCC),      .pin3  (D3_pin13), .pin4  (VCC),
        .pin5  (C3_Q1),    .pin6  (C3_Q1_n),
        .pin8  (C3_Q2_n),  .pin9  (C3_Q2),
        .pin10 (VCC),      .pin11 (D3_pin10), .pin12 (VCC),      .pin13 (VRESET_n)
    );

    // A1 - 7402 quad NOR.  Each gate NORs a STICK1 direction with the player
    //   speed S (= B5.Q2): output is HIGH only when that direction is pressed
    //   AND S is low.  STICK1[0]=R, [1]=L, [2]=D, [3]=U.
    ttl_7402 u_A1 (
        .pin1  (A1_pin1),   .pin2  (STICK1[0]), .pin3  (B5_Q2),
        .pin4  (A1_pin4),   .pin5  (STICK1[1]), .pin6  (B5_Q2),
        .pin8  (STICK1[3]), .pin9  (B5_Q2),     .pin10 (A1_pin10),
        .pin11 (STICK1[2]), .pin12 (B5_Q2),     .pin13 (A1_pin13)
    );

    // B2 - 7474 dual D-FF (right-player horizontal direction memory).
    //   FF1: D=A1.pin1, CK=E4_g6, /CLR=VCC, /PR=J4_g3.
    //   FF2: D=A1.pin4, CK=E4_g6, /CLR=VCC, /PR=C3.Q2_n.
    ttl_7474 u_B2 (
        .clk_sys (clk_sys),
        .pin1  (VCC),      .pin2  (A1_pin1),  .pin3  (E4_g6),    .pin4  (J4_g3),
        .pin5  (B2_Q1),    .pin6  (B2_Q1_n),
        .pin8  (B2_Q2_n),  .pin9  (B2_Q2),
        .pin10 (C3_Q2_n),  .pin11 (E4_g6),    .pin12 (A1_pin4),  .pin13 (VCC)
    );

    // B3 - 7474 dual D-FF (right-player vertical direction memory).
    //   FF1: D=A1.pin13, CK=E4_g6, /CLR=VCC, /PR=C3.Q1_n.
    //   FF2: D=A1.pin10, CK=E4_g6, /CLR=VCC, /PR=D3.pin1.  Q2 = "C".
    ttl_7474 u_B3 (
        .clk_sys (clk_sys),
        .pin1  (VCC),      .pin2  (A1_pin13), .pin3  (E4_g6),    .pin4  (C3_Q1_n),
        .pin5  (B3_Q1),    .pin6  (B3_Q1_n),
        .pin8  (B3_Q2_n),  .pin9  (B3_Q2),
        .pin10 (D3_pin1),  .pin11 (E4_g6),    .pin12 (A1_pin10), .pin13 (VCC)
    );

    // C2 - 7474 dual D-FF.
    //   FF1: D=L (G1.Q1), CK=C3.Q1, /CLR=E4_g6, /PR=VCC.
    //   FF2: D=M (E3.Q2), CK=C3.Q2, /CLR=VCC,   /PR=E4_g6.
    ttl_7474 u_C2 (
        .clk_sys (clk_sys),
        .pin1  (E4_g6),    .pin2  (G1_Q[1]),  .pin3  (C3_Q1),    .pin4  (VCC),
        .pin5  (C2_Q1),    .pin6  (C2_Q1_n),
        .pin8  (C2_Q2_n),  .pin9  (C2_Q2),
        .pin10 (E4_g6),    .pin11 (C3_Q2),    .pin12 (E3_Q[2]),  .pin13 (VCC)
    );

    // D2 - 7486 quad XOR.
    //   g2: B2./Q2 ^ C2./Q2 -> D2_pin6 (-> D3 g2).
    //   g3: B3./Q1 ^ C2.Q1  -> D_sig ("D").  (gotcha.cpp:774: "B3",6 = FF1 /Q1.)
    //   g1 (Phase 7): Y(J2./Q2) ^ J2.Q1  -> D2_pin3  -> PROXIMITY in[0]
    //   g4 (Phase 7): K1.Q3   ^ X(D1.Q3) -> D2_pin11 -> PROXIMITY in[1]
    ttl_7486 u_D2 (
        .pin1  (J2_Q2_n),  .pin2  (J2_Q1),    .pin3  (D2_pin3),
        .pin4  (B2_Q2_n),  .pin5  (C2_Q2_n),  .pin6  (D2_pin6),
        .pin9  (B3_Q1_n),  .pin10 (C2_Q1),    .pin8  (D_sig),
        .pin12 (K1_Q[3]),  .pin13 (D1_Q[3]),  .pin11 (D2_pin11)
    );

    // E5 - 7430 8-input NAND -> PRES.  Inputs: H6./Q1, M1(~V32), V8, V128,
    //   M2(~V16), V64, CATCHOS, V256_n.
    ttl_7430 u_E5 (
        .pin1  (H6_Q1_n),    .pin2  (J5_g3_out), .pin3  (V8),
        .pin4  (V128),       .pin5  (H8_inv3),   .pin6  (V64),
        .pin8  (PRES),
        .pin11 (B7_CATCHOS), .pin12 (V256_n)
    );

    // E1 - 7400 quad NAND.
    //   g1: VIDEO1 & VIDEO2     -> pin3  = CATCH_n
    //   g2 (Phase 6): L1.RCO & K1.RCO -> pin6 = E1_pin6 (-> L1/K1 /PE)
    //   g3: G1.RCO & D1.RCO     -> pin8  = E1_pin8  (-> G1/D1 /PE)
    //   g4: ~PRES & START       -> pin11 = OO
    ttl_7400 u_E1 (
        .pin1  (VIDEO1),   .pin2  (VIDEO2),   .pin3  (CATCH_n),
        .pin4  (L1_RCO),   .pin5  (K1_RCO),   .pin6  (E1_pin6),
        .pin9  (G1_RCO),   .pin10 (D1_RCO),   .pin8  (E1_pin8),
        .pin12 (H1_pin8),  .pin13 (START),    .pin11 (OO)
    );

    // B8 - 555 monostable, ~90ms (R=82k, C=1µF).  /TR=BUMP1, /RST=VCC.
    //   Fires when BUMP1 falls (right player touches a maze wall).
    ttl_555_mono #(.PULSE_CYCLES(32'd2_579_750)) u_B8 (
        .clk_sys (clk_sys),
        .pin2 (BUMP1),
        .pin3 (B8_pin3),
        .pin4 (VCC)
    );

    // ---- /* Right Counters */ ----------------------------------------

    // E3 - 9316 right-player horizontal position, low nibble.
    //   CP=CLK, /MR=OO, /PE=HLD1(E2.pin8), CET=HBLANK_n, CEP=VCC.
    //   Parallel-load value {VCC,GND,B,A}.
    ttl_9316 u_E3 (
        .clk_sys (clk_sys),
        .pin1  (OO),        .pin2  (CLK),
        .pin3  (A_sig),     .pin4  (B_sig),     .pin5  (GND),      .pin6  (VCC),
        .pin7  (VCC),       .pin9  (HLD1),      .pin10 (HBLANK_n_w),
        .pin11 (E3_Q[3]),   .pin12 (E3_Q[2]),   .pin13 (E3_Q[1]),  .pin14 (E3_Q[0]),
        .pin15 (E3_RCO)
    );

    // F3 - 9316 right-player horizontal position, high nibble.
    //   CP=CLK (same as E3), CEP=E3.RCO -> synchronous carry, no ripple lag.
    ttl_9316 u_F3 (
        .clk_sys (clk_sys),
        .pin1  (OO),        .pin2  (CLK),
        .pin3  (GND),       .pin4  (GND),       .pin5  (GND),      .pin6  (VCC),
        .pin7  (E3_RCO),    .pin9  (HLD1),      .pin10 (VCC),
        .pin11 (F3_Q[3]),   .pin12 (F3_Q[2]),   .pin13 (F3_Q[1]),  .pin14 (F3_Q[0]),
        .pin15 (F3_RCO)
    );

    // J2 - 74107 dual JK FF.
    //   FF1 (Phase 6, left "X"): schematic clocks CP1 from H3.RCO; converted to
    //     the same synchronous form as FF2 — CP1 = CLK_n, J1=K1 = H3.RCO & J3.RCO
    //     (the condition under which H3 rolls 15->0), /CLR1 = PRES.  Q1 -> J1.1.
    //   FF2 ("Y"): the schematic clocks CP2 from F3.RCO; to keep it atomic
    //     with the CLK-synchronous E3/F3 chain we instead clock CP2 = CLK_n
    //     (so the 74107's negedge trigger lands on the CLK posedge that E3/F3
    //     count on) and gate J2=K2 with J2_carry = F3.RCO & E3.RCO — the
    //     exact condition under which F3 rolls 15->0.  Functionally identical
    //     to the F3.RCO ripple, but no inter-chip lag.  (Same trick as J6.FF2
    //     for H256.)
    assign J2_carry   = F3_RCO & E3_RCO;
    assign J2_carry_L = H3_RCO & J3_RCO;
    ttl_74107 u_J2 (
        .clk_sys (clk_sys),
        .pin1    (J2_carry_L),// J1  = left carry (atomic with H3/J3)
        .pin2    (J2_Q1_n),
        .pin3    (J2_Q1),     // Q1 = left "X" -> J1.1
        .pin4    (J2_carry_L),// K1
        .pin5    (J2_Q2),     // Q2
        .pin6    (J2_Q2_n),   // /Q2 = "Y"
        .pin8    (J2_carry),  // J2
        .pin9    (CLK_n),     // CP2 = CLK_n (atomic with E3/F3)
        .pin10   (OO),        // /CLR2
        .pin11   (J2_carry),  // K2
        .pin12   (CLK_n),     // CP1 = CLK_n (atomic with H3/J3)
        .pin13   (PRES)       // /CLR1
    );

    // E2 - 7400 quad NAND.
    //   g1: J & E2.g4         -> pin3  = E2_pin3  (-> H2 g2)
    //   g2: ~L & G1.Q0        -> pin6  = J ("J")
    //   g3: J4.g2 & E3.RCO    -> pin8  = HLD1     (-> E3/F3 /PE)
    //   g4: E3.Q0 & E3.Q1     -> pin11 = E2_pin11 (-> E2 g1)
    ttl_7400 u_E2 (
        .pin1  (J_sig),    .pin2  (E2_pin11), .pin3  (E2_pin3),
        .pin4  (H1_pin12), .pin5  (G1_Q[0]),  .pin6  (J_sig),
        .pin9  (J4_g2),    .pin10 (E3_RCO),   .pin8  (HLD1),
        .pin12 (E3_Q[0]),  .pin13 (E3_Q[1]),  .pin11 (E2_pin11)
    );

    // F2 - 7474 dual D-FF, both clocked by CLK.
    //   FF1: D = F2./Q2, /CLR=VCC, /PR=VCC.
    //   FF2: D = M (E3.Q2), /CLR = M, /PR = VCC.
    ttl_7474 u_F2 (
        .clk_sys (clk_sys),
        .pin1  (VCC),      .pin2  (F2_Q2_n),  .pin3  (CLK),      .pin4  (VCC),
        .pin5  (F2_Q1),    .pin6  (F2_Q1_n),
        .pin8  (F2_Q2_n),  .pin9  (F2_Q2),
        .pin10 (VCC),      .pin11 (CLK),      .pin12 (E3_Q[2]),  .pin13 (E3_Q[2])
    );

    // H2 - 7420 dual 4-input NAND.
    //   Gate 2 (right): E3.Q3 & F2.Q1 & J4.g2 & E2.g1 -> H2_pin8 (-> F1 g1).
    //   Gate 1 (left, Phase 6): J3.Q3 & J3.Q2 & H3.RCO & J2.Q1 -> H2_g1_out (-> F1.5).
    ttl_7420 u_H2 (
        .pin1  (J3_Q[3]), .pin2  (J3_Q[2]), .pin4 (H3_RCO),  .pin5 (J2_Q1),    .pin6 (H2_g1_out),
        .pin9  (E3_Q[3]), .pin10 (F2_Q1),   .pin12 (J4_g2),  .pin13 (E2_pin3),
        .pin8  (H2_pin8)
    );

    // G1 - 9316 right-player vertical position, low nibble.
    //   CP=HSYNC_n, /MR=OO, /PE=E1_pin8, CET=VBLANK_n, CEP=VCC.
    //   Parallel-load value {VCC,GND,D,C}.
    ttl_9316 u_G1 (
        .clk_sys (clk_sys),
        .pin1  (OO),        .pin2  (HSYNC_n_w),
        .pin3  (B3_Q2),     .pin4  (D_sig),     .pin5  (GND),      .pin6  (VCC),
        .pin7  (VCC),       .pin9  (E1_pin8),   .pin10 (VBLANK_n_w),
        .pin11 (G1_Q[3]),   .pin12 (G1_Q[2]),   .pin13 (G1_Q[1]),  .pin14 (G1_Q[0]),
        .pin15 (G1_RCO)
    );

    // D1 - 9316 right-player vertical position, high nibble.
    //   CP=HSYNC_n (same as G1), CEP=G1.RCO -> synchronous carry.
    ttl_9316 u_D1 (
        .clk_sys (clk_sys),
        .pin1  (OO),        .pin2  (HSYNC_n_w),
        .pin3  (GND),       .pin4  (GND),       .pin5  (GND),      .pin6  (GND),
        .pin7  (G1_RCO),    .pin9  (E1_pin8),   .pin10 (VCC),
        .pin11 (D1_Q[3]),   .pin12 (D1_Q[2]),   .pin13 (D1_Q[1]),  .pin14 (D1_Q[0]),
        .pin15 (D1_RCO)
    );

    // F1 - 7402 quad NOR.
    //   g1: B1.g1(VVIDEO1_n) NOR H2.pin8 -> pin1 = VIDEO1 (right player pixel)
    //   g2 (Phase 6): H2.g1 NOR J1.g2 -> pin4 = VIDEO2 (left player pixel)
    //   g4 (Phase 6): K2.11 NOR K2.3  -> pin13 = F1.13 (-> H1 inv5, BUMP2 path)
    ttl_7402 u_F1 (
        .pin1  (VIDEO1),    .pin2  (B1_g1),    .pin3  (H2_pin8),
        .pin4  (VIDEO2),    .pin5  (H2_g1_out),.pin6  (J1_pin6),
        .pin8  (GND),       .pin9  (GND),      .pin10 (nc_F1_g3),
        .pin11 (K2_pin11),  .pin12 (K2_pin3),  .pin13 (F1_pin13)
    );

    // ==================================================================
    // ===== /* Left Control */ + /* Left Counters */ ===================
    // ===== (gotcha.cpp lines 885-1059) ================================
    // Mirror of the Right player.  Left joystick = STICK2.  Direction-memory
    // FFs M3/M2/L2 are strobed by M4c_pin11 (= C8|HLD2 in play, the mirror of
    // E4_g6 = B8|HLD1).  Position counters J3/H3 (horizontal) and L1/K1
    // (vertical) feed F1 gate 2 -> VIDEO2.  C8 is the left collision one-shot.
    // ==================================================================

    // K3 - 7402 quad NOR (mirror D3).
    //   g1: K NOR BUMP2          -> pin1  = K3_pin1  -> L3 FF1 CK
    //   g2: BUMP2 NOR ~K(H1.2)   -> pin4  = K3_pin4  -> L3 FF2 CK
    //   g3: K2.8 NOR VRESET_n    -> pin10 = K3_pin10 = "F" (J3.P1 load)
    //   g4: M3.Q1 NOR ATTRACT    -> pin13 = K3_pin13 -> M3 FF2 /CLR2
    ttl_7402 u_K3 (
        .pin1  (K3_pin1),  .pin2  (K2_pin3),  .pin3  (BUMP2),
        .pin4  (K3_pin4),  .pin5  (BUMP2),    .pin6  (H1_pin2),
        .pin8  (K2_pin8),  .pin9  (VRESET_n), .pin10 (K3_pin10),
        .pin11 (M3_Q1),    .pin12 (ATTRACT),  .pin13 (K3_pin13)
    );

    // L3 - 7474 dual D-FF (mirror C3).  Both FFs D=VCC, /PR=VCC, /CLR=VRESET_n.
    //   FF1 CK = K3.1;  FF2 CK = K3.4.
    ttl_7474 u_L3 (
        .clk_sys (clk_sys),
        .pin1  (VRESET_n), .pin2  (VCC),      .pin3  (K3_pin1),  .pin4  (VCC),
        .pin5  (L3_Q1),    .pin6  (L3_Q1_n),
        .pin8  (L3_Q2_n),  .pin9  (L3_Q2),
        .pin10 (VCC),      .pin11 (K3_pin4),  .pin12 (VCC),      .pin13 (VRESET_n)
    );

    // M1 - 7402 quad NOR (left joystick gates, mirror A1).  STICK2[0]=R,[1]=L,
    //   [2]=D,[3]=U; each NORed with player speed S (= B5_Q2).
    ttl_7402 u_M1 (
        .pin1  (M1_pin1),   .pin2  (STICK2[1]), .pin3  (B5_Q2),
        .pin4  (M1_pin4),   .pin5  (STICK2[0]), .pin6  (B5_Q2),
        .pin8  (STICK2[2]), .pin9  (B5_Q2),     .pin10 (M1_pin10),
        .pin11 (STICK2[3]), .pin12 (B5_Q2),     .pin13 (M1_pin13)
    );

    // M3 - 7474 dual D-FF (left horizontal direction memory, mirror B2).
    //   FF1: D=M1.1,  CK=M4c_pin11, /CLR=VCC,      /PR=L3.8(/Q2).
    //   FF2: D=M1.4,  CK=M4c_pin11, /CLR=K3.13,    /PR=VCC.   Q2 = M4-chip "E".
    ttl_7474 u_M3 (
        .clk_sys (clk_sys),
        .pin1  (VCC),      .pin2  (M1_pin1),  .pin3  (M4c_pin11), .pin4  (L3_Q2_n),
        .pin5  (M3_Q1),    .pin6  (M3_Q1_n),
        .pin8  (M3_Q2_n),  .pin9  (M3_Q2),
        .pin10 (K3_pin13), .pin11 (M4c_pin11),.pin12 (M1_pin4),   .pin13 (VCC)
    );

    // M2 - 7474 dual D-FF (left vertical direction memory, mirror B3).
    //   FF1: D=M1.13, CK=M4c_pin11, /CLR=VCC,      /PR=K4.g2.
    //   FF2: D=M1.10, CK=M4c_pin11, /CLR=L3.6(/Q1),/PR=VCC.  Q1 = "G".
    ttl_7474 u_M2 (
        .clk_sys (clk_sys),
        .pin1  (VCC),      .pin2  (M1_pin13), .pin3  (M4c_pin11), .pin4  (K4_g2_out),
        .pin5  (M2_Q1),    .pin6  (M2_Q1_n),
        .pin8  (M2_Q2_n),  .pin9  (M2_Q2),
        .pin10 (L3_Q1_n),  .pin11 (M4c_pin11),.pin12 (M1_pin10),  .pin13 (VCC)
    );

    // L2 - 7474 dual D-FF (mirror C2).
    //   FF1: D=N(L1.Q1), CK=L3.5(Q1), /CLR=M4c_pin11, /PR=VCC.
    //   FF2: D=O(J3.Q1), CK=L3.9(Q2), /CLR=VCC,        /PR=M4c_pin11.
    ttl_7474 u_L2 (
        .clk_sys (clk_sys),
        .pin1  (M4c_pin11),.pin2  (L1_Q[1]),  .pin3  (L3_Q1),    .pin4  (VCC),
        .pin5  (L2_Q1),    .pin6  (L2_Q1_n),
        .pin8  (L2_Q2_n),  .pin9  (L2_Q2),
        .pin10 (M4c_pin11),.pin11 (L3_Q2),    .pin12 (J3_Q[1]),  .pin13 (VCC)
    );

    // K2 - 7486 quad XOR (mirror D2).
    //   g1: L1.Q1 ^ L1.Q0 -> pin3  = K2_pin3  = "K"
    //   g2: L2.5  ^ M2.8   -> pin6  = K2_pin6  = "H" (L1.P1 load)
    //   g3: L2.8  ^ M3.6   -> pin8  = K2_pin8  (-> K3.8 -> "F")
    //   g4: J3.Q1 ^ J3.Q0  -> pin11 = K2_pin11 (-> F1.11)
    ttl_7486 u_K2 (
        .pin1  (L1_Q[1]),  .pin2  (L1_Q[0]),  .pin3  (K2_pin3),
        .pin4  (L2_Q1),    .pin5  (M2_Q2_n),  .pin6  (K2_pin6),
        .pin9  (L2_Q2_n),  .pin10 (M3_Q1_n),  .pin8  (K2_pin8),
        .pin12 (J3_Q[1]),  .pin13 (J3_Q[0]),  .pin11 (K2_pin11)
    );

    // M4 (chip) - 7400 quad NAND (mirror E4; distinct from the M4 *net* = H4.6).
    //   g3: M3.Q2 & VRESET   -> pin8  = E_sig ("E", J3.P0 load)
    //   g4: L4.g2 & ATTRACT_n-> pin11 = M4c_pin11 (left dir strobe = C8|HLD2)
    //   g1 (Phase 7): L4.1 & V8     -> pin3 = M4c_pin3 (proximity audio source)
    //   g2 (Phase 7): V8 & CATCHOS  -> pin6 = M4c_pin6 (catch audio source)
    ttl_7400 u_M4 (
        .pin1  (L4_pin1),  .pin2  (V8),       .pin3  (M4c_pin3),     // g1 audio
        .pin4  (V8),       .pin5  (B7_CATCHOS),.pin6 (M4c_pin6),     // g2 audio
        .pin9  (M3_Q2),    .pin10 (VRESET),   .pin8  (E_sig),        // g3 = "E"
        .pin12 (L4_pin4),  .pin13 (ATTRACT_n),.pin11 (M4c_pin11)     // g4 = left strobe
    );

    // L4 - 7402 quad NOR.
    //   g2: C8.3 NOR HLD2       -> pin4 = L4_pin4 (-> M4.12).
    //   g1 (Phase 7): E8.3 NOR ATTRACT -> pin1 = L4_pin1 (-> M4.1, proximity gate).
    //   g3,g4 unused.
    ttl_7402 u_L4 (
        .pin1  (L4_pin1),    .pin2  (E8_pin3), .pin3  (ATTRACT),
        .pin4  (L4_pin4),    .pin5  (C8_pin3), .pin6  (HLD2),
        .pin8  (GND),        .pin9  (GND),     .pin10 (nc_L4_pin10),
        .pin11 (GND),        .pin12 (GND),     .pin13 (nc_L4_pin13)
    );

    // C8 - 555 monostable, ~90ms (82k/1µF, same as B8).  /TR=BUMP2, /RST=VCC.
    //   Left player collision one-shot (mirror B8).
    ttl_555_mono #(.PULSE_CYCLES(32'd2_579_750)) u_C8 (
        .clk_sys (clk_sys),
        .pin2 (BUMP2),
        .pin3 (C8_pin3),
        .pin4 (VCC)
    );

    // ---- /* Left Counters */ -----------------------------------------

    // J3 - 9316 left-player horizontal position, low nibble (mirror E3).
    //   CP=CLK, /MR=OO2, /PE=HLD2(J1.12), CET=HBLANK_n, CEP=VCC.
    //   Parallel-load value {VCC,GND,F,E}.
    ttl_9316 u_J3 (
        .clk_sys (clk_sys),
        .pin1  (OO2),       .pin2  (CLK),
        .pin3  (E_sig),     .pin4  (K3_pin10),  .pin5  (GND),      .pin6  (VCC),
        .pin7  (VCC),       .pin9  (HLD2),      .pin10 (HBLANK_n_w),
        .pin11 (J3_Q[3]),   .pin12 (J3_Q[2]),   .pin13 (J3_Q[1]),  .pin14 (J3_Q[0]),
        .pin15 (J3_RCO)
    );

    // H3 - 9316 left-player horizontal position, high nibble (mirror F3).
    //   CP=CLK (same as J3), CEP=J3.RCO -> synchronous carry.
    ttl_9316 u_H3 (
        .clk_sys (clk_sys),
        .pin1  (OO2),       .pin2  (CLK),
        .pin3  (GND),       .pin4  (GND),       .pin5  (GND),      .pin6  (VCC),
        .pin7  (J3_RCO),    .pin9  (HLD2),      .pin10 (VCC),
        .pin11 (H3_Q[3]),   .pin12 (H3_Q[2]),   .pin13 (H3_Q[1]),  .pin14 (H3_Q[0]),
        .pin15 (H3_RCO)
    );

    // J1 - 7410 triple 3-input NAND.
    //   g1: J2.Q1 & H3.RCO & J3.RCO -> pin12 = HLD2 (-> J3/H3 /PE)
    //   g2: K1.RCO & L1.Q2 & ~L1.Q3 -> pin6  = J1_pin6 (-> F1.6, VIDEO2)
    //   g3: MAZE & ~F1.13 & VIDEO2  -> pin8  = BUMP2  (real schematic: J1.9=MAZE)
    ttl_7410 u_J1 (
        .pin1  (J2_Q1),    .pin2  (H3_RCO),   .pin13 (J3_RCO),   .pin12 (HLD2),
        .pin3  (K1_RCO),   .pin4  (L1_Q[2]),  .pin5  (H1_pin6),  .pin6  (J1_pin6),
        .pin9  (J4_g1),    .pin10 (H1_pin10), .pin11 (VIDEO2),   .pin8  (BUMP2)
    );

    // L1 - 9316 left-player vertical position, low nibble (mirror G1).
    //   CP=HSYNC_n, /MR=OO2, /PE=E1.6, CET=VBLANK_n, CEP=VCC.
    //   Parallel-load value {VCC,GND,H,G}.
    ttl_9316 u_L1 (
        .clk_sys (clk_sys),
        .pin1  (OO2),       .pin2  (HSYNC_n_w),
        .pin3  (M2_Q1),     .pin4  (K2_pin6),   .pin5  (GND),      .pin6  (VCC),
        .pin7  (VCC),       .pin9  (E1_pin6),   .pin10 (VBLANK_n_w),
        .pin11 (L1_Q[3]),   .pin12 (L1_Q[2]),   .pin13 (L1_Q[1]),  .pin14 (L1_Q[0]),
        .pin15 (L1_RCO)
    );

    // K1 - 9316 left-player vertical position, high nibble (mirror D1).
    //   CP=HSYNC_n (same as L1), CEP=L1.RCO -> synchronous carry.
    ttl_9316 u_K1 (
        .clk_sys (clk_sys),
        .pin1  (OO2),       .pin2  (HSYNC_n_w),
        .pin3  (GND),       .pin4  (GND),       .pin5  (GND),      .pin6  (GND),
        .pin7  (L1_RCO),    .pin9  (E1_pin6),   .pin10 (VCC),
        .pin11 (K1_Q[3]),   .pin12 (K1_Q[2]),   .pin13 (K1_Q[1]),  .pin14 (K1_Q[0]),
        .pin15 (K1_RCO)
    );

    // XY - 7410 (DICE right-wall collision fix, gotcha.cpp:1038).
    //   g3: MHBLANK_n & VIDEO2 & H8.10(=~C5_g2) -> pin8 = XY_pin8 (-> J10.10).
    ttl_7410 u_XY (
        .pin1  (GND),      .pin2  (GND),      .pin13 (GND),      .pin12 (nc_XY_pin12),
        .pin3  (GND),      .pin4  (GND),      .pin5  (GND),      .pin6  (nc_XY_pin6),
        .pin9  (D5_Q2_n_w),.pin10 (VIDEO2),   .pin11 (H8_inv5),  .pin8  (XY_pin8)
    );

    // K10 - 555 monostable, ~110ms (100k/1µF).  /TR=J10.3, /RST=VCC.
    //   Left-counter reset one-shot (homes J3/H3/L1/K1 via OO2).
    ttl_555_mono #(.PULSE_CYCLES(32'd3_146_000)) u_K10 (
        .clk_sys (clk_sys),
        .pin2 (J10_pin3),
        .pin3 (K10_pin3),
        .pin4 (VCC)
    );

    // J10 - 7400 quad NAND.
    //   g3: CATCH_n & XY.8 -> pin8 = J10_pin8
    //   g1: J10.8 & J10.8  -> pin3 = J10_pin3 = ~J10.8 (-> K10 /TR)
    //   g2: K10.3 & K10.3  -> pin6 = OO2      = ~K10.3 (left counters /MR)
    ttl_7400 u_J10 (
        .pin1  (J10_pin8), .pin2  (J10_pin8), .pin3  (J10_pin3),
        .pin4  (K10_pin3), .pin5  (K10_pin3), .pin6  (OO2),
        .pin9  (CATCH_n),  .pin10 (XY_pin8),  .pin8  (J10_pin8),
        .pin12 (GND),      .pin13 (GND),      .pin11 (nc_J10_g4)
    );

    // ==================================================================
    // ===== /* Sound */ (gotcha.cpp lines 1052-1111) ===================
    // ==================================================================

    // A10 - the CATCHOS trigger latch.  In the schematic this is two cross-
    //   coupled 7400 NAND gates (g3/g4) forming an SR latch.  A pure combinational
    //   translation would be a bistable feedback loop — a synthesis hazard
    //   (hdl-coding-guidelines anti-pattern #3: "combinational feedback loop";
    //   the only other comb loops here are the Phase-0 HBLANK/VBLANK latches).
    //   Per that guideline's fix (close the loop through a flop) and the
    //   ttl_latch.sv precedent, model it as a clocked SR latch, identical behaviour:
    //     SET   = CATCH_n low  (a catch — VIDEO1 & VIDEO2 overlap)
    //     RESET = VRESET_n low (once per frame), reset-dominant.
    //   A10.8 (active-low) -> B7 /2TR fires the 728ms CATCHOS one-shot.  BUF1
    //   (DICE 30ns deglitch) collapses away since CATCH_n is already synchronous.
    logic a10_latched = 1'b0;
    always_ff @(posedge clk_sys) begin
        if      (!VRESET_n) a10_latched <= 1'b0;   // reset each frame
        else if (!CATCH_n)  a10_latched <= 1'b1;   // set on catch
    end
    assign A10_pin8 = ~a10_latched;

    // E8 - 555 astable, the PROXIMITY-modulated oscillator (proximity "footstep"
    //   sound).  DICE charges an RC cap from the 2-bit {D2.11,D2.3} value to set
    //   E8's CV; we approximate it as a discrete 4-rate digital astable.  Index 0
    //   = players aligned = fastest; indices 2/3 = far apart = near cutoff (slow).
    //   Held low in ATTRACT (E8 /RST = ATTRACT_n).  Rates tunable on hardware.
    wire [1:0] prox_idx = {D2_pin11, D2_pin3};
    logic [22:0] e8_half;
    always_comb begin
        case (prox_idx)
            2'd0:    e8_half = 23'd795_454;    // ~18 Hz (closest)
            2'd1:    e8_half = 23'd1_431_818;  // ~10 Hz
            default: e8_half = 23'd3_977_272;  // ~3.6 Hz (far / cutoff)
        endcase
    end
    logic [22:0] e8_counter = '0;
    logic        e8_q       = 1'b0;
    always_ff @(posedge clk_sys) begin
        if (!ATTRACT_n) begin
            e8_counter <= '0;
            e8_q       <= 1'b0;
        end else if (e8_counter >= e8_half) begin
            e8_counter <= '0;
            e8_q       <= ~e8_q;
        end else begin
            e8_counter <= e8_counter + 23'd1;
        end
    end
    assign E8_pin3 = e8_q;

    // Audio mix.  Two 1-bit gated square sources, both idle HIGH:
    //   M4c_pin3 = proximity (V8 ~1kHz tone pulsed at the E8 footstep rate),
    //   M4c_pin6 = catch     (V8 tone gated on for the 728ms CATCHOS one-shot).
    // DICE sums them through MIXER1/MIXER2; here each source maps to +/-amp and
    // they add.  Steady (silent) levels are pure DC and the framework DC-blocker
    // removes them; the framework IIR LPF anti-aliases the raw squares.
    //   REGISTERED on clk_sys (not a bare combinational assign): audio_out commits
    //   a sample only when it reads the same value on two consecutive clk_audio
    //   edges, so AUDIO_L/R must be glitch-free and stable.  The audio content
    //   changes at <=~1kHz (V8), far slower than clk_sys, so the registered value
    //   easily holds stable across many clk_audio cycles.  (mister-framework-
    //   reference/41-audio.md §2, §4.3, anti-pattern A.2.)
    localparam signed [15:0] PROX_AMP  = 16'sd6000;
    localparam signed [15:0] CATCH_AMP = 16'sd9000;
    logic signed [15:0] audio_q = '0;
    always_ff @(posedge clk_sys)
        audio_q <= (M4c_pin3 ? PROX_AMP  : -PROX_AMP)
                 + (M4c_pin6 ? CATCH_AMP : -CATCH_AMP);
    assign audio = audio_q;

    // ------------------------------------------------------------------
    // Module outputs
    // ------------------------------------------------------------------
    // ce_pix: rising edge of CLK (= 7.159 MHz pixel-rate strobe in clk_sys)
    logic clk_prev = 1'b0;
    always_ff @(posedge clk_sys) clk_prev <= CLK;

    assign ce_pix = CLK & ~clk_prev;
    assign HBlank = HBLANK_w;
    assign VBlank = VBLANK_w;
    assign HSync  = HSYNC_w;        // active-high; framework can re-polarize via VGA_HS

    // VSync derived from V counter — gotcha.cpp uses composite sync via M4/M2
    // (Phase 3+) instead of a discrete VSync.  For MiSTer we need separate
    // HS/VS, so we pulse VSync HIGH for V=0..3 inside VBlank.
    assign VSync = ~V128 & ~V64 & ~V32 & ~V16 & ~V8 & ~V4 & VBLANK_w;

    // Monochrome picture: maze + score (F6_pin13) OR'd with the two player
    // sprites (VIDEO1 right, VIDEO2 left).  Phase 8 replaces this with the
    // real 3-channel colour video.
    assign video = (F6_pin13 | VIDEO1 | VIDEO2) ? 8'hFF : 8'h00;

endmodule
