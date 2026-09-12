//============================================================================
//
//  RCA Studio II core glue: CPU + CDP1861 + RAM + keypad.
//
//  Original implementation by Jason Coombes (JasonA-dev), 2022, with MiSTer
//  framework integration by Flandango. Extended 2026 by Alan Steremberg and
//  Elle Ball.
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

module rcastudioii
(
	input              clk_sys,
	input              reset,
	input              video_reset,
	input              cart_unload,
	
	input wire         ioctl_download,
	input wire  [15:0] ioctl_index,
	input wire         ioctl_wr,
	input       [24:0] ioctl_addr,
	input        [7:0] ioctl_dout,

	input       [10:0] ps2_key,
	input       [31:0] joystick_0,
	input       [31:0] joystick_1,
	input        [3:0] joy_override,   // OSD "Joystick" row: the profile to use when joy_manual
	input              joy_manual,     // OSD "Mapping": 0 = auto-detect, 1 = use joy_override
	output       [3:0] auto_profile,   // the detected profile, for the top level to show in the OSD
	input        [1:0] players,        // OSD: 0 = auto, 1 = one player, 2 = two players
	input        [2:0] beeper_tune,    // OSD tuning; 0 = original/reference
	input              ntsc_pal_pitch, // Studio III NTSC: use the PAL divide-by-four tone stage
	input        [9:0] osk_a,          // on-screen keypad presses for keypad A (bit = key)
	input        [9:0] osk_b,          // and for keypad B
	output reg         chip8_fw_loaded,
	input  reg         ce_pix,
	input              clear_key,
	//    0  Studio II
	//    1  Studio III PAL
	//    2  Studio III NTSC
	//    3  Visicom
	input        [1:0] machine,

	output reg         HBlank,
	output reg         HSync,
	output reg         VBlank,
	output reg         VSync,
	output reg         video_de,
	output reg         bitmap_de,
	output reg         bitmap_hblank,
	output reg         bitmap_vblank,
	output       [2:0] video,
	// Visicom 
	output       [1:0] vis_index,
	// CDP1864 BCKGND
	output reg         video_bg,
	output signed [15:0] audio
);

localparam [1:0] MACHINE_STUDIO2   = 2'd0;
localparam [1:0] MACHINE_S3_PAL    = 2'd1;
localparam [1:0] MACHINE_S3_NTSC   = 2'd2;
localparam [1:0] MACHINE_VISICOM   = 2'd3;

wire is_studio3      = (machine == MACHINE_S3_PAL) || (machine == MACHINE_S3_NTSC);
wire machine_mpt02   = (machine == MACHINE_S3_PAL);   // has the CDP1864
wire machine_visicom = (machine == MACHINE_VISICOM);
reg  chip8_loaded = 1'b0;
reg  chip8_write_seen = 1'b0;
reg  chip8_fw_start_seen = 1'b0;
reg  chip8_fw_os2 = 1'b1;
wire chip8_active = chip8_loaded && !machine_visicom;
wire chip8_os2_active = chip8_active && chip8_fw_os2;
wire chip8_marcel_active = chip8_active && !chip8_fw_os2;
wire preserve_sync_reset = reset && !video_reset;

wire [2:0] io_n;
wire       io_inp;
wire       io_out;
wire inp1 = io_inp && (io_n == 3'd1);
wire inp4 = io_inp && (io_n == 3'd4);
wire out1 = io_out && (io_n == 3'd1);
wire out2 = io_out && (io_n == 3'd2);
wire out4 = io_out && (io_n == 3'd4);

////////////////// KEYPAD //////////////////////////////////////////////////////////////////

// CPU selects key to scan with OUT 2
reg  [3:0] keylatch = 4'h0;
always @(posedge clk_sys) if(out2) keylatch <= cpu_dout[3:0];

wire       pressed = ps2_key[9];
wire [7:0] code    = ps2_key[7:0];
reg  [9:0] playerA = 10'h0;
reg  [9:0] playerB = 10'h0;
reg        chip8_active_d = 1'b0;
always @(posedge clk_sys) begin
	reg old_state;
	old_state <= ps2_key[10];
	chip8_active_d <= chip8_active;

	if(chip8_active_d != chip8_active) begin
		playerA <= 10'd0;
		playerB <= 10'd0;
	end
	else if(old_state != ps2_key[10]) begin
		case(code)
			// Keypad A / CHIP-8 digits
			'h16: playerA[1] <= pressed; // 1 → 1
			'h1E: playerA[2] <= pressed; // 2 → 2
			'h26: playerA[3] <= pressed; // 3 → 3
			'h15: playerA[4] <= pressed; // Q → 4
			'h1D: playerA[5] <= pressed; // W → 5
			'h24: playerA[6] <= pressed; // E → 6
			'h1C: playerA[7] <= pressed; // A → 7
			'h1B: playerA[8] <= pressed; // S → 8
			'h23: playerA[9] <= pressed; // D → 9
			'h22: playerA[0] <= pressed; // X → 0

			// CHIP-8 hex keys
			'h25: if(chip8_active) playerB[3] <= pressed; // 4 → C
			'h2D: if(chip8_active) playerB[4] <= pressed; // R → D
			'h2B: if(chip8_active) playerB[5] <= pressed; // F → E
			'h1A: if(chip8_active) playerB[1] <= pressed; // Z → A
			'h21: if(chip8_active) playerB[2] <= pressed; // C → B
			'h2A: if(chip8_active) playerB[6] <= pressed; // V → F

			// Keypad B
			'h3D: if(!chip8_active) playerB[1] <= pressed; // 7 → 1
			'h3E: if(!chip8_active) playerB[2] <= pressed; // 8 → 2
			'h46: if(!chip8_active) playerB[3] <= pressed; // 9 → 3
			'h3C: if(!chip8_active) playerB[4] <= pressed; // U → 4
			'h43: if(!chip8_active) playerB[5] <= pressed; // I → 5
			'h44: if(!chip8_active) playerB[6] <= pressed; // O → 6
			'h3B: if(!chip8_active) playerB[7] <= pressed; // J → 7
			'h42: if(!chip8_active) playerB[8] <= pressed; // K → 8
			'h4B: if(!chip8_active) playerB[9] <= pressed; // L → 9
			'h41: if(!chip8_active) playerB[0] <= pressed; // , → 0
		endcase
	end
end


////////////////// JOYSTICK -> KEYPAD ///////////////////////////////////////
`include "studio2_input_mapping.svh"

////////////////// CPU //////////////////////////////////////////////////////////////////

wire  [3:0] EF;
wire        key_valid = (keylatch < 4'd10);
wire  [9:0] padA = playerA | joyA_active | osk_a;
wire  [9:0] padB = playerB | joyB_active | osk_b;
assign EF = {key_valid & padB[keylatch], key_valid & padA[keylatch], 1'b1, EFx};

wire [7:0] cpu_din = 8'h00;
reg  [7:0] cpu_dout;
wire       Q;
wire       unsupported;
reg WAIT_N      = 1'b1;   // Clear=1, Wait=1 is Run.

// ---- CPU machine-cycle enable -------------------------------------------------------------
// CDP1861 is one pixel per CPU clock
// 1802 cycle is 8 clocks
reg  [2:0] cpu_div = 3'd0;
wire       cpu_ce  = ce_pix & (cpu_div == 3'd7);
// preserve HDMI sync hack
always @(posedge clk_sys) begin
	if (video_reset) cpu_div <= 3'd0;
	else if (ce_pix) cpu_div <= cpu_div + 3'd1;
end
reg dma_in_req  = 1'b0;
cdp1802 cdp1802 (
  .CLOCK        (clk_sys),
  .clk_enable   (cpu_ce),
  .CLEAR_N      (~reset),

  .Q            (Q),            // O beeper, active high
  .EF           (EF),           // I 3:0 external flags EF1 to EF4

  .WAIT_N       (WAIT_N),       // I
  .INT_N        (~INT),         // I
  .dma_in_req   (dma_in_req),   // I
  .dma_out_req  (DMAO),         // I  active-high DMA-OUT request
  .SC           (SC),           // O

  .io_din       (cpu_din),      // I
  .io_dout      (cpu_dout),     // O
  .io_n         (io_n),         // O 2:0 IO control lines: N2,N1,N0  (N0 used for display on/off)
  .io_inp       (io_inp),       // O IO input signal
  .io_out       (io_out),       // O IO output signal

  .unsupported  (unsupported),  // O

  .ram_rd       (ram_rd),       // O MRD_N
  .ram_wr       (ram_wr),       // O MWR_N
  .ram_a        (ram_a),        // O RAM address
  .ram_q        (ram_q),        // I DI
  .ram_d        (ram_d)         // O RAM write data

);

////////////////// MEMORY DECODE ////////////////////////////////////////////
//
//   $0000-$07FF  ROM      system ROM, plus the built-in games at $0400-$07FF
//                         (a cartridge takes that half over when plugged in)
//   $0800-$09FF  RAM      512 bytes: system/program memory, then display memory
//   $0A00-$0BFF  cart     multicart window
//   $0C00-$0DFF  RAM/ROM  the RAM mirror by default; a cartridge may page ROM
//                         over it (asteroids/berzerk/pacman/scramble .st2 do)
//   $0E00-$0FFF  cart     multicart window

wire         ram_rd; // MRD_N
wire         ram_wr; // MWR_N
wire  [7:0]  ram_d;  // CPU write data
wire [15:0]  ram_a;  // CPU address
wire  [7:0]  ram_q;  // data returned to the CPU (and to the 1861 during DMA)

// Cartridge data BRAMs
reg  [15:0] cart_page_s2      = 16'h0000;
reg  [15:0] cart_page_s3_pal  = 16'h0000;
reg  [15:0] cart_page_s3_ntsc = 16'h0000;
reg  [15:0] cart_page_vis     = 16'h0000;
wire [15:0] cart_page = (machine == MACHINE_STUDIO2) ? cart_page_s2
                      : (machine == MACHINE_S3_PAL)  ? cart_page_s3_pal
                      : (machine == MACHINE_S3_NTSC) ? cart_page_s3_ntsc
                      :                                cart_page_vis;

wire        bank0    = (ram_a[15:12] == 4'h0);
wire        rom_sel  = bank0 && !ram_a[11];
// Studio III puts a second ROM region at $0C00-$0FFF
wire        rom_hi   = (((is_studio3 && !chip8_os2_active) || chip8_marcel_active) &&
	                   bank0 && (ram_a[11:10] == 2'b11));                    // $0C00-$0FFF
// Colour RAM: 64 cells behind a one-page window at $0B00-$0BFF
wire        col_sel  = is_studio3 && bank0 && (ram_a[11:8] == 4'hB);
// Cartridge ownership is not part of firmware storage
wire        cart_sel = bank0 && cart_page[ram_a[11:8]] &&
	                   !col_sel && !chip8_active;

// ---- Toshiba Visicom COM-100 ----------------------------------------------
//
//   $0000-$07FF  ROM   2K image: BIOS, and the built-in games at $0400-$07FF
//   $0800-$0FFF  ROM   current cartridge; pages absent from its image are open bus
//   $1000-$11FF  RAM   512 bytes: scratch at $1000-$10FF, bit plane 0 at $1100
//   $1300-$13FF  RAM   256 bytes: bit plane 1
//   $1200-$12FF        nothing
//
wire        vis_ram  = machine_visicom && !bank0 && !ram_a[9];            // 512B, plane 0 in its top half
wire        vis_pl1  = machine_visicom && !bank0 && (ram_a[9:8] == 2'b11);// 256B, plane 1

// OpenStudio2 4 KiB RAM window at $1000-$1FFF
// Suppress 512-byte RAM mirrors while OS2 is active
wire        os2_ram_sel = chip8_os2_active && (ram_a[15:12] == 4'h1);
wire        ram_sel  = machine_visicom
                     ? (vis_ram || vis_pl1)
                     : (!os2_ram_sel && !rom_sel && !rom_hi && !col_sel &&
                        !cart_sel && !ram_a[9]);

wire        cpu_wr   = ram_wr && ram_sel && !vis_pl1;             // native/Visicom main RAM
wire        os2_cpu_wr = ram_wr && os2_ram_sel;                   // OpenStudio2 4 KiB CHIP-8 RAM
wire        pl1_wr   = ram_wr && vis_pl1;                         // Visicom's second plane
wire        col_wr   = ram_wr && col_sel;

// ---- CDP1864 colour RAM ---------------------------------------------------
reg  [2:0]  colour_ram [0:63];

reg         colour_on;
always @(posedge clk_sys) begin
	if (reset)       colour_on <= 1'b0;
	else if (col_wr) colour_on <= 1'b1;
end
always @(posedge clk_sys) if (col_wr) colour_ram[ram_a[5:0]] <= ram_d[2:0];
wire [5:0]  col_index = {ram_a[7:5], ram_a[2:0]};
wire [2:0]  colour_cell = colour_ram[col_index];
// convert RBG (1864 pin order) to RGB
wire [2:0]  colour_dot = {colour_cell[0], colour_cell[2], colour_cell[1]};

wire [7:0]  rom_q;
wire [7:0]  cart_q;
wire [7:0]  sram_q;
wire [7:0]  pl1_q;
wire [7:0]  os2_ram_q;
reg         rom_sel_q, cart_sel_q, ram_sel_q, pl1_sel_q, os2_ram_sel_q;
always @(posedge clk_sys) begin
	rom_sel_q     <= rom_sel | rom_hi;
	cart_sel_q    <= cart_sel;
	ram_sel_q     <= ram_sel;
	pl1_sel_q     <= vis_pl1;
	os2_ram_sel_q <= os2_ram_sel;
end
assign ram_q = os2_ram_sel_q ? os2_ram_q
             : pl1_sel_q        ? pl1_q
             : ram_sel_q        ? sram_q
             : cart_sel_q       ? cart_q
             : rom_sel_q        ? rom_q : 8'hFF;

////////////////// CARTRIDGE LOADER /////////////////////////////////////////

wire        boot_dl = ioctl_download && (ioctl_index[15:8] == 8'd0) &&
	             (ioctl_index[5:0] == 6'd0);
wire        fw_dl   = ioctl_download && (ioctl_index[5:0] == 6'd2);
wire        bios_dl = boot_dl | fw_dl;
wire        cart_dl = ioctl_download && (ioctl_index[5:0] == 6'd1);
wire        ch8_dl  = ioctl_download && (ioctl_index[15:8] == 8'd0) &&
	             (ioctl_index[5:0] == 6'd3);
wire        chip8_fw_auto_dl = ioctl_download && (ioctl_index[15:8] == 8'd1) &&
	                        (ioctl_index[5:0] == 6'd3);
wire        chip8_fw_manual_dl = ioctl_download && (ioctl_index[5:0] == 6'd4);
wire        chip8_fw_dl = chip8_fw_auto_dl | chip8_fw_manual_dl;

reg  [2:0]  st2_magic;                  // running match on "RCA"
reg         st2_mode;                   // "RCA2" seen: treat as paged
reg  [7:0]  st2_page [0:63];            // page table, header offsets 64..127

always @(posedge clk_sys) begin
	if (!ioctl_download) begin
		st2_magic <= 3'b000;
		st2_mode  <= 1'b0;
	end
	else if (cart_dl && ioctl_wr) begin
		case (ioctl_addr[15:0])
			16'd0: st2_magic[0] <=  (ioctl_dout == 8'h52);                    // 'R'
			16'd1: st2_magic[1] <=  (ioctl_dout == 8'h43) & st2_magic[0];     // 'C'
			16'd2: st2_magic[2] <=  (ioctl_dout == 8'h41) & st2_magic[1];     // 'A'
			16'd3: st2_mode     <=  (ioctl_dout == 8'h32) & st2_magic[2];     // '2'
			default: ;
		endcase
		if (ioctl_addr >= 16'd64 && ioctl_addr < 16'd128)
			st2_page[ioctl_addr[5:0]] <= ioctl_dout;
	end
end

// Byte at ioctl_addr belongs to block (addr>>8)-1
wire  [5:0] st2_blk   = ioctl_addr[13:8] - 6'd1;
wire  [7:0] st2_pg    = st2_page[st2_blk];

wire        st2_pg_ok = (st2_pg[7:4] == 4'h0) &&
	                    (machine_visicom ? st2_pg[3]
	                     : ((st2_pg[3:0] > 4'h3) &&
	                        (st2_pg[3:0] != 4'h8) && (st2_pg[3:0] != 4'h9) &&
	                        !(is_studio3 && (st2_pg[3:0] == 4'hB))));

wire        st2_data  = ioctl_addr >= 16'd256;          // past the header
wire [11:0] raw_base  = machine_visicom ? 12'h800 : 12'h400;
wire [11:0] cart_a    = st2_mode ? {st2_pg[3:0], ioctl_addr[7:0]}
                                 : (ioctl_addr[11:0] + raw_base);
wire        raw_ok    = !machine_visicom || (ioctl_addr < 25'h800);
wire        cart_we   = cart_dl && ioctl_wr && (st2_mode ? (st2_data && st2_pg_ok) : raw_ok);

// OS2 special handling
wire [11:0] marcel_ch8_a = (ioctl_addr < 25'h500)
	                      ? (12'h300 + ioctl_addr[11:0])
	                      : (12'hC00 + (ioctl_addr[11:0] - 12'h500));
wire        marcel_ch8_we = ch8_dl && ioctl_wr && chip8_fw_loaded &&
	                        !chip8_fw_os2 && !machine_visicom &&
	                        (ioctl_addr < 25'h900);

wire [11:0] os2_ch8_a = 12'h200 + ioctl_addr[11:0];
wire        os2_ch8_we = ch8_dl && ioctl_wr && chip8_fw_loaded &&
	                     chip8_fw_os2 && !machine_visicom &&
	                     (ioctl_addr < 25'hE00);
wire        ch8_we = marcel_ch8_we | os2_ch8_we;

wire [3:0]  cart_pg = cart_a[11:8];
wire        cart_claim = machine_visicom
                       ? cart_pg[3]
                       : ((cart_pg >= 4'h4) &&
                          (cart_pg != 4'h8) && (cart_pg != 4'h9) &&
                          !(is_studio3 && (cart_pg == 4'hB)));
wire        raw_known  = (ioctl_addr > 25'd3) ||
	                     ((ioctl_addr == 25'd3) && !((ioctl_dout == 8'h32) && st2_magic[2]));
wire        cart_page_we = cart_we && cart_claim && (st2_mode || raw_known);

always @(posedge clk_sys) begin
	if (cart_dl && ioctl_wr && (ioctl_addr == 0)) begin
		case (machine)
			MACHINE_STUDIO2: cart_page_s2      <= 16'h0000;
			MACHINE_S3_PAL:  cart_page_s3_pal  <= 16'h0000;
			MACHINE_S3_NTSC: cart_page_s3_ntsc <= 16'h0000;
			MACHINE_VISICOM: cart_page_vis     <= 16'h0000;
		endcase
	end

	if (cart_page_we) begin
		case (machine)
			MACHINE_STUDIO2: cart_page_s2[cart_pg]      <= 1'b1;
			MACHINE_S3_PAL:  cart_page_s3_pal[cart_pg]  <= 1'b1;
			MACHINE_S3_NTSC: cart_page_s3_ntsc[cart_pg] <= 1'b1;
			MACHINE_VISICOM: cart_page_vis[cart_pg]     <= 1'b1;
		endcase
	end

	if (cart_unload) begin
		case (machine)
			MACHINE_STUDIO2: cart_page_s2      <= 16'h0000;
			MACHINE_S3_PAL:  cart_page_s3_pal  <= 16'h0000;
			MACHINE_S3_NTSC: cart_page_s3_ntsc <= 16'h0000;
			MACHINE_VISICOM: cart_page_vis     <= 16'h0000;
		endcase
	end
end

// --------------- firmware, BRAMs, CHIP-8  ---------------

wire [1:0]  bios_slot = fw_dl ? machine : ioctl_index[7:6];
wire [11:0] chip8_rom_dl_a = (ch8_dl && !chip8_fw_os2)
                           ? marcel_ch8_a : ioctl_addr[11:0];

// BIOS write: only the matching firmware BRAM
wire        bios_we0 = bios_dl && ioctl_wr && (bios_slot == 2'd0);
wire        bios_we1 = bios_dl && ioctl_wr && (bios_slot == 2'd1);
wire        bios_we2 = bios_dl && ioctl_wr && (bios_slot == 2'd2);
wire        bios_we3 = bios_dl && ioctl_wr && (bios_slot == 2'd3);
wire        bios_we4 = chip8_fw_dl && ioctl_wr && (ioctl_addr < 25'h800);

// Cart write: only into the cartridge BRAM that belongs to the active machine
wire        cart_we0 = cart_we && (machine == 2'd0);
wire        cart_we1 = cart_we && (machine == 2'd1);
wire        cart_we2 = cart_we && (machine == 2'd2);
wire        cart_we3 = cart_we && (machine == 2'd3);

wire        we4 = bios_we4 | marcel_ch8_we;

wire [7:0]  rom0_q, rom1_q, rom2_q, rom3_q, rom4_q;
wire [7:0]  cart0_q, cart1_q, cart2_q, cart3_q;

// hardcoded to marcel/os2
initial chip8_fw_loaded = 1'b1;
always @(posedge clk_sys) begin
	if (!ioctl_download) chip8_fw_start_seen <= 1'b0;
	else if (bios_we4 && (ioctl_addr == 25'd0)) chip8_fw_start_seen <= 1'b1;

	if (chip8_fw_dl && !dl_d) begin
		chip8_fw_loaded <= 1'b0;
		chip8_fw_os2    <= 1'b0;
	end
	else begin
		if (bios_we4 && chip8_fw_start_seen && (ioctl_addr == 25'h2FF))
			chip8_fw_loaded <= 1'b1;
		if (bios_we4 && chip8_fw_start_seen && (ioctl_addr == 25'h7FF)) begin
			chip8_fw_loaded <= 1'b1;
			chip8_fw_os2    <= 1'b1;
		end
	end

	if (!ioctl_download) chip8_write_seen <= 1'b0;
	else if (ch8_we)     chip8_write_seen <= 1'b1;

	// keep chip8_fw_loaded
	if (cart_unload) chip8_loaded <= 1'b0;
	else if ((cart_dl || fw_dl || chip8_fw_dl) && !dl_d) chip8_loaded <= 1'b0;
	else if (dl_done && chip8_write_seen) chip8_loaded <= 1'b1;
end

dpram #(8, 12) rom0
(
	.clock(clk_sys),
	.ram_cs(1'b1),
	.address_a(bios_dl ? ioctl_addr[11:0] : ram_a[11:0]),
	.wren_a(bios_we0),
	.data_a(ioctl_dout),
	.q_a(rom0_q),
	.ram_cs_b(1'b0),
	.wren_b(1'b0),
	.address_b(12'd0),
	.data_b(),
	.q_b()
);

dpram #(8, 12) rom1
(
	.clock(clk_sys),
	.ram_cs(1'b1),
	.address_a(bios_dl ? ioctl_addr[11:0] : ram_a[11:0]),
	.wren_a(bios_we1),
	.data_a(ioctl_dout),
	.q_a(rom1_q),
	.ram_cs_b(1'b0),
	.wren_b(1'b0),
	.address_b(12'd0),
	.data_b(),
	.q_b()
);

dpram #(8, 12) rom2
(
	.clock(clk_sys),
	.ram_cs(1'b1),
	.address_a(bios_dl ? ioctl_addr[11:0] : ram_a[11:0]),
	.wren_a(bios_we2),
	.data_a(ioctl_dout),
	.q_a(rom2_q),
	.ram_cs_b(1'b0),
	.wren_b(1'b0),
	.address_b(12'd0),
	.data_b(),
	.q_b()
);

dpram #(8, 12) rom3
(
	.clock(clk_sys),
	.ram_cs(1'b1),
	.address_a(bios_dl ? ioctl_addr[11:0] : ram_a[11:0]),
	.wren_a(bios_we3),
	.data_a(ioctl_dout),
	.q_a(rom3_q),
	.ram_cs_b(1'b0),
	.wren_b(1'b0),
	.address_b(12'd0),
	.data_b(),
	.q_b()
);

`ifndef OS2_INIT_FILE
`define OS2_INIT_FILE "rom/openstudio2.hex"
`endif
dpram #(8, 12, `OS2_INIT_FILE) rom4
(
	.clock(clk_sys),
	.ram_cs(1'b1),
	.address_a((ch8_dl || chip8_fw_dl) ? chip8_rom_dl_a : ram_a[11:0]),
	.wren_a(we4),
	.data_a(ioctl_dout),
	.q_a(rom4_q),
	.ram_cs_b(1'b0),
	.wren_b(1'b0),
	.address_b(12'd0),
	.data_b(),
	.q_b()
);

// BRAMs
wire [11:0] os2_ram_addr = (ch8_dl && chip8_fw_os2) ? os2_ch8_a : ram_a[11:0];
wire  [7:0] os2_ram_data = os2_ch8_we ? ioctl_dout : ram_d;
wire        os2_ram_we   = os2_ch8_we | os2_cpu_wr;

dpram #(8, 12) chip8_ram
(
	.clock(clk_sys),
	.ram_cs(1'b1),
	.address_a(os2_ram_addr),
	.wren_a(os2_ram_we),
	.data_a(os2_ram_data),
	.q_a(os2_ram_q),
	.ram_cs_b(1'b0),
	.wren_b(1'b0),
	.address_b(12'd0),
	.data_b(),
	.q_b()
);

dpram #(8, 12) cart0
(
	.clock(clk_sys),
	.ram_cs(1'b1),
	.address_a(cart_dl ? cart_a : ram_a[11:0]),
	.wren_a(cart_we0),
	.data_a(ioctl_dout),
	.q_a(cart0_q),
	.ram_cs_b(1'b0),
	.wren_b(1'b0),
	.address_b(12'd0),
	.data_b(),
	.q_b()
);

dpram #(8, 12) cart1
(
	.clock(clk_sys),
	.ram_cs(1'b1),
	.address_a(cart_dl ? cart_a : ram_a[11:0]),
	.wren_a(cart_we1),
	.data_a(ioctl_dout),
	.q_a(cart1_q),
	.ram_cs_b(1'b0),
	.wren_b(1'b0),
	.address_b(12'd0),
	.data_b(),
	.q_b()
);

dpram #(8, 12) cart2
(
	.clock(clk_sys),
	.ram_cs(1'b1),
	.address_a(cart_dl ? cart_a : ram_a[11:0]),
	.wren_a(cart_we2),
	.data_a(ioctl_dout),
	.q_a(cart2_q),
	.ram_cs_b(1'b0),
	.wren_b(1'b0),
	.address_b(12'd0),
	.data_b(),
	.q_b()
);

dpram #(8, 12) cart3
(
	.clock(clk_sys),
	.ram_cs(1'b1),
	.address_a(cart_dl ? cart_a : ram_a[11:0]),
	.wren_a(cart_we3),
	.data_a(ioctl_dout),
	.q_a(cart3_q),
	.ram_cs_b(1'b0),
	.wren_b(1'b0),
	.address_b(12'd0),
	.data_b(),
	.q_b()
);

assign rom_q = chip8_active ? rom4_q :
	           (machine == 2'd0) ? rom0_q :
	           (machine == 2'd1) ? rom1_q :
	           (machine == 2'd2) ? rom2_q : rom3_q;

assign cart_q = (machine == 2'd0) ? cart0_q :
	            (machine == 2'd1) ? cart1_q :
	            (machine == 2'd2) ? cart2_q : cart3_q;

// CLEAR wipes display RAM without resetting the Pixie
reg [8:0] clear_addr_b = 9'd0;
reg       clear_active = 1'b0;

always @(posedge clk_sys) begin
    if (clear_key && !clear_active) begin
        clear_active <= 1'b1;
        clear_addr_b <= 9'd256; // VRAM starts at offset 256 in the 512-byte RAM
    end
    else if (clear_active) begin
        if (clear_addr_b == 9'd511) clear_active <= 1'b0;
        else                        clear_addr_b <= clear_addr_b + 1'b1;
    end
end

wire [8:0] sram_a_addr = clear_active ? clear_addr_b : ram_a[8:0];
wire [7:0] sram_a_data = clear_active ? 8'd0         : ram_d;
wire       sram_a_we   = clear_active ? 1'b1         : cpu_wr;

dpram #(8, 9) sram
(
	.clock(clk_sys),
	.ram_cs(1'b1),
	.address_a(sram_a_addr),
	.wren_a(sram_a_we),
	.data_a(sram_a_data),
	.q_a(sram_q),

	.ram_cs_b(1'b0),
	.wren_b(1'b0),
	.address_b(9'd0),
	.data_b(),
	.q_b()
);

dpram #(8, 8) sram2
(
	.clock(clk_sys),
	.ram_cs(1'b1),
	.address_a(ram_a[7:0]),
	.wren_a(pl1_wr),
	.data_a(ram_d),
	.q_a(pl1_q),

	.ram_cs_b(1'b0),
	.wren_b(1'b0),
	.address_b(8'd0),
	.data_b(),
	.q_b()
);

////////////////// VIDEO //////////////////////////////////////////////////////////////////

wire [1:0]  SC;

wire        INT;
wire        DMAO;
wire        EFx;


pixie_video pixie_video (
    // front end, CDP1802 bus clock domain
    .clk        (clk_sys),    // I
    .reset      (video_reset),             // I: soft resets keep raster timing alive

    .clk_enable (ce_pix),     // I
    .cpu_ce     (cpu_ce),     // I  CPU machine-cycle enable, for sampling DMA bytes

    .SC         (SC),         // I [1:0]
    .disp_on    (machine_visicom ? out1 : inp1),  // I
    .disp_off   (((machine == MACHINE_STUDIO2) && out1) || preserve_sync_reset),


    .data_in    (ram_q),      // I [7:0]  byte the CPU delivers during a DMA-OUT cycle
    .vis_mode   (machine_visicom),  // I
    .data_in2   (pl1_q),      // I [7:0]  Visicom plane 1: the byte $200 higher
    .colour_in  (colour_dot), // I  CDP1862 colour for that byte (NTSC Studio III)
    .con        (colour_on),  // I
    .bg_step    (out1 && !machine_visicom),  // I  OUT 1 steps the background

    .DMAO       (DMAO_61),    // O
    .INT        (INT_61),     // O
    .EFx        (EFx_61),     // O

    // back end, video clock domain
    .video_clk  (clk_sys),    // I
    .csync      (),           // O
    .video      (video_dot),  // O  one bit: the 1861 is a monochrome part
    .colour_out    (col61_dot),
    .vis_index     (vis_index),
    .bg_active     (col61_bg),
    .bg_colour_out (col61_bgc),

    .VSync      (VSync_61),   // O
    .HSync      (HSync_61),   // O
    .VBlank     (VBlank_61),  // O
    .HBlank     (HBlank_61),  // O
    .video_de   (de_61),      // O
    .bitmap_de  (bde_61),     // O
    .bitmap_hblank(bhb_61),
    .bitmap_vblank(bvb_61)
);

// ---- CDP1864 ---------------------------------
wire       DMAO_64, INT_64, EFx_64;
wire       VSync_64, HSync_64, VBlank_64, HBlank_64, de_64, bde_64, bg_64;
wire       bhb_64, bvb_64;
wire [2:0] video_64;

cdp1864 cdp1864
(
    .clk        (clk_sys),
    .ce_pix     (ce_pix),
    .cpu_ce     (cpu_ce),
    .reset      (video_reset),

    .SC         (SC),
    .data_in    (ram_q),
    .colour_in  (colour_dot),
    .con        (colour_on),
    .disp_on    (inp1),
    .disp_off   (inp4 || preserve_sync_reset),
    .bg_step    (out1),

    .DMAO       (DMAO_64),
    .INT        (INT_64),
    .EFx        (EFx_64),

    .csync      (),
    .video      (video_64),
    .bckgnd     (bg_64),
    .VSync      (VSync_64),
    .HSync      (HSync_64),
    .VBlank     (VBlank_64),
    .HBlank     (HBlank_64),
    .video_de   (de_64),
    .bitmap_de  (bde_64),
    .bitmap_hblank(bhb_64),
    .bitmap_vblank(bvb_64)
);

// ---- tone generator -------------------------------------------------------
// PAL is div/4
wire aud_tone;
cdp1863 cdp1863
(
    .clk     (clk_sys),
    .cpu_ce  (cpu_ce),
    .reset   (video_reset | (preserve_sync_reset & ~clear_key)),
    .div4    ((machine == MACHINE_S3_PAL) ||
              ((machine == MACHINE_S3_NTSC) && ntsc_pal_pitch)),
    .tone_we (out4),
    .tone_d  (cpu_dout),
    .aoe     (Q),
    .aud     (aud_tone)
);

// ---- select ---------------------------------------------------------------
wire       video_dot;
wire       DMAO_61, INT_61, EFx_61;
wire       VSync_61, HSync_61, VBlank_61, HBlank_61, de_61, bde_61;
wire       bhb_61, bvb_61;
wire [2:0] col61_dot, col61_bgc;
wire       col61_bg;
wire [2:0] video_61;
wire       bg_61;

cdp1862 cdp1862
(
    .enable     (machine == MACHINE_S3_NTSC),
    .luminance  (video_dot),
    .in_raster  (de_61),
    .dot_colour (col61_dot),
    .bg_active  (col61_bg),
    .bg_colour  (col61_bgc),
    .video      (video_61),
    .bckgnd     (bg_61)
);

reg  [2:0] vis_approx;
always @(*) begin
	case (vis_index)
		2'd0:    vis_approx = 3'b010;   // background: dark green
		2'd1:    vis_approx = 3'b011;   // cyan
		2'd2:    vis_approx = 3'b110;   // yellow
		default: vis_approx = 3'b100;   // red
	endcase
end

assign video    = machine_visicom ? vis_approx : (machine_mpt02 ? video_64 : video_61);
assign DMAO     = machine_mpt02 ? DMAO_64  : DMAO_61;
assign INT      = machine_mpt02 ? INT_64   : INT_61;
assign EFx      = machine_mpt02 ? EFx_64   : EFx_61;

always @(*) begin
	VSync    = machine_mpt02 ? VSync_64  : VSync_61;
	HSync    = machine_mpt02 ? HSync_64  : HSync_61;
	VBlank   = machine_mpt02 ? VBlank_64 : VBlank_61;
	HBlank   = machine_mpt02 ? HBlank_64 : HBlank_61;
	video_de = machine_mpt02 ? de_64     : de_61;
	bitmap_de = machine_mpt02 ? bde_64   : bde_61;
	bitmap_hblank = machine_mpt02 ? bhb_64 : bhb_61;
	bitmap_vblank = machine_mpt02 ? bvb_64 : bvb_61;
	video_bg  = machine_mpt02 ? bg_64    : bg_61;
end

////////////////// SOUND ////////////////////////////////////////////////////
`include "studio2_beeper_inline.svh"

endmodule
