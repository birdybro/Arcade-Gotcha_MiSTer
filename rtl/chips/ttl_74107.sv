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
// Every instance (including the J6 master clock divider) edge-detects its CP
// pin against clk_sys.  clk_sys runs faster than every chip clock — J6 sees
// the CLOCK_14M net (clk_sys/2) on CP1 — so a single posedge-clk_sys edge
// detector is sufficient and accurate for all instances.
module ttl_74107 (
    input  logic clk_sys,
    input  logic rst,     // synchronous reset to power-on state
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
        if (rst) begin
            q1 <= 1'b0; q2 <= 1'b0;
            cp1_prev <= 1'b0; cp2_prev <= 1'b0;
        end else begin
        cp1_prev <= pin12;
        cp2_prev <= pin9;

        // FF1 — negative-edge triggered on CP1
        if (!pin13)        q1 <= 1'b0;
        else if (~pin12 & cp1_prev) begin
            unique case ({pin1, pin4})
                2'b01: q1 <= 1'b0;
                2'b10: q1 <= 1'b1;
                2'b11: q1 <= ~q1;
                default: ;  // hold
            endcase
        end

        // FF2 — negative-edge triggered on CP2
        if (!pin10)        q2 <= 1'b0;
        else if (~pin9 & cp2_prev) begin
            unique case ({pin8, pin11})
                2'b01: q2 <= 1'b0;
                2'b10: q2 <= 1'b1;
                2'b11: q2 <= ~q2;
                default: ;
            endcase
        end
        end
    end

    assign pin3 =  q1;
    assign pin2 = ~q1;
    assign pin5 =  q2;
    assign pin6 = ~q2;
endmodule
