// 7427 - Triple 3-input NOR
//      +---+--+---+
//   1A |1  +--+ 14| VCC
//   1B |2       13| 1C
//   2A |3       12| 1Y
//   2B |4  7427 11| 3C
//   2C |5       10| 3B
//   2Y |6        9| 3A
//  GND |7        8| 3Y
//      +----------+
module ttl_7427 (
    input  logic pin1, pin2,          input  logic pin13,
    output logic pin12,
    input  logic pin3, pin4, pin5,
    output logic pin6,
    output logic pin8,
    input  logic pin9, pin10, pin11
);
    assign pin12 = ~(pin1 | pin2  | pin13);
    assign pin6  = ~(pin3 | pin4  | pin5);
    assign pin8  = ~(pin9 | pin10 | pin11);
endmodule
