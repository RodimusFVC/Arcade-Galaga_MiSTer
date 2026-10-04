//============================================================================
//  namco_06xx.sv — Namco 06XX bus arbiter (Z80 <-> up to 4 Namco 5xxx MCUs)
//
//  Ground truth: MAME src/devices/machine/namco06.cpp (namco_06xx_device).
//  Interfaces the Z80 (via PolePosition_CPU's n06_* ports, 0x9000 data /
//  0x9100 ctrl, both mirror 0x0EFF) to chip0=51xx, chip1=53xx, chip2=52xx
//  (Phase-5, unbuilt), chip3=54xx (Phase-4, unbuilt). Only chip0/chip1 are
//  wired to real wrappers in this increment; chip2/chip3 read as 0xFF
//  (matches MAME's devcb_read8 default) and have no write sink.
//
//  Control register (ctrl_w, MAME-bit-exact):
//    [3:0] = chip-select mask (bit0=51xx bit1=53xx bit2=52xx bit3=54xx)
//    [4]   = R/!W direction (1 = read mode, 0 = write mode)
//    [7:5] = num_shifts; enable/clock-divider. (ctrl[7:5]==0) => disabled.
//
//  data_r (read mode): AND-reduce of the read() outputs of all SELECTED
//    chips (0xFF for unselected/absent chips) — pure combinational, NOT
//    gated by the chipsel/NMI timer below (matches namco06.cpp data_r()).
//  data_w (write mode): broadcasts the written byte to all SELECTED chips'
//    write() ports — also NOT gated by the timer (matches data_w()/write_sync()).
//  The chipsel/NMI timer below only drives each MCU's own /IRQ input (so its
//  OWN firmware knows to service the mailbox) and the Z80's NMI (so the Z80's
//  boot-time polling loop knows a transfer is ready) — see nmi_generate().
//
//  #1 HW-TUNE POINT — TWO deferred/synchronized behaviors from MAME are
//  reproduced here as a ONE-clk_sys-cycle register delay (ctrl_apply /
//  data_apply below), NOT MAME's full "next scheduler quantum":
//    (a) ctrl_w is deferred (machine().scheduler().synchronize) — the Z80
//        boot code writes ctrl=0x10 then polls ~4 instructions later,
//        relying on the write NOT being visible instantly.
//    (b) data_w is deferred the same way.
//  If HW bring-up shows the Z80 racing/stalling on the 06xx handshake
//  (self-test stuck, "0" screen not advancing), THIS is the first thing to
//  re-time — e.g. widen the delay to a full Z80 CE tick, or align to a
//  falling-CE-edge boundary the way MAME aligns to "the next falling clock
//  edge" in ctrl_w_sync(). The nmi_generate phase-restart-on-ctrl-write
//  (div_cnt/timer_state reset in the ctrl_apply branch below) is also a
//  simplification of MAME's attotime-based "delay to the next falling clock
//  edge" re-arm — a deterministic restart-to-phase-0 rather than a true
//  phase-continuous realignment.
//
//  Base tick: MAME's 06xx device clock = MASTER_CLOCK/8/64 = 24.576MHz/512 =
//  48kHz. Our fabric clk_sys = 49.152MHz = 2x MASTER_CLOCK, so clk_sys/1024
//  is the equivalent 48kHz tick (base_ce below). nmi_generate is invoked
//  every (divisor/2) base ticks, divisor=2^ctrl[7:5] (1..128, only 2..128
//  reachable while enabled since ctrl[7:5]==0 means disabled).
//============================================================================
`default_nettype none

module namco_06xx
(
    input  wire        clk,        // fabric clock (CLK_49M, 49.152 MHz)
    input  wire        reset,      // active-high SYSTEM reset (NOT the LS259 namco_reset,
                                    // which only gates the MCUs' own reset_n externally)
    input  wire        pause,      // MiSTer pause (freezes the Z80/Z8002 CEN elsewhere) --
                                    // freezes the NMI/chipsel timer too so a paused frame
                                    // (e.g. a diagnostic screenshot) doesn't keep the 06xx
                                    // handshake advancing behind the frozen CPU's back

    // ---- Z80-side bus (PolePosition_CPU n06_* ports) ----------------------
    input  wire  [7:0] cpu_dout,
    input  wire        data_wr, data_rd,
    input  wire        ctrl_wr, ctrl_rd,
    output wire  [7:0] cpu_din,
    output wire        nmi_n,       // -> Z80 NMI_n (active low)

    // ---- per-chip interconnect (0=51xx 1=53xx 2=52xx[unbuilt] 3=54xx[unbuilt]) --
    output wire  [3:0] chipsel,     // active-high IRQ/select pulse per chip
    output wire        rw0,         // R/!W direction line — MAME binds rw_callback<0> (51xx) ONLY
    input  wire  [7:0] chip0_din, chip1_din, chip2_din, chip3_din,
    output wire  [7:0] chip_dout,   // broadcast write data to selected chip(s)
    output wire  [3:0] chip_wr      // per-chip write strobe (chip1/53xx has no MAME write
                                    // binding — namco_53xx.sv simply doesn't use chip_wr[1])
);

    // ---- deferred ctrl_w / data_w (see header #1 HW-TUNE POINT) ------------
    reg [7:0] ctrl_wdata_d;  reg ctrl_apply;
    reg [7:0] data_wdata_d;  reg data_apply;
    always @(posedge clk) begin
        ctrl_apply <= ctrl_wr;
        if (ctrl_wr) ctrl_wdata_d <= cpu_dout;
        data_apply <= data_wr;
        if (data_wr) data_wdata_d <= cpu_dout;
    end

    reg  [7:0] ctrl;
    reg        read_stretch;
    reg  [9:0] base_cnt;
    reg  [6:0] div_cnt;
    reg        timer_state;
    reg  [3:0] chipsel_r;
    reg        rw0_r;
    reg        nmi_n_r;

    wire       wmode     = ~ctrl[4];
    wire       enabled   = |ctrl[7:5];
    // divisor/2 - 1 (ticks between toggles); only evaluated while enabled (ctrl[7:5]>=1)
    wire [6:0] div_limit = (7'd1 << (ctrl[7:5] - 3'd1)) - 7'd1;
    wire       base_ce   = (base_cnt == 10'd1023);

    always @(posedge clk) begin
        if (reset) base_cnt <= 10'd0;
        else       base_cnt <= base_ce ? 10'd0 : base_cnt + 10'd1;
    end

    always @(posedge clk) begin
        if (reset) begin
            ctrl         <= 8'h00;
            read_stretch <= 1'b0;
            div_cnt      <= 7'd0;
            timer_state  <= 1'b0;
            chipsel_r    <= 4'h0;
            rw0_r        <= 1'b0;
            nmi_n_r      <= 1'b1;
        end else if (ctrl_apply) begin
            // ctrl_w_sync equivalent (deferred write commits now)
            ctrl    <= ctrl_wdata_d;
            // div_cnt/timer_state are deliberately NOT preloaded from ctrl here:
            // the closer match to namco06.cpp:186-223 measured worse on the 51xx reply.
            div_cnt <= 7'd0;
            timer_state <= 1'b0;
            if (ctrl_wdata_d[7:5] == 3'b000) begin
                // disabled: stop timer, clear NMI + all chipsels; RW left as-is (MAME comment)
                chipsel_r <= 4'h0;
                nmi_n_r   <= 1'b1;
            end else if (ctrl_wdata_d[4]) begin
                // entering read mode: NMI cleared immediately, suppress the FIRST pulse
                nmi_n_r      <= 1'b1;
                read_stretch <= 1'b1;
            end else begin
                read_stretch <= 1'b0;
            end
        end else if (enabled && base_ce && !pause) begin
            if (div_cnt == div_limit) begin
                div_cnt      <= 7'd0;
                timer_state  <= ~timer_state;
                read_stretch <= 1'b0;   // MAME clears m_read_stretch on EVERY nmi_generate call
                if (~timer_state) begin
                    // toggling false->true: this is nmi_generate's "m_timer_state==true" branch
                    rw0_r     <= ctrl[4];
                    chipsel_r <= ctrl[3:0];
                    nmi_n_r   <= read_stretch ? 1'b1 : 1'b0;
                end else begin
                    // toggling true->false: NMI + chipsel cleared
                    chipsel_r <= 4'h0;
                    nmi_n_r   <= 1'b1;
                end
            end else begin
                div_cnt <= div_cnt + 7'd1;
            end
        end
    end

    assign chipsel = chipsel_r;
    assign rw0     = rw0_r;
    assign nmi_n   = nmi_n_r;

    // ---- data_r: combinational AND-reduce of selected chips' read() -------
    wire [7:0] d0 = ctrl[0] ? chip0_din : 8'hFF;
    wire [7:0] d1 = ctrl[1] ? chip1_din : 8'hFF;
    wire [7:0] d2 = ctrl[2] ? chip2_din : 8'hFF;
    wire [7:0] d3 = ctrl[3] ? chip3_din : 8'hFF;
    wire [7:0] data_r_val = d0 & d1 & d2 & d3;

    // ---- N06-DATAHOLD-2026-08-11: A/B SWITCH #1 ---------------------------
    // data_r_val above is a FREE-RUNNING combinational tap of the 51xx's live
    // `mailbox` register: nothing holds the reply byte still for the duration of
    // a transfer, so the Z80 samples whatever the MCU happens to hold at that
    // instant. Measured symptom this targets: a slipped burst reads
    // `74, 74, FF` instead of `7F, 74, FF` -- the SAME mailbox value twice,
    // missing one entirely (~8% of reads, periodic 3/4/13 beat).
    //
    // MAME is structurally identical here but NOT behaviourally: it evaluates
    // data_r() at a scheduler-defined instant with the MCU advanced to exactly
    // that point. Real concurrent hardware has no such guarantee.
    //
    //   HOLD_MODE 0 = OFF, the pre-2026-08-11 free-running tap (baseline)
    //   HOLD_MODE 1 = capture at select-window CLOSE. The MCU has had the whole
    //                 window to respond; the Z80 reads it during the NEXT window.
    //   HOLD_MODE 2 = capture at select-window OPEN, i.e. the value the MCU
    //                 settled on during the PREVIOUS window.
    // 1 and 2 differ by one transfer of pipelining. I do not know which matches
    // the real 06xx's data latch, so both are exposed rather than guessed --
    // and CTRL-REARM-FIX-2026-08-10 is the standing warning about shipping a
    // "more faithful" 06xx change without measuring it.
    localparam HOLD_MODE = 0;   // HOLDMODE-0-2026-09-20 (was 1)

    wire win_close = enabled && base_ce && !pause && (div_cnt == div_limit) &&  timer_state;
    wire win_open  = enabled && base_ce && !pause && (div_cnt == div_limit) && ~timer_state;

    reg [7:0] data_r_hold;
    always @(posedge clk) begin
        if (reset)                                  data_r_hold <= 8'hFF;
        else if (HOLD_MODE == 1 ? win_close : win_open) data_r_hold <= data_r_val;
    end

    wire [7:0] data_r_sel = (HOLD_MODE == 0) ? data_r_val : data_r_hold;

    assign cpu_din = ctrl_rd ? ctrl : (ctrl[4] ? data_r_sel : 8'h00);

    // ---- data_w: deferred broadcast to selected chips in write mode -------
    reg [7:0] chip_dout_r;
    reg [3:0] chip_wr_r;
    always @(posedge clk) begin
        chip_wr_r <= 4'h0;
        if (data_apply && wmode) begin
            chip_dout_r <= data_wdata_d;
            chip_wr_r   <= ctrl[3:0];
        end
    end
    assign chip_dout = chip_dout_r;
    assign chip_wr   = chip_wr_r;

endmodule

`default_nettype wire
