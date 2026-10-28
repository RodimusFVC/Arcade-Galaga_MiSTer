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
    input  wire  [7:0] rom_data_in,
    // the shared MB88 (rtl/galaga_dispatcher.sv pool)
    output chip_pool_pkg::mb88_i_t mb88_i,
    input  chip_pool_pkg::mb88_o_t mb88_o
);

    wire [3:0] oh_w, ol_w;

    wire [10:0] rom_addr;
    wire  [7:0] rom_data;

    // MB8843: the shared MB88 in rtl/galaga_dispatcher.sv
    assign mb88_i.ena     = ena;
    assign mb88_i.reset_n = reset_n;
    assign mb88_i.k       = k_in;
    assign mb88_i.r_in    = {in_b[7:4], in_b[3:0], in_a[7:4], in_a[3:0]};   // R3, R2, R1, R0
    assign mb88_i.irq_n   = ~chip_sel;
    assign mb88_i.tc_n    = 1'b1;
    assign mb88_i.si_n    = 1'b1;
    assign mb88_i.rom_d   = rom_data;
    assign rom_addr       = mb88_o.rom_a;
    assign {oh_w, ol_w}   = mb88_o.o;

    assign data_out = {oh_w, ol_w};

    dpram_dc #(.widthad_a(10)) rom_53xx
    (
        .clock_a  (clk), .address_a(rom_addr[9:0]), .data_a(8'h00), .wren_a(1'b0), .q_a(rom_data),
        .clock_b  (clk), .address_b(rom_addr_in), .data_b(rom_data_in),
        .wren_b   (rom_wr), .q_b()
    );

endmodule

`default_nettype wire
