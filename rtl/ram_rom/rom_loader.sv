//============================================================================
//
//  Galaga / Bosconian / Xevious / Dig Dug ROM loader
//  ROM layout matched to MAME galaga.cpp regions
//
//============================================================================

// ioctl index 0 (MRA), all images stored exactly as dumped:
//   0x00000 - 0x07FFF  "maincpu"   (program at 0x0000-0x3FFF)
//   0x08000 - 0x0BFFF  "sub"
//   0x0C000 - 0x0FFFF  "sub2"
//   0x10000 - 0x11FFF  "gfx1"      characters
//   0x12000 - 0x12FFF  "sub3"      bootleg I/O CPU
//   0x14000 - 0x17FFF  "gfx2"      sprites
//   0x18000 - 0x21FFF  "gfx3"      Bosconian radar dots / Xevious sprites / Dig Dug playfield chars
//   0x22000 - 0x22FFF  "proms"
//   0x23000 - 0x231FF  "namco"     waveform PROM (0x100 timing PROM unused)
//   0x24000 - 0x27FFF  "gfx4"      Xevious background map / Dig Dug playfield map
//   0x28000 - 0x2AFFF  "52xx"      Bosconian speech samples
//   0x2C000 - 0x2D7FF  MCU mask ROMs: 50xx 0x000 (2K), 51xx 0x800, 52xx 0xC00, 53xx 0x1000, 54xx 0x1400
//
// ioctl index 1: game, flags and input map (see the top level)
// ioctl indexes 3 and 4 are reserved for hiscore config and NVRAM

module selector
(
    input  logic [24:0] ioctl_addr,
    output logic        main_cs,
    output logic        sub_cs,
    output logic        sub2_cs,
    output logic        gfx1_cs,
    output logic        sub3_cs,
    output logic        gfx2_cs,
    output logic        gfx3_cs,
    output logic        prom_cs,
    output logic        wave_cs,
    output logic        gfx4_cs,
    output logic        speech_cs,
    output logic        mcu50_cs,
    output logic        mcu51_cs,
    output logic        mcu52_cs,
    output logic        mcu53_cs,
    output logic        mcu54_cs
);
    always_comb begin
        {main_cs, sub_cs, sub2_cs, gfx1_cs, sub3_cs, gfx2_cs, gfx3_cs, prom_cs, wave_cs, gfx4_cs, speech_cs,
         mcu50_cs, mcu51_cs, mcu52_cs, mcu53_cs, mcu54_cs} = '0;

        if      (ioctl_addr < 25'h08000) main_cs   = 1'b1;
        else if (ioctl_addr < 25'h0C000) sub_cs    = 1'b1;
        else if (ioctl_addr < 25'h10000) sub2_cs   = 1'b1;
        else if (ioctl_addr < 25'h12000) gfx1_cs   = 1'b1;
        else if (ioctl_addr < 25'h13000) sub3_cs   = 1'b1;
        else if (ioctl_addr < 25'h14000) ;
        else if (ioctl_addr < 25'h18000) gfx2_cs   = 1'b1;
        else if (ioctl_addr < 25'h22000) gfx3_cs   = 1'b1;
        else if (ioctl_addr < 25'h23000) prom_cs   = 1'b1;
        else if (ioctl_addr < 25'h23100) wave_cs   = 1'b1;
        else if (ioctl_addr < 25'h24000) ;
        else if (ioctl_addr < 25'h28000) gfx4_cs   = 1'b1;
        else if (ioctl_addr < 25'h2B000) speech_cs = 1'b1;
        else if (ioctl_addr < 25'h2C000) ;
        else if (ioctl_addr < 25'h2C800) mcu50_cs  = 1'b1;
        else if (ioctl_addr < 25'h2CC00) mcu51_cs  = 1'b1;
        else if (ioctl_addr < 25'h2D000) mcu52_cs  = 1'b1;
        else if (ioctl_addr < 25'h2D400) mcu53_cs  = 1'b1;
        else if (ioctl_addr < 25'h2D800) mcu54_cs  = 1'b1;
    end
endmodule
