// LATCH - DICE's generic "Electronic Latch" with power-on reset.
//        +---+--+---+
//   /SET |1  +--+  *| (no other pins)
// /RESET |2  LATCH  |
//      Q |3        *|
//        +----------+
// At power-on, Q starts LOW for ~1µs (the original schematic uses a capacitor
// charging through a resistor; here we model it with a short clk_sys-cycle
// counter).  After that initial pulse, Q is forced HIGH (the "power-on reset
// released" state).  Thereafter the latch behaves as an active-low SR latch:
//   /RESET=0 → Q=0
//   /SET  =0 → Q=1
//   both 1   → hold
// See docs/DICE/chips/latch.cpp for the reference implementation.
module ttl_latch (
    input  logic clk_sys,
    input  logic rst,     // synchronous reset: re-run the power-on sequence
    input  logic pin1,    // /SET
    input  logic pin2,    // /RESET
    output logic pin3     // Q
);
    // ~1µs at 14.318MHz ≈ 15 clk_sys cycles; round up to 32 for margin.
    localparam int INIT_HOLD_CYCLES = 32;

    logic [5:0] init_counter = '0;
    logic       initialized  = 1'b0;
    logic       q            = 1'b0;

    always_ff @(posedge clk_sys) begin
        if (rst) begin
            // Re-arm the power-on pulse: Q low, replay the ~1µs init so the
            // ATTRACT/game-state chain re-initialises exactly as at power-on.
            init_counter <= '0;
            initialized  <= 1'b0;
            q            <= 1'b0;
        end else if (!initialized) begin
            if (init_counter == INIT_HOLD_CYCLES - 1) begin
                initialized <= 1'b1;
                q           <= 1'b1;       // power-on reset transition: 0 → 1
            end else begin
                init_counter <= init_counter + 6'd1;
            end
        end else begin
            if      (!pin2) q <= 1'b0;     // active-low RESET (priority)
            else if (!pin1) q <= 1'b1;     // active-low SET
            // else hold previous value
        end
    end

    assign pin3 = q;
endmodule
