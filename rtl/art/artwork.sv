//============================================================================
//
//  MAME artwork (backdrop / overlay / bezel) for MiSTer arcade cores
//  Copyright (C) 2026 Rodimus
//
//  ioctl index IDX = [2048-byte layout table from gen_mra][marker "AWI"+id][PNG]... (PNGs straight from the
//  MAME artwork zip). The PNGs are stored in DDR3, then the selected view is decoded (png_decode), scaled
//  (art_resample) and blended in MAME's legacy layer order into a canvas plane S of {Q, M} words:
//  final pixel = clamp(Q + game * M / 255) (Q = everything added on top, M = overlay / bezel factor).
//  HDMI: S + the game -> triple-buffered 32bpp framebuffer (canvas size). Analog / direct video: S
//  resampled to the native resolution (plane N), applied to the game pixel by pixel (one pixel of delay).
//  Rotated games (table byte 10): the layout is portrait; the whole game frame is captured (5-bit colour codes) and
//  composited by address; plane N is built from S read column by column, so it stays in the native raster.
//  Turned view (turn = OSD Orientation Horz, rotated monitor): the whole view is turned 90 so it stands upright on the
//  monitor (vertical game: the game picture is then the native raster; horizontal game: turned CW, drawn as a rotated
//  game). Layers are blended transposed into S; the rest of the pipeline is unchanged.
//
//  DDR3 (byte addresses): blob 38000000 (64 MB), S 31000000 (2048 words / row), FB 33000000 / 34000000 / 35000000
//  (8192 bytes / row), N 36000000 (512 words / row).
//
//  Redistribution and use in source and synthesized forms, with or without modification, are permitted
//  provided that the above copyright notice is retained. THIS SOFTWARE IS PROVIDED "AS IS" WITHOUT WARRANTY.
//
//============================================================================

module artwork #(parameter [7:0] IDX = 8'd5,    // ioctl index of the artwork download
                 parameter int CODE_BITS = 5)   // rotated games: colours per frame = 2^CODE_BITS (5-8)
(
    input             clk,
    input       [3:0] sel,             // 0 = off, n = view n of the layout table
    input       [3:0] layer_off,       // [0] backdrops, [1] overlays, [2] bezels, [3] control panels / marquees
    input             side_off,        // layers beside the screen (side art) off
    input             zoom,            // framebuffer shows the screen area only
    input             crt_flip,        // board picture is rotated 180 (CRT Flip): artwork follows on the core video
    input             hdmi_flip,       // HDMI Flip; the framebuffer is rotated 180 when crt_flip ^ hdmi_flip
    input             turn,            // rotated monitor (OSD Orientation Horz): the view is turned 90
    input      [11:0] hdmi_w,          // HDMI output size (sys HDMI_WIDTH / HDMI_HEIGHT, 0 = unknown / direct video):
    input      [11:0] hdmi_h,          // the view is built small enough for the scaler to show it whole
    output            avail,           // this game has artwork

    input             ioctl_download,
    input       [7:0] ioctl_index,
    input             ioctl_wr,
    input      [26:0] ioctl_addr,      // hps_io's full 27 bits: the artwork download can pass 32 MB
    input       [7:0] ioctl_dout,
    output            ioctl_wait,

    // game video in, delayed by one pixel out (artwork applied while running)
    input             ce_pix,
    input             hs_in, vs_in, hblank_in, vblank_in,
    input      [23:0] rgb_in,          // {R, G, B}
    output reg        hs_out, vs_out, hblank_out, vblank_out,
    output reg [23:0] rgb_out,

    output            running,         // artwork drawn (native composite on, framebuffer valid)
    output            ddr_owner,       // DDRAM belongs to this module
    output     [11:0] canvas_w,        // framebuffer size
    output     [11:0] canvas_h,

    output     [31:0] fb_base,
    input             fb_vbl,

    output            DDRAM_CLK,
    input             DDRAM_BUSY,
    output      [7:0] DDRAM_BURSTCNT,
    output     [28:0] DDRAM_ADDR,
    input      [63:0] DDRAM_DOUT,
    input             DDRAM_DOUT_READY,
    output            DDRAM_RD,
    output     [63:0] DDRAM_DIN,
    output      [7:0] DDRAM_BE,
    output            DDRAM_WE
);

localparam [28:0] BLOB_W = 29'h07000000;      // word addresses (byte >> 3); 38000000-3BFFFFFF is unused by Main_MiSTer
localparam [28:0] S_W    = 29'h06200000;
localparam [28:0] FB0_W  = 29'h06600000;
localparam [28:0] N_W    = 29'h06C00000;
localparam [63:0] S_INIT = 64'h00FFFFFF_FF000000;   // Q = 0, mask = FF, M = white

function [7:0] div255(input [15:0] x);
    reg [16:0] t;
    begin t = {1'b0, x} + 17'd128; div255 = 8'((t + (t >> 8)) >> 8); end
endfunction
function [7:0] sat(input [8:0] x);
    sat = x[8] ? 8'hFF : x[7:0];
endfunction

// =================================================================== DDR engine (one burst at a time)
// clients: 0 native prefetch, 1 compositor, 2 blob writer, 3 blender, 4 reader (fixed priority)

reg         p_req = 1'b0, k_req = 1'b0, w_req = 1'b0, b_req = 1'b0, r_req = 1'b0;
reg         k_we, b_we;
reg  [28:0] p_addr, k_addr, w_addr, b_addr, r_addr_q;
reg   [7:0] p_len, k_len, b_len8, r_len;
wire  [4:0] c_req = {r_req, b_req, w_req, k_req, p_req};
wire [63:0] k_wdata, w_wdata, b_wdata;

localparam E_IDLE = 3'd0, E_RREQ = 3'd1, E_RDATA = 3'd2, E_WPRIME = 3'd3, E_WDATA = 3'd4;
reg   [2:0] est = E_IDLE;
reg   [2:0] ecur;
reg  [28:0] eaddr;
reg   [7:0] elen, ebeat;
wire        w_acc   = est == E_WDATA && !DDRAM_BUSY;
wire  [7:0] wb_nxt  = w_acc ? ebeat + 8'd1 : (est == E_WDATA ? ebeat : 8'd0);
wire        rd_v    = est == E_RDATA && DDRAM_DOUT_READY;
wire        e_last  = (rd_v || w_acc) && ebeat == elen - 8'd1;
wire  [4:0] e_ack   = e_last ? (5'd1 << ecur) : 5'd0;      // client's last beat: it drops req on this clock
wire        nat_pend;                                       // native prefetch has a row due (set with the prefetch)

assign DDRAM_CLK      = clk;
assign DDRAM_BURSTCNT = elen;
assign DDRAM_ADDR     = eaddr;
assign DDRAM_RD       = est == E_RREQ;
assign DDRAM_WE       = est == E_WDATA;
assign DDRAM_DIN      = (ecur == 3'd1) ? k_wdata : (ecur == 3'd2) ? w_wdata : b_wdata;
assign DDRAM_BE       = 8'hFF;

always @(posedge clk) begin
    case (est)
        E_IDLE: begin
            ebeat <= 8'd0;
            if      (p_req) begin ecur <= 3'd0; eaddr <= p_addr;   elen <= p_len;  est <= E_RREQ; end
            else if (k_req && !nat_pend) begin ecur <= 3'd1; eaddr <= k_addr;   elen <= k_len;  est <= k_we ? E_WPRIME : E_RREQ; end   // compositor waits while a native row is due
            else if (w_req) begin ecur <= 3'd2; eaddr <= w_addr;   elen <= 8'd1;   est <= E_WPRIME; end
            else if (b_req) begin ecur <= 3'd3; eaddr <= b_addr;   elen <= b_len8; est <= b_we ? E_WPRIME : E_RREQ; end
            else if (r_req) begin ecur <= 3'd4; eaddr <= r_addr_q; elen <= r_len;  est <= E_RREQ; end
        end
        E_RREQ:   if (!DDRAM_BUSY) est <= E_RDATA;
        E_RDATA:  if (DDRAM_DOUT_READY) begin
            ebeat <= ebeat + 8'd1;
            if (ebeat == elen - 8'd1) est <= E_IDLE;
        end
        E_WPRIME: est <= E_WDATA;
        E_WDATA:  if (!DDRAM_BUSY) begin
            ebeat <= ebeat + 8'd1;
            if (ebeat == elen - 8'd1) est <= E_IDLE;
        end
        default: est <= E_IDLE;
    endcase
end
wire [4:0] e_rd = rd_v ? (5'd1 << ecur) : 5'd0;   // read beat for client n (data DDRAM_DOUT, index ebeat)
wire [4:0] e_wr = (est == E_WDATA || est == E_WPRIME) ? (5'd1 << ecur) : 5'd0;

// =================================================================== download: layout table + PNG blob

wire        dl5    = ioctl_download && ioctl_index == IDX;
reg         old_dl5 = 1'b0;
reg         blob_ok = 1'b0;
wire        hdr_wr = ioctl_wr && ioctl_index == IDX && ioctl_addr < 27'd2048;
wire        blb_wr = ioctl_wr && ioctl_index == IDX && ioctl_addr >= 27'd2048;
wire [25:0] boff   = 26'(ioctl_addr - 27'd2048);

wire [10:0] hdr_ra;
wire  [7:0] hdr_q;
dpram_dc #(.widthad_a(11)) hdr
(
    .clock_a(clk), .address_a(ioctl_addr[10:0]), .data_a(ioctl_dout), .wren_a(hdr_wr), .q_a(),
    .clock_b(clk), .address_b(hdr_ra), .data_b(8'd0), .wren_b(1'b0), .q_b(hdr_q)   // DPRAMSV-2026-10-25: was .data_b('0)
);

reg  [63:0] bw_acc, bw_word;
reg  [25:0] bw_last;
reg         bw_dirty = 1'b0;
assign      w_wdata = bw_word;
assign      ioctl_wait = w_req;

// PNG boundary scanner: records the blob offset of each image id ("AWI" id marker before each PNG)
localparam K_MARK = 3'd0, K_MK = 3'd1, K_SIG = 3'd2, K_LEN = 3'd3, K_TYPE = 3'd4, K_DATA = 3'd5, K_CRC = 3'd6;
reg   [2:0] kst = K_MARK;
reg   [1:0] kcnt;
reg  [31:0] klen, ktype;
reg   [4:0] kid;
reg  [25:0] img_off[32];
reg  [31:0] img_ok = 32'd0;

always @(posedge clk) begin
    old_dl5 <= dl5;
    if (e_ack[2]) w_req <= 1'b0;
    if (ioctl_download && ioctl_index == 8'd0) blob_ok <= 1'b0;     // a new game: its own artwork (if any) follows
    if (dl5 && !old_dl5) begin blob_ok <= 1'b0; img_ok <= 32'd0; kst <= K_MARK; bw_dirty <= 1'b0; end
    if (blb_wr) begin
        bw_acc[8 * boff[2:0] +: 8] <= ioctl_dout;
        bw_dirty <= 1'b1;
        bw_last <= boff;
        if (boff[2:0] == 3'd7) begin
            bw_word <= {ioctl_dout, bw_acc[55:0]};
            w_addr <= BLOB_W + {6'd0, boff[25:3]}; w_req <= 1'b1;
            bw_dirty <= 1'b0;
        end
        // scanner
        case (kst)
            K_MARK: if (ioctl_dout == 8'h89) begin img_off[kid] <= boff; img_ok[kid] <= 1'b1; kcnt <= 2'd0; klen <= 32'd6; kst <= K_SIG; end
                    else if (ioctl_dout == "A") begin kcnt <= 2'd0; kst <= K_MK; end
            K_MK:   begin kcnt <= kcnt + 2'd1; if (kcnt == 2'd2) begin kid <= ioctl_dout[4:0]; kst <= K_MARK; end end
            K_SIG:  begin klen <= klen - 32'd1; if (klen == 32'd0) begin kcnt <= 2'd0; kst <= K_LEN; end end
            K_LEN:  begin klen <= {klen[23:0], ioctl_dout}; kcnt <= kcnt + 2'd1; if (kcnt == 2'd3) kst <= K_TYPE; end
            K_TYPE: begin
                ktype <= {ktype[23:0], ioctl_dout}; kcnt <= kcnt + 2'd1;
                if (kcnt == 2'd3) kst <= (klen == 32'd0) ? K_CRC : K_DATA;
            end
            K_DATA: begin klen <= klen - 32'd1; if (klen == 32'd1) begin kcnt <= 2'd0; kst <= K_CRC; end end
            K_CRC:  begin kcnt <= kcnt + 2'd1; if (kcnt == 2'd3) kst <= (ktype == "IEND") ? K_MARK : K_LEN; end
            default: kst <= K_MARK;
        endcase
    end
    if (!dl5 && old_dl5) begin
        blob_ok <= 1'b1;
        if (bw_dirty) begin   // last partial word
            bw_word <= bw_acc;
            w_addr <= BLOB_W + {6'd0, bw_last[25:3]}; w_req <= 1'b1;
            bw_dirty <= 1'b0;
        end
    end
end

// =================================================================== reader: PNG bytes from the blob, or S pixels

reg         rd_go = 1'b0;           // one clock: start
reg         rd_smode;               // 0 = PNG bytes from rd_off, 1 = S rect rows (Q or M by rd_mq)
reg         rd_mq;
reg  [25:0] rd_off;
reg         rd_run = 1'b0, rd_stop = 1'b0;
reg   [5:0] r_wp, r_rp, r_ip;       // written / read / issued (32-entry ring, 6-bit pointers)
reg   [5:0] r_base;
reg  [28:0] r_addr;                 // next word to request
reg  [11:0] r_col, r_row;           // S mode: position of the next request
reg   [4:0] r_n;
wire [63:0] ring_q;
wire  [4:0] ring_ra = r_rp[4:0];   // next word to read, presented ahead
dpram_dc #(.widthad_a(5), .width_a(64)) rring
(
    .clock_a(clk), .address_a(5'(r_base + ebeat[5:0])), .data_a(DDRAM_DOUT), .wren_a(e_rd[4]), .q_a(),
    .clock_b(clk), .address_b(ring_ra), .data_b(64'd0), .wren_b(1'b0), .q_b(ring_q)   // DPRAMSV-2026-10-25: was .data_b('0)
);

reg  [11:0] v_cw, v_ch, v_sx, v_sy, v_sw, v_sh, v_nw, v_nh;   // view geometry (as drawn: after view rotation)
reg  [11:0] u_cw, u_ch, u_sx, u_sy, u_sw, u_sh;               // view geometry from the table (layers are placed in it)
reg   [1:0] v_rot = 2'd0;          // game orientation: 0 none, 1 ROT270, 2 ROT90 (table byte 10, or the view rotation)
reg   [1:0] vw_rot = 2'd0;         // view rotation in use: 0 none, 1 CCW, 2 CW
wire        rot   = v_rot != 2'd0;
wire        rot90 = v_rot == 2'd2;
wire [11:0] v_gw  = rot ? v_nh : v_nw;   // game picture as the layout shows it (rotated: portrait)
wire [11:0] v_gh  = rot ? v_nw : v_nh;
// S mode reads the screen rect row by row; a rotated game reads it column by column (plane N is unrotated)
wire [11:0] rv_w    = rot ? v_sh : v_sw;
wire [11:0] rv_h    = rot ? v_sw : v_sh;
wire [11:0] rs_row  = !rot ? r_row : rot90 ? r_col : 12'(v_sh - 12'd1 - r_col);
wire [11:0] rs_col  = !rot ? r_col : rot90 ? 12'(v_sw - 12'd1 - r_row) : r_row;
wire [28:0] rs_addr = S_W + {6'd0, 12'(v_sy + rs_row), 11'd0} + {17'd0, 12'(v_sx + rs_col)};
reg  [63:0] r_word;
reg         r_wv = 1'b0, r_pend = 1'b0;
reg   [2:0] r_bi;
reg         r_first;
wire        png_in_ready;
wire        res_in_ready;
wire        r_byte_v = r_wv && !rd_smode;
wire        r_pix_v  = r_wv && rd_smode;
wire        r_take   = rd_smode ? (r_pix_v && res_in_ready) : (r_byte_v && png_in_ready);
wire        r_last   = rd_smode || r_bi == 3'd7;
wire  [7:0] r_byte   = r_word[8 * r_bi +: 8];
wire [31:0] r_pix    = rd_mq ? {r_word[39:32], r_word[47:40], r_word[55:48], 8'hFF} : {r_word[7:0], r_word[15:8], r_word[23:16], 8'hFF};

always @(posedge clk) begin
    if (e_rd[4]) r_wp <= r_wp + 6'd1;
    if (e_ack[4]) r_req <= 1'b0;
    if (rd_go) begin
        rd_run <= 1'b1;
        r_wp <= 6'd0; r_rp <= 6'd0; r_ip <= 6'd0; r_wv <= 1'b0; r_pend <= 1'b0; r_first <= 1'b1;
        r_addr <= BLOB_W + {6'd0, rd_off[25:3]};
        r_col <= 12'd0; r_row <= 12'd0;
        r_bi <= rd_smode ? 3'd0 : rd_off[2:0];
    end
    else if (rd_run) begin
        // request 16 words (S mode: up to the end of the row; rotated: one word, the walk goes down a column)
        if (!r_req && !rd_stop && !e_wr[4] && 6'(r_ip - r_rp) <= 6'd16 && !(rd_smode && r_row == rv_h)) begin
            r_n = (rd_smode && rot) ? 5'd1 : (rd_smode && rv_w - r_col < 12'd16) ? 5'(rv_w - r_col) : 5'd16;
            r_addr_q <= rd_smode ? rs_addr : r_addr; r_len <= {3'd0, r_n}; r_req <= 1'b1;
            r_base <= r_ip; r_ip <= r_ip + {1'b0, r_n};
            r_addr <= r_addr + {24'd0, r_n};
            if (rd_smode && r_col + {7'd0, r_n} == rv_w) begin r_col <= 12'd0; r_row <= r_row + 12'd1; end
            else r_col <= r_col + {7'd0, r_n};
        end
        // ring -> word register
        if (r_pend) begin r_word <= ring_q; r_wv <= 1'b1; r_pend <= 1'b0; end
        else if ((!r_wv || (r_take && r_last)) && r_rp != r_wp) begin r_rp <= r_rp + 6'd1; r_pend <= 1'b1; end
        if (r_take) begin
            if (r_last) begin r_wv <= 1'b0; r_bi <= 3'd0; end
            else r_bi <= r_bi + 3'd1;
        end
    end
    if (rd_stop) begin rd_run <= 1'b0; r_wv <= 1'b0; end   // drop the held word: the next layer starts clean
end

// =================================================================== decode -> premultiply -> resample

reg         png_rst = 1'b1;
reg   [2:0] l_op;                    // layer op (see blender)
reg   [7:0] l_ca;                    // colour alpha
reg         l_rect = 1'b0;           // solid-colour layer (layout <rect>): rect_px instead of the resampler
reg  [31:0] rect_px;                 // {R, G, B, A}, premultiplied like a PNG pixel
wire        png_px_valid, png_img_start;
wire [31:0] png_px;
wire [15:0] png_w, png_h;
reg         pm_valid = 1'b0;
reg  [31:0] pm_px;

png_decode png
(
    .clk(clk), .reset(png_rst),
    .in_valid(r_byte_v), .in_data(r_byte), .in_ready(png_in_ready),
    .img_start(png_img_start), .width(png_w), .height(png_h), .img_done(),
    .px_valid(png_px_valid), .px_x(), .px_y(), .px_rgba(png_px), .px_ready(pm1_free)
);

// two stages: alpha x colour alpha (or mask luminance), then colour x alpha (mask: luminance x colour alpha,
// on the red multiplier: MAME scales an alphafile by the item's colour alpha)
reg         pm1_valid = 1'b0;
reg  [31:0] pm1_px;
wire        pm2_free = !pm_valid || res_in_ready;
wire        pm1_free = !pm1_valid || pm2_free;
wire  [7:0] lum = 8'((png_px[31:24] * 16'd57 + png_px[23:16] * 16'd181 + png_px[15:8] * 16'd18) >> 8);
wire  [7:0] pm2_r = div255(((l_op == 3'd4) ? l_ca : pm1_px[31:24]) * pm1_px[7:0]);
always @(posedge clk) begin
    if (png_rst) begin pm_valid <= 1'b0; pm1_valid <= 1'b0; end
    else begin
        if (pm_valid && res_in_ready) pm_valid <= 1'b0;
        if (pm1_valid && pm2_free) begin
            pm_valid <= 1'b1; pm1_valid <= 1'b0;
            pm_px <= (l_op == 3'd4) ? {24'd0, pm2_r} :
                     {pm2_r, div255(pm1_px[23:16] * pm1_px[7:0]), div255(pm1_px[15:8] * pm1_px[7:0]), pm1_px[7:0]};
        end
        if (png_px_valid && pm1_free) begin
            pm1_valid <= 1'b1;
            pm1_px <= (l_op == 3'd4) ? {24'd0, lum} : {png_px[31:8], div255(png_px[7:0] * l_ca)};
        end
    end
end

reg         res_go = 1'b0;
reg  [11:0] res_dw, res_dh;
reg         res_flip;
wire        res_valid, res_ready;
wire [31:0] res_px;
art_resample res
(
    .clk(clk),
    .start(rd_smode ? res_go : (png_img_start && !png_rst)),
    .src_w(rd_smode ? {1'b0, rv_w} : png_w[12:0]), .src_h(rd_smode ? {1'b0, rv_h} : png_h[12:0]),
    .dst_w(res_dw), .dst_h(res_dh), .flipx(res_flip),
    .in_valid(rd_smode ? r_pix_v : pm_valid), .in_px(rd_smode ? r_pix : pm_px), .in_ready(res_in_ready),
    .out_valid(res_valid), .out_px(res_px), .out_ready(res_ready), .done()
);
wire        src_valid = l_rect || res_valid;
wire [31:0] src_px    = l_rect ? rect_px : res_px;

// =================================================================== blender (RMW of S / N plane rows)
// ops: 0 multiply (overlay), 1 add (backdrop), 2 alpha over (bezel), 3 alpha under, 4 mask (alpha only),
//      5 N plane Q, 6 N plane M, 7 fill S with S_INIT

reg         bl_go = 1'b0, bl_abort = 1'b0;
reg         bl_done = 1'b1;
reg         bl_mask;                 // use the S mask byte as alpha
reg         bl_nplane;
reg   [1:0] bl_rot = 2'd0;           // view rotation: the layer is placed turned (one word per pixel), rect in table coords
reg  signed [13:0] bl_x, bl_y;
reg  [11:0] bl_w, bl_h, bl_cw, bl_ch;
reg  [11:0] bp_x, bp_y;              // position within the rect
reg   [6:0] b_len, b_i, bc_wa;
localparam B_IDLE = 3'd0, B_POS = 3'd1, B_RD = 3'd2, B_A = 3'd3, B_B = 3'd4, B_C = 3'd5, B_D = 3'd6, B_WR = 3'd7;
reg   [2:0] bst = B_IDLE;

wire signed [13:0] b_cx = bl_x + $signed({2'b00, bp_x});
wire signed [13:0] b_cy = bl_y + $signed({2'b00, bp_y});
wire        b_out = b_cx < 0 || b_cy < 0 || b_cx >= $signed({2'b00, bl_cw}) || b_cy >= $signed({2'b00, bl_ch});
wire signed [13:0] b_end0 = bl_x + $signed({2'b00, bl_w});
wire signed [13:0] b_end  = (b_end0 < $signed({2'b00, bl_cw})) ? b_end0 : $signed({2'b00, bl_cw});
wire [13:0] b_span = 14'(b_end - b_cx);
wire  [6:0] b_n    = (bl_rot != 2'd0) ? 7'd1 : (b_span > 14'd64) ? 7'd64 : b_span[6:0];
// S position: CW (X, Y) -> (CH - 1 - Y, X), CCW (X, Y) -> (Y, CW - 1 - X) in the table's canvas (bl_cw x bl_ch)
wire [11:0] b_ax   = (bl_rot == 2'd0) ? b_cx[11:0] : (bl_rot == 2'd2) ? 12'(bl_ch - 12'd1 - b_cy[11:0]) : b_cy[11:0];
wire [11:0] b_ay   = (bl_rot == 2'd0) ? b_cy[11:0] : (bl_rot == 2'd2) ? b_cx[11:0] : 12'(bl_cw - 12'd1 - b_cx[11:0]);
wire        fill = l_op == 3'd7;

wire [63:0] bc_q;
reg  [63:0] bc_qd;
reg  [63:0] bc_wd;
reg         bc_we;
dpram_dc #(.widthad_a(6), .width_a(64)) bcbuf
(
    .clock_a(clk), .address_a(e_rd[3] ? ebeat[5:0] : bc_wa[5:0]), .data_a(e_rd[3] ? DDRAM_DOUT : bc_wd), .wren_a(e_rd[3] | bc_we), .q_a(),
    .clock_b(clk), .address_b(bst == B_WR ? wb_nxt[5:0] : b_i[5:0]), .data_b(64'd0), .wren_b(1'b0), .q_b(bc_q)   // DPRAMSV-2026-10-25: was .data_b('0)
);
assign b_wdata = fill ? S_INIT : bc_q;
assign res_ready  = (bst == B_POS && !fill && b_out) || bst == B_C;

// stage C: source (premultiplied by the mask byte when masked), stage D: blend
reg   [7:0] s_c[3], s_a, s_raw[3];
reg   [7:0] q_c[3], m_c[3], k_c[3];
integer j;
always @(posedge clk) begin
    bc_we <= 1'b0;
    if (e_ack[3]) b_req <= 1'b0;
    if (bl_go) begin bp_x <= 12'd0; bp_y <= 12'd0; bl_done <= 1'b0; bst <= B_POS; end
    else case (bst)
        B_POS: if (bl_abort) begin bl_done <= 1'b1; bst <= B_IDLE; end
        else if (bp_y == bl_h) begin bl_done <= 1'b1; bst <= B_IDLE; end
        else if (fill || (src_valid && !b_out)) begin
            b_len <= b_n; b_len8 <= {1'b0, b_n};
            b_addr <= (bl_nplane ? N_W + {8'd0, b_cy[11:0], 9'd0} : S_W + {6'd0, b_ay[10:0], 11'd0}) + {17'd0, b_ax};
            b_we <= fill; b_req <= 1'b1;
            b_i <= 7'd0;
            bst <= fill ? B_WR : B_RD;
        end
        else if (src_valid) begin   // outside the canvas: dropped (res_ready)
            if (bp_x == bl_w - 12'd1) begin bp_x <= 12'd0; bp_y <= bp_y + 12'd1; end else bp_x <= bp_x + 12'd1;
        end
        B_RD: if (e_ack[3]) bst <= B_A;
        B_A:  bst <= B_B;            // b_i addresses port B
        B_B:  bst <= B_C;
        B_C:  if (bl_abort) begin bl_done <= 1'b1; bst <= B_IDLE; end
        else if (src_valid) begin
            bc_qd <= bc_q;
            s_a   <= bl_mask ? bc_q[31:24] : src_px[7:0];
            for (j = 0; j < 3; j = j + 1) begin
                s_raw[j] <= src_px[8 * (3 - j) +: 8];
                s_c[j]   <= bl_mask ? div255(src_px[8 * (3 - j) +: 8] * bc_q[31:24]) : src_px[8 * (3 - j) +: 8];
            end
            bst <= B_D;
        end
        B_D: begin
            bc_wd <= bc_qd;
            for (j = 0; j < 3; j = j + 1) begin
                case (l_op)
                    3'd0: begin bc_wd[8*j +: 8] <= div255(bc_qd[8*j +: 8] * mulf(s_c[j], s_a)); bc_wd[32+8*j +: 8] <= div255(bc_qd[32+8*j +: 8] * mulf(s_c[j], s_a)); end
                    3'd1: bc_wd[8*j +: 8] <= sat({1'b0, bc_qd[8*j +: 8]} + {1'b0, s_c[j]});
                    3'd2: begin bc_wd[8*j +: 8] <= sat({1'b0, s_c[j]} + {1'b0, div255(bc_qd[8*j +: 8] * (8'hFF - s_a))});
                                bc_wd[32+8*j +: 8] <= div255(bc_qd[32+8*j +: 8] * (8'hFF - s_a)); end
                    3'd3: bc_wd[8*j +: 8] <= sat({1'b0, s_c[j]} + {1'b0, div255(bc_qd[8*j +: 8] * (8'hFF - s_a))});
                    3'd5: bc_wd[8*j +: 8] <= s_raw[j];
                    3'd6: bc_wd[32+8*j +: 8] <= s_raw[j];
                    default: ;
                endcase
            end
            if (l_op == 3'd4) bc_wd[31:24] <= s_a;
            bc_we <= 1'b1; bc_wa <= b_i;
            if (bp_x == bl_w - 12'd1) begin bp_x <= 12'd0; bp_y <= bp_y + 12'd1; end else bp_x <= bp_x + 12'd1;
            b_i <= b_i + 7'd1;
            if (b_i + 7'd1 == b_len) begin b_we <= 1'b1; b_req <= 1'b1; bst <= B_WR; end
            else bst <= B_A;
        end
        B_WR: if (e_ack[3]) begin
            if (fill) begin
                if (bp_x + {5'd0, b_len} == bl_w) begin bp_x <= 12'd0; bp_y <= bp_y + 12'd1; end
                else bp_x <= bp_x + {5'd0, b_len};
            end
            bst <= B_POS;
        end
        default: bst <= B_IDLE;
    endcase
end

function [7:0] mulf(input [7:0] s, input [7:0] a);   // overlay factor: lerp(white, source, alpha)
    mulf = sat({1'b0, s} + {1'b0, 8'hFF - a});
endfunction

// =================================================================== game capture (32-line ring) + native composite
// 32 lines: at 40 MHz with a slow DDR3 the compositor trails the raster by ~20 lines (sim, 2026-10-14)

reg  [8:0] gx_c = 9'd0, gy_c = 9'd0;
reg        old_hbl = 1'b0, old_vbl = 1'b0;
reg        frame_start = 1'b0, frame_end = 1'b0, vbl_rise = 1'b0, line_inc = 1'b0;
wire       act_px = !hblank_in && !vblank_in;
// line of the pixel being captured: a board may drop vblank on the frame's first pixel (Centipede), before gy_c resets
wire [4:0] gy_w   = old_vbl ? 5'd0 : gy_c[4:0];
// rotated games: the whole frame as CODE_BITS-bit colour codes, 8 pixels a word, double-buffered at {buffer, index / 8}
// (2 x 8064 words for 288 x 224). Each frame's first 2^CODE_BITS colours get codes (a frame with more draws the rest as
// the last code). CODE_BITS 5: 32 parallel comparators, palette in registers. 6-8: hashed RGB -> code table (linear
// probing, cleared in vblank) and a palette RAM; needs >= 8 clocks per pixel (one lookup takes up to 7).
localparam int CB = CODE_BITS, NC = 1 << CODE_BITS, WW = 8 * CODE_BITS;
reg  [15:0] cap_i = 16'd0, cap_tot = 16'd0;   // pixel index in the frame, pixels in the last frame
reg         cap_buf = 1'b0;
reg  [WW-1:0] cap_acc;
reg    [CB:0] cpal_n = '0;           // codes in use in the frame being captured
wire          cap_put;               // the code of the next pixel in raster order is ready
wire [CB-1:0] cap_code;
wire        cap_vbr = ce_pix && vblank_in && !old_vbl;
wire        cap_wr  = rot ? (cap_put && cap_i[2:0] == 3'd7) || (cap_vbr && cap_i[2:0] != 3'd0) : ce_pix && act_px;
wire [WW-1:0] gr_qw;
reg  [13:0] gr_ra;
reg   [2:0] gr_sub;                 // rotated: pixel within the word read
dpram_dc #(.widthad_a(14), .width_a(WW)) gring
(
    .clock_a(clk), .address_a(rot ? {cap_buf, cap_i[15:3]} : {gy_w, gx_c[8:0]}),
    .data_a(rot ? (cap_put ? {cap_code, cap_acc[WW-CB-1:0]} : cap_acc) : {{(WW-24){1'b0}}, rgb_in}), .wren_a(cap_wr), .q_a(),
    .clock_b(clk), .address_b(gr_ra), .data_b({WW{1'b0}}), .wren_b(1'b0), .q_b(gr_qw)   // DPRAMSV-2026-10-25: was .data_b('0)
);
reg           cp_rbuf;               // buffer the compositor reads (the last whole frame)
wire [CB-1:0] gr_code = gr_qw[CB * gr_sub +: CB];
reg    [23:0] pal2;                  // colour of the stage-1 code, one clock later (compositor stage 2)
always @(posedge clk) begin
    if (cap_put) begin cap_acc[CB * cap_i[2:0] +: CB] <= cap_code; cap_i <= cap_i + 16'd1; end
    if (cap_vbr) begin cap_tot <= cap_i; cap_buf <= ~cap_buf; cap_i <= 16'd0; end
end

generate if (CODE_BITS == 5) begin : map_cmp
    reg  [23:0] cpal[64];            // colour of code n in buffer b: {b, n}
    reg  [31:0] cpal_hit;
    integer     ci;
    always @* for (ci = 0; ci < 32; ci = ci + 1) cpal_hit[ci] = ci < cpal_n && cpal[{cap_buf, 5'(ci)}] == rgb_in;
    reg   [4:0] hit_code;            // codes are unique, so at most one hit: OR of the hit indices
    always @* begin
        hit_code = 5'd0;
        for (ci = 0; ci < 32; ci = ci + 1) if (cpal_hit[ci]) hit_code = hit_code | 5'(ci);
    end
    wire        cpal_new = cpal_hit == 32'd0 && !cpal_n[5];
    assign cap_put  = ce_pix && act_px && rot;
    assign cap_code = cpal_hit != 32'd0 ? hit_code : cpal_n[5] ? 5'd31 : cpal_n[4:0];
    always @(posedge clk) begin
        if (ce_pix && act_px && cpal_new) begin cpal[{cap_buf, cpal_n[4:0]}] <= rgb_in; cpal_n <= cpal_n + 6'd1; end
        if (cap_vbr) cpal_n <= 6'd0;
        pal2 <= cpal[{cp_rbuf, gr_code}];
    end
end else begin : map_hash
    // table: 2^(CB+1) buckets of 4 slots (8 slots per code), all 4 compared at once; up to 3 buckets probed
    localparam int HB = CB + 1, SW = CB + 25;   // bucket address bits, slot = {valid, RGB, code}
    function [HB-1:0] hash(input [23:0] c);
        reg [71:0] s; integer k;
        begin s = {48'd0, c ^ {c[10:0], c[23:11]}}; hash = '0; for (k = 0; k < 24; k = k + HB) hash = hash ^ s[k +: HB]; end
    endfunction
    reg  [23:0] m_rgb;
    reg [HB-1:0] m_h;
    reg   [1:0] m_try;
    reg   [1:0] m_st = 2'd0;         // 0 idle, 1 table read in flight, 2 compare
    reg         m_put = 1'b0;
    reg [CB-1:0] m_code;
    reg [HB-1:0] t_wa, clr_a = '0;
    reg [4*SW-1:0] t_wd;
    reg         t_we = 1'b0, clr = 1'b1;
    wire [4*SW-1:0] t_q;
    dpram_dc #(.widthad_a(HB), .width_a(4 * SW)) ctab
    (
        .clock_a(clk), .address_a(clr ? clr_a : t_wa), .data_a(clr ? '0 : t_wd), .wren_a(clr | t_we), .q_a(),
        .clock_b(clk), .address_b(m_h), .data_b({(4 * SW){1'b0}}), .wren_b(1'b0), .q_b(t_q)   // DPRAMSV-2026-10-25: was .data_b('0)
    );
    reg   [3:0] s_hit, s_free;
    reg [CB-1:0] s_code;             // code of the hit slot (slots hold unique colours: OR of the hits)
    reg   [1:0] s_fi;                // first free slot
    integer     si;
    always @* begin
        s_code = '0; s_fi = 2'd0;
        for (si = 0; si < 4; si = si + 1) begin
            s_hit[si]  = t_q[SW * si + SW - 1] && t_q[SW * si + CB +: 24] == m_rgb;
            s_free[si] = !t_q[SW * si + SW - 1];
            if (s_hit[si]) s_code = s_code | t_q[SW * si +: CB];
        end
        for (si = 3; si >= 0; si = si - 1) if (s_free[si]) s_fi = 2'(si);
    end
    reg         p_we = 1'b0;
    reg [CB-1:0] p_wa;
    wire [23:0] p_q;
    dpram_dc #(.widthad_a(CB + 1), .width_a(24)) cpal
    (
        .clock_a(clk), .address_a({cap_buf, p_wa}), .data_a(m_rgb), .wren_a(p_we), .q_a(),
        .clock_b(clk), .address_b({cp_rbuf, gr_code}), .data_b(24'd0), .wren_b(1'b0), .q_b(p_q)   // DPRAMSV-2026-10-25: was .data_b('0)
    );
    always @* pal2 = p_q;
    assign cap_put  = m_put;
    assign cap_code = m_code;
    always @(posedge clk) begin
        t_we <= 1'b0; p_we <= 1'b0; m_put <= 1'b0;
        if (clr) begin clr_a <= clr_a + 1'd1; if (&clr_a) clr <= 1'b0; end
        if (cap_vbr) begin clr <= 1'b1; clr_a <= '0; cpal_n <= '0; end   // a fresh code set every frame
        case (m_st)
            2'd0: if (ce_pix && act_px && rot) begin m_rgb <= rgb_in; m_h <= hash(rgb_in); m_try <= 2'd0; m_st <= 2'd1; end
            2'd1: m_st <= 2'd2;      // slot m_h is read this clock
            default: begin
                m_st <= 2'd0;
                if (s_hit != 4'd0) begin m_code <= s_code; m_put <= 1'b1; end
                else if (s_free != 4'd0 || m_try == 2'd2) begin  // a free slot (or 3 full buckets): a new code, if any is left
                    m_put <= 1'b1;
                    if (s_free != 4'd0 && !cpal_n[CB]) begin
                        m_code <= cpal_n[CB-1:0]; cpal_n <= cpal_n + 1'd1;
                        t_wa <= m_h; t_wd <= t_q; t_wd[SW * s_fi +: SW] <= {1'b1, m_rgb, cpal_n[CB-1:0]}; t_we <= 1'b1;
                        p_wa <= cpal_n[CB-1:0]; p_we <= 1'b1;
                    end else m_code <= {CB{1'b1}};
                end else begin m_h <= m_h + 1'd1; m_try <= m_try + 2'd1; m_st <= 2'd1; end
            end
        endcase
    end
end endgenerate

wire [63:0] nb_q;
reg   [8:0] nb_x;                   // prefetch: first column of the burst
reg         nb_half;
dpram_dc #(.widthad_a(10), .width_a(64)) nbuf
(
    .clock_a(clk), .address_a({nb_half, 9'(nb_x + {1'b0, ebeat})}), .data_a(DDRAM_DOUT), .wren_a(e_rd[0]), .q_a(),
    .clock_b(clk), .address_b({vblank_in ? 1'b0 : gy_c[0], crt_flip ? 9'(v_nw - 12'd1 - {3'd0, gx_c}) : gx_c[8:0]}), .data_b(64'd0), .wren_b(1'b0), .q_b(nb_q)   // DPRAMSV-2026-10-25: was .data_b('0)
);

reg  run = 1'b0;
assign running = run;

function [7:0] comp(input [7:0] g, input [7:0] q, input [7:0] m);
    comp = sat({1'b0, q} + {1'b0, div255(g * m)});
endfunction

always @(posedge clk) begin
    frame_start <= 1'b0; vbl_rise <= 1'b0; line_inc <= 1'b0;
    if (ce_pix) begin
        old_hbl <= hblank_in; old_vbl <= vblank_in;
        if (act_px) gx_c <= gx_c + 9'd1;
        if (hblank_in) gx_c <= 9'd0;
        if (hblank_in && !old_hbl && !old_vbl) begin gy_c <= gy_c + 9'd1; line_inc <= 1'b1; end
        if (vblank_in && !old_vbl) begin frame_end <= 1'b1; vbl_rise <= 1'b1; end
        if (!vblank_in && old_vbl) begin gy_c <= 9'd0; frame_end <= 1'b0; frame_start <= 1'b1; end

        {hs_out, vs_out, hblank_out, vblank_out} <= {hs_in, vs_in, hblank_in, vblank_in};
        rgb_out <= (run && act_px) ? {comp(rgb_in[23:16], nb_q[7:0], nb_q[39:32]),
                                      comp(rgb_in[15:8], nb_q[15:8], nb_q[47:40]),
                                      comp(rgb_in[7:0], nb_q[23:16], nb_q[55:48])} : rgb_in;
    end
end

// native row prefetch: rows 0 and 1 at the end of a frame, then row y + 1 when line y starts
reg  [8:0] pf_row, pf_upto;
reg        pf_on = 1'b0;
assign     nat_pend = pf_on && pf_row <= pf_upto && pf_row < v_nh[8:0];
always @(posedge clk) begin
    if (e_ack[0]) p_req <= 1'b0;
    if (!run) pf_on <= 1'b0;
    else begin
        if (line_inc) pf_upto <= gy_c + 9'd1;
        // after line_inc: the board raises vblank with the last line's hblank (same clock), and the frame restart must win
        if (vbl_rise) begin pf_row <= 9'd0; pf_upto <= 9'd1; nb_x <= 9'd0; pf_on <= 1'b1; end
        if (pf_on && !p_req) begin
            if (pf_row <= pf_upto && pf_row < v_nh[8:0]) begin
                p_addr <= N_W + {11'd0, crt_flip ? 9'(v_nh - 12'd1 - {3'd0, pf_row}) : pf_row, 9'd0} + {20'd0, nb_x};
                p_len <= (v_nw - {3'd0, nb_x} > 12'd64) ? 8'd64 : 8'(v_nw - {3'd0, nb_x});
                p_req <= 1'b1;
                nb_half <= pf_row[0];
            end
        end
        if (e_ack[0]) begin
            if ({3'd0, nb_x} + 12'd64 >= v_nw) begin nb_x <= 9'd0; pf_row <= pf_row + 9'd1; end
            else nb_x <= nb_x + 9'd64;
        end
    end
end

// =================================================================== compositor: S + game -> framebuffer

reg  [1:0] i_fb = 2'd0, o_fb = 2'd1, l_fb = 2'd2;
reg        fresh = 1'b0, vbl_pend = 1'b0, old_fbvbl = 1'b0;
// shown area: the screen (zoom), else the screen plus every layer drawn (a layer switched off gives its space back)
reg [11:0] k_x0, k_y0, k_x1, k_y1;
wire       fbf = crt_flip ^ hdmi_flip;                                   // framebuffer written rotated 180
wire [11:0] ua_x0 = zoom ? u_sx : k_x0, ua_y0 = zoom ? u_sy : k_y0;            // table coords
wire [11:0] ua_x1 = zoom ? u_sx + u_sw : k_x1, ua_y1 = zoom ? u_sy + u_sh : k_y1;
wire [11:0] sa_x0 = (vw_rot == 2'd0) ? ua_x0 : (vw_rot == 2'd2) ? u_ch - ua_y1 : ua_y0;
wire [11:0] sa_y0 = (vw_rot == 2'd0) ? ua_y0 : (vw_rot == 2'd2) ? ua_x0 : u_cw - ua_x1;
wire [11:0] sa_x1 = (vw_rot == 2'd0) ? ua_x1 : (vw_rot == 2'd2) ? u_ch - ua_y0 : ua_y1;
wire [11:0] sa_y1 = (vw_rot == 2'd0) ? ua_y1 : (vw_rot == 2'd2) ? ua_x1 : u_cw - ua_x0;
wire [11:0] fa_x = fbf ? v_cw - sa_x1 : sa_x0, fa_y = fbf ? v_ch - sa_y1 : sa_y0;
assign     fb_base = {6'b001100, 2'b11, 24'd0} + {6'd0, o_fb, 24'd0}     // 33000000 + n * 01000000
                   + {7'd0, fa_y, 13'd0} + {18'd0, fa_x, 2'd0};
assign     canvas_w = sa_x1 - sa_x0;
assign     canvas_h = sa_y1 - sa_y0;

reg        cp_init = 1'b0;           // one clock: write all three buffers from S (game = black)
reg        cp_idone = 1'b0;
reg        cp_imode;
reg        frame_pend = 1'b0, cp_late = 1'b0;
wire       cp_done1 = cst == C_WR && e_ack[1] && !cp_imode && cp_x + {5'd0, cp_n} == cp_xend && cp_r + 12'd1 == cp_rows;
localparam C_IDLE = 3'd0, C_ROW = 3'd1, C_CHUNK = 3'd2, C_RD = 3'd3, C_CALC = 3'd4, C_WR = 3'd5, C_GY = 3'd6;
reg  [2:0] cst = C_IDLE;
reg [11:0] cp_row, cp_r, cp_x, cp_xend, cp_rows;
reg  [8:0] cp_k, cp_gx;              // capture line needed by this row (raster order), game x
reg [23:0] cp_hacc;
reg [23:0] dv_rem;                   // per-row game line: (row offset * NH) / SH, restoring divide
reg  [8:0] dv_q;
reg  [3:0] dv_b = 4'd0;
reg [11:0] dv_o;
reg  [6:0] cp_n, cp_i, cp_i1, cp_i2, cp_i3;
reg  [6:0] cp_got;                   // S words of this chunk already in ccbuf (written the clock before)
reg        cp_v1, cp_v2, cp_v3;
reg [23:0] g2, g3;                   // stage 2: raw ring pixel (pal2 = its code's colour); stage 3: game pixel
reg [63:0] cc2, cc3;                 // S word, stages 2 / 3
reg  [1:0] cp_buf;
reg [31:0] cp_lo;
wire [63:0] cc_q;
reg [63:0] cw_d;
reg        cw_we;
reg  [4:0] cw_a;
wire       in_rect = !cp_imode;
wire [11:0] fb_row = fbf ? v_ch - 12'd1 - cp_row : cp_row;
wire [11:0] fb_x   = fbf ? v_cw - cp_x - {5'd0, cp_n} : cp_x;

dpram_dc #(.widthad_a(6), .width_a(64)) ccbuf
(
    .clock_a(clk), .address_a(ebeat[5:0]), .data_a(DDRAM_DOUT), .wren_a(e_rd[1]), .q_a(),
    .clock_b(clk), .address_b(cp_i[5:0]), .data_b(64'd0), .wren_b(1'b0), .q_b(cc_q)   // DPRAMSV-2026-10-25: was .data_b('0)
);
wire [63:0] cw_q;
dpram_dc #(.widthad_a(5), .width_a(64)) cwbuf
(
    .clock_a(clk), .address_a(cw_a), .data_a(cw_d), .wren_a(cw_we), .q_a(),
    .clock_b(clk), .address_b(wb_nxt[4:0]), .data_b(64'd0), .wren_b(1'b0), .q_b(cw_q)   // DPRAMSV-2026-10-25: was .data_b('0)
);
assign k_wdata = cw_q;
// rotated: frame index of the game pixel (picture unflipped; the board rotates it 180 for CRT Flip)
reg  [16:0] cp_p;
wire [15:0] cp_pf = crt_flip ? 16'(cap_tot - 16'd1 - cp_p[15:0]) : cp_p[15:0];
always @* gr_ra = rot ? {cp_rbuf, cp_pf[15:3]} : {cp_k[4:0], crt_flip ? 9'(v_nw - 12'd1 - {3'd0, cp_gx}) : cp_gx[8:0]};
always @(posedge clk) gr_sub <= cp_pf[2:0];

wire [31:0] cpx = {8'd0, comp(g3[7:0], cc3[23:16], cc3[55:48]), comp(g3[15:8], cc3[15:8], cc3[47:40]), comp(g3[23:16], cc3[7:0], cc3[39:32])};

always @(posedge clk) begin
    cw_we <= 1'b0;
    if (e_ack[1]) k_req <= 1'b0;
    if (e_rd[1]) cp_got <= cp_got + 7'd1;
    // rotated: a frame is composited once it is wholly captured (vblank), else following the raster
    if (rot ? vbl_rise : frame_start) begin frame_pend <= 1'b1; if (cst != C_IDLE) cp_late <= 1'b1; end

    // triple buffering: o_fb takes the newest finished buffer at the display's vblank
    old_fbvbl <= fb_vbl;
    if (fb_vbl && !old_fbvbl) vbl_pend <= 1'b1;

    if (vbl_pend && !cp_done1) begin vbl_pend <= 1'b0; if (fresh) begin o_fb <= l_fb; fresh <= 1'b0; end end

    case (cst)
        C_IDLE: begin
            if (cp_init) begin
                cp_imode <= 1'b1; cp_row <= 12'd0; cp_r <= 12'd0; cp_rows <= v_ch; cp_idone <= 1'b0; cst <= C_ROW;
            end else if (!run) frame_pend <= 1'b0;                 // only frames that begin while drawing count
            else if (frame_pend) begin
                frame_pend <= 1'b0;
                cp_imode <= 1'b0; cp_r <= 12'd0; cp_rows <= v_sh; cp_rbuf <= ~cap_buf;
                dv_b <= 4'd0; cp_late <= 1'b0; cst <= C_GY;
            end
        end
        C_ROW: begin
            cp_x <= cp_imode ? 12'd0 : v_sx;
            cp_xend <= cp_imode ? v_cw : v_sx + v_sw;
            cp_gx <= 9'd0; cp_hacc <= 24'd0;
            // running late into the next game frame: finish this one anyway (at worst a tear), the next starts at once
            if (cp_imode || rot || cp_late || frame_end || {3'd0, gy_c} > {3'd0, cp_k}) cst <= C_CHUNK;
        end
        C_GY: begin
            // CRT Flip: the picture arrives bottom-up, so the screen rect is composited bottom-up (capture order)
            if (dv_b == 4'd0) begin
                dv_o = (crt_flip && !rot) ? cp_rows - 12'd1 - cp_r : cp_r;
                cp_row <= v_sy + dv_o;
                dv_rem <= dv_o * v_gh; dv_q <= 9'd0; dv_b <= 4'd10;
            end else if (dv_b != 4'd1) begin
                if (dv_rem >= ({12'd0, v_sh} << (dv_b - 4'd2))) begin
                    dv_rem <= dv_rem - ({12'd0, v_sh} << (dv_b - 4'd2));
                    dv_q[dv_b - 4'd2] <= 1'b1;
                end
                dv_b <= dv_b - 4'd1;
            end else begin
                cp_k <= crt_flip ? 9'(v_nh - 12'd1 - {3'd0, dv_q}) : dv_q;
                // rotated: portrait row dv_q = native column; ROT270 x = NW-1-row, y = col; ROT90 x = row, y = NH-1-col
                cp_p <= rot90 ? {1'b0, 16'(cap_tot - {4'd0, v_nw} + {7'd0, dv_q})} : {8'd0, 9'(v_nw - 12'd1 - {3'd0, dv_q})};
                dv_b <= 4'd0; cst <= C_ROW;
            end
        end
        C_CHUNK: begin
            cp_n <= (cp_xend - cp_x > 12'd64) ? 7'd64 : 7'(cp_xend - cp_x);
            k_addr <= S_W + {6'd0, cp_row[10:0], 11'd0} + {17'd0, cp_x};
            k_len <= (cp_xend - cp_x > 12'd64) ? 8'd64 : 8'(cp_xend - cp_x);
            k_we <= 1'b0; k_req <= 1'b1;
            cp_i <= 7'd0; cp_v1 <= 1'b0; cp_v2 <= 1'b0; cp_v3 <= 1'b0; cp_got <= 7'd0;
            cst <= C_CALC;                 // compute while the burst arrives (40 MHz: a serial read-then-calc misses the raster)
        end
        C_CALC: begin
            // address pixel cp_i (S word + game pixel) once its word has landed, register pixel cp_i1 (and read its code's
            // colour), take the colour for pixel cp_i2, compute pixel cp_i3
            cp_v1 <= cp_i < cp_n && cp_i < cp_got; cp_i1 <= cp_i;
            cp_v2 <= cp_v1; cp_i2 <= cp_i1; g2 <= gr_qw[23:0]; cc2 <= cc_q;
            cp_v3 <= cp_v2; cp_i3 <= cp_i2; g3 <= !in_rect ? 24'd0 : rot ? pal2 : g2; cc3 <= cc2;
            if (cp_i < cp_n && cp_i < cp_got) begin
                cp_i <= cp_i + 7'd1;
                if (cp_hacc + {12'd0, v_gw} >= {12'd0, v_sw}) begin
                    cp_hacc <= cp_hacc + {12'd0, v_gw} - {12'd0, v_sw}; cp_gx <= cp_gx + 9'd1;
                    cp_p <= rot90 ? cp_p - {5'd0, v_nw} : cp_p + {5'd0, v_nw};     // next native line
                end
                else cp_hacc <= cp_hacc + {12'd0, v_gw};
            end
            if (cp_v3) begin
                if (!cp_i3[0]) cp_lo <= cpx;
                else begin                // framebuffer rotated 180: words in reverse order, pixels swapped
                    cw_a <= fbf ? 5'(cp_n[6:1] - 6'd1 - {1'b0, cp_i3[5:1]}) : cp_i3[5:1];
                    cw_d <= fbf ? {cp_lo, cpx} : {cpx, cp_lo}; cw_we <= 1'b1;
                end
                if (cp_i3 == cp_n - 7'd1) begin cp_buf <= 2'd0; cst <= C_WR; end
            end
        end
        C_WR: begin
            if (!k_req && !e_wr[1] && !e_ack[1]) begin
                k_addr <= FB0_W + {5'd0, (cp_imode ? cp_buf : i_fb), 21'd0} + {7'd0, fb_row[10:0], 10'd0} + {18'd0, fb_x[11:1]};
                k_len <= {2'd0, cp_n[6:1]}; k_we <= 1'b1; k_req <= 1'b1;
            end
            if (e_ack[1]) begin
                if (cp_imode && cp_buf != 2'd2) cp_buf <= cp_buf + 2'd1;
                else begin
                    if (cp_x + {5'd0, cp_n} != cp_xend) begin cp_x <= cp_x + {5'd0, cp_n}; cst <= C_CHUNK; end
                    else begin
                        cp_row <= cp_row + 12'd1; cp_r <= cp_r + 12'd1;
                        if (cp_r + 12'd1 == cp_rows) begin
                            if (cp_imode) cp_idone <= 1'b1;
                            else begin
                                l_fb <= i_fb; i_fb <= 2'd3 - i_fb - o_fb; fresh <= 1'b1;
                                frame_pend <= 1'b0;    // a frame that began while this one ran late is skipped: its top lines are gone
                            end
                            cst <= C_IDLE;
                        end else cst <= cp_imode ? C_ROW : C_GY;
                    end
                end
            end
        end
        default: cst <= C_IDLE;
    endcase
end

// =================================================================== sequencer

localparam Q_IDLE = 5'd0, Q_GLOB = 5'd1, Q_VIEW = 5'd2, Q_CLEAR = 5'd3, Q_LREC = 5'd4, Q_LGO = 5'd5, Q_LRUN = 5'd6,
           Q_LEND = 5'd7, Q_NAT = 5'd8, Q_NRUN = 5'd9, Q_INIT = 5'd10, Q_IRUN = 5'd11, Q_RUN = 5'd12, Q_STOP = 5'd13,
           Q_FIT = 5'd14, Q_VSCL = 5'd15, Q_VSET = 5'd16, Q_LSCL = 5'd17, Q_LSET = 5'd18;
reg   [4:0] qst = Q_IDLE;
reg   [7:0] rec[16];
reg   [4:0] rk;                      // record byte being fetched (+1 latency)
reg  [10:0] rbase;
reg         rbusy = 1'b0;
assign      hdr_ra = rbase + {6'd0, rk};
reg  [10:0] cur_cfg;
wire [10:0] cfg = {turn, fbf, side_off, layer_off, sel};
assign      avail = blob_ok && img_ok != 32'd0;   // zip missing on the SD card: only the table came, no artwork
reg   [6:0] l_cur, l_end;
reg   [7:0] n_views;
reg         n_pass;
reg  [27:0] wdog;

// HDMI fit: ascal cannot shrink a framebuffer horizontally (a canvas wider / taller than the output is cropped), so the
// view is built at q / 256 of the table's size: the largest q <= 256 whose canvas fits the output, but never below the q
// that keeps the screen rect 2 pixels over the game's native size. One shared multiplier, binary searches over q.
reg  [11:0] hw_s1 = 12'd0, hw_s2 = 12'd0, hh_s1 = 12'd0, hh_s2 = 12'd0;
always @(posedge clk) begin hw_s1 <= hdmi_w; hw_s2 <= hw_s1; hh_s1 <= hdmi_h; hh_s2 <= hh_s1; end
reg  [23:0] cur_hd;
reg  [11:0] t_cw, t_ch, t_sx, t_sy, t_sw, t_sh;   // view record from the table (unscaled)
reg   [8:0] f_q, f_fit;                           // search result so far, the fit's q
reg   [8:0] t_qf = 9'd1;                         // view L0 high byte + 1: smallest q keeping every PNG within 15x downscale
reg   [3:0] f_b;                                  // search bit
reg   [2:0] f_k;                                  // step
reg         f_min;                                // search 0: largest q fitting the output, 1: largest q too small
reg  [20:0] f_p0;
reg  signed [14:0] m_a;
reg   [8:0] m_b;
wire signed [24:0] m_p  = m_a * $signed({1'b0, m_b});
wire signed [16:0] m_sc = 17'((m_p + 25'sd128) >>> 8);                    // round(v * q / 256)
wire [11:0] m_ev = 12'(((m_p + 25'sd256) >>> 9) << 1);                    // the same, rounded to even
reg         s_ox, s_oy;                           // view shifted one pixel / row so the screen starts even
reg  signed [16:0] sl_a;                           // scaled left / top edge
reg  signed [14:0] s_x, s_y, s_x2;                // layer rect, scaled
reg  [11:0] s_w, s_h, s_w2;
reg  [11:0] a_cw, a_ch;
// drawn (after the view rotation) canvas / screen size and the game picture as drawn
wire [11:0] d_cw = (vw_rot != 2'd0) ? t_ch : t_cw, d_ch = (vw_rot != 2'd0) ? t_cw : t_ch;
wire [11:0] d_sw = (vw_rot != 2'd0) ? t_sh : t_sw, d_sh = (vw_rot != 2'd0) ? t_sw : t_sh;
wire  [8:0] f_c  = f_q | (9'd1 << f_b);
wire        f_ok = f_min ? (f_p0 < {1'b0, 12'(v_gw + 12'd2), 8'd0} || m_p[20:0] < {1'b0, 12'(v_gh + 12'd2), 8'd0})
                         : (f_p0 <= {1'b0, hw_s2, 8'd0} && m_p[20:0] <= {1'b0, hh_s2, 8'd0});
wire  [8:0] f_fin = f_ok ? f_c : f_q;
wire  [9:0] f_qmin = {1'b0, f_fin} + 10'd1;
wire  [9:0] f_flr = (f_qmin > {1'b0, t_qf}) ? f_qmin : {1'b0, t_qf};      // floor: native game size, PNG downscale
wire  [8:0] f_sel = (f_flr > {1'b0, f_fit}) ? ((f_flr > 10'd256) ? 9'd256 : f_flr[8:0]) : f_fit;
wire        chg   = cfg != cur_cfg || {hh_s2, hw_s2} != cur_hd;          // rebuild: OSD settings or HDMI size changed

wire [15:0] r16_0 = {rec[1], rec[0]},  r16_1 = {rec[3], rec[2]},  r16_2 = {rec[5], rec[4]},  r16_3 = {rec[7], rec[6]};
// layer rect: side art (flag bit 4) uses its alternate x / width and the screen's rows when bezels are off
wire        l_alt = cur_cfg[6] && rec[2][4];
// record fields (table scale) and the rect as drawn (scaled by Q_LSCL)
wire signed [14:0] r_x  = $signed({rec[5][6:0], rec[4]}), r_y = $signed({rec[7][6:0], rec[6]}), r_x2 = $signed({rec[13][6:0], rec[12]});
wire        [11:0] r_w  = {rec[9][3:0], rec[8]}, r_h = {rec[11][3:0], rec[10]}, r_w2 = {rec[15][3:0], rec[14]};
wire signed [14:0] lr_x  = l_alt ? s_x2 : s_x;
wire signed [14:0] lr_y  = l_alt ? $signed({3'b000, u_sy}) : s_y;
wire        [11:0] lr_w  = l_alt ? s_w2 : s_w;
wire        [11:0] lr_h  = l_alt ? u_sh : s_h;
wire signed [14:0] lr_x1 = lr_x + $signed({3'b000, lr_w}), lr_y1 = lr_y + $signed({3'b000, lr_h});
// layer rect clipped to the canvas (for the shown area)
wire [11:0] lc_x0 = lr_x < 0 ? 12'd0 : lr_x[11:0], lc_y0 = lr_y < 0 ? 12'd0 : lr_y[11:0];
wire [11:0] lc_x1 = lr_x1 > $signed({3'b000, u_cw}) ? u_cw : lr_x1[11:0], lc_y1 = lr_y1 > $signed({3'b000, u_ch}) ? u_ch : lr_y1[11:0];
wire        l_draw = (rec[2][6] || img_ok[rec[1][4:0]]) && !cur_cfg[4 + rec[2][3:2]] && !(cur_cfg[8] && rec[2][5]);
wire [15:0] r16_4 = {rec[9], rec[8]},  r16_5 = {rec[11], rec[10]}, r16_6 = {rec[13], rec[12]}, r16_7 = {rec[15], rec[14]};

assign ddr_owner = qst != Q_IDLE || est != E_IDLE || c_req != 5'd0;

always @(posedge clk) begin
    rd_go <= 1'b0; rd_stop <= 1'b0; res_go <= 1'b0; bl_go <= 1'b0; cp_init <= 1'b0;

    // 16-byte record fetch from the layout table
    if (rbusy) begin
        if (rk != 5'd0) rec[rk - 5'd1] <= hdr_q;
        rk <= rk + 5'd1;
        if (rk == 5'd16) rbusy <= 1'b0;
    end

    if (ioctl_download && (ioctl_index == 8'd0 || ioctl_index == IDX)) begin
        // ROM / artwork reload: stop drawing (DDR transactions in flight finish on their own)
        run <= 1'b0; png_rst <= 1'b1; bl_abort <= 1'b1; rd_stop <= 1'b1;
        if (qst != Q_IDLE && bst == B_IDLE && cst == C_IDLE) qst <= Q_IDLE;
    end
    else case (qst)
        Q_IDLE: begin
            bl_abort <= 1'b0;
            if (avail && sel != 4'd0 && !rbusy) begin
                cur_cfg <= cfg; cur_hd <= {hh_s2, hw_s2}; rbase <= 11'd0; rk <= 5'd0; rbusy <= 1'b1; qst <= Q_GLOB;
            end
        end
        Q_GLOB: if (!rbusy && !(rk == 5'd0)) begin
            if (r16_0 != 16'h5741 || {4'd0, cur_cfg[3:0]} > rec[2]) qst <= Q_STOP;   // no table / no such view
            else begin
                v_nw <= r16_3[11:0]; v_nh <= r16_4[11:0];
                // turned: ROT270 layout CW and ROT90 CCW (the game is then the native raster), horizontal CW (game as ROT90)
                v_rot  <= !cur_cfg[10] ? rec[10][1:0] : (rec[10][1:0] == 2'd0) ? 2'd2 : 2'd0;
                vw_rot <= !cur_cfg[10] ? 2'd0 : (rec[10][1:0] == 2'd2) ? 2'd1 : 2'd2;
                rbase <= 11'd16 + {3'd0, 4'(cur_cfg[3:0] - 4'd1), 4'd0}; rk <= 5'd0; rbusy <= 1'b1; qst <= Q_VIEW;
            end
        end
        Q_VIEW: if (!rbusy) begin
            t_cw <= r16_0[11:0]; t_ch <= r16_1[11:0]; t_sx <= r16_2[11:0]; t_sy <= r16_3[11:0];
            t_sw <= r16_4[11:0]; t_sh <= r16_5[11:0];
            l_cur <= r16_6[6:0]; l_end <= 7'(r16_6[6:0] + r16_7[6:0]); t_qf <= {1'b0, rec[13]} + 9'd1;
            // HDMI size unknown (direct video): no fit search, only the native-size floor
            f_q <= 9'd0; f_b <= 4'd8; f_k <= 3'd0; f_fit <= 9'd256; f_min <= hw_s2 == 12'd0 || hh_s2 == 12'd0;
            qst <= Q_FIT;
        end
        Q_FIT: begin                                        // per q bit: two products, then keep the bit if f_ok
            case (f_k)
                3'd0: begin m_a <= $signed({3'b000, f_min ? d_sw : d_cw}); m_b <= f_c; f_k <= 3'd1; end
                3'd1: begin f_p0 <= m_p[20:0]; m_a <= $signed({3'b000, f_min ? d_sh : d_ch}); f_k <= 3'd2; end
                default: begin
                    f_k <= 3'd0;
                    if (f_b != 4'd0) begin f_q <= f_fin; f_b <= f_b - 4'd1; end
                    else if (!f_min) begin f_fit <= (f_fin > 9'd256) ? 9'd256 : f_fin; f_min <= 1'b1; f_q <= 9'd0; f_b <= 4'd8; end
                    else begin m_b <= f_sel; m_a <= $signed({3'b000, t_sx}); qst <= Q_VSCL; end
                end
            endcase
        end
        Q_VSCL: begin                                       // view at q / 256; screen x / y, sizes and canvas kept even
            f_k <= f_k + 3'd1;
            case (f_k)
                3'd0: begin s_ox <= m_sc[0]; u_sx <= 12'(m_sc[11:0] - {11'd0, m_sc[0]}); m_a <= $signed({3'b000, t_sy}); end
                3'd1: begin s_oy <= m_sc[0]; u_sy <= 12'(m_sc[11:0] - {11'd0, m_sc[0]}); m_a <= $signed({3'b000, t_cw}); end
                3'd2: begin a_cw <= m_sc[11:0]; m_a <= $signed({3'b000, t_ch}); end
                3'd3: begin a_ch <= m_sc[11:0]; m_a <= $signed({3'b000, t_sw}); end
                3'd4: begin u_sw <= m_ev; m_a <= $signed({3'b000, t_sh}); end
                default: begin
                    u_sh <= m_ev;
                    u_cw <= (a_cw - {11'd0, s_ox} + 12'd1) & ~12'd1; u_ch <= (a_ch - {11'd0, s_oy} + 12'd1) & ~12'd1;
                    qst <= Q_VSET;
                end
            endcase
        end
        Q_VSET: begin
            if (vw_rot == 2'd0) begin
                v_cw <= u_cw; v_ch <= u_ch; v_sx <= u_sx; v_sy <= u_sy; v_sw <= u_sw; v_sh <= u_sh;
            end else begin                   // turned 90: CW screen x = CH - SY - SH, y = SX; CCW x = SY, y = CW - SX - SW
                v_cw <= u_ch; v_ch <= u_cw; v_sw <= u_sh; v_sh <= u_sw;
                v_sx <= (vw_rot == 2'd2) ? 12'(u_ch - u_sy - u_sh) : u_sy;
                v_sy <= (vw_rot == 2'd2) ? u_sx : 12'(u_cw - u_sx - u_sw);
            end
            k_x0 <= u_sx; k_y0 <= u_sy; k_x1 <= u_sx + u_sw; k_y1 <= u_sy + u_sh;
            // clear S (canvas as drawn)
            l_op <= 3'd7; l_rect <= 1'b0; bl_nplane <= 1'b0; bl_rot <= 2'd0; bl_x <= 14'sd0; bl_y <= 14'sd0;
            if (vw_rot == 2'd0) begin bl_w <= u_cw; bl_h <= u_ch; bl_cw <= u_cw; bl_ch <= u_ch; end
            else begin bl_w <= u_ch; bl_h <= u_cw; bl_cw <= u_ch; bl_ch <= u_cw; end
            bl_go <= 1'b1; qst <= Q_CLEAR;
        end
        Q_CLEAR: if (!bl_go && bl_done) begin
            if (l_cur == l_end) qst <= Q_NAT;
            else begin rbase <= 11'd256 + {l_cur, 4'd0}; rk <= 5'd0; rbusy <= 1'b1; qst <= Q_LREC; end
        end
        Q_LREC: if (!rbusy) begin m_a <= r_x; f_k <= 3'd0; qst <= Q_LSCL; end
        Q_LSCL: begin                                       // layer rect at q / 256, edges scaled (neighbours stay joined)
            f_k <= f_k + 3'd1;
            case (f_k)
                3'd0: begin sl_a <= m_sc; s_x <= 15'(m_sc - {16'd0, s_ox}); m_a <= 15'(r_x + $signed({3'b000, r_w})); end
                3'd1: begin s_w <= 12'(m_sc - sl_a); m_a <= r_y; end
                3'd2: begin sl_a <= m_sc; s_y <= 15'(m_sc - {16'd0, s_oy}); m_a <= 15'(r_y + $signed({3'b000, r_h})); end
                3'd3: begin s_h <= 12'(m_sc - sl_a); m_a <= r_x2; end
                3'd4: begin sl_a <= m_sc; s_x2 <= 15'(m_sc - {16'd0, s_ox}); m_a <= 15'(r_x2 + $signed({3'b000, r_w2})); end
                default: begin s_w2 <= 12'(m_sc - sl_a); qst <= Q_LSET; end
            endcase
        end
        Q_LSET: begin
            l_op <= rec[0][2:0]; l_ca <= rec[3];
            l_rect <= rec[2][6];             // rect layer: colour {byte 1, byte 12, byte 13}
            rect_px <= {div255(rec[1] * rec[3]), div255(rec[12] * rec[3]), div255(rec[13] * rec[3]), rec[3]};
            bl_mask <= rec[2][1]; res_flip <= rec[2][0];
            bl_x <= lr_x[13:0]; bl_y <= lr_y[13:0];
            bl_w <= lr_w; bl_h <= lr_h; res_dw <= lr_w; res_dh <= lr_h;
            bl_cw <= u_cw; bl_ch <= u_ch; bl_nplane <= 1'b0; bl_rot <= vw_rot;
            rd_off <= img_off[rec[1][4:0]]; rd_smode <= 1'b0;
            qst <= l_draw ? Q_LGO : Q_LEND;                       // missing image / layer off
            if (l_draw && lr_x1 > 0 && lr_y1 > 0 && lc_x0 < u_cw && lc_y0 < u_ch) begin
                if (lc_x0 < k_x0) k_x0 <= lc_x0;
                if (lc_y0 < k_y0 && !cur_cfg[6]) k_y0 <= lc_y0;      // bezels off: keep to the screen's rows
                if (lc_x1 > k_x1) k_x1 <= lc_x1;
                if (lc_y1 > k_y1 && !cur_cfg[6]) k_y1 <= lc_y1;
            end
        end
        Q_LGO: begin
            if (!l_rect) begin png_rst <= 1'b0; rd_go <= 1'b1; end
            bl_go <= 1'b1; wdog <= 28'd0; qst <= Q_LRUN;
        end
        Q_LRUN: begin
            wdog <= (png_px_valid || src_valid) ? 28'd0 : wdog + 28'd1;   // stall timer: big bezels take seconds
            if (&wdog) bl_abort <= 1'b1;                    // corrupt / truncated PNG: give up on this layer
            if (!bl_go && bl_done) begin bl_abort <= 1'b0; rd_stop <= 1'b1; png_rst <= 1'b1; qst <= Q_LEND; end
        end
        Q_LEND: if (!rd_run && !r_req && est == E_IDLE) begin   // reader stopped and its last burst has landed
            l_cur <= l_cur + 7'd1;
            if (l_cur + 7'd1 == l_end) begin n_pass <= 1'b0; qst <= Q_NAT; end
            else begin rbase <= 11'd256 + {7'(l_cur + 7'd1), 4'd0}; rk <= 5'd0; rbusy <= 1'b1; qst <= Q_LREC; end
        end
        Q_NAT: begin                                        // S screen rect -> N plane (Q pass, then M pass)
            rd_smode <= 1'b1; rd_mq <= n_pass; l_rect <= 1'b0;
            l_op <= n_pass ? 3'd6 : 3'd5; bl_mask <= 1'b0; res_flip <= 1'b0;
            bl_nplane <= 1'b1; bl_rot <= 2'd0; bl_x <= 14'sd0; bl_y <= 14'sd0;
            bl_w <= v_nw; bl_h <= v_nh; bl_cw <= v_nw; bl_ch <= v_nh; res_dw <= v_nw; res_dh <= v_nh;
            rd_go <= 1'b1; res_go <= 1'b1; bl_go <= 1'b1;
            qst <= Q_NRUN;
        end
        Q_NRUN: if (!bl_go && bl_done) begin
            rd_stop <= 1'b1;
            if (!rd_run && !r_req && est == E_IDLE) begin
                if (!n_pass) begin n_pass <= 1'b1; qst <= Q_NAT; end
                else begin cp_init <= 1'b1; qst <= Q_IRUN; end
            end
        end
        Q_IRUN: if (!cp_init && cp_idone) begin run <= 1'b1; qst <= Q_RUN; end
        Q_RUN: if (chg) begin run <= 1'b0; qst <= Q_STOP; end
        Q_STOP: if (cst == C_IDLE && !p_req && !k_req && est == E_IDLE && chg) qst <= Q_IDLE;
        default: qst <= Q_IDLE;
    endcase
end

`ifdef ART_DEBUG
reg  [4:0] dbg_q = 5'd0;
reg [31:0] dbg_c = 32'd0;
reg  [4:0] dbg_n = 5'd0;
always @(posedge clk) begin
    dbg_c <= dbg_c + 32'd1;
    dbg_q <= qst;
    if (qst == Q_GLOB && !rbusy && rk != 5'd0) $display("%0d: glob rec %02x %02x %02x %02x cur_cfg %03x sel %0d", dbg_c, rec[0], rec[1], rec[2], rec[3], cur_cfg, sel);
    if (qst != dbg_q) $display("%0d: qst %0d layer %0d op %0d rect %0d,%0d %0dx%0d img_ok %08x", dbg_c, qst, l_cur, l_op, bl_x, bl_y, bl_w, bl_h, img_ok);
    if (r_byte_v && png_in_ready && dbg_n < 20) begin dbg_n <= dbg_n + 5'd1; $display("%0d: byte %02x pst %0d bcnt %0d clen %0d cpos %0d ctype_ch %0d rst %0d", dbg_c, r_byte, png.pst, png.bcnt, png.clen, png.cpos, png.ctype_ch, png_rst); end
    if (rd_go) dbg_n <= 5'd0;
    if (cp_done1) $display("%0d: frame done buf %0d", dbg_c, i_fb);
    if (cst == C_IDLE && frame_pend && run && !cp_init) $display("%0d: composite start rot %0d", dbg_c, rot);
    if (frame_start && run) $display("%0d: frame_start cst %0d row %0d", dbg_c, cst, cp_r);
    if (vbl_pend && !cp_done1 && fresh) $display("%0d: show buf %0d", dbg_c, l_fb);
    if (rd_go) $display("%0d: reader start off %0d smode %0d", dbg_c, rd_off, rd_smode);
    if (png_img_start && !png_rst) $display("%0d: png %0dx%0d", dbg_c, png_w, png_h);
    if (dbg_c[23:0] == 24'd0) $display("%0d: qst %0d bst %0d bp %0d,%0d png_rst %0d rd_run %0d r_wv %0d res_in_ready %0d res_valid %0d pm_valid %0d cst %0d est %0d req %b wait %0d", dbg_c, qst, bst, bp_x, bp_y, png_rst, rd_run, r_wv, res_in_ready, res_valid, pm_valid, cst, est, c_req, ioctl_wait);
end
`endif

endmodule
