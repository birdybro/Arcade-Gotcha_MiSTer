// 7490 - Decade counter (divide-by-2 on CKA, divide-by-5 on CKB)
//      +---+--+---+
//  CKB |1  +--+ 14| CKA
// R0_1 |2       13| NC
// R0_2 |3       12| QA
//   NC |4  7490 11| QD
//  VCC |5       10| GND
// R9_1 |6        9| QB
// R9_2 |7        8| QC
//      +----------+
// QA  is an independent /2 stage on CKA negedge.
// QB,QC,QD form a /5 (count sequence 0,1,2,3,4 then 0) on CKB negedge.
// External wire QA->CKB (pin12->pin1) gives a 4-bit BCD 0..9 decade counter.
// R0 (pin2 & pin3 both high): force QA=QB=QC=QD=0 (priority over R9).
// R9 (pin6 & pin7 both high, R0 not asserted): force count = 9 (QA=1, QD=1).
module ttl_7490 (
    input  logic clk_sys,
    input  logic pin1,    // CKB
    input  logic pin2,    // R0_1
    input  logic pin3,    // R0_2
    output logic pin8,    // QC
    output logic pin9,    // QB
    output logic pin11,   // QD
    output logic pin12,   // QA
    input  logic pin6,    // R9_1
    input  logic pin7,    // R9_2
    input  logic pin14    // CKA
);
    logic       qa       = 1'b0;
    logic [2:0] qbcd     = 3'b0;   // {QD, QC, QB}
    logic       cka_prev = 1'b0;
    logic       ckb_prev = 1'b0;

    wire r0 = pin2 & pin3;
    wire r9 = pin6 & pin7;

    always_ff @(posedge clk_sys) begin
        cka_prev <= pin14;
        ckb_prev <= pin1;

        if (r0) begin
            qa   <= 1'b0;
            qbcd <= 3'b0;
        end else if (r9) begin
            qa   <= 1'b1;
            qbcd <= 3'b100;          // QD=1, QC=0, QB=0 → count = 4 → with QA=1 makes BCD 9
        end else begin
            if (~pin14 & cka_prev) qa   <= ~qa;
            if (~pin1  & ckb_prev) qbcd <= (qbcd == 3'd4) ? 3'd0 : qbcd + 3'd1;
        end
    end

    assign pin12 = qa;
    assign pin9  = qbcd[0];          // QB
    assign pin8  = qbcd[1];          // QC
    assign pin11 = qbcd[2];          // QD
endmodule
