// 7430 - Single 8-input NAND
//      +---+--+---+
//    A |1  +--+ 14| VCC
//    B |2       13| NC
//    C |3       12| H
//    D |4  7430 11| G
//    E |5       10| NC
//    F |6        9| NC
//  GND |7        8| Y
//      +----------+
module ttl_7430 (
    input  logic pin1, pin2, pin3, pin4, pin5, pin6,
    output logic pin8,
    input  logic pin11, pin12
);
    assign pin8 = ~(pin1 & pin2 & pin3 & pin4 & pin5 & pin6 & pin11 & pin12);
endmodule
