// 74157 - Quad 2-to-1 multiplexer (shared select, common active-low strobe)
//        +---+--+---+
//   SEL |1  +--+ 16| VCC
//    1A |2       15| /G
//    1B |3       14| 4A
//    1Y |4 74157 13| 4B
//    2A |5       12| 4Y
//    2B |6       11| 3A
//    2Y |7       10| 3B
//   GND |8        9| 3Y
//        +----------+
// Output Y_n = /G ? 0 : (SEL ? B_n : A_n).
// When /G (strobe) is LOW, mux passes through.  When /G is HIGH, all Y's forced LOW.
module ttl_74157 (
    input  logic pin1,    // SEL
    input  logic pin2,    // 1A
    input  logic pin3,    // 1B
    output logic pin4,    // 1Y
    input  logic pin5,    // 2A
    input  logic pin6,    // 2B
    output logic pin7,    // 2Y
    output logic pin9,    // 3Y
    input  logic pin10,   // 3B
    input  logic pin11,   // 3A
    output logic pin12,   // 4Y
    input  logic pin13,   // 4B
    input  logic pin14,   // 4A
    input  logic pin15    // /G
);
    wire enable = ~pin15;
    assign pin4  = enable ? (pin1 ? pin3  : pin2 ) : 1'b0;
    assign pin7  = enable ? (pin1 ? pin6  : pin5 ) : 1'b0;
    assign pin9  = enable ? (pin1 ? pin10 : pin11) : 1'b0;
    assign pin12 = enable ? (pin1 ? pin13 : pin14) : 1'b0;
endmodule
