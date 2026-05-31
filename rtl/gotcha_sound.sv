// ======================================================================
// gotcha_sound — the analog/custom sound chips of Atari Gotcha, modeled
// behaviourally (the digital TTL gates A10/D2/L4/M4/B7 stay in gotcha.sv).
//
// Mirrors three DICE custom blocks (docs/DICE/games/gotcha.cpp,
// docs/DICE/chips/{555astable,mixer}.cpp; PROXIMITY is inline in gotcha.cpp):
//
//   PROXIMITY — an RC cap (r=1.5k, C=0.1µF -> τ≈150µs) that low-passes a
//     control voltage selected by the 2-bit {D2.11,D2.3} player-proximity
//     value.  DICE: v = v_th[idx]; if v > 2.0V, v = 4.8V (cutoff); cap charges
//     toward v.  The cap voltage is E8's control voltage (CV).
//
//   E8 — a 555 astable (R1=200k, R2=100k, C=1µF) whose CV is the PROXIMITY
//     cap.  Output Q is HIGH while the timing cap charges toward 5V through
//     R1+R2 (τ=0.3s) up to CV, LOW while it discharges through R2 (τ=0.1s)
//     down to CV/2.  As the players align, CV drops, the charge interval
//     shrinks, and the "footstep" quickens (~1.2 Hz far -> ~8.4 Hz aligned).
//     /RST = ATTRACT_n holds Q low in attract mode.  This is modeled as the
//     actual cap charge/discharge (not a frequency LUT), matching DICE's
//     analytical 555: hi = -ln((5-CV)/(5-CV/2))·(R1+R2)·C, lo = ln2·R2·C.
//
//   MIXER1/MIXER2 — resistor-network analog summing.  From the DICE descs
//     (mixer1 = {1k} into 1k -> ×0.5; mixer2 = {1k,1.5k} -> 0.6·in1 + 0.4·in2)
//     the final output is 0.6·catch + 0.2·proximity, i.e. the catch source is
//     3× the proximity source.  The framework IIR LPF + DC-blocker finish the
//     chain, so we emit the raw weighted sum as signed PCM.
//
// Fixed point: voltages are Q16.16 (volts << 16).  The RC integrators use
// shift-only one-poles (no multiplies); update cadences are chosen so the
// shift amounts land on the real time constants.  See the localparams.
// ======================================================================
module gotcha_sound (
    input  logic               clk_sys,
    input  logic        [1:0]  prox_in,     // {D2_pin11, D2_pin3} proximity value
    input  logic               attract_n,   // E8 /RST (held low in attract)
    input  logic               src_prox,    // M4.3 proximity audio source (V8-gated)
    input  logic               src_catch,   // M4.6 catch audio source (V8 & CATCHOS)
    output logic               e8_out,      // E8.3 -> netlist L4.2
    output logic signed [15:0] audio        // mixed mono PCM (signed)
);
    // ---- Q16.16 voltage constants ------------------------------------
    localparam signed [31:0] V5    = 32'sd327680;  // 5.000 V
    localparam signed [31:0] V48   = 32'sd314573;  // 4.800 V  (cutoff target)
    localparam signed [31:0] V1337 = 32'sd87622;   // 1.337 V  (v_th[0])
    localparam signed [31:0] V1521 = 32'sd99680;   // 1.521 V  (v_th[1])

    // ---- PROXIMITY: one-pole RC cap (τ≈150µs) -> E8 control voltage ---
    //   v_th[idx] with the DICE >2.0V cutoff: idx 0/1 -> 1.337/1.521V (used
    //   directly), idx 2/3 -> 2.737/3.815V which both exceed 2.0V -> 4.8V.
    //   Updated every 64 clk (T=2.23µs); >>6 gives τ = 64·T ≈ 143µs ≈ 150µs.
    logic signed [31:0] v_target;
    always_comb begin
        case (prox_in)
            2'd0:    v_target = V1337;
            2'd1:    v_target = V1521;
            default: v_target = V48;     // idx 2,3 -> cutoff
        endcase
    end

    logic signed [31:0] v_cap   = V48;   // CV; power up at "far" (idle)
    logic        [5:0]  prox_div = '0;
    always_ff @(posedge clk_sys) begin
        prox_div <= prox_div + 6'd1;
        if (prox_div == 6'd0)
            v_cap <= v_cap + ((v_target - v_cap) >>> 6);
    end

    // ---- E8: behavioural 555 astable, CV = v_cap --------------------
    //   Updated every 1024 clk (T=35.76µs).  Charge toward 5V: >>13 gives
    //   τ = 8192·T = 0.293s ≈ (R1+R2)C=0.3s.  Discharge toward 0: (>>12+>>13)
    //   = ×3/8192 gives τ = (8192/3)·T = 0.098s ≈ R2·C=0.1s.  Q HIGH while
    //   charging.  /RST (attract_n low) holds Q low and the cap discharged.
    logic signed [31:0] v_e8   = '0;
    logic               e8_q   = 1'b0;
    logic        [9:0]  e8_div = '0;
    always_ff @(posedge clk_sys) begin
        e8_div <= e8_div + 10'd1;
        if (!attract_n) begin
            v_e8 <= '0;
            e8_q <= 1'b0;
        end else if (e8_div == 10'd0) begin
            if (e8_q) begin                                      // charging (Q high)
                v_e8 <= v_e8 + ((V5 - v_e8) >>> 13);
                if (v_e8 >= v_cap)         e8_q <= 1'b0;          // hit CV -> discharge
            end else begin                                       // discharging (Q low)
                v_e8 <= v_e8 - ((v_e8 >>> 12) + (v_e8 >>> 13));
                if (v_e8 <= (v_cap >>> 1)) e8_q <= 1'b1;          // hit CV/2 -> charge
            end
        end
    end
    assign e8_out = e8_q;

    // ---- MIXER: 0.6·catch + 0.2·proximity (3:1) ----------------------
    //   Sources are 1-bit (0/5V); map each to ±amplitude in that ratio and sum.
    //   Registered for audio_out's stability synchroniser; the framework DC
    //   blocker removes the idle offset and its IIR LPF anti-aliases the square.
    localparam signed [15:0] CATCH_AMP = 16'sd18000;  // 0.6 weight
    localparam signed [15:0] PROX_AMP  = 16'sd6000;   // 0.2 weight
    logic signed [15:0] audio_q = '0;
    always_ff @(posedge clk_sys)
        audio_q <= (src_catch ? CATCH_AMP : -CATCH_AMP)
                 + (src_prox  ? PROX_AMP  : -PROX_AMP);
    assign audio = audio_q;
endmodule
