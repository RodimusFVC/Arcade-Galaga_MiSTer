//============================================================================
//
//  Galaga video: timing, 36 x 28 character layer, 64 sprites, palette
//
//  Tile / sprite geometry and colour lookups per MAME galaga_v.cpp
//  (Nicola Salmoria); counters after Dar's (darfpga) Galaga core.
//  Coordinates below are MAME's raw (unrotated) screen: x 0-287, y 0-223.
//
//============================================================================

module galaga_video
(
    input               clk,            // 49.152 MHz
    input         [2:0] sub,            // fabric clock within the pixel; ce6 when sub == 7
    input               ce6,
    input               flip,           // video latch Q7
    input               crt_flip,       // OSD: mirror the picture both ways (stars keep raster order)
    input         [5:0] star_ctl,       // video latch Q0-Q5: 05xx X speed, set select, STARCLR

    output reg    [8:0] hcnt = 9'h080,
    output reg    [8:0] vcnt = 9'd0,
    output              line_step,      // last clock of a line (vcnt advances)

    // tile RAM (8000-87FF) and sprite registers (8B80 / 9380 / 9B80), read ports
    output reg   [10:0] vram_addr,
    input         [7:0] vram_q,
    output reg    [9:0] spr_addr,
    input         [7:0] spr1_q,
    input         [7:0] spr2_q,
    input         [7:0] spr3_q,

    // ROM / PROM load (ioctl index 0)
    input        [24:0] ioctl_addr,
    input         [7:0] ioctl_dout,
    input               gfx1_wr,
    input               gfx2_wr,
    input               prom_wr,

    output reg    [7:0] red = 8'd0,
    output reg    [7:0] green = 8'd0,
    output reg    [7:0] blue = 8'd0,
    output reg          hblank = 1'b1,
    output reg          vblank = 1'b1,
    output reg          hsync = 1'b1,
    output reg          vsync = 1'b1
);

//------------------------------------------------------- Counters ------------------------------------------------------------//

// H 080-1FF (384 per line), V 000-107 (264 lines); 6.144 MHz / 384 / 264 = 60.61 Hz
assign line_step = ce6 & (hcnt == 9'h0BF);

always @(posedge clk) begin
    if (ce6) begin
        hcnt <= (hcnt == 9'h1FF) ? 9'h080 : hcnt + 9'd1;
        if (hcnt == 9'h0BF) vcnt <= (vcnt == 9'd263) ? 9'd0 : vcnt + 9'd1;
    end
end

// raw-screen position of the current pixel: x 0 at H 0F0 (0F0-1FF, then 080-08F); y 0 at V 010
wire [8:0] px = (hcnt >= 9'h0F0) ? hcnt - 9'h0F0 : hcnt + 9'd144;
wire [8:0] py = vcnt - 9'd16;
wire       h_vis = (hcnt >= 9'h0F0) || (hcnt < 9'h090);

// picture position fetched for the current pixel
wire [8:0] fpx = crt_flip ? 9'd287 - px : px;
wire [8:0] fpy = crt_flip ? 9'd223 - py : py;
wire       v_vis = (vcnt >= 9'd16) && (vcnt < 9'd240);

//------------------------------------------------------- ROMs / PROMs --------------------------------------------------------//

reg  [11:0] chr_addr;
wire  [7:0] chr_q;
dpram_dc #(.widthad_a(12)) chr_rom
(
    .clock_a(clk), .address_a(chr_addr), .data_a(8'h00), .wren_a(1'b0), .q_a(chr_q),
    .clock_b(clk), .address_b(ioctl_addr[11:0]), .data_b(ioctl_dout), .wren_b(gfx1_wr & ~ioctl_addr[12]), .q_b()
);

reg  [12:0] spr_rom_addr;
wire  [7:0] spr_rom_q;
dpram_dc #(.widthad_a(13)) spr_rom
(
    .clock_a(clk), .address_a(spr_rom_addr), .data_a(8'h00), .wren_a(1'b0), .q_a(spr_rom_q),
    .clock_b(clk), .address_b(ioctl_addr[12:0]), .data_b(ioctl_dout), .wren_b(gfx2_wr & ~ioctl_addr[13]), .q_b()
);

// "proms": 000 palette, 020 character lookup, 120 sprite lookup. One copy for the pixel path, one for the sprite engine
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

//------------------------------------------------------- Sprite line buffer --------------------------------------------------//

// two lines of 512: entry = {opaque, 3'b0, pen}; the pixel path reads and clears one while the engine fills the other
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

//------------------------------------------------------- 05xx starfield ------------------------------------------------------//

// 16-bit Fibonacci LFSR (taps 16, 13, 11, 6), stepped once per pixel over x 16-271 of the 224 visible lines; the rest
// of each frame's 65536 + offset steps run at fabric speed in vertical blank (MAME starfield_05xx.cpp)
reg  [15:0] lfsr = 16'h7FFF;
reg  [12:0] bulk = 13'd0;
reg         star_en = 1'b0;
reg   [1:0] star_set_a, star_set_b;
wire [15:0] lfsr_next = {lfsr[0] ^ lfsr[3] ^ lfsr[5] ^ lfsr[10], lfsr[15:1]};
wire        star_win  = v_vis && px >= 9'd16 && px < 9'd272;
wire        star_hit  = ((lfsr & 16'hFA14) == 16'h7800) && ({lfsr[10], lfsr[8]} == star_set_a || {lfsr[10], lfsr[8]} == star_set_b);
wire  [5:0] star_col  = ~{lfsr[4], lfsr[1], lfsr[0], lfsr[7], lfsr[6], lfsr[5]};   // BBGGRR

// X speed: extra (+) or skipped (-) steps per frame, indexed by Q2-Q0
function [2:0] x_steps(input [2:0] q);       // 4 + offset
    case (q)
        3'd0: x_steps = 3'd4; 3'd1: x_steps = 3'd5; 3'd2: x_steps = 3'd6; 3'd3: x_steps = 3'd7;
        3'd4: x_steps = 3'd0; 3'd5: x_steps = 3'd1; 3'd6: x_steps = 3'd2; 3'd7: x_steps = 3'd3;
    endcase
endfunction

always @(posedge clk) begin
    if (line_step && vcnt == 9'd15) begin                  // vblank ends: MAME screen_vblank_galaga
        star_en    <= star_ctl[5];
        star_set_a <= {1'b0, star_ctl[3]};
        star_set_b <= {1'b1, star_ctl[4]};
        if (!star_ctl[5]) lfsr <= 16'h7FFF;
        else bulk <= {10'd0, x_steps(star_ctl[2:0])};
    end
    else if (line_step && vcnt == 9'd239) begin            // post-visible 10 lines + next frame's pre-visible 22, less 4
        if (star_en) bulk <= 13'd8188;
    end
    else if (bulk != 13'd0) begin
        bulk <= bulk - 13'd1;
        lfsr <= lfsr_next;
    end
    else if (ce6 && star_en && star_win) lfsr <= lfsr_next;
end

//------------------------------------------------------- Character layer + pixel path -----------------------------------------//

// Two-pixel pipeline: the pixel at hcnt is fetched during its own pixel period (sub 0-7) and coloured during the next,
// so RGB, blanking and syncs all leave two pixels after the counters.

// tilemap_scan: row += 2, col -= 2; cols 0-1 and 34-35 come from the side columns
wire [5:0] t_col  = fpx[8:3] - 6'd2;
wire [4:0] t_row  = fpy[7:3] + 5'd2;
wire [9:0] t_offs = t_col[5] ? {t_col[4:0], t_row} : {t_row, t_col[4:0]};

reg  [5:0] t_color;
reg  [2:0] t_x, t_y;
reg  [1:0] t_pix;
reg  [7:0] s_entry;
reg        vis_a, vis_b;
reg  [3:0] c_pen;
reg  [7:0] s_entry_b;
reg        st_a, st_b;
reg  [5:0] st_col_a, st_col_b;

// charlayout_2bpp: 16 bytes per char, x 0-3 in bytes 8-15, x 4-7 in bytes 0-7; plane 0 = bits 7-4, plane 1 = bits 3-0.
// Codes 80-FF (the flipped set, used while the screen is flipped) have the byte halves swapped (MAME init_galaga).
always @(posedge clk) begin
    lb_disp_clr <= 1'b0;
    case (sub)
        3'd0: begin
            vram_addr    <= {1'b0, t_offs};
            lb_disp_addr <= {py[0], fpx};
            t_x          <= fpx[2:0];
            t_y          <= fpy[2:0];
            vis_a        <= h_vis & v_vis;
            st_a         <= star_en & star_win & star_hit;
            st_col_a     <= star_col;
        end
        3'd1: vram_addr <= {1'b1, t_offs};
        3'd2: begin
            chr_addr[11:4] <= {flip, vram_q[6:0]};
            s_entry <= lb_disp_q;
            lb_disp_clr <= vis_a;
        end
        3'd3: begin
            t_color  <= vram_q[5:0];
            chr_addr[3:0] <= {~t_x[2] ^ flip, t_y};
        end
        3'd5: t_pix <= {chr_q[3'd7 - {1'b0, t_x[1:0]}], chr_q[3'd3 - {1'b0, t_x[1:0]}]};
        3'd7: begin                                  // hand over to the colour stage
            vis_b     <= vis_a;
            s_entry_b <= s_entry;
            st_b      <= st_a;
            st_col_b  <= st_col_a;
        end
        default: ;
    endcase
end

// PROM port: sub 6 character lookup for this pixel, sub 1 palette for the previous pixel
reg  [4:0] pen;
always @(posedge clk) begin
    case (sub)
        3'd6: pix_prom_addr <= 10'h020 + {2'b00, t_color, t_pix};
        3'd0: begin
            c_pen <= pix_prom_q[3:0];                       // lookup for the pixel now in the colour stage
            if (pix_prom_q[3:0] != 4'hF)  pen <= {1'b1, pix_prom_q[3:0]};     // characters: palette 10-1F
            else if (s_entry_b[7])        pen <= {1'b0, s_entry_b[3:0]};      // sprites: palette 00-0F
            else                          pen <= 5'h1F;                       // background: star or black
        end
        3'd1: pix_prom_addr <= {5'd0, pen};
        default: ;
    endcase
end

// resistor networks: R/G 1K, 470, 220; B 470, 220 (MAME galaga_palette). Stars drive the 470 / 220 legs only.
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

reg       black, star;
always @(posedge clk) begin
    if (sub == 3'd3) begin
        black <= ~vis_b | (pen == 5'h1F & ~st_b);
        star  <= pen == 5'h1F & st_b;
    end
    if (ce6) begin
        red    <= black ? 8'd0 : star ? lvl_star(st_col_b[1:0]) : lvl3(pix_prom_q[2:0]);
        green  <= black ? 8'd0 : star ? lvl_star(st_col_b[3:2]) : lvl3(pix_prom_q[5:3]);
        blue   <= black ? 8'd0 : star ? lvl2(st_col_b[5:4])     : lvl2(pix_prom_q[7:6]);
    end
end

// blanking and syncs: sampled at the end of the pixel's fetch period, out with its colour one period later
reg hb_d, vb_d, hs_d, vs_d;
always @(posedge clk) begin
    if (ce6) begin
        hb_d   <= ~h_vis;
        vb_d   <= ~v_vis;
        hs_d   <= ~(hcnt >= 9'h0A8 && hcnt < 9'h0C8);      // 24 px front porch, 32 sync, 40 back porch (05xx notes)
        vs_d   <= ~(vcnt >= 9'd248 && vcnt < 9'd256);      // 8 lines front porch, 8 sync, 24 back porch
        hblank <= hb_d;
        vblank <= vb_d;
        hsync  <= hs_d;
        vsync  <= vs_d;
    end
end

//------------------------------------------------------- Sprite engine -------------------------------------------------------//

// During each line the engine draws the NEXT line's sprites into the other half of the line buffer, in MAME's order
// (sprite 0 first, later sprites on top). Registers at 0x380 + 2n: ram1 {code, colour}, ram2 {y, x}, ram3 {flags, x msb}.
localparam S_IDLE = 3'd0, S_FETCH = 3'd1, S_EVAL = 3'd2, S_DRAW = 3'd3, S_NEXT = 3'd4;

reg  [2:0] st = S_IDLE;
reg  [5:0] s_num;
reg  [1:0] f_cnt;
reg  [7:0] r_code, r_color, r_y, r_x, r_flags, r_xmsb;
reg  [8:0] tgt_y;                        // raw-screen line being prepared
reg        tgt_buf;
reg  [5:0] d_px;                         // pixel within the sprite row
reg  [5:0] d_len;
reg  [4:0] d_dy;                         // line within the sprite
reg  [9:0] d_sx;
reg        d_go;

wire       f_flipx = r_flags[0] ^ flip;
wire       f_flipy = r_flags[1] ^ flip;
wire       f_sizex = r_flags[2];
wire       f_sizey = r_flags[3];

// MAME: sx = x - 40 + 256 * (xmsb & 3); sy = ((256 - y + 1 - 16 * sizey) & 0xFF) - 32
wire [9:0] e_sx  = {r_xmsb[1:0], r_x} - 10'd40;
wire [7:0] e_sy8 = 8'd1 - r_y - {3'd0, f_sizey, 4'd0};
wire [8:0] e_dy  = tgt_y + 9'd32 - {1'b0, e_sy8};          // line within the sprite, valid when < height
wire       e_hit = (e_dy < (f_sizey ? 9'd32 : 9'd16));

// draw pipeline (2-clock RAM latency): ROM address, ROM data -> lookup address two clocks later, lookup -> line buffer
reg  [3:0] p_v;
reg  [9:0] p_x[4];
reg  [1:0] p_c[2];

wire [4:0] dcx    = f_flipx ? ~d_px[4:0] : d_px[4:0];       // column in the (up to) 32-wide sprite, after flip
wire [4:0] dcy    = f_flipy ? ~d_dy : d_dy;
wire       code_x = f_sizex ? dcx[4] : 1'b0;
wire       code_y = f_sizey ? dcy[4] : 1'b0;
wire [6:0] d_code = r_code[6:0] + {5'd0, code_y, code_x};
wire [3:0] col    = f_sizex ? dcx[3:0] : (f_flipx ? ~d_px[3:0] : d_px[3:0]);
wire [3:0] row    = f_sizey ? dcy[3:0] : (f_flipy ? ~d_dy[3:0] : d_dy[3:0]);

always @(posedge clk) begin
    lb_eng_wr <= 1'b0;

    p_v    <= {p_v[2:0], 1'b0};
    p_x[1] <= p_x[0]; p_x[2] <= p_x[1]; p_x[3] <= p_x[2];
    p_c[1] <= p_c[0];

    // ROM data valid for the address issued two clocks ago
    if (p_v[1]) spr_prom_addr <= 10'h120 + {2'b00, r_color[5:0], spr_rom_q[3'd7 - {1'b0, p_c[1]}], spr_rom_q[3'd3 - {1'b0, p_c[1]}]};

    // lookup data -> line buffer (pen F is transparent)
    if (p_v[3] && spr_prom_q[3:0] != 4'hF && p_x[3] < 10'd288) begin
        lb_eng_addr <= {tgt_buf, p_x[3][8:0]};
        lb_eng_data <= {4'b1000, spr_prom_q[3:0]};
        lb_eng_wr   <= 1'b1;
    end

    if (line_step) begin
        tgt_y   <= crt_flip ? 9'd238 - vcnt : vcnt - 9'd15;   // picture line for the next display line (vcnt - 15)
        tgt_buf <= ~vcnt[0];                                   // that display line's half of the buffer
        s_num   <= 6'd0;
        f_cnt   <= 2'd0;
        st      <= S_FETCH;
    end
    else case (st)
        S_FETCH: begin
            f_cnt <= f_cnt + 2'd1;
            case (f_cnt)
                2'd0: spr_addr <= {3'b111, s_num, 1'b0};
                2'd1: spr_addr <= {3'b111, s_num, 1'b1};
                2'd2: begin r_code <= spr1_q; r_y <= spr2_q; r_flags <= spr3_q; end
                2'd3: begin r_color <= spr1_q; r_x <= spr2_q; r_xmsb <= spr3_q; st <= S_EVAL; end
            endcase
        end
        S_EVAL: begin
            d_dy  <= e_dy[4:0];
            d_sx  <= e_sx;
            d_px  <= 6'd0;
            d_len <= f_sizex ? 6'd31 : 6'd15;
            st    <= e_hit ? S_DRAW : S_NEXT;
        end
        S_DRAW: begin
            // spritelayout_galaga: 64 bytes per sprite; x 0-3/4-7/8-11/12-15 in bytes 0/8/16/24, y 8-15 at +32
            spr_rom_addr <= {d_code, row[3], col[3:2], row[2:0]};
            p_v[0] <= 1'b1;
            p_c[0] <= col[1:0];
            p_x[0] <= d_sx + {4'd0, d_px};
            d_px  <= d_px + 6'd1;
            if (d_px == d_len) st <= S_NEXT;
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
