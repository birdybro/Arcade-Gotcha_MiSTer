// 7402 - Quad 2-input NOR (note: pin order differs from 7400)
//      +---+--+---+
//   1Y |1  +--+ 14| VCC
//   1A |2       13| 4Y
//   1B |3       12| 4A
//   2Y |4  7402 11| 4B
//   2A |5       10| 3Y
//   2B |6        9| 3A
//  GND |7        8| 3B
//      +----------+
module ttl_7402 (
    output logic pin1,    input  logic pin2, pin3,
    output logic pin4,    input  logic pin5, pin6,
    input  logic pin8, pin9,    output logic pin10,
    input  logic pin11, pin12,  output logic pin13
);
    assign pin1  = ~(pin2  | pin3);
    assign pin4  = ~(pin5  | pin6);
    assign pin10 = ~(pin8  | pin9);
    assign pin13 = ~(pin11 | pin12);
endmodule
