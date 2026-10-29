//  Based on MAME namco51.cpp (Mike Harris, Aaron Giles, BSD-3-Clause)
`default_nettype none

module namco_51xx
(
    input  wire        clk,
    input  wire        ena,
    input  wire        reset_n,

    input  wire        chip_sel,
    input  wire        rw_in,
    output wire  [7:0] data_out,
    input  wire        wr_en,
    input  wire  [7:0] wr_data,

    input  wire  [7:0] in_a,       // input<0> = in_a[3:0], input<1> = in_a[7:4]
    input  wire  [7:0] in_b,       // input<2> = in_b[3:0], input<3> = in_b[7:4]

    output wire  [3:0] p_port_out,

    input  wire        rom_wr,
    input  wire  [9:0] rom_addr_in,
    input  wire  [7:0] rom_data_in,

    input  wire        vblank,
    output chip_pool_pkg::mb88_i_t mb88_i,
    input  chip_pool_pkg::mb88_o_t mb88_o
);

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
    wire [3:0] oh_w, ol_w;
    assign o_out_w = {oh_w, ol_w};

    wire [10:0] rom_addr;
    wire  [7:0] rom_data;

    assign mb88_i.ena     = ena;
    assign mb88_i.reset_n = reset_n;
    assign mb88_i.k       = k_in;
    assign mb88_i.r_in    = {r3_in, r2_in, r1_in, r0_in};
    assign mb88_i.irq_n   = ~chip_sel;
    assign mb88_i.tc_n    = ~vblank;
    assign mb88_i.si_n    = 1'b1;
    assign mb88_i.rom_d   = rom_data;
    assign rom_addr       = mb88_o.rom_a;
    assign {oh_w, ol_w}   = mb88_o.o;
    assign o_wr_w         = mb88_o.o_wr;
    assign p_port_out     = mb88_o.p;

    dpram_dc #(.widthad_a(10)) rom_51xx
    (
        .clock_a  (clk), .address_a(rom_addr[9:0]), .data_a(8'h00), .wren_a(1'b0), .q_a(rom_data),
        .clock_b  (clk), .address_b(rom_addr_in[9:0]), .data_b(rom_data_in),
        .wren_b   (rom_wr), .q_b()
    );

endmodule

`default_nettype wire
