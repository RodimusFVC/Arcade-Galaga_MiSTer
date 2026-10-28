//============================================================================
//  board_template.sv - start a new Galaga-core board by copying this file (NOT in files.qip, never compiled).
//  Copyright (C) 2026 Rodimus
//
//  Boards never instantiate a CPU, MCU, Namco custom, sound chip, ROM store or board RAM. They live ONCE in the
//  dispatcher rtl/galaga_dispatcher.sv: Z80s z80_0-2 (z80r_*), MB88s mb88_0-4 behind the namco_5Nxx customs n50_0/1,
//  n51_0, n52_0, n53_0, n54_0, 06xx n06_0/1, 05xx n05_0, WSG wsg_0, 52xx / 54xx sound n52snd_0 / n54snd_0
//  (chip_pool_pkg buses), the shared ROM blocks (program x3, gfx1, gfx2 + 2b, gfx3 + 3b, gfx4, proms 0/1, Xevious
//  PROMs, speech; loaded by ioctl index 0 address through rtl/ram_rom/rom_loader.sv) and the board RAM pool pr 0-9
//  (4K, 2K x 7, 1K x 2; ram_pool_pkg). The Galaga-family CPU board rtl/boards/galaga/galaga_cpu.sv carries the video
//  boards and drives every pool port.
//  To add a board: copy this file to rtl/boards/<board>/<board>.sv, add it to files.qip + verilator/Makefile, instance
//  it from galaga_cpu.sv (or the dispatcher), put its requests on the shared blocks there (muxed by variant) and tie
//  what it doesn't use to '0. A RAM bigger than its block = grow the block, never a private dpram_dc. ROM images: load
//  decode by ioctl index and address only, NEVER by variant. A RAM / chip that truly can't pool =
//  "// POOL-EXCEPTION: <reason>" on its instance line + a Pool contract row (Claude/ vault note).
//  verilator/common/pool_check.sh (POOL_MODS) enforces it.
//============================================================================

module board_template
(
    input  logic        clk,            // 49.152 MHz
    input  logic        reset,          // core reset | this board inactive
    input  logic        pause,

    output chip_pool_pkg::z80r_i_t [2:0] z80_i,
    input  chip_pool_pkg::z80r_o_t [2:0] z80_o,
    output chip_pool_pkg::namco_wsg3_i_t wsg_0_i,
    input  chip_pool_pkg::namco_wsg3_o_t wsg_0_o,

    output logic [13:0] main_rom_a,     // shared ROM block read port
    input  logic  [7:0] main_rom_d,

    output ram_pool_pkg::pram_i_t  [9:0] pr_i,
    input  ram_pool_pkg::pram_o_t  [9:0] pr_o,

    output logic signed [15:0] audio
);

assign z80_i      = '0;
assign wsg_0_i    = '0;
assign main_rom_a = 14'd0;
assign pr_i       = '0;
assign audio      = 16'sd0;

endmodule
