//============================================================================
//
//  Namco 51xx I/O (coins, switches): MB8843 MCU running its 0x400 mask ROM
//
//  Per MAME namco51.cpp. The mailbox (MAME m_portO) is one byte written by
//  both sides: a CPU write through the 06xx, or the MCU's own O-port output.
//  K3 = R/W direction from the 06xx, K2-K0 = mailbox low bits.
//  R0-R3 = the four input nibbles; TC = vblank.
//
//============================================================================
`default_nettype none

module namco_51xx
(
    input  wire        clk,
    input  wire        ena,        // MCU clock enable, 1.536 MHz
    input  wire        reset_n,

    // 06xx side
    input  wire        chip_sel,   // select pulse -> MCU IRQ
    input  wire        rw_in,      // R/W direction (06xx control bit 4)
    output wire  [7:0] data_out,   // mailbox -> 06xx read data
    input  wire        wr_en,      // write strobe (06xx write mode, chip selected)
    input  wire  [7:0] wr_data,

    // R-port inputs (namco51.cpp input_callback<0..3>)
    input  wire  [7:0] in_a,       // input<0> = in_a[3:0], input<1> = in_a[7:4]
    input  wire  [7:0] in_b,       // input<2> = in_b[3:0], input<3> = in_b[7:4]

    output wire  [3:0] p_port_out, // coin counters / lamps

    // 0x400 mask ROM load (write strobe already decoded by the board)
    input  wire        rom_wr,
    input  wire  [9:0] rom_addr_in,
    input  wire  [7:0] rom_data_in,

    input  wire        vblank      // -> TC, counted on its falling edge
);

    // Shared mailbox: a CPU write wins; otherwise each MCU outO instruction latches its O port once
    // (o_wr is held for a whole MCU cycle, so gate it with ena to latch exactly one fabric clock).
    wire [7:0] o_out_w;
    wire       o_wr_w;
    reg  [7:0] mbox;

    always @(posedge clk) begin
        if (!reset_n) begin
            mbox <= 8'h00;
        end else begin
            if (wr_en)                mbox <= wr_data;
            else if (o_wr_w && ena)   mbox <= o_out_w;
        end
    end

    assign data_out = mbox;

    wire [3:0] k_in = {rw_in, mbox[2:0]};

    wire [3:0] r0_in = in_a[3:0];
    wire [3:0] r1_in = in_a[7:4];
    wire [3:0] r2_in = in_b[3:0];
    wire [3:0] r3_in = in_b[7:4];
    wire [3:0] r0_out, r1_out, r2_out, r3_out;  // unused

    wire [3:0] oh_w, ol_w;
    assign o_out_w = {oh_w, ol_w};

    wire [10:0] rom_addr;
    wire  [7:0] rom_data;

    mb88 u_mcu
    (
        .clock      (clk),
        .ena        (ena),
        .reset_n    (reset_n),

        .r0_port_in (r0_in), .r1_port_in (r1_in), .r2_port_in (r2_in), .r3_port_in (r3_in),
        .r0_port_out(r0_out), .r1_port_out(r1_out), .r2_port_out(r2_out), .r3_port_out(r3_out),
        .k_port_in  (k_in),
        .ol_port_out(ol_w), .oh_port_out(oh_w),
        .o_wr       (o_wr_w),
        .p_port_out (p_port_out),

        .stby_n     (1'b1),
        .tc_n       (~vblank),          // MAME: TC asserted while not in vblank
        .irq_n      (~chip_sel),
        .sc_in_n    (1'b1),
        .si_n       (1'b1),
        .sc_out_n   (),
        .so_n       (),
        .to_n       (),

        .rom_addr   (rom_addr),
        .rom_data   (rom_data)
    );

    // 1K mask ROM (rom_addr is 11 bits wide for the MB8841 family)
    dpram_dc #(.widthad_a(10)) rom_51xx
    (
        .clock_a  (clk), .address_a(rom_addr[9:0]), .data_a(8'h00), .wren_a(1'b0), .q_a(rom_data),
        .clock_b  (clk), .address_b(rom_addr_in[9:0]), .data_b(rom_data_in),
        .wren_b   (rom_wr), .q_b()
    );

endmodule

`default_nettype wire
