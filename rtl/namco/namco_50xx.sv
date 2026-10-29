//  Based on MAME namco50.cpp (Aaron Giles, BSD-3-Clause)
`default_nettype none

module namco_50xx
(
    input  wire        clk,
    input  wire        ena,
    input  wire        reset_n,

    input  wire        chip_sel,
    input  wire        rw_in,
    output wire  [7:0] data_out,
    input  wire        wr_en,
    input  wire  [7:0] wr_data,

    input  wire        rom_wr,
    input  wire [10:0] rom_addr_in,
    input  wire  [7:0] rom_data_in,
    output chip_pool_pkg::mb88_i_t mb88_i,
    input  chip_pool_pkg::mb88_o_t mb88_o
);

    reg [7:0] cmd;
    always @(posedge clk) begin
        if (!reset_n) cmd <= 8'h00;
        else if (wr_en) cmd <= wr_data;
    end

    wire [3:0] oh_w, ol_w;

    wire [10:0] rom_addr;
    wire  [7:0] rom_data;

    assign mb88_i.ena     = ena;
    assign mb88_i.reset_n = reset_n;
    assign mb88_i.k       = cmd[7:4];
    assign mb88_i.r_in    = {4'h0, 3'b000, rw_in, 4'h0, cmd[3:0]};
    assign mb88_i.irq_n   = ~chip_sel;
    assign mb88_i.tc_n    = 1'b1;
    assign mb88_i.si_n    = 1'b1;
    assign mb88_i.rom_d   = rom_data;
    assign rom_addr       = mb88_o.rom_a;
    assign {oh_w, ol_w}   = mb88_o.o;

    assign data_out = {oh_w, ol_w};

    dpram_dc #(.widthad_a(11)) rom_50xx
    (
        .clock_a  (clk), .address_a(rom_addr), .data_a(8'h00), .wren_a(1'b0), .q_a(rom_data),
        .clock_b  (clk), .address_b(rom_addr_in), .data_b(rom_data_in),
        .wren_b   (rom_wr), .q_b()
    );

endmodule

`default_nettype wire
