//============================================================================
//
//  Namco 05xx starfield
//
//  Per MAME starfield_05xx.cpp (R. Hildinger): 16-bit Fibonacci LFSR (taps
//  16, 13, 11, 6), one step per pixel across a 256-pixel window of each of
//  the 224 visible lines; a hit (state & FA14 == 7800) is a star of set
//  {b10, b8} and colour ~{b4, b1, b0, b7, b6, b5} (BBGGRR). The rest of each
//  frame's steps (pre / post visible lines, X and Y scroll) run at fabric
//  speed in vertical blank: post + pre at the end of the visible area with
//  the current Y speed, and the X adjustment when the speeds are latched.
//
//============================================================================

module namco_05xx
(
    input               clk,
    input               ce6,
    input               line_step,      // end of line: vcnt advances
    input         [8:0] vcnt,
    input               win,            // this pixel is inside the 256-pixel window of a visible line

    input         [2:0] speed_x,
    input         [2:0] speed_y,
    input         [1:0] set_a,
    input         [1:0] set_b,
    input               enable,

    output              star,           // a star of an active set is at this pixel
    output        [5:0] color           // BBGGRR
);

reg  [15:0] lfsr = 16'h7FFF;
reg  [13:0] bulk = 14'd0;
reg         en = 1'b0;
reg   [1:0] sa, sb;
reg   [2:0] sy = 3'd0;

wire [15:0] lfsr_next = {lfsr[0] ^ lfsr[3] ^ lfsr[5] ^ lfsr[10], lfsr[15:1]};
wire  [1:0] set = {lfsr[10], lfsr[8]};
assign star  = en && win && ((lfsr & 16'hFA14) == 16'h7800) && (set == sa || set == sb);
assign color = ~{lfsr[4], lfsr[1], lfsr[0], lfsr[7], lfsr[6], lfsr[5]};

// pre-visible + post-visible lines (x 256) per Y speed, less the 4 steps the X adjustment adds back
function [13:0] frame_steps(input [2:0] y);
    case (y)
        3'd0: frame_steps = 14'd8188;   // 22 + 10
        3'd1: frame_steps = 14'd8444;   // 23 + 10
        3'd2: frame_steps = 14'd8700;   // 22 + 12
        3'd3: frame_steps = 14'd8956;   // 23 + 12
        3'd4: frame_steps = 14'd7164;   // 19 + 9
        3'd5: frame_steps = 14'd7420;   // 20 + 9
        3'd6: frame_steps = 14'd7676;   // 20 + 10
        3'd7: frame_steps = 14'd7932;   // 22 + 9
    endcase
endfunction

// X speed: 4 + (0, 1, 2, 3, -4, -3, -2, -1)
function [2:0] x_steps(input [2:0] q);
    case (q)
        3'd0: x_steps = 3'd4; 3'd1: x_steps = 3'd5; 3'd2: x_steps = 3'd6; 3'd3: x_steps = 3'd7;
        3'd4: x_steps = 3'd0; 3'd5: x_steps = 3'd1; 3'd6: x_steps = 3'd2; 3'd7: x_steps = 3'd3;
    endcase
endfunction

always @(posedge clk) begin
    if (line_step && vcnt == 9'd15) begin                  // vblank ends: speeds, sets and enable latched
        en <= enable;
        sa <= set_a;
        sb <= set_b;
        sy <= speed_y;
        if (!enable) lfsr <= 16'h7FFF;
        else bulk <= {11'd0, x_steps(speed_x)};
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
