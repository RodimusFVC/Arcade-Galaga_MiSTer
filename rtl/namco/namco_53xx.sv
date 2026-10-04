//============================================================================
//
//  Namco 53xx multiplexed input reader: MB8843 MCU running its 0x400 mask ROM
//
//  Per MAME namco53.cpp. Read-only from the CPU side: the 06xx read returns
//  the O port. K and R0-R3 come from the board.
//
//============================================================================
`default_nettype none

module namco_53xx
(
    input  wire        clk,
    input  wire        ena,        // MCU clock enable, 256 kHz machine cycles
    input  wire        reset_n,

    // 06xx side
    input  wire        chip_sel,   // select pulse -> MCU IRQ
    output wire  [7:0] data_out,

    input  wire  [3:0] k_in,
    input  wire  [7:0] in_a,       // input<0> = in_a[3:0], input<1> = in_a[7:4]
    input  wire  [7:0] in_b,       // input<2> = in_b[3:0], input<3> = in_b[7:4]

    // 0x400 mask ROM load (write strobe already decoded by the board)
    input  wire        rom_wr,
    input  wire  [9:0] rom_addr_in,
    input  wire  [7:0] rom_data_in
);

    wire [3:0] r0_out, r1_out, r2_out, r3_out;  // unused
    wire [3:0] p_out_unused;
    wire [3:0] oh_w, ol_w;

    wire [10:0] rom_addr;
    wire  [7:0] rom_data;

    mb88 u_mcu
    (
        .clock      (clk),
        .ena        (ena),
        .reset_n    (reset_n),

        .r0_port_in (in_a[3:0]), .r1_port_in (in_a[7:4]), .r2_port_in (in_b[3:0]), .r3_port_in (in_b[7:4]),
        .r0_port_out(r0_out), .r1_port_out(r1_out), .r2_port_out(r2_out), .r3_port_out(r3_out),
        .k_port_in  (k_in),
        .ol_port_out(ol_w), .oh_port_out(oh_w),
        .o_wr       (),
        .p_port_out (p_out_unused),

        .stby_n     (1'b1),
        .tc_n       (1'b1),
        .irq_n      (~chip_sel),
        .sc_in_n    (1'b1),
        .si_n       (1'b1),
        .sc_out_n   (),
        .so_n       (),
        .to_n       (),

        .rom_addr   (rom_addr),
        .rom_data   (rom_data)
    );

    assign data_out = {oh_w, ol_w};

    dpram_dc #(.widthad_a(10)) rom_53xx
    (
        .clock_a  (clk), .address_a(rom_addr[9:0]), .data_a(8'h00), .wren_a(1'b0), .q_a(rom_data),
        .clock_b  (clk), .address_b(rom_addr_in), .data_b(rom_data_in),
        .wren_b   (rom_wr), .q_b()
    );

endmodule

`default_nettype wire
