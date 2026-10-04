// ============================================================================
//  mb88.sv  —  Fujitsu MB88xx 4-bit MCU core (MB8841/8843 family)
//  Greenfield, correctness-first re-implementation in SystemVerilog for Verilator
//  co-sim debugging (primary target: Kangaroo MB8841 protection MCU bug).
//
//  Oracle: MAME cpu/mb88xx/mb88xx.cpp (opcode-for-opcode).  Verified vs mb88xx.h.
//
//  Architecture (MB8841 = 11-bit program / 7-bit data):
//    A/X/Y = 4-bit; PC = 6-bit + PA = 5-bit -> GETPC = (PA<<6)|PC (11-bit).
//    Data RAM = 128 nibbles, EA = (X<<4)+Y & 0x7F.  Stack = 4 x {flags,PA,PC}.
//    Flags: st(skip-branch), zf(1=zero), cf(carry), vf(timer), sf(serial), if(irq).
//    Reset: all 0, st=1.  st gates ONLY jmp/call/jpl/jpa (MB88 conditional model).
//
//  COMPLETE vs MAME mb88xx.cpp — opcode AND non-opcode.
//  ----------------------------------------------------------------------------
//  OPCODES: all 256 bytes, verified byte-for-byte vs mb88xx.cpp execute_run()
//    (0x00-2f individual; 0x30-3f sbit/rbit/tbit/rti/jpa/en/dis; 0x40-7f setD/
//    rstD/tstD/tba/xd/xyd/lxi/call/jpl/ai; 0x80-bf lyi/li/cyi/ci; 0xc0-ff jmp).
//    No S_ILLEGAL is reachable — mb88 decodes every byte.
//  NON-OPCODE (all implemented):
//    * Interrupts: external-pin (rising-edge), timer-overflow, serial; enabled by
//      pio[2:0]; vectors 0x02 / 0x04 / 0x06 (ext > timer > serial priority).
//    * Timer: internal (pio7, ÷32 prescale) OR external TC pin (pio6) per MAME
//      increment_timer() (2026-07-11 + 2026-07-17 fixes).
//    * SERIAL: 4-bit RECEIVE shift @ clock()/6, armed by pio[5:4]==0x20; shifts SI
//      in, sets sf + serial IRQ after 4 bits; runaway guard (SERIAL_DISABLE_THRESH);
//      tsts re-arm/SBcount-reset. DIRECTED CO-SIM PROVEN: serial fill -> serial IRQ
//      -> vector 0x06 (verilator/mb88 serial_test.bin).
//    * O-port PLA: 8-bit cf-nibble-select outO = MAME write_pla with pla_bits==8
//      (the device default; what the Namco 5xxx use).
//  NOT MODELLED — NONE are gaps (MAME doesn't model them for the default part, or
//  no target device uses them):
//    * STANDBY (stby_n pin): MAME has no standby/STOP state for mb88.
//    * External-clock serial (pio 0x10/0x30): MAME fatalerror's it (unsupported).
//    * 4-bit loadable output PLA (set_pla_bits(4)+set_pla_data): opt-in per-device
//      table; add a pla_data port only if a target programs a custom output PLA.
// ============================================================================

// IRQ-ENTRY-STALL-2026-09-23: extra ce cycles spent entering an interrupt before the handler's first
// fetch. 0 = legacy 1-ce entry (51xx/52xx/53xx rely on it; the global MAME-exact change broke the
// 51xx and the main-CPU POST on 2026-09-19). 3 = MAME burn_cycles(3); the 54xx needs it or its IRQ
// handler reads the command latch before the 06xx byte lands (verilator/n54_cosim).
module mb88_core #(parameter IRQ_ENTRY_STALL = 0)
(
    input  wire        clk, ce, reset_n,
    input  wire        ena_timer,      // timer enable (already ÷32-prescaled externally)

    // internal mask ROM (external here so the co-sim / core can load it)
    output wire [10:0] prog_addr,
    input  wire [7:0]  prog_data,

    // ports
    input  wire [3:0]  k_in,           // K3-K0 input-only
    input  wire [15:0] r_in,           // R0..R3 (4 ports x 4 bits) input
    output reg  [15:0] r_out,          // R0..R3 output latch
    output reg  [3:0]  p_out,          // P output latch
    output reg  [7:0]  o_out,          // O output latch (via PLA - stubbed identity)
    // O-PORT-STROBE-2026-08-09: pulses for one ce cycle on EVERY outO instruction,
    // whether or not o_out's value changed. MAME's write_pla() ends with an
    // unconditional `m_write_o(0, m_o_output, mask)` (mb88xx.cpp:373), so consumers
    // that latch the O port (e.g. namco_51xx's shared mailbox = MAME m_portO) must
    // re-latch on every write, not on a value change. Purely additive: existing
    // instantiations that leave it unconnected are unaffected.
    output reg         o_wr,
    input  wire        si_in,
    output reg         so_out,
    input  wire        irq_n, tc_in,   // real IRQ pins (TODO: internal trigger path)

    // interrupt injection (harness drives from the MAME trace during bug hunt)
    input  wire        int_req,        // take an interrupt at the next fetch boundary
    input  wire [5:0]  int_vec,        // vector PC (0x02 ext / 0x04 timer / 0x06 serial)

    // debug taps
    output wire [10:0] dbg_pc,          // current {PA,PC} (post-execution on retire)
    output wire [10:0] dbg_fetch_pc,    // PC of the executing instruction (matches MAME)
    output wire [3:0]  dbg_a, dbg_x, dbg_y,
    output wire        dbg_st, dbg_zf, dbg_cf,
    output wire        dbg_retire,
    output wire        dbg_int_ack,     // pulses when an interrupt is taken
    output wire        dbg_illegal,
    output wire [511:0] dbg_ram        // 128 nibbles {ram[127]..ram[0]}
);
    // ---- architectural state ----
    reg [5:0]  PC;
    reg [4:0]  PA;
    reg [3:0]  A, X, Y;
    reg        st, zf, cf, vf, sf, iflag;
    reg [15:0] SP [0:3];       // {cf,zf,st,--,PA[4:0],PC[5:0]}
    reg [1:0]  SI;
    reg [3:0]  TH, TL, SB;
    reg [7:0]  pio;
    reg [3:0]  ram [0:127];
    reg        retire, illegal;
    reg        in_irq, int_ack;
    reg  [1:0] irq_stall;                        // IRQ-ENTRY-STALL-2026-09-23
    reg        tc_in_d;       // TC pin level registered, for external-counter falling-edge detect
    reg [10:0] fetch_pc;
    reg [2:0]  pending_irq;    // {external, timer, serial} pending  (bit2/1/0)
    reg [5:0]  TP;             // timer prescaler (÷32)
    // ---- SERIAL (2026-07-18; faithful to MAME mb88xx.cpp serial_timer()/pio_enable()) ----
    // 4-bit RECEIVE shift register clocked at clock()/SERIAL_PRESCALE(=6), armed when
    // pio[5:4]==2'b10 (MAME's (m_pio & 0x30)==0x20 = internal serial clock). Each tick
    // shifts SI into SB bit3; after 4 bits sets sf + serial IRQ (pending_irq[0], vec 0x06).
    // sf blocks further shifting until tsts clears it; SBcount runaway-disables at THRESH
    // (MAME anti-hang). External-clock serial (pio 0x10/0x30) is unsupported by MAME
    // (fatalerror) so we just don't tick. SO/transmit is not modeled in MAME's mb88 either.
    reg [10:0] SBcount;        // serial tick counter (reaches SERIAL_DISABLE_THRESH)
    reg [2:0]  serial_ps;      // ÷6 serial prescaler (counts ce)
    reg        serial_disabled;// runaway guard tripped; re-armed by tsts
    localparam [10:0] SERIAL_THRESH = 11'd1000;   // MAME SERIAL_DISABLE_THRESH
    // enabled+pending interrupt sources and the winning vector (ext>timer>serial)
    wire [2:0] active_irq = pending_irq & pio[2:0];
    wire [5:0] hw_vec = active_irq[2] ? 6'h02 : active_irq[1] ? 6'h04 : 6'h06;
    wire serial_running = (pio[5:4]==2'b10) && !serial_disabled;   // internal serial enabled

    localparam [1:0] S_FETCH=0, S_FETCH2=1, S_ILLEGAL=2;
    reg [1:0] state;
    reg [7:0] op1;             // latched opcode for 2-byte insns

    // ---- combinational helpers ----
    wire [6:0] ea = {X[2:0], Y};                 // (X<<4)+Y masked to 7 bits
    wire [3:0] mem = ram[ea];
    assign prog_addr = {PA, PC};                 // GETPC
    wire [7:0] op = prog_data;
    wire timer_ovf_now = ena_timer && pio[7] && (TL == 4'hF) && (TH == 4'hF);

    // INCPC (PC 6-bit rolls into PA at 0x40)
    wire [5:0] pc_n = (PC==6'h3f) ? 6'h00 : PC + 6'd1;
    wire [4:0] pa_n = (PC==6'h3f) ? PA + 5'd1 : PA;
    wire [15:0] sp_pop = SP[SI-2'd1];   // top of stack (avoids SP[idx][bits] construct)

    assign dbg_pc={PA,PC}; assign dbg_fetch_pc=fetch_pc;
    assign dbg_a=A; assign dbg_x=X; assign dbg_y=Y;
    assign dbg_st=st; assign dbg_zf=zf; assign dbg_cf=cf;
    assign dbg_retire=retire; assign dbg_int_ack=int_ack; assign dbg_illegal=illegal;
    genvar gi;
    generate
      for (gi=0; gi<128; gi=gi+1) begin : g_dbgram
        assign dbg_ram[gi*4 +: 4] = ram[gi];
      end
    endgenerate

    // scratch
    reg [4:0] add5;            // 5-bit ALU (carry in bit4)
    reg [7:0] sub8;            // 8-bit for subtract borrow (bit4 = borrow)
    reg [3:0] wr_val; reg [6:0] wr_addr; reg wr_en;
    integer i;

    always @(posedge clk) begin
        if (!reset_n) begin
            PC<=0; PA<=0; A<=0; X<=0; Y<=0;
            st<=1; zf<=0; cf<=0; vf<=0; sf<=0; iflag<=0;
            SI<=0; TH<=0; TL<=0; SB<=0; pio<=0;
            // R0 resets HIGH (MB8841.pdf: output ports high during reset); R1-R3 low
            // (R3.3 high => spurious NMI). Z80 reads R0.bit1 at boot to arm E039 — must be 1.
            r_out<=16'h000F; p_out<=0; o_out<=0; so_out<=0; o_wr<=1'b0;
            retire<=0; illegal<=0; state<=S_FETCH; op1<=0; irq_stall<=2'd0;
            in_irq<=0; int_ack<=0; fetch_pc<=0; pending_irq<=0; TP<=0; tc_in_d<=1'b1;
            SBcount<=11'd0; serial_ps<=3'd0; serial_disabled<=1'b0;
            // SP[] and ram[] intentionally NOT reset (MAME device_reset doesn't
            // clear data RAM/stack; ROM inits RAM; Verilator zero-inits arrays).
        end else begin
          // external IRQ pin (active-low): logical rising edge sets pending if enabled
          iflag <= ~irq_n;
          if (~irq_n && !iflag && pio[2]) pending_irq[2] <= 1'b1;
          // TC-TIMER-FIX-2026-07-17: external-counter timer path. MAME mb88xx.cpp:
          //   `if (m_ctr && !state && (m_pio & 0x40)) increment_timer();  m_ctr = state;`
          // i.e. on a FALLING edge of the TC pin, if external-counter mode (pio bit6/0x40)
          // is enabled, tick the SAME timer. This drives the 51xx's per-frame timer, which
          // MAME clocks from screen vblank (namco51.cpp vblank() -> MB88XX_TC_LINE). `tc_in`
          // is the TC pin LEVEL; register it here (every clk, ungated) to catch the edge.
          tc_in_d <= tc_in;
          // timer: ena_timer is ALREADY ÷32-prescaled externally (Kangaroo mcu_tp),
          // so increment TL directly -> TH cascade -> overflow -> timer IRQ pending. Two
          // mutually-exclusive sources feed the ONE counter (a chip uses internal OR external
          // mode, never both): internal clock (ena_timer & pio7 = MAME 0x80), OR external TC
          // falling edge (pio6 = MAME 0x40).
          if ((ena_timer && pio[7]) || ((tc_in_d & ~tc_in) && pio[6])) begin  // MCU-TIMER-FIX-2026-07-11: pio7 gate (MAME 0x80); TC-TIMER-FIX-2026-07-17: + external TC path (pio6/MAME 0x40)
            TL <= TL + 4'd1;
            if (TL == 4'hF) begin
              TH <= TH + 4'd1;
              if (TH == 4'hF) begin vf <= 1'b1; pending_irq[1] <= 1'b1; end
            end
          end
          // ---- SERIAL receive engine (MAME serial_timer). ce-paced ÷6 prescaler. Placed
          // BEFORE the instruction block so a coincident tsts (clears sf/SBcount) overrides. ----
          if (ce) begin
            if (serial_running) begin
              // MAME SERIAL_PRESCALE=6 divides the MB88 PIN
              // clock; `ce` is already pin/6 (MCU_CEN_DIV), so the /6 must not be
              // applied twice. Serial shifts once per machine cycle.
              if (serial_ps == 3'd0) begin
                serial_ps <= 3'd0;
                SBcount   <= SBcount + 11'd1;
                if ((SBcount + 11'd1) >= SERIAL_THRESH) serial_disabled <= 1'b1;   // runaway guard
                if (!sf) begin
                  SB <= {si_in, SB[3:1]};                       // MAME: SB = (SB>>1) | (si?8:0)
                  if ((SBcount + 11'd1) >= 11'd4) begin sf <= 1'b1; pending_irq[0] <= 1'b1; end
                end
              end else serial_ps <= serial_ps + 3'd1;
            end else serial_ps <= 3'd0;   // hold phase reset while disarmed (timer restarts on arm)
          end
          if (ce) begin
            retire <= 1'b0; int_ack <= 1'b0;
            o_wr <= 1'b0;                       // O-PORT-STROBE-2026-08-09
            wr_en = 1'b0; wr_val = 4'h0; wr_addr = 7'h0;
            if (irq_stall != 2'd0) irq_stall <= irq_stall - 2'd1;   // IRQ-ENTRY-STALL: no fetch while entering
            else
            case (state)
            // ==================================================================
            S_FETCH: if ((int_req || |active_irq) && !in_irq) begin
                // ---- take interrupt: push {flags,return PC}, vector to handler ----
                // int_req = trace-injection (co-sim diff); active_irq = real HW path.
                SP[SI] <= {cf, zf, st, 2'b00, PA, PC};   // return addr = deferred insn
                SI <= SI + 2'd1;
                PA <= 5'd0; PC <= int_req ? int_vec : hw_vec;  // ext 0x02/timer 0x04/serial 0x06
                in_irq <= 1'b1; st <= 1'b1; int_ack <= 1'b1;   // no retire (not an insn)
                pending_irq <= 3'b000;                          // MAME clears all pending on take
                irq_stall <= IRQ_ENTRY_STALL[1:0];              // IRQ-ENTRY-STALL-2026-09-23
            end else begin
                fetch_pc <= {PA,PC};     // executing instruction's own PC (matches MAME)
                PC<=pc_n; PA<=pa_n;      // default INCPC (branches override below)
                retire<=1'b1;
                case (op)
                8'h00: st<=1;                                   // nop
                // outO: cf=1->oh, cf=0->ol (MAME write_pla 8-bit / VHDL). o_wr pulses
                // unconditionally here — see the O-PORT-STROBE note on the port decl.
                8'h01: begin if (cf) o_out[7:4]<=A; else o_out[3:0]<=A; o_wr<=1'b1; st<=1; end
                8'h02: begin p_out<=A; st<=1; end               // outP
                8'h03: begin r_out[Y[1:0]*4 +: 4]<=A; st<=1; end// outR
                8'h04: begin Y<=A; st<=1; end                   // tay
                8'h05: begin TH<=A; st<=1; end                  // tath
                8'h06: begin TL<=A; st<=1; end                  // tatl
                8'h07: begin SB<=A; st<=1; end                  // tas
                8'h08: begin add5={1'b0,Y}+5'd1; st<=~add5[4]; Y<=add5[3:0]; zf<=(add5[3:0]==0); end // icy
                8'h09: begin add5={1'b0,mem}+5'd1; st<=~add5[4]; zf<=(add5[3:0]==0); wr_en=1;wr_addr=ea;wr_val=add5[3:0]; end // icm
                8'h0a: begin wr_en=1;wr_addr=ea;wr_val=A; add5={1'b0,Y}+5'd1; st<=~add5[4]; Y<=add5[3:0]; zf<=(add5[3:0]==0); end // stic
                8'h0b: begin A<=mem; wr_en=1;wr_addr=ea;wr_val=A; zf<=(mem==0); st<=1; end // x (swap A,mem)
                8'h0c: begin add5={A,cf}; st<=~add5[4]; cf<=add5[4]; A<=add5[3:0]; zf<=(add5[3:0]==0); end // rol
                8'h0d: begin A<=mem; zf<=(mem==0); st<=1; end   // l
                8'h0e: begin add5={1'b0,mem}+{1'b0,A}+{4'b0,cf}; st<=~add5[4]; cf<=add5[4]; A<=add5[3:0]; zf<=(add5[3:0]==0); end // adc
                8'h0f: begin A<=A&mem; zf<=((A&mem)==0); st<=((A&mem)==0)?1'b0:1'b1; end // and (st=zf^1)
                8'h10: begin add5=(cf||A>9)?({1'b0,A}+5'd6):{1'b0,A}; st<=~add5[4]; cf<=add5[4]; A<=add5[3:0]; end // daa
                8'h11: begin add5=(cf||A>9)?({1'b0,A}+5'd10):{1'b0,A}; st<=~add5[4]; cf<=add5[4]; A<=add5[3:0]; end // das
                8'h12: begin A<=k_in; zf<=(k_in==0); st<=1; end // inK
                8'h13: begin A<=r_in[Y[1:0]*4 +: 4]; zf<=(r_in[Y[1:0]*4 +: 4]==0); st<=1; end // inR
                8'h14: begin A<=Y; zf<=(Y==0); st<=1; end       // tya
                8'h15: begin A<=TH; zf<=(TH==0); st<=1; end     // ttha
                8'h16: begin A<=TL; zf<=(TL==0); st<=1; end     // ttla
                8'h17: begin A<=SB; zf<=(SB==0); st<=1; end     // tsa
                8'h18: begin sub8={4'b0,Y}-8'd1; st<=~sub8[4]; Y<=sub8[3:0]; end // dcy
                8'h19: begin sub8={4'b0,mem}-8'd1; st<=~sub8[4]; zf<=(sub8[3:0]==0); wr_en=1;wr_addr=ea;wr_val=sub8[3:0]; end // dcm
                8'h1a: begin wr_en=1;wr_addr=ea;wr_val=A; sub8={4'b0,Y}-8'd1; st<=~sub8[4]; Y<=sub8[3:0]; zf<=(sub8[3:0]==0); end // stdc
                8'h1b: begin A<=X; X<=A; zf<=(X==0); st<=1; end // xx (swap A,X)
                8'h1c: begin st<=~A[0]; cf<=A[0]; A<={cf,A[3:1]}; zf<=({cf,A[3:1]}==0); end // ror
                8'h1d: begin wr_en=1;wr_addr=ea;wr_val=A; st<=1; end // st
                8'h1e: begin sub8={4'b0,mem}-{4'b0,A}-{7'b0,cf}; st<=~sub8[4]; cf<=sub8[4]; A<=sub8[3:0]; zf<=(sub8[3:0]==0); end // sbc
                8'h1f: begin A<=A|mem; zf<=((A|mem)==0); st<=((A|mem)==0)?1'b0:1'b1; end // or
                8'h20: begin r_out[{Y[3:2],2'b0} +: 4] <= (r_in[{Y[3:2],2'b0} +: 4] | (4'd1<<Y[1:0])); st<=1; end // setR
                8'h21: begin cf<=1; st<=1; end                  // setc
                8'h22: begin r_out[{Y[3:2],2'b0} +: 4] <= (r_in[{Y[3:2],2'b0} +: 4] & ~(4'd1<<Y[1:0])); st<=1; end // rstR
                8'h23: begin cf<=0; st<=1; end                  // rstc
                8'h24: st <= (r_in[{Y[3:2],2'b0} +: 4] & (4'd1<<Y[1:0])) ? 1'b0 : 1'b1; // tstr
                8'h25: st <= ~iflag;                            // tsti
                8'h26: begin st<=~vf; if (!timer_ovf_now) vf<=0; end // tstv — MCU-TIMERVF-FIX-2026-07-11: skip clear on coincident overflow; was "vf<=0;" unconditional
                8'h27: begin st<=~sf;                          // tsts: st=~sf; if(sf){re-arm+SBcount=0}; sf=0
                             if (sf) begin
                               if (SBcount >= SERIAL_THRESH) serial_disabled <= 1'b0;  // re-enable runaway-disabled serial
                               SBcount <= 11'd0;
                             end
                             sf <= 1'b0; end
                8'h28: st <= ~cf;                               // tstc
                8'h29: st <= ~zf;                               // tstz
                8'h2a: begin wr_en=1;wr_addr=ea;wr_val=SB; zf<=(SB==0); st<=1; end // sts
                8'h2b: begin SB<=mem; zf<=(mem==0); st<=1; end  // ls
                8'h2c: begin SI<=SI-2'd1; PC<=sp_pop[5:0]; PA<=sp_pop[10:6]; st<=1; end // rts
                8'h2d: begin A<=(~A)+4'd1; st<=(((~A)+4'd1)==0)?1'b0:1'b1; end // neg
                8'h2e: begin sub8={4'b0,mem}-{4'b0,A}; cf<=sub8[4]; st<=(sub8[3:0]==0)?1'b0:1'b1; zf<=(sub8[3:0]==0)?1'b1:1'b0; end // c
                8'h2f: begin A<=A^mem; st<=((A^mem)==0)?1'b0:1'b1; zf<=((A^mem)==0)?1'b1:1'b0; end // eor
                8'h30,8'h31,8'h32,8'h33: begin wr_en=1;wr_addr=ea;wr_val=mem|(4'd1<<op[1:0]); st<=1; end // sbit
                8'h34,8'h35,8'h36,8'h37: begin wr_en=1;wr_addr=ea;wr_val=mem&~(4'd1<<op[1:0]); st<=1; end // rbit
                8'h38,8'h39,8'h3a,8'h3b: st <= (mem & (4'd1<<op[1:0])) ? 1'b0 : 1'b1; // tbit
                8'h3c: begin SI<=SI-2'd1; PC<=sp_pop[5:0]; PA<=sp_pop[10:6]; // rti
                             st<=sp_pop[13]; zf<=sp_pop[14]; cf<=sp_pop[15]; in_irq<=1'b0; end
                8'h3d,8'h3e,8'h3f: begin op1<=op; retire<=1'b0; state<=S_FETCH2; end // jpa/en/dis (2-byte)
                8'h40,8'h41,8'h42,8'h43: begin r_out[3:0]<=(r_in[3:0]|(4'd1<<op[1:0])); st<=1; end // setD (R0)
                8'h44,8'h45,8'h46,8'h47: begin r_out[3:0]<=(r_in[3:0]&~(4'd1<<op[1:0])); st<=1; end // rstD (R0)
                8'h48,8'h49,8'h4a,8'h4b: st <= (r_in[11:8] & (4'd1<<op[1:0])) ? 1'b0 : 1'b1; // tstD (R2)
                8'h4c,8'h4d,8'h4e,8'h4f: st <= (A & (4'd1<<op[1:0])) ? 1'b0 : 1'b1; // tba
                8'h50,8'h51,8'h52,8'h53: begin A<=ram[{5'b0,op[1:0]}]; wr_en=1;wr_addr={5'b0,op[1:0]};wr_val=A; zf<=(ram[{5'b0,op[1:0]}]==0); st<=1; end // xd
                8'h54,8'h55,8'h56,8'h57: begin Y<=ram[7'd4+{5'b0,op[1:0]}]; wr_en=1;wr_addr=7'd4+{5'b0,op[1:0]};wr_val=Y; zf<=(ram[7'd4+{5'b0,op[1:0]}]==0); st<=1; end // xyd
                8'h58,8'h59,8'h5a,8'h5b,8'h5c,8'h5d,8'h5e,8'h5f: begin X<={1'b0,op[2:0]}; zf<=(op[2:0]==0); st<=1; end // lxi
                8'h60,8'h61,8'h62,8'h63,8'h64,8'h65,8'h66,8'h67: begin op1<=op; retire<=1'b0; state<=S_FETCH2; end // call
                8'h68,8'h69,8'h6a,8'h6b,8'h6c,8'h6d,8'h6e,8'h6f: begin op1<=op; retire<=1'b0; state<=S_FETCH2; end // jpl
                8'h70,8'h71,8'h72,8'h73,8'h74,8'h75,8'h76,8'h77,
                8'h78,8'h79,8'h7a,8'h7b,8'h7c,8'h7d,8'h7e,8'h7f: begin add5={1'b0,A}+{1'b0,op[3:0]}; st<=~add5[4]; cf<=add5[4]; A<=add5[3:0]; zf<=(add5[3:0]==0); end // ai
                8'h80,8'h81,8'h82,8'h83,8'h84,8'h85,8'h86,8'h87,
                8'h88,8'h89,8'h8a,8'h8b,8'h8c,8'h8d,8'h8e,8'h8f: begin Y<=op[3:0]; zf<=(op[3:0]==0); st<=1; end // lyi
                8'h90,8'h91,8'h92,8'h93,8'h94,8'h95,8'h96,8'h97,
                8'h98,8'h99,8'h9a,8'h9b,8'h9c,8'h9d,8'h9e,8'h9f: begin A<=op[3:0]; zf<=(op[3:0]==0); st<=1; end // li
                8'ha0,8'ha1,8'ha2,8'ha3,8'ha4,8'ha5,8'ha6,8'ha7,
                8'ha8,8'ha9,8'haa,8'hab,8'hac,8'had,8'hae,8'haf: begin sub8={4'b0,op[3:0]}-{4'b0,Y}; cf<=sub8[4]; st<=(sub8[3:0]==0)?1'b0:1'b1; zf<=(sub8[3:0]==0)?1'b1:1'b0; end // cyi
                8'hb0,8'hb1,8'hb2,8'hb3,8'hb4,8'hb5,8'hb6,8'hb7,
                8'hb8,8'hb9,8'hba,8'hbb,8'hbc,8'hbd,8'hbe,8'hbf: begin sub8={4'b0,op[3:0]}-{4'b0,A}; cf<=sub8[4]; st<=(sub8[3:0]==0)?1'b0:1'b1; zf<=(sub8[3:0]==0)?1'b1:1'b0; end // ci
                default: begin if (st) PC<=op[5:0]; st<=1; end  // jmp within page (INCPC-then-override, matches MAME)
                endcase
            end
            // ==================================================================
            // ==================================================================
            S_FETCH2: begin
                PC<=pc_n; PA<=pa_n;                 // consume operand byte
                retire<=1'b1; state<=S_FETCH;
                case (op1)
                8'h3d: begin PA<=op[4:0]; PC<={A,2'b00}; st<=1; end          // jpa: PA=imm, PC=A*4
                8'h3e: begin pio<=pio | op; st<=1; end                        // en
                8'h3f: begin pio<=pio & ~op; st<=1; end                       // dis
                8'h60,8'h61,8'h62,8'h63,8'h64,8'h65,8'h66,8'h67: begin        // call
                    if (st) begin
                        SP[SI] <= {5'b0, pa_n, pc_n};      // return addr (past operand)
                        SI <= SI + 2'd1;
                        PC <= op[5:0];
                        PA <= {op1[2:0], op[7:6]};
                    end
                    st<=1;
                end
                8'h68,8'h69,8'h6a,8'h6b,8'h6c,8'h6d,8'h6e,8'h6f: begin        // jpl
                    if (st) begin PC <= op[5:0]; PA <= {op1[2:0], op[7:6]}; end
                    st<=1;
                end
                default: ;
                endcase
            end
            S_ILLEGAL: ;
            default: state<=S_FETCH;
            endcase

            if (wr_en) ram[wr_addr] <= wr_val;
          end   // if (ce)
        end     // else (not reset)
    end

    // verilator lint_off UNUSED
    wire _unused = &{1'b0, si_in, irq_n, sf, vf, pio, TH, TL, op[7]};
    // verilator lint_on UNUSED
endmodule
