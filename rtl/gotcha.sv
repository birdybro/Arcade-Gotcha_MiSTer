//============================================================================
//  Atari Gotcha (1973) - chip-level FPGA port
//
//  This module is a structural translation of docs/DICE/games/gotcha.cpp into
//  SystemVerilog. Each 74xx chip in the original PCB has a corresponding
//  ttl_* primitive instance. Net names (CLK, H1..H256, V1..V256, ...) and
//  chip designators (J6, L6, K6, ...) mirror the Atari schematic.
//
//  Current scope: H/V counter + sync gen (Phase 0) + playfield maze pattern
//  (Phase 1, gotcha.cpp /* Playfield */ section, lines 456-501).
//  Players, score, collision, audio: TBD (Phases 2-5, see tasks.md).
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

    output logic        ce_pix,
    output logic        HBlank,
    output logic        HSync,
    output logic        VBlank,
    output logic        VSync,

    output logic [7:0]  video
);

    // ------------------------------------------------------------------
    // Power rails
    // ------------------------------------------------------------------
    wire VCC = 1'b1;
    wire GND = 1'b0;

    // ------------------------------------------------------------------
    // Net declarations (names mirror gotcha.cpp #defines)
    // ------------------------------------------------------------------
    wire        CLK, CLK_n;                              // J6 FF1 outputs
    wire        H1,  H2,  H4,  H8;                       // L6 outputs
    wire        H16, H32, H64, H128;                     // M6 outputs
    wire        H256, H256_n;                            // J6 FF2 outputs
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

    wire        J5_g2_out;                               // ~H64
    wire        L5_g2_out;                               // ~(H32 & ~H64)
    wire        J4_g4_out;                               // ~H64 & HBLANK
    wire        HSYNC_w, HSYNC_n_w;                      // F4 FF1 outputs

    // Playfield internal nets
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
    wire        D5_Q2_w;                                 // D5 FF2 Q (CP2=C5_g1 toggle)
    wire        C5_g3;                                   // ~(D5_Q2_w & C5_g4)
    wire        C5_g2;                                   // ~(C5_g1 & C5_g3) = MAZE INK
    wire        H8_inv5;                                 // ~C5_g2 (feeds F8 in Phase 2)

    // Stubs for chip gates not yet wired in any phase
    wire        nc_J5_pin2, nc_J5_pin6, nc_J5_pin12;
    wire        nc_L5_pin3, nc_L5_pin8, nc_L5_pin11;
    wire        nc_J4_pin3, nc_J4_pin6, nc_J4_pin8;
    wire        nc_H4_g2, nc_H4_g3;
    wire        nc_F6_pin1, nc_F6_pin13;
    wire        nc_B4_Q1, nc_B4_Q1_n;                    // B4 FF1 unused in Phase 1
    wire        nc_E4_g1, nc_E4_g2, nc_E4_g3;            // E4 gates 1-3 unused in Phase 1
    wire        nc_D6_g1, nc_D6_g3, nc_D6_g4;            // D6 gates 1, 3, 4 unused in Phase 1
    wire        nc_K4_g2, nc_K4_g3;                      // K4 gates 2, 3 unused in Phase 1
    wire        nc_K5_g2, nc_K5_g3, nc_K5_g4;            // K5 gates 2, 3, 4 unused in Phase 1
    wire        nc_E6_g1, nc_E6_g3;                      // E6 gates 1, 3 unused in Phase 1
    wire        nc_H8_inv1, nc_H8_inv2, nc_H8_inv3, nc_H8_inv4, nc_H8_inv6;

    // ==================================================================
    // J6 - 74107 dual JK FF
    //   FF1: CP1 = CLOCK = clk_sys, J=K=VCC -> Q1 toggles every clk_sys
    //        cycle, giving CLK = clk_sys / 2 = 7.159 MHz.
    //   FF2: CP2 = M6.QD (H128), J=K=VCC, /CLR2 = H6.Q1 -> Q2 = H256.
    //   CP1_IS_CLK_SYS=1 because pin12 is wired to the master clock.
    // ==================================================================
    ttl_74107 #(.CP1_IS_CLK_SYS(1)) u_J6 (
        .clk_sys (clk_sys),
        .pin1    (VCC),         // J1
        .pin2    (CLK_n),       // /Q1
        .pin3    (CLK),         // Q1
        .pin4    (VCC),         // K1
        .pin5    (H256),        // Q2
        .pin6    (H256_n),      // /Q2
        .pin8    (VCC),         // J2
        .pin9    (H128),        // CP2 <- M6.QD
        .pin10   (H6_Q1),       // /CLR2 <- H6.Q1
        .pin11   (VCC),         // K2
        .pin12   (1'b0),        // CP1 unused in CLK_SYS mode (tied for cleanliness)
        .pin13   (VCC)          // /CLR1
    );

    // ==================================================================
    // L6 - 7493 H counter low nibble
    //   (declared 9316 in gotcha.cpp; functionally a 7493 ripple counter)
    //   CKA=CLK, QA->CKB self-cascade, R0=H6./Q1
    // ==================================================================
    ttl_7493 u_L6 (
        .clk_sys (clk_sys),
        .pin1    (H1),          // CKB <- QA
        .pin2    (H6_Q1_n),     // R0(1)
        .pin3    (H6_Q1_n),     // R0(2)
        .pin8    (H4),          // QC
        .pin9    (H2),          // QB
        .pin11   (H8),          // QD
        .pin12   (H1),          // QA
        .pin14   (CLK)          // CKA
    );

    // ==================================================================
    // M6 - 7493 H counter high nibble
    //   CKA = L6.QD (H8), QA->CKB, R0=H6./Q1
    // ==================================================================
    ttl_7493 u_M6 (
        .clk_sys (clk_sys),
        .pin1    (H16),
        .pin2    (H6_Q1_n),
        .pin3    (H6_Q1_n),
        .pin8    (H64),
        .pin9    (H32),
        .pin11   (H128),
        .pin12   (H16),
        .pin14   (H8)
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
    //   Gate 1 (pins 1,2,13 -> 12): V=261 detect: ~(V256 & V1 & V4)
    //   Gates 2 and 3 unused for now (used for player M-counter logic
    //   later in the port — see gotcha.cpp /* M4 */ and /* Right Control */).
    // ==================================================================
    ttl_7410 u_H4 (
        .pin1  (V256), .pin2  (V1),    .pin13 (V4),    .pin12 (H4_g1_out),
        .pin3  (GND),  .pin4  (GND),   .pin5  (GND),   .pin6  (nc_H4_g2),
        .pin9  (GND),  .pin10 (GND),   .pin11 (GND),   .pin8  (nc_H4_g3)
    );

    // ==================================================================
    // H6 - 7474 dual D-FF: H reset latch (FF1) + V reset latch (FF2)
    //   FF1: D=K6_out, CK=CLK, Q1 goes low after H=455 detected.
    //        /Q1 async-resets L6/M6 (R0) and clocks the V counter (H5.CKA).
    //        Q1 also gates J6.FF2 /CLR2 (drops H256 when H counter reset).
    //   FF2: D=H4_g1_out, CK=H6./Q1, Q2 goes low after V=261 detected.
    //        Q2 async-clears D5.FF1 (V256); /Q2 resets H5/F5 (R0).
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
    // H5 - 7493 V counter low nibble
    //   CKA = H6./Q1, QA->CKB, R0 = H6./Q2
    // ==================================================================
    ttl_7493 u_H5 (
        .clk_sys (clk_sys),
        .pin1    (V1),
        .pin2    (H6_Q2_n),
        .pin3    (H6_Q2_n),
        .pin8    (V4),
        .pin9    (V2),
        .pin11   (V8),
        .pin12   (V1),
        .pin14   (H6_Q1_n)
    );

    // ==================================================================
    // F5 - 7493 V counter high nibble
    //   CKA = H5.QD (V8), QA->CKB, R0 = H6./Q2
    // ==================================================================
    ttl_7493 u_F5 (
        .clk_sys (clk_sys),
        .pin1    (V16),
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
    //   FF1 (V256): CP1=V128, J=K=VCC, /CLR1=H6.Q2 -> Q1 = V256
    //   FF2 (Playfield): CP2=C5.pin3 (C5_g1), J=K=VCC, /CLR2=H6.Q1
    //                    -> Q2 toggles per C5_g1 edge, drives C5.gate3
    // ==================================================================
    ttl_74107 u_D5 (
        .clk_sys (clk_sys),
        .pin1    (VCC),          // J1
        .pin2    (V256_n),       // /Q1
        .pin3    (V256),         // Q1
        .pin4    (VCC),          // K1
        .pin5    (D5_Q2_w),      // Q2
        .pin6    (),             // /Q2 unused
        .pin8    (VCC),          // J2
        .pin9    (C5_g1),        // CP2
        .pin10   (H6_Q1),        // /CLR2
        .pin11   (VCC),          // K2
        .pin12   (V128),         // CP1
        .pin13   (H6_Q2)         // /CLR1
    );

    // ==================================================================
    // M5 - 7400 quad NAND, HBLANK NAND-latch + playfield H32&H64 gate
    //   Gate 1: pin1=H16, pin2=H64 -> pin3 = ~(H16 & H64)
    //   Gate 2: pin4=gate1_out, pin5=gate3_out -> pin6 = HBLANK_n
    //   Gate 3: pin9=gate2_out, pin10=H6.Q1 -> pin8 = HBLANK
    //   Gate 4: pin12=H32, pin13=H64 -> pin11 = M5_g4 (playfield)
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
    // F6 - 7402 quad NOR, VBLANK NOR-latch
    //   Gate 2: pin5=gate3_out, pin6=H6./Q2 -> pin4 = VBLANK_n
    //   Gate 3: pin8=V16,       pin9=gate2_out -> pin10 = VBLANK
    //   Gates 1 and 4 unused here (used in playfield/video composition).
    // ==================================================================
    ttl_7402 u_F6 (
        .pin1  (nc_F6_pin1), .pin2 (GND), .pin3 (GND),
        .pin4  (VBLANK_n_w),
        .pin5  (VBLANK_w),
        .pin6  (H6_Q2_n),
        .pin8  (V16),
        .pin9  (VBLANK_n_w),
        .pin10 (VBLANK_w),
        .pin11 (GND), .pin12 (GND), .pin13 (nc_F6_pin13)
    );

    // ==================================================================
    // J5 - 7404 hex inverter
    //   Gate 2 (pin3 -> pin4): ~H64 for HSync timing
    //   Gate 4 (pin9 -> pin8): ~K4_g4 for playfield
    //   Gate 5 (pin11 -> pin10): ~V4 for playfield (B4 reset + K4 input)
    //   Other gates used later (M1/M3 logic) — stubbed for now.
    // ==================================================================
    ttl_7404 u_J5 (
        .pin1  (GND),    .pin2  (nc_J5_pin2),
        .pin3  (H64),    .pin4  (J5_g2_out),
        .pin5  (GND),    .pin6  (nc_J5_pin6),
        .pin9  (K4_g4),  .pin8  (J5_g4),
        .pin11 (V4),     .pin10 (J5_g5),
        .pin13 (GND),    .pin12 (nc_J5_pin12)
    );

    // ==================================================================
    // L5 - 7400 quad NAND
    //   Gate 2 (pin4=H32, pin5=~H64 -> pin6): ~(H32 & ~H64) for HSync
    //   Other gates used in playfield/blanking logic — stubs.
    // ==================================================================
    ttl_7400 u_L5 (
        .pin1  (GND),       .pin2  (GND),       .pin3  (nc_L5_pin3),
        .pin4  (H32),       .pin5  (J5_g2_out), .pin6  (L5_g2_out),
        .pin9  (GND),       .pin10 (GND),       .pin8  (nc_L5_pin8),
        .pin12 (GND),       .pin13 (GND),       .pin11 (nc_L5_pin11)
    );

    // ==================================================================
    // J4 - 7408 quad AND
    //   Gate 4 (pin12=~H64, pin13=HBLANK -> pin11): used as HSync FF /CLR
    //   Other gates used in playfield/control logic — stubs.
    // ==================================================================
    ttl_7408 u_J4 (
        .pin1  (GND),       .pin2  (GND),     .pin3  (nc_J4_pin3),
        .pin4  (GND),       .pin5  (GND),     .pin6  (nc_J4_pin6),
        .pin9  (GND),       .pin10 (GND),     .pin8  (nc_J4_pin8),
        .pin12 (J5_g2_out), .pin13 (HBLANK_w), .pin11 (J4_g4_out)
    );

    // ==================================================================
    // F4 - 7474 dual D-FF
    //   FF1 (HSync): D=L5_g2_out, CK=H2, /CLR=J4_g4_out, /PR=VCC
    //                /Q1 (pin6) = HSYNC_n
    //   FF2 (Playfield): D=VCC, CK=V64, /PR=VCC, /CLR=H6.Q2
    //                    /Q2 (pin8) goes to E6.gate2 input (V64-latched signal)
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

    // ==================================================================
    // D6 - 7400 quad NAND
    //   Gate 2 (pin4=H4, pin5=H8 -> pin6): D6_g2 = ~(H4 & H8) for playfield
    //   Other gates used in /* Coin */ (Phase 4) — stubbed.
    // ==================================================================
    ttl_7400 u_D6 (
        .pin1  (GND),  .pin2  (GND),  .pin3  (nc_D6_g1),
        .pin4  (H4),   .pin5  (H8),   .pin6  (D6_g2),
        .pin9  (GND),  .pin10 (GND),  .pin8  (nc_D6_g3),
        .pin12 (GND),  .pin13 (GND),  .pin11 (nc_D6_g4)
    );

    // ==================================================================
    // E6 - 7427 triple 3-input NOR
    //   Gate 2 (pin3=D6_g2, pin4=F4./Q2, pin5=M5_g4 -> pin6 = E6_g2):
    //     E6_g2 = ~(~(H4&H8) | F4./Q2 | ~(H32&H64))
    //   Other gates used in /* Playfield mux part 2 */ (Phase 2) — stubbed.
    // ==================================================================
    ttl_7427 u_E6 (
        .pin1  (GND), .pin2  (GND), .pin13 (GND), .pin12 (nc_E6_g1),
        .pin3  (D6_g2),
        .pin4  (F4_Q2_n_w),
        .pin5  (M5_g4),
        .pin6  (E6_g2),
        .pin9  (GND), .pin10 (GND), .pin11 (GND), .pin8  (nc_E6_g3)
    );

    // ==================================================================
    // K5 - 7486 quad XOR
    //   Gate 1 (pin1=H16, pin2=H256 -> pin3): K5_g1 = H16 XOR H256
    //   Other gates used later — stubbed.
    // ==================================================================
    ttl_7486 u_K5 (
        .pin1  (H16),  .pin2  (H256), .pin3  (K5_g1),
        .pin4  (GND),  .pin5  (GND),  .pin6  (nc_K5_g2),
        .pin9  (GND),  .pin10 (GND),  .pin8  (nc_K5_g3),
        .pin12 (GND),  .pin13 (GND),  .pin11 (nc_K5_g4)
    );

    // ==================================================================
    // K4 - 7402 quad NOR
    //   Gate 1 (pin2=H128, pin3=K5_g1 -> pin1 = K4_g1):
    //     K4_g1 = ~((H16 XOR H256) | H128)
    //   Gate 4 (pin11=V256_n, pin12=J5_g5 -> pin13 = K4_g4):
    //     K4_g4 = ~(V256_n | ~V4)
    //   Other gates used later — stubbed.
    // ==================================================================
    ttl_7402 u_K4 (
        .pin1  (K4_g1),
        .pin2  (H128),
        .pin3  (K5_g1),
        .pin4  (nc_K4_g2), .pin5  (GND),  .pin6  (GND),
        .pin8  (GND), .pin9  (GND), .pin10 (nc_K4_g3),
        .pin11 (V256_n),
        .pin12 (J5_g5),
        .pin13 (K4_g4)
    );

    // ==================================================================
    // C5 - 7400 quad NAND  (all four gates used in playfield)
    //   Gate 1: pin1=E6_g2,  pin2=K4_g1  -> pin3  = C5_g1
    //   Gate 2: pin4=C5_g1,  pin5=C5_g3  -> pin6  = C5_g2  (MAZE INK)
    //   Gate 3: pin9=D5.Q2,  pin10=C5_g4 -> pin8  = C5_g3
    //   Gate 4: pin12=J5_g4, pin13=E4_g4 -> pin11 = C5_g4
    // ==================================================================
    ttl_7400 u_C5 (
        .pin1  (E6_g2),
        .pin2  (K4_g1),
        .pin3  (C5_g1),
        .pin4  (C5_g1),
        .pin5  (C5_g3),
        .pin6  (C5_g2),
        .pin9  (D5_Q2_w),
        .pin10 (C5_g4),
        .pin8  (C5_g3),
        .pin12 (J5_g4),
        .pin13 (E4_g4),
        .pin11 (C5_g4)
    );

    // ==================================================================
    // B4 - 74107 dual JK FF
    //   FF1 used in /* M4 */ (Phase 3) — stubbed.
    //   FF2 (Playfield): J2=VCC, K2=GND, CP2=F4./Q2, /CLR2=J5_g5 (~V4)
    //                    Q2 -> E4.gate4 input.  J=1,K=0 means SET on edge.
    // ==================================================================
    ttl_74107 u_B4 (
        .clk_sys (clk_sys),
        .pin1    (GND),       // J1 (FF1 unused)
        .pin2    (nc_B4_Q1_n),
        .pin3    (nc_B4_Q1),
        .pin4    (GND),       // K1
        .pin5    (B4_Q2),     // Q2
        .pin6    (),          // /Q2 unused
        .pin8    (VCC),       // J2
        .pin9    (F4_Q2_n_w), // CP2
        .pin10   (J5_g5),     // /CLR2 = ~V4
        .pin11   (GND),       // K2
        .pin12   (GND),       // CP1
        .pin13   (VCC)        // /CLR1 = VCC so FF1 isn't perpetually cleared
    );

    // ==================================================================
    // E4 - 7400 quad NAND
    //   Gate 4: pin12=B4.Q2, pin13=V2 -> pin11 = E4_g4 = ~(B4.Q2 & V2)
    //   Other gates used in /* Right Control */ (Phase 3) — stubbed.
    // ==================================================================
    ttl_7400 u_E4 (
        .pin1  (GND), .pin2  (GND), .pin3  (nc_E4_g1),
        .pin4  (GND), .pin5  (GND), .pin6  (nc_E4_g2),
        .pin9  (GND), .pin10 (GND), .pin8  (nc_E4_g3),
        .pin12 (B4_Q2), .pin13 (V2), .pin11 (E4_g4)
    );

    // ==================================================================
    // H8 - 7404 hex inverter
    //   Gate 5: pin11=C5_g2 -> pin10 = H8_inv5 = ~MAZE_INK
    //     (feeds F8 NAND combiner in Phase 2; left dangling for Phase 1)
    //   Other gates used in player/score logic — stubbed.
    // ==================================================================
    ttl_7404 u_H8 (
        .pin1  (GND),    .pin2  (nc_H8_inv1),
        .pin3  (GND),    .pin4  (nc_H8_inv2),
        .pin5  (GND),    .pin6  (nc_H8_inv3),
        .pin9  (GND),    .pin8  (nc_H8_inv4),
        .pin11 (C5_g2),  .pin10 (H8_inv5),
        .pin13 (GND),    .pin12 (nc_H8_inv6)
    );

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

    // VSync — gotcha.cpp generates composite sync via M4/M2 chip in /* Sound */
    // section rather than a discrete VSYNC signal; for the MiSTer framework
    // (which wants separate HS/VS) we derive VSYNC from the V counter.
    // Standard NTSC 240p vsync: 3-line pulse starting a few lines into VBlank.
    // VBlank goes active at V=261 (then wraps to V=0..15 inside blanking).
    // Pulse VSync on V=0..3 (first 4 lines of frame, fully inside VBlank).
    assign VSync = ~V128 & ~V64 & ~V32 & ~V16 & ~V8 & ~V4 & VBLANK_w;
    //               V<4 inside vblank == V \in {0,1,2,3} during blanking

    // Picture — Phase 1 stub.  Drives the raw maze-ink signal (C5.pin6)
    // directly to all 8 video bits as black/white.  In Phase 2 this will
    // be replaced by the full F8 NAND combiner that mixes maze + player
    // sprites + score segments per gotcha.cpp lines 1072-1078.
    assign video = C5_g2 ? 8'hFF : 8'h00;

endmodule
