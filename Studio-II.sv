//============================================================================
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or (at your option)
//  any later version.
//
//  This program is distributed in the hope that it will be useful, but WITHOUT
//  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
//  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
//  more details.
//
//  You should have received a copy of the GNU General Public License along
//  with this program; if not, write to the Free Software Foundation, Inc.,
//  51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
//
//============================================================================

module emu
(
	//Master input clock
	input         CLK_50M,

	//Async reset from top-level module.
	//Can be used as initial reset.
	input         RESET,

	//Must be passed to hps_io module
	inout  [45:0] HPS_BUS,

	//Base video clock. Usually equals to CLK_SYS.
	output        CLK_VIDEO,

	//Multiple resolutions are supported using different CE_PIXEL rates.
	//Must be based on CLK_VIDEO
	output        CE_PIXEL,

	//Video aspect ratio for HDMI.
	output [12:0] VIDEO_ARX,
	output [12:0] VIDEO_ARY,

	output  [7:0] VGA_R,
	output  [7:0] VGA_G,
	output  [7:0] VGA_B,
	output        VGA_HS,
	output        VGA_VS,
	output        VGA_DE,    // = ~(VBlank | HBlank)
	output        VGA_F1,
	output [1:0]  VGA_SL,
	output        VGA_SCALER,  // Force VGA scaler
	output        VGA_DISABLE,

	input  [11:0] HDMI_WIDTH,
	input  [11:0] HDMI_HEIGHT,
	output        HDMI_FREEZE,
	output        HDMI_BLACKOUT,
	output        HDMI_BOB_DEINT,



`ifdef MISTER_FB
	// Use framebuffer in DDRAM (USE_FB=1 in qsf)
	// FB_FORMAT:
	//    [2:0] : 011=8bpp(palette) 100=16bpp 101=24bpp 110=32bpp
	//    [3]   : 0=16bits 565 1=16bits 1555
	//    [4]   : 0=RGB  1=BGR (for 16/24/32 modes)
	//
	// FB_STRIDE either 0 (rounded to 256 bytes) or multiple of pixel size (in bytes)
	output        FB_EN,
	output  [4:0] FB_FORMAT,
	output [11:0] FB_WIDTH,
	output [11:0] FB_HEIGHT,
	output [31:0] FB_BASE,
	output [13:0] FB_STRIDE,
	input         FB_VBL,
	input         FB_LL,
	output        FB_FORCE_BLANK,

`ifdef MISTER_FB_PALETTE
	// Palette control for 8bit modes.
	// Ignored for other video modes.
	output        FB_PAL_CLK,
	output  [7:0] FB_PAL_ADDR,
	output [23:0] FB_PAL_DOUT,
	input  [23:0] FB_PAL_DIN,
	output        FB_PAL_WR,
`endif
`endif

	output        LED_USER,  // 1 - ON, 0 - OFF.

	// b[1]: 0 - LED status is system status OR'd with b[0]
	//       1 - LED status is controled solely by b[0]
	// hint: supply 2'b00 to let the system control the LED.
	output  [1:0] LED_POWER,
	output  [1:0] LED_DISK,

	// I/O board button press simulation (active high)
	// b[1]: user button
	// b[0]: osd button
	output  [1:0] BUTTONS,

	input         CLK_AUDIO, // 24.576 MHz
	output [15:0] AUDIO_L,
	output [15:0] AUDIO_R,
	output        AUDIO_S,   // 1 - signed audio samples, 0 - unsigned
	output  [1:0] AUDIO_MIX, // 0 - no mix, 1 - 25%, 2 - 50%, 3 - 100% (mono)

	//ADC
	inout   [3:0] ADC_BUS,

	//SD-SPI
	output        SD_SCK,
	output        SD_MOSI,
	input         SD_MISO,
	output        SD_CS,
	input         SD_CD,

	//High latency DDR3 RAM interface
	//Use for non-critical time purposes
	output        DDRAM_CLK,
	input         DDRAM_BUSY,
	output  [7:0] DDRAM_BURSTCNT,
	output [28:0] DDRAM_ADDR,
	input  [63:0] DDRAM_DOUT,
	input         DDRAM_DOUT_READY,
	output        DDRAM_RD,
	output [63:0] DDRAM_DIN,
	output  [7:0] DDRAM_BE,
	output        DDRAM_WE,

	//SDRAM interface with lower latency
	output        SDRAM_CLK,
	output        SDRAM_CKE,
	output [12:0] SDRAM_A,
	output  [1:0] SDRAM_BA,
	inout  [15:0] SDRAM_DQ,
	output        SDRAM_DQML,
	output        SDRAM_DQMH,
	output        SDRAM_nCS,
	output        SDRAM_nCAS,
	output        SDRAM_nRAS,
	output        SDRAM_nWE,

`ifdef MISTER_DUAL_SDRAM
	//Secondary SDRAM
	//Set all output SDRAM_* signals to Z ASAP if SDRAM2_EN is 0
	input         SDRAM2_EN,
	output        SDRAM2_CLK,
	output [12:0] SDRAM2_A,
	output  [1:0] SDRAM2_BA,
	inout  [15:0] SDRAM2_DQ,
	output        SDRAM2_nCS,
	output        SDRAM2_nCAS,
	output        SDRAM2_nRAS,
	output        SDRAM2_nWE,
`endif

	input         UART_CTS,
	output        UART_RTS,
	input         UART_RXD,
	output        UART_TXD,
	output        UART_DTR,
	input         UART_DSR,

	// Open-drain User port.
	// 0 - D+/RX
	// 1 - D-/TX
	// 2..6 - USR2..USR6
	// Set USER_OUT to 1 to read from USER_IN.
	input   [6:0] USER_IN,
	output  [6:0] USER_OUT,

	input         OSD_STATUS
);

///// Default values for ports not used in this core /////////

assign ADC_BUS  = 'Z;
assign USER_OUT = '1;
assign {UART_RTS, UART_TXD, UART_DTR} = 0;
assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;
assign {SDRAM_DQ, SDRAM_A, SDRAM_BA, SDRAM_CLK, SDRAM_CKE, SDRAM_DQML, SDRAM_DQMH, SDRAM_nWE, SDRAM_nCAS, SDRAM_nRAS, SDRAM_nCS} = 'Z;
assign {DDRAM_CLK, DDRAM_BURSTCNT, DDRAM_ADDR, DDRAM_DIN, DDRAM_BE, DDRAM_RD, DDRAM_WE} = '0;  

assign VGA_SL = 0;
assign VGA_F1 = 0;
assign VGA_SCALER = 0;
assign VGA_DISABLE = 0;
assign HDMI_FREEZE = 0;
assign HDMI_BLACKOUT = 0;
assign HDMI_BOB_DEINT = 0;

// Signed audio sample generated in rcastudioii.sv
wire signed [15:0] audio;
assign AUDIO_S   = 1'b1;                                   // signed samples
assign AUDIO_MIX = 2'd0;

assign LED_DISK = 0;
assign LED_POWER = 0;
assign BUTTONS = 0;

//////////////////////////////////////////////////////////////////////

`include "build_id.v"
localparam CONF_STR = {
	"Studio-II;v11;",
	"F1,ST2BIN,Load Software;",
	// CHIP-8 data can be preloaded regardless of the active machine
	"F3,CH8,Load CHIP-8;",
	"-;",

	// Machine held until Apply
	"O[14:13],Machine,Studio II,Studio III PAL,Studio III NTSC,Visicom;",
	"R[15],Apply and Reset;",
	"-;",

	"O[6],Mapping,Auto,Manual;",
	// Order must match localparams in rtl/rcastudioii.sv
	"D2O[5:2],Joystick,None,4-way,Space War,Freeway,Bowling,Baseball,Robson,Visicom Art,8-way,Art,Robson2P,Race,Gunfighter/Tennis,CHIP-8,Climber/Outbreak,Space Explorer;",
	"O[8:7],Players,Auto,1,2;",
	"O[10:9],Numstick,Off,Pad A,Pad B;",
	"-;",

	"P1,Audio & Video;",
	"P1-;",
	"P1O[122:121],Aspect Ratio,Original,Full Screen,[ARC1],[ARC2];",
	// Menu-mask prefixes must precede page selector
	"d6P1O[21],Vertical Crop,Disabled,216p (5x);",
	"d6P1O[25:22],Crop Offset,0,2,4,8,10,12,-12,-10,-8,-6,-4,-2;",
	"P1O[12:11],Scale,Normal,V-Integer,Narrower HV-Integer,Wider HV-Integer;",
	"P1O[26],Borders,Show,Hide;",
	"P1-;",
	"D8P1O[33:31],Studio II Palette,Original,Amber,Green,Inverted,Custom;",
	"HBP1F6,GBP,Load Custom Palette;",
	"D7P1O[39:37],Studio III Palette,Original,Prototype,Warm,Cool,Custom;",
	"HAP1F7,PAL,Load Custom Palette;",
	"D9P1O[36:34],Visicom Palette,Balanced,Box Art,Emma 02,FLiP,MAME,Manuals,Nicole Express,Custom;",
	"HCP1F5,GBP,Load Custom Palette;",
	"P1-;",
	"P1O[16],Sound,On,Off;",
	"D4P1O[19:17],Beeper Pitch,Original,High,Higher,Highest,Lowest,Lower,Low;",
	"D5P1O[20],CDP1863 Pitch,Original,PAL (Lower);",

	"P3,System;",
	"P3-;",
	"P3F2,BINROM,Load Firmware/ROM;",
	"P3F4,BINROM,Load CHIP-8 Interp.;",
	"P3-;",
	"P3T[1],Clear;",
	"P3T[0],Reset;",
	"P3-;",
	"P3R[28],Unload Software;",
	"P3R[27],Unload Software and Reset;",
	"-;",

	"R[0],Reset and Close OSD;",

	// Virtual mappings
	"J1,Fire,Extra,Start,Clear,A0,A1,A2,A3,A4,A5,A6,A7,A8,A9,B0,B1,B2,B3,B4,B5,B6,B7,B8,B9;",
	// Default virtual mapping
	"jn,A,B,Start,Select;",
	"V,v",`BUILD_DATE
};

wire forced_scandoubler;
wire  [21:0] gamma_bus;
wire   [1:0] buttons;
wire [127:0] status;
// Gray-out OSD options
wire  [15:0] status_menumask;
wire  [10:0] ps2_key;
wire  [31:0] joystick_0, joystick_1;
wire  [15:0] joystick_l_analog_0, joystick_r_analog_0;
wire  [15:0] joystick_l_analog_1, joystick_r_analog_1;

// Tone generators continue running.
wire signed [15:0] audio_out = status[16] ? 16'sd0 : audio;
assign AUDIO_L = audio_out;
assign AUDIO_R = audio_out;

// NOTE: this is a hack to keep video alive and prevent HDMI resync 
// this mostly works fine but you might get an occasional glitch
// ~elle
reg clear_key = 1'b0;
always @(posedge clk_sys) begin
	reg old_stb;
	old_stb <= ps2_key[10];
	if (old_stb != ps2_key[10] && ps2_key[7:0] == 8'h04) clear_key <= ps2_key[9];
end

wire        ioctl_download;
wire [15:0] ioctl_index;
wire        ioctl_wr;
wire [24:0] ioctl_addr;
wire  [7:0] ioctl_data;

hps_io #(.CONF_STR(CONF_STR), .CONF_STR_BRAM(1)) hps_io
(
	.clk_sys(clk_sys),
	.HPS_BUS(HPS_BUS),
	.EXT_BUS(),
	.gamma_bus(gamma_bus),

	.forced_scandoubler(forced_scandoubler),

	//ioctl
	.ioctl_download(ioctl_download),
	.ioctl_index(ioctl_index),
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_data),

	.buttons(buttons),
	.status(status),
	.status_in(status_in),
	.status_set(status_set),
	.status_menumask(status_menumask),

	.ps2_key(ps2_key),
	.joystick_0(joystick_0),
	.joystick_1(joystick_1),
	.joystick_l_analog_0(joystick_l_analog_0),
	.joystick_r_analog_0(joystick_r_analog_0),
	.joystick_l_analog_1(joystick_l_analog_1),
	.joystick_r_analog_1(joystick_r_analog_1)
);

///////////////////////   CLOCKS   ///////////////////////////////

wire clk_sys;
wire clk_vid;
pll pll
(
	.refclk(CLK_50M),
	.rst(0),
	.outclk_0(clk_sys),
	.outclk_1(clk_vid)
);

// One pixel per 1802 clock
// 1.7897725 MHz nominal versus core's 1.760229 MHz (clk_sys/4).
reg [1:0] ce_cnt = 2'd0;
always @(posedge clk_sys) ce_cnt <= ce_cnt + 2'd1;
wire ce_pix = (ce_cnt == 2'd0);

// Select / Clear
wire joy_clear = joystick_0[7] | joystick_1[7];
wire clear_request = status[1] | clear_key | joy_clear;

// Preserve video timing on soft resets
reg       vis_palette_latched = 1'b0;
reg       studio_palette_latched = 1'b0;
reg       studio3_palette_latched = 1'b0;
wire      vis_palette_index = ioctl_index[5:0] == 6'd5;
wire      studio_palette_index = ioctl_index[5:0] == 6'd6;
wire      studio3_palette_index = ioctl_index[5:0] == 6'd7;
wire      vis_palette_download = ioctl_download &&
	                              (vis_palette_index || vis_palette_latched);
wire      studio_palette_download = ioctl_download &&
	                                 (studio_palette_index || studio_palette_latched);
wire      studio3_palette_download = ioctl_download &&
	                                  (studio3_palette_index || studio3_palette_latched);
wire      palette_download = vis_palette_download || studio_palette_download ||
	                         studio3_palette_download;
wire      machine_download = ioctl_download && !palette_download;
wire      user_download_now = (ioctl_index[5:0] == 6'd1) ||
	                          (ioctl_index[5:0] == 6'd2) ||
	                          (ioctl_index[5:0] == 6'd3) ||
	                          (ioctl_index[5:0] == 6'd4);
reg       download_soft_latched = 1'b0;
reg [7:0] download_reset_cnt = 8'd0;
wire      download_reset = (ioctl_download && !palette_download) |
	                       (download_reset_cnt != 0);
wire      download_soft = (ioctl_download && !palette_download) ?
	                      user_download_now : download_soft_latched;

always @(posedge clk_sys) begin
	if (!ioctl_download) begin
		vis_palette_latched <= 1'b0;
		studio_palette_latched <= 1'b0;
		studio3_palette_latched <= 1'b0;
	end
	else if (!vis_palette_latched && !studio_palette_latched && !studio3_palette_latched) begin
		if (vis_palette_index)         vis_palette_latched <= 1'b1;
		else if (studio_palette_index) studio_palette_latched <= 1'b1;
		else if (studio3_palette_index) studio3_palette_latched <= 1'b1;
	end
end

// Cartridge eject actions share the same core-side unload path. Bit 27 also
// hard-resets the machine; bit 28 deliberately leaves CPU and video running.
wire cart_unload = status[27] | status[28];

// RESET / Reset-and-close-OSD
reg [7:0] hard_reset_cnt = 8'd0;
wire      hard_reset_hold = hard_reset_cnt != 0;
reg       rom_loaded = 0;

always @(posedge CLK_50M) begin
	if (ioctl_download && !palette_download) begin
		download_reset_cnt <= 8'd255;
		download_soft_latched <= user_download_now;
	end
	else if (download_reset_cnt != 0) download_reset_cnt <= download_reset_cnt - 8'd1;

	if (RESET || status[0] || status[27] || buttons[1])
	hard_reset_cnt <= 8'd255;
	else if (hard_reset_cnt != 0) hard_reset_cnt <= hard_reset_cnt - 8'd1;

	if(ioctl_download && (((ioctl_index[5:0] == 0) && (ioctl_index[15:6] < 10'd4)) ||
	   (ioctl_index[5:0] == 2)) && ioctl_addr == 24'd100) rom_loaded <= 1'b1;
end

////////////////// Machine select and staging ////////////////
//
// status[14:13] Machine controlled only by "Apply and reset". Apply is R[15], status
// bit 15. The reset itself gets the same duration a download's reset gets.
reg [1:0] machine_active = 2'd0;
reg [7:0] apply_reset_cnt = 8'd0;
reg       apply_video_hard = 1'b0;
wire      apply_reset = apply_reset_cnt != 0;
wire      apply_crossing_now = (machine_active == 2'd1) ^ (status[14:13] == 2'd1);
always @(posedge CLK_50M) begin
	reg apply_d = 1'b0;
	apply_d <= status[15];
	if (status[15] && !apply_d) begin
		apply_reset_cnt <= 8'd255;
		// 1 = PAL; 0, 2, 3 = NTSC.
		apply_video_hard <= apply_crossing_now;
	end
	else if (apply_reset_cnt != 0) apply_reset_cnt <= apply_reset_cnt - 8'd1;
end

// Main delivers status while autoloading the boot ROMs, so changing machine_active 
// immediately can reconfigure the active machine in the middle of firmware/reset 
// startup. Start with safe Studio II power-up for 0.6s during boot, then apply user's 
// saved machine value once under reset.

reg [22:0] boot_follow_cnt = 23'd0;                  // ~0.6s at clk_sys
wire       boot_follow = ~boot_follow_cnt[22];
reg  [7:0] mach_reset_cnt = 8'd0;
wire       mach_reset = mach_reset_cnt != 0;
always @(posedge clk_sys) begin
	reg apply_reset_d = 1'b0;
	apply_reset_d <= apply_reset;
	if (boot_follow) boot_follow_cnt <= boot_follow_cnt + 23'd1;
	if (apply_reset && !apply_reset_d) machine_active <= status[14:13];
	if (boot_follow && (boot_follow_cnt == 23'h3FFFFF) &&
	    (machine_active != status[14:13])) begin
		machine_active <= status[14:13];
		mach_reset_cnt <= 8'd255;
	end
	else if (mach_reset_cnt != 0) mach_reset_cnt <= mach_reset_cnt - 8'd1;
end

// prevent issues with machine switch
wire apply_hard_reset = (status[15] && apply_crossing_now) || (apply_reset && apply_video_hard);
wire apply_soft_reset = apply_reset && !apply_hard_reset;

// Hard reset win if sources overlap
wire hard_reset = RESET | status[0] | status[27] | buttons[1] | hard_reset_hold | ~rom_loaded | mach_reset |
                  (download_reset && !download_soft) | apply_hard_reset;
wire soft_reset = clear_request | (download_reset && download_soft) | apply_soft_reset;
wire reset       = hard_reset | soft_reset;
wire video_reset = hard_reset;

//////////////////////////////////////////////////////////////////

wire HBlank;
wire HSync;
wire VBlank;
wire VSync;
wire bitmap_hblank;
wire bitmap_vblank;
wire [2:0] video;   	// R,G,B
wire       video_bg;    // CDP1864 BCKGND
wire [1:0] vis_index;   // Visicom

rcastudioii rcastudio
(
	.clk_sys(clk_sys),
	.reset(reset),
	.video_reset(video_reset),
	.cart_unload(cart_unload),
	
	.ioctl_download(machine_download),
	.ioctl_index(ioctl_index),
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_data),

	.ps2_key(ps2_key),
	.ce_pix(ce_pix),

	.HBlank(HBlank),
	.HSync(HSync),
	.VBlank(VBlank),
	.VSync(VSync),
	.video_de(),
	.bitmap_de(),
	.bitmap_hblank(bitmap_hblank),
	.bitmap_vblank(bitmap_vblank),
	.video(video),
	.vis_index(vis_index),
	.audio(audio),
	.joystick_0(joystick_0),
	.joystick_1(joystick_1),
	.joy_override(status[5:2]),
	.machine(machine_active),
	.video_bg(video_bg),
	.joy_manual(status[6]),
	.auto_profile(auto_profile),
	.players(status[8:7]),
	.beeper_tune(status[19:17]),
	.ntsc_pal_pitch(status[20]),
	.osk_a(osk_a),
	.osk_b(osk_b),
	.clear_key(clear_request)
);

////////////////// Joystick profile -> OSD ///////////////////////////////////

wire [3:0]   auto_profile;
reg  [127:0] status_in;
reg          status_set   = 1'b0;
reg    [3:0] auto_d       = 4'd0;
reg          manual_d     = 1'b0;
reg          auto_sync_done = 1'b0;
reg          push_pending = 1'b0;
reg   [21:0] push_dly     = 22'd0;

always @(posedge clk_sys) begin
	status_set <= 1'b0;
	auto_d     <= auto_profile;
	manual_d   <= status[6];

	// wait for !boot_follow to avoid user settings overwrite
	if (!boot_follow && ((!auto_sync_done && !status[6]) || (auto_profile != auto_d) ||
	    (manual_d && !status[6]))) begin
		auto_sync_done <= 1'b1;
		push_pending <= 1'b1;
		// let HPS finish first
		push_dly     <= 22'd2000000;
	end
	else if (|push_dly) begin
		push_dly <= push_dly - 1'b1;
	end
	else if (push_pending && !status[6] && !ioctl_download && !boot_follow) begin
		push_pending <= 1'b0;
		status_in    <= {status[127:6], auto_profile, status[1:0]};
		status_set   <= 1'b1;
	end
end

assign status_menumask = ((!status[6]) ? 16'h0004 : 16'h0000) |
	                     (((machine_active == 2'd1) ||
	                       (machine_active == 2'd2)) ? 16'h0010 : 16'h0000) |
	                     ((machine_active != 2'd2) ? 16'h0020 : 16'h0000) |
	                     (en216p ? 16'h0040 : 16'h0000) |
	                     (((machine_active != 2'd1) &&
	                       (machine_active != 2'd2)) ? 16'h0080 : 16'h0000) |
	                     ((machine_active != 2'd0) ? 16'h0100 : 16'h0000) |
	                     ((machine_active != 2'd3) ? 16'h0200 : 16'h0000) |
	                     ((((machine_active == 2'd1) || (machine_active == 2'd2)) &&
	                       (status[39:37] == 3'd4)) ? 16'h0000 : 16'h0400) |
	                     (((machine_active == 2'd0) &&
	                       (status[33:31] == 3'd4)) ? 16'h0000 : 16'h0800) |
	                     (((machine_active == 2'd3) &&
	                       (status[36:34] == 3'd7)) ? 16'h0000 : 16'h1000);

// resample 88 wide 4x to 352 for scaler
assign CLK_VIDEO = clk_vid;

reg  [2:0] ce_vid_cnt = 3'd0;
reg        ce_pix_vid = 1'b0;
always @(posedge clk_vid) begin
	ce_vid_cnt <= (ce_vid_cnt == 3'd5) ? 3'd0 : ce_vid_cnt + 3'd1;
	ce_pix_vid <= (ce_vid_cnt == 3'd5);
end

wire [23:0] palette_rgb;
studio2_palette palette
(
	.clk_sys(clk_sys),
	.machine(machine_active),
	.video(video),
	.video_bg(video_bg),
	.vis_index(vis_index),
	.studio2_select(status[33:31]),
	.studio3_select(status[39:37]),
	.visicom_select(status[36:34]),
	.studio2_download(studio_palette_download),
	.studio3_download(studio3_palette_download),
	.visicom_download(vis_palette_download),
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr),
	.ioctl_data(ioctl_data),
	.rgb(palette_rgb)
);

wire [7:0] vid_r = palette_rgb[23:16];
wire [7:0] vid_g = palette_rgb[15:8];
wire [7:0] vid_b = palette_rgb[7:0];

////////////////// Numstick //////////////////

wire [1:0] osk_mode   = status[10:9];   // 0 off, 1 pad A, 2 pad B
wire       osk_use_j1 = (osk_mode == 2'd2) && (status[8:7] == 2'd2);
wire [15:0] osk_l = osk_use_j1 ? joystick_l_analog_1 : joystick_l_analog_0;
wire [15:0] osk_r = osk_use_j1 ? joystick_r_analog_1 : joystick_r_analog_0;

wire [11:0] osk_press;
wire  [7:0] osk_vr, osk_vg, osk_vb;

wire output_hblank = status[26] ? bitmap_hblank : HBlank;
wire output_vblank = status[26] ? bitmap_vblank : VBlank;

numstick #(
	.HOLD_CYCLES     (3520000),   // ~0.5s  @ 7.04MHz
	.PRESS_CYCLES    (528000),    // ~75ms
	.RECENTER_CYCLES (141000),    // ~20ms
	.DEFAULT_ACTIVE_W(64),
	.DEFAULT_ACTIVE_H(128),
	.CELL_W          (18),
	.CELL_H          (12),
	.CELL_GAP        (1),
	.BOX_PAD         (2),
	.STACK_GAP       (4),
	.BORDER_THICKNESS(1)
) numstick
(
	.clk_sys  (clk_sys),
	.ce_pix   (ce_pix),
	.reset    (reset),
	.enable   (osk_mode != 2'd0),
	.hblank   (output_hblank),
	.vblank   (output_vblank),
	.in_r     (vid_r),
	.in_g     (vid_g),
	.in_b     (vid_b),
	.stick_l_x($signed(osk_l[7:0])),
	.stick_l_y($signed(osk_l[15:8])),
	.stick_r_x($signed(osk_r[7:0])),
	.stick_r_y($signed(osk_r[15:8])),
	.keypad_press(osk_press),
	.out_r    (osk_vr),
	.out_g    (osk_vg),
	.out_b    (osk_vb)
);

// numstick
wire [9:0] osk_keys = {osk_press[8:0], osk_press[9]};
wire [9:0] osk_a = (osk_mode == 2'd1) ? osk_keys : 10'd0;
wire [9:0] osk_b = (osk_mode == 2'd2) ? osk_keys : 10'd0;

wire       vga_de;
wire       freeze_sync;

// resample clk_sys into clk_vid domain
reg [7:0] vmix_r, vmix_g, vmix_b;
reg       vmix_hs, vmix_vs, vmix_hb, vmix_vb;
always @(posedge clk_vid) begin
	vmix_r  <= osk_vr;
	vmix_g  <= osk_vg;
	vmix_b  <= osk_vb;
	vmix_hs <= HSync;
	vmix_vs <= VSync;
	vmix_hb <= output_hblank;
	vmix_vb <= output_vblank;
end

video_mixer #(.LINE_LENGTH(352), .GAMMA(1)) video_mixer
(
	.CLK_VIDEO(CLK_VIDEO),
	.CE_PIXEL(CE_PIXEL),
	.ce_pix(ce_pix_vid),
	.scandoubler(forced_scandoubler),
	.hq2x(1'b0),
	.gamma_bus(gamma_bus),
	.R(vmix_r),
	.G(vmix_g),
	.B(vmix_b),
	.HSync(vmix_hs),
	.VSync(vmix_vs),
	.HBlank(vmix_hb),
	.VBlank(vmix_vb),
	.HDMI_FREEZE(HDMI_FREEZE),
	.freeze_sync(freeze_sync),
	.VGA_R(VGA_R),
	.VGA_G(VGA_G),
	.VGA_B(VGA_B),
	.VGA_VS(VGA_VS),
	.VGA_HS(VGA_HS),
	.VGA_DE(vga_de)
);

wire [1:0] ar = status[122:121];

// 5x 216p crop
wire       vcrop_en = status[21];
wire [3:0] vcopt    = status[25:22];
reg        en216p = 1'b0;
reg  [4:0] voff    = 5'd0;
always @(posedge CLK_VIDEO) begin
	en216p <= (HDMI_WIDTH == 12'd1920) && (HDMI_HEIGHT == 12'd1080) &&
	           !forced_scandoubler;
	voff <= (vcopt < 4'd6) ? {vcopt, 1'b0} : ({vcopt, 1'b0} - 5'd24);
end

// VSync one pixel later so DE falling edge and VSync 
// posedge are handled on separate enables
reg vf_vs = 1'b0;
always @(posedge CLK_VIDEO) begin
	if (CE_PIXEL) vf_vs <= VGA_VS;
end

wire scale_active = |status[12:11];
// Preserve raster pixel proportions when cropping 88x242/292 to 64x128/192.
wire [11:0] original_arx = !status[26] ? 12'd4 :
                           (machine_active == 2'd1) ? 12'd146 : 12'd11;
wire [11:0] original_ary = !status[26] ? 12'd3 :
                           (machine_active == 2'd1) ? 12'd99 : 12'd6;
wire [11:0] arx_val = (scale_active || ar == 2'd0) ? original_arx : {10'd0, ar - 1'd1};
wire [11:0] ary_val = (scale_active || ar == 2'd0) ? original_ary : 12'd0;

video_freak video_freak
(
    .CLK_VIDEO(CLK_VIDEO),
    .CE_PIXEL(CE_PIXEL),
    .VGA_VS(vf_vs),
    .HDMI_WIDTH(HDMI_WIDTH),
    .HDMI_HEIGHT(HDMI_HEIGHT),
    .VGA_DE(VGA_DE),
    .VIDEO_ARX(VIDEO_ARX),
    .VIDEO_ARY(VIDEO_ARY),
    .VGA_DE_IN(vga_de),
    .ARX(arx_val),
    .ARY(ary_val),
	.CROP_SIZE((en216p && vcrop_en) ? 12'd216 : 12'd0),
	.CROP_OFF(voff),
    .SCALE({1'b0, status[12:11]})
);

assign LED_USER = 1'b0;

endmodule
