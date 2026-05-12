// 74107 - Dual JK FF with async clear, negative-edge triggered (master-slave)
//        +---+--+---+
//    J1 |1  +--+ 14| VCC
//   /Q1 |2       13| /CLR1
//    Q1 |3       12| CP1
//    K1 |4 74107 11| K2
//    Q2 |5       10| /CLR2
//   /Q2 |6        9| CP2
//   GND |7        8| J2
//        +----------+
// J=0,K=0: hold;  J=1,K=0: set;  J=0,K=1: reset;  J=1,K=1: toggle
// Async: /CLR=0 -> q=0
//
// Parameters CP1_IS_CLK_SYS / CP2_IS_CLK_SYS = 1 mean the chip's clock pin is
// wired to the FPGA system clock itself (the netlist's CLOCK net). In that mode
// the FF fires on every clk_sys posedge instead of edge-detecting the pin.
// Use this only for the master clock divider (J6 in Gotcha); all other 74107
// instances see derived signals on their CP pins and must edge-detect.
module ttl_74107 #(
    parameter int CP1_IS_CLK_SYS = 0,
    parameter int CP2_IS_CLK_SYS = 0
) (
    input  logic clk_sys,
    input  logic pin1,    // J1
    output logic pin2,    // /Q1
    output logic pin3,    // Q1
    input  logic pin4,    // K1
    output logic pin5,    // Q2
    output logic pin6,    // /Q2
    input  logic pin8,    // J2
    input  logic pin9,    // CP2
    input  logic pin10,   // /CLR2
    input  logic pin11,   // K2
    input  logic pin12,   // CP1
    input  logic pin13    // /CLR1
);
    logic q1 = 1'b0;
    logic q2 = 1'b0;
    logic cp1_prev = 1'b0;
    logic cp2_prev = 1'b0;

    always_ff @(posedge clk_sys) begin
        cp1_prev <= pin12;
        cp2_prev <= pin9;

        // FF1
        if (!pin13)        q1 <= 1'b0;
        else if ((CP1_IS_CLK_SYS != 0) || (~pin12 & cp1_prev)) begin
            unique case ({pin1, pin4})
                2'b01: q1 <= 1'b0;
                2'b10: q1 <= 1'b1;
                2'b11: q1 <= ~q1;
                default: ;  // hold
            endcase
        end

        // FF2
        if (!pin10)        q2 <= 1'b0;
        else if ((CP2_IS_CLK_SYS != 0) || (~pin9 & cp2_prev)) begin
            unique case ({pin8, pin11})
                2'b01: q2 <= 1'b0;
                2'b10: q2 <= 1'b1;
                2'b11: q2 <= ~q2;
                default: ;
            endcase
        end
    end

    assign pin3 =  q1;
    assign pin2 = ~q1;
    assign pin5 =  q2;
    assign pin6 = ~q2;
endmodule
