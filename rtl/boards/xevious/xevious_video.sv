//  Based on MAME xevious.cpp (Nicola Salmoria, BSD-3-Clause)

module xevious_video
(
    input               clk,
    input         [2:0] sub,
    input               ce6,
    input               xevios,
    input               flip,
    input               crt_flip,
    input         [8:0] bg_sx, bg_sy, fg_sx, fg_sy,
    input         [8:0] hcnt,
    input         [8:0] vcnt,
    input               line_step,

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

    output       [11:0] fg_rom_a,
    input         [7:0] fg_rom_d,
    output       [11:0] bg_rom_a,
    input         [7:0] bg_rom_d0,
    input         [7:0] bg_rom_d1,
    output       [14:0] spa_rom_a,
    input         [7:0] spa_rom_d,
    output       [12:0] spb_rom_a,
    input         [7:0] spb_rom_d,
    output        [7:0] pal_prom_a,
    input         [7:0] pal_prom_r,
    input         [7:0] pal_prom_g,
    input         [7:0] pal_prom_b,
    output        [8:0] bgl_prom_a,
    input         [7:0] bgl_prom_d0,
    input         [7:0] bgl_prom_d1,
    output        [8:0] spl_prom_a,
    input         [7:0] spl_prom_d0,
    input         [7:0] spl_prom_d1,

    output ram_pool_pkg::pram_i_t lb_i,
    input  ram_pool_pkg::pram_o_t lb_o,

    output reg    [7:0] red = 8'd0,
    output reg    [7:0] green = 8'd0,
    output reg    [7:0] blue = 8'd0
);

wire [8:0] px = (hcnt >= 9'h0F0) ? hcnt - 9'h0F0 : hcnt + 9'd144;
wire [8:0] py = vcnt - 9'd16;
wire       h_vis = (hcnt >= 9'h0F0) || (hcnt < 9'h090);
wire       v_vis = (vcnt >= 9'd16) && (vcnt < 9'd240);
wire       mir   = crt_flip ^ flip;
wire [8:0] fpx   = mir ? 9'd287 - px : px;
wire [8:0] fpy   = mir ? 9'd223 - py : py;

function [7:0] bswap_spr(input [7:0] v);
    bswap_spr = {v[1], v[3], v[5], v[7], v[0], v[2], v[4], v[6]};
endfunction

reg  [11:0] fgr_addr;
wire  [7:0] fgr_q;
assign fg_rom_a = fgr_addr;
assign fgr_q = fg_rom_d;

reg  [11:0] bgr_addr;
wire  [7:0] bgr0_q, bgr1_q;
assign bg_rom_a = bgr_addr;
assign bgr0_q = bg_rom_d0;
assign bgr1_q = bg_rom_d1;

reg  [14:0] spa_addr;
wire  [7:0] spa_q;
assign spa_rom_a = spa_addr;
assign spa_q = spa_rom_d;

reg  [12:0] spb_addr;
wire  [7:0] spb_q;
assign spb_rom_a = spb_addr;
assign spb_q = spb_rom_d;

reg   [9:0] pal_addr;
wire  [7:0] pal_r, pal_g, pal_b;
assign pal_prom_a = pal_addr[7:0];
assign pal_r = pal_prom_r;
assign pal_g = pal_prom_g;
assign pal_b = pal_prom_b;

reg   [8:0] bgl_addr;
wire  [7:0] bgl_lo, bgl_hi;
assign bgl_prom_a = bgl_addr;
assign bgl_lo = bgl_prom_d0;
assign bgl_hi = bgl_prom_d1;

reg   [8:0] spl_addr;
wire  [7:0] spl_lo, spl_hi;
assign spl_prom_a = spl_addr;
assign spl_lo = spl_prom_d0;
assign spl_hi = spl_prom_d1;

reg   [9:0] lb_disp_addr;
reg         lb_disp_clr;
wire  [7:0] lb_disp_q;
reg   [9:0] lb_eng_addr;
reg   [7:0] lb_eng_data;
reg         lb_eng_wr;

assign lb_i.a_addr = {5'd0, lb_disp_addr}; assign lb_i.a_d = 8'h00; assign lb_i.a_we = lb_disp_clr;
assign lb_i.b_addr = {5'd0, lb_eng_addr}; assign lb_i.b_d = lb_eng_data; assign lb_i.b_we = lb_eng_wr;
assign lb_disp_q = lb_o.a_q;

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
wire [8:0] e_code0 = r_flags[7] ? {3'b100, r_code[5:0]} : {1'b0, r_code};
wire [9:0] e_sx = {1'b0, r_xmsb[0], r_x} - 10'd40;
wire [9:0] e_sy = 10'd223 - {2'b00, r_y};

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
wire [9:0] e_dy     = {1'b0, tgt_y} - e_ty;
wire       e_hit    = tp && e_dy < 10'd16;

wire [3:0]  d_c   = e_fx ? ~d_px : d_px;
wire [14:0] d_off = {d_code[8:0], d_row[3], d_c[3:2], d_row[2:0]};
wire [7:0]  spb_d = xevios ? bswap_spr(spb_q) : spb_q;

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

    if (p_v[1]) spl_addr <= {r_color[5:0], p_none[1] ? 1'b0 : spb_d[(p_hi[1] ? 3'd7 : 3'd3) - {1'b0, p_c[1]}],
                             spa_q[3'd7 - {1'b0, p_c[1]}], spa_q[3'd3 - {1'b0, p_c[1]}]};

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
        st      <= (vcnt >= 9'd15 && vcnt < 9'd239) ? S_FETCH : S_IDLE;
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
