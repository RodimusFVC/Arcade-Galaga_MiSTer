//============================================================================
//
//  dpram_dc: true dual-port, dual-clock block RAM (M10K)
//  Drop-in replacement for the dpram_dc.vhd wrapper used across the MiSTer
//  arcade cores: same generics/ports/defaults, same altsyncram settings.
//
//  Port defaults (VHDL: ":= ..."): an unconnected input reads
//     address_b, data_a, data_b, wren_a, wren_b = 0 ; byteena_a/b = all ones.
//  clock_a / clock_b have no default (must be connected), as in the VHDL.
//  Mechanism: tri0 / tri1 port nets. An unconnected port is Z, which a tri0 net
//  resolves to 0 and a tri1 net to 1. (SV default port values were not used:
//  Quartus 17.0 support is not established.)
//
//  width_a < 8: byteena_a/b exist (1 bit, ignored) and are NOT connected to
//  altsyncram, which gets width_byteena_a/b = 1: the form Quartus' own MegaWizard
//  emits for a RAM without byte enables. Writes are always full word.
// Quartus 17.0 rejects width_byteena = width_a/8 = 0 in altsyncram.tdf (Error 287087), so below 8 bits it is 1.
//
// Cross-port same-address read / write is undefined in hardware for different clocks; the model must not be relied on.
//
//============================================================================

module dpram_dc #(
    parameter init_file     = " ",
    parameter widthad_a     = 8,
    parameter width_a       = 8,
    parameter outdata_reg_a = "UNREGISTERED",
    parameter outdata_reg_b = "UNREGISTERED"
)
(
    input  tri0 [widthad_a-1:0] address_a,         // no default in the VHDL; tri0 only so lint is quiet
    input  tri0 [widthad_a-1:0] address_b,         // default 0
    input                       clock_a,
    input                       clock_b,
    input  tri0 [width_a-1:0]   data_a,            // default 0
    input  tri0 [width_a-1:0]   data_b,            // default 0
    input  tri0                 wren_a,            // default 0
    input  tri0                 wren_b,            // default 0
    input  tri1 [((width_a < 8) ? 1 : (width_a/8))-1:0] byteena_a,   // default all ones
    input  tri1 [((width_a < 8) ? 1 : (width_a/8))-1:0] byteena_b,   // default all ones
    output [width_a-1:0]        q_a,
    output [width_a-1:0]        q_b
);

localparam BEW = (width_a < 8) ? 1 : (width_a/8);   // byteena port width (VHDL: width_a/8; 0 -> 1 here)
localparam BS  = width_a / BEW;                      // bits per enable (width_a<8: whole word)

`ifdef VERILATOR

reg [width_a-1:0] mem [2**widthad_a];
reg [width_a-1:0] qa_r, qb_r, qa_o, qb_o;

localparam ORA_REG = (outdata_reg_a != "UNREGISTERED");
localparam ORB_REG = (outdata_reg_b != "UNREGISTERED");
localparam ORA_CB  = (outdata_reg_a == "CLOCK1");     // output register clocked by clock_b
localparam ORB_CB  = (outdata_reg_b == "CLOCK1");

initial begin
    for (int i = 0; i < 2**widthad_a; i++) mem[i] = '0;
    qa_r = '0; qb_r = '0; qa_o = '0; qb_o = '0;
    if (init_file != " ") $readmemh(init_file, mem);
end

// byte enable -> bit mask (width_a < 8: byteena ignored, full word, as no enable reaches the RAM)
function automatic [width_a-1:0] bmask(input [BEW-1:0] be);
    integer k;
    for (k = 0; k < width_a; k = k + 1)
        bmask[k] = (width_a < 8) ? 1'b1 : be[(k/BS < BEW) ? (k/BS) : (BEW-1)];
endfunction

wire [width_a-1:0] ma = bmask(byteena_a);
wire [width_a-1:0] mb = bmask(byteena_b);


wire [width_a-1:0] wa_new = (mem[address_a] & ~ma) | (data_a & ma);
wire [width_a-1:0] wb_new = (mem[address_b] & ~mb) | (data_b & mb);

always @(posedge clock_a) begin
    if (wren_a) mem[address_a] <= wa_new;
    qa_r <= wren_a ? wa_new : mem[address_a];     // NEW_DATA for enabled bytes, old contents for disabled ones
end

always @(posedge clock_b) begin
    if (wren_b) mem[address_b] <= wb_new;
    qb_r <= wren_b ? wb_new : mem[address_b];
end

// output register stage: clocked by clock_a (CLOCK0) or clock_b (CLOCK1); no derived clock, so same-edge sampling is of the old qx_r
generate
    if (ORA_CB) begin : g_oa1  always @(posedge clock_b) qa_o <= qa_r;  end
    else        begin : g_oa0  always @(posedge clock_a) qa_o <= qa_r;  end
    if (ORB_CB) begin : g_ob1  always @(posedge clock_b) qb_o <= qb_r;  end
    else        begin : g_ob0  always @(posedge clock_a) qb_o <= qb_r;  end
endgenerate

assign q_a = ORA_REG ? qa_o : qa_r;
assign q_b = ORB_REG ? qb_o : qb_r;

`else

// Same generics as dpram_dc.vhd for every width. Only the byteena port connection
// is conditional: width_a < 8 leaves it off (null-range port in the VHDL).
generate
if (width_a >= 8) begin : g_be
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
    .outdata_reg_b(outdata_reg_b),
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
    .byteena_a(byteena_a),
    .byteena_b(byteena_b),
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
end else begin : g_nobe
// width_a < 8: width_byteena = 1 (MegaWizard form); byteena ports not connected.
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
    .outdata_reg_b(outdata_reg_b),
    .power_up_uninitialized("FALSE"),
    .read_during_write_mode_port_a("NEW_DATA_NO_NBE_READ"),
    .read_during_write_mode_port_b("NEW_DATA_NO_NBE_READ"),
    .widthad_a(widthad_a),
    .widthad_b(widthad_a),
    .width_a(width_a),
    .width_b(width_a),
    .width_byteena_a(1),
    .width_byteena_b(1),
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
end
endgenerate

`endif

endmodule
