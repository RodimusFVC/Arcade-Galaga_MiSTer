//============================================================================
//
//  Namco Galaga / Bosconian / Xevious / Dig Dug hardware for MiSTer
//  Copyright (C) 2026 Rodimus
//
//  Built from MAME's galaga.cpp driver (Nicola Salmoria), with reference to
//  Dar's (darfpga) Galaga core and the MiSTer arcade framework by Sorgelig
//
//  Permission is hereby granted, free of charge, to any person obtaining a
//  copy of this software and associated documentation files (the "Software"),
//  to deal in the Software without restriction, including without limitation
//  the rights to use, copy, modify, merge, publish, distribute, sublicense,
//  and/or sell copies of the Software, and to permit persons to whom the
//  Software is furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
//  FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
//  DEALINGS IN THE SOFTWARE.
//
//============================================================================

module emu
(
    `include "sys/emu_ports.vh"
);

wire        CLK_49M;
wire        locked;
wire [127:0] status;
wire  [1:0] buttons;
wire        forced_scandoubler;
wire [10:0] ps2_key;
wire        ioctl_download;
wire        ioctl_upload;
wire        ioctl_upload_req;
wire  [7:0] ioctl_din;
wire        ioctl_wr;
wire  [7:0] ioctl_index;
wire [26:0] ioctl_addr27;                     // hps_io's full address: the artwork download can pass 32 MB
wire [24:0] ioctl_addr = ioctl_addr27[24:0];  // every other ioctl user
wire  [7:0] ioctl_dout;
wire [15:0] joystick_0, joystick_1;
wire [21:0] gamma_bus;
wire        direct_video;
wire        video_rotated;
wire        pause_cpu;
wire        hblank, vblank;

assign ADC_BUS  = 'Z;
assign USER_OUT = '1;
assign {UART_RTS, UART_TXD, UART_DTR} = 0;
assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;
assign {SDRAM_DQ, SDRAM_A, SDRAM_BA, SDRAM_CLK, SDRAM_CKE, SDRAM_DQML, SDRAM_DQMH, SDRAM_nWE, SDRAM_nCAS, SDRAM_nRAS, SDRAM_nCS} = 'Z;

assign VGA_F1 = 0;
assign VGA_SCALER = 0;
assign VGA_DISABLE = 0;
assign FB_FORCE_BLANK = 0;
assign HDMI_FREEZE = 0;
assign HDMI_BLACKOUT = 0;
assign HDMI_BOB_DEINT = 0;

wire signed [15:0] audio;
assign AUDIO_L = pause_cpu ? 16'd0 : audio;
assign AUDIO_R = pause_cpu ? 16'd0 : audio;
assign AUDIO_S = 1;   // signed
assign AUDIO_MIX = 0;

assign LED_DISK  = 0;
assign LED_POWER = 0;
assign LED_USER  = ioctl_download;
assign BUTTONS = 0;

///////////////////////////////////////////////////

// MRA index 1:
//   byte 0      board variant (see rtl/galaga_board.sv)
//   byte 1      flags: [0] 4-way joystick, [2] coins are 2-frame pulses, [4] vertical, [7] vertical is ROT90
//   bytes 16-47 input map, one byte per port bit (IN0, IN1, DSWA, DSWB; bit 0 first): control id, 0 = none
// DIP switch bytes 0-3 hold the idle level of every bit of IN0, IN1, DSWA, DSWB; a pressed control inverts its bit
reg [7:0] game_var   = 8'd0;
reg [7:0] game_flags = 8'h90;
reg [5:0] in_map[32];

always @(posedge CLK_49M) begin
    if (ioctl_wr && ioctl_index == 8'd1) begin
        if (ioctl_addr == 25'd0) game_var   <= ioctl_dout;
        if (ioctl_addr == 25'd1) game_flags <= ioctl_dout;
        if (ioctl_addr[24:5] == 20'd0 && ioctl_addr[4]) in_map[{1'b0, ioctl_addr[3:0]}] <= ioctl_dout[5:0];
        if (ioctl_addr[24:5] == 20'd1 && ioctl_addr[4] == 1'b0) in_map[{1'b1, ioctl_addr[3:0]}] <= ioctl_dout[5:0];
    end
end

wire game_vert = game_flags[4];
wire vert_view = game_vert & ~status[34];

wire [1:0] ar = status[33:32];

wire        art_fb;                // artwork framebuffer on HDMI: square canvas pixels
wire        art_wait, art_avail;
wire [11:0] art_cw, art_ch;
assign VIDEO_ARX = (!ar) ? (art_fb ? art_cw : vert_view ? 12'd3 : 12'd4) : (ar - 1'd1);
assign VIDEO_ARY = (!ar) ? (art_fb ? art_ch : vert_view ? 12'd4 : 12'd3) : 12'd0;

// Status bits start at 32 so the old Galaga core's saved settings (bits 2-31) can't leak in
`include "build_id.v"
localparam CONF_STR = {
	"GALAGA;;",
	"P1,Video Options;",
	"P1O[33:32],Aspect Ratio,Original,Full screen,[ARC1],[ARC2];",
	"P1O[34],Orientation,Vert,Horz;",
	"P1O[35],HDMI Flip,Off,On;",
	"P1O[36],CRT Flip,Off,On;",
	"P1O[46:43],H Position (CRT),0,+1,+2,+3,+4,+5,+6,+7,-8,-7,-6,-5,-4,-3,-2,-1;",
	"P1O[50:47],V Position (CRT),0,+1,+2,+3,+4,+5,+6,+7,-8,-7,-6,-5,-4,-3,-2,-1;",
	"P1O[39:37],Scandoubler Fx,None,HQ2x,CRT 25%,CRT 50%,CRT 75%;",
	"-;",
	"H1P4,Game Options;",
	"H1P4-,Artwork (MAME layout views);",
	"H1P4O[54:51],View,Off,View 1,View 2,View 3,View 4,View 5,View 6,View 7,View 8,View 9,View 10,View 11,View 12,View 13,View 14,View 15;",
	"H1P4O[55],Backdrop,On,Off;",
	"H1P4O[56],Overlay,On,Off;",
	"H1P4O[57],Bezel,On,Off;",
	"H1P4O[60],Control Panel,On,Off;",
	"H1P4O[58],Side Art,On,Off;",
	"H1P4O[59],Zoom to Screen,Off,On;",
	"H1-;",
	"P2,Pause Options;",
	"P2O[40],Pause when OSD is open,On,Off;",
	"P2O[41],Dim video after 10s,On,Off;",
	"-;",
	"P3,High Score Options;",
	"P3O[42],Autosave Hiscores,Off,On;",
	"-;",
	"DIP;",
	"-;",
	"R0,Reset;",
	"J1,Btn 1,Btn 2,Btn 3,Btn 4,Coin,Start 1P,Start 2P,Pause,Btn 5,Btn 6,Rack Test;",
	"jn,A,B,X,Y,Select,Start,R,L;",
	"V,v",`BUILD_DATE
};

hps_io #(.CONF_STR(CONF_STR)) hps_io
(
	.clk_sys(CLK_49M),
	.HPS_BUS(HPS_BUS),
	.EXT_BUS(),
	.gamma_bus(gamma_bus),
	.direct_video(direct_video),
	.video_rotated(video_rotated),

	.forced_scandoubler(forced_scandoubler),

	.buttons(buttons),
	.status(status),
	.status_menumask({~art_avail, direct_video}),

	.ioctl_download(ioctl_download),
	.ioctl_upload(ioctl_upload),
	.ioctl_upload_req(ioctl_upload_req),
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr27),
	.ioctl_dout(ioctl_dout),
	.ioctl_din(ioctl_din),
	.ioctl_index(ioctl_index),
	.ioctl_wait(art_wait),

	.joystick_0(joystick_0),
	.joystick_1(joystick_1),
	.ps2_key(ps2_key)
);


////////////////////   CLOCKS   ///////////////////

pll pll
(
	.refclk(CLK_50M),
	.rst(0),
	.outclk_0(CLK_49M),
	.reconfig_to_pll(reconfig_to_pll),
	.reconfig_from_pll(reconfig_from_pll),
	.locked(locked)
);

wire [63:0] reconfig_to_pll;
wire [63:0] reconfig_from_pll;
wire        cfg_waitrequest;

pll_cfg pll_cfg
(
	.mgmt_clk(CLK_50M),
	.mgmt_reset(0),
	.mgmt_waitrequest(cfg_waitrequest),
	.mgmt_read(0),
	.mgmt_readdata(),
	.mgmt_write(0),
	.mgmt_address(0),
	.mgmt_writedata(0),
	.reconfig_to_pll(reconfig_to_pll),
	.reconfig_from_pll(reconfig_from_pll)
);

// Hold the board in reset until the PLL is locked and the ROM download has finished
// DIAG-REVERT-2026-10-05: original below, uncomment to restore (and delete dl_hold, hps_ready)
// wire reset = RESET | status[0] | buttons[1] | ioctl_download | ~locked;
// DIAG-REVERT-2026-10-05 (dl_hold): HW-proven fix, commented out to test hps_ready alone. To restore: uncomment
// this block and the dl_hold reset line below, delete the hps_ready lines.
// Reset held ~0.34 s from FPGA configuration and past the last ioctl transfer (cured the Namco Galaga POST on HW)
// reg [23:0] dl_hold = 24'hFFFFFF;
// always @(posedge CLK_49M) begin
// 	if (ioctl_download)       dl_hold <= 24'hFFFFFF;
// 	else if (dl_hold != 24'd0) dl_hold <= dl_hold - 24'd1;
// end
// wire reset = RESET | status[0] | buttons[1] | ioctl_download | ~locked | (dl_hold != 24'd0);
// Main_MiSTer releases the sys reset on its first SPI access, before it sets status[0] for the MRA load:
// hold the board from FPGA configuration until status[0] has been seen once
reg hps_ready = 1'b0;
always @(posedge CLK_49M) if (status[0]) hps_ready <= 1'b1;
wire reset = RESET | status[0] | buttons[1] | ioctl_download | ~locked | ~hps_ready;

///////////////////         Keyboard           //////////////////

// CTL-2026-10-24: keyboard -> ctl_keyboard (rtl/mister_custom/controllers.sv); keys now act on press. Original commented out below.
// reg kb_up = 0, kb_down = 0, kb_left = 0, kb_right = 0;
// reg kb_b1 = 0, kb_b2 = 0;
// reg kb_coin1 = 0, kb_coin2 = 0, kb_start1 = 0, kb_start2 = 0, kb_pause = 0, kb_service = 0, kb_tilt = 0;
//
// wire       pressed = ~ps2_key[9];
// wire [7:0] code    = ps2_key[7:0];
//
// always @(posedge CLK_49M) begin
// 	reg old_state;
// 	old_state <= ps2_key[10];
// 	if (old_state != ps2_key[10]) begin
// 		case (code)
// 			'h16: kb_start1  <= pressed; // 1
// 			'h1E: kb_start2  <= pressed; // 2
// 			'h2E: kb_coin1   <= pressed; // 5
// 			'h36: kb_coin2   <= pressed; // 6
// 			'h46: kb_service <= pressed; // 9
// 			'h2C: kb_tilt    <= pressed; // T
// 			'h4D: kb_pause   <= pressed; // P
//
// 			'h75: kb_up      <= pressed; // up
// 			'h72: kb_down    <= pressed; // down
// 			'h6B: kb_left    <= pressed; // left
// 			'h74: kb_right   <= pressed; // right
// 			'h14: kb_b1      <= pressed; // ctrl
// 			'h11: kb_b2      <= pressed; // alt
// 		endcase
// 	end
// end
// kb: [0] up [1] down [2] left [3] right [4] Btn 1 (Ctrl) [5] Btn 2 (Alt) [6] Start 1 [7] Start 2 [8] Coin 1 [9] Coin 2 [10] Service [11] Tilt [12] Pause
wire [12:0] kb;
// CTL2-2026-10-25: controllers.sv v2: ctl_keyboard pause wired (no toggle keys here, so no behaviour change). v1 commented out below.
// ctl_keyboard keyboard(.clk(CLK_49M), .ps2_key(ps2_key), .kb(kb));
/* verilator lint_off PINCONNECTEMPTY */
ctl_keyboard keyboard(.clk(CLK_49M), .ps2_key(ps2_key), .pause(pause_cpu), .kb(kb), .kbx());
/* verilator lint_on PINCONNECTEMPTY */

//////////////////  Arcade Buttons/Interfaces   ///////////////////////////

// Joystick bits: 0 R, 1 L, 2 D, 3 U, 4-7 Btn 1-4, 8 Coin, 9 Start 1P, 10 Start 2P, 11 Pause, 12-14 Btn 5-6 + Rack Test
// CTL-2026-10-24: keyboard arrows from ctl_keyboard. Original commented out below.
// wire [3:0] dir1_raw = {joystick_0[3] | kb_up, joystick_0[2] | kb_down, joystick_0[1] | kb_left, joystick_0[0] | kb_right};
wire [3:0] dir1_raw = {joystick_0[3] | kb[0], joystick_0[2] | kb[1], joystick_0[1] | kb[2], joystick_0[0] | kb[3]};
wire [3:0] dir2_raw = joystick_1[3:0];
wire [3:0] dir1, dir2;   // {U, D, L, R}

// CTL-2026-10-24: 4-way restriction -> ctl_joy4way. Original commented out below.
// joy4way joy4way_1(.clk(CLK_49M), .en(game_flags[0]), .in(dir1_raw), .out(dir1));
// joy4way joy4way_2(.clk(CLK_49M), .en(game_flags[0]), .in(dir2_raw), .out(dir2));
ctl_joy4way joy4way_1(.clk(CLK_49M), .en(game_flags[0]), .in(dir1_raw), .out(dir1));
ctl_joy4way joy4way_2(.clk(CLK_49M), .en(game_flags[0]), .in(dir2_raw), .out(dir2));

// CTL-2026-10-24: keyboard P from ctl_keyboard. Original commented out below.
// wire m_pause = joystick_0[11] | kb_pause;
wire m_pause = joystick_0[11] | kb[12];

// CTL-2026-10-24: coin PORT_IMPULSE(2) -> ctl_coin_impulse. Original commented out below.
// // MAME PORT_IMPULSE(2): a coin press is latched, then held for exactly two frames from the next vblank
// wire       coin1_raw = joystick_0[8] | kb_coin1;
// wire       coin2_raw = joystick_1[8] | kb_coin2;
// reg        coin1_d = 1'b0, coin2_d = 1'b0, coin1_pend = 1'b0, coin2_pend = 1'b0, imp_vbl = 1'b0;
// reg  [1:0] coin1_frames = 2'd0, coin2_frames = 2'd0;
// always @(posedge CLK_49M) begin
// 	coin1_d <= coin1_raw;
// 	coin2_d <= coin2_raw;
// 	imp_vbl <= vblank;
// 	if (coin1_raw & ~coin1_d) coin1_pend <= 1'b1;
// 	if (coin2_raw & ~coin2_d) coin2_pend <= 1'b1;
// 	if (vblank & ~imp_vbl) begin
// 		if (coin1_pend)                begin coin1_frames <= 2'd2; coin1_pend <= 1'b0; end
// 		else if (coin1_frames != 2'd0) coin1_frames <= coin1_frames - 2'd1;
// 		if (coin2_pend)                begin coin2_frames <= 2'd2; coin2_pend <= 1'b0; end
// 		else if (coin2_frames != 2'd0) coin2_frames <= coin2_frames - 2'd1;
// 	end
// end
// wire coin1 = game_flags[2] ? |coin1_frames : coin1_raw;
// wire coin2 = game_flags[2] ? |coin2_frames : coin2_raw;
// MAME PORT_IMPULSE(2) when game_flags[2]: a coin press is held for exactly two frames from the next vblank.
// CTL2-2026-10-25: coin impulse paused with the CPU (PAUSE_MODE 1: frame count holds, a press while paused is discarded). v1 commented out below.
// // pause tied 0: the original block keeps counting vblanks while paused (bit-identical).
// wire coin1, coin2;
// ctl_coin_impulse coin_imp1(.clk(CLK_49M), .pause(1'b0), .vblank(vblank), .en(game_flags[2]),
//                            .coin_raw(joystick_0[8] | kb[8]), .coin(coin1));
// ctl_coin_impulse coin_imp2(.clk(CLK_49M), .pause(1'b0), .vblank(vblank), .en(game_flags[2]),
//                            .coin_raw(joystick_1[8] | kb[9]), .coin(coin2));
wire coin1, coin2;
ctl_coin_impulse #(.PAUSE_MODE(1)) coin_imp1(.clk(CLK_49M), .pause(pause_cpu), .vblank(vblank), .en(game_flags[2]),
                           .coin_raw(joystick_0[8] | kb[8]), .coin(coin1));
ctl_coin_impulse #(.PAUSE_MODE(1)) coin_imp2(.clk(CLK_49M), .pause(pause_cpu), .vblank(vblank), .en(game_flags[2]),
                           .coin_raw(joystick_1[8] | kb[9]), .coin(coin2));

// Rack Test cheat: held (MAME DIP with a key), or flipped on each press (MAME PORT_TOGGLE)
wire rack_btn = joystick_0[14] | joystick_1[14];
// CTL-2026-10-24: Rack Test PORT_TOGGLE -> ctl_toggle. Original commented out below.
// reg  rack_d = 1'b0, rack_tog = 1'b0;
// always @(posedge CLK_49M) begin
// 	rack_d <= rack_btn;
// 	if (ioctl_download)          rack_tog <= 1'b0;
// 	else if (rack_btn & ~rack_d) rack_tog <= ~rack_tog;
// end
wire rack_tog;
// CTL2-2026-10-25: Rack Test toggle ignores presses while paused. v1 commented out below.
// ctl_toggle rack_toggle(.clk(CLK_49M), .clear(ioctl_download), .btn(rack_btn), .q(rack_tog));
ctl_toggle rack_toggle(.clk(CLK_49M), .clear(ioctl_download), .btn(rack_btn), .pause(pause_cpu), .q(rack_tog));

// CTL-2026-10-24: control ids 0-35 -> ctl_ids (pad 2's Start = Start 2 only); ids 36-37 stay core-local. Original commented out below.
// // control ids used by the MRA input map
// wire [63:0] ctl =
// {
// 	26'd0,
// 	rack_tog,                                       // 37 rack test (toggle)
// 	rack_btn,                                       // 36 rack test (held)
// 	joystick_1[13:12],                              // 35-34 P2 Btn 6-5
// 	joystick_0[13:12],                              // 33-32 P1 Btn 6-5
// 	8'd0,                                           // 31-24 unused
// 	1'b0,                                           // 23 coin 3
// 	kb_service,                                     // 22 service
// 	kb_tilt,                                        // 21 tilt
// 	joystick_0[10] | joystick_1[10] | kb_start2,    // 20 start 2
// 	joystick_0[9]  | joystick_1[9]  | kb_start1,    // 19 start 1
// 	coin2,                                          // 18 coin 2
// 	coin1,                                          // 17 coin 1
// 	joystick_1[7:4],                                // 16-13 P2 Btn 4-1
// 	dir2[0], dir2[1], dir2[2], dir2[3],             // 12 R, 11 L, 10 D, 9 U
// 	joystick_0[7:6], joystick_0[5] | kb_b2, joystick_0[4] | kb_b1,   // 8-5 P1 Btn 4-1
// 	dir1[0], dir1[1], dir1[2], dir1[3],             // 4 R, 3 L, 2 D, 1 U
// 	1'b0                                            // 0 none
// };
wire [35:0] ctl36;
ctl_ids ids(.joy0(joystick_0), .joy1(joystick_1), .kb(kb), .dir1(dir1), .dir2(dir2),
            .coin1(coin1), .coin2(coin2), .coin3(1'b0), .ctl(ctl36));
wire [63:0] ctl =
{
	26'd0,
	rack_tog,                                       // 37 rack test (toggle)
	rack_btn,                                       // 36 rack test (held)
	ctl36                                           // 35-0 shared ids
};

// DIP switches arrive from the OSD via ioctl index 254
reg [7:0] dip_sw[8] = '{8'hFF,8'hFF,8'hFF,8'hFF,8'h00,8'h00,8'h00,8'h00};
always @(posedge CLK_49M) begin
	if (ioctl_wr && (ioctl_index == 8'd254) && !ioctl_addr[24:3])
		dip_sw[ioctl_addr[2:0]] <= ioctl_dout;
end

// Controls idle high (all active-low, MAME galaga.cpp) whatever the DIP bytes hold; only DIP switch bits come from them.
// IN0/IN1: all controls except IN1 bit 7 (Service Mode). DSWA/DSWB: bits mapped to a player button (Xevious bombs).
function automatic is_btn(input [5:0] id);
	is_btn = (id >= 6'd5 && id <= 6'd8) || (id >= 6'd13 && id <= 6'd16) || (id >= 6'd32 && id <= 6'd35);
endfunction

wire [31:0] idle;
assign idle[15:0] = {dip_sw[1][7], 7'h7F, 8'hFF};
genvar gi;
generate
	for (gi = 16; gi < 32; gi = gi + 1) begin : dsw_idle
		assign idle[gi] = is_btn(in_map[gi]) ? 1'b1 : dip_sw[gi / 8][gi % 8];
	end
endgenerate

// CTL-2026-10-24: input port builder -> ctl_port_map (idle computed above). Original commented out below.
// reg [7:0] in_port[4];
// always @(posedge CLK_49M) begin
// 	for (int p = 0; p < 4; p++)
// 		for (int b = 0; b < 8; b++)
// 			in_port[p][b] <= idle[p*8 + b] ^ ctl[in_map[p*8 + b]];
// end
wire [7:0]   in_port[4];
wire [31:0]  in_ports;
wire [255:0] in_map_flat;
generate
	for (gi = 0; gi < 4; gi = gi + 1) begin : g_port
		assign in_port[gi] = in_ports[gi*8 +: 8];
	end
	for (gi = 0; gi < 32; gi = gi + 1) begin : g_map
		assign in_map_flat[gi*8 +: 8] = {2'b00, in_map[gi]};
	end
endgenerate
// CTL2-2026-10-25: controllers.sv v2: port_sel / dip_bytes / dip_bit tied 0 (unused in BASE_MODE 0; idle stays the local is_btn builder). v1 commented out below.
// ctl_port_map #(.NP(4), .IDW(6)) port_map
// (
// 	.clk(CLK_49M), .idle(idle), .in_map(in_map_flat), .dips(32'd0), .ctl(ctl),
// 	.ovr_mask(32'd0), .ovr_val(32'd0), .ports(in_ports)
// );
ctl_port_map #(.NP(4), .IDW(6)) port_map
(
	.clk(CLK_49M), .idle(idle), .in_map(in_map_flat), .dips(32'd0), .port_sel(32'd0), .dip_bytes(64'd0), .dip_bit(96'd0),
	.ctl(ctl), .ovr_mask(32'd0), .ovr_val(32'd0), .ports(in_ports)
);

// PAUSE SYSTEM
wire [23:0] rgb_out;
pause #(8,8,8,49) pause
(
	.*,
	.clk_sys(CLK_49M),
	.user_button(m_pause),
	.pause_request(hs_pause),
	.options(~status[41:40])
);

///////////////                 Video                  ////////////////

wire hs, vs;
wire [7:0] r, g, b;
wire ce_pix;
wire        bd_hs, bd_vs, bd_hbl, bd_vbl;
wire  [7:0] bd_r, bd_g, bd_b;

// MAME artwork (ioctl index 5, OSD Artwork page): native composite on the core video (one pixel late),
// full view through the DDR3 framebuffer on HDMI. 7-bit colour codes: Galaga's starfield puts ~70 colours on screen.
wire        art_run, art_ddr;
wire [31:0] art_fb_base;
wire  [7:0] art_burstcnt, art_be;
wire [28:0] art_addr;
wire [63:0] art_din;
wire        art_rd, art_we, art_clk;
artwork #(.IDX(8'd5), .CODE_BITS(7)) artwork
(
	.clk(CLK_49M),
	.sel(status[54:51]), .layer_off({status[60], status[57:55]}), .side_off(status[58]), .zoom(status[59]),
	.crt_flip(status[36]), .hdmi_flip(status[35]), .turn(status[34]), .avail(art_avail),
	.hdmi_w(HDMI_WIDTH), .hdmi_h(HDMI_HEIGHT),
	.ioctl_download(ioctl_download), .ioctl_index(ioctl_index), .ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr27), .ioctl_dout(ioctl_dout), .ioctl_wait(art_wait),
	.ce_pix(ce_pix),
	.hs_in(bd_hs), .vs_in(bd_vs), .hblank_in(bd_hbl), .vblank_in(bd_vbl), .rgb_in({bd_r, bd_g, bd_b}),
	.hs_out(hs), .vs_out(vs), .hblank_out(hblank), .vblank_out(vblank), .rgb_out({r, g, b}),
	.running(art_run), .ddr_owner(art_ddr), .canvas_w(art_cw), .canvas_h(art_ch),
	.fb_base(art_fb_base), .fb_vbl(FB_VBL),
	.DDRAM_CLK(art_clk), .DDRAM_BUSY(DDRAM_BUSY), .DDRAM_BURSTCNT(art_burstcnt), .DDRAM_ADDR(art_addr),
	.DDRAM_DOUT(DDRAM_DOUT), .DDRAM_DOUT_READY(DDRAM_DOUT_READY), .DDRAM_RD(art_rd),
	.DDRAM_DIN(art_din), .DDRAM_BE(art_be), .DDRAM_WE(art_we)
);
// Orientation Horz (rotated monitor): the artwork turns its own view, so it keeps the framebuffer
assign art_fb = art_run & ~direct_video;

wire rotate_ccw = ~game_flags[7];  // ROT270 sets rotate CCW, ROT90 sets CW
wire no_rotate  = ~game_vert | status[34] | direct_video;
wire flip       = status[35];
wire        sr_fb_en, sr_clk, sr_rd, sr_we;
wire  [4:0] sr_fb_format;
wire [11:0] sr_fb_w, sr_fb_h;
wire [31:0] sr_fb_base;
wire [13:0] sr_fb_stride;
wire  [7:0] sr_burstcnt, sr_be;
wire [28:0] sr_addr;
wire [63:0] sr_din;
screen_rotate screen_rotate
(
	.*,
	.FB_EN(sr_fb_en), .FB_FORMAT(sr_fb_format), .FB_WIDTH(sr_fb_w), .FB_HEIGHT(sr_fb_h),
	.FB_BASE(sr_fb_base), .FB_STRIDE(sr_fb_stride),
	.DDRAM_CLK(sr_clk), .DDRAM_BURSTCNT(sr_burstcnt), .DDRAM_ADDR(sr_addr), .DDRAM_DIN(sr_din),
	.DDRAM_BE(sr_be), .DDRAM_WE(sr_we), .DDRAM_RD(sr_rd)
);

// the artwork takes the framebuffer while it draws, and DDR3 while it loads or draws
assign FB_EN     = art_fb | sr_fb_en;
assign FB_FORMAT = art_fb ? 5'b00110  : sr_fb_format;
assign FB_WIDTH  = art_fb ? art_cw    : sr_fb_w;
assign FB_HEIGHT = art_fb ? art_ch    : sr_fb_h;
assign FB_BASE   = art_fb ? art_fb_base : sr_fb_base;
assign FB_STRIDE = art_fb ? 14'd8192  : sr_fb_stride;
assign DDRAM_CLK      = CLK_49M;
assign DDRAM_BURSTCNT = art_ddr ? art_burstcnt : sr_burstcnt;
assign DDRAM_ADDR     = art_ddr ? art_addr : sr_addr;
assign DDRAM_DIN      = art_ddr ? art_din : sr_din;
assign DDRAM_BE       = art_ddr ? art_be : sr_be;
assign DDRAM_WE       = art_ddr ? art_we : sr_we;
assign DDRAM_RD       = art_ddr ? art_rd : sr_rd;

arcade_video #(288,24) arcade_video
(
	.*,

	.clk_video(CLK_49M),

	.RGB_in(rgb_out),
	.HBlank(hblank),
	.VBlank(vblank),
	.HSync(hs),
	.VSync(vs),

	.fx(status[39:37])
);

///////////////                 Board                  ////////////////

galaga_board board
(
	.clk(CLK_49M),
	.reset(reset),
	.pause(pause_cpu),
	.crt_flip(status[36]),
	.h_adj(status[46:43]),
	.v_adj(status[50:47]),
	.variant(game_var),

	.in0(in_port[0]),
	.in1(in_port[1]),
	.dswa(in_port[2]),
	.dswb(in_port[3]),

	.earom_addr(6'd0),
	.earom_din(8'd0),
	.earom_we(1'b0),
	.earom_dout(),

	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_dout),
	.ioctl_wr0(ioctl_wr & (ioctl_index == 8'd0)),

	.ce_pix(ce_pix),
	.video_r(bd_r),
	.video_g(bd_g),
	.video_b(bd_b),
	.video_hs(bd_hs),
	.video_vs(bd_vs),
	.video_hblank(bd_hbl),
	.video_vblank(bd_vbl),

	.audio(audio),

	.hs_access(hs_access_read | hs_access_write),
	.hs_address(hs_address),
	.hs_data_in(hs_data_in),
	.hs_data_out(hs_data_out),
	.hs_write(hs_write_enable)
);

// Hiscore: config = MRA index 3, dump = index 4; the board's bus is handed to it while the CPUs are paused
wire [15:0] hs_address;
wire  [7:0] hs_data_in;
wire  [7:0] hs_data_out;
wire        hs_write_enable;
wire        hs_access_read;
wire        hs_access_write;
wire        hs_pause;
wire        hs_configured;

hiscore #(
	.HS_ADDRESSWIDTH(16),
	.CFG_ADDRESSWIDTH(4),
	.CFG_LENGTHWIDTH(2)
) hi (
	.*,
	.clk(CLK_49M),
	.paused(pause_cpu),
	.autosave(status[42]),
	.ram_address(hs_address),
	.data_from_ram(hs_data_out),
	.data_to_ram(hs_data_in),
	.data_from_hps(ioctl_dout),
	.data_to_hps(ioctl_din),
	.ram_write(hs_write_enable),
	.ram_intent_read(hs_access_read),
	.ram_intent_write(hs_access_write),
	.pause_cpu(hs_pause),
	.configured(hs_configured)
);

endmodule

// CTL-2026-10-24: local joy4way replaced by ctl_joy4way (rtl/mister_custom/controllers.sv). Original commented out below.
// // 4-way joystick: the most recently pressed direction wins (from the MiSTer Pac-Man port)
// module joy4way
// (
// 	input        clk,
// 	input        en,
// 	input  [3:0] in,
// 	output [3:0] out
// );
//
// reg  [3:0] mask = 4'hF;
// reg  [3:0] in1 = 0, in2 = 0;
// wire [3:0] innew = in1 & ~in2;
//
// assign out = in1 & mask;
//
// always @(posedge clk) begin
// 	in1 <= in;
// 	in2 <= in1;
//
// 	if (innew[0]) mask <= 4'b0001;
// 	if (innew[1]) mask <= 4'b0010;
// 	if (innew[2]) mask <= 4'b0100;
// 	if (innew[3]) mask <= 4'b1000;
//
// 	if (!(in & mask) || !en) mask <= 4'hF;
// end
//
// endmodule
