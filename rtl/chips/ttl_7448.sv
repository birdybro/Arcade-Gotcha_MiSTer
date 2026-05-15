// 7448 - BCD-to-7-segment decoder (active-high outputs)
//        +---+--+---+
//     B |1  +--+ 16| VCC
//     C |2       15| f
//   /LT |3       14| g
// /BIRO |4  7448 13| a
//  /RBI |5       12| b
//     D |6       11| c
//     A |7       10| d
//   GND |8        9| e
//        +----------+
// Inputs: A (pin7), B (pin1), C (pin2), D (pin6) form BCD value {D,C,B,A}.
// /LT (pin3, active-low lamp test): when 0, all 7 segments ON.
// /BI  (pin4, active-low blanking input): when 0, all 7 segments OFF (priority over /LT).
//      In real silicon pin4 is bidirectional (/BI input or /RBO output) — here we
//      model it as input only, which is how Gotcha's J7 uses it.
// /RBI (pin5, active-low ripple-blanking input): when 0 AND BCD=0, segments OFF.
// Segment outputs a..g are active-HIGH; pin map a=13, b=12, c=11, d=10, e=9, f=15, g=14.
module ttl_7448 (
    input  logic pin1,    // B
    input  logic pin2,    // C
    input  logic pin3,    // /LT
    input  logic pin4,    // /BI
    input  logic pin5,    // /RBI
    input  logic pin6,    // D
    input  logic pin7,    // A
    output logic pin9,    // e
    output logic pin10,   // d
    output logic pin11,   // c
    output logic pin12,   // b
    output logic pin13,   // a
    output logic pin14,   // g
    output logic pin15    // f
);
    wire [3:0]  bcd = {pin6, pin2, pin1, pin7};   // D C B A
    logic [6:0] segs;                              // {a, b, c, d, e, f, g}

    always_comb begin
        unique case (bcd)
            4'd0:  segs = 7'b1111110;
            4'd1:  segs = 7'b0110000;
            4'd2:  segs = 7'b1101101;
            4'd3:  segs = 7'b1111001;
            4'd4:  segs = 7'b0110011;
            4'd5:  segs = 7'b1011011;
            4'd6:  segs = 7'b0011111;
            4'd7:  segs = 7'b1110000;
            4'd8:  segs = 7'b1111111;
            4'd9:  segs = 7'b1111011;
            4'd10: segs = 7'b0001101;
            4'd11: segs = 7'b0011001;
            4'd12: segs = 7'b0100011;
            4'd13: segs = 7'b1001011;
            4'd14: segs = 7'b0001111;
            4'd15: segs = 7'b0000000;
        endcase

        if      (!pin4)                  segs = 7'b0000000;   // /BI  forces blank (highest priority)
        else if (!pin3)                  segs = 7'b1111111;   // /LT  forces all on
        else if (!pin5 && bcd == 4'd0)   segs = 7'b0000000;   // /RBI blanks leading zero
    end

    assign {pin13, pin12, pin11, pin10, pin9, pin15, pin14} = segs;
endmodule
