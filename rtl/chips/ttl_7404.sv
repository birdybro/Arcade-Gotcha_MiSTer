// 7404 - Hex inverter
//      +---+--+---+
//   1A |1  +--+ 14| VCC
//   1Y |2       13| 6A
//   2A |3       12| 6Y
//   2Y |4  7404 11| 5A
//   3A |5       10| 5Y
//   3Y |6        9| 4A
//  GND |7        8| 4Y
//      +----------+
module ttl_7404 (
    input  logic pin1,  output logic pin2,
    input  logic pin3,  output logic pin4,
    input  logic pin5,  output logic pin6,
    output logic pin8,  input  logic pin9,
    output logic pin10, input  logic pin11,
    output logic pin12, input  logic pin13
);
    assign pin2  = ~pin1;
    assign pin4  = ~pin3;
    assign pin6  = ~pin5;
    assign pin8  = ~pin9;
    assign pin10 = ~pin11;
    assign pin12 = ~pin13;
endmodule
