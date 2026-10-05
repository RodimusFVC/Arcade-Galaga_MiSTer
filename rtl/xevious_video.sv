//============================================================================
//
//  Xevious video: scrolling 64 x 32 background and foreground, 64 sprites
//
//  Per MAME xevious.cpp (Nicola Salmoria): background (2bpp, colour lookup),
//  sprites (3bpp, colour lookup, drawn over the background), foreground text
//  (1bpp, on top); palette = three 4-bit colour PROMs. Coordinates are
//  MAME's raw screen: x 0-287, y 0-223. Counters come from galaga_video.
//
//============================================================================

module xevious_video
(
    input               clk,            // 49.152 MHz
    input         [2:0] sub,            // fabric clock within the pixel; ce6 when sub == 7
    input               ce6,
    input               xevios,         // bootleg ROM bit order (MAME init_xevios)
    input               flip,           // CRTC register 7
    input               crt_flip,       // OSD: mirror the picture both ways
    input         [8:0] bg_sx, bg_sy, fg_sx, fg_sy,
    input         [8:0] hcnt,
    input         [8:0] vcnt,
    input               line_step,

    // tile RAMs (B000 fg colour, B800 bg colour, C000 fg code, C800 bg code) and sprite registers
    // (A780 code / colour, 8780 y / x, 9780 flags / x msb), read ports
    output reg   [10:0] fg_addr,
    input         [7:0] fgc_q,
    input         [7:0] fgv_q,
    output reg   [10:0] bg_addr,
    input         [7:0] bgc_q,
    input         [7:0] bgv_q,
    output reg   [10:0] spr_addr,
    input         [7:0] sr1_q,
    input         [7:0] sr2_q,
    input         [7:0] sr3_q,

    // ROM / PROM load (ioctl index 0)
    input        [24:0] ioctl_addr,
    input         [7:0] ioctl_dout,
    input               gfx1_wr,
    input               gfx2_wr,
    input               gfx3_wr,
    input               prom_wr,

    output reg    [7:0] red = 8'd0,
    output reg    [7:0] green = 8'd0,
    output reg    [7:0] blue = 8'd0
);

// raw-screen position of the current pixel (galaga_video's mapping)
wire [8:0] px = (hcnt >= 9'h0F0) ? hcnt - 9'h0F0 : hcnt + 9'd144;
wire [8:0] py = vcnt - 9'd16;
wire       h_vis = (hcnt >= 9'h0F0) || (hcnt < 9'h090);
wire       v_vis = (vcnt >= 9'd16) && (vcnt < 9'd240);
wire       mir   = crt_flip ^ flip;
wire [8:0] fpx   = mir ? 9'd287 - px : px;
wire [8:0] fpy   = mir ? 9'd223 - py : py;

function [7:0] bswap_spr(input [7:0] v);    // bitswap<8>(v, 1,3,5,7,0,2,4,6)
    bswap_spr = {v[1], v[3], v[5], v[7], v[0], v[2], v[4], v[6]};
endfunction

//------------------------------------------------------- ROMs / PROMs --------------------------------------------------------//

// foreground characters (gfx1, 512 x 8 x 8 1bpp; 100-1FF = the x-flipped set)
reg  [11:0] fgr_addr;
wire  [7:0] fgr_q;
dpram_dc #(.widthad_a(12)) fg_rom
(
    .clock_a(clk), .address_a(fgr_addr), .data_a(8'h00), .wren_a(1'b0), .q_a(fgr_q),
    .clock_b(clk), .address_b(ioctl_addr[11:0]), .data_b(ioctl_dout), .wren_b(gfx1_wr && ioctl_addr[12] == 1'b0), .q_b()
);

// background characters (gfx2): plane 0 in the first 4K, plane 1 in the second
reg  [11:0] bgr_addr;
wire  [7:0] bgr0_q, bgr1_q;
dpram_dc #(.widthad_a(12)) bg_rom0
(
    .clock_a(clk), .address_a(bgr_addr), .data_a(8'h00), .wren_a(1'b0), .q_a(bgr0_q),
    .clock_b(clk), .address_b(ioctl_addr[11:0]), .data_b(ioctl_dout), .wren_b(gfx2_wr && ioctl_addr[13:12] == 2'd0), .q_b()
);
dpram_dc #(.widthad_a(12)) bg_rom1
(
    .clock_a(clk), .address_a(bgr_addr), .data_a(8'h00), .wren_a(1'b0), .q_a(bgr1_q),
    .clock_b(clk), .address_b(ioctl_addr[11:0]), .data_b(ioctl_dout), .wren_b(gfx2_wr && ioctl_addr[13:12] == 2'd1), .q_b()
);

// sprites (gfx3, ioctl 18000): planes 0/1 at 0000-4FFF (32K store), plane 2 at 5000-6FFF (8K store)
wire [17:0] g3_off = ioctl_addr[17:0] - 18'h18000;
wire [17:0] g3_hi  = g3_off - 18'h05000;
reg  [14:0] spa_addr;
wire  [7:0] spa_q;
dpram_dc #(.widthad_a(15)) spr_rom_a
(
    .clock_a(clk), .address_a(spa_addr), .data_a(8'h00), .wren_a(1'b0), .q_a(spa_q),
    .clock_b(clk), .address_b(g3_off[14:0]), .data_b(ioctl_dout), .wren_b(gfx3_wr && g3_off < 18'h05000), .q_b()
);

reg  [12:0] spb_addr;
wire  [7:0] spb_q;
dpram_dc #(.widthad_a(13)) spr_rom_b
(
    .clock_a(clk), .address_a(spb_addr), .data_a(8'h00), .wren_a(1'b0), .q_a(spb_q),
    .clock_b(clk), .address_b(g3_hi[12:0]), .data_b(ioctl_dout), .wren_b(gfx3_wr && g3_hi < 18'h02000), .q_b()
);

// PROMs: 000 red, 100 green, 200 blue (128 used), 300 / 500 background lookup low / high, 700 / 900 sprite lookup
reg   [9:0] pal_addr;
wire  [7:0] pal_r, pal_g, pal_b;
dpram_dc #(.widthad_a(8)) prom_r
(
    .clock_a(clk), .address_a(pal_addr[7:0]), .data_a(8'h00), .wren_a(1'b0), .q_a(pal_r),
    .clock_b(clk), .address_b(ioctl_addr[7:0]), .data_b(ioctl_dout), .wren_b(prom_wr && ioctl_addr[11:8] == 4'h0), .q_b()
);
dpram_dc #(.widthad_a(8)) prom_g
(
    .clock_a(clk), .address_a(pal_addr[7:0]), .data_a(8'h00), .wren_a(1'b0), .q_a(pal_g),
    .clock_b(clk), .address_b(ioctl_addr[7:0]), .data_b(ioctl_dout), .wren_b(prom_wr && ioctl_addr[11:8] == 4'h1), .q_b()
);
dpram_dc #(.widthad_a(8)) prom_b
(
    .clock_a(clk), .address_a(pal_addr[7:0]), .data_a(8'h00), .wren_a(1'b0), .q_a(pal_b),
    .clock_b(clk), .address_b(ioctl_addr[7:0]), .data_b(ioctl_dout), .wren_b(prom_wr && ioctl_addr[11:8] == 4'h2), .q_b()
);

wire [11:0] prom_off = ioctl_addr[11:0];
reg   [8:0] bgl_addr;
wire  [7:0] bgl_lo, bgl_hi;
dpram_dc #(.widthad_a(9)) prom_bgl_lo
(
    .clock_a(clk), .address_a(bgl_addr), .data_a(8'h00), .wren_a(1'b0), .q_a(bgl_lo),
    .clock_b(clk), .address_b(prom_off[8:0] - 9'h100), .data_b(ioctl_dout), .wren_b(prom_wr && prom_off >= 12'h300 && prom_off < 12'h500), .q_b()
);
dpram_dc #(.widthad_a(9)) prom_bgl_hi
(
    .clock_a(clk), .address_a(bgl_addr), .data_a(8'h00), .wren_a(1'b0), .q_a(bgl_hi),
    .clock_b(clk), .address_b(prom_off[8:0] - 9'h100), .data_b(ioctl_dout), .wren_b(prom_wr && prom_off >= 12'h500 && prom_off < 12'h700), .q_b()
);

reg   [8:0] spl_addr;
wire  [7:0] spl_lo, spl_hi;
dpram_dc #(.widthad_a(9)) prom_spl_lo
(
    .clock_a(clk), .address_a(spl_addr), .data_a(8'h00), .wren_a(1'b0), .q_a(spl_lo),
    .clock_b(clk), .address_b(prom_off[8:0] - 9'h100), .data_b(ioctl_dout), .wren_b(prom_wr && prom_off >= 12'h700 && prom_off < 12'h900), .q_b()
);
dpram_dc #(.widthad_a(9)) prom_spl_hi
(
    .clock_a(clk), .address_a(spl_addr), .data_a(8'h00), .wren_a(1'b0), .q_a(spl_hi),
    .clock_b(clk), .address_b(prom_off[8:0] - 9'h100), .data_b(ioctl_dout), .wren_b(prom_wr && prom_off >= 12'h900 && prom_off < 12'hB00), .q_b()
);

//------------------------------------------------------- Sprite line buffer --------------------------------------------------//

// two lines of 512: entry = {opaque, palette entry 0-127}
reg   [9:0] lb_disp_addr;
reg         lb_disp_clr;
wire  [7:0] lb_disp_q;
reg   [9:0] lb_eng_addr;
reg   [7:0] lb_eng_data;
reg         lb_eng_wr;

dpram_dc #(.widthad_a(10)) line_buf
(
    .clock_a(clk), .address_a(lb_disp_addr), .data_a(8'h00), .wren_a(lb_disp_clr), .q_a(lb_disp_q),
    .clock_b(clk), .address_b(lb_eng_addr), .data_b(lb_eng_data), .wren_b(lb_eng_wr), .q_b()
);

//------------------------------------------------------- Tile layers + pixel path --------------------------------------------//

// MAME tilemap scroll: source = screen + scroll - dx; background dx -20 / dy -16, foreground dx -32 / dy -18
wire [8:0] bx = fpx + bg_sx + 9'd20;
wire [7:0] by = fpy[7:0] + bg_sy[7:0] + 8'd16;
wire [8:0] fx = fpx + fg_sx + 9'd32;
wire [7:0] fy = fpy[7:0] + fg_sy[7:0] + 8'd18;

reg  [2:0] bx_l, by_l, fx_l, fy_l;
reg  [7:0] bg_attr, fg_attr;
reg  [7:0] bg_code;
reg  [2:0] bxi, byi, fxi;
reg  [1:0] bg_pix;
reg        fg_bit;
reg  [6:0] bg_color;
reg  [5:0] fg_color;
reg  [7:0] s_entry;
reg        vis_a, vis_b;
reg  [7:0] s_entry_b;
reg        fg_bit_b;
reg  [5:0] fg_color_b;

// background: code = video + attr0 * 256, colour = attr 5-2 | code bit 7 << 4 | attr 1-0 << 5, attr 6 flip x,
// attr 7 flip y. Foreground: colour = attr 1-0 << 4 | attr 5-2, attr 6 / 7 flips; the game flip picks the x-flipped
// character set (code + 100) instead of mirroring x.
always @(posedge clk) begin
    lb_disp_clr <= 1'b0;
    case (sub)
        3'd0: begin
            bg_addr      <= {by[7:3], bx[8:3]};
            fg_addr      <= {fy[7:3], fx[8:3]};
            bx_l         <= bx[2:0];
            by_l         <= by[2:0];
            fx_l         <= fx[2:0];
            fy_l         <= fy[2:0];
            lb_disp_addr <= {py[0], crt_flip ? 9'd287 - px : px};
            vis_a        <= h_vis & v_vis;
        end
        3'd2: begin
            bg_attr <= bgc_q;
            fg_attr <= fgc_q;
            bg_code <= bgv_q;
            bxi     <= bx_l ^ {3{bgc_q[6]}};
            byi     <= by_l ^ {3{bgc_q[7]}};
            fxi     <= fx_l ^ {3{fgc_q[6] ^ flip}};
            bgr_addr <= {bgc_q[0], bgv_q, by_l ^ {3{bgc_q[7]}}};
            fgr_addr <= {flip, fgv_q, fy_l ^ {3{fgc_q[7]}}};
            s_entry <= lb_disp_q;
            lb_disp_clr <= vis_a;
        end
        3'd4: begin
            bg_pix   <= {bgr0_q[3'd7 - bxi], bgr1_q[3'd7 - bxi]};
            fg_bit   <= fgr_q[3'd7 - fxi];
            bg_color <= {bg_attr[1:0], bg_code[7], bg_attr[5:2]};
            fg_color <= {fg_attr[1:0], fg_attr[5:2]};
        end
        3'd5: bgl_addr <= {bg_color, bg_pix};
        3'd7: begin
            vis_b      <= vis_a;
            s_entry_b  <= s_entry;
            fg_bit_b   <= fg_bit;
            fg_color_b <= fg_color;
        end
        default: ;
    endcase
end

// colour stage: foreground > sprites > background; palette entry 80 = black
reg  [7:0] pen;
reg  [7:0] bg_pen_b;
always @(posedge clk) begin
    if (sub == 3'd7) bg_pen_b <= {bgl_hi[3:0], bgl_lo[3:0]};
    if (sub == 3'd0) begin
        if (fg_bit_b)          pen <= {2'b00, fg_color_b};
        else if (s_entry_b[7]) pen <= {1'b0, s_entry_b[6:0]};
        else                   pen <= bg_pen_b;
    end
    if (sub == 3'd1) pal_addr <= {2'b00, pen};
end

// 4-bit DACs: 0x0e, 0x1f, 0x43, 0x8f
function [7:0] dac4(input [3:0] v);
    dac4 = (v[0] ? 8'h0e : 8'h00) + (v[1] ? 8'h1f : 8'h00) + (v[2] ? 8'h43 : 8'h00) + (v[3] ? 8'h8f : 8'h00);
endfunction

reg black;
always @(posedge clk) begin
    if (sub == 3'd3) black <= ~vis_b | pen[7];
    if (ce6) begin
        red   <= black ? 8'd0 : dac4(pal_r[3:0]);
        green <= black ? 8'd0 : dac4(pal_g[3:0]);
        blue  <= black ? 8'd0 : dac4(pal_b[3:0]);
    end
end

//------------------------------------------------------- Sprite engine -------------------------------------------------------//

// MAME draw_sprites: for each of 64 entries at 780 + 2n with sr3[1] bit 6 clear: code = sr3[0] (or (sr3[0] & 3F) + 100
// when sr2[0] bit 7), colour = sr3[1] & 7F, flips sr2[0] bits 2 (x) / 3 (y), sx = sr1[1] - 40 + 256 * sr2[1] bit 0,
// sy = 223 - sr1[0]; sr2[0] bit 1 double height, bit 0 double width, as up to four 16 x 16 tiles placed per MAME.
localparam S_IDLE = 3'd0, S_FETCH = 3'd1, S_TILE = 3'd2, S_DRAW = 3'd3, S_NEXT = 3'd4;

reg  [2:0] st = S_IDLE;
reg  [5:0] s_num;
reg  [1:0] f_cnt;
reg  [7:0] r_code, r_color, r_y, r_x, r_flags, r_xmsb;
reg  [8:0] tgt_y;
reg        tgt_buf;
reg  [1:0] t_idx;
reg  [3:0] d_px;
reg  [3:0] d_row;
reg  [8:0] d_code;
reg  [9:0] d_x;

wire       e_dh = r_flags[1];
wire       e_dw = r_flags[0];
wire       e_fx = r_flags[2] ^ flip;
wire       e_fy = r_flags[3] ^ flip;
wire [8:0] e_code0 = r_flags[7] ? {3'b100, r_code[5:0]} : {1'b0, r_code};   // set 3 = codes 100-13F
wire [9:0] e_sx = {1'b0, r_xmsb[0], r_x} - 10'd40;
wire [9:0] e_sy = 10'd223 - {2'b00, r_y};

// tile t: code offset, x offset (0 / 16), y offset (0 / -16), present
reg  [1:0] tc;
reg        tx, ty, tp;
always @(*) begin
    tc = 2'd0; tx = 1'b0; ty = 1'b0; tp = 1'b0;
    if (e_dh && e_dw) begin
        case (t_idx)
            2'd0: begin tc = 2'd3; tx = ~e_fx; ty =  e_fy; tp = 1'b1; end
            2'd1: begin tc = 2'd1; tx = ~e_fx; ty = ~e_fy; tp = 1'b1; end
            2'd2: begin tc = 2'd2; tx =  e_fx; ty =  e_fy; tp = 1'b1; end
            2'd3: begin tc = 2'd0; tx =  e_fx; ty = ~e_fy; tp = 1'b1; end
        endcase
    end
    else if (e_dh) begin
        case (t_idx)
            2'd0: begin tc = 2'd2; tx = e_fx; ty =  e_fy; tp = 1'b1; end
            2'd1: begin tc = 2'd0; tx = e_fx; ty = ~e_fy; tp = 1'b1; end
            default: ;
        endcase
    end
    else if (e_dw) begin
        case (t_idx)
            2'd0: begin tc = 2'd0; tx =  e_fx; ty = e_fy; tp = 1'b1; end
            2'd1: begin tc = 2'd1; tx = ~e_fx; ty = e_fy; tp = 1'b1; end
            default: ;
        endcase
    end
    else if (t_idx == 2'd0) tp = 1'b1;
end

wire [8:0] e_base   = e_dh && e_dw ? {e_code0[8:2], 2'b00} : e_dh ? {e_code0[8:2], 1'b0, e_code0[0]} :
                      e_dw ? {e_code0[8:1], 1'b0} : e_code0;
wire [9:0] e_ty     = e_sy - (ty ? 10'd16 : 10'd0);
wire [9:0] e_dy     = {1'b0, tgt_y} - e_ty;                       // line inside the tile when < 16
wire       e_hit    = tp && e_dy < 10'd16;

// 64 bytes per sprite: x 0-3 / 4-7 / 8-11 / 12-15 in bytes 0 / 8 / 16 / 24, rows 8-15 at +32
wire [3:0]  d_c   = e_fx ? ~d_px : d_px;
wire [14:0] d_off = {d_code[8:0], d_row[3], d_c[3:2], d_row[2:0]};
wire [7:0]  spb_d = xevios ? bswap_spr(spb_q) : spb_q;

// draw pipeline: ROM address, ROM data -> lookup address, lookup -> line buffer
reg  [3:0] p_v;
reg  [9:0] p_x[4];
reg  [1:0] p_c[2];
reg        p_hi[2];
reg        p_none[2];

always @(posedge clk) begin
    lb_eng_wr <= 1'b0;

    p_v    <= {p_v[2:0], 1'b0};
    p_x[1] <= p_x[0]; p_x[2] <= p_x[1]; p_x[3] <= p_x[2];
    p_c[1] <= p_c[0]; p_hi[1] <= p_hi[0]; p_none[1] <= p_none[0];

    // spritelayout_xevious: planes {plane-2 half + 4, 0, 4}; plane 2 for codes 80-FF is the high nibble of the stored
    // byte (MAME init_xevious), codes 100-13F have none
    if (p_v[1]) spl_addr <= {r_color[5:0], p_none[1] ? 1'b0 : spb_d[(p_hi[1] ? 3'd7 : 3'd3) - {1'b0, p_c[1]}],
                             spa_q[3'd7 - {1'b0, p_c[1]}], spa_q[3'd3 - {1'b0, p_c[1]}]};

    // lookup bit 7 clear = transparent
    if (p_v[3] && spl_hi[3] && p_x[3] < 10'd288) begin
        lb_eng_addr <= {tgt_buf, p_x[3][8:0]};
        lb_eng_data <= {1'b1, spl_hi[2:0], spl_lo[3:0]};
        lb_eng_wr   <= 1'b1;
    end

    if (line_step) begin
        tgt_y   <= crt_flip ? 9'd238 - vcnt : vcnt - 9'd15;
        tgt_buf <= ~vcnt[0];
        s_num   <= 6'd0;
        f_cnt   <= 2'd0;
        st      <= S_FETCH;
    end
    else case (st)
        S_FETCH: begin
            f_cnt <= f_cnt + 2'd1;
            case (f_cnt)
                2'd0: spr_addr <= {4'b1111, s_num, 1'b0};
                2'd1: spr_addr <= {4'b1111, s_num, 1'b1};
                2'd2: begin r_code <= sr3_q; r_y <= sr1_q; r_flags <= sr2_q; end
                2'd3: begin
                    r_color <= sr3_q; r_x <= sr1_q; r_xmsb <= sr2_q;
                    t_idx   <= 2'd0;
                    st      <= sr3_q[6] ? S_NEXT : S_TILE;
                end
            endcase
        end
        S_TILE: begin
            d_code <= e_base + {7'd0, tc};
            d_x    <= e_sx + (tx ? 10'd16 : 10'd0);
            d_row  <= e_fy ? ~e_dy[3:0] : e_dy[3:0];
            d_px   <= 4'd0;
            if (e_hit) st <= S_DRAW;
            else if (t_idx == 2'd3) st <= S_NEXT;
            else t_idx <= t_idx + 2'd1;
        end
        S_DRAW: begin
            spa_addr  <= d_off;
            spb_addr  <= d_off[12:0];
            p_v[0]    <= 1'b1;
            p_c[0]    <= d_c[1:0];
            p_hi[0]   <= d_off[13];
            p_none[0] <= d_off[14];
            p_x[0]    <= d_x + {6'd0, d_px};
            d_px      <= d_px + 4'd1;
            if (d_px == 4'd15) begin
                if (t_idx == 2'd3) st <= S_NEXT;
                else begin t_idx <= t_idx + 2'd1; st <= S_TILE; end
            end
        end
        S_NEXT: begin
            f_cnt <= 2'd0;
            if (s_num == 6'd63) st <= S_IDLE;
            else begin
                s_num <= s_num + 6'd1;
                st    <= S_FETCH;
            end
        end
        default: ;
    endcase
end

endmodule
