//============================================================================
//
//  Namco Galaga-family dispatcher: ROM load map, shared CPU / custom chip / sound chip / ROM / RAM pools, and the
//  board (rtl/boards/galaga/galaga_cpu.sv: the CPU board, carrying the Galaga / Dig Dug, Xevious and Bosconian
//  video boards). Games: Galaga, Dig Dug, Xevious, Bosconian.
//
//  Memory maps, interrupt and custom-chip wiring per MAME galaga.cpp
//  (Nicola Salmoria); video counters after Dar's (darfpga) Galaga core.
//
//============================================================================

module galaga_dispatcher
(
    input               clk,            // 49.152 MHz
    input               reset,
    input               pause,
    input               crt_flip,
    input  signed [3:0] h_adj,          // CRT position: HSYNC moved 2 pixels per step
    input  signed [3:0] v_adj,          //               VSYNC moved 1 line per step
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

wire v_dd = variant == 8'd3 || variant == 8'd4;

//------------------------------------------------------- ROM load map --------------------------------------------------------//

// Layout in rtl/ram_rom/rom_loader.sv. Every ROM block below is loaded by ioctl index 0 address only.
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

wire        gfx1_wr  = ioctl_wr0 & gfx1_cs;
wire        gfx2_wr  = ioctl_wr0 & gfx2_cs;
wire        gfx3_wr  = ioctl_wr0 & gfx3_cs;
wire        gfx4_wr  = ioctl_wr0 & gfx4_cs;
wire        prom_wr  = ioctl_wr0 & prom_cs;
wire [17:0] g3_off   = ioctl_addr[17:0] - 18'h18000;          // offset into gfx3
wire [17:0] g3_hi    = g3_off - 18'h05000;
wire [11:0] prom_off = ioctl_addr[11:0];

/////////////////////////////  Shared CPU / custom chip / sound chip pool  /////////////////////////////

// One board family, one game at a time: every CPU, MCU, Namco custom and sound chip is instanced once here and the
// board drives it (rtl/chip_pool_pkg.sv buses). Exception to the pool's core-reset rule: the Z80s, MB88s and customs
// take the board's reset lines (watchdog, RAM clear, misc latch Q3, video latch Q7) on their buses.

// z80_0: main CPU, z80_1: sub CPU, z80_2: sub 2 (sound) CPU - every game
chip_pool_pkg::z80r_i_t [2:0] z80_i;
chip_pool_pkg::z80r_o_t [2:0] z80_o;

wire [15:0] z80_0_a, z80_1_a, z80_2_a;
wire  [7:0] z80_0_do, z80_1_do, z80_2_do;
wire        z80_0_m1_n, z80_0_mreq_n, z80_0_iorq_n, z80_0_rd_n, z80_0_wr_n, z80_0_rfsh_n;
wire        z80_1_m1_n, z80_1_mreq_n, z80_1_iorq_n, z80_1_rd_n, z80_1_wr_n, z80_1_rfsh_n;
wire        z80_2_m1_n, z80_2_mreq_n, z80_2_iorq_n, z80_2_rd_n, z80_2_wr_n, z80_2_rfsh_n;

T80se #(.Mode(0), .T2Write(0), .IOWait(1)) z80_0
(
    .RESET_n(z80_i[0].reset_n), .CLK_n(clk), .CLKEN(z80_i[0].ce), .WAIT_n(1'b1), .INT_n(z80_i[0].int_n), .NMI_n(z80_i[0].nmi_n), .BUSRQ_n(1'b1),
    .M1_n(z80_0_m1_n), .MREQ_n(z80_0_mreq_n), .IORQ_n(z80_0_iorq_n), .RD_n(z80_0_rd_n), .WR_n(z80_0_wr_n), .RFSH_n(z80_0_rfsh_n),
    .HALT_n(), .BUSAK_n(), .A(z80_0_a), .DI(z80_i[0].di), .DO(z80_0_do)
);

assign z80_o[0].a = z80_0_a;           assign z80_o[0].dout = z80_0_do;
assign z80_o[0].m1_n = z80_0_m1_n;     assign z80_o[0].mreq_n = z80_0_mreq_n; assign z80_o[0].iorq_n = z80_0_iorq_n;
assign z80_o[0].rd_n = z80_0_rd_n;     assign z80_o[0].wr_n = z80_0_wr_n;     assign z80_o[0].rfsh_n = z80_0_rfsh_n;

T80se #(.Mode(0), .T2Write(0), .IOWait(1)) z80_1
(
    .RESET_n(z80_i[1].reset_n), .CLK_n(clk), .CLKEN(z80_i[1].ce), .WAIT_n(1'b1), .INT_n(z80_i[1].int_n), .NMI_n(z80_i[1].nmi_n), .BUSRQ_n(1'b1),
    .M1_n(z80_1_m1_n), .MREQ_n(z80_1_mreq_n), .IORQ_n(z80_1_iorq_n), .RD_n(z80_1_rd_n), .WR_n(z80_1_wr_n), .RFSH_n(z80_1_rfsh_n),
    .HALT_n(), .BUSAK_n(), .A(z80_1_a), .DI(z80_i[1].di), .DO(z80_1_do)
);

assign z80_o[1].a = z80_1_a;           assign z80_o[1].dout = z80_1_do;
assign z80_o[1].m1_n = z80_1_m1_n;     assign z80_o[1].mreq_n = z80_1_mreq_n; assign z80_o[1].iorq_n = z80_1_iorq_n;
assign z80_o[1].rd_n = z80_1_rd_n;     assign z80_o[1].wr_n = z80_1_wr_n;     assign z80_o[1].rfsh_n = z80_1_rfsh_n;

T80se #(.Mode(0), .T2Write(0), .IOWait(1)) z80_2
(
    .RESET_n(z80_i[2].reset_n), .CLK_n(clk), .CLKEN(z80_i[2].ce), .WAIT_n(1'b1), .INT_n(z80_i[2].int_n), .NMI_n(z80_i[2].nmi_n), .BUSRQ_n(1'b1),
    .M1_n(z80_2_m1_n), .MREQ_n(z80_2_mreq_n), .IORQ_n(z80_2_iorq_n), .RD_n(z80_2_rd_n), .WR_n(z80_2_wr_n), .RFSH_n(z80_2_rfsh_n),
    .HALT_n(), .BUSAK_n(), .A(z80_2_a), .DI(z80_i[2].di), .DO(z80_2_do)
);

assign z80_o[2].a = z80_2_a;           assign z80_o[2].dout = z80_2_do;
assign z80_o[2].m1_n = z80_2_m1_n;     assign z80_o[2].mreq_n = z80_2_mreq_n; assign z80_o[2].iorq_n = z80_2_iorq_n;
assign z80_o[2].rd_n = z80_2_rd_n;     assign z80_o[2].wr_n = z80_2_wr_n;     assign z80_o[2].rfsh_n = z80_2_rfsh_n;

// Namco customs (the board wires them to its 06xx's chip slots):
//   n06_0: main 06xx (every game)                    n06_1: second 06xx, MASTER / 6 / 512 (Bosconian)
//   n51_0: 51xx inputs / coins (every game)          n50_0: 50xx on n06_0 (Xevious, Bosconian)
//   n54_0: 54xx noise (Galaga, Xevious, Bosconian)   n50_1: 50xx on n06_1 (Bosconian)
//   n53_0: 53xx DIP reader (Dig Dug)                 n52_0: 52xx speech (Bosconian)
// Each 5Nxx custom is an MB88 from the mb88 pool below plus its own mask ROM.
chip_pool_pkg::namco_06xx_i_t n06_0_i, n06_1_i;
chip_pool_pkg::namco_06xx_o_t n06_0_o, n06_1_o;
chip_pool_pkg::namco_50xx_i_t n50_0_i, n50_1_i;
chip_pool_pkg::namco_50xx_o_t n50_0_o, n50_1_o;
chip_pool_pkg::namco_51xx_i_t n51_0_i;
chip_pool_pkg::namco_51xx_o_t n51_0_o;
chip_pool_pkg::namco_52xx_i_t n52_0_i;
chip_pool_pkg::namco_52xx_o_t n52_0_o;
chip_pool_pkg::namco_53xx_i_t n53_0_i;
chip_pool_pkg::namco_53xx_o_t n53_0_o;
chip_pool_pkg::namco_54xx_i_t n54_0_i;
chip_pool_pkg::namco_54xx_o_t n54_0_o;

namco_06xx n06_0
(
    .clk(clk), .reset(n06_0_i.reset), .pause(pause), .irq_on_access(n06_0_i.irq_on_access),
    .cpu_dout(n06_0_i.cpu_dout), .data_wr(n06_0_i.data_wr), .data_rd(n06_0_i.data_rd), .ctrl_wr(n06_0_i.ctrl_wr),
    .ctrl_rd(n06_0_i.ctrl_rd), .cpu_din(n06_0_o.cpu_din), .nmi_n(n06_0_o.nmi_n),
    .chipsel(n06_0_o.chipsel), .rw0(n06_0_o.rw0), .chip0_din(n06_0_i.chip0_din), .chip1_din(n06_0_i.chip1_din),
    .chip2_din(n06_0_i.chip2_din), .chip3_din(n06_0_i.chip3_din), .chip_dout(n06_0_o.chip_dout), .chip_wr(n06_0_o.chip_wr)
);

namco_06xx #(.BASE_DIV(8192)) n06_1
(
    .clk(clk), .reset(n06_1_i.reset), .pause(pause), .irq_on_access(n06_1_i.irq_on_access),
    .cpu_dout(n06_1_i.cpu_dout), .data_wr(n06_1_i.data_wr), .data_rd(n06_1_i.data_rd), .ctrl_wr(n06_1_i.ctrl_wr),
    .ctrl_rd(n06_1_i.ctrl_rd), .cpu_din(n06_1_o.cpu_din), .nmi_n(n06_1_o.nmi_n),
    .chipsel(n06_1_o.chipsel), .rw0(n06_1_o.rw0), .chip0_din(n06_1_i.chip0_din), .chip1_din(n06_1_i.chip1_din),
    .chip2_din(n06_1_i.chip2_din), .chip3_din(n06_1_i.chip3_din), .chip_dout(n06_1_o.chip_dout), .chip_wr(n06_1_o.chip_wr)
);

// MB88 x 5 (Namco custom MCUs, rtl/cpu/mb88_sv), driven by the namco_5Nxx customs:
//   mb88_0: 51xx (every game)
//   mb88_1: 50xx on the main 06xx (Xevious, Bosconian)
//   mb88_2: 54xx (Galaga, Xevious, Bosconian) - IRQ_ENTRY_STALL 3, the 54xx's own setting
//   mb88_3: second 50xx (Bosconian)
//   mb88_4: 52xx (Bosconian), 53xx (Dig Dug)
chip_pool_pkg::mb88_i_t n51_mb88_i, n50_mb88_i, n54_mb88_i, n50b_mb88_i, n52_mb88_i, n53_mb88_i;
chip_pool_pkg::mb88_i_t [4:0] mb88_i;
chip_pool_pkg::mb88_o_t [4:0] mb88_o;

assign mb88_i[0] = n51_mb88_i;
assign mb88_i[1] = n50_mb88_i;
assign mb88_i[2] = n54_mb88_i;
assign mb88_i[3] = n50b_mb88_i;
assign mb88_i[4] = v_dd ? n53_mb88_i : n52_mb88_i;

genvar mi;
generate
    for (mi = 0; mi < 5; mi = mi + 1) begin : g_mb88
        chip_pool_pkg::mb88_i_t i;
        assign i = mb88_i[mi];
        wire  [3:0] r0, r1, r2, r3, ol, oh, p;
        wire        o_wr;
        wire [10:0] rom_a;
        mb88 #(.IRQ_ENTRY_STALL(mi == 2 ? 3 : 0)) mb88
        (
            .clock(clk), .ena(i.ena), .reset_n(i.reset_n), .ram_clr(reset),
            .r0_port_in(i.r_in[3:0]), .r1_port_in(i.r_in[7:4]), .r2_port_in(i.r_in[11:8]), .r3_port_in(i.r_in[15:12]),
            .r0_port_out(r0), .r1_port_out(r1), .r2_port_out(r2), .r3_port_out(r3),
            .k_port_in(i.k), .ol_port_out(ol), .oh_port_out(oh), .o_wr(o_wr), .p_port_out(p),
            .stby_n(1'b1), .tc_n(i.tc_n), .irq_n(i.irq_n), .sc_in_n(1'b1), .si_n(i.si_n),
            .sc_out_n(), .so_n(), .to_n(),
            .rom_addr(rom_a), .rom_data(i.rom_d)
        );
        assign mb88_o[mi].r_out = {r3, r2, r1, r0};
        assign mb88_o[mi].o     = {oh, ol};
        assign mb88_o[mi].o_wr  = o_wr;
        assign mb88_o[mi].p     = p;
        assign mb88_o[mi].rom_a = rom_a;
    end
endgenerate

namco_51xx n51_0
(
    .clk(clk), .ena(n51_0_i.ena), .reset_n(n51_0_i.reset_n), .chip_sel(n51_0_i.chip_sel), .rw_in(n51_0_i.rw_in),
    .data_out(n51_0_o.data_out), .wr_en(n51_0_i.wr_en), .wr_data(n51_0_i.wr_data), .in_a(n51_0_i.in_a),
    .in_b(n51_0_i.in_b), .p_port_out(n51_0_o.p_port_out), .vblank(n51_0_i.vblank),
    .rom_wr(ioctl_wr0 & mcu51_cs), .rom_addr_in(ioctl_addr[9:0]), .rom_data_in(ioctl_dout),
    .mb88_i(n51_mb88_i), .mb88_o(mb88_o[0])
);

namco_50xx n50_0
(
    .clk(clk), .ena(n50_0_i.ena), .reset_n(n50_0_i.reset_n), .chip_sel(n50_0_i.chip_sel), .rw_in(n50_0_i.rw_in),
    .data_out(n50_0_o.data_out), .wr_en(n50_0_i.wr_en), .wr_data(n50_0_i.wr_data),
    .rom_wr(ioctl_wr0 & mcu50_cs), .rom_addr_in(ioctl_addr[10:0]), .rom_data_in(ioctl_dout),
    .mb88_i(n50_mb88_i), .mb88_o(mb88_o[1])
);

namco_53xx n53_0
(
    .clk(clk), .ena(n53_0_i.ena), .reset_n(n53_0_i.reset_n), .chip_sel(n53_0_i.chip_sel),
    .data_out(n53_0_o.data_out), .k_in(n53_0_i.k_in), .in_a(n53_0_i.in_a), .in_b(n53_0_i.in_b),
    .rom_wr(ioctl_wr0 & mcu53_cs), .rom_addr_in(ioctl_addr[9:0]), .rom_data_in(ioctl_dout),
    .mb88_i(n53_mb88_i), .mb88_o(mb88_o[4])
);

namco_54xx n54_0
(
    .clk(clk), .ena(n54_0_i.ena), .reset_n(n54_0_i.reset_n), .chip_sel(n54_0_i.chip_sel), .wr_en(n54_0_i.wr_en),
    .wr_data(n54_0_i.wr_data), .discrete_o0(n54_0_o.discrete_o0), .discrete_o1(n54_0_o.discrete_o1),
    .discrete_r1(n54_0_o.discrete_r1),
    .rom_wr(ioctl_wr0 & mcu54_cs), .rom_addr_in(ioctl_addr[9:0]), .rom_data_in(ioctl_dout),
    .mb88_i(n54_mb88_i), .mb88_o(mb88_o[2])
);

namco_50xx n50_1
(
    .clk(clk), .ena(n50_1_i.ena), .reset_n(n50_1_i.reset_n), .chip_sel(n50_1_i.chip_sel), .rw_in(n50_1_i.rw_in),
    .data_out(n50_1_o.data_out), .wr_en(n50_1_i.wr_en), .wr_data(n50_1_i.wr_data),
    .rom_wr(ioctl_wr0 & mcu50_cs), .rom_addr_in(ioctl_addr[10:0]), .rom_data_in(ioctl_dout),
    .mb88_i(n50b_mb88_i), .mb88_o(mb88_o[3])
);

namco_52xx n52_0
(
    .clk(clk), .ena(n52_0_i.ena), .reset_n(n52_0_i.reset_n), .chip_sel(n52_0_i.chip_sel), .wr_en(n52_0_i.wr_en),
    .wr_data(n52_0_i.wr_data), .si(n52_0_i.si), .tc_n(n52_0_i.tc_n), .p_out(n52_0_o.p_out),
    .sample_addr(n52_0_o.sample_addr), .sample_data(n52_0_i.sample_data),
    .rom_wr(ioctl_wr0 & mcu52_cs), .rom_addr_in(ioctl_addr[9:0]), .rom_data_in(ioctl_dout),
    .mb88_i(n52_mb88_i), .mb88_o(mb88_o[4])
);

// 05xx starfield: Galaga (galaga_video), Bosconian (bosco_video)
chip_pool_pkg::namco_05xx_i_t n05_0_i;
chip_pool_pkg::namco_05xx_o_t n05_0_o;

namco_05xx n05_0
(
    .clk(clk), .ce6(n05_0_i.ce6), .pause(pause), .line_step(n05_0_i.line_step), .vcnt(n05_0_i.vcnt),
    .win(n05_0_i.win), .speed_x(n05_0_i.speed_x), .speed_y(n05_0_i.speed_y), .set_a(n05_0_i.set_a),
    .set_b(n05_0_i.set_b), .enable(n05_0_i.enable), .star(n05_0_o.star), .color(n05_0_o.color)
);

// sound: WSG (every game), 54xx noise / discrete mixer (Galaga, Xevious, Bosconian), 52xx voice chain (Bosconian)
chip_pool_pkg::namco_wsg3_i_t     wsg_0_i;
chip_pool_pkg::namco_wsg3_o_t     wsg_0_o;
chip_pool_pkg::namco_52xx_snd_i_t n52snd_0_i;
chip_pool_pkg::namco_52xx_snd_o_t n52snd_0_o;
chip_pool_pkg::namco_54xx_snd_i_t n54snd_0_i;
chip_pool_pkg::namco_54xx_snd_o_t n54snd_0_o;

namco_wsg3 wsg_0
(
    .clk(clk), .reset(wsg_0_i.reset), .pause(pause), .reg_addr(wsg_0_i.reg_addr), .reg_data(wsg_0_i.reg_data),
    .reg_wr(wsg_0_i.reg_wr), .wave_addr(ioctl_addr[7:0]), .wave_data(ioctl_dout), .wave_wr(ioctl_wr0 & wave_cs),
    .audio(wsg_0_o.audio)
);

namco_52xx_snd n52snd_0
(
    .clk(clk), .reset(n52snd_0_i.reset), .pause(pause), .p_data(n52snd_0_i.p_data), .volts(n52snd_0_o.volts)
);

namco_54xx_snd #(.BOARD(0)) n54snd_0
(
    .clk(clk), .reset(n54snd_0_i.reset), .pause(pause), .o0_data(n54snd_0_i.o0_data), .o1_data(n54snd_0_i.o1_data),
    .r1_data(n54snd_0_i.r1_data), .bosco(n54snd_0_i.bosco), .ext_volts(n54snd_0_i.ext_volts), .audio(n54snd_0_o.audio)
);

/////////////////////////////  Shared ROM blocks  /////////////////////////////
// port A = the board's read, port B = the download (ioctl index 0, decoded by address above). A block shared by the
// video boards holds the same bytes whichever of them reads it (one game loaded at a time).

wire [13:0] main_rom_a, sub_rom_a, sub2_rom_a, gfx2_rom_a, gfx4_rom_a, speech_rom_a;
wire [12:0] gfx1_rom_a, gfx3b_rom_a;
wire [11:0] gfx2b_rom_a;
wire [14:0] gfx3_rom_a;
wire  [9:0] prom0_a, prom1_a;
wire  [7:0] xprom_b_a;
wire  [8:0] xprom_bgl_a, xprom_spl_a;
wire  [7:0] main_rom_d, sub_rom_d, sub2_rom_d, gfx1_rom_d, gfx2_rom_d, gfx2b_rom_d, gfx3_rom_d, gfx3b_rom_d, gfx4_rom_d;
wire  [7:0] prom0_d, prom1_d, xprom_b_d, xprom_bgl_d0, xprom_bgl_d1, xprom_spl_d0, xprom_spl_d1, speech_rom_d;

// program ROMs (0000-3FFF), one per CPU
dpram_dc #(.widthad_a(14)) main_rom
(
    .clock_a(clk), .address_a(main_rom_a), .data_a(8'h00), .wren_a(1'b0), .q_a(main_rom_d),
    .clock_b(clk), .address_b(ioctl_addr[13:0]), .data_b(ioctl_dout), .wren_b(ioctl_wr0 & main_cs & ~ioctl_addr[14]), .q_b()
);

dpram_dc #(.widthad_a(14)) sub_rom
(
    .clock_a(clk), .address_a(sub_rom_a), .data_a(8'h00), .wren_a(1'b0), .q_a(sub_rom_d),
    .clock_b(clk), .address_b(ioctl_addr[13:0]), .data_b(ioctl_dout), .wren_b(ioctl_wr0 & sub_cs), .q_b()
);

dpram_dc #(.widthad_a(14)) sub2_rom
(
    .clock_a(clk), .address_a(sub2_rom_a), .data_a(8'h00), .wren_a(1'b0), .q_a(sub2_rom_d),
    .clock_b(clk), .address_b(ioctl_addr[13:0]), .data_b(ioctl_dout), .wren_b(ioctl_wr0 & sub2_cs), .q_b()
);

// gfx1 characters (8K: Galaga 4K 2bpp, Gatsbee 8K banked, Dig Dug 2K 1bpp, Xevious foreground 4K, Bosconian 4K)
dpram_dc #(.widthad_a(13)) gfx1_rom
(
    .clock_a(clk), .address_a(gfx1_rom_a), .data_a(8'h00), .wren_a(1'b0), .q_a(gfx1_rom_d),
    .clock_b(clk), .address_b(ioctl_addr[12:0]), .data_b(ioctl_dout), .wren_b(gfx1_wr), .q_b()
);

// gfx2 (16K): Galaga / Dig Dug / Bosconian sprites, Xevious background plane 0 (0000-0FFF); plane 1 (1000-1FFF) has
// its own block, read at the same time
dpram_dc #(.widthad_a(14)) gfx2_rom
(
    .clock_a(clk), .address_a(gfx2_rom_a), .data_a(8'h00), .wren_a(1'b0), .q_a(gfx2_rom_d),
    .clock_b(clk), .address_b(ioctl_addr[13:0]), .data_b(ioctl_dout), .wren_b(gfx2_wr), .q_b()
);

dpram_dc #(.widthad_a(12)) gfx2b_rom
(
    .clock_a(clk), .address_a(gfx2b_rom_a), .data_a(8'h00), .wren_a(1'b0), .q_a(gfx2b_rom_d),
    .clock_b(clk), .address_b(ioctl_addr[11:0]), .data_b(ioctl_dout), .wren_b(gfx2_wr && ioctl_addr[13:12] == 2'd1), .q_b()
);

// gfx3 0000-4FFF: Dig Dug playfield characters (0000-0FFF), Bosconian radar dots (0000-00FF), Xevious sprite planes
// 0/1; Xevious sprite plane 2 (5000-6FFF) has its own block, read at the same time
dpram_dc #(.widthad_a(15)) gfx3_rom
(
    .clock_a(clk), .address_a(gfx3_rom_a), .data_a(8'h00), .wren_a(1'b0), .q_a(gfx3_rom_d),
    .clock_b(clk), .address_b(g3_off[14:0]), .data_b(ioctl_dout), .wren_b(gfx3_wr && g3_off < 18'h05000), .q_b()
);

dpram_dc #(.widthad_a(13)) gfx3b_rom
(
    .clock_a(clk), .address_a(gfx3b_rom_a), .data_a(8'h00), .wren_a(1'b0), .q_a(gfx3b_rom_d),
    .clock_b(clk), .address_b(g3_hi[12:0]), .data_b(ioctl_dout), .wren_b(gfx3_wr && g3_hi < 18'h02000), .q_b()
);

// gfx4 (16K): Xevious planet map ROMs 2A / 2B / 2C (board), Dig Dug playfield maps (0000-0FFF)
dpram_dc #(.widthad_a(14)) gfx4_rom
(
    .clock_a(clk), .address_a(gfx4_rom_a), .data_a(8'h00), .wren_a(1'b0), .q_a(gfx4_rom_d),
    .clock_b(clk), .address_b(ioctl_addr[13:0]), .data_b(ioctl_dout), .wren_b(gfx4_wr), .q_b()
);

// "proms" 000-3FF, two copies: Galaga / Dig Dug / Bosconian pixel path + sprite engine, Xevious red (000) + green (100)
dpram_dc #(.widthad_a(10)) prom0
(
    .clock_a(clk), .address_a(prom0_a), .data_a(8'h00), .wren_a(1'b0), .q_a(prom0_d),
    .clock_b(clk), .address_b(ioctl_addr[9:0]), .data_b(ioctl_dout), .wren_b(prom_wr && ioctl_addr[11:10] == 2'b00), .q_b()
);

dpram_dc #(.widthad_a(10)) prom1
(
    .clock_a(clk), .address_a(prom1_a), .data_a(8'h00), .wren_a(1'b0), .q_a(prom1_d),
    .clock_b(clk), .address_b(ioctl_addr[9:0]), .data_b(ioctl_dout), .wren_b(prom_wr && ioctl_addr[11:10] == 2'b00), .q_b()
);

// Xevious: blue (200), background lookup low / high (300 / 500), sprite lookup low / high (700 / 900)
dpram_dc #(.widthad_a(8)) xprom_b
(
    .clock_a(clk), .address_a(xprom_b_a), .data_a(8'h00), .wren_a(1'b0), .q_a(xprom_b_d),
    .clock_b(clk), .address_b(ioctl_addr[7:0]), .data_b(ioctl_dout), .wren_b(prom_wr && ioctl_addr[11:8] == 4'h2), .q_b()
);

dpram_dc #(.widthad_a(9)) xprom_bgl_lo
(
    .clock_a(clk), .address_a(xprom_bgl_a), .data_a(8'h00), .wren_a(1'b0), .q_a(xprom_bgl_d0),
    .clock_b(clk), .address_b(prom_off[8:0] - 9'h100), .data_b(ioctl_dout), .wren_b(prom_wr && prom_off >= 12'h300 && prom_off < 12'h500), .q_b()
);
dpram_dc #(.widthad_a(9)) xprom_bgl_hi
(
    .clock_a(clk), .address_a(xprom_bgl_a), .data_a(8'h00), .wren_a(1'b0), .q_a(xprom_bgl_d1),
    .clock_b(clk), .address_b(prom_off[8:0] - 9'h100), .data_b(ioctl_dout), .wren_b(prom_wr && prom_off >= 12'h500 && prom_off < 12'h700), .q_b()
);

dpram_dc #(.widthad_a(9)) xprom_spl_lo
(
    .clock_a(clk), .address_a(xprom_spl_a), .data_a(8'h00), .wren_a(1'b0), .q_a(xprom_spl_d0),
    .clock_b(clk), .address_b(prom_off[8:0] - 9'h100), .data_b(ioctl_dout), .wren_b(prom_wr && prom_off >= 12'h700 && prom_off < 12'h900), .q_b()
);
dpram_dc #(.widthad_a(9)) xprom_spl_hi
(
    .clock_a(clk), .address_a(xprom_spl_a), .data_a(8'h00), .wren_a(1'b0), .q_a(xprom_spl_d1),
    .clock_b(clk), .address_b(prom_off[8:0] - 9'h100), .data_b(ioctl_dout), .wren_b(prom_wr && prom_off >= 12'h900 && prom_off < 12'hB00), .q_b()
);

// Bosconian 52xx speech samples (three 4K ROMs)
dpram_dc #(.widthad_a(14)) speech_rom
(
    .clock_a(clk), .address_a(speech_rom_a), .data_a(8'h00), .wren_a(1'b0), .q_a(speech_rom_d),
    .clock_b(clk), .address_b(ioctl_addr[13:0]), .data_b(ioctl_dout), .wren_b(ioctl_wr0 & speech_cs), .q_b()
);

/////////////////////////////  Board RAM pool  /////////////////////////////
//   pr 0  4K  tile RAM 8000 (Galaga / Dig Dug), work RAM 7800 (Xevious), video RAM 8000-8FFF (Bosconian); port B video
//   pr 1  2K  RAM 1 (sprite registers +380; Xevious / Bosconian 2K); port B sprite engine
//   pr 2  2K  RAM 2                         pr 3  2K  RAM 3
//   pr 4  2K  Xevious fg colour B000        pr 5  2K  Xevious bg colour B800
//   pr 6  2K  Xevious fg code C000          pr 7  2K  Xevious bg code C800
//   pr 8  1K  sprite line buffer (Galaga / Dig Dug, Xevious, Bosconian)
//   pr 9  1K  Bosconian radar dot line buffer
// Private: the Dig Dug EAROM (64 x 8 registers in the board; its NVRAM port reads asynchronously).
ram_pool_pkg::pram_i_t [9:0] pr_i;
ram_pool_pkg::pram_o_t [9:0] pr_o;

dpram_dc #(.widthad_a(12)) pr_0
(
    .clock_a(clk), .address_a(pr_i[0].a_addr[11:0]), .data_a(pr_i[0].a_d), .wren_a(pr_i[0].a_we), .q_a(pr_o[0].a_q),
    .clock_b(clk), .address_b(pr_i[0].b_addr[11:0]), .data_b(pr_i[0].b_d), .wren_b(pr_i[0].b_we), .q_b(pr_o[0].b_q)
);
dpram_dc #(.widthad_a(11)) pr_1
(
    .clock_a(clk), .address_a(pr_i[1].a_addr[10:0]), .data_a(pr_i[1].a_d), .wren_a(pr_i[1].a_we), .q_a(pr_o[1].a_q),
    .clock_b(clk), .address_b(pr_i[1].b_addr[10:0]), .data_b(pr_i[1].b_d), .wren_b(pr_i[1].b_we), .q_b(pr_o[1].b_q)
);
dpram_dc #(.widthad_a(11)) pr_2
(
    .clock_a(clk), .address_a(pr_i[2].a_addr[10:0]), .data_a(pr_i[2].a_d), .wren_a(pr_i[2].a_we), .q_a(pr_o[2].a_q),
    .clock_b(clk), .address_b(pr_i[2].b_addr[10:0]), .data_b(pr_i[2].b_d), .wren_b(pr_i[2].b_we), .q_b(pr_o[2].b_q)
);
dpram_dc #(.widthad_a(11)) pr_3
(
    .clock_a(clk), .address_a(pr_i[3].a_addr[10:0]), .data_a(pr_i[3].a_d), .wren_a(pr_i[3].a_we), .q_a(pr_o[3].a_q),
    .clock_b(clk), .address_b(pr_i[3].b_addr[10:0]), .data_b(pr_i[3].b_d), .wren_b(pr_i[3].b_we), .q_b(pr_o[3].b_q)
);
dpram_dc #(.widthad_a(11)) pr_4
(
    .clock_a(clk), .address_a(pr_i[4].a_addr[10:0]), .data_a(pr_i[4].a_d), .wren_a(pr_i[4].a_we), .q_a(pr_o[4].a_q),
    .clock_b(clk), .address_b(pr_i[4].b_addr[10:0]), .data_b(pr_i[4].b_d), .wren_b(pr_i[4].b_we), .q_b(pr_o[4].b_q)
);
dpram_dc #(.widthad_a(11)) pr_5
(
    .clock_a(clk), .address_a(pr_i[5].a_addr[10:0]), .data_a(pr_i[5].a_d), .wren_a(pr_i[5].a_we), .q_a(pr_o[5].a_q),
    .clock_b(clk), .address_b(pr_i[5].b_addr[10:0]), .data_b(pr_i[5].b_d), .wren_b(pr_i[5].b_we), .q_b(pr_o[5].b_q)
);
dpram_dc #(.widthad_a(11)) pr_6
(
    .clock_a(clk), .address_a(pr_i[6].a_addr[10:0]), .data_a(pr_i[6].a_d), .wren_a(pr_i[6].a_we), .q_a(pr_o[6].a_q),
    .clock_b(clk), .address_b(pr_i[6].b_addr[10:0]), .data_b(pr_i[6].b_d), .wren_b(pr_i[6].b_we), .q_b(pr_o[6].b_q)
);
dpram_dc #(.widthad_a(11)) pr_7
(
    .clock_a(clk), .address_a(pr_i[7].a_addr[10:0]), .data_a(pr_i[7].a_d), .wren_a(pr_i[7].a_we), .q_a(pr_o[7].a_q),
    .clock_b(clk), .address_b(pr_i[7].b_addr[10:0]), .data_b(pr_i[7].b_d), .wren_b(pr_i[7].b_we), .q_b(pr_o[7].b_q)
);
dpram_dc #(.widthad_a(10)) pr_8
(
    .clock_a(clk), .address_a(pr_i[8].a_addr[9:0]), .data_a(pr_i[8].a_d), .wren_a(pr_i[8].a_we), .q_a(pr_o[8].a_q),
    .clock_b(clk), .address_b(pr_i[8].b_addr[9:0]), .data_b(pr_i[8].b_d), .wren_b(pr_i[8].b_we), .q_b(pr_o[8].b_q)
);
dpram_dc #(.widthad_a(10)) pr_9
(
    .clock_a(clk), .address_a(pr_i[9].a_addr[9:0]), .data_a(pr_i[9].a_d), .wren_a(pr_i[9].a_we), .q_a(pr_o[9].a_q),
    .clock_b(clk), .address_b(pr_i[9].b_addr[9:0]), .data_b(pr_i[9].b_d), .wren_b(pr_i[9].b_we), .q_b(pr_o[9].b_q)
);

/////////////////////////////  Board  /////////////////////////////

galaga_cpu board
(
    .clk(clk), .reset(reset), .pause(pause), .crt_flip(crt_flip), .h_adj(h_adj), .v_adj(v_adj), .variant(variant),
    .in0(in0), .in1(in1), .dswa(dswa), .dswb(dswb),
    .earom_addr(earom_addr), .earom_din(earom_din), .earom_we(earom_we), .earom_dout(earom_dout),
    .ce_pix(ce_pix), .video_r(video_r), .video_g(video_g), .video_b(video_b), .video_hs(video_hs), .video_vs(video_vs),
    .video_hblank(video_hblank), .video_vblank(video_vblank), .audio(audio),
    .hs_access(hs_access), .hs_address(hs_address), .hs_data_in(hs_data_in), .hs_data_out(hs_data_out),
    .hs_write(hs_write),

    .z80_i(z80_i), .z80_o(z80_o),
    .n06_0_i(n06_0_i), .n06_0_o(n06_0_o), .n06_1_i(n06_1_i), .n06_1_o(n06_1_o),
    .n50_0_i(n50_0_i), .n50_0_o(n50_0_o), .n50_1_i(n50_1_i), .n50_1_o(n50_1_o),
    .n51_0_i(n51_0_i), .n51_0_o(n51_0_o), .n52_0_i(n52_0_i), .n52_0_o(n52_0_o),
    .n53_0_i(n53_0_i), .n53_0_o(n53_0_o), .n54_0_i(n54_0_i), .n54_0_o(n54_0_o),
    .wsg_0_i(wsg_0_i), .wsg_0_o(wsg_0_o), .n52snd_0_i(n52snd_0_i), .n52snd_0_o(n52snd_0_o),
    .n54snd_0_i(n54snd_0_i), .n54snd_0_o(n54snd_0_o), .n05_0_i(n05_0_i), .n05_0_o(n05_0_o),

    .main_rom_a(main_rom_a), .main_rom_d(main_rom_d), .sub_rom_a(sub_rom_a), .sub_rom_d(sub_rom_d),
    .sub2_rom_a(sub2_rom_a), .sub2_rom_d(sub2_rom_d), .gfx1_rom_a(gfx1_rom_a), .gfx1_rom_d(gfx1_rom_d),
    .gfx2_rom_a(gfx2_rom_a), .gfx2_rom_d(gfx2_rom_d), .gfx2b_rom_a(gfx2b_rom_a), .gfx2b_rom_d(gfx2b_rom_d),
    .gfx3_rom_a(gfx3_rom_a), .gfx3_rom_d(gfx3_rom_d), .gfx3b_rom_a(gfx3b_rom_a), .gfx3b_rom_d(gfx3b_rom_d),
    .gfx4_rom_a(gfx4_rom_a), .gfx4_rom_d(gfx4_rom_d), .prom0_a(prom0_a), .prom0_d(prom0_d),
    .prom1_a(prom1_a), .prom1_d(prom1_d), .xprom_b_a(xprom_b_a), .xprom_b_d(xprom_b_d),
    .xprom_bgl_a(xprom_bgl_a), .xprom_bgl_d0(xprom_bgl_d0), .xprom_bgl_d1(xprom_bgl_d1),
    .xprom_spl_a(xprom_spl_a), .xprom_spl_d0(xprom_spl_d0), .xprom_spl_d1(xprom_spl_d1),
    .speech_rom_a(speech_rom_a), .speech_rom_d(speech_rom_d),

    .pr_i(pr_i), .pr_o(pr_o)
);

endmodule
