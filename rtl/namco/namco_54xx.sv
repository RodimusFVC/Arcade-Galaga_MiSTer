//============================================================================
//
//  Namco 54xx noise generator: MB8844 MCU running its 0x400 mask ROM
//
//  Per MAME namco54.cpp. Write-only from the CPU side: the 06xx write
//  latches a command, K3-K0 = command[7:4], R0 = command[3:0]. The O port
//  (O0-O3, O4-O7) and R1 are the three 4-bit levels for the analog stage
//  (namco_54xx_snd.sv).
//
//============================================================================
`default_nettype none

module namco_54xx
(
    input  wire        clk,
    input  wire        ena,        // MCU clock enable, 1.536 MHz
    input  wire        reset_n,
    input  wire        ram_clr,        // power-on MCU RAM clear

    // 06xx side
    input  wire        chip_sel,   // select pulse -> MCU IRQ
    input  wire        wr_en,      // write strobe (06xx write mode, chip selected)
    input  wire  [7:0] wr_data,

    // analog stage inputs
    output wire  [3:0] discrete_o0,   // O0-O3
    output wire  [3:0] discrete_o1,   // O4-O7
    output wire  [3:0] discrete_r1,   // R1

    // 0x400 mask ROM load (write strobe already decoded by the board)
    input  wire        rom_wr,
    input  wire  [9:0] rom_addr_in,
    input  wire  [7:0] rom_data_in
);

    // command latch
    reg [7:0] latched_cmd;
    always @(posedge clk) begin
        if (!reset_n) latched_cmd <= 8'h00;
        else if (wr_en) latched_cmd <= wr_data;
    end

    wire [3:0] k_in  = latched_cmd[7:4];
    wire [3:0] r0_in = latched_cmd[3:0];
    wire [3:0] r1_in = 4'h0;            // R1 is an output
    wire [3:0] r2_in = 4'h0, r3_in = 4'h0;
    wire [3:0] r0_out_unused, r2_out_unused, r3_out_unused;
    wire [3:0] r1_out;
    wire [3:0] p_out_unused;

    wire [3:0] oh_w, ol_w;
    assign discrete_o0 = ol_w;
    assign discrete_o1 = oh_w;
    assign discrete_r1 = r1_out;

    wire [10:0] rom_addr;
    wire  [7:0] rom_data;

    mb88 #(.IRQ_ENTRY_STALL(3)) u_mcu   // MAME-exact interrupt entry timing, see mb88_core.sv
    (
        .clock      (clk),
        .ena        (ena),
        .reset_n    (reset_n),
        .ram_clr    (ram_clr),

        .r0_port_in (r0_in), .r1_port_in (r1_in), .r2_port_in (r2_in), .r3_port_in (r3_in),
        .r0_port_out(r0_out_unused), .r1_port_out(r1_out),
        .r2_port_out(r2_out_unused), .r3_port_out(r3_out_unused),
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

    dpram_dc #(.widthad_a(10)) rom_54xx
    (
        .clock_a  (clk), .address_a(rom_addr[9:0]), .data_a(8'h00), .wren_a(1'b0), .q_a(rom_data),
        .clock_b  (clk), .address_b(rom_addr_in[9:0]), .data_b(rom_data_in),
        .wren_b   (rom_wr), .q_b()
    );

endmodule

`default_nettype wire
