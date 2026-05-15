// 7420 - Dual 4-input NAND
//      +---+--+---+
//   1A |1  +--+ 14| VCC
//   1B |2       13| 2D
//   NC |3       12| 2C
//   1C |4  7420 11| NC
//   1D |5       10| 2B
//   1Y |6        9| 2A
//  GND |7        8| 2Y
//      +----------+
module ttl_7420 (
    input  logic pin1, pin2, pin4, pin5,    output logic pin6,
    input  logic pin9, pin10, pin12, pin13, output logic pin8
);
    assign pin6 = ~(pin1 & pin2  & pin4  & pin5);
    assign pin8 = ~(pin9 & pin10 & pin12 & pin13);
endmodule
