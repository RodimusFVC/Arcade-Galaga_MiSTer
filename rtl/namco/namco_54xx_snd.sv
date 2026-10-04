//============================================================================
//
//  Namco 54xx noise generator: analog output stage
//
//  The 54xx MCU makes the noise itself and presents three 4-bit levels; the
//  board is a resistor DAC per level, three multiple-feedback band-pass
//  op-amp filters and a mixer. Per MAME galaga_a.cpp / polepos_a.cpp
//  (DISCRETE_DAC_R1 -> DISCRETE_OP_AMP_FILTER BAND_PASS_1M), 48 kHz.
//  Coefficients: verilator/noise54/coef.py.
//
//  BOARD 0: Galaga / Xevious / Bosconian parts, op-amp mixer 33k/33k/10k,
//           rF 3.3k, 0.1 uF output coupling, gain 40800, route 0.90
//  BOARD 1: Pole Position parts, outputs summed, route 0.90
//
//============================================================================

module namco_54xx_snd #(parameter BOARD = 0)
(
    input                   clk,            // 49.152 MHz
    input                   reset,
    input                   pause,

    input             [3:0] o0_data,        // O0-O3 -> CHANL3
    input             [3:0] o1_data,        // O4-O7 -> CHANL2
    input             [3:0] r1_data,        // R1    -> CHANL1

    output reg signed [15:0] audio = 16'sd0
);

// 48 kHz tick
reg [9:0] tick_div = 10'd0;
reg       tick = 1'b0;
always @(posedge clk) begin
    tick <= 1'b0;
    if (reset) tick_div <= 10'd0;
    else if (!pause) begin
        tick_div <= tick_div + 10'd1;
        if (tick_div == 10'd1023) tick <= 1'b1;
    end
end

// units: 1 V = 16384; filter state carries 8 more fraction bits (Q8)
localparam signed [35:0] CLIP_HI =  36'sd24576 <<< 8;   // vP - 1.5 V - vRef
localparam signed [35:0] CLIP_LO = -36'sd32768 <<< 8;   // vN - vRef

// 4 V ladder 47k / 22k / 10k / 4.7k, minus the 2.0 V reference
function automatic signed [17:0] dac(input [3:0] level);
    case (level)
        4'h0: dac = -18'sd32768;   4'h1: dac = -18'sd29094;
        4'h2: dac = -18'sd24918;   4'h3: dac = -18'sd21244;
        4'h4: dac = -18'sd15499;   4'h5: dac = -18'sd11825;
        4'h6: dac = -18'sd7649;    4'h7: dac = -18'sd3975;
        4'h8: dac =  18'sd3975;    4'h9: dac =  18'sd7649;
        4'hA: dac =  18'sd11825;   4'hB: dac =  18'sd15499;
        4'hC: dac =  18'sd21244;   4'hD: dac =  18'sd24918;
        4'hE: dac =  18'sd29094;   default: dac = 18'sd32768;
    endcase
endfunction

wire signed [17:0] dac_c1 = dac(r1_data);
wire signed [17:0] dac_c2 = dac(o1_data);
wire signed [17:0] dac_c3 = dac(o0_data);

reg        [1:0]  ch = 2'd0;                    // 0 CHANL1, 1 CHANL2, 2 CHANL3
reg        [2:0]  t = 3'd0;                     // term 0-5
reg               busy = 1'b0;
reg signed [31:0] x0 [3];
reg signed [31:0] x1 [3];
reg signed [31:0] x2 [3];
reg signed [31:0] y1 [3];
reg signed [31:0] y2 [3];
reg signed [63:0] acc;
reg signed [31:0] out_acc;

// b0, b1 (0), b2, -a1, -a2 in Q28
reg signed [31:0] coef;
always @(*) begin
    if (BOARD == 0)
        case ({ch, t})
            {2'd0,3'd0}: coef = -32'sd24476346;   {2'd0,3'd2}: coef =  32'sd24476346;      // 2521 Hz
            {2'd0,3'd3}: coef =  32'sd464692700;  {2'd0,3'd4}: coef = -32'sd222760339;
            {2'd1,3'd0}: coef = -32'sd5553176;    {2'd1,3'd2}: coef =  32'sd5553176;       //  450 Hz
            {2'd1,3'd3}: coef =  32'sd528600551;  {2'd1,3'd4}: coef = -32'sd261085262;
            {2'd2,3'd0}: coef = -32'sd1823723;    {2'd2,3'd2}: coef =  32'sd1823723;       //  167 Hz
            {2'd2,3'd3}: coef =  32'sd534373512;  {2'd2,3'd4}: coef = -32'sd266066400;
            default:     coef = 32'sd0;
        endcase
    else
        case ({ch, t})
            {2'd0,3'd0}: coef = -32'sd47137828;   {2'd0,3'd2}: coef =  32'sd47137828;      // 2325 Hz
            {2'd0,3'd3}: coef =  32'sd475273100;  {2'd0,3'd4}: coef = -32'sd229727338;
            {2'd1,3'd0}: coef = -32'sd7149718;    {2'd1,3'd2}: coef =  32'sd7149718;       //  232 Hz
            {2'd1,3'd3}: coef =  32'sd532422526;  {2'd1,3'd4}: coef = -32'sd264232598;
            {2'd2,3'd0}: coef = -32'sd2409029;    {2'd2,3'd2}: coef =  32'sd2409029;       //   74 Hz
            {2'd2,3'd3}: coef =  32'sd535526948;  {2'd2,3'd4}: coef = -32'sd267116643;
            default:     coef = 32'sd0;
        endcase
end

reg signed [31:0] operand;
always @(*) begin
    case (t)
        3'd0:    operand = x0[ch];
        3'd1:    operand = x1[ch];
        3'd2:    operand = x2[ch];
        3'd3:    operand = y1[ch];
        default: operand = y2[ch];
    endcase
end

wire signed [63:0] prod  = coef * operand;
wire signed [63:0] acc_r = acc + 64'sd134217728;            // round the Q28 product
wire signed [35:0] y_new = acc_r[63:28];
wire signed [35:0] y_c36 = (y_new > CLIP_HI) ? CLIP_HI : (y_new < CLIP_LO) ? CLIP_LO : y_new;
wire signed [31:0] y_cl  = y_c36[31:0];

// BOARD 0: inverting op-amp mixer, weight -rF / r_i (Q12), accumulated in Q8 volts.
// BOARD 1: weight 0.90 (Q12) straight to sample units, truncated per channel as the Pole Position core does.
wire signed [12:0] w_ch     = (BOARD == 0) ? ((ch == 2'd2) ? -13'sd1352 : -13'sd410) : 13'sd3686;
wire signed [44:0] wprod    = y_cl * w_ch;
wire signed [31:0] out_next = (BOARD == 0) ? out_acc + wprod[43:12] : out_acc + {{12{wprod[44]}}, wprod[39:20]};

// BOARD 0 output: 0.1 uF coupling into 100k (high-pass, MAME cAmp), then 40800 / 32768 * 0.90 per volt
reg  signed [31:0] hp_cap = 32'sd0;
wire signed [31:0] hp_in       = out_next - hp_cap;
wire signed [48:0] hp_d        = hp_in * 17'sd136;               // 1 - exp(-1 / (10 ms * 48 kHz)), Q16
wire signed [31:0] hp_cap_next = hp_cap + hp_d[47:16];
wire signed [31:0] hp_v        = out_next - hp_cap_next;
wire signed [47:0] g0          = hp_v * 15'sd9180;                              // 36720 / 4, Q8 volts = 2^22 per volt

function automatic signed [15:0] sat16(input signed [47:0] v);
    sat16 = (v > 48'sd32767) ? 16'sh7FFF : (v < -48'sd32768) ? 16'sh8000 : v[15:0];
endfunction

integer k;
always @(posedge clk) begin
    if (reset) begin
        busy <= 1'b0; ch <= 2'd0; t <= 3'd0; acc <= 64'sd0; out_acc <= 32'sd0; audio <= 16'sd0; hp_cap <= 32'sd0;
        for (k = 0; k < 3; k = k + 1) begin
            x0[k] <= 32'sd0; x1[k] <= 32'sd0; x2[k] <= 32'sd0; y1[k] <= 32'sd0; y2[k] <= 32'sd0;
        end
    end
    else if (!busy) begin
        if (tick) begin
            x0[0] <= {{6{dac_c1[17]}}, dac_c1, 8'd0};
            x0[1] <= {{6{dac_c2[17]}}, dac_c2, 8'd0};
            x0[2] <= {{6{dac_c3[17]}}, dac_c3, 8'd0};
            busy <= 1'b1; ch <= 2'd0; t <= 3'd0; acc <= 64'sd0; out_acc <= 32'sd0;
        end
    end
    else if (t != 3'd5) begin
        acc <= acc + prod;
        t   <= t + 3'd1;
    end
    else begin
        x2[ch] <= x1[ch];
        x1[ch] <= x0[ch];
        y2[ch] <= y1[ch];
        y1[ch] <= y_cl;                                     // clipped, as MAME
        acc    <= 64'sd0;
        t      <= 3'd0;
        if (ch == 2'd2) begin
            busy <= 1'b0;
            if (BOARD == 0) begin
                hp_cap <= hp_cap_next;
                audio  <= sat16(g0 >>> 20);
            end
            else audio <= sat16({{16{out_next[31]}}, out_next});
        end
        else begin
            out_acc <= out_next;
            ch      <= ch + 2'd1;
        end
    end
end

endmodule
