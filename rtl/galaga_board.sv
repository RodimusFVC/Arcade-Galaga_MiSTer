//============================================================================
//
//  Namco Galaga-family board (CPU board + video board): Galaga, Dig Dug, Xevious, Bosconian
//
//  Memory maps, interrupt and custom-chip wiring per MAME galaga.cpp
//  (Nicola Salmoria); video counters after Dar's (darfpga) Galaga core.
//
//============================================================================

module galaga_board
(
    input               clk,            // 49.152 MHz
    input               reset,
    input               pause,
    input               crt_flip,
    input         [7:0] variant,        // 0 Galaga, 1 Galaga bootleg (no 54xx: Gallag, Nebulous Bee), 2 Gatsbee,
                                        // 3 Dig Dug (also Zig Zag), 5 Xevious, 6 Xevious with bootleg ROM bit order (Xevios, Battles set 2),
                                        // 7 Bosconian

    input         [7:0] in0,            // 51xx input<0>/<1>
    input         [7:0] in1,            // 51xx input<2>/<3>
    input         [7:0] dswa,
    input         [7:0] dswb,

    // Dig Dug EAROM contents, for saving (second port)
    input         [5:0] earom_addr,
    input         [7:0] earom_din,
    input               earom_we,
    output        [7:0] earom_dout,

    input        [24:0] ioctl_addr,
    input         [7:0] ioctl_dout,
    input               ioctl_wr0,      // ioctl index 0

    output              ce_pix,
    output        [7:0] video_r,
    output        [7:0] video_g,
    output        [7:0] video_b,
    output              video_hs,
    output              video_vs,
    output              video_hblank,
    output              video_vblank,

    output signed [15:0] audio,

    // hiscore: drives the shared bus while the CPUs are paused
    input               hs_access,
    input        [15:0] hs_address,
    input         [7:0] hs_data_in,
    output        [7:0] hs_data_out,
    input               hs_write
);

//------------------------------------------------------- Clock enables -------------------------------------------------------//

// 49.152 MHz / 16 = 3.072 MHz Z80s; / 8 = 6.144 MHz pixel. Namco MCUs: 1.536 MHz pin clock, one machine cycle per
// 6 clocks (MAME MB8843 "internally divided by 6"), and mb88_core retires a cycle per enable -> 49.152 MHz / 192 = 256 kHz
reg [3:0] ph = 4'd0;
always @(posedge clk) ph <= ph + 4'd1;

reg [7:0] mcu_div = 8'd0;
always @(posedge clk) mcu_div <= (mcu_div == 8'd191) ? 8'd0 : mcu_div + 8'd1;

wire ce_cpu = (ph == 4'd15) & ~pause;
wire ce6    = (ph[2:0] == 3'd7);
wire ce_mcu = (mcu_div == 8'd191) & ~pause;
assign ce_pix = ce6;

reg  wdog_reset = 1'b0;
wire sys_reset  = reset | wdog_reset;

wire v_gb  = variant == 8'd1;
wire v_gat = variant == 8'd2;
wire v_dd  = variant == 8'd3 || variant == 8'd4;
wire v_xev = variant == 8'd5 || variant == 8'd6;
wire v_xb  = variant == 8'd6;
wire v_bo  = variant == 8'd7;
wire has_54xx = ~v_gb & ~v_dd;

//------------------------------------------------------- ROM load map --------------------------------------------------------//

wire main_cs, sub_cs, sub2_cs, gfx1_cs, sub3_cs, gfx2_cs, gfx3_cs, prom_cs, wave_cs, gfx4_cs, speech_cs;
wire mcu50_cs, mcu51_cs, mcu52_cs, mcu53_cs, mcu54_cs;

selector rom_selector
(
    .ioctl_addr(ioctl_addr),
    .main_cs(main_cs), .sub_cs(sub_cs), .sub2_cs(sub2_cs), .gfx1_cs(gfx1_cs), .sub3_cs(sub3_cs),
    .gfx2_cs(gfx2_cs), .gfx3_cs(gfx3_cs), .prom_cs(prom_cs), .wave_cs(wave_cs), .gfx4_cs(gfx4_cs),
    .speech_cs(speech_cs), .mcu50_cs(mcu50_cs), .mcu51_cs(mcu51_cs), .mcu52_cs(mcu52_cs), .mcu53_cs(mcu53_cs),
    .mcu54_cs(mcu54_cs)
);

//------------------------------------------------------- Video --------------------------------------------------------------//

reg  [7:0] misc_latch = 8'h00;              // 3C LS259: Q0 IRQ1, Q1 IRQ2, Q2 NMION, Q3 RESET, Q5-7 MOD
reg  [7:0] video_latch = 8'h00;             // 5K LS259: Q0-Q5 05xx starfield (Dig Dug: playfield), Q7 flip
reg        gat_bank = 1'b0;                 // Gatsbee character bank
wire [7:0] n53_q, n50_q;
wire       n06b_nmi_n;
wire [7:0] n06b_q;

wire  [8:0] hcnt, vcnt;
wire        line_step;
wire [10:0] vram_addr_b;
wire [11:0] bvram_addr_b;
wire  [7:0] o_r, o_g, o_b;
reg   [7:0] b_scroll_x = 8'd0, b_scroll_y = 8'd0, b_star_ctl = 8'd0;   // Bosconian 9810 / 9820 / 9830
reg         b_star_en = 1'b0;                                          // after the first 9840 (STARCLR) write
reg [127:0] b_dot_attr = 128'd0;                                       // 9800-980F
reg  [95:0] b_spr_a = 96'd0, b_spr_b = 96'd0;                          // video RAM 3D4-3DF / BD4-BDF
reg [127:0] b_dot_x = 128'd0, b_dot_y = 128'd0;                        // video RAM 3F0-3FF / BF0-BFF
wire  [7:0] vram_q_b;
wire  [9:0] spr_addr_b;
wire [10:0] xspr_addr_b, xfg_addr_b, xbg_addr_b;
wire  [7:0] ram1_q_b, ram2_q_b, ram3_q_b;
wire  [7:0] g_r, g_g, g_b, x_r, x_g, x_b;
wire  [7:0] fgc_q_b, bgc_q_b, fgv_q_b, bgv_q_b;
reg   [8:0] x_bg_sx = 9'd0, x_fg_sx = 9'd0, x_bg_sy = 9'd0, x_fg_sy = 9'd0;   // Xevious CRTC scroll
reg         x_flip = 1'b0;
wire        flip_screen;

galaga_video video
(
    .clk(clk),
    .sub(ph[2:0]),
    .ce6(ce6),
    .dd(v_dd),
    .vlatch(video_latch),
    .gfx_bank(gat_bank),
    .crt_flip(crt_flip),
    .hcnt(hcnt),
    .vcnt(vcnt),
    .line_step(line_step),
    .vram_addr(vram_addr_b),
    .vram_q(vram_q_b),
    .spr_addr(spr_addr_b),
    .spr1_q(ram1_q_b),
    .spr2_q(ram2_q_b),
    .spr3_q(ram3_q_b),
    .ioctl_addr(ioctl_addr),
    .ioctl_dout(ioctl_dout),
    .gfx1_wr(ioctl_wr0 & gfx1_cs),
    .gfx2_wr(ioctl_wr0 & gfx2_cs),
    .gfx3_wr(ioctl_wr0 & gfx3_cs),
    .gfx4_wr(ioctl_wr0 & gfx4_cs),
    .prom_wr(ioctl_wr0 & prom_cs),
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
    .ioctl_addr(ioctl_addr),
    .ioctl_dout(ioctl_dout),
    .gfx1_wr(ioctl_wr0 & gfx1_cs),
    .gfx2_wr(ioctl_wr0 & gfx2_cs),
    .gfx3_wr(ioctl_wr0 & gfx3_cs),
    .prom_wr(ioctl_wr0 & prom_cs),
    .red(x_r),
    .green(x_g),
    .blue(x_b)
);

bosco_video bvideo
(
    .clk(clk),
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
    .ioctl_addr(ioctl_addr),
    .ioctl_dout(ioctl_dout),
    .gfx1_wr(ioctl_wr0 & gfx1_cs),
    .gfx2_wr(ioctl_wr0 & gfx2_cs),
    .gfx3_wr(ioctl_wr0 & gfx3_cs),
    .prom_wr(ioctl_wr0 & prom_cs),
    .red(o_r),
    .green(o_g),
    .blue(o_b)
);

assign video_r = v_xev ? x_r : v_bo ? o_r : g_r;
assign video_g = v_xev ? x_g : v_bo ? o_g : g_g;
assign video_b = v_xev ? x_b : v_bo ? o_b : g_b;

wire vblank_start = line_step & (vcnt == 9'd239);       // first vblank line is 240 (MAME line 224)

//------------------------------------------------------- CPUs ----------------------------------------------------------------//

// Three Z80s on one shared bus. Each owns a 4-clock window of every 16-clock CPU cycle: ph[3:2] = 0 main, 1 sub, 2 sub2.
wire [15:0] cpu_a[3];
wire  [7:0] cpu_do[3];
wire  [2:0] cpu_mreq_n, cpu_iorq_n, cpu_rd_n, cpu_wr_n, cpu_rfsh_n, cpu_m1_n;
reg   [7:0] cpu_di[3];
wire  [2:0] cpu_int_n, cpu_nmi_n;
wire  [2:0] cpu_reset_n;

genvar gi;
generate
    for (gi = 0; gi < 3; gi++) begin : cpu
        T80se #(.Mode(0), .T2Write(0), .IOWait(1)) z80
        (
            .RESET_n(cpu_reset_n[gi]),
            .CLK_n(clk),
            .CLKEN(ce_cpu),
            .WAIT_n(1'b1),
            .INT_n(cpu_int_n[gi]),
            .NMI_n(cpu_nmi_n[gi]),
            .BUSRQ_n(1'b1),
            .M1_n(cpu_m1_n[gi]),
            .MREQ_n(cpu_mreq_n[gi]),
            .IORQ_n(cpu_iorq_n[gi]),
            .RD_n(cpu_rd_n[gi]),
            .WR_n(cpu_wr_n[gi]),
            .RFSH_n(cpu_rfsh_n[gi]),
            .HALT_n(),
            .BUSAK_n(),
            .A(cpu_a[gi]),
            .DI(cpu_di[gi]),
            .DO(cpu_do[gi])
        );
    end
endgenerate

// program ROMs (0000-3FFF), one per CPU
wire [7:0] rom_q[3];

dpram_dc #(.widthad_a(14)) main_rom
(
    .clock_a(clk), .address_a(cpu_a[0][13:0]), .data_a(8'h00), .wren_a(1'b0), .q_a(rom_q[0]),
    .clock_b(clk), .address_b(ioctl_addr[13:0]), .data_b(ioctl_dout), .wren_b(ioctl_wr0 & main_cs & ~ioctl_addr[14]), .q_b()
);

dpram_dc #(.widthad_a(14)) sub_rom
(
    .clock_a(clk), .address_a(cpu_a[1][13:0]), .data_a(8'h00), .wren_a(1'b0), .q_a(rom_q[1]),
    .clock_b(clk), .address_b(ioctl_addr[13:0]), .data_b(ioctl_dout), .wren_b(ioctl_wr0 & sub_cs), .q_b()
);

dpram_dc #(.widthad_a(14)) sub2_rom
(
    .clock_a(clk), .address_a(cpu_a[2][13:0]), .data_a(8'h00), .wren_a(1'b0), .q_a(rom_q[2]),
    .clock_b(clk), .address_b(ioctl_addr[13:0]), .data_b(ioctl_dout), .wren_b(ioctl_wr0 & sub2_cs), .q_b()
);

//------------------------------------------------------- Shared bus ----------------------------------------------------------//

wire  [1:0] own  = ph[3:2];                 // bus owner this window (3 = idle)
wire  [1:0] slot = ph[1:0];                 // 0 address out, 1 RAM data valid, 2 capture
wire        own_ok = (own != 2'd3);
wire [15:0] ba   = hs_access ? hs_address : own_ok ? cpu_a[own]  : 16'h0000;
wire  [7:0] bdo  = hs_access ? hs_data_in : own_ok ? cpu_do[own] : 8'h00;
wire        bmem = ~hs_access & own_ok & ~cpu_mreq_n[own] & cpu_rfsh_n[own];
wire        brd  = bmem & ~cpu_rd_n[own];
wire        bwr  = hs_access ? hs_write : bmem & ~cpu_wr_n[own] & (slot == 2'd0);   // one write strobe per bus cycle

// address decode (galaga.cpp memory map; mirrors as in the CPU board decode table)
wire cs_rom    = ba[15:14] == 2'b00;
wire cs_io     = ba[15:11] == 5'b01101;                          // 6800-6FFF
wire cs_dsw    = cs_io & (ba[5:4] == 2'b00) & ~v_dd;             // read 6800-6807 (Dig Dug reads its DIPs through the 53xx)
wire cs_wsg    = cs_io & ~ba[5];                                 // write 6800-681F
wire cs_misc   = cs_io & (ba[5:4] == 2'b10);                     // write 6820-6827
wire cs_wdog   = cs_io & (ba[5:4] == 2'b11);                     // write 6830
wire cs_06xx   = ba[15:11] == 5'b01110;                          // 7000-77FF, A8 = 0 data / 1 control
// Galaga / Dig Dug: tile RAM 8000, RAM 1-3 at 8800 / 9000 / 9800 (1K mirrored). Xevious: work RAM 7800 (the tile RAM),
// RAM 1-3 at 8000 / 9000 / A000 (2K), tile RAMs B000-CFFF, CRTC D000, planet map F000
// Bosconian: work RAM 7800 (RAM 1), video RAM 8000-8FFF (4K), second 06xx 9000, registers 9800, video latch 9870
wire cs_vram   = v_bo ? ba[15:12] == 4'h8 : v_xev ? ba[15:11] == 5'b01111 : ba[15:11] == 5'b10000;
wire cs_ram1   = (v_xev ? ba[15:11] == 5'b10000 : v_bo ? ba[15:11] == 5'b01111 : ba[15:11] == 5'b10001);
wire cs_ram2   = ~v_bo & (ba[15:11] == 5'b10010);
wire cs_ram3   = ~v_bo & (v_xev ? ba[15:11] == 5'b10100 : ba[15:11] == 5'b10011);
wire cs_vlatch = v_bo ? ba[15:11] == 5'b10011 && ba[6:4] == 3'd7 : ~v_xev & (ba[15:11] == 5'b10100);
wire cs_06xx1  = v_bo & (ba[15:11] == 5'b10010);                 // 9000-97FF, A8 = 0 data / 1 control
wire cs_bregs  = v_bo & (ba[15:11] == 5'b10011);                 // 9800-9FFF
wire cs_fgc    = v_xev & (ba[15:11] == 5'b10110);                // B000-B7FF
wire cs_bgc    = v_xev & (ba[15:11] == 5'b10111);                // B800-BFFF
wire cs_fgv    = v_xev & (ba[15:11] == 5'b11000);                // C000-C7FF
wire cs_bgv    = v_xev & (ba[15:11] == 5'b11001);                // C800-CFFF
wire cs_crtc   = v_xev & (ba[15:7] == 9'b1101_0000_0);           // D000-D07F
wire cs_bb     = v_xev & (ba[15:12] == 4'hF);                    // F000-FFFF
wire cs_earom  = v_dd & (ba[15:11] == 5'b10111) & ~ba[6];        // Dig Dug B800-B83F EAROM data
wire cs_earomc = v_dd & (ba[15:11] == 5'b10111) &  ba[6];        // Dig Dug B840 EAROM control
wire cs_xlatch = v_gat & cs_rom;                                  // Gatsbee 0000-0007 (mirrored) extra LS259
wire [7:0] earom_q;

// work / video RAMs; port B: video (tile RAM, sprite registers)
wire  [7:0] vram_q, ram1_q, ram2_q, ram3_q;
wire [10:0] ra = (v_xev | v_bo) ? ba[10:0] : {1'b0, ba[9:0]};   // Xevious / Bosconian RAM 1 is 2K

dpram_dc #(.widthad_a(12)) vram
(
    .clock_a(clk), .address_a(v_bo ? ba[11:0] : {1'b0, ba[10:0]}), .data_a(bdo), .wren_a(bwr & cs_vram), .q_a(vram_q),
    .clock_b(clk), .address_b(v_bo ? bvram_addr_b : {1'b0, vram_addr_b}), .data_b(8'h00), .wren_b(1'b0), .q_b(vram_q_b)
);

// Bosconian registers, and copies of the sprite / dot registers held in video RAM (for the video's engine)
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

dpram_dc #(.widthad_a(11)) ram1
(
    .clock_a(clk), .address_a(ra), .data_a(bdo), .wren_a(bwr & cs_ram1), .q_a(ram1_q),
    .clock_b(clk), .address_b(v_xev ? xspr_addr_b : {1'b0, spr_addr_b}), .data_b(8'h00), .wren_b(1'b0), .q_b(ram1_q_b)
);

dpram_dc #(.widthad_a(11)) ram2
(
    .clock_a(clk), .address_a(ra), .data_a(bdo), .wren_a(bwr & cs_ram2), .q_a(ram2_q),
    .clock_b(clk), .address_b(v_xev ? xspr_addr_b : {1'b0, spr_addr_b}), .data_b(8'h00), .wren_b(1'b0), .q_b(ram2_q_b)
);

dpram_dc #(.widthad_a(11)) ram3
(
    .clock_a(clk), .address_a(ra), .data_a(bdo), .wren_a(bwr & cs_ram3), .q_a(ram3_q),
    .clock_b(clk), .address_b(v_xev ? xspr_addr_b : {1'b0, spr_addr_b}), .data_b(8'h00), .wren_b(1'b0), .q_b(ram3_q_b)
);

// Xevious tile RAMs; port B: xevious_video
wire  [7:0] fgc_q, bgc_q, fgv_q, bgv_q;

dpram_dc #(.widthad_a(11)) x_fgc
(
    .clock_a(clk), .address_a(ba[10:0]), .data_a(bdo), .wren_a(bwr & cs_fgc), .q_a(fgc_q),
    .clock_b(clk), .address_b(xfg_addr_b), .data_b(8'h00), .wren_b(1'b0), .q_b(fgc_q_b)
);
dpram_dc #(.widthad_a(11)) x_bgc
(
    .clock_a(clk), .address_a(ba[10:0]), .data_a(bdo), .wren_a(bwr & cs_bgc), .q_a(bgc_q),
    .clock_b(clk), .address_b(xbg_addr_b), .data_b(8'h00), .wren_b(1'b0), .q_b(bgc_q_b)
);
dpram_dc #(.widthad_a(11)) x_fgv
(
    .clock_a(clk), .address_a(ba[10:0]), .data_a(bdo), .wren_a(bwr & cs_fgv), .q_a(fgv_q),
    .clock_b(clk), .address_b(xfg_addr_b), .data_b(8'h00), .wren_b(1'b0), .q_b(fgv_q_b)
);
dpram_dc #(.widthad_a(11)) x_bgv
(
    .clock_a(clk), .address_a(ba[10:0]), .data_a(bdo), .wren_a(bwr & cs_bgv), .q_a(bgv_q),
    .clock_b(clk), .address_b(xbg_addr_b), .data_b(8'h00), .wren_b(1'b0), .q_b(bgv_q_b)
);

// Xevious CRTC (MAME xevious_vh_latch_w): register = A7-A4, value = A0 << 8 | data
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

// Xevious planet map (MAME xevious_bb_r, schematic 9B): F000-F001 writes set BS0/BS1; reads return BB0/BB1 looked up
// through ROMs 2A (gfx4 0000), 2B (1000) and 2C (3000). The lookup runs after each BS write, long before the read.
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

dpram_dc #(.widthad_a(14)) planet_rom
(
    .clock_a(clk), .address_a(pm_addr), .data_a(8'h00), .wren_a(1'b0), .q_a(pm_q_raw),
    .clock_b(clk), .address_b(ioctl_addr[13:0]), .data_b(ioctl_dout), .wren_b(ioctl_wr0 & gfx4_cs), .q_b()
);

always @(posedge clk) begin
    if (bwr & cs_bb) begin
        if (ba[0]) x_bs1 <= bdo; else x_bs0 <= bdo;
        bb_st <= 4'd1;
    end
    else case (bb_st)
        4'd1: begin pm_addr <= {2'b00, adr_2b[12:1]};   bb_st <= 4'd2; end   // 2A
        4'd2: begin pm_addr <= {1'b0, adr_2b} + 14'h1000; bb_st <= 4'd3; end  // 2B
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
        4'd8: begin                                                    // BB0: swap bits 6 / 7, flip by dat1 bits 10 / 9
            x_bb0 <= {pm_q[6] ^ bb_dat1[9], pm_q[7] ^ bb_dat1[10], pm_q[5:0]};
            bb_st <= 4'd9;
        end
        4'd9: begin x_bb1 <= pm_q; bb_st <= 4'd0; end
        default: ;
    endcase
end

// DIP switches: bit 0 = DSWB, bit 1 = DSWA, selected by A2-A0; the rest of the data bus floats high
wire [7:0] dsw_q = {6'b111111, dswa[ba[2:0]], dswb[ba[2:0]]};

// 06xx read data
wire [7:0] n06_q;

// read data for the bus owner, captured in slot 2; floating bus reads FF (data bus pull-ups)
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

// CPU data in: own ROM directly, shared bus otherwise; interrupt acknowledge reads FF
always_comb begin
    for (int i = 0; i < 3; i++) begin
        if (~cpu_iorq_n[i])                 cpu_di[i] = 8'hFF;
        else if (cpu_a[i][15:14] == 2'b00)  cpu_di[i] = rom_q[i];
        else                                cpu_di[i] = shared_q[i];
    end
end

//------------------------------------------------------- Latches, interrupts, watchdog ---------------------------------------//

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

// Gatsbee: extra LS259 at 0000-0007 (mirror 3FF8), Q0 = character bank
always @(posedge clk) begin
    if (sys_reset) gat_bank <= 1'b0;
    else if (bwr & cs_xlatch & ba[2:0] == 3'd0) gat_bank <= bdo[0];
end

// Dig Dug EAROM (ER2055, 64 x 8, per MAME er2055.cpp). B800-B83F writes load the address and data latch and reads
// return the latch; B840 = {CS1, C2, /C1, CK}. A control change while selected, or a CK falling edge while selected,
// performs the mode: write (C1 = C2 = 0) ANDs the latch into the cell, erase (C2) sets FF; read (C1, on CK fall) loads
// the latch from the cell.
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

// watchdog: 8 vblanks without a write to 6830 resets the board
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

// main / sub IRQ: asserted at vblank while enabled, held until the enable bit is cleared
reg irq1 = 1'b0, irq2 = 1'b0;
always @(posedge clk) begin
    if (~misc_latch[0])  irq1 <= 1'b0;
    else if (vblank_start) irq1 <= 1'b1;
    if (~misc_latch[1])  irq2 <= 1'b0;
    else if (vblank_start) irq2 <= 1'b1;
end

// sound CPU NMI: lines 64 and 192 (MAME), held for one CPU cycle while NMION (Q2) is low
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

//------------------------------------------------------- Namco customs ------------------------------------------------------//

wire [3:0] n06_chipsel;
wire       n06_rw0;
wire [7:0] n06_chip_dout;
wire [3:0] n06_chip_wr;
wire [7:0] n51_q;
wire       mcu_reset_n = ~sys_reset & misc_latch[3];

// Xevious only: 06xx base tick anchored to MAME screen time 0 (raw x 0, y 0), so the per-frame 51xx poll ends
// before the main CPU's 50xx request. Other boards keep the free-running tick they were verified with.
wire n06_sync = v_xev && ce6 && hcnt == 9'h0F0 && vcnt == 9'd16;

namco_06xx n06
(
    .clk(clk),
    .reset(sys_reset),
    .pause(pause),
    .sync(n06_sync),
    .cpu_dout(bdo),
    .data_wr(bwr & cs_06xx & ~ba[8]),
    .data_rd(brd & cs_06xx & ~ba[8]),
    .ctrl_wr(bwr & cs_06xx & ba[8]),
    .ctrl_rd(cs_06xx & ba[8]),
    .cpu_din(n06_q),
    .nmi_n(n06_nmi_n),
    .chipsel(n06_chipsel),
    .rw0(n06_rw0),
    .chip0_din(n51_q),
    .chip1_din(v_dd ? n53_q : 8'hFF),
    .chip2_din((v_xev | v_bo) ? n50_q : 8'hFF),
    .chip3_din(8'hFF),
    .chip_dout(n06_chip_dout),
    .chip_wr(n06_chip_wr)
);

namco_51xx n51
(
    .clk(clk),
    .ena(ce_mcu),
    .reset_n(mcu_reset_n),
    .chip_sel(n06_chipsel[0]),
    .rw_in(n06_rw0),
    .data_out(n51_q),
    .wr_en(n06_chip_wr[0]),
    .wr_data(n06_chip_dout),
    .in_a(in0),
    .in_b(in1),
    .p_port_out(),
    .rom_wr(ioctl_wr0 & mcu51_cs),
    .rom_addr_in(ioctl_addr[9:0]),
    .rom_data_in(ioctl_dout),
    .vblank(video_vblank)
);

// Xevious: 50xx on 06xx chip 2
namco_50xx n50
(
    .clk(clk),
    .ena(ce_mcu),
    .reset_n(mcu_reset_n),
    .chip_sel(n06_chipsel[2] & (v_xev | v_bo)),
    .rw_in(n06_rw0),
    .data_out(n50_q),
    .wr_en(n06_chip_wr[2] & (v_xev | v_bo)),
    .wr_data(n06_chip_dout),
    .rom_wr(ioctl_wr0 & mcu50_cs),
    .rom_addr_in(ioctl_addr[10:0]),
    .rom_data_in(ioctl_dout)
);

// Dig Dug: 53xx DIP reader on 06xx chip 1; K3-K1 = misc latch Q7-Q5

namco_53xx n53
(
    .clk(clk),
    .ena(ce_mcu),
    .reset_n(mcu_reset_n),
    .chip_sel(n06_chipsel[1] & v_dd),
    .data_out(n53_q),
    .k_in({misc_latch[7:5], 1'b0}),
    .in_a(dswa),
    .in_b(dswb),
    .rom_wr(ioctl_wr0 & mcu53_cs),
    .rom_addr_in(ioctl_addr[9:0]),
    .rom_data_in(ioctl_dout)
);

wire [3:0] n54_o0, n54_o1, n54_r1;

namco_54xx n54
(
    .clk(clk),
    .ena(ce_mcu),
    .reset_n(mcu_reset_n),
    .chip_sel(n06_chipsel[3] & has_54xx),
    .wr_en(n06_chip_wr[3] & has_54xx),
    .wr_data(n06_chip_dout),
    .discrete_o0(n54_o0),
    .discrete_o1(n54_o1),
    .discrete_r1(n54_r1),
    .rom_wr(ioctl_wr0 & mcu54_cs),
    .rom_addr_in(ioctl_addr[9:0]),
    .rom_data_in(ioctl_dout)
);

//------------------------------------------------------- Sound -------------------------------------------------------------//

wire signed [15:0] wsg_audio, n54_audio;

namco_wsg3 wsg
(
    .clk(clk),
    .reset(sys_reset),
    .pause(pause),
    .reg_addr(ba[4:0]),
    .reg_data(bdo[3:0]),
    .reg_wr(bwr & cs_wsg),
    .wave_addr(ioctl_addr[7:0]),
    .wave_data(ioctl_dout),
    .wave_wr(ioctl_wr0 & wave_cs),
    .audio(wsg_audio)
);

//------------------------------------------------------- Bosconian: second 06xx, 50xx, 52xx ----------------------------------//

// 06xx clocked at MASTER / 6 / 512 (MAME: "should be hblank, but approx with 512"), NMI to the sub CPU;
// chip 0 = second 50xx, chip 1 = 52xx. Both reset by video latch Q7.
wire [3:0] n06b_chipsel;
wire       n06b_rw0;
wire [7:0] n06b_chip_dout;
wire [3:0] n06b_chip_wr;
wire [7:0] n50b_q;
wire       vreset_n = ~sys_reset & video_latch[7];

namco_06xx #(.BASE_DIV(8192)) n06b
(
    .clk(clk),
    .reset(sys_reset | ~v_bo),
    .pause(pause),
    .sync(n06_sync),
    .cpu_dout(bdo),
    .data_wr(bwr & cs_06xx1 & ~ba[8]),
    .data_rd(brd & cs_06xx1 & ~ba[8]),
    .ctrl_wr(bwr & cs_06xx1 & ba[8]),
    .ctrl_rd(cs_06xx1 & ba[8]),
    .cpu_din(n06b_q),
    .nmi_n(n06b_nmi_n),
    .chipsel(n06b_chipsel),
    .rw0(n06b_rw0),
    .chip0_din(n50b_q),
    .chip1_din(8'hFF),
    .chip2_din(8'hFF),
    .chip3_din(8'hFF),
    .chip_dout(n06b_chip_dout),
    .chip_wr(n06b_chip_wr)
);

namco_50xx n50b
(
    .clk(clk),
    .ena(ce_mcu),
    .reset_n(vreset_n),
    .chip_sel(n06b_chipsel[0]),
    .rw_in(n06b_rw0),
    .data_out(n50b_q),
    .wr_en(n06b_chip_wr[0]),
    .wr_data(n06b_chip_dout),
    .rom_wr(ioctl_wr0 & mcu50_cs),
    .rom_addr_in(ioctl_addr[10:0]),
    .rom_data_in(ioctl_dout)
);

// 52xx speech: SI = GND (A12-A15 are active-low chip selects of the three 4K ROMs), TC = 555 astable
// (33k, 10k, 4.7 nF: 172.6 us = 8485 clocks)
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
    else begin              sp_rd = {2'd3, n52_addr[11:0]}; sp_ff = 1'b1; end      // fourth select: no ROM
end
reg sp_ff_d;
always @(posedge clk) sp_ff_d <= sp_ff;

dpram_dc #(.widthad_a(14)) speech_rom
(
    .clock_a(clk), .address_a(sp_rd), .data_a(8'h00), .wren_a(1'b0), .q_a(sp_q),
    .clock_b(clk), .address_b(ioctl_addr[13:0] - 14'h0000), .data_b(ioctl_dout), .wren_b(ioctl_wr0 & speech_cs), .q_b()
);

reg [13:0] t555 = 14'd0;
always @(posedge clk) t555 <= (t555 == 14'd8484) ? 14'd0 : t555 + 14'd1;
wire n52_tc_n = ~(t555 < 14'd256);

namco_52xx n52
(
    .clk(clk),
    .ena(ce_mcu),
    .reset_n(vreset_n),
    .chip_sel(n06b_chipsel[1]),
    .wr_en(n06b_chip_wr[1]),
    .wr_data(n06b_chip_dout),
    .si(1'b0),
    .tc_n(n52_tc_n),
    .p_out(n52_p),
    .sample_addr(n52_addr),
    .sample_data(sp_ff_d ? 8'hFF : sp_q),
    .rom_wr(ioctl_wr0 & mcu52_cs),
    .rom_addr_in(ioctl_addr[9:0]),
    .rom_data_in(ioctl_dout)
);

wire signed [31:0] n52_volts;
namco_52xx_snd n52_snd
(
    .clk(clk),
    .reset(sys_reset | ~v_bo),
    .pause(pause),
    .p_data(n52_p),
    .volts(n52_volts)
);

namco_54xx_snd #(.BOARD(0)) n54_snd
(
    .clk(clk),
    .reset(sys_reset),
    .pause(pause),
    .o0_data(n54_o0),
    .o1_data(n54_o1),
    .r1_data(n54_r1),
    .bosco(v_bo),
    .ext_volts(n52_volts),
    .audio(n54_audio)
);

wire signed [15:0] n54_gated = has_54xx ? n54_audio : 16'sd0;
wire signed [16:0] mix = wsg_audio + n54_gated;
assign audio = (mix > 17'sd32767) ? 16'sh7FFF : (mix < -17'sd32768) ? 16'sh8000 : mix[15:0];

endmodule
