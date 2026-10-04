// ============================================================================
//  mb88.sv  —  wrapper presenting darfpga/Xevious's EXACT `mb88` entity, so it
//  binds to poleposition.vhd's `entity work.mb88` instantiations (cs51xx / cs54xx /
//  cs50xx) with NO edit to the game logic. Wraps our combinational-RAM mb88_core
//  (mb88_sv/mb88_core.sv) — the validated rewrite that fixes the BRAM read-after-
//  write hazard the deployed darfpga mb88.vhd suffered.
//
//  vs the Xevious/darfpga entity our core added ONE port (`ena_timer`, which Kangaroo
//  drove pre-÷32 externally). That port is dropped here and the ÷32 timer tick is
//  generated INTERNALLY from `ena`, so the entity now matches exactly.
//
//  NOTE (mixed-language): poleposition.vhd instantiates this via `entity work.mb88`
//  (VHDL-instantiates-SystemVerilog). Verify Quartus 17 binds it; if not, a thin VHDL
//  shim entity `mb88` wrapping mb88_core is the fallback.
// ============================================================================

module mb88 #(parameter IRQ_ENTRY_STALL = 0)   // IRQ-ENTRY-STALL-2026-09-23, see mb88_core.sv
(
    input  wire        clock,
    input  wire        ena,
    input  wire        reset_n,

    input  wire [3:0]  r0_port_in,  r1_port_in,  r2_port_in,  r3_port_in,
    output wire [3:0]  r0_port_out, r1_port_out, r2_port_out, r3_port_out,
    input  wire [3:0]  k_port_in,
    output wire [3:0]  ol_port_out, oh_port_out,
    output wire        o_wr,        // O-PORT-STROBE-2026-08-09: pulses on every outO
    output wire [3:0]  p_port_out,

    input  wire        stby_n,
    input  wire        tc_n,
    input  wire        irq_n,
    input  wire        sc_in_n,
    input  wire        si_n,
    output wire        sc_out_n,
    output wire        so_n,
    output wire        to_n,

    output wire [10:0] rom_addr,
    input  wire [7:0]  rom_data
);
    wire [15:0]  r_in  = {r3_port_in, r2_port_in, r1_port_in, r0_port_in};
    wire [15:0]  r_out;
    wire [7:0]   o_out;

    assign {r3_port_out, r2_port_out, r1_port_out, r0_port_out} = r_out;
    assign ol_port_out = o_out[3:0];
    assign oh_port_out = o_out[7:4];

    // serial/handshake outputs — mb88_core serial is a stub (as was darfpga's "Todo: Serial")
    assign sc_out_n = 1'b1;
    assign so_n     = 1'b1;
    assign to_n     = 1'b1;

    // ---- internal timer prescaler (mb88_core wants ena_timer PRE-÷32) ----
    // The darfpga/Xevious mb88 entity has no ena_timer port (its VHDL core divided
    // internally). Generate it here: one ena_timer pulse per 32 `ena` machine-cycle
    // enables — MAME mb88 burn_cycles /32 (full timer overflow = ÷8192 of `ena`).
    // Free-running vs pio7 (the core gates the TL increment on pio7 itself); per the
    // mb88 co-sim log the pio7 phase is inert here (pio7 set once at init, not toggled).
    reg [4:0] tdiv;
    reg       ena_timer_int;
    always @(posedge clock) begin
        if (!reset_n) begin
            tdiv          <= 5'd0;
            ena_timer_int <= 1'b0;
        end else begin
            ena_timer_int <= 1'b0;
            if (ena) begin
                tdiv <= tdiv + 5'd1;
                if (tdiv == 5'd31) ena_timer_int <= 1'b1;
            end
        end
    end

    mb88_core #(.IRQ_ENTRY_STALL(IRQ_ENTRY_STALL)) core
    (
        .clk       (clock),
        .ce        (ena),
        .ena_timer (ena_timer_int),
        .reset_n   (reset_n),

        .prog_addr (rom_addr),
        .prog_data (rom_data),

        .k_in      (k_port_in),
        .r_in      (r_in),
        .r_out     (r_out),
        .p_out     (p_port_out),
        .o_out     (o_out),
        .o_wr      (o_wr),
        .si_in     (si_n),
        .so_out    (),
        .irq_n     (irq_n),
        .tc_in     (tc_n),

        .int_req   (1'b0),        // trace injection off on hardware
        .int_vec   (6'd0),

        .dbg_pc(), .dbg_fetch_pc(), .dbg_a(), .dbg_x(), .dbg_y(),
        .dbg_st(), .dbg_zf(), .dbg_cf(), .dbg_retire(), .dbg_int_ack(),
        .dbg_illegal(), .dbg_ram()
    );

    // silence unused inputs (stby_n / sc_in_n not modeled)
    // verilator lint_off UNUSED
    wire _wunused = &{1'b0, stby_n, sc_in_n};
    // verilator lint_on UNUSED
endmodule
