//  Based on MAME namco.cpp (Nicola Salmoria,Aaron Giles, BSD-3-Clause)

module namco_wsg3
(
    input                   clk,
    input                   reset,
    input                   pause,

    input             [4:0] reg_addr,
    input             [3:0] reg_data,
    input                   reg_wr,

    input             [7:0] wave_addr,
    input             [7:0] wave_data,
    input                   wave_wr,

    output reg signed [15:0] audio = 16'sd0
);

reg [3:0] regs[32];
always @(posedge clk) if (reg_wr) regs[reg_addr] <= reg_data;

reg [8:0] div = 9'd0;
always @(posedge clk) if (!pause) div <= div + 9'd1;

wire [19:0] freq[3];
assign freq[0] = {regs[5'h14], regs[5'h13], regs[5'h12], regs[5'h11], regs[5'h10]};
assign freq[1] = {regs[5'h19], regs[5'h18], regs[5'h17], regs[5'h16], 4'd0};
assign freq[2] = {regs[5'h1E], regs[5'h1D], regs[5'h1C], regs[5'h1B], 4'd0};
wire  [2:0] wsel[3];
assign wsel[0] = regs[5'h05][2:0];
assign wsel[1] = regs[5'h0A][2:0];
assign wsel[2] = regs[5'h0F][2:0];
wire  [3:0] vol[3];
assign vol[0] = regs[5'h15];
assign vol[1] = regs[5'h1A];
assign vol[2] = regs[5'h1F];

reg  [19:0] acc[3];
reg   [7:0] wave_rd;
wire  [7:0] wave_q;

dpram_dc #(.widthad_a(8)) wave_rom
(
    .clock_a(clk), .address_a(wave_rd), .data_a(8'h00), .wren_a(1'b0), .q_a(wave_q),
    .clock_b(clk), .address_b(wave_addr), .data_b(wave_data), .wren_b(wave_wr), .q_b()
);

reg  signed [10:0] mix;
reg   [1:0] v;
reg   [2:0] step;
wire signed [10:0] wave_s = $signed({7'd0, wave_q[3:0]}) - 11'sd8;
wire signed [10:0] term   = wave_s * $signed({7'd0, vol[v]});
always @(posedge clk) begin
    if (reset) begin
        acc[0] <= 20'd0; acc[1] <= 20'd0; acc[2] <= 20'd0;
        step   <= 3'd0;
        audio  <= 16'sd0;
    end
    else if (div == 9'd0 && !pause) begin
        v    <= 2'd0;
        mix  <= 11'sd0;
        step <= 3'd1;
    end
    else case (step)
        3'd1: begin wave_rd <= {wsel[v], acc[v][19:15]}; step <= 3'd2; end
        3'd2: step <= 3'd3;
        3'd3: begin
            mix    <= mix + term;
            if (vol[v] != 4'd0) acc[v] <= acc[v] + freq[v];
            if (v == 2'd2) step <= 3'd4;
            else begin v <= v + 2'd1; step <= 3'd1; end
        end
        3'd4: begin audio <= mix * 16'sd48; step <= 3'd0; end
        default: ;
    endcase
end

endmodule
