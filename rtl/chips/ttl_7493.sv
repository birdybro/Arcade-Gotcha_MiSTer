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
// External wiring QA->CKB (pin12->pin1) makes it a 4-bit binary counter on CKA.
// Reset: R0_1 & R0_2 -> all Q=0.
module ttl_7493 (
    input  logic clk_sys,
    input  logic pin1,    // CKB
    input  logic pin2,    // R0(1)
    input  logic pin3,    // R0(2)
    output logic pin8,    // QC
    output logic pin9,    // QB
    output logic pin11,   // QD
    output logic pin12,   // QA
    input  logic pin14    // CKA
);
    logic       qa       = 1'b0;
    logic [2:0] qbcd     = 3'b0;
    logic       cka_prev = 1'b0;
    logic       ckb_prev = 1'b0;

    wire reset = pin2 & pin3;

    always_ff @(posedge clk_sys) begin
        cka_prev <= pin14;
        ckb_prev <= pin1;

        if (reset) begin
            qa   <= 1'b0;
            qbcd <= 3'b0;
        end else begin
            if (~pin14 & cka_prev) qa   <= ~qa;          // CKA negedge -> toggle QA
            if (~pin1  & ckb_prev) qbcd <= qbcd + 3'd1;  // CKB negedge -> advance cascade
        end
    end

    assign pin12 = qa;
    assign pin9  = qbcd[0];
    assign pin8  = qbcd[1];
    assign pin11 = qbcd[2];
endmodule
