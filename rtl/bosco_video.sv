//============================================================================
//
//  Bosconian video: scrolling playfield, radar panel, 6 sprites, radar dots,
//  05xx starfield
//
//  Per MAME bosco.cpp (Nicola Salmoria). MAME's Bosconian screen is y 16-239,
//  i.e. y = V counter; x 0-287 as the Galaga boards. Composition at picture
//  position c: dots on top; c >= 224 the radar tiles; c < 224 the playfield
//  (lookup F transparent) over the sprites over the stars. The hardware skips
//  H 221-223, so the screen shows c = x for x < 221, c = x + 3 for 221-284
//  and black from 285.
//
//============================================================================

module bosco_video
(
    input               clk,            // 49.152 MHz
    input         [2:0] sub,            // fabric clock within the pixel; ce6 when sub == 7
    input               ce6,
    input         [8:0] hcnt,
    input         [8:0] vcnt,
    input               line_step,

    input         [7:0] scroll_x,       // 9810
    input         [7:0] scroll_y,       // 9820
    input         [5:0] star_ctl,       // 9830: X speed, Y speed
    input               star_en,        // after the first STARCLR write
    input         [1:0] star_sets,      // video latch Q4, Q5
    input               flip,           // video latch Q0 inverted (MAME): game flip
    input               crt_flip,

    // video RAM 8000-8FFF: 000 radar codes, 400 playfield codes, 800 radar attributes, C00 playfield attributes
    output reg   [11:0] vram_addr,
    input         [7:0] vram_q,

    // sprite and dot registers (copies of video RAM 3D4-3DF / BD4-BDF and 3F0-3FF / BF0-BFF) and 9800-980F
    input        [95:0] spr_a,          // 12 bytes at 3D4: {code / flips} x even, {x} x odd
    input        [95:0] spr_b,          // 12 bytes at BD4: {y} x even, {colour} x odd
    input       [127:0] dot_x,          // 16 bytes at 3F0
    input       [127:0] dot_y,          // 16 bytes at BF0
    input       [127:0] dot_attr,       // 16 bytes at 9800

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

wire [8:0] px0   = (hcnt >= 9'h0F0) ? hcnt - 9'h0F0 : hcnt + 9'd144;
wire [8:0] px    = crt_flip ? 9'd287 - px0 : px0;
wire [7:0] my    = crt_flip ? 8'd255 - vcnt[7:0] : vcnt[7:0];    // MAME y (16-239)
wire       h_vis = (hcnt >= 9'h0F0) || (hcnt < 9'h090);
wire       v_vis = (vcnt >= 9'd16) && (vcnt < 9'd240);
// composed picture position: upright, H 221-223 are skipped (radar moves 3 left); flipped, the radar is at the left
// and moves 3 right
wire [8:0] cx    = flip ? ((px < 9'd67) ? px - 9'd3 : px) : ((px < 9'd221) ? px : px + 9'd3);
wire       blank = flip ? px < 9'd3 : px >= 9'd285;
// tile layers flip with the screen (MAME tilemap flip): fetch at the mirrored position
wire [8:0] tx    = flip ? 9'd287 - cx : cx;
wire [7:0] ty    = flip ? 8'd255 - my : my;

//------------------------------------------------------- ROMs / PROMs --------------------------------------------------------//

reg  [11:0] chr_addr;
wire  [7:0] chr_q;
dpram_dc #(.widthad_a(12)) chr_rom
(
    .clock_a(clk), .address_a(chr_addr), .data_a(8'h00), .wren_a(1'b0), .q_a(chr_q),
    .clock_b(clk), .address_b(ioctl_addr[11:0]), .data_b(ioctl_dout), .wren_b(gfx1_wr && ioctl_addr[12] == 1'b0), .q_b()
);

reg  [11:0] spr_rom_addr;
wire  [7:0] spr_rom_q;
dpram_dc #(.widthad_a(12)) spr_rom
(
    .clock_a(clk), .address_a(spr_rom_addr), .data_a(8'h00), .wren_a(1'b0), .q_a(spr_rom_q),
    .clock_b(clk), .address_b(ioctl_addr[11:0]), .data_b(ioctl_dout), .wren_b(gfx2_wr && ioctl_addr[13:12] == 2'd0), .q_b()
);

reg   [7:0] dot_rom_addr;
wire  [7:0] dot_rom_q;
dpram_dc #(.widthad_a(8)) dot_rom
(
    .clock_a(clk), .address_a(dot_rom_addr), .data_a(8'h00), .wren_a(1'b0), .q_a(dot_rom_q),
    .clock_b(clk), .address_b(ioctl_addr[7:0]), .data_b(ioctl_dout), .wren_b(gfx3_wr && ioctl_addr[16:8] == 9'h180), .q_b()
);

// "proms": 000 palette, 020 lookup (characters | 10, sprites as is)
reg   [9:0] pix_prom_addr;
wire  [7:0] pix_prom_q;
dpram_dc #(.widthad_a(10)) pix_prom
(
    .clock_a(clk), .address_a(pix_prom_addr), .data_a(8'h00), .wren_a(1'b0), .q_a(pix_prom_q),
    .clock_b(clk), .address_b(ioctl_addr[9:0]), .data_b(ioctl_dout), .wren_b(prom_wr && ioctl_addr[11:10] == 2'b00), .q_b()
);

reg   [9:0] spr_prom_addr;
wire  [7:0] spr_prom_q;
dpram_dc #(.widthad_a(10)) spr_prom
(
    .clock_a(clk), .address_a(spr_prom_addr), .data_a(8'h00), .wren_a(1'b0), .q_a(spr_prom_q),
    .clock_b(clk), .address_b(ioctl_addr[9:0]), .data_b(ioctl_dout), .wren_b(prom_wr && ioctl_addr[11:10] == 2'b00), .q_b()
);

//------------------------------------------------------- Line buffers --------------------------------------------------------//

// two lines of 512 each: sprites {opaque, 3'b0, pen (4)}, dots {opaque, 5'b0, pen (2)}; the pixel path reads and
// clears one line while the engine fills the other
reg   [9:0] lb_disp_addr;
reg         lb_disp_clr;
wire  [7:0] lbs_q, lbd_q;
reg   [9:0] lbs_addr, lbd_addr;
reg   [7:0] lbs_data, lbd_data;
reg         lbs_wr, lbd_wr;

dpram_dc #(.widthad_a(10)) spr_line
(
    .clock_a(clk), .address_a(lb_disp_addr), .data_a(8'h00), .wren_a(lb_disp_clr), .q_a(lbs_q),
    .clock_b(clk), .address_b(lbs_addr), .data_b(lbs_data), .wren_b(lbs_wr), .q_b()
);

dpram_dc #(.widthad_a(10)) dot_line
(
    .clock_a(clk), .address_a(lb_disp_addr), .data_a(8'h00), .wren_a(lb_disp_clr), .q_a(lbd_q),
    .clock_b(clk), .address_b(lbd_addr), .data_b(lbd_data), .wren_b(lbd_wr), .q_b()
);

//------------------------------------------------------- Starfield -----------------------------------------------------------//

// window x 0-255 of the visible lines, shown at picture x < 224 (i.e. screen x < 221)
wire       star_hit;
wire [5:0] star_col;

namco_05xx stars
(
    .clk(clk),
    .ce6(ce6),
    .line_step(line_step),
    .vcnt(vcnt),
    .win(v_vis && px0 < 9'd256),
    .speed_x(star_ctl[2:0]),
    .speed_y(star_ctl[5:3]),
    .set_a({1'b0, star_sets[0]}),
    .set_b({1'b1, star_sets[1]}),
    .enable(star_en),
    .star(star_hit),
    .color(star_col)
);

//------------------------------------------------------- Tiles + pixel path --------------------------------------------------//

// playfield at c < 224: source = (c + scroll_x, y + scroll_y), 32 x 32 scan rows, codes at 400, attributes at C00.
// radar at c >= 224: column (c / 8) & 7, row y / 8, codes at 000, attributes at 800. Attribute: colour 5-0,
// bit 6 clear = flip x (MAME TILE_FLIPYX(attr >> 6) ^ TILE_FLIPX), bit 7 = flip y.
wire       is_pf  = tx < 9'd224;
wire [7:0] sx     = tx[7:0] + scroll_x;
wire [7:0] sy     = ty + scroll_y;
wire [9:0] t_idx  = is_pf ? {sy[7:3], sx[7:3]} : {ty[7:3], 2'b00, tx[5:3]};
wire [2:0] t_xin  = is_pf ? sx[2:0] : tx[2:0];
wire [2:0] t_yin  = is_pf ? sy[2:0] : ty[2:0];

reg  [2:0] t_x, t_y;
reg        t_pf;
reg  [7:0] t_code;
reg  [5:0] t_color;
reg  [1:0] t_pix;
reg  [7:0] s_entry, s_entry_b, d_entry, d_entry_b;
reg  [9:0] t_idx_d;
reg        vis_a, vis_b, pf_a, pf_b, blank_a, blank_b;
reg        st_a, st_b;
reg  [5:0] st_col_a, st_col_b;

always @(posedge clk) begin
    lb_disp_clr <= 1'b0;
    case (sub)
        3'd0: begin
            vram_addr    <= {1'b0, is_pf, t_idx};
            lb_disp_addr <= {vcnt[0], cx};
            t_x          <= t_xin;
            t_y          <= t_yin;
            t_pf         <= is_pf;
            vis_a        <= h_vis & v_vis;
            blank_a      <= blank;
            st_a         <= star_hit && !flip && cx < 9'd224 && px < 9'd221;
            st_col_a     <= star_col;
        end
        3'd1: vram_addr <= {1'b1, t_pf, t_idx_d};
        3'd2: begin
            t_code  <= vram_q;
            s_entry <= lbs_q;
            d_entry <= lbd_q;
            lb_disp_clr <= vis_a;
        end
        3'd3: begin
            // charlayout_2bpp: x 0-3 in bytes 8-15, x 4-7 in bytes 0-7
            t_color  <= vram_q[5:0];
            chr_addr <= {t_code, ~(t_x[2] ^ ~vram_q[6]), t_y ^ {3{vram_q[7]}}};
            t_x      <= t_x ^ {3{~vram_q[6]}};
        end
        3'd5: t_pix <= {chr_q[3'd7 - {1'b0, t_x[1:0]}], chr_q[3'd3 - {1'b0, t_x[1:0]}]};
        3'd7: begin
            vis_b     <= vis_a;
            pf_b      <= t_pf;
            blank_b   <= blank_a;
            s_entry_b <= s_entry;
            d_entry_b <= d_entry;
            st_b      <= st_a;
            st_col_b  <= st_col_a;
        end
        default: ;
    endcase
end

always @(posedge clk) if (sub == 3'd0) t_idx_d <= t_idx;

reg  [4:0] pen;
reg        pen_none;
always @(posedge clk) begin
    case (sub)
        3'd6: pix_prom_addr <= 10'h020 + {2'b00, t_color, t_pix};
        3'd0: begin
            pen_none <= 1'b0;
            if (d_entry_b[7])                         pen <= 5'd31 - {3'd0, d_entry_b[1:0]};   // dot
            else if (pix_prom_q[3:0] != 4'hF)         pen <= {1'b1, pix_prom_q[3:0]};          // playfield / radar
            else if (pf_b && s_entry_b[7])            pen <= {1'b0, s_entry_b[3:0]};           // sprite
            else begin                                pen <= 5'h1F; pen_none <= 1'b1; end
        end
        3'd1: pix_prom_addr <= {5'd0, pen};
        default: ;
    endcase
end

function [7:0] lvl_star(input [1:0] v);
    case (v)
        2'd0: lvl_star = 8'd0; 2'd1: lvl_star = 8'd71; 2'd2: lvl_star = 8'd151; 2'd3: lvl_star = 8'd222;
    endcase
endfunction

function [7:0] lvl3(input [2:0] v);
    case (v)
        3'd0: lvl3 = 8'd0;   3'd1: lvl3 = 8'd33;  3'd2: lvl3 = 8'd71;  3'd3: lvl3 = 8'd104;
        3'd4: lvl3 = 8'd151; 3'd5: lvl3 = 8'd184; 3'd6: lvl3 = 8'd222; 3'd7: lvl3 = 8'd255;
    endcase
endfunction

function [7:0] lvl2(input [1:0] v);
    case (v)
        2'd0: lvl2 = 8'd0; 2'd1: lvl2 = 8'd81; 2'd2: lvl2 = 8'd174; 2'd3: lvl2 = 8'd255;
    endcase
endfunction

reg black, star;
always @(posedge clk) begin
    if (sub == 3'd3) begin
        black <= ~vis_b | blank_b | (pen_none & ~st_b);
        star  <= pen_none & st_b;
    end
    if (ce6) begin
        red   <= black ? 8'd0 : star ? lvl_star(st_col_b[1:0]) : lvl3(pix_prom_q[2:0]);
        green <= black ? 8'd0 : star ? lvl_star(st_col_b[3:2]) : lvl3(pix_prom_q[5:3]);
        blue  <= black ? 8'd0 : star ? lvl2(st_col_b[5:4])     : lvl2(pix_prom_q[7:6]);
    end
end

//------------------------------------------------------- Sprites + dots ------------------------------------------------------//

// During each line the engine prepares the next one (picture coordinates). Sprites (MAME draw_sprites): 6 entries,
// x = a[2n+1] - 2, y = 240 - b[2n], code = a[2n] >> 2, flips a[2n] bits 0 / 1, colour b[2n+1] & 3F, clipped to c < 224.
// Dots (draw_bullets): entries 4-15, x = dot_x + 256 * ~attr0 - 2, y = 251 - dot_y, shape (attr 3-1) ^ 7, drawn
// flipped both ways, pens 0-3 opaque (palette 31 - pen). Sprites first, then dots.
localparam E_IDLE = 3'd0, E_SPR = 3'd1, E_SDRAW = 3'd2, E_DOT = 3'd3, E_DDRAW = 3'd4;

reg  [2:0] est = E_IDLE;
reg  [3:0] e_n;
reg  [7:0] tgt_y;
reg        tgt_buf;
reg  [3:0] d_px;
reg  [9:0] d_x;
reg  [3:0] d_row;
reg  [5:0] d_code;
reg  [5:0] d_color, d_color_p;
reg        d_fx;

wire [7:0] sa0 = spr_a[e_n*16 +: 8];
wire [7:0] sa1 = spr_a[e_n*16 + 8 +: 8];
wire [7:0] sb0 = spr_b[e_n*16 +: 8];
wire [7:0] sb1 = spr_b[e_n*16 + 8 +: 8];
wire [7:0] s_y = 8'd240 - sb0;
wire [7:0] s_dy = tgt_y - s_y;

wire [7:0] dx8  = dot_x[e_n*8 +: 8];
wire [7:0] dy8  = dot_y[e_n*8 +: 8];
wire [7:0] da   = dot_attr[e_n*8 +: 8];
wire [7:0] d_y  = 8'd251 - dy8 + (flip ? 8'd2 : 8'd0);
wire [7:0] d_dy = tgt_y - d_y;

// sprite pipeline: ROM address -> data (2 clocks) -> lookup address -> lookup (2 clocks) -> line buffer
reg  [3:0] p_v;
reg  [9:0] p_x[4];
reg  [1:0] p_c[2];
// dot pipeline: ROM address -> data (2 clocks) -> line buffer
reg  [1:0] q_v;
reg  [9:0] q_x[2];

wire [3:0] scol = d_fx ? ~d_px : d_px;
// spritelayout_bosco: x 0-3 / 4-7 / 8-11 / 12-15 in bytes 8 / 16 / 24 / 0, rows 8-15 at +32
wire [1:0] sgrp = scol[3:2] + 2'd1;

always @(posedge clk) begin
    lbs_wr <= 1'b0;
    lbd_wr <= 1'b0;
    p_v <= {p_v[2:0], 1'b0};
    p_x[1] <= p_x[0]; p_x[2] <= p_x[1]; p_x[3] <= p_x[2];
    p_c[1] <= p_c[0];
    q_v <= {q_v[0], 1'b0};
    q_x[1] <= q_x[0];

    if (p_v[1]) spr_prom_addr <= 10'h020 + {2'b00, d_color_p, spr_rom_q[3'd7 - {1'b0, p_c[1]}], spr_rom_q[3'd3 - {1'b0, p_c[1]}]};
    if (p_v[3] && spr_prom_q[3:0] != 4'hF && (flip ? (p_x[3] >= 10'd64 && p_x[3] < 10'd288) : p_x[3] < 10'd224)) begin
        lbs_addr <= {tgt_buf, p_x[3][8:0]};
        lbs_data <= {1'b1, 3'b000, spr_prom_q[3:0]};
        lbs_wr   <= 1'b1;
    end

    // dots: pen = bits 2-0 of the shape byte (planes at bit offsets 5, 6, 7); pens 4-7 transparent
    if (q_v[1] && !dot_rom_q[2] && q_x[1] < 10'd288) begin
        lbd_addr <= {tgt_buf, q_x[1][8:0]};
        lbd_data <= {1'b1, 5'b00000, dot_rom_q[1:0]};
        lbd_wr   <= 1'b1;
    end

    if (line_step) begin
        tgt_y   <= crt_flip ? 8'd255 - (vcnt[7:0] + 8'd1) : vcnt[7:0] + 8'd1;
        tgt_buf <= ~vcnt[0];
        e_n     <= 4'd0;
        est     <= E_SPR;
    end
    else case (est)
        E_SPR: begin
            d_x     <= {2'b00, sa1} - 10'd2 + (flip ? 10'd31 : 10'd0);
            d_row   <= sa0[1] ? ~s_dy[3:0] : s_dy[3:0];
            d_code  <= sa0[7:2];
            d_color <= sb1[5:0];
            d_fx    <= sa0[0];
            d_px    <= 4'd0;
            if (s_dy < 8'd16) est <= E_SDRAW;
            else if (e_n == 4'd5) begin e_n <= 4'd4; est <= E_DOT; end
            else e_n <= e_n + 4'd1;
        end
        E_SDRAW: begin
            spr_rom_addr <= {d_code, d_row[3], sgrp, d_row[2:0]};
            d_color_p <= d_color;
            p_v[0] <= 1'b1;
            p_c[0] <= scol[1:0];
            p_x[0] <= d_x + {6'd0, d_px};
            d_px   <= d_px + 4'd1;
            if (d_px == 4'd15) begin
                if (e_n == 4'd5) begin e_n <= 4'd4; est <= E_DOT; end
                else begin e_n <= e_n + 4'd1; est <= E_SPR; end
            end
        end
        E_DOT: begin
            // dotlayout: 16 bytes per shape, byte = row * 4 + column; drawn flipped both ways
            d_x    <= {1'b0, ~da[0], dx8} - (flip ? 10'd3 : 10'd2);
            d_row  <= {2'b00, d_dy[1:0] ^ {2{~flip}}};
            d_code <= {3'b000, da[3:1] ^ 3'd7};
            d_px   <= 4'd0;
            if (d_dy < 8'd4) est <= E_DDRAW;
            else if (e_n == 4'd15) est <= E_IDLE;
            else e_n <= e_n + 4'd1;
        end
        E_DDRAW: begin
            dot_rom_addr <= {1'b0, d_code[2:0], d_row[1:0], d_px[1:0] ^ {2{~flip}}};
            q_v[0] <= 1'b1;
            q_x[0] <= d_x + {6'd0, d_px};
            d_px   <= d_px + 4'd1;
            if (d_px == 4'd3) begin
                if (e_n == 4'd15) est <= E_IDLE;
                else begin e_n <= e_n + 4'd1; est <= E_DOT; end
            end
        end
        default: ;
    endcase
end

endmodule
