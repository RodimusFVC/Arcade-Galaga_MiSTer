//============================================================================
//
//  Namco 50xx protection / scoring: MB8842 MCU running its 0x800 mask ROM
//
//  Per MAME namco50.cpp. A 06xx write latches a command: K3-K0 = command[7:4],
//  R0 = command[3:0], R2 bit 0 = R/W direction from the 06xx. A 06xx read
//  returns the MCU's O port.
//
//============================================================================
`default_nettype none

module namco_50xx
(
    input  wire        clk,
    input  wire        ena,        // MCU clock enable, 256 kHz machine cycles
    input  wire        reset_n,
    input  wire        ram_clr,        // power-on MCU RAM clear

    // 06xx side
    input  wire        chip_sel,   // select pulse -> MCU IRQ
    input  wire        rw_in,      // R/W direction
    output wire  [7:0] data_out,
    input  wire        wr_en,
    input  wire  [7:0] wr_data,

    // 0x800 mask ROM load (write strobe already decoded by the board)
    input  wire        rom_wr,
    input  wire [10:0] rom_addr_in,
    input  wire  [7:0] rom_data_in
);

    reg [7:0] cmd;
    always @(posedge clk) begin
        if (!reset_n) cmd <= 8'h00;
        else if (wr_en) cmd <= wr_data;
    end

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
        .ram_clr    (ram_clr),

        .r0_port_in (cmd[3:0]), .r1_port_in (4'h0), .r2_port_in ({3'b000, rw_in}), .r3_port_in (4'h0),
        .r0_port_out(r0_out), .r1_port_out(r1_out), .r2_port_out(r2_out), .r3_port_out(r3_out),
        .k_port_in  (cmd[7:4]),
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

    dpram_dc #(.widthad_a(11)) rom_50xx
    (
        .clock_a  (clk), .address_a(rom_addr), .data_a(8'h00), .wren_a(1'b0), .q_a(rom_data),
        .clock_b  (clk), .address_b(rom_addr_in), .data_b(rom_data_in),
        .wren_b   (rom_wr), .q_b()
    );

endmodule

`default_nettype wire
