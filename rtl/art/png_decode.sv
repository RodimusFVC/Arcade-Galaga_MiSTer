//============================================================================
//
//  PNG decoder: non-interlaced; 8-bit colour types 0 / 2 / 3 / 4 / 6, 1 / 2 / 4-bit types 0 / 3 (+ tRNS for palette images)
//  Copyright (C) 2026 Rodimus
//
//  Takes one or more PNG files back to back and emits each image's pixels in raster order as RGBA with x / y.
//  Chunks: IHDR, PLTE, tRNS, IDAT (zlib -> inflate.sv), IEND; everything else is skipped (CRCs are not checked).
//  Scanlines are unfiltered (None / Sub / Up / Average / Paeth) against a 32K previous-line buffer.
//
//  Redistribution and use in source and synthesized forms, with or without modification, are permitted
//  provided that the above copyright notice is retained. THIS SOFTWARE IS PROVIDED "AS IS" WITHOUT WARRANTY.
//
//============================================================================

module png_decode
(
    input             clk,
    input             reset,

    input             in_valid,
    input       [7:0] in_data,
    output            in_ready,

    output reg        img_start = 1'b0,  // one clock: IHDR of a new image parsed (width / height valid)
    output reg [15:0] width = 16'd0,
    output reg [15:0] height = 16'd0,
    output reg        img_done = 1'b0,   // one clock: last pixel of the image emitted

    output reg        px_valid = 1'b0,
    output reg [15:0] px_x = 16'd0,
    output reg [15:0] px_y = 16'd0,
    output reg [31:0] px_rgba = 32'd0,   // {R, G, B, A}
    input             px_ready
);

// ---------------------------------------------------------------- chunk parser

localparam P_SIG = 3'd0, P_LEN = 3'd1, P_TYPE = 3'd2, P_DATA = 3'd3, P_CRC = 3'd4;
localparam T_OTHER = 3'd0, T_IHDR = 3'd1, T_PLTE = 3'd2, T_TRNS = 3'd3, T_IDAT = 3'd4, T_IEND = 3'd5;

reg   [2:0] pst = P_SIG;
reg   [2:0] ctype_ch = T_OTHER;
reg  [31:0] clen = 32'd0, cpos = 32'd0;
reg  [31:0] tag = 32'd0;
reg   [3:0] bcnt = 4'd0;
reg   [1:0] zskip = 2'd0;               // zlib header bytes still to drop
reg   [7:0] depth = 8'd0, ctype = 8'd0;
reg         inf_rst = 1'b1;

wire        inf_in_ready, inf_out_valid, inf_done;
wire  [7:0] inf_out;
wire        idat_byte = pst == P_DATA && ctype_ch == T_IDAT && zskip == 2'd0;
assign      in_ready  = idat_byte ? (inf_in_ready || inf_done) : 1'b1;
wire        acc = in_valid && in_ready;

// palette (RGB) and its tRNS alpha, in block RAM (as registers they cost ~4K ALMs)
wire [23:0] pal_q;
wire  [7:0] pal_aq;
reg  [23:0] pal_wd;
reg   [7:0] pal_wa;
reg         pal_we = 1'b0, pal_awe = 1'b0;
reg   [8:0] trns_n = 9'd0;               // tRNS entries given; palette entries past them are opaque
reg   [7:0] pal_i = 8'd0;
reg   [1:0] pal_c = 2'd0;
reg  [15:0] pal_r = 16'd0;              // first two components of the entry being written

always @(posedge clk) begin
    inf_rst   <= 1'b0;
    img_start <= 1'b0;
    pal_we    <= 1'b0;
    pal_awe   <= 1'b0;
    if (reset) begin pst <= P_SIG; bcnt <= 4'd0; inf_rst <= 1'b1; end
    else if (acc) case (pst)
        P_SIG: begin bcnt <= bcnt + 4'd1; if (bcnt == 4'd7) begin pst <= P_LEN; bcnt <= 4'd0; end end
        P_LEN: begin
            clen <= {clen[23:0], in_data};
            bcnt <= bcnt + 4'd1;
            if (bcnt == 4'd3) begin pst <= P_TYPE; bcnt <= 4'd0; end
        end
        P_TYPE: begin
            tag <= {tag[23:0], in_data};
            bcnt <= bcnt + 4'd1;
            if (bcnt == 4'd3) begin
                case ({tag[23:0], in_data})
                    "IHDR": ctype_ch <= T_IHDR;
                    "PLTE": ctype_ch <= T_PLTE;
                    "tRNS": ctype_ch <= T_TRNS;
                    "IDAT": ctype_ch <= T_IDAT;
                    "IEND": ctype_ch <= T_IEND;
                    default: ctype_ch <= T_OTHER;
                endcase
                if ({tag[23:0], in_data} == "IHDR") begin
                    inf_rst <= 1'b1; zskip <= 2'd2;
                    trns_n <= 9'd0;
                end
                cpos <= 32'd0; pal_i <= 8'd0; pal_c <= 2'd0;
                bcnt <= 4'd0;
                pst <= (clen == 32'd0) ? P_CRC : P_DATA;
            end
        end
        P_DATA: begin
            case (ctype_ch)
                T_IHDR: case (cpos[3:0])
                    4'd2: width[15:8]  <= in_data;  4'd3: width[7:0]  <= in_data;
                    4'd6: height[15:8] <= in_data;  4'd7: height[7:0] <= in_data;
                    4'd8: depth <= in_data;         4'd9: ctype <= in_data;
                    default: ;
                endcase
                T_PLTE: begin
                    if (pal_c == 2'd2) begin pal_wd <= {pal_r, in_data}; pal_wa <= pal_i; pal_we <= 1'b1; pal_i <= pal_i + 8'd1; pal_c <= 2'd0; end
                    else begin pal_r <= {pal_r[7:0], in_data}; pal_c <= pal_c + 2'd1; end
                end
                T_TRNS: if (ctype == 8'd3) begin pal_wd[7:0] <= in_data; pal_wa <= pal_i; pal_awe <= 1'b1; pal_i <= pal_i + 8'd1; trns_n <= trns_n + 9'd1; end
                T_IDAT: if (zskip != 2'd0) zskip <= zskip - 2'd1;
                default: ;
            endcase
            cpos <= cpos + 32'd1;
            if (cpos + 32'd1 == clen) begin
                pst <= P_CRC; bcnt <= 4'd0;
                if (ctype_ch == T_IHDR) img_start <= 1'b1;
            end
        end
        P_CRC: begin
            bcnt <= bcnt + 4'd1;
            if (bcnt == 4'd3) begin bcnt <= 4'd0; pst <= (ctype_ch == T_IEND) ? P_SIG : P_LEN; end
        end
        default: ;
    endcase
end

// ---------------------------------------------------------------- inflate

reg inf_out_ready;
inflate inf
(
    .clk(clk), .reset(inf_rst),
    .in_valid(in_valid && idat_byte && !inf_done), .in_data(in_data), .in_ready(inf_in_ready),
    .out_valid(inf_out_valid), .out_data(inf_out), .out_ready(inf_out_ready),
    .done(inf_done)
);

// ---------------------------------------------------------------- unfilter

wire  [2:0] bpp    = (ctype == 8'd2) ? 3'd3 : (ctype == 8'd6) ? 3'd4 : (ctype == 8'd4) ? 3'd2 : 3'd1;
// 1 / 2 / 4-bit (grey / palette): several pixels per byte, MSB first, lines padded to a byte; filters work on bytes
wire        sub    = depth < 8'd8 && (ctype == 8'd0 || ctype == 8'd3);
wire  [1:0] dsh    = depth[2] ? 2'd2 : depth[1] ? 2'd1 : 2'd0;     // log2(depth)
wire  [3:0] spb    = 4'd8 >> dsh;                                   // pixels per byte
wire [15:0] stride = sub ? ((width << dsh) + 16'd7) >> 3 :
                     (bpp == 3'd3) ? width * 16'd3 : width << (bpp == 3'd4 ? 2 : bpp == 3'd2 ? 1 : 0);

reg  [14:0] lb_addr = 15'd0;
reg   [7:0] lb_d = 8'd0;
reg         lb_we = 1'b0;
wire  [7:0] lb_q;
dpram_dc #(.widthad_a(15)) prev_line
(
    .clock_a(clk), .address_a(lb_addr), .data_a(lb_d), .wren_a(lb_we), .q_a(lb_q),
    .clock_b(clk), .address_b(15'd0), .data_b('0), .wren_b(1'b0), .q_b()
);

localparam U_FILT = 3'd0, U_RD = 3'd1, U_CALC = 3'd2, U_EMIT = 3'd3, U_SUB = 3'd4;
reg   [2:0] ust = U_FILT;
reg   [7:0] sbyte = 8'd0;               // sub-byte pixels left in the current byte (top bits first)
reg   [3:0] scnt = 4'd0;
reg         slast = 1'b0;               // that byte ends the line
wire  [7:0] sidx = sbyte >> (4'd8 - (4'd1 << dsh));               // next sub-byte pixel value
wire  [7:0] sgrey = depth[2] ? {2{sidx[3:0]}} : depth[1] ? {4{sidx[1:0]}} : {8{sidx[0]}};
reg   [2:0] filt = 3'd0;
reg  [15:0] bx = 16'd0;                 // byte index within the line
reg  [15:0] row = 16'd0;
reg  [31:0] a4 = 32'd0, c4 = 32'd0;     // last 4 reconstructed bytes (this line) / prior-line bytes
reg  [31:0] pixb = 32'd0;               // bytes of the pixel being assembled
reg   [2:0] pb = 3'd0;
reg  [15:0] pxc = 16'd0;                // pixel index within the line
reg         pal_pend = 1'b0;
reg         pal_wait = 1'b0;          // 8-bit palette pixel: index registered, palette read this clock
wire        pal_busy = pal_pend || pal_wait;
reg   [7:0] pal_idx = 8'd0;

wire  [7:0] fa = (bx < {13'd0, bpp}) ? 8'd0 : a4[8 * bpp - 1 -: 8];
wire  [7:0] fb = (row == 16'd0) ? 8'd0 : lb_q;
wire  [7:0] fc = (row == 16'd0 || bx < {13'd0, bpp}) ? 8'd0 : c4[8 * bpp - 1 -: 8];
wire signed [9:0] pp = $signed({2'b00, fa}) + $signed({2'b00, fb}) - $signed({2'b00, fc});
wire  [9:0] pa_ = (pp > $signed({2'b00, fa})) ? pp - {2'b00, fa} : {2'b00, fa} - pp;
wire  [9:0] pb_ = (pp > $signed({2'b00, fb})) ? pp - {2'b00, fb} : {2'b00, fb} - pp;
wire  [9:0] pc_ = (pp > $signed({2'b00, fc})) ? pp - {2'b00, fc} : {2'b00, fc} - pp;
wire  [7:0] paeth = (pa_ <= pb_ && pa_ <= pc_) ? fa : (pb_ <= pc_) ? fb : fc;
wire  [8:0] avg   = ({1'b0, fa} + {1'b0, fb}) >> 1;
wire  [7:0] pred  = (filt == 3'd1) ? fa : (filt == 3'd2) ? fb : (filt == 3'd3) ? avg[7:0] : (filt == 3'd4) ? paeth : 8'd0;
wire  [7:0] recon = inf_out + pred;

// palette read: 8-bit pixels register the index first (pal_wait: recon -> address was too long a path at 49 MHz);
// sub-byte pixels address sidx (a register) directly. The entry is on pal_q while pal_pend.
wire  [7:0] pal_ra = pal_busy ? pal_idx : sidx;
dpram_dc #(.widthad_a(8), .width_a(24)) pal_rgb
(
    .clock_a(clk), .address_a(pal_wa), .data_a(pal_wd), .wren_a(pal_we), .q_a(),
    .clock_b(clk), .address_b(pal_ra), .data_b('0), .wren_b(1'b0), .q_b(pal_q)
);
dpram_dc #(.widthad_a(8), .width_a(8)) pal_alpha
(
    .clock_a(clk), .address_a(pal_wa), .data_a(pal_wd[7:0]), .wren_a(pal_awe), .q_a(),
    .clock_b(clk), .address_b(pal_ra), .data_b('0), .wren_b(1'b0), .q_b(pal_aq)
);

always @* inf_out_ready = (ust == U_FILT) || (ust == U_CALC && !px_valid_hold && !pal_busy);

reg px_valid_hold;
always @* px_valid_hold = px_valid && !px_ready;

always @(posedge clk) begin
    lb_we <= 1'b0;
    img_done <= 1'b0;
    if (px_valid && px_ready) px_valid <= 1'b0;
    if (img_start) begin ust <= U_FILT; row <= 16'd0; bx <= 16'd0; pb <= 3'd0; end
    // palette lookup finishing (one clock after the index)
    if (pal_wait) begin pal_wait <= 1'b0; pal_pend <= 1'b1; end
    if (pal_pend) begin
        px_rgba  <= {pal_q, ({1'b0, pal_idx} < trns_n) ? pal_aq : 8'hFF};
        px_valid <= 1'b1;
        pal_pend <= 1'b0;
    end
    case (ust)
        U_FILT: if (inf_out_valid) begin filt <= inf_out[2:0]; bx <= 16'd0; pb <= 3'd0; pxc <= 16'd0; lb_addr <= 15'd0; ust <= U_RD; end
        U_RD:   ust <= U_CALC;                      // prior-line byte bx readable next clock
        U_CALC: if (inf_out_valid && !px_valid_hold && !pal_busy) begin
            lb_d  <= recon; lb_we <= 1'b1;          // overwrite the prior line in place
            a4    <= {a4[23:0], recon};
            c4    <= {c4[23:0], fb};
            pixb  <= {pixb[23:0], recon};
            if (sub) begin                          // unpack the byte's pixels, then finish the byte in U_SUB
                sbyte <= recon; scnt <= 4'd0; slast <= bx + 16'd1 == stride;
                ust   <= U_SUB;
            end else if (pb == bpp - 3'd1) begin    // pixel complete
                pb <= 3'd0;
                px_x <= pxc; pxc <= pxc + 16'd1;
                px_y <= row;
                case (ctype)
                    8'd2: begin px_rgba <= {pixb[15:0], recon, 8'hFF}; px_valid <= 1'b1; end
                    8'd6: begin px_rgba <= {pixb[23:0], recon}; px_valid <= 1'b1; end
                    8'd0: begin px_rgba <= {recon, recon, recon, 8'hFF}; px_valid <= 1'b1; end
                    8'd4: begin px_rgba <= {pixb[7:0], pixb[7:0], pixb[7:0], recon}; px_valid <= 1'b1; end
                    default: begin pal_idx <= recon; pal_wait <= 1'b1; end
                endcase
            end else pb <= pb + 3'd1;
            if (!sub) begin
                if (bx + 16'd1 == stride) begin
                    row <= row + 16'd1;
                    ust <= U_FILT;
                    if (row + 16'd1 == height) img_done <= 1'b1;
                end else begin
                    bx <= bx + 16'd1;
                    ust <= U_EMIT;
                end
            end
        end
        U_SUB: if (!px_valid_hold && !pal_busy) begin
            if (scnt != spb && pxc != width) begin  // one pixel per clock; the line's padding bits are dropped
                px_x  <= pxc; pxc <= pxc + 16'd1;
                px_y  <= row;
                sbyte <= sbyte << (4'd1 << dsh);
                scnt  <= scnt + 4'd1;
                if (ctype == 8'd0) begin px_rgba <= {sgrey, sgrey, sgrey, 8'hFF}; px_valid <= 1'b1; end
                else begin pal_idx <= sidx; pal_pend <= 1'b1; end
            end else if (slast) begin
                row <= row + 16'd1;
                ust <= U_FILT;
                if (row + 16'd1 == height) img_done <= 1'b1;
            end else begin
                bx  <= bx + 16'd1;
                ust <= U_EMIT;
            end
        end
        U_EMIT: begin lb_addr <= bx[14:0]; ust <= U_RD; end   // address the next prior-line byte
        default: ;
    endcase
end

endmodule
