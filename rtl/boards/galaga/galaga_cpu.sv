//  Based on MAME galaga.cpp (Nicola Salmoria, BSD-3-Clause)

module galaga_cpu
(
    input               clk,
    input               reset,
    input               pause,
    input               crt_flip,
    input  signed [3:0] h_adj,
    input  signed [3:0] v_adj,
    input         [7:0] variant,

    input         [7:0] in0,
    input         [7:0] in1,
    input         [7:0] dswa,
    input         [7:0] dswb,

    input         [5:0] earom_addr,
    input         [7:0] earom_din,
    input               earom_we,
    output        [7:0] earom_dout,

    output              ce_pix,
    output        [7:0] video_r,
    output        [7:0] video_g,
    output        [7:0] video_b,
    output              video_hs,
    output              video_vs,
    output              video_hblank,
    output              video_vblank,

    output signed [15:0] audio,

    input               hs_access,
    input        [15:0] hs_address,
    input         [7:0] hs_data_in,
    output        [7:0] hs_data_out,
    input               hs_write,

    output chip_pool_pkg::z80r_i_t     [2:0] z80_i,
    input  chip_pool_pkg::z80r_o_t     [2:0] z80_o,
    output chip_pool_pkg::namco_06xx_i_t     n06_0_i,
    input  chip_pool_pkg::namco_06xx_o_t     n06_0_o,
    output chip_pool_pkg::namco_06xx_i_t     n06_1_i,
    input  chip_pool_pkg::namco_06xx_o_t     n06_1_o,
    output chip_pool_pkg::namco_50xx_i_t     n50_0_i,
    input  chip_pool_pkg::namco_50xx_o_t     n50_0_o,
    output chip_pool_pkg::namco_50xx_i_t     n50_1_i,
    input  chip_pool_pkg::namco_50xx_o_t     n50_1_o,
    output chip_pool_pkg::namco_51xx_i_t     n51_0_i,
    input  chip_pool_pkg::namco_51xx_o_t     n51_0_o,
    output chip_pool_pkg::namco_52xx_i_t     n52_0_i,
    input  chip_pool_pkg::namco_52xx_o_t     n52_0_o,
    output chip_pool_pkg::namco_53xx_i_t     n53_0_i,
    input  chip_pool_pkg::namco_53xx_o_t     n53_0_o,
    output chip_pool_pkg::namco_54xx_i_t     n54_0_i,
    input  chip_pool_pkg::namco_54xx_o_t     n54_0_o,
    output chip_pool_pkg::namco_wsg3_i_t     wsg_0_i,
    input  chip_pool_pkg::namco_wsg3_o_t     wsg_0_o,
    output chip_pool_pkg::namco_52xx_snd_i_t n52snd_0_i,
    input  chip_pool_pkg::namco_52xx_snd_o_t n52snd_0_o,
    output chip_pool_pkg::namco_54xx_snd_i_t n54snd_0_i,
    input  chip_pool_pkg::namco_54xx_snd_o_t n54snd_0_o,
    output chip_pool_pkg::namco_05xx_i_t     n05_0_i,
    input  chip_pool_pkg::namco_05xx_o_t     n05_0_o,

    output       [13:0] main_rom_a,
    input         [7:0] main_rom_d,
    output       [13:0] sub_rom_a,
    input         [7:0] sub_rom_d,
    output       [13:0] sub2_rom_a,
    input         [7:0] sub2_rom_d,
    output       [12:0] gfx1_rom_a,
    input         [7:0] gfx1_rom_d,
    output       [13:0] gfx2_rom_a,
    input         [7:0] gfx2_rom_d,
    output       [11:0] gfx2b_rom_a,
    input         [7:0] gfx2b_rom_d,
    output       [14:0] gfx3_rom_a,
    input         [7:0] gfx3_rom_d,
    output       [12:0] gfx3b_rom_a,
    input         [7:0] gfx3b_rom_d,
    output       [13:0] gfx4_rom_a,
    input         [7:0] gfx4_rom_d,
    output        [9:0] prom0_a,
    input         [7:0] prom0_d,
    output        [9:0] prom1_a,
    input         [7:0] prom1_d,
    output        [7:0] xprom_b_a,
    input         [7:0] xprom_b_d,
    output        [8:0] xprom_bgl_a,
    input         [7:0] xprom_bgl_d0,
    input         [7:0] xprom_bgl_d1,
    output        [8:0] xprom_spl_a,
    input         [7:0] xprom_spl_d0,
    input         [7:0] xprom_spl_d1,
    output       [13:0] speech_rom_a,
    input         [7:0] speech_rom_d,

    output ram_pool_pkg::pram_i_t [9:0] pr_i,
    input  ram_pool_pkg::pram_o_t [9:0] pr_o
);

reg [3:0] ph = 4'd0;
always @(posedge clk) ph <= ph + 4'd1;

reg [7:0] mcu_div = 8'd0;
always @(posedge clk) mcu_div <= (mcu_div == 8'd191) ? 8'd0 : mcu_div + 8'd1;

wire ce_cpu = (ph == 4'd15) & ~pause;
wire ce6    = (ph[2:0] == 3'd7);
wire ce_mcu = (mcu_div == 8'd191) & ~pause;
assign ce_pix = ce6;

reg  wdog_reset = 1'b0;

reg        clr_run = 1'b1;
reg [15:0] clr_a   = 16'd0;
always @(posedge clk) begin
    if (reset) begin
        clr_run <= 1'b1;
        clr_a   <= 16'd0;
    end
    else if (clr_run) begin
        clr_a <= clr_a + 16'd1;
        if (clr_a == 16'hFFFF) clr_run <= 1'b0;
    end
end

wire sys_reset  = reset | wdog_reset | clr_run;

wire v_gb  = variant == 8'd1;
wire v_gat = variant == 8'd2;
wire v_dd  = variant == 8'd3 || variant == 8'd4;
wire v_xev = variant == 8'd5 || variant == 8'd6;
wire v_xb  = variant == 8'd6;
wire v_bo  = variant == 8'd7;
wire has_54xx = ~v_gb & ~v_dd;

reg  [7:0] misc_latch = 8'h00;
reg  [7:0] video_latch = 8'h00;
reg        gat_bank = 1'b0;
wire [7:0] n53_q, n50_q;
wire       n06b_nmi_n;
wire [7:0] n06b_q;

wire  [8:0] hcnt, vcnt;
wire        line_step;
wire [10:0] vram_addr_b;
wire [11:0] bvram_addr_b;
wire  [7:0] o_r, o_g, o_b;
reg   [7:0] b_scroll_x = 8'd0, b_scroll_y = 8'd0, b_star_ctl = 8'd0;
reg         b_star_en = 1'b0;
reg [127:0] b_dot_attr = 128'd0;
reg  [95:0] b_spr_a = 96'd0, b_spr_b = 96'd0;
reg [127:0] b_dot_x = 128'd0, b_dot_y = 128'd0;
wire  [7:0] vram_q_b;
wire  [9:0] spr_addr_b;
wire [10:0] xspr_addr_b, xfg_addr_b, xbg_addr_b;
wire  [7:0] ram1_q_b, ram2_q_b, ram3_q_b;
wire  [7:0] g_r, g_g, g_b, x_r, x_g, x_b;
wire  [7:0] fgc_q_b, bgc_q_b, fgv_q_b, bgv_q_b;
reg   [8:0] x_bg_sx = 9'd0, x_fg_sx = 9'd0, x_bg_sy = 9'd0, x_fg_sy = 9'd0;
reg         x_flip = 1'b0;
wire        flip_screen;

wire [12:0] gv_chr_a;
wire [13:0] gv_spr_a;
wire [11:0] gv_pfc_a, gv_map_a;
wire  [9:0] gv_pixp_a, gv_sprp_a;
wire [11:0] xv_fg_a, xv_bg_a;
wire [14:0] xv_spa_a;
wire  [7:0] xv_pal_a;
wire [11:0] bv_chr_a, bv_spr_a;
wire  [7:0] bv_dot_a;
wire  [9:0] bv_pixp_a, bv_sprp_a;
ram_pool_pkg::pram_i_t        gv_lb_i, xv_lb_i, bv_lbs_i;
chip_pool_pkg::namco_05xx_i_t gv_n05_i, bv_n05_i;

galaga_video video
(
    .clk(clk),
    .pause(pause),
    .sub(ph[2:0]),
    .ce6(ce6),
    .dd(v_dd),
    .vlatch(video_latch),
    .gfx_bank(gat_bank),
    .crt_flip(crt_flip),
    .h_adj(h_adj),
    .v_adj(v_adj),
    .hcnt(hcnt),
    .vcnt(vcnt),
    .line_step(line_step),
    .vram_addr(vram_addr_b),
    .vram_q(vram_q_b),
    .spr_addr(spr_addr_b),
    .spr1_q(ram1_q_b),
    .spr2_q(ram2_q_b),
    .spr3_q(ram3_q_b),
    .chr_rom_a(gv_chr_a), .chr_rom_d(gfx1_rom_d), .spr_rom_a(gv_spr_a), .spr_rom_d(gfx2_rom_d),
    .pfc_rom_a(gv_pfc_a), .pfc_rom_d(gfx3_rom_d), .map_rom_a(gv_map_a), .map_rom_d(gfx4_rom_d),
    .pix_prom_a(gv_pixp_a), .pix_prom_d(prom0_d), .spr_prom_a(gv_sprp_a), .spr_prom_d(prom1_d),
    .lb_i(gv_lb_i), .lb_o(pr_o[8]), .star_i(gv_n05_i), .star_o(n05_0_o),
    .red(g_r),
    .green(g_g),
    .blue(g_b),
    .hblank(video_hblank),
    .vblank(video_vblank),
    .hsync(video_hs),
    .vsync(video_vs)
);

xevious_video xvideo
(
    .clk(clk),
    .sub(ph[2:0]),
    .ce6(ce6),
    .xevios(v_xb),
    .flip(x_flip),
    .crt_flip(crt_flip),
    .bg_sx(x_bg_sx),
    .bg_sy(x_bg_sy),
    .fg_sx(x_fg_sx),
    .fg_sy(x_fg_sy),
    .hcnt(hcnt),
    .vcnt(vcnt),
    .line_step(line_step),
    .fg_addr(xfg_addr_b),
    .fgc_q(fgc_q_b),
    .fgv_q(fgv_q_b),
    .bg_addr(xbg_addr_b),
    .bgc_q(bgc_q_b),
    .bgv_q(bgv_q_b),
    .spr_addr(xspr_addr_b),
    .sr1_q(ram1_q_b),
    .sr2_q(ram2_q_b),
    .sr3_q(ram3_q_b),
    .fg_rom_a(xv_fg_a), .fg_rom_d(gfx1_rom_d), .bg_rom_a(xv_bg_a), .bg_rom_d0(gfx2_rom_d), .bg_rom_d1(gfx2b_rom_d),
    .spa_rom_a(xv_spa_a), .spa_rom_d(gfx3_rom_d), .spb_rom_a(gfx3b_rom_a), .spb_rom_d(gfx3b_rom_d),
    .pal_prom_a(xv_pal_a), .pal_prom_r(prom0_d), .pal_prom_g(prom1_d), .pal_prom_b(xprom_b_d),
    .bgl_prom_a(xprom_bgl_a), .bgl_prom_d0(xprom_bgl_d0), .bgl_prom_d1(xprom_bgl_d1),
    .spl_prom_a(xprom_spl_a), .spl_prom_d0(xprom_spl_d0), .spl_prom_d1(xprom_spl_d1),
    .lb_i(xv_lb_i), .lb_o(pr_o[8]),
    .red(x_r),
    .green(x_g),
    .blue(x_b)
);

bosco_video bvideo
(
    .clk(clk),
    .pause(pause),
    .sub(ph[2:0]),
    .ce6(ce6),
    .hcnt(hcnt),
    .vcnt(vcnt),
    .line_step(line_step),
    .scroll_x(b_scroll_x),
    .scroll_y(b_scroll_y),
    .star_ctl(b_star_ctl[5:0]),
    .star_en(b_star_en),
    .star_sets(video_latch[5:4]),
    .flip(~video_latch[0]),
    .crt_flip(crt_flip),
    .vram_addr(bvram_addr_b),
    .vram_q(vram_q_b),
    .spr_a(b_spr_a),
    .spr_b(b_spr_b),
    .dot_x(b_dot_x),
    .dot_y(b_dot_y),
    .dot_attr(b_dot_attr),
    .chr_rom_a(bv_chr_a), .chr_rom_d(gfx1_rom_d), .spr_rom_a(bv_spr_a), .spr_rom_d(gfx2_rom_d),
    .dot_rom_a(bv_dot_a), .dot_rom_d(gfx3_rom_d), .pix_prom_a(bv_pixp_a), .pix_prom_d(prom0_d),
    .spr_prom_a(bv_sprp_a), .spr_prom_d(prom1_d),
    .lbs_i(bv_lbs_i), .lbs_o(pr_o[8]), .lbd_i(pr_i[9]), .lbd_o(pr_o[9]), .star_i(bv_n05_i), .star_o(n05_0_o),
    .red(o_r),
    .green(o_g),
    .blue(o_b)
);

assign video_r = v_xev ? x_r : v_bo ? o_r : g_r;
assign video_g = v_xev ? x_g : v_bo ? o_g : g_g;
assign video_b = v_xev ? x_b : v_bo ? o_b : g_b;

assign gfx1_rom_a  = v_xev ? {1'b0, xv_fg_a} : v_bo ? {1'b0, bv_chr_a} : gv_chr_a;
assign gfx2_rom_a  = v_xev ? {2'b00, xv_bg_a} : v_bo ? {2'b00, bv_spr_a} : gv_spr_a;
assign gfx2b_rom_a = xv_bg_a;
assign gfx3_rom_a  = v_xev ? xv_spa_a : v_bo ? {7'd0, bv_dot_a} : {3'd0, gv_pfc_a};
assign prom0_a     = v_xev ? {2'b00, xv_pal_a} : v_bo ? bv_pixp_a : gv_pixp_a;
assign prom1_a     = v_xev ? {2'b01, xv_pal_a} : v_bo ? bv_sprp_a : gv_sprp_a;
assign xprom_b_a   = xv_pal_a;
assign pr_i[8]     = v_xev ? xv_lb_i : v_bo ? bv_lbs_i : gv_lb_i;
assign n05_0_i     = v_bo ? bv_n05_i : gv_n05_i;

wire vblank_start = line_step & (vcnt == 9'd239);

wire [15:0] cpu_a[3];
wire  [7:0] cpu_do[3];
wire  [2:0] cpu_mreq_n, cpu_iorq_n, cpu_rd_n, cpu_wr_n, cpu_rfsh_n, cpu_m1_n;
reg   [7:0] cpu_di[3];
wire  [2:0] cpu_int_n, cpu_nmi_n;
wire  [2:0] cpu_reset_n;

assign z80_i[0].reset_n = cpu_reset_n[0];  assign z80_i[0].ce = ce_cpu;  assign z80_i[0].int_n = cpu_int_n[0];
assign z80_i[0].nmi_n   = cpu_nmi_n[0];    assign z80_i[0].di = cpu_di[0];
assign z80_i[1].reset_n = cpu_reset_n[1];  assign z80_i[1].ce = ce_cpu;  assign z80_i[1].int_n = cpu_int_n[1];
assign z80_i[1].nmi_n   = cpu_nmi_n[1];    assign z80_i[1].di = cpu_di[1];
assign z80_i[2].reset_n = cpu_reset_n[2];  assign z80_i[2].ce = ce_cpu;  assign z80_i[2].int_n = cpu_int_n[2];
assign z80_i[2].nmi_n   = cpu_nmi_n[2];    assign z80_i[2].di = cpu_di[2];

assign cpu_a[0] = z80_o[0].a;  assign cpu_do[0] = z80_o[0].dout;
assign cpu_a[1] = z80_o[1].a;  assign cpu_do[1] = z80_o[1].dout;
assign cpu_a[2] = z80_o[2].a;  assign cpu_do[2] = z80_o[2].dout;
assign cpu_m1_n   = {z80_o[2].m1_n,   z80_o[1].m1_n,   z80_o[0].m1_n};
assign cpu_mreq_n = {z80_o[2].mreq_n, z80_o[1].mreq_n, z80_o[0].mreq_n};
assign cpu_iorq_n = {z80_o[2].iorq_n, z80_o[1].iorq_n, z80_o[0].iorq_n};
assign cpu_rd_n   = {z80_o[2].rd_n,   z80_o[1].rd_n,   z80_o[0].rd_n};
assign cpu_wr_n   = {z80_o[2].wr_n,   z80_o[1].wr_n,   z80_o[0].wr_n};
assign cpu_rfsh_n = {z80_o[2].rfsh_n, z80_o[1].rfsh_n, z80_o[0].rfsh_n};

wire [7:0] rom_q[3];
assign main_rom_a = cpu_a[0][13:0];  assign rom_q[0] = main_rom_d;
assign sub_rom_a  = cpu_a[1][13:0];  assign rom_q[1] = sub_rom_d;
assign sub2_rom_a = cpu_a[2][13:0];  assign rom_q[2] = sub2_rom_d;

wire  [1:0] own  = ph[3:2];
wire  [1:0] slot = ph[1:0];
wire        own_ok = (own != 2'd3);
wire [15:0] ba   = clr_run ? clr_a : hs_access ? hs_address : own_ok ? cpu_a[own]  : 16'h0000;
wire  [7:0] bdo  = clr_run ? 8'h00 : hs_access ? hs_data_in : own_ok ? cpu_do[own] : 8'h00;
wire        bmem = ~hs_access & own_ok & ~cpu_mreq_n[own] & cpu_rfsh_n[own];
wire        brd  = bmem & ~cpu_rd_n[own];
wire        bwr  = hs_access ? hs_write : bmem & ~cpu_wr_n[own] & (slot == 2'd0);

wire cs_rom    = ba[15:14] == 2'b00;
wire cs_io     = ba[15:11] == 5'b01101;
wire cs_dsw    = cs_io & (ba[5:4] == 2'b00) & ~v_dd;
wire cs_wsg    = cs_io & ~ba[5];
wire cs_misc   = cs_io & (ba[5:4] == 2'b10);
wire cs_wdog   = cs_io & (ba[5:4] == 2'b11);
wire cs_06xx   = ba[15:11] == 5'b01110;
wire cs_vram   = v_bo ? ba[15:12] == 4'h8 : v_xev ? ba[15:11] == 5'b01111 : ba[15:11] == 5'b10000;
wire cs_ram1   = (v_xev ? ba[15:11] == 5'b10000 : v_bo ? ba[15:11] == 5'b01111 : ba[15:11] == 5'b10001);
wire cs_ram2   = ~v_bo & (ba[15:11] == 5'b10010);
wire cs_ram3   = ~v_bo & (v_xev ? ba[15:11] == 5'b10100 : ba[15:11] == 5'b10011);
wire cs_vlatch = v_bo ? ba[15:11] == 5'b10011 && ba[6:4] == 3'd7 : ~v_xev & (ba[15:11] == 5'b10100);
wire cs_06xx1  = v_bo & (ba[15:11] == 5'b10010);
wire cs_bregs  = v_bo & (ba[15:11] == 5'b10011);
wire cs_fgc    = v_xev & (ba[15:11] == 5'b10110);
wire cs_bgc    = v_xev & (ba[15:11] == 5'b10111);
wire cs_fgv    = v_xev & (ba[15:11] == 5'b11000);
wire cs_bgv    = v_xev & (ba[15:11] == 5'b11001);
wire cs_crtc   = v_xev & (ba[15:7] == 9'b1101_0000_0);
wire cs_bb     = v_xev & (ba[15:12] == 4'hF);
wire cs_earom  = v_dd & (ba[15:11] == 5'b10111) & ~ba[6];
wire cs_earomc = v_dd & (ba[15:11] == 5'b10111) &  ba[6];
wire cs_xlatch = v_gat & cs_rom;
wire [7:0] earom_q;
wire       bwr_ram = bwr | clr_run;

wire  [7:0] vram_q, ram1_q, ram2_q, ram3_q;
wire [10:0] ra = (v_xev | v_bo) ? ba[10:0] : {1'b0, ba[9:0]};

assign pr_i[0].a_addr = {3'd0, (v_bo ? ba[11:0] : {1'b0, ba[10:0]})}; assign pr_i[0].a_d = bdo; assign pr_i[0].a_we = bwr_ram & cs_vram;
assign pr_i[0].b_addr = {3'd0, (v_bo ? bvram_addr_b : {1'b0, vram_addr_b})}; assign pr_i[0].b_d = 8'h00; assign pr_i[0].b_we = 1'b0;
assign vram_q = pr_o[0].a_q;
assign vram_q_b = pr_o[0].b_q;

always @(posedge clk) begin
    if (sys_reset) b_star_en <= 1'b0;
    else if (bwr & cs_bregs) begin
        case (ba[6:4])
            3'd0: b_dot_attr[ba[3:0]*8 +: 8] <= bdo;
            3'd1: b_scroll_x <= bdo;
            3'd2: b_scroll_y <= bdo;
            3'd3: b_star_ctl <= bdo;
            3'd4: b_star_en  <= 1'b1;
            default: ;
        endcase
    end
    if (bwr & cs_vram & v_bo) begin
        if (ba[11:0] >= 12'h3D4 && ba[11:0] <= 12'h3DF) b_spr_a[(ba[3:0] - 4'd4)*8 +: 8] <= bdo;
        if (ba[11:0] >= 12'hBD4 && ba[11:0] <= 12'hBDF) b_spr_b[(ba[3:0] - 4'd4)*8 +: 8] <= bdo;
        if (ba[11:4] == 8'h3F) b_dot_x[ba[3:0]*8 +: 8] <= bdo;
        if (ba[11:4] == 8'hBF) b_dot_y[ba[3:0]*8 +: 8] <= bdo;
    end
end

assign pr_i[1].a_addr = {4'd0, (ra)}; assign pr_i[1].a_d = bdo; assign pr_i[1].a_we = bwr_ram & cs_ram1;
assign pr_i[1].b_addr = {4'd0, (v_xev ? xspr_addr_b : {1'b0, spr_addr_b})}; assign pr_i[1].b_d = 8'h00; assign pr_i[1].b_we = 1'b0;
assign ram1_q = pr_o[1].a_q;
assign ram1_q_b = pr_o[1].b_q;

assign pr_i[2].a_addr = {4'd0, (ra)}; assign pr_i[2].a_d = bdo; assign pr_i[2].a_we = bwr_ram & cs_ram2;
assign pr_i[2].b_addr = {4'd0, (v_xev ? xspr_addr_b : {1'b0, spr_addr_b})}; assign pr_i[2].b_d = 8'h00; assign pr_i[2].b_we = 1'b0;
assign ram2_q = pr_o[2].a_q;
assign ram2_q_b = pr_o[2].b_q;

assign pr_i[3].a_addr = {4'd0, (ra)}; assign pr_i[3].a_d = bdo; assign pr_i[3].a_we = bwr_ram & cs_ram3;
assign pr_i[3].b_addr = {4'd0, (v_xev ? xspr_addr_b : {1'b0, spr_addr_b})}; assign pr_i[3].b_d = 8'h00; assign pr_i[3].b_we = 1'b0;
assign ram3_q = pr_o[3].a_q;
assign ram3_q_b = pr_o[3].b_q;

wire  [7:0] fgc_q, bgc_q, fgv_q, bgv_q;

assign pr_i[4].a_addr = {4'd0, (ba[10:0])}; assign pr_i[4].a_d = bdo; assign pr_i[4].a_we = bwr_ram & cs_fgc;
assign pr_i[4].b_addr = {4'd0, (xfg_addr_b)}; assign pr_i[4].b_d = 8'h00; assign pr_i[4].b_we = 1'b0;
assign fgc_q = pr_o[4].a_q;
assign fgc_q_b = pr_o[4].b_q;
assign pr_i[5].a_addr = {4'd0, (ba[10:0])}; assign pr_i[5].a_d = bdo; assign pr_i[5].a_we = bwr_ram & cs_bgc;
assign pr_i[5].b_addr = {4'd0, (xbg_addr_b)}; assign pr_i[5].b_d = 8'h00; assign pr_i[5].b_we = 1'b0;
assign bgc_q = pr_o[5].a_q;
assign bgc_q_b = pr_o[5].b_q;
assign pr_i[6].a_addr = {4'd0, (ba[10:0])}; assign pr_i[6].a_d = bdo; assign pr_i[6].a_we = bwr_ram & cs_fgv;
assign pr_i[6].b_addr = {4'd0, (xfg_addr_b)}; assign pr_i[6].b_d = 8'h00; assign pr_i[6].b_we = 1'b0;
assign fgv_q = pr_o[6].a_q;
assign fgv_q_b = pr_o[6].b_q;
assign pr_i[7].a_addr = {4'd0, (ba[10:0])}; assign pr_i[7].a_d = bdo; assign pr_i[7].a_we = bwr_ram & cs_bgv;
assign pr_i[7].b_addr = {4'd0, (xbg_addr_b)}; assign pr_i[7].b_d = 8'h00; assign pr_i[7].b_we = 1'b0;
assign bgv_q = pr_o[7].a_q;
assign bgv_q_b = pr_o[7].b_q;

always @(posedge clk) begin
    if (sys_reset) x_flip <= 1'b0;
    else if (bwr & cs_crtc) begin
        case (ba[7:4])
            4'd0: x_bg_sx <= {ba[0], bdo};
            4'd1: x_fg_sx <= {ba[0], bdo};
            4'd2: x_bg_sy <= {ba[0], bdo};
            4'd3: x_fg_sy <= {ba[0], bdo};
            4'd7: x_flip  <= bdo[0];
            default: ;
        endcase
    end
end

reg  [7:0] x_bs0 = 8'd0, x_bs1 = 8'd0;
reg  [7:0] x_bb0 = 8'd0, x_bb1 = 8'd0;
reg  [3:0] bb_st = 4'd0;
reg [13:0] pm_addr;
wire [7:0] pm_q_raw;
reg  [7:0] pm_2a;
reg [11:0] bb_dat1;
reg [10:0] bb_adr2c;
wire [7:0] pm_q = (v_xb && pm_addr[13:12] == 2'd0) ? {pm_q_raw[3], pm_q_raw[7], pm_q_raw[5], pm_q_raw[1],
                                                       pm_q_raw[2], pm_q_raw[6], pm_q_raw[4], pm_q_raw[0]} : pm_q_raw;
wire [12:0] adr_2b = {x_bs1[6:1], x_bs0[7:1]};

assign gfx4_rom_a = v_xev ? pm_addr : {2'b00, gv_map_a};
assign pm_q_raw = gfx4_rom_d;

always @(posedge clk) begin
    if (bwr & cs_bb) begin
        if (ba[0]) x_bs1 <= bdo; else x_bs0 <= bdo;
        bb_st <= 4'd1;
    end
    else case (bb_st)
        4'd1: begin pm_addr <= {2'b00, adr_2b[12:1]};   bb_st <= 4'd2; end
        4'd2: begin pm_addr <= {1'b0, adr_2b} + 14'h1000; bb_st <= 4'd3; end
        4'd3: begin pm_2a <= pm_q; bb_st <= 4'd4; end
        4'd4: begin
            bb_dat1 <= adr_2b[0] ? {pm_2a[7:4], pm_q} : {pm_2a[3:0], pm_q};
            bb_st   <= 4'd5;
        end
        4'd5: begin
            bb_adr2c <= {bb_dat1[8:0], x_bs1[0] ^ bb_dat1[9], x_bs0[0] ^ bb_dat1[10]};
            bb_st    <= 4'd6;
        end
        4'd6: begin pm_addr <= 14'h3000 + {3'd0, bb_adr2c};          bb_st <= 4'd7; end
        4'd7: begin pm_addr <= 14'h3000 + {3'd0, bb_adr2c} + 14'h800; bb_st <= 4'd8; end
        4'd8: begin
            x_bb0 <= {pm_q[6] ^ bb_dat1[9], pm_q[7] ^ bb_dat1[10], pm_q[5:0]};
            bb_st <= 4'd9;
        end
        4'd9: begin x_bb1 <= pm_q; bb_st <= 4'd0; end
        default: ;
    endcase
end

wire [7:0] dsw_q = {6'b111111, dswa[ba[2:0]], dswb[ba[2:0]]};

wire [7:0] n06_q;

reg [7:0] bus_q;
always_comb begin
    bus_q = 8'hFF;
    if      (cs_dsw)  bus_q = dsw_q;
    else if (cs_06xx) bus_q = n06_q;
    else if (cs_vram) bus_q = vram_q;
    else if (cs_ram1) bus_q = ram1_q;
    else if (cs_ram2) bus_q = ram2_q;
    else if (cs_ram3) bus_q = ram3_q;
    else if (cs_earom) bus_q = earom_q;
    else if (cs_fgc)  bus_q = fgc_q;
    else if (cs_bgc)  bus_q = bgc_q;
    else if (cs_fgv)  bus_q = fgv_q;
    else if (cs_bgv)  bus_q = bgv_q;
    else if (cs_bb)   bus_q = ba[0] ? x_bb1 : x_bb0;
    else if (cs_06xx1) bus_q = n06b_q;
end

reg [7:0] shared_q[3];
assign hs_data_out = bus_q;
always @(posedge clk) if (own_ok && slot == 2'd2 && brd) shared_q[own] <= bus_q;

always_comb begin
    for (int i = 0; i < 3; i++) begin
        if (~cpu_iorq_n[i])                 cpu_di[i] = 8'hFF;
        else if (cpu_a[i][15:14] == 2'b00)  cpu_di[i] = rom_q[i];
        else                                cpu_di[i] = shared_q[i];
    end
end

reg  [3:0] wdog = 4'd0;

always @(posedge clk) begin
    if (sys_reset) begin
        misc_latch  <= 8'h00;
        video_latch <= 8'h00;
    end
    else if (bwr) begin
        if (cs_misc)   misc_latch[ba[2:0]]  <= bdo[0];
        if (cs_vlatch) video_latch[ba[2:0]] <= bdo[0];
    end
end

always @(posedge clk) begin
    if (sys_reset) gat_bank <= 1'b0;
    else if (bwr & cs_xlatch & ba[2:0] == 3'd0) gat_bank <= bdo[0];
end

reg  [7:0] er_mem[64];
reg  [5:0] er_addr = 6'd0;
reg  [7:0] er_data = 8'hFF;
reg        er_cs1 = 1'b0, er_c1 = 1'b0, er_c2 = 1'b0, er_ck = 1'b0;
assign earom_q = er_data;

initial for (int i = 0; i < 64; i++) er_mem[i] = 8'hFF;

wire n_cs1 = bdo[3];
wire n_c1  = ~bdo[1];
wire n_c2  = bdo[2];
wire n_ck  = bdo[0];
wire er_ctl_act = n_cs1 && {n_cs1, n_c1, n_c2} != {er_cs1, er_c1, er_c2};
wire er_clk_act = n_cs1 && er_ck && !n_ck;

always @(posedge clk) begin
    if (bwr & cs_earom) begin
        er_addr <= ba[5:0];
        er_data <= bdo;
    end
    else if (bwr & cs_earomc) begin
        {er_cs1, er_c1, er_c2, er_ck} <= {n_cs1, n_c1, n_c2, n_ck};
        if ((er_ctl_act || er_clk_act) && !n_c1) er_mem[er_addr] <= n_c2 ? 8'hFF : (er_mem[er_addr] & er_data);
        if (er_clk_act && n_c1) er_data <= er_mem[er_addr];
    end
    else if (earom_we) er_mem[earom_addr] <= earom_din;
end

assign earom_dout = er_mem[earom_addr];

always @(posedge clk) begin
    wdog_reset <= 1'b0;
    if (reset) wdog <= 4'd0;
    else if (bwr & cs_wdog) wdog <= 4'd0;
    else if (vblank_start & ~pause) begin
        if (wdog == 4'd7) begin
            wdog       <= 4'd0;
            wdog_reset <= 1'b1;
        end
        else wdog <= wdog + 4'd1;
    end
end

reg irq1 = 1'b0, irq2 = 1'b0;
always @(posedge clk) begin
    if (~misc_latch[0])  irq1 <= 1'b0;
    else if (vblank_start) irq1 <= 1'b1;
    if (~misc_latch[1])  irq2 <= 1'b0;
    else if (vblank_start) irq2 <= 1'b1;
end

reg        nmi3 = 1'b0;
reg  [4:0] nmi3_cnt = 5'd0;
always @(posedge clk) begin
    if (line_step && (v_bo ? (vcnt == 9'd63 || vcnt == 9'd191) : (vcnt == 9'd79 || vcnt == 9'd207)) && ~misc_latch[2]) begin
        nmi3     <= 1'b1;
        nmi3_cnt <= 5'd31;
    end
    else if (nmi3_cnt != 5'd0) nmi3_cnt <= nmi3_cnt - 5'd1;
    else nmi3 <= 1'b0;
end

wire n06_nmi_n;

assign cpu_int_n   = {1'b1, ~irq2, ~irq1};
assign cpu_nmi_n   = {~nmi3, v_bo ? n06b_nmi_n : 1'b1, n06_nmi_n};
assign cpu_reset_n = {~sys_reset & misc_latch[3], ~sys_reset & misc_latch[3], ~sys_reset};

assign flip_screen = video_latch[7];

wire [3:0] n06_chipsel;
wire       n06_rw0;
wire [7:0] n06_chip_dout;
wire [3:0] n06_chip_wr;
wire [7:0] n51_q;
wire       mcu_reset_n = ~sys_reset & misc_latch[3];

assign n06_0_i.reset = sys_reset;
assign n06_0_i.irq_on_access = ~v_dd & ~v_bo;
assign n06_0_i.cpu_dout = bdo;
assign n06_0_i.data_wr = bwr & cs_06xx & ~ba[8];
assign n06_0_i.data_rd = brd & cs_06xx & ~ba[8];
assign n06_0_i.ctrl_wr = bwr & cs_06xx & ba[8];
assign n06_0_i.ctrl_rd = cs_06xx & ba[8];
assign n06_q = n06_0_o.cpu_din;
assign n06_nmi_n = n06_0_o.nmi_n;
assign n06_chipsel = n06_0_o.chipsel;
assign n06_rw0 = n06_0_o.rw0;
assign n06_0_i.chip0_din = n51_q;
assign n06_0_i.chip1_din = v_dd ? n53_q : 8'hFF;
assign n06_0_i.chip2_din = (v_xev | v_bo) ? n50_q : 8'hFF;
assign n06_0_i.chip3_din = 8'hFF;
assign n06_chip_dout = n06_0_o.chip_dout;
assign n06_chip_wr = n06_0_o.chip_wr;

assign n51_0_i.ena = ce_mcu;
assign n51_0_i.reset_n = mcu_reset_n;
assign n51_0_i.chip_sel = n06_chipsel[0];
assign n51_0_i.rw_in = n06_rw0;
assign n51_q = n51_0_o.data_out;
assign n51_0_i.wr_en = n06_chip_wr[0];
assign n51_0_i.wr_data = n06_chip_dout;
assign n51_0_i.in_a = in0;
assign n51_0_i.in_b = in1;
assign n51_0_i.vblank = video_vblank;

assign n50_0_i.ena = ce_mcu;
assign n50_0_i.reset_n = mcu_reset_n;
assign n50_0_i.chip_sel = n06_chipsel[2] & (v_xev | v_bo);
assign n50_0_i.rw_in = n06_rw0;
assign n50_q = n50_0_o.data_out;
assign n50_0_i.wr_en = n06_chip_wr[2] & (v_xev | v_bo);
assign n50_0_i.wr_data = n06_chip_dout;

assign n53_0_i.ena = ce_mcu;
assign n53_0_i.reset_n = mcu_reset_n;
assign n53_0_i.chip_sel = n06_chipsel[1] & v_dd;
assign n53_q = n53_0_o.data_out;
assign n53_0_i.k_in = {misc_latch[7:5], 1'b0};
assign n53_0_i.in_a = dswa;
assign n53_0_i.in_b = dswb;

wire [3:0] n54_o0, n54_o1, n54_r1;

assign n54_0_i.ena = ce_mcu;
assign n54_0_i.reset_n = mcu_reset_n;
assign n54_0_i.chip_sel = n06_chipsel[3] & has_54xx;
assign n54_0_i.wr_en = n06_chip_wr[3] & has_54xx;
assign n54_0_i.wr_data = n06_chip_dout;
assign n54_o0 = n54_0_o.discrete_o0;
assign n54_o1 = n54_0_o.discrete_o1;
assign n54_r1 = n54_0_o.discrete_r1;

wire signed [15:0] wsg_audio, n54_audio;

assign wsg_0_i.reset = sys_reset;
assign wsg_0_i.reg_addr = ba[4:0];
assign wsg_0_i.reg_data = bdo[3:0];
assign wsg_0_i.reg_wr = bwr & cs_wsg;
assign wsg_audio = wsg_0_o.audio;

wire [3:0] n06b_chipsel;
wire       n06b_rw0;
wire [7:0] n06b_chip_dout;
wire [3:0] n06b_chip_wr;
wire [7:0] n50b_q;
wire       vreset_n = ~sys_reset & video_latch[7];

assign n06_1_i.reset = sys_reset | ~v_bo;
assign n06_1_i.irq_on_access = 1'b0;
assign n06_1_i.cpu_dout = bdo;
assign n06_1_i.data_wr = bwr & cs_06xx1 & ~ba[8];
assign n06_1_i.data_rd = brd & cs_06xx1 & ~ba[8];
assign n06_1_i.ctrl_wr = bwr & cs_06xx1 & ba[8];
assign n06_1_i.ctrl_rd = cs_06xx1 & ba[8];
assign n06b_q = n06_1_o.cpu_din;
assign n06b_nmi_n = n06_1_o.nmi_n;
assign n06b_chipsel = n06_1_o.chipsel;
assign n06b_rw0 = n06_1_o.rw0;
assign n06_1_i.chip0_din = n50b_q;
assign n06_1_i.chip1_din = 8'hFF;
assign n06_1_i.chip2_din = 8'hFF;
assign n06_1_i.chip3_din = 8'hFF;
assign n06b_chip_dout = n06_1_o.chip_dout;
assign n06b_chip_wr = n06_1_o.chip_wr;

assign n50_1_i.ena = ce_mcu;
assign n50_1_i.reset_n = vreset_n;
assign n50_1_i.chip_sel = n06b_chipsel[0];
assign n50_1_i.rw_in = n06b_rw0;
assign n50b_q = n50_1_o.data_out;
assign n50_1_i.wr_en = n06b_chip_wr[0];
assign n50_1_i.wr_data = n06b_chip_dout;

wire  [3:0] n52_p;
wire [15:0] n52_addr;
reg  [13:0] sp_rd;
wire  [7:0] sp_q;
reg         sp_ff;
always @(*) begin
    sp_ff = 1'b0;
    if      (!n52_addr[12]) sp_rd = {2'd0, n52_addr[11:0]};
    else if (!n52_addr[13]) sp_rd = {2'd1, n52_addr[11:0]};
    else if (!n52_addr[14]) sp_rd = {2'd2, n52_addr[11:0]};
    else begin              sp_rd = {2'd3, n52_addr[11:0]}; sp_ff = 1'b1; end
end
reg sp_ff_d;
always @(posedge clk) sp_ff_d <= sp_ff;

assign speech_rom_a = sp_rd;
assign sp_q = speech_rom_d;

reg [13:0] t555 = 14'd0;
always @(posedge clk) t555 <= (t555 == 14'd8484) ? 14'd0 : t555 + 14'd1;
wire n52_tc_n = ~(t555 < 14'd256);

assign n52_0_i.ena = ce_mcu;
assign n52_0_i.reset_n = vreset_n;
assign n52_0_i.chip_sel = n06b_chipsel[1];
assign n52_0_i.wr_en = n06b_chip_wr[1];
assign n52_0_i.wr_data = n06b_chip_dout;
assign n52_0_i.si = 1'b0;
assign n52_0_i.tc_n = n52_tc_n;
assign n52_p = n52_0_o.p_out;
assign n52_addr = n52_0_o.sample_addr;
assign n52_0_i.sample_data = sp_ff_d ? 8'hFF : sp_q;

wire signed [31:0] n52_volts;
assign n52snd_0_i.reset = sys_reset | ~v_bo;
assign n52snd_0_i.p_data = n52_p;
assign n52_volts = n52snd_0_o.volts;

assign n54snd_0_i.reset = sys_reset;
assign n54snd_0_i.o0_data = n54_o0;
assign n54snd_0_i.o1_data = n54_o1;
assign n54snd_0_i.r1_data = n54_r1;
assign n54snd_0_i.bosco = v_bo;
assign n54snd_0_i.ext_volts = n52_volts;
assign n54_audio = n54snd_0_o.audio;

wire signed [15:0] n54_gated = has_54xx ? n54_audio : 16'sd0;
wire signed [16:0] mix = wsg_audio + n54_gated;
assign audio = (mix > 17'sd32767) ? 16'sh7FFF : (mix < -17'sd32768) ? 16'sh8000 : mix[15:0];

endmodule
