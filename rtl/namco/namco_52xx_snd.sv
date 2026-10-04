//============================================================================
//
//  Namco 52xx sample player: Bosconian analog output stage
//
//  Per MAME galaga_a.cpp bosco_discrete CHANL4: the 52xx P0-P3 levels through
//  a 4 V resistor DAC (100k / 47k / 22k / 10k), a 2nd-order 80 Hz high-pass
//  (damping 1/0.3), a 2nd-order 2400 Hz low-pass (damping 1/0.9) and a gain
//  of 0.25, at 48 kHz. Output in volts, 2^22 per volt, for namco_54xx_snd's
//  Bosconian mixer. Coefficients: verilator/noise54/coef52.py.
//
//============================================================================

module namco_52xx_snd
(
    input                    clk,            // 49.152 MHz
    input                    reset,
    input                    pause,
    input              [3:0] p_data,

    output reg signed [31:0] volts = 32'sd0
);

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

// DAC level in units of 1/16384 V
function automatic [16:0] dac(input [3:0] l);
    case (l)
        4'h0: dac = 17'd0;     4'h1: dac = 17'd3708;  4'h2: dac = 17'd7890;  4'h3: dac = 17'd11598;
        4'h4: dac = 17'd16856; 4'h5: dac = 17'd20564; 4'h6: dac = 17'd24745; 4'h7: dac = 17'd28454;
        4'h8: dac = 17'd37082; 4'h9: dac = 17'd40791; 4'hA: dac = 17'd44972; 4'hB: dac = 17'd48680;
        4'hC: dac = 17'd53938; 4'hD: dac = 17'd57646; 4'hE: dac = 17'd61828; default: dac = 17'd65536;
    endcase
endfunction

// state in units of 2^-22 V
reg signed [31:0] hx0, hx1, hx2, hy1, hy2;     // high-pass
reg signed [31:0] ly1, ly2, lx1, lx2;          // low-pass (its input is the high-pass output)
reg               stage;                        // 0 high-pass, 1 low-pass
reg         [2:0] t;
reg               busy = 1'b0;
reg signed [63:0] acc;
reg signed [31:0] hy_new_r;

// b0, b1, b2, -a1, -a2 (Q28)
reg signed [31:0] coef, operand;
always @(*) begin
    case ({stage, t})
        4'b0_000: coef =  32'sd263823591;  4'b0_001: coef = -32'sd527647181;  4'b0_010: coef = 32'sd263823591;
        4'b0_011: coef =  32'sd527632715;  4'b0_100: coef = -32'sd259226191;
        4'b1_000: coef =  32'sd5606569;    4'b1_001: coef =  32'sd11213138;   4'b1_010: coef = 32'sd5606569;
        4'b1_011: coef =  32'sd435781336;  4'b1_100: coef = -32'sd189772156;
        default:  coef =  32'sd0;
    endcase
    case ({stage, t})
        4'b0_000: operand = hx0;  4'b0_001: operand = hx1;  4'b0_010: operand = hx2;
        4'b0_011: operand = hy1;  4'b0_100: operand = hy2;
        4'b1_000: operand = hy_new_r;  4'b1_001: operand = lx1;  4'b1_010: operand = lx2;
        4'b1_011: operand = ly1;  4'b1_100: operand = ly2;
        default:  operand = 32'sd0;
    endcase
end

wire signed [63:0] prod  = coef * operand;
wire signed [63:0] acc_r = acc + 64'sd134217728;
wire signed [31:0] y_new = acc_r[59:28];

always @(posedge clk) begin
    if (reset) begin
        busy <= 1'b0; volts <= 32'sd0;
        hx0 <= 32'sd0; hx1 <= 32'sd0; hx2 <= 32'sd0; hy1 <= 32'sd0; hy2 <= 32'sd0;
        lx1 <= 32'sd0; lx2 <= 32'sd0; ly1 <= 32'sd0; ly2 <= 32'sd0;
    end
    else if (!busy) begin
        if (tick) begin
            hx0   <= {7'd0, dac(p_data), 8'd0};
            busy  <= 1'b1;
            stage <= 1'b0;
            t     <= 3'd0;
            acc   <= 64'sd0;
        end
    end
    else if (t != 3'd5) begin
        acc <= acc + prod;
        t   <= t + 3'd1;
    end
    else if (!stage) begin
        hx2 <= hx1; hx1 <= hx0;
        hy2 <= hy1; hy1 <= y_new;
        hy_new_r <= y_new;
        stage <= 1'b1; t <= 3'd0; acc <= 64'sd0;
    end
    else begin
        lx2 <= lx1; lx1 <= hy_new_r;
        ly2 <= ly1; ly1 <= y_new;
        volts <= y_new >>> 2;                       // gain 0.25
        busy  <= 1'b0;
    end
end

endmodule
