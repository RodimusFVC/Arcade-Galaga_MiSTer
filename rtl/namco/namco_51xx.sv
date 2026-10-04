//============================================================================
//  namco_51xx.sv — Namco 51xx I/O MCU wrapper (coin/switch reader)
//
//  Ground truth: MAME src/devices/machine/namco51.cpp (namco_51xx_device) +
//  src/mame/namco/polepos.cpp machine_config (:887-893, :914-917).
//  MB8843 4-bit MCU (rtl/cpu/mb88_sv/mb88.sv, the validated combinational-RAM
//  rewrite) + its 0x400 internal mask ROM (ioctl index 6, offset 0x000-0x3FF,
//  51xx.bin crc c2f57ef8) + the polepos-specific port wiring below.
//
//  polepos machine_config port wiring (namco51.cpp R_r<N> <- devcb):
//    input<0> = DSWB & 0x0f     (R0)
//    input<1> = DSWB >> 4       (R1)
//    input<2> = IN0  & 0x0f     (R2)
//    input<3> = IN0  >> 4       (R3)
//    output_callback  = polepos_state::out (coin counters — NOT wired downstream;
//                        mechanical coin-counter output, no gameplay effect)
//    lockout_callback = bound but namco51.cpp never calls m_lockout() — dead in MAME
//
//  Namco51 K-port protocol (namco51.cpp K_r/read/write):
//    K3        = R/!W direction, driven externally by the 06xx bus (rw0)
//    K2:0      = the SHARED mbox register's low 3 bits read back by the MCU's
//                own firmware (M_portO & 0x07 in MAME)
//  The "mbox" (MAME's m_portO) is a SINGLE byte written from BOTH sides:
//    - the Z80 (via 06xx write(), when chip0 selected + write-mode) directly
//      overwrites it with the command/data byte (namco51.cpp write_sync());
//    - the MCU's own O-port instruction (outO, mb88 opcode 0x01) overwrites it
//      with its response (namco51.cpp O_w_sync()).
//  mb88_core's `o_out` register only models the MCU's own half of this; the
//  external Z80-write half is modeled here as `mbox`, which mirrors o_out
//  whenever the MCU changes it, but a CPU write (wr_en) takes priority and
//  temporarily overrides it — exactly matching MAME's single-shared-variable
//  semantics without needing to touch the validated mb88_core/mb88 modules.
//============================================================================
`default_nettype none

module namco_51xx
(
    input  wire        clk,        // fabric clock (CLK_49M)
    input  wire        ena,        // MCU clock enable = clk_sys/32 = 1.536 MHz (MASTER_CLOCK/8/2)
    input  wire        reset_n,    // = ~system_reset & namco_reset (LS259 q1, MAME reset(state))

    // ---- 06xx bus-side (per-chip signals from namco_06xx) ------------------
    input  wire        chip_sel,   // chipsel[0]: active-high IRQ/select pulse
    input  wire        rw_in,      // 06xx rw0 (R/!W direction, mirrors ctrl[4])
    output wire  [7:0] data_out,   // -> namco_06xx chip0_din (data_r AND-reduce input)
    input  wire        wr_en,      // 06xx chip_wr[0] strobe (data_w broadcast, write-mode+selected)
    input  wire  [7:0] wr_data,

    // ---- R-port inputs (namco51.cpp input_callback<0..3>) ------------------
    input  wire  [7:0] in_a,       // input<0> = in_a[3:0], input<1> = in_a[7:4]
    input  wire  [7:0] in_b,       // input<2> = in_b[3:0], input<3> = in_b[7:4]

    output wire  [3:0] p_port_out, // MAME P_w -> output_callback (coin counters) — unwired downstream

    // ---- 0x400 mask ROM load (write strobe already decoded by the board) --
    input  wire        rom_wr,
    input  wire  [9:0] rom_addr_in,
    input  wire  [7:0] rom_data_in,

    // ---- vblank -> mb88 TC (external-counter) pin --------------------------
    //   MAME: m_screen->screen_vblank().set("51xx", vblank); vblank(state) drives
    //   MB88XX_TC_LINE, "active on falling edges". The mb88 external-counter timer
    //   ticks once per frame off this. `vblank` here = 1 during vertical blank.
    input  wire        vblank
);

    // ---- shared mbox (see header) ---------------------------------------
    // O-PORT-STROBE-FIX-2026-08-09 -------------------------------------------
    // Was: `o_out_changed = (o_out_w != o_out_prev)` -- the mbox only re-latched
    // when the MCU's O value CHANGED. MAME re-latches on every outO regardless:
    // mb88xx.cpp write_pla() ends in an unconditional `m_write_o(0, m_o_output, mask)`
    // -> namco51.cpp O_w() -> `m_portO = data`. So a repeat outO of the same value
    // still clobbers whatever the Z80 wrote. With change-detection the Z80's command
    // byte survived instead, leaving a STALE reply in the mbox -- which corrupts
    // both data_out (the byte the Z80 reads back at $810C) and K_r, since K2:0 feeds
    // the mbox low bits back into the MCU's own firmware.
    // Now driven by mb88's real o_wr strobe, matching MAME exactly.
    wire [7:0] o_out_w;
    wire       o_wr_w;
    reg  [7:0] mbox;

    // O-PORT-PULSE-FIX-2026-08-10 -------------------------------------------
    // O-PORT-STROBE-FIX-2026-08-09 was right to drop change-detection but made
    // the re-latch LEVEL-sensitive. mb88_core's `o_wr` is registered inside the
    // ce-gated block (set on outO at mb88_core.sv:219, cleared at :199), so it
    // stays high for a whole MCU cycle = clk/32 = ~32 fabric clocks here. This
    // block runs on bare `clk`, so it re-latched o_out ~32 times per outO. A Z80
    // command byte landing in that window won the arbitration for exactly ONE
    // clock and was then clobbered back to the MCU's stale o_out on the next.
    // MAME calls O_w_sync() ONCE per outO instruction (namco51.cpp:122-125), a
    // single event. Gating with `ena` reproduces that: o_wr_w is set on one ena
    // tick and cleared on the next, so `o_wr_w & ena` is true for exactly one
    // fabric clock per outO. Z80 writes on every other clock now survive.
    always @(posedge clk) begin
        if (!reset_n) begin
            mbox <= 8'h00;
        end else begin
            if (wr_en)                mbox <= wr_data;   // Z80 write wins (matches MAME order)
            else if (o_wr_w && ena)   mbox <= o_out_w;   // MCU outO: ONE latch per instruction
        end
    end

    assign data_out = mbox;

    // ---- K-port: K3=rw (external), K2:0 = mbox low nibble bits ----------
    wire [3:0] k_in = {rw_in, mbox[2:0]};

    // ---- R-ports: DSWB (R0/R1), IN0 (R2/R3) --------------------------------
    wire [3:0] r0_in = in_a[3:0];
    wire [3:0] r1_in = in_a[7:4];
    wire [3:0] r2_in = in_b[3:0];
    wire [3:0] r3_in = in_b[7:4];
    wire [3:0] r0_out, r1_out, r2_out, r3_out;  // unused (51xx doesn't drive R as outputs in polepos)

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
        .o_wr       (o_wr_w),                       // O-PORT-STROBE-FIX-2026-08-09
        .p_port_out (p_port_out),

        .stby_n     (1'b1),
        // TC-TIMER-FIX-2026-07-17: was tied 1'b1 (stub). Now the mb88 TC pin = the TC
        // LEVEL that MAME sets from vblank: `set_input_line(TC, state?CLEAR:ASSERT)` =>
        // TC = ~vblank (high during active display, low during blank). mb88_core ticks the
        // external-counter timer on TC's FALLING edge (= vblank START), gated by pio bit6.
        .tc_n       (~vblank),
        .irq_n      (~chip_sel),
        .sc_in_n    (1'b1),
        .si_n       (1'b1),
        .sc_out_n   (),
        .so_n       (),
        .to_n       (),

        .rom_addr   (rom_addr),
        .rom_data   (rom_data)
    );

    // ---- 0x400 internal MCU ROM -------------------------------------------
    // mb88's rom_addr is 11 bits (MB8841-width port); the MB8843 51xx part
    // only has a 1KB (10-bit) mask ROM, so the top address bit is dropped —
    // any real firmware stays within page 0-15 and never reaches it.
    dpram_dc #(.widthad_a(10)) rom_51xx
    (
        .clock_a  (clk), .address_a(rom_addr[9:0]), .data_a(8'h00), .wren_a(1'b0), .q_a(rom_data),
        .clock_b  (clk), .address_b(rom_addr_in[9:0]), .data_b(rom_data_in),
        .wren_b   (rom_wr), .q_b()
    );

endmodule

`default_nettype wire
