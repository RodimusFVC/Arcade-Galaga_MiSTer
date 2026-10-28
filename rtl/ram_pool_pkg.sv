//============================================================================
//
//  ram_pool_pkg - bus types for a multi-board core's shared board RAM pool
//  Copyright (C) 2026 Rodimus
//
//  Master copy: RodimusCoresMaster_MiSTer/rtl/ram_pool_pkg.sv; sync.sh copies it into each core unchanged.
//  Only one board runs at a time, so the boards' RAMs live in a few true dual-port blocks in the core's
//  dispatcher, each sized to its largest user. A board drives the blocks through pram_i_t (both ports read / write,
//  as dpram_dc) and reads pram_o_t; the dispatcher picks the owner by variant. Same timing as a private dpram_dc:
//  registered address, one clock to q. A block narrower than 32K uses the low address bits.
//
//============================================================================

package ram_pool_pkg;

typedef struct packed {
    logic [14:0] a_addr;
    logic  [7:0] a_d;
    logic        a_we;
    logic [14:0] b_addr;
    logic  [7:0] b_d;
    logic        b_we;
} pram_i_t;

typedef struct packed {
    logic  [7:0] a_q;
    logic  [7:0] b_q;
} pram_o_t;

endpackage
