//============================================================================
//  namco_54xx.sv — Namco 54xx noise-generator MCU wrapper (tire screech / horn)
//
//  Ground truth: Useful Stuff/mame/namco54.cpp (namco_54xx_device) +
//  Useful Stuff/mame/polepos.cpp machine_config (:908-910, :922-923, :938).
//  MB8844 4-bit MCU (rtl/cpu/mb88_sv/mb88.sv) + its 0x400 internal mask ROM
//  (ioctl index 6, offset 0x800-0xBFF, 54xx.bin crc ee7357e0 -- already
//  loaded by the .mra, see poleposition.vhd's mcu_rom_* comment).
//
//  polepos machine_config port wiring (namco54.cpp):
//    K3:0     = command[7:4]  (K_r() = m_latched_cmd >> 4)
//    R0       = command[3:0]  (R0_r() = m_latched_cmd & 0x0f)
//    O-port   = discrete circuit inputs NAMCO_54XX_0_DATA (ol, O0-O3) /
//               NAMCO_54XX_1_DATA (oh, O4-O7)
//    R1(out)  = discrete circuit input NAMCO_54XX_2_DATA
//    reset    = LS259 q1 (namco_reset, shared with 51/52/53xx)
//    chip_sel = 06xx chipsel[3] -> IRQ
//  UNLIKE 51xx: namco54.cpp has NO read() method and polepos.cpp binds no
//  read_callback<3> at all -- the Z80 never reads this chip back through 06xx,
//  so (a) there is no data_out port here, and existing chip23_din=0xFF stub in
//  poleposition.vhd already matches MAME's unbound-callback default exactly;
//  (b) the command latch is a simple one-way write, no shared-mailbox dance
//  needed (unlike 51xx's O-port/Z80-write shared register).
//  discrete_o0/o1/r1 (the three 4-bit outputs feeding MAME's analog "discrete"
//  circuit) are exposed but NOT wired to real audio synthesis yet -- that
//  circuit (op-amp filter network) is a separate follow-up, same as
//  PolePosition_CPU.sv's engine_dout/engine_lsb_wr/engine_msb_wr TODO.
//============================================================================
`default_nettype none

module namco_54xx
(
    input  wire        clk,        // fabric clock (CLK_49M)
    input  wire        ena,        // MCU clock enable = clk_sys/32 = 1.536 MHz (MASTER_CLOCK/8/2)
    input  wire        reset_n,    // = ~system_reset & namco_reset (LS259 q1)

    // ---- 06xx bus-side (write-only from the Z80's perspective; see header) --
    input  wire        chip_sel,   // chipsel[3]: active-high IRQ/select pulse
    input  wire        wr_en,      // 06xx chip_wr[3] strobe (data_w broadcast, write-mode+selected)
    input  wire  [7:0] wr_data,

    // ---- discrete circuit inputs (namco54.cpp O_w/R1_w) -- UNCONNECTED downstream,
    //      no analog filter network modeled yet ------------------------------
    output wire  [3:0] discrete_o0,   // O0-O3 (mem_mask 0x0f half) -> NAMCO_54XX_0_DATA
    output wire  [3:0] discrete_o1,   // O4-O7 (mem_mask 0xf0 half) -> NAMCO_54XX_1_DATA
    output wire  [3:0] discrete_r1,   // R1 out                     -> NAMCO_54XX_2_DATA

    // ---- 0x400 mask ROM load (write strobe already decoded by the board) --
    input  wire        rom_wr,
    input  wire  [9:0] rom_addr_in,
    input  wire  [7:0] rom_data_in
);

    // ---- command latch (namco54.cpp write()->write_sync(), simple one-way) --
    reg [7:0] latched_cmd;
    always @(posedge clk) begin
        if (!reset_n) latched_cmd <= 8'h00;
        else if (wr_en) latched_cmd <= wr_data;
    end

    // ---- K-port: command upper nibble; R0: command lower nibble ------------
    wire [3:0] k_in  = latched_cmd[7:4];
    wire [3:0] r0_in = latched_cmd[3:0];
    wire [3:0] r1_in = 4'h0;  // R1 is output-only here (namco54.cpp never sets read_r<1>)
    wire [3:0] r2_in = 4'h0, r3_in = 4'h0;  // unused (no read_r<2>/<3> bound)
    wire [3:0] r0_out_unused, r2_out_unused, r3_out_unused;
    wire [3:0] r1_out;
    wire [3:0] p_out_unused;

    wire [3:0] oh_w, ol_w;
    assign discrete_o0 = ol_w;
    assign discrete_o1 = oh_w;
    assign discrete_r1 = r1_out;

    wire [10:0] rom_addr;
    wire  [7:0] rom_data;

    mb88 #(.IRQ_ENTRY_STALL(3)) u_mcu   // IRQ-ENTRY-STALL-2026-09-23: MAME-exact entry, see mb88_core.sv
    (
        .clock      (clk),
        .ena        (ena),
        .reset_n    (reset_n),

        .r0_port_in (r0_in), .r1_port_in (r1_in), .r2_port_in (r2_in), .r3_port_in (r3_in),
        .r0_port_out(r0_out_unused), .r1_port_out(r1_out),
        .r2_port_out(r2_out_unused), .r3_port_out(r3_out_unused),
        .k_port_in  (k_in),
        .ol_port_out(ol_w), .oh_port_out(oh_w),
        .p_port_out (p_out_unused),

        .stby_n     (1'b1),
        .tc_n       (1'b1),      // no external clock source bound for 54xx in polepos.cpp
        .irq_n      (~chip_sel),
        .sc_in_n    (1'b1),
        .si_n       (1'b1),
        .sc_out_n   (),
        .so_n       (),
        .to_n       (),

        .rom_addr   (rom_addr),
        .rom_data   (rom_data)
    );

    // ---- 0x400 internal MCU ROM -------------------------------------------
    dpram_dc #(.widthad_a(10)) rom_54xx
    (
        .clock_a  (clk), .address_a(rom_addr[9:0]), .data_a(8'h00), .wren_a(1'b0), .q_a(rom_data),
        .clock_b  (clk), .address_b(rom_addr_in[9:0]), .data_b(rom_data_in),
        .wren_b   (rom_wr), .q_b()
    );

endmodule

`default_nettype wire
