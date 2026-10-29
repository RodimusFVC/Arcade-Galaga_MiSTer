//  Based on MAME starfield_05xx.cpp (Robert Hildinger, BSD-3-Clause)

module namco_05xx
(
    input               clk,
    input               ce6,
    input               pause,
    input               line_step,
    input         [8:0] vcnt,
    input               win,

    input         [2:0] speed_x,
    input         [2:0] speed_y,
    input         [1:0] set_a,
    input         [1:0] set_b,
    input               enable,

    output              star,
    output        [5:0] color
);

reg  [15:0] lfsr = 16'h7FFF;
reg  [15:0] lfsr_frame = 16'h7FFF;
reg  [13:0] bulk = 14'd0;
reg         en = 1'b0;
reg   [1:0] sa, sb;
reg   [2:0] sy = 3'd0;

wire [15:0] lfsr_next = {lfsr[0] ^ lfsr[3] ^ lfsr[5] ^ lfsr[10], lfsr[15:1]};
wire  [1:0] set = {lfsr[10], lfsr[8]};
assign star  = en && win && ((lfsr & 16'hFA14) == 16'h7800) && (set == sa || set == sb);
assign color = ~{lfsr[4], lfsr[1], lfsr[0], lfsr[7], lfsr[6], lfsr[5]};

function [13:0] frame_steps(input [2:0] y);
    case (y)
        3'd0: frame_steps = 14'd8188;
        3'd1: frame_steps = 14'd8444;
        3'd2: frame_steps = 14'd8700;
        3'd3: frame_steps = 14'd8956;
        3'd4: frame_steps = 14'd7164;
        3'd5: frame_steps = 14'd7420;
        3'd6: frame_steps = 14'd7676;
        3'd7: frame_steps = 14'd7932;
    endcase
endfunction

function [2:0] x_steps(input [2:0] q);
    case (q)
        3'd0: x_steps = 3'd4; 3'd1: x_steps = 3'd5; 3'd2: x_steps = 3'd6; 3'd3: x_steps = 3'd7;
        3'd4: x_steps = 3'd0; 3'd5: x_steps = 3'd1; 3'd6: x_steps = 3'd2; 3'd7: x_steps = 3'd3;
    endcase
endfunction

always @(posedge clk) begin
    if (line_step && vcnt == 9'd15) begin
        en <= enable;
        sa <= set_a;
        sb <= set_b;
        sy <= speed_y;
        if (!enable) lfsr <= 16'h7FFF;
        else begin
            bulk <= {11'd0, x_steps(speed_x)};
            if (pause) lfsr <= lfsr_frame;
        end
        if (!pause) lfsr_frame <= enable ? lfsr : 16'h7FFF;
    end
    else if (line_step && vcnt == 9'd239) begin
        if (en) bulk <= frame_steps(sy);
    end
    else if (bulk != 14'd0) begin
        bulk <= bulk - 14'd1;
        lfsr <= lfsr_next;
    end
    else if (ce6 && en && win) lfsr <= lfsr_next;
end

endmodule
