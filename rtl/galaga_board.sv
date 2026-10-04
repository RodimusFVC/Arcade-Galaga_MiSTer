//============================================================================
//
//  Namco Galaga board (CPU board + video board)
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

    input         [7:0] in0,            // 51xx input<0>/<1>
    input         [7:0] in1,            // 51xx input<2>/<3>
    input         [7:0] dswa,
    input         [7:0] dswb,

    input        [24:0] ioctl_addr,
    input         [7:0] ioctl_dout,
    input               ioctl_wr0,      // ioctl index 0

    output              ce_pix,
    output        [7:0] video_r,
    output        [7:0] video_g,
    output        [7:0] video_b,
    output reg          video_hs = 1'b1,
    output reg          video_vs = 1'b1,
    output reg          video_hblank = 1'b1,
    output reg          video_vblank = 1'b1,

    output signed [15:0] audio
);

//------------------------------------------------------- Clock enables -------------------------------------------------------//

// 49.152 MHz / 16 = 3.072 MHz Z80s; / 8 = 6.144 MHz pixel; / 32 = 1.536 MHz Namco MCUs
reg [4:0] ph = 5'd0;
always @(posedge clk) ph <= ph + 5'd1;

wire ce_cpu = (ph[3:0] == 4'd15) & ~pause;
wire ce6    = (ph[2:0] == 3'd7);
wire ce_mcu = (ph == 5'd31) & ~pause;
assign ce_pix = ce6;

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

//------------------------------------------------------- Video timing --------------------------------------------------------//

// H counts 080-1FF (384), V counts 000-107 (264); 60.61 Hz. Visible: H 0C0-1DF wrapped (288), V 010-0EF (224)
reg [8:0] hcnt = 9'h080;
reg [8:0] vcnt = 9'd0;

wire line_step = ce6 & (hcnt == 9'h0BF);

always @(posedge clk) begin
    if (ce6) begin
        hcnt <= (hcnt == 9'h1FF) ? 9'h080 : hcnt + 9'd1;
        if (hcnt == 9'h0BF) vcnt <= (vcnt == 9'd263) ? 9'd0 : vcnt + 9'd1;

        if      (hcnt == 9'h098) video_hblank <= 1'b1;
        else if (hcnt == 9'h0F8) video_hblank <= 1'b0;

        if      (hcnt == 9'h0AF) video_hs <= 1'b0;
        else if (hcnt == 9'h0CC) video_hs <= 1'b1;

        if (hcnt == 9'h0BF) begin
            if      (vcnt == 9'd239) video_vblank <= 1'b1;
            else if (vcnt == 9'd15)  video_vblank <= 1'b0;
            if      (vcnt == 9'd259) video_vs <= 1'b0;
            else if (vcnt == 9'd2)   video_vs <= 1'b1;
        end
    end
end

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
wire [15:0] ba   = own_ok ? cpu_a[own]  : 16'h0000;
wire  [7:0] bdo  = own_ok ? cpu_do[own] : 8'h00;
wire        bmem = own_ok & ~cpu_mreq_n[own] & cpu_rfsh_n[own];
wire        brd  = bmem & ~cpu_rd_n[own];
wire        bwr  = bmem & ~cpu_wr_n[own] & (slot == 2'd0);   // one write strobe per bus cycle

// address decode (galaga.cpp memory map; mirrors as in the CPU board decode table)
wire cs_rom    = ba[15:14] == 2'b00;
wire cs_io     = ba[15:11] == 5'b01101;                          // 6800-6FFF
wire cs_dsw    = cs_io & (ba[5:4] == 2'b00);                     // read 6800-6807
wire cs_wsg    = cs_io & ~ba[5];                                 // write 6800-681F
wire cs_misc   = cs_io & (ba[5:4] == 2'b10);                     // write 6820-6827
wire cs_wdog   = cs_io & (ba[5:4] == 2'b11);                     // write 6830
wire cs_06xx   = ba[15:11] == 5'b01110;                          // 7000-77FF, A8 = 0 data / 1 control
wire cs_vram   = ba[15:11] == 5'b10000;                          // 8000-87FF
wire cs_ram1   = ba[15:11] == 5'b10001;                          // 8800-8FFF (1K mirrored)
wire cs_ram2   = ba[15:11] == 5'b10010;                          // 9000-97FF
wire cs_ram3   = ba[15:11] == 5'b10011;                          // 9800-9FFF
wire cs_vlatch = ba[15:11] == 5'b10100;                          // A000-A7FF

// work / video RAMs (port B reserved for the video and hiscore)
wire  [7:0] vram_q, ram1_q, ram2_q, ram3_q;
wire [10:0] vram_addr_b = 11'd0;
wire  [7:0] vram_q_b;

dpram_dc #(.widthad_a(11)) vram
(
    .clock_a(clk), .address_a(ba[10:0]), .data_a(bdo), .wren_a(bwr & cs_vram), .q_a(vram_q),
    .clock_b(clk), .address_b(vram_addr_b), .data_b(8'h00), .wren_b(1'b0), .q_b(vram_q_b)
);

dpram_dc #(.widthad_a(10)) ram1
(
    .clock_a(clk), .address_a(ba[9:0]), .data_a(bdo), .wren_a(bwr & cs_ram1), .q_a(ram1_q),
    .clock_b(clk), .address_b(10'd0), .data_b(8'h00), .wren_b(1'b0), .q_b()
);

dpram_dc #(.widthad_a(10)) ram2
(
    .clock_a(clk), .address_a(ba[9:0]), .data_a(bdo), .wren_a(bwr & cs_ram2), .q_a(ram2_q),
    .clock_b(clk), .address_b(10'd0), .data_b(8'h00), .wren_b(1'b0), .q_b()
);

dpram_dc #(.widthad_a(10)) ram3
(
    .clock_a(clk), .address_a(ba[9:0]), .data_a(bdo), .wren_a(bwr & cs_ram3), .q_a(ram3_q),
    .clock_b(clk), .address_b(10'd0), .data_b(8'h00), .wren_b(1'b0), .q_b()
);


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
end

reg [7:0] shared_q[3];
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

reg  [7:0] misc_latch = 8'h00;              // 3C LS259: Q0 IRQ1, Q1 IRQ2, Q2 NMION, Q3 RESET, Q5-7 MOD
reg  [7:0] video_latch = 8'h00;             // 5K LS259: Q0-Q5 05xx starfield, Q7 flip
reg  [3:0] wdog = 4'd0;
reg        wdog_reset = 1'b0;

wire sys_reset = reset | wdog_reset;

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
    if (line_step && (vcnt == 9'd79 || vcnt == 9'd207) && ~misc_latch[2]) begin
        nmi3     <= 1'b1;
        nmi3_cnt <= 5'd31;
    end
    else if (nmi3_cnt != 5'd0) nmi3_cnt <= nmi3_cnt - 5'd1;
    else nmi3 <= 1'b0;
end

wire n06_nmi_n;

assign cpu_int_n   = {1'b1, ~irq2, ~irq1};
assign cpu_nmi_n   = {~nmi3, 1'b1, n06_nmi_n};
assign cpu_reset_n = {~sys_reset & misc_latch[3], ~sys_reset & misc_latch[3], ~sys_reset};

wire flip_screen = video_latch[7];

//------------------------------------------------------- Namco customs ------------------------------------------------------//

wire [3:0] n06_chipsel;
wire       n06_rw0;
wire [7:0] n06_chip_dout;
wire [3:0] n06_chip_wr;
wire [7:0] n51_q;
wire       mcu_reset_n = ~sys_reset & misc_latch[3];

namco_06xx n06
(
    .clk(clk),
    .reset(sys_reset),
    .pause(pause),
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
    .chip1_din(8'hFF),
    .chip2_din(8'hFF),
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

wire [3:0] n54_o0, n54_o1, n54_r1;

namco_54xx n54
(
    .clk(clk),
    .ena(ce_mcu),
    .reset_n(mcu_reset_n),
    .chip_sel(n06_chipsel[3]),
    .wr_en(n06_chip_wr[3]),
    .wr_data(n06_chip_dout),
    .discrete_o0(n54_o0),
    .discrete_o1(n54_o1),
    .discrete_r1(n54_r1),
    .rom_wr(ioctl_wr0 & mcu54_cs),
    .rom_addr_in(ioctl_addr[9:0]),
    .rom_data_in(ioctl_dout)
);

//------------------------------------------------------- Video / sound (to come) ---------------------------------------------//

assign video_r = 8'd0;
assign video_g = 8'd0;
assign video_b = 8'd0;
assign audio   = 16'sd0;

endmodule
