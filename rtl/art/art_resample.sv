//============================================================================
//
//  Artwork resampler: scales a raster-order RGBA stream (src_w x src_h) to dst_w x dst_h
//  Copyright (C) 2026 Rodimus
//
//  Downscale = area average (box filter), upscale = pixel replication, per axis. Each destination row is
//  built in a 2048-entry line buffer of per-channel sums, then emitted left to right (divided by the
//  pixel count). flipx mirrors the row. Limits: dst_w <= 2048, downscale factor <= 15 per axis.
//
//  Redistribution and use in source and synthesized forms, with or without modification, are permitted
//  provided that the above copyright notice is retained. THIS SOFTWARE IS PROVIDED "AS IS" WITHOUT WARRANTY.
//
//============================================================================

module art_resample
(
    input             clk,
    input             start,          // one clock: latch sizes, begin a new image
    input      [12:0] src_w,          // up to 8191 (MAME bezels reach 7183 x 7726)
    input      [12:0] src_h,
    input      [11:0] dst_w,
    input      [11:0] dst_h,
    input             flipx,

    input             in_valid,
    input      [31:0] in_px,          // {R, G, B, A}
    output            in_ready,

    output reg        out_valid = 1'b0,
    output reg [31:0] out_px = 32'd0,
    input             out_ready,
    output reg        done = 1'b1     // every destination row emitted
);

localparam S_IN = 3'd0, S_FLUSH = 3'd1, S_ROWEND = 3'd2, S_EMIT_RD = 3'd3, S_EMIT_WAIT = 3'd4, S_LOAD = 3'd5, S_DIV = 3'd6, S_OUT = 3'd7;
reg   [2:0] st = S_OUT;
reg         idle = 1'b1;

reg  [12:0] sw, sh;
reg  [11:0] dw, dh;
reg         flip;
wire        hdown = dw <= sw;
wire        vdown = dh <= sh;

function [10:0] mirror(input [11:0] d, input f, input [11:0] w);
    mirror = f ? 11'(w - 12'd1 - d) : d[10:0];
endfunction

// horizontal accumulator for the destination pixel being built
reg  [11:0] dx, cur_dx;
reg  [12:0] sx;
reg  [23:0] hacc, vacc;
reg  [63:0] hsum;
reg   [7:0] hcnt;
reg         hact;                     // hsum holds a contribution
reg         first_row;                // first source row of this destination row: overwrite, not add
reg   [7:0] vcnt;                     // source rows summed into the line buffer
reg  [11:0] rows_out, ex;

assign in_ready = idle || (st == S_IN && (hdown || (hacc + {11'd0, sw} >= {12'd0, dw})));
wire   new_dx   = st == S_IN && in_valid && !(hact && dx == cur_dx);

// line buffer: {count[7:0], R[15:0], G[15:0], B[15:0], A[15:0]}; the read address is presented
// combinationally when a destination pixel starts, so its old sum is on rq from the next clock
reg  [10:0] wa, ra_hold;
reg  [71:0] wd;
reg         we;
wire [71:0] rq;
wire [10:0] ra = new_dx ? mirror(dx, flip, dw) : ra_hold;
dpram_dc #(.widthad_a(11), .width_a(72)) lbuf
(
    .clock_a(clk), .address_a(wa), .data_a(wd), .wren_a(we), .q_a(),
    .clock_b(clk), .address_b(ra), .data_b('0), .wren_b(1'b0), .q_b(rq)
);

wire [63:0] px_ext = {8'd0, in_px[31:24], 8'd0, in_px[23:16], 8'd0, in_px[15:8], 8'd0, in_px[7:0]};
wire [71:0] flush_val = {hcnt, first_row ? hsum : (hsum + rq[63:0])};

// emit: (sum + div / 2) / div per channel, div = pixels summed; restoring divide, 8 quotient bits
wire  [7:0] div_n = 8'(rq[71:64] * vcnt);
reg   [7:0] div;
reg  [15:0] rem[4];
reg   [7:0] quo[4];
reg   [3:0] dbit;
wire [22:0] dsh = {15'd0, div} << dbit[2:0];

integer i;
always @(posedge clk) begin
    we <= 1'b0;
    if (out_valid && out_ready) out_valid <= 1'b0;
    if (new_dx) ra_hold <= mirror(dx, flip, dw);

    if (start) begin
        sw <= src_w; sh <= src_h; dw <= dst_w; dh <= dst_h; flip <= flipx;
        sx <= 13'd0; dx <= 12'd0; hacc <= 24'd0; vacc <= 24'd0;
        hact <= 1'b0; first_row <= 1'b1; vcnt <= 8'd0; rows_out <= 12'd0;
        out_valid <= 1'b0; done <= 1'b0; idle <= 1'b0;
        st <= S_IN;
    end
    else if (!idle) case (st)
        S_IN: if (in_valid) begin
            // contribution (dx, pixel): accumulate, or flush the previous destination pixel and start dx
            if (!new_dx) begin
                hsum <= hsum + px_ext; hcnt <= hcnt + 8'd1;
            end else begin
                if (hact) begin wa <= mirror(cur_dx, flip, dw); wd <= flush_val; we <= 1'b1; end
                cur_dx <= dx; hsum <= px_ext; hcnt <= 8'd1; hact <= 1'b1;
            end
            if (hdown) begin
                if (hacc + {12'd0, dw} >= {11'd0, sw}) begin hacc <= hacc + {12'd0, dw} - {11'd0, sw}; dx <= dx + 12'd1; end
                else hacc <= hacc + {12'd0, dw};
            end else begin
                // upscale: one destination pixel per clock; in_ready marks this source pixel's last one
                dx <= dx + 12'd1;
                if (hacc + {11'd0, sw} >= {12'd0, dw}) hacc <= hacc + {11'd0, sw} - {12'd0, dw};
                else hacc <= hacc + {11'd0, sw};
            end
            if (in_ready) begin
                if (sx == sw - 13'd1) begin sx <= 13'd0; st <= S_FLUSH; end
                else sx <= sx + 13'd1;
            end
        end
        S_FLUSH: begin                // last destination pixel of the row (rq holds cur_dx)
            wa <= mirror(cur_dx, flip, dw); wd <= flush_val; we <= 1'b1;
            hact <= 1'b0; dx <= 12'd0; hacc <= 24'd0;
            vcnt <= vcnt + 8'd1;
            st <= S_ROWEND;
        end
        S_ROWEND: begin
            ex <= 12'd0;
            if (!vdown) st <= S_EMIT_RD;  // upscale: emit once per destination row mapped to this row
            else if (vacc + {12'd0, dh} >= {11'd0, sh}) begin
                vacc <= vacc + {12'd0, dh} - {11'd0, sh};
                st <= S_EMIT_RD;
            end else begin
                vacc <= vacc + {12'd0, dh};
                first_row <= 1'b0; st <= S_IN;
            end
        end
        S_EMIT_RD:   begin ra_hold <= ex[10:0]; st <= S_EMIT_WAIT; end
        S_EMIT_WAIT: st <= S_LOAD;
        S_LOAD: begin
            div <= div_n;
            for (i = 0; i < 4; i = i + 1) begin rem[i] <= rq[16*i +: 16] + {9'd0, div_n[7:1]}; quo[i] <= 8'd0; end
            dbit <= 4'd7;
            st <= S_DIV;
        end
        S_DIV: begin
            for (i = 0; i < 4; i = i + 1)
                if ({7'd0, rem[i]} >= dsh) begin
                    rem[i] <= rem[i] - dsh[15:0];
                    quo[i][dbit[2:0]] <= 1'b1;
                end
            dbit <= dbit - 4'd1;
            if (dbit == 4'd0) st <= S_OUT;
        end
        S_OUT: if (!out_valid || out_ready) begin
            out_px <= {quo[3], quo[2], quo[1], quo[0]};
            out_valid <= 1'b1;
            if (ex == dw - 12'd1) begin
                ex <= 12'd0;
                rows_out <= rows_out + 12'd1;
                if (rows_out + 12'd1 == dh) begin idle <= 1'b1; done <= 1'b1; end
                else if (vdown) begin first_row <= 1'b1; vcnt <= 8'd0; st <= S_IN; end
                else if (vacc + {11'd0, sh} < {12'd0, dh}) begin vacc <= vacc + {11'd0, sh}; st <= S_EMIT_RD; end
                else begin vacc <= vacc + {11'd0, sh} - {12'd0, dh}; first_row <= 1'b1; vcnt <= 8'd0; st <= S_IN; end
            end else begin
                ex <= ex + 12'd1;
                st <= S_EMIT_RD;
            end
        end
        default: ;
    endcase
end

endmodule
