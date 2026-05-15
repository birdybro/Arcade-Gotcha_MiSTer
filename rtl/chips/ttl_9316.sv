// 9316 / 74LS161 - 4-bit synchronous binary counter with sync clear, sync load
//        +---+--+---+
//   /MR |1  +--+ 16| VCC
//    CP |2       15| TC (ripple carry out)
//    P0 |3       14| Q0
//    P1 |4  9316 13| Q1
//    P2 |5       12| Q2
//    P3 |6       11| Q3
//   CEP |7       10| CET
//   GND |8        9| /PE
//        +----------+
// All control is SYNCHRONOUS to the rising edge of CP:
//   /MR=0 -> Q=0000 (sync clear, priority).
//   /PE=0 -> Q={P3,P2,P1,P0} (sync load).
//   CEP=CET=1 with /MR=1, /PE=1 -> Q++ (count up).
//   else -> hold.
// TC = Q3 & Q2 & Q1 & Q0 & CET (combinational; goes HIGH the cycle Q reaches 15).
module ttl_9316 (
    input  logic clk_sys,
    input  logic pin1,    // /MR
    input  logic pin2,    // CP
    input  logic pin3,    // P0
    input  logic pin4,    // P1
    input  logic pin5,    // P2
    input  logic pin6,    // P3
    input  logic pin7,    // CEP
    input  logic pin9,    // /PE
    input  logic pin10,   // CET
    output logic pin11,   // Q3
    output logic pin12,   // Q2
    output logic pin13,   // Q1
    output logic pin14,   // Q0
    output logic pin15    // TC
);
    logic [3:0] q       = 4'b0;
    logic       cp_prev = 1'b0;

    always_ff @(posedge clk_sys) begin
        cp_prev <= pin2;
        if (pin2 & ~cp_prev) begin                  // rising edge of CP
            if      (!pin1)            q <= 4'b0;
            else if (!pin9)            q <= {pin6, pin5, pin4, pin3};
            else if (pin7 & pin10)     q <= q + 4'd1;
        end
    end

    assign pin14 = q[0];
    assign pin13 = q[1];
    assign pin12 = q[2];
    assign pin11 = q[3];
    assign pin15 = (&q) & pin10;
endmodule
