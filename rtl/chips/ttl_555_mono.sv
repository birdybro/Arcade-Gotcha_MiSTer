// 555 - Universal timer, monostable mode
//      +---+--+---+
//  GND |1  +--+  8| VCC
//  /TR |2        7| Dis
//    Q |3   555  6| Thr
// /RST |4        5| CV
//      +----------+
// Monostable one-shot.  In the original the pulse width is set by an external
// RC; here PULSE_CYCLES gives it in clk_sys cycles (= LN_3 * R * C * f_clk_sys,
// LN_3 = 1.0986).  Behaviour (per DICE chips/555mono.cpp):
//   /RST (pin4) = 0          -> Q = 0 (overriding reset)
//   /TR  (pin2) falling edge -> Q = 1, (re)start the timing interval
//   while /TR is held low    -> Q stays 1 (pulse extends past the RC time)
//   timing interval elapsed AND /TR high -> Q = 0
// Only pin2 (/TR), pin3 (Q) and pin4 (/RST) are modeled; Dis/Thr/CV are the
// internal RC network, represented by the PULSE_CYCLES parameter.
module ttl_555_mono #(
    parameter int unsigned PULSE_CYCLES = 32'd2_579_750   // ~90ms at 28.636 MHz
) (
    input  logic clk_sys,
    input  logic pin2,    // /TR  (trigger, active-low)
    output logic pin3,    // Q    (output)
    input  logic pin4     // /RST (reset, active-low)
);
    logic [31:0] timer     = '0;
    logic        trig_prev = 1'b1;
    logic        q         = 1'b0;

    always_ff @(posedge clk_sys) begin
        trig_prev <= pin2;
        if (!pin4) begin
            timer <= '0;
        end else begin
            if      (~pin2 & trig_prev)  timer <= PULSE_CYCLES;   // /TR falling edge
            else if (timer != 32'd0)     timer <= timer - 32'd1;
        end
        // Q is high while the trigger is held low or the interval is running;
        // /RST forces it low.
        q <= pin4 & (~pin2 | (timer != 32'd0));
    end

    assign pin3 = q;
endmodule
