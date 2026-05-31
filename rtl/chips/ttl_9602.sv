// 9602 - Dual retriggerable monostable multivibrator (with overriding /RST)
//        +---+--+---+
// 1Cext |1  +--+ 16| VCC
//1RCext |2       15| 2RCext
// /1RST |3       14| 2Cext
//   1TR |4   9602 13| /2RST
//  /1TR |5       12| 2TR
//    1Q |6       11| /2TR
//   /1Q |7       10| 2Q
//   GND |8        9| /2Q
//        +----------+
// In the original silicon the pulse width is set by an external RC; here it
// is provided in clk_sys cycles via the PULSE_A_CYCLES / PULSE_B_CYCLES
// parameters per gotcha.cpp's RC values multiplied by clk_sys frequency.
//
// Trigger logic (per DICE chips/9602.cpp):
//   TRIG = TRIG1 | ~TRIG2          (combinational)
//   Pulse fires on POS_EDGE of TRIG.
//   While the pulse is active, Q=1, /Q=0; pulse retriggers if TRIG fires again.
//   /RST = 0 forces Q = 0 immediately and stops the timer.
module ttl_9602 #(
    // Defaults scaled for clk_sys = 28.636 MHz (every instance overrides these).
    parameter int unsigned PULSE_A_CYCLES = 32'd209_000,    // ~7.3ms at 28.636 MHz
    parameter int unsigned PULSE_B_CYCLES = 32'd20_864_000  // ~728ms at 28.636 MHz
) (
    input  logic clk_sys,
    input  logic rst,     // synchronous reset to power-on state

    // Half A
    input  logic pin3,    // /1RST
    input  logic pin4,    // 1TR  (TRIG1)
    input  logic pin5,    // /1TR (TRIG2)
    output logic pin6,    // 1Q
    output logic pin7,    // /1Q

    // Half B
    input  logic pin11,   // /2TR (TRIG2)
    input  logic pin12,   // 2TR  (TRIG1)
    input  logic pin13,   // /2RST
    output logic pin10,   // 2Q
    output logic pin9     // /2Q
);
    wire trig_a = pin4  | ~pin5;
    wire trig_b = pin12 | ~pin11;

    logic        trig_a_prev = 1'b0;
    logic        trig_b_prev = 1'b0;
    logic [31:0] timer_a     = '0;
    logic [31:0] timer_b     = '0;
    logic        q_a         = 1'b0;
    logic        q_b         = 1'b0;

    always_ff @(posedge clk_sys) begin
        if (rst) begin
            timer_a <= '0; q_a <= 1'b0; trig_a_prev <= 1'b0;
            timer_b <= '0; q_b <= 1'b0; trig_b_prev <= 1'b0;
        end else begin
        trig_a_prev <= trig_a;
        trig_b_prev <= trig_b;

        // ------- Half A -------
        if (!pin3) begin
            timer_a <= '0;
            q_a     <= 1'b0;
        end else if (trig_a & ~trig_a_prev) begin
            timer_a <= PULSE_A_CYCLES;
            q_a     <= 1'b1;
        end else if (timer_a != 32'd0) begin
            timer_a <= timer_a - 32'd1;
            if (timer_a == 32'd1) q_a <= 1'b0;
        end

        // ------- Half B -------
        if (!pin13) begin
            timer_b <= '0;
            q_b     <= 1'b0;
        end else if (trig_b & ~trig_b_prev) begin
            timer_b <= PULSE_B_CYCLES;
            q_b     <= 1'b1;
        end else if (timer_b != 32'd0) begin
            timer_b <= timer_b - 32'd1;
            if (timer_b == 32'd1) q_b <= 1'b0;
        end
        end
    end

    assign pin6  =  q_a;
    assign pin7  = ~q_a;
    assign pin10 =  q_b;
    assign pin9  = ~q_b;
endmodule
