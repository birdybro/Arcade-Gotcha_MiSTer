// 7474 - Dual D-FF with async preset and clear, positive-edge triggered
//        +---+--+---+
// /CLR1 |1  +--+ 14| VCC
//    D1 |2       13| /CLR2
//   CK1 |3       12| D2
//  /PR1 |4  7474 11| CK2
//    Q1 |5       10| /PR2
//   /Q1 |6        9| Q2
//   GND |7        8| /Q2
//        +----------+
// Async: !CLR=0 -> q=0 (overrides !PR), !PR=0 -> q=1
module ttl_7474 (
    input  logic clk_sys,
    input  logic pin1,    // /CLR1
    input  logic pin2,    // D1
    input  logic pin3,    // CK1
    input  logic pin4,    // /PR1
    output logic pin5,    // Q1
    output logic pin6,    // /Q1
    output logic pin8,    // /Q2
    output logic pin9,    // Q2
    input  logic pin10,   // /PR2
    input  logic pin11,   // CK2
    input  logic pin12,   // D2
    input  logic pin13    // /CLR2
);
    logic q1 = 1'b0;
    logic q2 = 1'b0;
    logic ck1_prev = 1'b0;
    logic ck2_prev = 1'b0;

    always_ff @(posedge clk_sys) begin
        ck1_prev <= pin3;
        ck2_prev <= pin11;

        if (!pin1)                  q1 <= 1'b0;
        else if (!pin4)             q1 <= 1'b1;
        else if (pin3 & ~ck1_prev)  q1 <= pin2;

        if (!pin13)                 q2 <= 1'b0;
        else if (!pin10)            q2 <= 1'b1;
        else if (pin11 & ~ck2_prev) q2 <= pin12;
    end

    assign pin5 =  q1;
    assign pin6 = ~q1;
    assign pin9 =  q2;
    assign pin8 = ~q2;
endmodule
