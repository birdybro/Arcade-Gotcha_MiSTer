// 7486 - Quad 2-input XOR
//      +---+--+---+
//   1A |1  +--+ 14| VCC
//   1B |2       13| 4B
//   1Y |3       12| 4A
//   2A |4  7486 11| 4Y
//   2B |5       10| 3B
//   2Y |6        9| 3A
//  GND |7        8| 3Y
//      +----------+
module ttl_7486 (
    input  logic pin1, pin2,   output logic pin3,
    input  logic pin4, pin5,   output logic pin6,
    output logic pin8,         input  logic pin9, pin10,
    output logic pin11,        input  logic pin12, pin13
);
    assign pin3  = pin1  ^ pin2;
    assign pin6  = pin4  ^ pin5;
    assign pin8  = pin9  ^ pin10;
    assign pin11 = pin12 ^ pin13;
endmodule
