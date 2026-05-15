// 7493 - 4-bit binary ripple counter
//      +---+--+---+
//  CKB |1  +--+ 14| CKA
// R0_1 |2       13| NC
// R0_2 |3       12| QA
//   NC |4  7493 11| QD
//  VCC |5       10| GND
//   NC |6        9| QB
//   NC |7        8| QC
//      +----------+
// QA is an independent /2 stage clocked by CKA.
// QB,QC,QD form a /8 ripple counter clocked by CKB.
// In Gotcha every 7493 is wired QA->CKB (pin12->pin1) to form a 4-bit binary
// counter clocked by CKA.
//
// SELF_CASCADE parameter:
//   The naive structural model edge-detects CKB (= QA) with a clk_sys-registered
//   `prev` flop — so QBCD updates one clk_sys cycle AFTER QA toggles.  At
//   clk_sys = 4x the pixel rate that 1-cycle gap is a wrong counter value
//   sampled on ~every other pixel, which shows up as a "sliver wraparound"
//   artifact once the MiSTer scaler samples the picture.  With SELF_CASCADE=1
//   the self-cascaded chip is modeled as ONE atomic 4-bit synchronous counter
//   that increments all four bits together on a CKA negedge.  The real chip's
//   internal ripple is sub-nanosecond and functionally irrelevant, so this is
//   the faithful translation of the chip's *function*.  All four Gotcha 7493
//   instances (L6, M6, H5, F5) set SELF_CASCADE=1.
//
//   In SELF_CASCADE mode pin1 (CKB) is repurposed as a SYNCHRONOUS COUNT-ENABLE:
//   the counter increments only on a CKA negedge where pin1 is high.  Tie pin1
//   to VCC for a free-running nibble; tie it to the lower nibble's terminal
//   count (QA&QB&QC&QD) and feed every nibble the *same* root clock on CKA to
//   build a multi-nibble counter with NO inter-chip ripple lag — every nibble
//   then updates on the same clk_sys edge.
module ttl_7493 #(
    parameter int SELF_CASCADE = 0
) (
    input  logic clk_sys,
    input  logic pin1,    // CKB  (SELF_CASCADE: synchronous count-enable)
    input  logic pin2,    // R0(1)
    input  logic pin3,    // R0(2)
    output logic pin8,    // QC
    output logic pin9,    // QB
    output logic pin11,   // QD
    output logic pin12,   // QA
    input  logic pin14    // CKA
);
    wire reset = pin2 & pin3;

    generate
    if (SELF_CASCADE != 0) begin : g_sync
        // Atomic 4-bit synchronous counter.  Increments on a CKA negedge while
        // the count-enable (pin1) is high.
        logic [3:0] cnt      = 4'b0;
        logic       cka_prev = 1'b0;

        always_ff @(posedge clk_sys) begin
            cka_prev <= pin14;
            if (reset)                         cnt <= 4'b0;
            else if (~pin14 & cka_prev & pin1) cnt <= cnt + 4'd1;
        end

        assign pin12 = cnt[0];   // QA
        assign pin9  = cnt[1];   // QB
        assign pin8  = cnt[2];   // QC
        assign pin11 = cnt[3];   // QD
    end else begin : g_ripple
        // Generic 7493: independent /2 (QA on CKA) and /8 (QBCD on CKB).
        logic       qa       = 1'b0;
        logic [2:0] qbcd     = 3'b0;
        logic       cka_prev = 1'b0;
        logic       ckb_prev = 1'b0;

        always_ff @(posedge clk_sys) begin
            cka_prev <= pin14;
            ckb_prev <= pin1;
            if (reset) begin
                qa   <= 1'b0;
                qbcd <= 3'b0;
            end else begin
                if (~pin14 & cka_prev) qa   <= ~qa;
                if (~pin1  & ckb_prev) qbcd <= qbcd + 3'd1;
            end
        end

        assign pin12 = qa;
        assign pin9  = qbcd[0];
        assign pin8  = qbcd[1];
        assign pin11 = qbcd[2];
    end
    endgenerate
endmodule
