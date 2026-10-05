//============================================================================
//
//  Namco 52xx sample player: MB8843 MCU running its 0x400 mask ROM
//
//  Per MAME namco52.cpp. A 06xx write latches the command (K = command[3:0]);
//  the MCU sets the sample address on R2 (A0-A3), R3 (A4-A7) and O (A8-A15),
//  reads the byte on R0 / R1 and plays it on P0-P3. SI selects the board's
//  ROM addressing; TC is the board's external sample clock.
//
//============================================================================
`default_nettype none

module namco_52xx
(
    input  wire        clk,
    input  wire        ena,        // MCU clock enable, 256 kHz machine cycles
    input  wire        reset_n,
    input  wire        ram_clr,        // power-on MCU RAM clear

    input  wire        chip_sel,   // select pulse -> MCU IRQ
    input  wire        wr_en,
    input  wire  [7:0] wr_data,

    input  wire        si,
    input  wire        tc_n,

    output wire  [3:0] p_out,
    output wire [15:0] sample_addr,
    input  wire  [7:0] sample_data,

    // 0x400 mask ROM load (write strobe already decoded by the board)
    input  wire        rom_wr,
    input  wire  [9:0] rom_addr_in,
    input  wire  [7:0] rom_data_in
);

    reg [7:0] cmd;
    always @(posedge clk) begin
        if (!reset_n) cmd <= 8'h00;
        else if (wr_en) cmd <= wr_data;
    end

    wire [3:0] r0_out_unused, r1_out_unused, r2_out, r3_out;
    wire [3:0] oh_w, ol_w;

    assign sample_addr = {oh_w, ol_w, r3_out, r2_out};

    wire [10:0] rom_addr;
    wire  [7:0] rom_data;

    mb88 u_mcu
    (
        .clock      (clk),
        .ena        (ena),
        .reset_n    (reset_n),
        .ram_clr    (ram_clr),

        .r0_port_in (sample_data[3:0]), .r1_port_in (sample_data[7:4]), .r2_port_in (4'h0), .r3_port_in (4'h0),
        .r0_port_out(r0_out_unused), .r1_port_out(r1_out_unused),
        .r2_port_out(r2_out), .r3_port_out(r3_out),
        .k_port_in  (cmd[3:0]),
        .ol_port_out(ol_w), .oh_port_out(oh_w),
        .o_wr       (),
        .p_port_out (p_out),

        .stby_n     (1'b1),
        .tc_n       (tc_n),
        .irq_n      (~chip_sel),
        .sc_in_n    (1'b1),
        .si_n       (si),
        .sc_out_n   (),
        .so_n       (),
        .to_n       (),

        .rom_addr   (rom_addr),
        .rom_data   (rom_data)
    );

    dpram_dc #(.widthad_a(10)) rom_52xx
    (
        .clock_a  (clk), .address_a(rom_addr[9:0]), .data_a(8'h00), .wren_a(1'b0), .q_a(rom_data),
        .clock_b  (clk), .address_b(rom_addr_in), .data_b(rom_data_in),
        .wren_b   (rom_wr), .q_b()
    );

endmodule

`default_nettype wire
