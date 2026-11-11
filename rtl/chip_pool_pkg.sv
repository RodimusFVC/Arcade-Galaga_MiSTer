//============================================================================
//
//  chip_pool_pkg - bus types for a multi-board core's shared CPU / sound chip pool
//  Copyright (C) 2026 Rodimus
//
//  Master copy: RodimusCoresMaster_MiSTer/rtl/chip_pool_pkg.sv; sync.sh copies it into each core unchanged.
//  Only one board runs at a time, so each CPU / sound chip is instanced once in the core's dispatcher and the
//  active board drives it through these buses (selected by variant). <chip>_i_t = board to chip, <chip>_o_t =
//  chip to every board. Reset is the core reset unless a type carries its own reset as the first field.
//  Types are named after the instanced module's interface; a new type only when the pins differ.
//  Add new types here, in the master, never in a core's copy.
//
//============================================================================

package chip_pool_pkg;


// Z80 (T80s, Mode 0, T2Write 1, IOWait 1; WAIT_n / BUSRQ_n inactive)
typedef struct packed {
    logic        ce;
    logic        int_n;
    logic        nmi_n;
    logic  [7:0] di;
} z80_i_t;

typedef struct packed {
    logic [15:0] a;
    logic  [7:0] dout;
    logic        m1_n;
    logic        mreq_n;
    logic        iorq_n;
    logic        rd_n;
    logic        wr_n;
    logic        rfsh_n;
} z80_o_t;

// Z80 (T80s, as z80_i_t) with RESET_n on the bus: Konami82's board watchdogs reset the main and sound CPUs
typedef struct packed {
    logic        reset_n;
    logic        ce;
    logic        int_n;
    logic        nmi_n;
    logic  [7:0] di;
} z80r_i_t;

typedef struct packed {
    logic [15:0] a;
    logic  [7:0] dout;
    logic        m1_n;
    logic        mreq_n;
    logic        iorq_n;
    logic        rd_n;
    logic        wr_n;
    logic        rfsh_n;
} z80r_o_t;

// MC6809E (mc6809is; DMABREQ inactive) with RESET and HALT on the bus: Konami82's board watchdogs, Qix's OSD pause (HALT).
// A core that doesn't use HALT ties nHALT high in its dispatcher and leaves halt_n undriven
typedef struct packed {
    logic        reset_n;
    logic        halt_n;
    logic        fall_e;
    logic        fall_q;
    logic        irq_n;
    logic        firq_n;
    logic        nmi_n;
    logic  [7:0] d;
} m6809r_i_t;

typedef struct packed {
    logic [15:0] a;
    logic  [7:0] dout;
    logic        rw;
    logic        lic;
} m6809r_o_t;

// AY-3-8910 (jt49_bus, sel = 1)
typedef struct packed {
    logic        ce;
    logic        bdir;
    logic        bc1;
    logic  [7:0] din;
    logic  [7:0] ioa_in;
    logic  [7:0] iob_in;
} ay_i_t;

typedef struct packed {
    logic  [7:0] dout;
    logic  [7:0] a;
    logic  [7:0] b;
    logic  [7:0] c;
    logic  [7:0] iob_out;
    logic  [9:0] sound;                 // jt49 internal A+B+C mix (registered per accumulator cycle)
} ay_o_t;

// 8035 / 8039 (T48 t8039_notri_extrom, EA low, program on pmem). Superset of every core's pins: a core that doesn't use
// reset_n / T0 / T1 / the port inputs / the MOVX bus ties those pins in its dispatcher and leaves the fields undriven.
typedef struct packed {
    logic        reset_n;
    logic        xtal_en;
    logic        int_n;
    logic        t0;
    logic        t1;
    logic  [7:0] p1_in;
    logic  [7:0] p2_in;
    logic  [7:0] db;                    // MOVX read data
    logic  [7:0] pmem_d;
} mcs48_i_t;

typedef struct packed {
    logic  [7:0] p1;
    logic  [7:0] p2;
    logic [11:0] pmem_a;
    logic        rd_n;
    logic        wr_n;
    logic        ale;
    logic  [7:0] db;                    // address (at ALE) / MOVX write data
    logic        db_dir;                // 1 = the 8039 drives db (Sega speech board latch timing)
} mcs48_o_t;

// UPI-41 / 8041 (t48sv_upi41_core, every pin; clocks xtal_i / clk_i stay on the instance). reset_n is active-low
// (T48 res_active_c = 0). pmem = program store, dmem = 64/128 x 8 data RAM (pool blocks in the dispatcher).
typedef struct packed {
    logic        reset_n;
    logic        xtal_en;
    logic        en_clk;
    logic        t0;
    logic        t1;
    logic        cs_n;
    logic        rd_n;
    logic        wr_n;
    logic        a0;
    logic  [7:0] db;
    logic  [7:0] p1_in;
    logic  [7:0] p2_in;
    logic  [7:0] dmem_d;
    logic  [7:0] pmem_d;
} upi41_i_t;

typedef struct packed {
    logic        sync;
    logic  [7:0] db;
    logic  [7:0] sts;
    logic        db_dir;
    logic  [7:0] p1;
    logic  [7:0] p2;
    logic        p1_low_imp;
    logic        p2l_low_imp;
    logic        p2h_low_imp;
    logic        prog_n;
    logic        xtal3;
    logic  [7:0] dmem_a;
    logic        dmem_we;
    logic  [7:0] dmem_d;
    logic [10:0] pmem_a;
} upi41_o_t;

// Z80 (T80pa, Mode 0). Superset of every core's pins: a core without a DMA ties BUSRQ_n high in its dispatcher and leaves
// busrq_n / busak_n undriven; inte = IFF1 (T80pa REG bit 210: the 8080's INTE pin for an 8080 board). RESET_n is on the bus:
// Lady Bug / 8203 hold their CPUs in reset ~48 ms past the core reset
typedef struct packed {
    logic        reset_n;
    logic        cen_p;
    logic        cen_n;
    logic        wait_n;
    logic        int_n;
    logic        nmi_n;
    logic        busrq_n;
    logic  [7:0] di;
} z80pa_i_t;

typedef struct packed {
    logic [15:0] a;
    logic  [7:0] dout;
    logic        m1_n;
    logic        mreq_n;
    logic        iorq_n;
    logic        rd_n;
    logic        wr_n;
    logic        rfsh_n;
    logic        busak_n;
    logic        inte;                    // IFF1 (an 8080 board's INTE pin)
} z80pa_o_t;

// SN76489 family PSG: chips-repo sn76489sv (VARIANT = the chip) or jt89 (INTERPOL16 0, MODE 0), same pins. sn76489sv's
// sound is the real chip's 0..1020 (jt89: +-1020). rst is on the bus: some boards reset their PSGs on power-on only
typedef struct packed {
    logic        rst;
    logic        ce;
    logic        wr_n;
    logic        cs_n;
    logic  [7:0] din;
} sn76489_i_t;

typedef struct packed {
    logic [10:0] sound;                 // signed field: sn76489sv 0..1020, jt89 +-1020
    logic        ready;
} sn76489_o_t;

// MB88 (mb88 / mb88_core; STBY / SC inputs inactive, RAM clear = core reset)
typedef struct packed {
    logic        ena;
    logic        reset_n;
    logic  [3:0] k;
    logic [15:0] r_in;          // {R3, R2, R1, R0}
    logic        irq_n;
    logic        tc_n;
    logic        si_n;
    logic  [7:0] rom_d;
} mb88_i_t;

typedef struct packed {
    logic [15:0] r_out;         // {R3, R2, R1, R0}
    logic  [7:0] o;             // {OH, OL}
    logic        o_wr;
    logic  [3:0] p;
    logic [10:0] rom_a;
} mb88_o_t;

// ---- types added by the cores (first user in brackets) ----

// Z80 (T80sed; BUSRQ_n inactive). RESET_n and WAIT_n are on the bus: Galaxian's main CPU has video RAM waits and a
// watchdog / CPU-select reset; its sound boards hold their Z80 in reset on sets that do not use them
typedef struct packed {
    logic        reset_n;
    logic        ce;
    logic        wait_n;
    logic        int_n;
    logic        nmi_n;
    logic  [7:0] di;
} z80sed_i_t;

typedef struct packed {
    logic [15:0] a;
    logic  [7:0] dout;
    logic        m1_n;
    logic        mreq_n;
    logic        iorq_n;
    logic        rd_n;
    logic        wr_n;
    logic        rfsh_n;
} z80sed_o_t;

// S2650 (s2650_cpu around sgs2650; ivec 03, flag unused). reset is on the bus: watchdog reset, held in reset on
// sets that do not use it
typedef struct packed {
    logic        reset;
    logic        ack;
    logic  [7:0] dr;
    logic        irq;
    logic        sense;
} s2650_i_t;

typedef struct packed {
    logic        req;
    logic [14:0] ad;
    logic        wr;
    logic  [7:0] dw;
    logic        mio;
    logic        ene;
    logic        dc;
    logic  [1:0] ph;
    logic        intack;
} s2650_o_t;

// 6502 (stock T65, Mode 00). Enable = one CPU cycle. res_n on the bus: Punch-Out's main
// latch Q3 resets the RP2A03. Verbatim copy of Arcade-Nintendo's t65_i_t / t65_o_t (its NEW types, not merged yet).
typedef struct packed {
    logic        res_n;
    logic        enable;
    logic        rdy;
    logic        irq_n;
    logic        nmi_n;
    logic  [7:0] di;
} t65_i_t;

typedef struct packed {
    logic [15:0] a;
    logic  [7:0] dout;
    logic        rw;                    // 1 = read
    logic        sync;                  // opcode fetch (T65 Sync pin); every dispatcher drives it (DECO Cassette deco222 decrypt reads it)
} t65_o_t;

// 8039 with its external bus (T48 t8039_notri_extrom, EA low, program on pmem; T0 low, P2 inputs high): BUS / ALE /
// WR out, T1 and P1 inputs used. reset_n is on the bus: held in reset on sets that do not use it
typedef struct packed {
    logic        reset_n;
    logic        xtal_en;
    logic        int_n;
    logic        t1;
    logic  [7:0] db;
    logic  [7:0] p1;
    logic  [7:0] pmem_d;
} mcs48bus_i_t;

typedef struct packed {
    logic  [7:0] p1;
    logic  [7:0] p2;
    logic  [7:0] db;
    logic        ale;
    logic        wr_n;
    logic        rd_n;
    logic [11:0] pmem_a;
} mcs48bus_o_t;

// MC6800 / M6802 (jt680x, 6802 microcode; ext_halt and the 6801 on-chip interrupts inactive). rst is on the bus:
// Space Invaders' 8080 board resets it with its watchdog and holds it in reset on sets that do not use it
typedef struct packed {
    logic        rst;
    logic        cen;
    logic        irq;
    logic        nmi;
    logic  [7:0] din;
} m6800_i_t;

typedef struct packed {
    logic [15:0] a;
    logic  [7:0] dout;
    logic        wr;
} m6800_o_t;

// AY-3-8910 (jt49_bus, COMP 3'b010; IOA_in / IOB_in low). sel is on the bus: Tangram Q and Au divide by 2, the rest don't;
// IOA_out / IOB_out = Crazy Climber sample start / loop address
typedef struct packed {
    logic        ce;
    logic        sel;
    logic        bdir;
    logic        bc1;
    logic  [7:0] din;
} aysel_i_t;

typedef struct packed {
    logic  [7:0] dout;
    logic  [7:0] a;
    logic  [7:0] b;
    logic  [7:0] c;
    logic  [7:0] ioa_out;
    logic  [7:0] iob_out;
} aysel_o_t;

// MC6803 (rtl/cpu/m6803.sv around jt680x, 6801 microcode): expanded multiplexed mode, external ROM; on-chip
// registers 0x00-0x1F and RAM 0x80-0xFF, everything else is an external access (x_cs). cen = crystal rate (4 x E)
typedef struct packed {
    logic        cen;
    logic        irq;
    logic        nmi;
    logic  [7:0] xdin;
    logic  [7:0] p1_in;
    logic  [4:0] p2_in;
    logic  [2:0] mode;
} m6803_i_t;

typedef struct packed {
    logic [15:0] addr;
    logic  [7:0] dout;
    logic        wr;
    logic        x_cs;
    logic  [7:0] p1_out;
    logic  [4:0] p2_out;
} m6803_o_t;

// HD63701 (jtframe_6801mcu, MODEL "HD63701V"): rom_data comes from the dispatcher's ROM block
typedef struct packed {
    logic        rst;
    logic        cen;
    logic        cen_tmr;
    logic        irq;
    logic        nmi;
    logic  [7:0] xdin;
    logic  [7:0] p1_din;
    logic  [4:0] p2_din;
    logic  [7:0] p3_din;
    logic  [7:0] p4_din;
} hd63701_i_t;

typedef struct packed {
    logic [15:0] addr;
    logic  [7:0] dout;
    logic        wr;
    logic        x_cs;
    logic        ba;
    logic  [7:0] p1_dout;
    logic  [4:0] p2_dout;
    logic  [7:0] p3_dout;
    logic  [7:0] p4_dout;
} hd63701_o_t;

// Namco CUS30 (jtcus30): b* = main CPU bus, s* = sound CPU bus; snd_l / snd_r are signed
typedef struct packed {
    logic        rst;
    logic        cen;
    logic        bsel;
    logic        bcs;
    logic        brnw;
    logic  [9:0] baddr;
    logic  [7:0] bdout;
    logic        scs;
    logic        srnw;
    logic [15:0] saddr;
    logic  [7:0] sdout;
} cus30_i_t;

typedef struct packed {
    logic  [7:0] xdin;
    logic        sample;
    logic [12:0] snd_l;
    logic [12:0] snd_r;
} cus30_o_t;

// Toshiba TC8830F ADPCM speech (rtl/rodimus/tc8830f): rom_req / rom_addr / rom_data / rom_busy go to the dispatcher's ROM path
typedef struct packed {
    logic        reset;
    logic        pause;
    logic        p_wr;
    logic  [3:0] p_data;
    logic        acl;
} tc8830f_i_t;

typedef struct packed {
    logic [15:0] out;
} tc8830f_o_t;

// RP2A03 (rtl/rodimus/rp2a03): APU + glue around a pooled T65 (its t65_i / t65_o connect to a t65 slot in the dispatcher)
typedef struct packed {
    logic        reset;
    logic        ce;
    logic        nmi_n;
    logic  [7:0] ext_din;
} rp2a03_i_t;

typedef struct packed {
    logic [15:0] ext_a;
    logic        ext_rw;
    logic  [7:0] ext_dout;
    logic [15:0] aux_a;
    logic [15:0] aux_b;
} rp2a03_o_t;

// Williams special chip / blitter (rtl/rodimus/williams_sc): remap_* go to the dispatcher's remap PROM block
typedef struct packed {
    logic        rst;
    logic        run;
    logic        reg_we;
    logic  [2:0] reg_a;
    logic  [7:0] reg_d;
    logic  [2:0] size_xor;
    logic [15:0] clip_addr;
    logic        window;
    logic        remap_en;
    logic  [6:0] remap_idx;
    logic  [7:0] din;
    logic  [7:0] vram_q;
} williams_sc_i_t;

typedef struct packed {
    logic        busy;
    logic [15:0] a;
    logic  [7:0] dout;
    logic        we;
} williams_sc_o_t;

// Sega 315-5018 opcode decryption (rtl/rodimus/sega_315_5018), combinational
typedef struct packed {
    logic  [7:0] src;
    logic [15:0] addr;
    logic        m1;
} sega_315_5018_i_t;

typedef struct packed {
    logic  [7:0] dout;
} sega_315_5018_o_t;

// TMS5110 PROM sequencer (rtl/rodimus/tms5110 tmsprom): rom_addr / rom_q go to the dispatcher's speech ROM block
typedef struct packed {
    logic        reset;
    logic        ce_romclk;
    logic        chip_busy;
    logic        enable;
    logic  [2:0] bit_sel;
    logic        csq0;
    logic        csq1;
    logic        prom_wr;
    logic  [4:0] prom_waddr;
    logic  [7:0] prom_wdata;
    logic        m0;
} tmsprom_i_t;

typedef struct packed {
    logic        data_bit;
    logic  [3:0] ctl;
    logic        pdc;
} tmsprom_o_t;

// Konami 084 starfield + watchdog (rtl/rodimus/k084, Vic20-Ian)
typedef struct packed {
    logic        reset;
    logic        cen_6m;
    logic        hblank;
    logic        vblank;
    logic        blank;
    logic        aux_en;
    logic        stars_en;
    logic        hff;
    logic        h8q;
    logic        v1;
    logic        v2;
    logic  [1:0] hpos_hi;
    logic        wd_kick;
    logic        bootleg_mode;
} k084_i_t;

typedef struct packed {
    logic  [1:0] star_r;
    logic  [1:0] star_g;
    logic  [1:0] star_b;
    logic        star_on;
    logic        wd_reset;
} k084_o_t;

typedef struct packed {
    logic        step;
    logic        rst;
    logic  [3:0] data;
} msm5205_i_t;

typedef struct packed {
    logic [11:0] signal;                // signed
} msm5205_o_t;

// MSM5205 ADPCM (rtl/sound/jt5205, Jose Tejada): cen = the chip's 384 kHz clock, sel = S1/S2 prescaler pins,
// rst = RESET pin. irq = the VCK strobe (sample rate) that feeds the sound CPU's NMI; vclk = the VCK pin level.
typedef struct packed {
    logic        rst;
    logic        cen;
    logic  [1:0] sel;
    logic  [3:0] din;
} jt5205_i_t;

typedef struct packed {
    logic [11:0] sound;                 // signed
    logic        irq;
    logic        vclk;
} jt5205_o_t;

// Z80 / 8085 (T80pa, Mode 0, Phoenix core copy of rtl/cpu/T80: runtime I8080 = 8080 mode, I8085 = opcode 20 is RIM
// loading RIM_D). BUSRQ_n inactive. rst = a board-driven reset pulse: every dispatcher ORs it into the CPU reset
// (RESET_n = ~(reset | rst)); a board without one ties it 1'b0 (VIC: coin insert resets the CPU).
typedef struct packed {
    logic        cen_p;
    logic        cen_n;
    logic        wait_n;
    logic        int_n;
    logic        nmi_n;
    logic        i8080;
    logic        i8085;
    logic  [7:0] rim_d;
    logic  [7:0] di;
    logic        rst;
} z80pa85_i_t;

typedef struct packed {
    logic [15:0] a;
    logic  [7:0] dout;
    logic        m1_n;
    logic        mreq_n;
    logic        iorq_n;
    logic        rd_n;
    logic        wr_n;
    logic        rfsh_n;
    logic        sod;                   // 8085 SID / SOD: SOD latched by SIM (opcode 30)
} z80pa85_o_t;

// 8080 (t80sv_T8080se: 8080 bus with SYNC / DBIN / WR_n / INTE). reset_n is on the bus: the Space Invaders 8080 board's
// watchdog resets its CPU. hold drives T8080se HOLD (passed to the core as BUSRQ_n): the 8080 boards tie it 0.
typedef struct packed {
    logic        reset_n;
    logic        clken;
    logic        ready;
    logic        hold;
    logic        intr;                  // INT
    logic  [7:0] di;
} t8080se_i_t;

typedef struct packed {
    logic [15:0] a;
    logic  [7:0] dout;
    logic        wr_n;
    logic        sync;
    logic        dbin;
    logic        inte;
    logic        vait;
    logic        hlda;
} t8080se_o_t;

// TMS36XX family (rtl/sound/tms36xx.sv: MM6221AA tunes, TMS3615 / TMS3617 notes); parameters per instance
typedef struct packed {
    logic        tune_we;
    logic  [1:0] tune;
    logic        note_we;
    logic  [1:0] note_octave;
    logic  [3:0] note;
    logic        enable_we;
    logic  [5:0] voice_enable;
    logic        cfg_b;                 // the instance's second parameter set (static between resets)
} tms36xx_i_t;

typedef struct packed {
    logic [15:0] audio;                 // signed
    logic        ce_snd;
} tms36xx_o_t;

// Discrete sound engine (rtl/sound/dsnd_engine.sv); the program download (MRA index 5) is wired in the dispatcher.
// A mono board reads out only.
typedef struct packed {
    logic [63:0] src;                   // sources 7..0, one byte each
} dsnd_i_t;

typedef struct packed {
    logic [15:0] out;                   // signed
    logic [15:0] out_r;                 // signed
    logic        sample;                // one clk at the start of each sample period
} dsnd_o_t;

// VLM5030 (jotego jtcores modules/vlm5030: vlm5030_gl, Arnim Laeuger's gate-level VHDL; i_tst1 0, i_vref / i_tst3
// default). rst is the chip's RST pin (Punch-Out main latch Q4), not the core reset. oscen = 3.579545 MHz enable
// (the model needs clk >= 2x OSC).
typedef struct packed {
    logic        rst;
    logic        oscen;
    logic        start;
    logic        vcu;
    logic  [7:0] d;
} vlm5030_i_t;

typedef struct packed {
    logic [15:0] a;
    logic        me_l;
    logic        mte;
    logic        bsy;
    logic  [5:0] dao;                   // unsigned DAC + PWM (the pin)
    logic  [9:0] audio;                 // signed PCM (~8136 Hz)
} vlm5030_o_t;

// Namco 15XX WSG (8 voices). The registers live in the first 64 bytes of the CPU-shared sound RAM; the chip
// snoops CPU writes there. dac_mode picks the board's volume DAC
// (0 = Super Pac-Man LS273 + 4066 resistor ladder, 1 = Mappy / Gaplus 99XX).
typedef struct packed {
    logic        sound_en;      // LS259 SOUND ON
    logic  [1:0] dac_mode;
    logic        reg_wr;        // one clock per CPU write to shared RAM offset 0x00-0x3F
    logic  [5:0] reg_addr;
    logic  [7:0] reg_din;
    logic  [3:0] wave_d;        // waveform PROM nibble at wave_a
} wsg15_i_t;

typedef struct packed {
    logic  [7:0] wave_a;        // waveform PROM address {waveform, step}
    logic [15:0] sound;         // signed mono
} wsg15_o_t;

// Namco 56XX / 58XX / 59XX custom I/O (MB8843, undumped: behavioural), runtime-configured
// by kind; CPU side is the 16XX nibble buffer (16 nibbles per chip).
typedef struct packed {
    logic  [1:0] kind;          // 0 = 56XX, 1 = 58XX, 2 = 59XX
    logic        reset_n;       // LS259 4 RESET
    logic        run;   // vblank strobe: process the command
    logic        wr;
    logic  [3:0] addr;
    logic  [3:0] din;
    logic [15:0] in;            // {in3, in2, in1, in0} 4-bit input ports
} namcoio_i_t;

typedef struct packed {
    logic  [3:0] dout;
    logic  [7:0] out;           // {out1, out0} 4-bit output ports (lamps, coin lockout, DIP mux select)
} namcoio_o_t;

// Z80 (T80s, Mode 0, T2Write 1, IOWait 1; BUSRQ_n inactive) with WAIT_n driven: Dragon's Lair inserts a wait state for the AY
typedef struct packed {
    logic        ce;
    logic        wait_n;
    logic        int_n;
    logic        nmi_n;
    logic  [7:0] di;
} z80w_i_t;

typedef struct packed {
    logic [15:0] a;
    logic  [7:0] dout;
    logic        m1_n;
    logic        mreq_n;
    logic        iorq_n;
    logic        rd_n;
    logic        wr_n;
    logic        rfsh_n;
} z80w_o_t;

// AY-3-8910 register core (jt49, no bus wrapper; sel = 1). rst_n is on the bus: Dragon's Lair II holds its board in reset during the SDRAM phase sweep
typedef struct packed {
    logic        rst_n;
    logic        ce;
    logic  [3:0] addr;
    logic        cs_n;
    logic        wr_n;
    logic  [7:0] din;
} jt49_i_t;

typedef struct packed {
    logic  [7:0] a;
    logic  [7:0] b;
    logic  [7:0] c;
    logic  [9:0] sound;                 // jt49 A+B+C mix; cores that don't read it leave it undriven
} jt49_o_t;

// Laserdisc player HLE (rtl/ldp/ldp_top.sv: shared transport + LD-V1000 / PR-7820 / PR-8210 / LDP-1450 front-ends)
typedef struct packed {
    logic  [3:0] player_sel;
    logic        pr8210_555;            // PR-8210 bit boundary: 0 = bit-banged (870 us), 1 = Gottlieb 555 (1497 us)
    logic        cmd_stb;
    logic  [7:0] cmd_byte;
    logic        blip;
    logic        tx_pop;
    logic        pause;
    logic        disc_hold;
    logic  [3:0] post_seek_frames;
    logic        disc_2997;
    logic [16:0] park_frame;
    logic        status_rd;
    logic        cmd_oe;                // host drives the LD data bus (DL: misc b5 low = U21 enabled)
} ldp_i_t;

typedef struct packed {
    logic  [7:0] status;
    logic        status_strobe;
    logic        command_strobe;
    logic        ready_n;
    logic        frame_valid;
    logic        tx_valid;
    logic  [7:0] tx_byte;
    logic        search_cmd;
    logic        play_end;
    logic [16:0] curr_frame;
    logic        playing;
    logic [16:0] dbg_seek_frame;
    logic [19:0] dbg_end_frame;
    logic  [3:0] dbg_flags;
    logic        txt_we;
    logic  [1:0] txt_line;
    logic  [5:0] txt_col;
    logic  [7:0] txt_glyph;
    logic        txt_on;
    logic  [7:0] txt_x;
    logic  [7:0] txt_y;
    logic        ldv_fw;                // LD-V1000 is running its real firmware (else HLE)
} ldp_o_t;

// Dual-port RAM block (dpram_dc, 8-bit, port A = CPU side read/write, port B = video side read-only)
typedef struct packed {
    logic [13:0] a_addr;
    logic        a_we;
    logic  [7:0] a_din;
    logic [13:0] b_addr;
} ram_i_t;

typedef struct packed {
    logic  [7:0] a_q;
    logic  [7:0] b_q;
} ram_o_t;

// COP421 (T400 t400_core, opt_type 421, CK divisor 32, crystal CKO; CKO low, IN port high; POR from t400_por)
typedef struct packed {
    logic        ck_en;
    logic  [7:0] pm_data;
    logic  [3:0] dm_data;
    logic  [7:0] io_l;
    logic  [3:0] io_g;
    logic        si;
} t400_i_t;

typedef struct packed {
    logic  [9:0] pm_addr;
    logic  [5:0] dm_addr;
    logic        dm_we;
    logic  [3:0] dm_data;
    logic  [7:0] io_l;
    logic  [7:0] io_l_en;
    logic  [3:0] io_d;
    logic  [3:0] io_d_en;
    logic  [3:0] io_g;
    logic  [3:0] io_g_en;
    logic        so;
    logic        so_en;
    logic        sk;
    logic        sk_en;
} t400_o_t;

// YM2203 (jt03, YM2203_LUMPED 0). rst is on the bus: ninjakd2's sound reset. The SSG is AY-3-8910 register- and
// port-compatible, so the pair can also stand in for two AY8910s
typedef struct packed {
    logic        rst;
    logic        ce;
    logic        cs_n;
    logic        wr_n;
    logic        addr;
    logic  [7:0] din;
    logic  [7:0] ioa_in;
    logic  [7:0] iob_in;
} ym2203_i_t;

typedef struct packed {
    logic  [7:0] dout;
    logic        irq_n;
    logic  [7:0] ioa_out;
    logic  [7:0] iob_out;
    logic        ioa_oe;                // port is an output (SSG register 7 bit 6 / 7)
    logic        iob_oe;
    logic  [9:0] psg_snd;               // SSG only, unsigned
    logic [15:0] snd;                   // FM + SSG, signed
} ym2203_o_t;

// Dual-port RAM block (dpram_dc, true dual port, both ports read/write). One bus shape for every pooled RAM:
// each instance uses the low widthad address bits and its width_a data bits; be is used by the 32-bit ones only
typedef struct packed {
    logic [13:0] a_addr;
    logic        a_we;
    logic  [3:0] a_be;
    logic [31:0] a_din;
    logic [13:0] b_addr;
    logic        b_we;
    logic  [3:0] b_be;
    logic [31:0] b_din;
} dpram_i_t;

typedef struct packed {
    logic [31:0] a_q;
    logic [31:0] b_q;
} dpram_o_t;

// AY-3-8910 (jt49_bus, sel = 1; inputs as ay_i_t) with port A output: MCR SSIO volume counters (added by the MCR core)
typedef struct packed {
    logic  [7:0] dout;
    logic  [7:0] a;
    logic  [7:0] b;
    logic  [7:0] c;
    logic  [7:0] ioa_out;
    logic  [7:0] iob_out;
    logic  [9:0] sound;                 // jt49 internal A+B+C mix (registered per accumulator cycle)
} ayio_o_t;

// Exidy's own chip models (rtl/sound/). rst is on every bus: each board drives its own reset (sound board snd_rst,
// Car Polo reset | ~cp, Star Fire reset | ~sf), so a pooled chip behaves exactly as the board's private copy did.
// MC6821 PIA (pia6821). ce = one-clock bus strobe, cs = address decode. pa_pins: 1 = port A reads the pins for
// output bits too, 0 = port A output bits read back the latch.
typedef struct packed {
    logic        rst;
    logic        ce;
    logic        cs;
    logic        rw;                    // 1 = read
    logic  [1:0] rs;
    logic  [7:0] din;
    logic  [7:0] pa_i;
    logic        pa_pins;
    logic        ca1;
    logic        ca2_i;
    logic  [7:0] pb_i;
    logic        cb1;
    logic        cb2_i;
} pia6821_i_t;

typedef struct packed {
    logic  [7:0] dout;
    logic        irqa;
    logic        irqb;
    logic  [7:0] pa_o;
    logic  [7:0] pa_oe;
    logic        ca2_o;
    logic        ca2_oe;
    logic  [7:0] pb_o;
    logic  [7:0] pb_oe;
    logic        cb2_o;
    logic        cb2_oe;
} pia6821_o_t;

// 8253 PIT (pit8253)
typedef struct packed {
    logic        rst;
    logic        wr_en;
    logic  [1:0] a;
    logic  [7:0] din;
    logic        clk_ce;
    logic  [2:0] gate;
} pit8253_i_t;

typedef struct packed {
    logic  [2:0] out;
} pit8253_o_t;

// 6532 RIOT (riot6532)
typedef struct packed {
    logic        rst;
    logic        ce;
    logic        ram_cs;
    logic        io_cs;
    logic        rw;
    logic  [6:0] a;
    logic  [7:0] din;
    logic  [7:0] pa_i;
    logic  [7:0] pb_i;
} riot6532_i_t;

typedef struct packed {
    logic  [7:0] dout;
    logic        irq;
    logic  [7:0] pa_pins;
    logic  [7:0] pb_pins;
} riot6532_o_t;

// MC6840 PTM (ptm6840)
typedef struct packed {
    logic        rst;
    logic        ce;
    logic        cs;
    logic        rw;
    logic  [2:0] rs;
    logic  [7:0] din;
    logic  [2:0] cx;
} ptm6840_i_t;

typedef struct packed {
    logic  [7:0] dout;
    logic  [2:0] o;
    logic        irq;
} ptm6840_o_t;

// MC3417 CVSD decoder (mc3417)
typedef struct packed {
    logic        rst;
    logic        bclk;
    logic        din;
} mc3417_i_t;

typedef struct packed {
    logic [23:0] integ;                 // signed Q16
} mc3417_o_t;

// TMS5220 with the /RS /WS bus interface (tms5220_rsws; CLK_HZ / TMS_HZ stay instance parameters)
typedef struct packed {
    logic        reset;
    logic        pause;
    logic        rs_n;
    logic        ws_n;
    logic  [7:0] d_in;
} tms5220rsws_i_t;

typedef struct packed {
    logic  [7:0] d_out;
    logic        ready_n;
    logic        int_n;
    logic [15:0] audio;                 // signed
} tms5220rsws_o_t;

// MC6845 CRTC (rtl/rodimus/crtc6845sv crtc6845sv_pool, VARIANT 0; CURSOR unused, LPSTB low). reset_n is on the bus:
// each board holds the chip in reset while it is not the active one (Castle: reset | ~dcastle, TMS: reset | ~tms).
// Castle writes only (r_nw 0, do unused); the TMS board reads registers back through do.
typedef struct packed {
    logic        reset_n;
    logic        clken;
    logic        enable;
    logic        r_nw;
    logic        rs;
    logic  [7:0] di;
} mc6845_i_t;

typedef struct packed {
    logic  [7:0] dout;
    logic        vsync;
    logic        hsync;
    logic        vblank;
    logic        hblank;
    logic        de;
    logic [13:0] ma;
    logic  [4:0] ra;
} mc6845_o_t;

// TMS9900 / TMS9980A (Piehl's tms9900.vhd, edited: no scratchpad, in-file multiplier, byte_bus, ir_step2;
// generic cycle_clks_g stays at its default 8; waits 0, scratch_en 0, turbo 0 and the debug outputs are constants /
// unused). reset is the CPU pin (high), on the bus: the TMS board holds it with reset | ~tms.
typedef struct packed {
    logic        reset;
    logic [15:0] data_in;
    logic        ready;
    logic        int_req;
    logic  [3:0] ic03;
    logic        cruin;
    logic        hold;
    logic        byte_bus;
    logic        ir_step2;
} tms9900_i_t;

typedef struct packed {
    logic [15:0] addr_out;
    logic [15:0] data_out;
    logic        rd;
    logic        wr;
    logic        iaq;
    logic        as;
    logic        int_ack;
    logic        cruout;
    logic        cruclk;
    logic        holda;
} tms9900_o_t;

// HC-55516 CVSD decoder (hc55516): clock and digit are pin levels; rst is on the bus (the board holds it while it has no speech)
typedef struct packed {
    logic        rst;
    logic        cvsd_clk;
    logic        digit;
} hc55516_i_t;

typedef struct packed {
    logic [15:0] out;                   // signed
} hc55516_o_t;

// YM2151 (jotego jt51; cen = 3.58 MHz enable, cen_p1 = half rate; ct1 / ct2 / sample / xleft / xright unused). rst is on the bus:
// the board resets it from a PIA line as well as the board reset
typedef struct packed {
    logic        rst;
    logic        cen;
    logic        cen_p1;
    logic        cs_n;
    logic        wr_n;
    logic        a0;
    logic  [7:0] din;
} jt51_i_t;

typedef struct packed {
    logic  [7:0] dout;
    logic        irq_n;
    logic [15:0] left;                  // signed
    logic [15:0] right;                 // signed
} jt51_o_t;

// POKEY (pokey_glue around pokey_cx; enable_179 1, keyboard scan / SIO inactive). POT_CMP stays an instance parameter,
// so a slot serves only boards with the same value. reset_n is on the bus: each board resets it with its CPU
typedef struct packed {
    logic        reset_n;
    logic        ce;
    logic        wr_en;
    logic  [3:0] addr;
    logic  [7:0] din;
    logic  [7:0] pot_in;
} pokey_i_t;

typedef struct packed {
    logic  [7:0] dout;
    logic  [3:0] ch0;                   // channel volumes while the channel output is high
    logic  [3:0] ch1;
    logic  [3:0] ch2;
    logic  [3:0] ch3;
    logic  [7:0] pot_count;
} pokey_o_t;

// AY-3-8910 (jt49_bus, sel = 1; inputs as ay_i_t) with rst_n on the bus: a board resets it with its CPU. Outputs: ay_o_t
typedef struct packed {
    logic        rst_n;
    logic        ce;
    logic        bdir;
    logic        bc1;
    logic  [7:0] din;
    logic  [7:0] ioa_in;
    logic  [7:0] iob_in;
} ayr_i_t;

// 93C46 serial EEPROM, 128 x 8 (eeprom_93c46). ext_* = the NVRAM save / load port (CPU held or paused)
typedef struct packed {
    logic        reset;
    logic        clear;
    logic        wr;
    logic        di;
    logic        sk;
    logic        cs;
    logic        ext_sel;
    logic  [6:0] ext_addr;
    logic  [7:0] ext_din;
    logic        ext_we;
} eeprom93c46_i_t;

typedef struct packed {
    logic        dout;
    logic  [7:0] ext_q;
} eeprom93c46_o_t;

// ALPHA-8201 / 8302 protection MCU (alpha8201: HMCS40 core + 1K shared RAM). ext_* = the main CPU's side of the shared
// RAM, mcu_addr / mcu_data = its program ROM
typedef struct packed {
    logic        reset;
    logic        pause;
    logic        mcu_start;
    logic        bus_dir;
    logic  [9:0] ext_addr;
    logic  [7:0] ext_din;
    logic        ext_we;
    logic  [7:0] mcu_data;
} alpha8201_i_t;

typedef struct packed {
    logic  [7:0] ext_dout;
    logic [12:0] mcu_addr;
} alpha8201_o_t;

// TMS5110 speech synthesizer (tms5110). ctl / pdc / data_bit come from the board's VSM / PROM controller; m0 / busy go
// back to it. ce_sample = one 8 kHz output step
typedef struct packed {
    logic        reset;
    logic        ce_sample;
    logic  [3:0] ctl;
    logic        pdc;
    logic        data_bit;
} tms5110_i_t;

typedef struct packed {
    logic        m0;
    logic        busy;
    logic        talk_status;
    logic signed [15:0] sample;
} tms5110_o_t;

// Namco 06XX bus controller (namco_06xx; BASE_DIV per instance): the CPU's 7000 / 7100 data / control port and the
// four custom-chip slots (select pulse, R/W to chip 0, write strobes)
typedef struct packed {
    logic        reset;
    logic        irq_on_access;
    logic  [7:0] cpu_dout;
    logic        data_wr;
    logic        data_rd;
    logic        ctrl_wr;
    logic        ctrl_rd;
    logic  [7:0] chip0_din;
    logic  [7:0] chip1_din;
    logic  [7:0] chip2_din;
    logic  [7:0] chip3_din;
} namco_06xx_i_t;

typedef struct packed {
    logic  [7:0] cpu_din;
    logic        nmi_n;
    logic  [3:0] chipsel;
    logic        rw0;
    logic  [7:0] chip_dout;
    logic  [3:0] chip_wr;
} namco_06xx_o_t;

// Namco 50XX / 51XX / 52XX / 53XX / 54XX customs (namco_5Nxx: an MB88 on the mb88_* pool + its mask ROM, loaded in
// the dispatcher). ena = the MCU clock enable; the 06XX side is chip_sel / rw_in / wr_en / wr_data
typedef struct packed {
    logic        ena;
    logic        reset_n;
    logic        chip_sel;
    logic        rw_in;
    logic        wr_en;
    logic  [7:0] wr_data;
} namco_50xx_i_t;

typedef struct packed {
    logic  [7:0] data_out;
} namco_50xx_o_t;

typedef struct packed {
    logic        ena;
    logic        reset_n;
    logic        chip_sel;
    logic        rw_in;
    logic        wr_en;
    logic  [7:0] wr_data;
    logic  [7:0] in_a;          // input<0> = in_a[3:0], input<1> = in_a[7:4]
    logic  [7:0] in_b;          // input<2> = in_b[3:0], input<3> = in_b[7:4]
    logic        vblank;
} namco_51xx_i_t;

typedef struct packed {
    logic  [7:0] data_out;
    logic  [3:0] p_port_out;
} namco_51xx_o_t;

typedef struct packed {
    logic        ena;
    logic        reset_n;
    logic        chip_sel;
    logic        wr_en;
    logic  [7:0] wr_data;
    logic        si;
    logic        tc_n;
    logic  [7:0] sample_data;   // sample ROM data at sample_addr
} namco_52xx_i_t;

typedef struct packed {
    logic  [3:0] p_out;
    logic [15:0] sample_addr;
} namco_52xx_o_t;

typedef struct packed {
    logic        ena;
    logic        reset_n;
    logic        chip_sel;
    logic  [3:0] k_in;
    logic  [7:0] in_a;
    logic  [7:0] in_b;
} namco_53xx_i_t;

typedef struct packed {
    logic  [7:0] data_out;
} namco_53xx_o_t;

typedef struct packed {
    logic        ena;
    logic        reset_n;
    logic        chip_sel;
    logic        wr_en;
    logic  [7:0] wr_data;
} namco_54xx_i_t;

typedef struct packed {
    logic  [3:0] discrete_o0;
    logic  [3:0] discrete_o1;
    logic  [3:0] discrete_r1;
} namco_54xx_o_t;

// Namco 3-voice WSG (namco_wsg3; waveform PROM loaded in the dispatcher)
typedef struct packed {
    logic        reset;
    logic  [4:0] reg_addr;
    logic  [3:0] reg_data;
    logic        reg_wr;
} namco_wsg3_i_t;

typedef struct packed {
    logic [15:0] audio;         // signed
} namco_wsg3_o_t;

// Namco 52XX voice filter chain (namco_52xx_snd) and 54XX noise / discrete mixer (namco_54xx_snd; BOARD per instance)
typedef struct packed {
    logic        reset;
    logic  [3:0] p_data;
} namco_52xx_snd_i_t;

typedef struct packed {
    logic [31:0] volts;         // signed, 2^22 per volt
} namco_52xx_snd_o_t;

typedef struct packed {
    logic        reset;
    logic  [3:0] o0_data;
    logic  [3:0] o1_data;
    logic  [3:0] r1_data;
    logic        bosco;
    logic [31:0] ext_volts;     // signed
} namco_54xx_snd_i_t;

typedef struct packed {
    logic [15:0] audio;         // signed
} namco_54xx_snd_o_t;

// Namco 05XX starfield (namco_05xx)
typedef struct packed {
    logic        ce6;
    logic        line_step;
    logic  [8:0] vcnt;
    logic        win;
    logic  [2:0] speed_x;
    logic  [2:0] speed_y;
    logic  [1:0] set_a;
    logic  [1:0] set_b;
    logic        enable;
} namco_05xx_i_t;

typedef struct packed {
    logic        star;
    logic  [5:0] color;         // BBGGRR
} namco_05xx_o_t;

// Namco 62XX (namco_62xx: an MB88 in a 28-pin package on the mb88_* pool; its mask ROM is read through the module's
// rom_a / rom_d ports). R0-R10 are bonded and read latch AND r_ext; R10 doubles as _IRQ
typedef struct packed {
    logic        ena;           // X clock enable
    logic        reset_n;
    logic  [3:0] k;
    logic [10:0] r_ext;         // external drive on R0-R10, 1 = released
} namco_62xx_i_t;

typedef struct packed {
    logic [10:0] r_out;         // R0-R10 output latch
    logic  [7:0] o;             // {O7-O4, O3-O0}
    logic        o_wr;
} namco_62xx_o_t;

// Intel 8257 DMA controller (rtl/cpu/i8257.sv, ours). Field names = the module's ports.
typedef struct packed {
    logic        reset;
    logic        ce;
    logic        rev_rw;
    logic        cs;
    logic  [3:0] a;
    logic        wr;
    logic        rd;
    logic  [7:0] din;
    logic  [3:0] drq;
    logic        hlda;
    logic  [7:0] mem_d;
    logic  [7:0] io_d;
} i8257_i_t;

typedef struct packed {
    logic  [7:0] dout;
    logic        hrq;
    logic [15:0] addr;
    logic  [1:0] chan;
    logic        busy;
    logic        ior;
    logic        iow;
    logic        memr;
    logic        memw;
    logic  [7:0] data;
} i8257_o_t;

// Zilog Z80 DMA (rtl/cpu/z80dma.sv, ours). Field names = the module's ports.
typedef struct packed {
    logic        reset;
    logic        cen_p;
    logic        cs;
    logic        wr;
    logic        rd;
    logic  [7:0] din;
    logic        rdy;
    logic        bai;
    logic  [7:0] bus_d;
} z80dma_i_t;

typedef struct packed {
    logic  [7:0] dout;
    logic        busrq;
    logic        busy;
    logic [15:0] addr;
    logic        mreq;
    logic        iorq;
    logic        memr;
    logic        memw_s;
    logic  [7:0] data;
} z80dma_o_t;

// TI SN76477 complex sound generator (rtl/sound/sn76477.sv, ours). Field names = the module's ports; the analog
// part values arrive as per-sample steps (Q24 volts), so one instance serves any board's parts.
typedef struct packed {
    logic        reset;
    logic        step;
    logic        enable;
    logic        vco_sel;
    logic  [2:0] mixer;
    logic  [1:0] env;
    logic [31:0] vco_v;
    logic [31:0] os_c;
    logic [31:0] os_d;
    logic [31:0] slf_c;
    logic [31:0] slf_d;
    logic [31:0] vco_c;
    logic [31:0] vco_d;
    logic [31:0] nf_c;
    logic [31:0] nf_d;
    logic [31:0] ad_c;
    logic [31:0] ad_d;
    logic [31:0] noise_f;
    logic [31:0] fs;
} sn76477_i_t;

typedef struct packed {
    logic [31:0] vout;
} sn76477_o_t;

// HD38880 speech synthesizer (rtl/sound/hd38880/hd38880_top.v, ours; CLK_HZ = the board clock, core reset / pause).
// game_is_fantasy picks the host command protocol (Vanguard / Fantasy); the PARCOR data ROM is read through
// rom_addr / rom_data (one clock).
typedef struct packed {
    logic        host_wr;
    logic  [5:0] host_din;
    logic        game_is_fantasy;
    logic  [7:0] rom_data;
} hd38880_i_t;

typedef struct packed {
    logic [12:0] rom_addr;
    logic [14:0] audio;                 // signed
} hd38880_o_t;

// SN76477 noise leg (rtl/sound/sn76477_noise.v, ours: noise clock + optional RC filter, no VCO / SLF / envelope).
// The part values are per-slot parameters on the instance; gate = ENABLE (level).
typedef struct packed {
    logic        gate;
} sn76477_noise_i_t;

typedef struct packed {
    logic [15:0] audio;                 // signed
} sn76477_noise_o_t;

// SP0250 LPC speech (rtl/sound/sp0250/sp0250.sv). ce_3_12m / ce_rom_1_56m = the board's
// 3.12 MHz and 1.56 MHz enables; reset_n on the bus (the speech board's reset).
typedef struct packed {
    logic        reset_n;
    logic        ce_3_12m;
    logic        ce_rom_1_56m;
    logic  [7:0] data_in;
    logic        wr;
} sp0250_i_t;

typedef struct packed {
    logic        drq;
    logic [13:0] audio;                 // signed
    logic        audio_valid;
} sp0250_o_t;

// 8035 through the i8035.v wrapper (bare t48_core, 64-byte RAM; program via the external bus, I_EA = 1).
// rst_n on the bus: the Sega Universal Sound Board holds it in reset while the host loads its program RAM.
typedef struct packed {
    logic        rst_n;
    logic        ce;
    logic        int_n;
    logic        ea;
    logic        t0;
    logic        t1;
    logic  [7:0] db;
    logic  [7:0] p1;
    logic  [7:0] p2;
} i8035_i_t;

typedef struct packed {
    logic        psen_n;
    logic        rd_n;
    logic        wr_n;
    logic        ale;
    logic        prog_n;
    logic        t0;
    logic  [7:0] db;
    logic  [7:0] p1;
    logic  [7:0] p2;
} i8035_o_t;

// 8088 as one CPU on a request / acknowledge bus (x86sv, rtl/rodimus/x86sv x86sv_mcl86; the type keeps its mcl86 name)
typedef struct packed {
    logic        reset;
    logic        cpu_clk;               // 8088 pin clock
    logic        nmi;
    logic        intr;
    logic  [7:0] req_rdata;
    logic        req_ack;               // 1 clk: rdata valid / write taken
} mcl86_i_t;
typedef struct packed {
    logic        req;
    logic  [2:0] req_type;              // S2-S0 of the cycle
    logic [19:0] req_addr;
    logic  [7:0] req_wdata;
} mcl86_o_t;

// Intel 8088 (x86sv, rtl/x86sv_fleet.sv x86sv_i8088): max-mode bus, one CPU clock per ce, 8288 command strobes
typedef struct packed {
    logic        reset;                 // >= 4 ce
    logic        ce;                    // one 8088 clock
    logic        ready;                 // READY: low in T3 / Tw inserts a wait state
    logic        intr;
    logic        nmi;                   // rising edge
    logic        test_n;                // WAIT input
    logic  [7:0] din;                   // read data / INTA type, taken in the T3 / Tw with ready high
} i8088_i_t;
typedef struct packed {
    logic [19:0] addr;                  // address of the current bus cycle (ALE latch), valid T1-T4
    logic  [2:0] cyc;                   // S2-S0 of the current bus cycle, valid T1-T4
    logic        ale;
    logic  [2:0] s;                     // S2-S0 pins (8288 timing; 111 passive)
    logic  [1:0] seg;                   // S4-S3
    logic  [7:0] dout;                  // write data, valid T2-T4
    logic        mrdc_n;                // 8288 commands, active low, T2-T3-Tw
    logic        amwc_n;
    logic        mwtc_n;
    logic        iorc_n;
    logic        aiowc_n;
    logic        iowc_n;
    logic        inta_n;
    logic  [1:0] qs;                    // QS1-QS0
    logic        lock_n;
    logic [19:0] ad;                    // AD19-AD0 as driven this clock (trace / debug)
} i8088_o_t;


// Intel 8086 (x86sv, rtl/x86sv_fleet.sv x86sv_i8086): max-mode 16-bit bus, one CPU clock per ce, 8288 commands.
// Byte lanes: AD7-0 active when addr[0] = 0, AD15-8 active when bhe_n = 0; a word at an odd address is two cycles.
typedef struct packed {
    logic        reset;                 // >= 4 ce
    logic        ce;                    // one 8086 clock
    logic        ready;                 // READY: low in T3 / Tw inserts a wait state
    logic        intr;
    logic        nmi;                   // rising edge
    logic        test_n;                // WAIT input
    logic [15:0] din;                   // read data (both lanes; INTA type on AD7-0), taken in the T3 / Tw with ready high
} i8086_i_t;
typedef struct packed {
    logic [19:0] addr;                  // address of the current bus cycle (ALE latch), valid T1-T4
    logic  [2:0] cyc;                   // S2-S0 of the current bus cycle, valid T1-T4
    logic        bhe_n;                 // BHE of the current bus cycle (ALE latch), valid T1-T4
    logic        ale;
    logic  [2:0] s;                     // S2-S0 pins (8288 timing; 111 passive)
    logic  [1:0] seg;                   // S4-S3
    logic [15:0] dout;                  // write data on its lane(s), valid T2-T4
    logic        mrdc_n;                // 8288 commands, active low, T2-T3-Tw
    logic        amwc_n;
    logic        mwtc_n;
    logic        iorc_n;
    logic        aiowc_n;
    logic        iowc_n;
    logic        inta_n;
    logic  [1:0] qs;                    // QS1-QS0
    logic        lock_n;
    logic [19:0] ad;                    // AD19-AD0 as driven this clock (trace / debug)
} i8086_o_t;

// NEC V20 (uPD70108) native mode: same max-mode pins as the 8088 (x86sv_v20)
typedef i8088_i_t v20_i_t;
typedef i8088_o_t v20_o_t;

// NEC V30 (uPD70116) native mode: same max-mode pins as the 8086 (x86sv_v30)
typedef i8086_i_t v30_i_t;
typedef i8086_o_t v30_o_t;

// Votrax SC-01 / SC-01A (rtl/sound/sc01, ours); the internal ROM is a dispatcher ROM block
typedef struct packed {
    logic        reset;
    logic        mc;                    // master-clock enable
    logic        stb;
    logic  [5:0] phoneme;
    logic  [1:0] inflection;
} sc01_i_t;
typedef struct packed {
    logic        ar;                    // 1 = ready
    logic [15:0] audio;                 // signed
    logic        sample;
} sc01_o_t;

// Z80 CTC (rtl/rodimus/z80ctc, every port). reset_n is on the bus: MCR's CPU board watchdog resets it with the Z80.
// wr_stb = 1-clk register write (wsel / wdata); rsel reads dout combinationally; inta / reti = 1-clk strobes
typedef struct packed {
    logic        reset_n;
    logic        ce;
    logic        wr_stb;
    logic  [1:0] wsel;
    logic  [7:0] wdata;
    logic  [1:0] rsel;
    logic  [3:0] trg;                   // trigger / clock inputs (level)
    logic        trg_en;
    logic        inta;
    logic        reti;
} z80ctc_i_t;
typedef struct packed {
    logic  [7:0] dout;
    logic        int_n;
    logic  [7:0] ack_vector;
    logic  [3:0] zc_to;                 // ZC/TO pulse per channel
} z80ctc_o_t;

// Intel 8255 PPI (rtl/rodimus/i8255, every pin; TRI_PA / TRI_PB / TRI_PC set in the dispatcher). reset is on the bus.
// wr = one clock per write; rd = read cycle (level)
typedef struct packed {
    logic        reset;
    logic        cs;
    logic        rd;
    logic        wr;
    logic  [1:0] a;
    logic  [7:0] din;
    logic  [7:0] pa_in;
    logic  [7:0] pb_in;
    logic  [7:0] pc_in;
    logic        stb_a_n;
    logic        ack_a_n;
    logic        pc2_n;
} i8255_i_t;
typedef struct packed {
    logic  [7:0] dout;
    logic  [7:0] pa_out;
    logic  [7:0] pb_out;
    logic  [7:0] pc_out;
} i8255_o_t;

// MM54104 Digitalker (rtl/rodimus/digitalker). reset is on the bus; the 1 MHz stream tick (ce) and the speech ROM
// (rom_a / rom_d, a dispatcher ROM block) connect in the dispatcher. cs / cms / wr as the pins (cs = 1 deselected)
typedef struct packed {
    logic        reset;
    logic  [7:0] data;
    logic        cs;
    logic        cms;
    logic        wr;
} digitalker_i_t;
typedef struct packed {
    logic        intr;                  // 1 = idle
    logic [15:0] sample;                // signed
} digitalker_o_t;

// MC68705P3 MCU (rtl/rodimus/mc68705p3, ours; every port). reset is on the bus. ce_4m = the 4 MHz oscillator pulse.
// rom_wr / rom_addr / rom_data load the internal 2K EPROM (the core's MCU download)
typedef struct packed {
    logic        reset;
    logic        ce_4m;
    logic        irq_n;
    logic  [7:0] pa_in;
    logic  [7:0] pb_in;
    logic  [3:0] pc_in;
    logic        rom_wr;
    logic [10:0] rom_addr;
    logic  [7:0] rom_data;
} mc68705p3_i_t;
typedef struct packed {
    logic  [7:0] pa_out;
    logic  [7:0] pa_latch_out;          // raw PA latch
    logic        pa_wr_stb;             // 1 clk when the MCU writes PA
    logic  [7:0] pb_out;
    logic  [7:0] pb_ddr;
    logic  [3:0] pc_out;
    logic  [3:0] pc_ddr;
} mc68705p3_o_t;

endpackage
