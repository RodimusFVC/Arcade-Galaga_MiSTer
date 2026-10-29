//  Based on MAME galaga.cpp, digdug.cpp (Nicola Salmoria, BSD-3-Clause)

module galaga_video
(
    input               clk,
    input         [2:0] sub,
    input               ce6,
    input               pause,
    input               dd,
    input         [7:0] vlatch,
    input               gfx_bank,
    input               crt_flip,
    input  signed [3:0] h_adj,
    input  signed [3:0] v_adj,

    output reg    [8:0] hcnt = 9'h080,
    output reg    [8:0] vcnt = 9'd0,
    output              line_step,

    output reg   [10:0] vram_addr,
    input         [7:0] vram_q,
    output reg    [9:0] spr_addr,
    input         [7:0] spr1_q,
    input         [7:0] spr2_q,
    input         [7:0] spr3_q,

    output       [12:0] chr_rom_a,
    input         [7:0] chr_rom_d,
    output       [13:0] spr_rom_a,
    input         [7:0] spr_rom_d,
    output       [11:0] pfc_rom_a,
    input         [7:0] pfc_rom_d,
    output       [11:0] map_rom_a,
    input         [7:0] map_rom_d,
    output        [9:0] pix_prom_a,
    input         [7:0] pix_prom_d,
    output        [9:0] spr_prom_a,
    input         [7:0] spr_prom_d,

    output ram_pool_pkg::pram_i_t lb_i,
    input  ram_pool_pkg::pram_o_t lb_o,
    output chip_pool_pkg::namco_05xx_i_t star_i,
    input  chip_pool_pkg::namco_05xx_o_t star_o,

    output reg    [7:0] red = 8'd0,
    output reg    [7:0] green = 8'd0,
    output reg    [7:0] blue = 8'd0,
    output reg          hblank = 1'b1,
    output reg          vblank = 1'b1,
    output reg          hsync = 1'b1,
    output reg          vsync = 1'b1
);

wire       flip     = vlatch[7];
wire [5:0] star_ctl = dd ? 6'd0 : vlatch[5:0];
wire [1:0] pf_sel   = vlatch[1:0];
wire       tx_mode  = vlatch[2];
wire       pf_off   = vlatch[3];
wire [1:0] pf_bank  = vlatch[5:4];

assign line_step = ce6 & (hcnt == 9'h0BF);

always @(posedge clk) begin
    if (ce6) begin
        hcnt <= (hcnt == 9'h1FF) ? 9'h080 : hcnt + 9'd1;
        if (hcnt == 9'h0BF) vcnt <= (vcnt == 9'd263) ? 9'd0 : vcnt + 9'd1;
    end
end

wire [8:0] px = (hcnt >= 9'h0F0) ? hcnt - 9'h0F0 : hcnt + 9'd144;
wire [8:0] py = vcnt - 9'd16;
wire       h_vis = (hcnt >= 9'h0F0) || (hcnt < 9'h090);

wire [8:0] fpx = crt_flip ? 9'd287 - px : px;
wire [8:0] fpy = crt_flip ? 9'd223 - py : py;
wire [8:0] tpx = (crt_flip ^ flip) ? 9'd287 - px : px;
wire [8:0] tpy = (crt_flip ^ flip) ? 9'd223 - py : py;
wire       v_vis = (vcnt >= 9'd16) && (vcnt < 9'd240);

reg  [12:0] chr_addr;
wire  [7:0] chr_q;
assign chr_rom_a = chr_addr;
assign chr_q = chr_rom_d;

reg  [13:0] spr_rom_addr;
wire  [7:0] spr_rom_q;
assign spr_rom_a = spr_rom_addr;
assign spr_rom_q = spr_rom_d;

reg  [11:0] pfc_addr;
wire  [7:0] pfc_q;
assign pfc_rom_a = pfc_addr;
assign pfc_q = pfc_rom_d;

reg  [11:0] map_addr;
wire  [7:0] map_q;
assign map_rom_a = map_addr;
assign map_q = map_rom_d;

reg   [9:0] pix_prom_addr;
wire  [7:0] pix_prom_q;
assign pix_prom_a = pix_prom_addr;
assign pix_prom_q = pix_prom_d;

reg   [9:0] spr_prom_addr;
wire  [7:0] spr_prom_q;
assign spr_prom_a = spr_prom_addr;
assign spr_prom_q = spr_prom_d;

reg   [9:0] lb_disp_addr;
reg         lb_disp_clr;
wire  [7:0] lb_disp_q;
reg   [9:0] lb_eng_addr;
reg   [7:0] lb_eng_data;
reg         lb_eng_wr;

assign lb_i.a_addr = {5'd0, lb_disp_addr}; assign lb_i.a_d = 8'h00; assign lb_i.a_we = lb_disp_clr;
assign lb_i.b_addr = {5'd0, lb_eng_addr}; assign lb_i.b_d = lb_eng_data; assign lb_i.b_we = lb_eng_wr;
assign lb_disp_q = lb_o.a_q;

wire       star_win = v_vis && px >= 9'd16 && px < 9'd272;
wire       star_hit;
wire [5:0] star_col;

assign star_i.ce6 = ce6;
assign star_i.line_step = line_step;
assign star_i.vcnt = vcnt;
assign star_i.win = star_win;
assign star_i.speed_x = star_ctl[2:0];
assign star_i.speed_y = 3'd0;
assign star_i.set_a = {1'b0, star_ctl[3]};
assign star_i.set_b = {1'b1, star_ctl[4]};
assign star_i.enable = star_ctl[5];
assign star_hit = star_o.star;
assign star_col = star_o.color;

wire [5:0] t_col  = tpx[8:3] - 6'd2;
wire [4:0] t_row  = tpy[7:3] + 5'd2;
wire [9:0] t_offs = t_col[5] ? {t_col[4:0], t_row} : {t_row, t_col[4:0]};

reg  [2:0] t_x, t_y, pf_x;
reg  [5:0] t_color;
reg  [1:0] t_pix, pf_pix;
reg  [7:0] fg_code;
reg        fg_bit;
reg  [7:0] s_entry;
reg        vis_a, vis_b;
reg  [7:0] s_entry_b;
reg        st_a, st_b;
reg  [5:0] st_col_a, st_col_b;
reg  [3:0] fg_col_b;
reg        fg_bit_b;

wire [3:0] dd_fg_color = tx_mode ? fg_code[3:0] : {fg_code[7], fg_code[6], fg_code[5] | fg_code[4], 1'b0};

always @(posedge clk) begin
    lb_disp_clr <= 1'b0;
    case (sub)
        3'd0: begin
            vram_addr    <= {1'b0, t_offs};
            map_addr     <= {pf_sel, t_offs};
            lb_disp_addr <= {py[0], fpx};
            t_x          <= tpx[2:0] ^ {3{flip}};
            pf_x         <= tpx[2:0];
            t_y          <= tpy[2:0];
            vis_a        <= h_vis & v_vis;
            st_a         <= star_hit;
            st_col_a     <= star_col;
        end
        3'd1: vram_addr <= {1'b1, t_offs};
        3'd2: begin
            fg_code <= vram_q;
            if (dd) chr_addr <= {2'b00, flip, vram_q[6:0], t_y};
            else    chr_addr[12:4] <= {gfx_bank, flip, vram_q[6:0]};
            pfc_addr <= {map_q, ~pf_x[2], t_y};
            s_entry <= lb_disp_q;
            lb_disp_clr <= vis_a;
        end
        3'd3: begin
            t_color <= dd ? (pf_off ? {pf_bank, 4'hF} : {pf_bank, map_q[7:4]}) : vram_q[5:0];
            if (!dd) chr_addr[3:0] <= {~t_x[2] ^ flip, t_y};
        end
        3'd5: begin
            t_pix  <= {chr_q[3'd7 - {1'b0, t_x[1:0]}], chr_q[3'd3 - {1'b0, t_x[1:0]}]};
            pf_pix <= {pfc_q[3'd7 - {1'b0, pf_x[1:0]}], pfc_q[3'd3 - {1'b0, pf_x[1:0]}]};
        end
        3'd6: fg_bit <= chr_q[t_x];
        3'd7: begin
            vis_b     <= vis_a;
            s_entry_b <= s_entry;
            st_b      <= st_a;
            st_col_b  <= st_col_a;
            fg_col_b  <= dd_fg_color;
            fg_bit_b  <= fg_bit;
        end
        default: ;
    endcase
end

reg  [4:0] pen;
reg        pen_none;
always @(posedge clk) begin
    case (sub)
        3'd6: pix_prom_addr <= dd ? 10'h120 + {2'b00, t_color, pf_pix} : 10'h020 + {2'b00, t_color, t_pix};
        3'd0: begin
            pen_none <= 1'b0;
            if (dd) begin
                if (s_entry_b[7])     pen <= s_entry_b[4:0];
                else if (fg_bit_b)    pen <= {1'b0, fg_col_b};
                else                  pen <= {1'b0, pix_prom_q[3:0]};
            end
            else begin
                if (pix_prom_q[3:0] != 4'hF)  pen <= {1'b1, pix_prom_q[3:0]};
                else if (s_entry_b[7])        pen <= s_entry_b[4:0];
                else begin                    pen <= 5'h1F; pen_none <= 1'b1; end
            end
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

reg       black, star;
always @(posedge clk) begin
    if (sub == 3'd3) begin
        black <= ~vis_b | (pen_none & ~st_b);
        star  <= pen_none & st_b;
    end
    if (ce6) begin
        red    <= black ? 8'd0 : star ? lvl_star(st_col_b[1:0]) : lvl3(pix_prom_q[2:0]);
        green  <= black ? 8'd0 : star ? lvl_star(st_col_b[3:2]) : lvl3(pix_prom_q[5:3]);
        blue   <= black ? 8'd0 : star ? lvl2(st_col_b[5:4])     : lvl2(pix_prom_q[7:6]);
    end
end

reg hb_d, vb_d, hs_d, vs_d;
wire [8:0] hs_on = 9'h0A8 + {{4{h_adj[3]}}, h_adj, 1'b0};
wire [8:0] vs_on = 9'd248 + {{5{v_adj[3]}}, v_adj};
always @(posedge clk) begin
    if (ce6) begin
        hb_d   <= ~h_vis;
        vb_d   <= ~v_vis;
        hs_d   <= ~(hcnt >= hs_on && hcnt < hs_on + 9'd32);
        vs_d   <= ~(vcnt >= vs_on && vcnt < vs_on + 9'd8);
        hblank <= hb_d;
        vblank <= vb_d;
        hsync  <= hs_d;
        vsync  <= vs_d;
    end
end

localparam S_IDLE = 3'd0, S_FETCH = 3'd1, S_EVAL = 3'd2, S_DRAW = 3'd3, S_NEXT = 3'd4;

reg  [2:0] st = S_IDLE;
reg  [5:0] s_num;
reg  [1:0] f_cnt;
reg  [7:0] r_code, r_color, r_y, r_x, r_flags, r_xmsb;
reg  [8:0] tgt_y;
reg        tgt_buf;
reg  [5:0] d_px;
reg  [5:0] d_len;
reg  [4:0] d_dy;
reg  [9:0] d_sx;
reg        d_go;

wire       f_flipx = r_flags[0] ^ flip;
wire       f_flipy = r_flags[1] ^ flip;
wire       f_sizex = dd ? r_code[7] : r_flags[2];
wire       f_sizey = dd ? r_code[7] : r_flags[3];

wire [7:0] e_code = dd ? (r_code[7] ? {r_code[7] | r_code[5], r_code[6] | r_code[4], r_code[3:0], 2'b00} : r_code)
                       : {1'b0, r_code[6:0]};

wire [9:0] e_sx  = dd ? {2'b00, r_x} - 10'd39 : {r_xmsb[1:0], r_x} - 10'd40;
wire [7:0] e_sy8 = 8'd1 - r_y - {3'd0, f_sizey, 4'd0};
wire [8:0] e_dy  = tgt_y + 9'd32 - {1'b0, e_sy8};
wire       e_hit = (e_dy < (f_sizey ? 9'd32 : 9'd16));

reg  [3:0] p_v;
reg  [9:0] p_x[4];
reg  [1:0] p_c[2];

wire [4:0] dcx    = f_flipx ? ~d_px[4:0] : d_px[4:0];
wire [4:0] dcy    = f_flipy ? ~d_dy : d_dy;
wire       code_x = f_sizex ? dcx[4] : 1'b0;
wire       code_y = f_sizey ? dcy[4] : 1'b0;
reg  [7:0] d_code0;
wire [7:0] d_code = d_code0 + {6'd0, code_y, code_x};

wire [7:0] dd_col0 = d_sx[7:0] + {3'd0, d_px[4], 4'd0};
wire [8:0] dd_x0   = {1'b0, dd_col0} + {5'd0, d_px[3:0]};
wire [9:0] dd_x    = (dd_x0 < 9'd16) ? {1'b0, dd_x0} + 10'd256 : {1'b0, dd_x0};
wire [3:0] col    = f_sizex ? dcx[3:0] : (f_flipx ? ~d_px[3:0] : d_px[3:0]);
wire [3:0] row    = f_sizey ? dcy[3:0] : (f_flipy ? ~d_dy[3:0] : d_dy[3:0]);

always @(posedge clk) begin
    lb_eng_wr <= 1'b0;

    p_v    <= {p_v[2:0], 1'b0};
    p_x[1] <= p_x[0]; p_x[2] <= p_x[1]; p_x[3] <= p_x[2];
    p_c[1] <= p_c[0];

    if (p_v[1]) spr_prom_addr <= (dd ? 10'h020 : 10'h120) + {2'b00, r_color[5:0], spr_rom_q[3'd7 - {1'b0, p_c[1]}], spr_rom_q[3'd3 - {1'b0, p_c[1]}]};

    if (p_v[3] && spr_prom_q[3:0] != 4'hF && (dd ? (p_x[3] >= 10'd16 && p_x[3] < 10'd272) : p_x[3] < 10'd288)) begin
        lb_eng_addr <= {tgt_buf, p_x[3][8:0]};
        lb_eng_data <= {3'b100, dd, spr_prom_q[3:0]};
        lb_eng_wr   <= 1'b1;
    end

    if (line_step) begin
        tgt_y   <= crt_flip ? 9'd238 - vcnt : vcnt - 9'd15;
        tgt_buf <= ~vcnt[0];
        s_num   <= 6'd0;
        f_cnt   <= 2'd0;
        st      <= (vcnt >= 9'd15 && vcnt < 9'd239) ? S_FETCH : S_IDLE;
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
            d_code0 <= e_code;
            d_px  <= 6'd0;
            d_len <= f_sizex ? 6'd31 : 6'd15;
            st    <= e_hit ? S_DRAW : S_NEXT;
        end
        S_DRAW: begin
            spr_rom_addr <= {d_code, row[3], col[3:2], row[2:0]};
            p_v[0] <= 1'b1;
            p_c[0] <= col[1:0];
            p_x[0] <= dd ? dd_x : d_sx + {4'd0, d_px};
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
