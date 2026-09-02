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

// Signed beeper/tone sample generated in rcastudioii.sv. The Studio II/Visicom
// NE555 path includes release envelope; Studio III is a fixed-level square wave.
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
	"F1,ST2BINROM,Load Cartridge;",
	"F2,BINROM,Load Firmware;",
	"F4,BIN,Load CHIP-8 Interpreter;",
	// Main sends chip8.bin from the selected program's directory before F3.
	"f,!chip8.bin;",
	// Loading only allowed on Studio II and Studio III, not Visicom.
	"D3F3,CH8,Load CHIP-8;",
	"-;",
	// Machine held until Apply and reset
	"O[14:13],Machine,Studio II,Studio III PAL,Studio III NTSC,Visicom;",
	"R[15],Apply and reset;",
	"-;",
	"O[6],Mapping,Auto,Manual;",
	// Order must match localparams in rtl/rcastudioii.sv
	"D2O[5:2],Joystick,None,Cross,Space War,Freeway,Bowling,Baseball,Homebrew,Gunfighter,8-way,Doodle,2P Homebrew,Race,Tennis,CHIP-8,Climb/Outbreak,Space Explorer;",
	"O[8:7],Players,Auto,1,2;",
	"O[10:9],Numstick,Off,Pad A,Pad B;",
	"-;",
	"O[16],Sound,On,Off;",
	"D4O[19:17],NE555 pitch,Original,High,Higher,Highest,Lowest,Lower,Low;",
	"D5O[20],CDP1863 pitch,Original,PAL;",
	"-;",
	"O[122:121],Aspect ratio,Original,Full Screen,[ARC1],[ARC2];",
	"d6O[21],Vertical Crop,Disabled,216p (5x);",
	"d6O[25:22],Crop Offset,0,2,4,8,10,12,-12,-10,-8,-6,-4,-2;",
	"O[12:11],Scale,Normal,V-Integer,Narrower HV-Integer,Wider HV-Integer;",
	"O[26],Borders,On,Off;",
	"-;",
	"T[1],Clear;",
	"T[0],Reset;",
	"J1,Fire,Extra,Start,Clear,A0,A1,A2,A3,A4,A5,A6,A7,A8,A9,B0,B1,B2,B3,B4,B5,B6,B7,B8,B9;",
	// jn is default virtual mapping
	"jn,A,B,Start,Select;",
	"V,v",`BUILD_DATE
};

wire forced_scandoubler;
wire  [21:0] gamma_bus;
wire   [1:0] buttons;
wire [127:0] status;
// Menu mask to gray-out/disable OSD options
wire  [15:0] status_menumask;
wire  [10:0] ps2_key;
wire  [31:0] joystick_0, joystick_1;
wire  [15:0] joystick_l_analog_0, joystick_r_analog_0;
wire  [15:0] joystick_l_analog_1, joystick_r_analog_1;

// Sound On/Off switch only gates audio. Tone
// generators continue running.
wire signed [15:0] audio_out = status[16] ? 16'sd0 : audio;
assign AUDIO_L = audio_out;
assign AUDIO_R = audio_out;

// Pixie's timing generator is kept running which is
// friendlier to display sync. TODO: This is very useful but 
// still a hack and may need further scrutiny or refinement
// in the future.
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

// The CDP1861 emits one pixel per CPU clock: 1.7897725 MHz nominal, 1.760229 MHz
// here (clk_sys/4). TODO: A point of potential accuracy improvement.
reg [1:0] ce_cnt = 2'd0;
always @(posedge clk_sys) ce_cnt <= ce_cnt + 2'd1;
wire ce_pix = (ce_cnt == 2'd0);

// Select / Clear
wire joy_clear = joystick_0[7] | joystick_1[7];
wire clear_request = status[1] | clear_key | joy_clear;

// Preserve raster timing on soft resets
wire      user_download_now = (ioctl_index[5:0] == 6'd1) ||
	                          (ioctl_index[5:0] == 6'd2) ||
	                          (ioctl_index[5:0] == 6'd3) ||
	                          (ioctl_index[5:0] == 6'd4);
reg       download_soft_latched = 1'b0;
reg [7:0] download_reset_cnt = 8'd0;
wire      download_reset = ioctl_download | (download_reset_cnt != 0);
wire      download_soft = ioctl_download ? user_download_now : download_soft_latched;

// RESET / Reset-and-close-OSD
reg [7:0] hard_reset_cnt = 8'd0;
wire      hard_reset_hold = hard_reset_cnt != 0;
reg       rom_loaded = 0;

always @(posedge CLK_50M) begin
	if (ioctl_download) begin
		download_reset_cnt <= 8'd255;
		download_soft_latched <= user_download_now;
	end
	else if (download_reset_cnt != 0) download_reset_cnt <= download_reset_cnt - 8'd1;

	if (RESET || status[0] || buttons[1]) hard_reset_cnt <= 8'd255;
	else if (hard_reset_cnt != 0) hard_reset_cnt <= hard_reset_cnt - 8'd1;

	if(ioctl_download && (((ioctl_index[5:0] == 0) && (ioctl_index[15:6] < 10'd4)) ||
	   (ioctl_index[5:0] == 2)) && ioctl_addr == 24'd100) rom_loaded <= 1'b1;
end

////////////////// Machine select: staged, applied on request ////////////////
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

// Standard crossing must be hard from the initiating Apply edge, before
// stretched classification latch can become visible. Latch then retains it
// after machine_active changes and apply_crossing_now drops.
wire apply_hard_reset = (status[15] && apply_crossing_now) || (apply_reset && apply_video_hard);
wire apply_soft_reset = apply_reset && !apply_hard_reset;

// Hard reset win if sources overlap
wire hard_reset = RESET | status[0] | buttons[1] | hard_reset_hold | ~rom_loaded | mach_reset |
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
wire [2:0] video;   	// {R,G,B} from the core
wire       video_bg;    // ...at background luminance (CDP1864 BCKGND)
wire [1:0] vis_index;   // Visicom: one of its four fixed colours

rcastudioii rcastudio
(
	.clk_sys(clk_sys),
	.reset(reset),
	.video_reset(video_reset),
	
	.ioctl_download(ioctl_download),
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
//
// On Auto, the core's CRC/built-in-game detection owns the Joystick row and the
// menu is made to agree with it: hps_io's status_set hands the HPS a whole new
// status word, so writing the detected profile into bits [5:2] is what makes the
// OSD read "Gunfighter" after Gunfighter is loaded. On Manual nothing is
// written, so the row holds the last detected profile and the user edits from
// there rather than from a stale selection.

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

	// Schedule exactly one write on initial Auto mode, a new detection, or a
	// Manual-to-Auto transition. Do not test whether the row is stale here: that
	// would reload the delay on every clock and prevent the write from firing.
	// Gated by !boot_follow so initial status writeback only happens after Main
	// has delivered saved settings.
	if (!boot_follow && ((!auto_sync_done && !status[6]) || (auto_profile != auto_d) ||
	    (manual_d && !status[6]))) begin
		auto_sync_done <= 1'b1;
		push_pending <= 1'b1;
		// ~0.3 s at 7.04 MHz. map_profile only settles when the transfer ends,
		// and the HPS is busy with the download until then, so let it finish.
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

// D2 disables the manual Joystick row while Mapping is Auto. D3 disables the
// CHIP-8 picker on Visicom. D4 disables NE555 tuning on the Studio III machines.
// D5 enables the NTSC tone-pitch selector only on the Studio III NTSC. d6
// enables 216p crop controls only for un-doubled 1080p.
// Use machine_active so a staged selection does not take effect before Apply
// and reset.
assign status_menumask = ((!status[6]) ? 16'h0004 : 16'h0000) |
	                     ((machine_active == 2'd3) ? 16'h0008 : 16'h0000) |
	                     (((machine_active == 2'd1) ||
	                       (machine_active == 2'd2)) ? 16'h0010 : 16'h0000) |
	                     ((machine_active != 2'd2) ? 16'h0020 : 16'h0000) |
	                     (en216p ? 16'h0040 : 16'h0000);

// The scaler can't handle the very low res native raster. So the video
// chain runs on the PLL's 42.24 MHz output and samples the core's pixel 
// stream at 7.04 MHz. Each 1861 pixel (88) is repeated 4x to 352 wide.
assign CLK_VIDEO = clk_vid;

reg  [2:0] ce_vid_cnt = 3'd0;
reg        ce_pix_vid = 1'b0;
always @(posedge clk_vid) begin
	ce_vid_cnt <= (ce_vid_cnt == 3'd5) ? 3'd0 : ce_vid_cnt + 3'd1;
	ce_pix_vid <= (ce_vid_cnt == 3'd5);
end

// 1-bit {R,G,B} per channel to mirror the CDP1864's three
// colour pins. The Studio II's 1861 drives all three together.
// BCKGND lowers the luminance of background pixels, so one colour can serve as
// both background and data, see datasheet. Half scale here.
wire [7:0] vid_lvl = video_bg ? 8'h80 : 8'hFF;

// Visicom colours are fixed values so they cannot be expressed
// on the {R,G,B} bus above.
//
// The current default is MAME's four-entry table. Alternative emulator values,
// source observations, and future selectable/custom palette requirements are
// tracked in docs/visicom-palettes.md.
wire machine_visicom = (machine_active == 2'd3);
reg [23:0] vis_rgb;
always @(*) begin
	case (vis_index)
		2'd0:    vis_rgb = 24'h004000;
		2'd1:    vis_rgb = 24'hAFDFE4;
		2'd2:    vis_rgb = 24'hB9C42F;
		default: vis_rgb = 24'hEF454A;
	endcase
end

wire [7:0] vid_r = machine_visicom ? vis_rgb[23:16] : (video[2] ? vid_lvl : 8'h00);
wire [7:0] vid_g = machine_visicom ? vis_rgb[15:8]  : (video[1] ? vid_lvl : 8'h00);
wire [7:0] vid_b = machine_visicom ? vis_rgb[7:0]   : (video[0] ? vid_lvl : 8'h00);

////////////////// Numstick //////////////////

wire [1:0] osk_mode   = status[10:9];   // 0 off, 1 pad A, 2 pad B
wire       osk_use_j1 = (osk_mode == 2'd2) && (status[8:7] == 2'd2);
wire [15:0] osk_l = osk_use_j1 ? joystick_l_analog_1 : joystick_l_analog_0;
wire [15:0] osk_r = osk_use_j1 ? joystick_r_analog_1 : joystick_r_analog_0;

wire [11:0] osk_press;
wire  [7:0] osk_vr, osk_vg, osk_vb;

// Border hiding changes only the presented active window. Device counters and
// sync pulses keep running at their native timings, as in SMS_MiSTer.
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

// numstick's one-hot runs bit0='1'..bit8='9', bit9='0'; reorder to key number.
wire [9:0] osk_keys = {osk_press[8:0], osk_press[9]};
wire [9:0] osk_a = (osk_mode == 2'd1) ? osk_keys : 10'd0;
wire [9:0] osk_b = (osk_mode == 2'd2) ? osk_keys : 10'd0;

// video_mixer gives analog outputs a scandoubler (15.7kHz native -> 31kHz when
// forced) and the OSD gamma control; video_freak provides aspect ratio and the
// integer scaling modes on top of the HDMI scaler.
wire       vga_de;
wire       freeze_sync;

// Resample the clk_sys-domain pixel stream (numstick overlay included) into
// the clk_vid domain. Plain registers: the clocks share a PLL, so this is an
// ordinary timed path, and sampling at 42 MHz then presenting on the 7.04 MHz
// enable repeats each source pixel 4x. LINE_LENGTH reserves the full 88-pixel
// raster width (352 samples); Borders Off uses 256 of that capacity.
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

// NES/SNES-style 216-line crop: at 1080p this permits an exact 5x vertical
// scale. Other output modes retain the native 242/292-line raster window.
wire       vcrop_en = status[21];
wire [3:0] vcopt    = status[25:22];
reg        en216p = 1'b0;
reg  [4:0] voff    = 5'd0;
always @(posedge CLK_VIDEO) begin
	en216p <= (HDMI_WIDTH == 12'd1920) && (HDMI_HEIGHT == 12'd1080) &&
	           !forced_scandoubler;
	voff <= (vcopt < 4'd6) ? {vcopt, 1'b0} : ({vcopt, 1'b0} - 5'd24);
end

// Present VSync one output pixel later so DE falling edge and VSync 
// rising edge are handled on separate enables.
reg vf_vs = 1'b0;
always @(posedge CLK_VIDEO) begin
	if (CE_PIXEL) vf_vs <= VGA_VS;
end

wire scale_active = |status[12:11];
wire [11:0] arx_val = (scale_active || ar == 2'd0) ? 12'd4 : {10'd0, ar - 1'd1};
wire [11:0] ary_val = (scale_active || ar == 2'd0) ? 12'd3  : 12'd0;

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

//reg  [26:0] act_cnt;
//always @(posedge clk_sys) act_cnt <= act_cnt + 1'd1; 
//assign LED_USER = act_cnt[26] ? act_cnt[25:18] > act_cnt[7:0] : act_cnt[25:18] <= act_cnt[7:0];
assign LED_USER = 1'b0;   // was undriven

endmodule
