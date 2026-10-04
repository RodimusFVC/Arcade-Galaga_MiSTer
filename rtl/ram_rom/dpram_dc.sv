//============================================================================
//
//  dpram_dc: true dual-port, dual-clock block RAM (M10K)
//  Same generics and altsyncram settings as the dpram_dc.vhd wrapper used
//  across the MiSTer arcade cores, without byte enables (full-word writes).
//  width_a must be at least 8.
//
//============================================================================

module dpram_dc #(
    parameter init_file     = " ",
    parameter widthad_a     = 8,
    parameter width_a       = 8,
    parameter outdata_reg_a = "UNREGISTERED",
    parameter outdata_reg_b = "UNREGISTERED"     // unused: both ports follow outdata_reg_a, as in the VHDL
)
(
    input  [widthad_a-1:0] address_a,
    input  [widthad_a-1:0] address_b,
    input                  clock_a,
    input                  clock_b,
    input  [width_a-1:0]   data_a,
    input  [width_a-1:0]   data_b,
    input                  wren_a,
    input                  wren_b,
    output [width_a-1:0]   q_a,
    output [width_a-1:0]   q_b
);

`ifdef VERILATOR

reg [width_a-1:0] mem [2**widthad_a];
reg [width_a-1:0] qa_r, qb_r, qa_o, qb_o;

initial begin
    for (int i = 0; i < 2**widthad_a; i++) mem[i] = '0;
    if (init_file != " ") $readmemh(init_file, mem);
end

always @(posedge clock_a) begin
    if (wren_a) mem[address_a] <= data_a;
    qa_r <= wren_a ? data_a : mem[address_a];
    qa_o <= qa_r;
end

always @(posedge clock_b) begin
    if (wren_b) mem[address_b] <= data_b;
    qb_r <= wren_b ? data_b : mem[address_b];
    qb_o <= qb_r;
end

assign q_a = (outdata_reg_a == "UNREGISTERED") ? qa_r : qa_o;
assign q_b = (outdata_reg_a == "UNREGISTERED") ? qb_r : qb_o;

`else

altsyncram #(
    .address_reg_b("CLOCK1"),
    .clock_enable_input_a("BYPASS"),
    .clock_enable_input_b("BYPASS"),
    .clock_enable_output_a("BYPASS"),
    .clock_enable_output_b("BYPASS"),
    .indata_reg_b("CLOCK1"),
    .init_file(init_file),
    .intended_device_family("Cyclone III"),
    .lpm_type("altsyncram"),
    .numwords_a(2**widthad_a),
    .numwords_b(2**widthad_a),
    .operation_mode("BIDIR_DUAL_PORT"),
    .outdata_aclr_a("NONE"),
    .outdata_aclr_b("NONE"),
    .outdata_reg_a(outdata_reg_a),
    .outdata_reg_b(outdata_reg_a),
    .power_up_uninitialized("FALSE"),
    .read_during_write_mode_port_a("NEW_DATA_NO_NBE_READ"),
    .read_during_write_mode_port_b("NEW_DATA_NO_NBE_READ"),
    .widthad_a(widthad_a),
    .widthad_b(widthad_a),
    .width_a(width_a),
    .width_b(width_a),
    .width_byteena_a(width_a/8),
    .width_byteena_b(width_a/8),
    .wrcontrol_wraddress_reg_b("CLOCK1")
) altsyncram_component (
    .wren_a(wren_a),
    .clock0(clock_a),
    .wren_b(wren_b),
    .clock1(clock_b),
    .address_a(address_a),
    .address_b(address_b),
    .data_a(data_a),
    .data_b(data_b),
    .q_a(q_a),
    .q_b(q_b),
    .byteena_a({(width_a/8){1'b1}}),
    .byteena_b({(width_a/8){1'b1}}),
    .aclr0(1'b0),
    .aclr1(1'b0),
    .addressstall_a(1'b0),
    .addressstall_b(1'b0),
    .clocken0(1'b1),
    .clocken1(1'b1),
    .clocken2(1'b1),
    .clocken3(1'b1),
    .eccstatus(),
    .rden_a(1'b1),
    .rden_b(1'b1)
);

`endif

endmodule
