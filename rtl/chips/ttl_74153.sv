// 74153 - Dual 4-to-1 multiplexer (shared select lines, per-channel enable)
//        +---+--+---+
//   /G1 |1  +--+ 16| VCC
//  SEL B|2       15| /G2
//  1C3  |3       14| SEL A
//  1C2  |4       13| 2C3
//  1C1  |5 74153 12| 2C2
//  1C0  |6       11| 2C1
//   1Y  |7       10| 2C0
//  GND  |8        9| 2Y
//        +----------+
// Output Y_n = /G_n ? 0 : C_n[{SEL_B, SEL_A}].
// When the enable /G is asserted (LOW), the data input selected by {B,A} drives Y.
// When /G is HIGH, Y is forced LOW.
module ttl_74153 (
    input  logic pin1,    // /G1
    input  logic pin2,    // SEL_B
    input  logic pin3,    // 1C3
    input  logic pin4,    // 1C2
    input  logic pin5,    // 1C1
    input  logic pin6,    // 1C0
    output logic pin7,    // 1Y
    output logic pin9,    // 2Y
    input  logic pin10,   // 2C0
    input  logic pin11,   // 2C1
    input  logic pin12,   // 2C2
    input  logic pin13,   // 2C3
    input  logic pin14,   // SEL_A
    input  logic pin15    // /G2
);
    wire [1:0] sel = {pin2, pin14};   // {B, A}

    logic d1, d2;
    always_comb begin
        unique case (sel)
            2'b00: d1 = pin6;
            2'b01: d1 = pin5;
            2'b10: d1 = pin4;
            2'b11: d1 = pin3;
        endcase
        unique case (sel)
            2'b00: d2 = pin10;
            2'b01: d2 = pin11;
            2'b10: d2 = pin12;
            2'b11: d2 = pin13;
        endcase
    end

    assign pin7 = pin1  ? 1'b0 : d1;
    assign pin9 = pin15 ? 1'b0 : d2;
endmodule
