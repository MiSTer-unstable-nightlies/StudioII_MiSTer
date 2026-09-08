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
	input              clear_key,      // literal CLEAR input; also owns the VRAM-clear behavior below
	//  Which machine, from the OSD:
	//    0  Studio II          CDP1861, NTSC, monochrome
	//    1  Studio III PAL     CDP1864 -- video, colour and tone in one part
	//    2  Studio III NTSC    CDP1861 + CDP1862 colour + CDP1863 tone
	//    3  Visicom		    CDP1861, NTSC, colour from second RAM plane
	input        [1:0] machine,

	output reg         HBlank,
	output reg         HSync,
	output reg         VBlank,
	output reg         VSync,
	output reg         video_de,
	// DE for the bitmap alone, as distinct from video_de (the whole raster). The
	// simulation harness captures this so its frames stay 64x128 / 64x192 and the
	// recorded scores keep their meaning. Separate bitmap blanking lets the FPGA
	// top hide borders without changing the device raster or sync.
	output reg         bitmap_de,
	output reg         bitmap_hblank,
	output reg         bitmap_vblank,
	// {R,G,B}, one bit per channel -- this mirrors the hardware rather than
	// inventing a format. The CDP1864 in the successor machines has exactly one
	// RDATA, GDATA and BDATA pin, fed from colour RAM. The CDP1861
	// here is a mono part, so the Studio II drives all three together and the
	// picture is unchanged.
	output       [2:0] video,
	// Visicom only: which of its four colours this pixel is. The palette is
	// four fixed RGB values that a 1-bit-per-channel bus cannot carry, so the
	// top level applies it; `video` above still gets a 3-bit approximation for
	// anything that only has three wires (the simulation harness).
	output       [1:0] vis_index,
	// BCKGND from the CDP1864: this pixel's colour came from the background
	// select rather than a lit bit, so it should be shown at lower luminance.
	// Always low on the monochrome Studio II, which has no background colour.
	output reg         video_bg,
	output signed [15:0] audio
);

//  Derived from `machine`. Most of the machine-dependent behaviour keys off
//  "is this a Studio III" (the memory map, colour RAM, the tone generator)
//  rather than off which video part it has, which is only the PAL one.
localparam [1:0] MACHINE_STUDIO2   = 2'd0;
localparam [1:0] MACHINE_S3_PAL    = 2'd1;
localparam [1:0] MACHINE_S3_NTSC   = 2'd2;
localparam [1:0] MACHINE_VISICOM   = 2'd3;

// The Visicom is NOT a Studio III despite Robson's visicom.txt calling it a
// "clone of the Studio 3". It has a plain CDP1861 and no colour RAM at all: its
// colour comes from a second bit plane in main RAM, so none of the Studio III
// memory map, colour RAM or tone generator applies to it. Keeping is_studio3 as
// "not a Studio II" would have handed it all three.
wire is_studio3      = (machine == MACHINE_S3_PAL) || (machine == MACHINE_S3_NTSC);
wire machine_mpt02   = (machine == MACHINE_S3_PAL);   // has the CDP1864
wire machine_visicom = (machine == MACHINE_VISICOM);
reg  chip8_loaded = 1'b0;
reg  chip8_write_seen = 1'b0;
reg  chip8_fw_start_seen = 1'b0;
wire chip8_active = chip8_loaded && !machine_visicom;
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

//The CPU selects the key to scan with OUT 2, latched into a CD4515.
reg  [3:0] keylatch = 4'h0;
always @(posedge clk_sys) if(out2) keylatch <= cpu_dout[3:0];

wire       pressed = ps2_key[9];
wire [7:0] code    = ps2_key[7:0];
always @(posedge clk_sys) begin
	reg old_state;
	old_state <= ps2_key[10];

	if(old_state != ps2_key[10]) begin
		case(code)
			// Keypad A
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
		
			// Keypad B
			'h3D: playerB[1] <= pressed; // 7 → 1
			'h3E: playerB[2] <= pressed; // 8 → 2
			'h46: playerB[3] <= pressed; // 9 → 3
			'h3C: playerB[4] <= pressed; // U → 4
			'h43: playerB[5] <= pressed; // I → 5
			'h44: playerB[6] <= pressed; // O → 6
			'h3B: playerB[7] <= pressed; // J → 7
			'h42: playerB[8] <= pressed; // K → 8
			'h4B: playerB[9] <= pressed; // L → 9
			'h41: playerB[0] <= pressed; // , → 0
		endcase
	end
end
reg  [9:0] playerA = 10'h0;
reg  [9:0] playerB = 10'h0;


////////////////// JOYSTICK -> KEYPAD ///////////////////////////////////////
`include "studio2_input_mapping.svh"
////////////////// CPU //////////////////////////////////////////////////////////////////

// EF4=B, EF3=A, EF2=unused (high), EF1=1861 display status.
// The CD4515 outputs 10-15 have no keypad connection.
wire  [3:0] EF;
wire        key_valid = (keylatch < 4'd10);
wire  [9:0] padA = playerA | joyA_active | osk_a;
wire  [9:0] padB = playerB | joyB_active | osk_b;
assign EF = {key_valid & padB[keylatch], key_valid & padA[keylatch], 1'b1, EFx};

// The Studio II has no input port that returns data -- the keypads are read through EF3/EF4,
// and INP 1 only toggles the display, discarding the byte. 
wire [7:0] cpu_din = 8'h00;
reg  [7:0] cpu_dout;
wire       Q;
wire       unsupported;
reg WAIT_N      = 1'b1;   // Clear=1, Wait=1 is Run.

// ---- CPU machine-cycle enable -------------------------------------------------------------
// The CDP1861 shifts one pixel per CPU clock and a 1802 machine cycle is 8 clocks, so the CPU
// advances one state every 8 pixel times. Deriving this from ce_pix rather than counting clk_sys
// keeps it correct whatever clk_sys is running at. 112 pixels x 262 lines / 8 = 3668 machine
// cycles per frame, which is what a real Studio II gets.
reg  [2:0] cpu_div = 3'd0;
wire       cpu_ce  = ce_pix & (cpu_div == 3'd7);
// Keep cpu_div counting through sync-preserving resets so the CPU's machine-cycle grid stays locked
// to the raster phase. Only a hard video reset restarts the divider.
always @(posedge clk_sys) begin
	if (video_reset) cpu_div <= 3'd0;
	else if (ce_pix) cpu_div <= cpu_div + 3'd1;
end
reg dma_in_req  = 1'b0;
cdp1802 cdp1802 (
  .CLOCK        (clk_sys),
  .clk_enable   (cpu_ce),
  .CLEAR_N      (~reset),

  .Q            (Q),            // O external pin Q Turns the sound off and on. When logic '1', the beeper is on.
  .EF           (EF),           // I 3:0 external flags EF1 to EF4

  .WAIT_N       (WAIT_N),       // I
  .INT_N        (~INT),         // I
  .dma_in_req   (dma_in_req),   // I
  .dma_out_req  (DMAO),         // I  TODO: check
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
  .ram_d        (ram_d)        // O RAM write data

);

////////////////// MEMORY DECODE ////////////////////////////////////////////
//
// docs/memorymap.txt:
//
//   $0000-$07FF  ROM      system ROM, plus the built-in games at $0400-$07FF
//                         (a cartridge takes that half over when plugged in)
//   $0800-$09FF  RAM      512 bytes: system/program memory, then display memory
//   $0A00-$0BFF  cart     multicart window
//   $0C00-$0DFF  RAM/ROM  the RAM mirror by default; a cartridge may page ROM
//                         over it (asteroids/berzerk/pacman/scramble .st2 do)
//   $0E00-$0FFF  cart     multicart window
//
// The rule behind that table is one line: RAM answers wherever A9 = 0 and
// nothing else is decoded, which is why it also reappears at $0C00, $1000,
// $1400, $1800 and so on. A9 = 1 with no cartridge is open bus.

wire         ram_rd; // MRD_N
wire         ram_wr; // MWR_N
wire  [7:0]  ram_d;  // CPU write data
wire [15:0]  ram_a;  // CPU address
wire  [7:0]  ram_q;  // data returned to the CPU (and to the 1861 during DMA)

// Which of pages $00-$0F each machine's loaded cartridge actually supplies.
// Cartridge data lives in four independent machine BRAMs, separate from
// firmware. Page ownership therefore controls the overlay explicitly: a cart
// may replace the normal $0400-$07FF firmware window, plus the cartridge
// windows described below. CLEAR/reset does not unplug any resident cart.
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
// Studio III puts a second ROM region at $0C00-$0FFF -- MAME's mpt02_map has
// .rom() there as well as at $0000-$07FF, and the BIOS is a 4K image covering
// both. Marcel's interpreter needs the same window on Studio II while CHIP-8 is
// active. It takes precedence over the normal $0C00-$0DFF RAM mirror.
wire        rom_hi   = (is_studio3 || chip8_active) && bank0 &&
	                   (ram_a[11:10] == 2'b11);                              // $0C00-$0FFF
// Colour RAM: 64 cells behind a one-page window at $0B00-$0BFF. Only six address
// lines are decoded, which is why MAME names the storage ($0B00-$0B3F) and Emma 02
// the window ($0B00-$0BFF) without disagreeing. See AGENTS.md for the unified-model rule.
wire        col_sel  = is_studio3 && bank0 && (ram_a[11:8] == 4'hB);
// Cartridge ownership is an overlay, not part of firmware storage. CHIP-8
// deliberately wins over any native cartridge. Colour RAM also remains fixed
// hardware on Studio III. Valid loaders never claim Studio RAM pages $08/$09.
wire        cart_sel = bank0 && cart_page[ram_a[11:8]] &&
	                   !col_sel && !chip8_active;

// ---- Toshiba Visicom COM-100 ----------------------------------------------
// A different map from either Studio, and the only one here that puts RAM above
// $0FFF. From Emma 02's Visicom/standard.xml:
//
//   $0000-$07FF  ROM   2K image: BIOS, and the built-in games at $0400-$07FF
//   $0800-$0FFF  ROM   current cartridge; pages absent from its image are open bus
//   $1000-$11FF  RAM   512 bytes: scratch at $1000-$10FF, bit plane 0 at $1100
//   $1300-$13FF  RAM   256 bytes: bit plane 1
//   $1200-$12FF        nothing
//
// Both RAM windows repeat every $400 all the way to $FFFF -- Emma spells the
// mirrors out one by one in <map>, which is the same statement as decoding
// A9-A0 within each 1K page and ignoring everything above.
wire        vis_ram  = machine_visicom && !bank0 && !ram_a[9];            // 512B, plane 0 in its top half
wire        vis_pl1  = machine_visicom && !bank0 && (ram_a[9:8] == 2'b11);// 256B, plane 1

wire        ram_sel  = machine_visicom
                     ? (vis_ram || vis_pl1)
                     : (!rom_sel && !rom_hi && !col_sel && !cart_sel && !ram_a[9]);

// Plane 1 is its own 256-byte array rather than a second window into the main
// RAM, and it is addressed by A7-A0 in both of its roles: the video reads it
// during a DMA cycle, when the address bus holds R(0) = $11xx, and the CPU
// reads or writes it at $13xx. Same low byte either way, so one single-port
// array serves both and there is never a conflict -- the CPU is not driving the
// bus during a DMA cycle.
wire        cpu_wr   = ram_wr && ram_sel && !vis_pl1;             // RAM is the only writeable thing
wire        pl1_wr   = ram_wr && vis_pl1;                        // ...and the Visicom's second plane
wire        col_wr   = ram_wr && col_sel;

// ---- CDP1864 colour RAM ---------------------------------------------------
// 64 x 3 bits, so a plain register array rather than block RAM. The cell for a
// display byte is {off[7:5], off[2:0]}: the low three bits are the column (8
// bytes across a 64-pixel row) and off[7:5] the row group, so one cell covers 8
// pixels across by 4 logical rows down. Indexing is MAME's, from
// mpt02_state::dma_w(), whose offset is the DMA address (cosmac_device passes
// R[0]). Reads are combinational and off the *current* address, because the
// 1864 latches colour "concurrent with the latching of the luminance
// information" -- the byte and its colour arrive together.
reg  [2:0]  colour_ram [0:63];
// CON, "Color On". The datasheet has this pin "connected to the gated MWR signal
// of the color memory", so colour switches on with the first write to colour RAM
// and the part is monochrome until then.
reg         colour_on;
always @(posedge clk_sys) begin
	if (reset)       colour_on <= 1'b0;
	else if (col_wr) colour_on <= 1'b1;
end
always @(posedge clk_sys) if (col_wr) colour_ram[ram_a[5:0]] <= ram_d[2:0];
wire [5:0]  col_index = {ram_a[7:5], ram_a[2:0]};
wire [2:0]  colour_cell = colour_ram[col_index];
// Colour RAM bit order is the 1864's pin order, which is NOT {R,G,B}: MAME's
// mpt02_state has rdata_r() = BIT(m_color,0), bdata_r() = BIT(m_color,1) and
// gdata_r() = BIT(m_color,2), i.e. bit0 red, bit1 blue, bit2 green. Permute into
// the {R,G,B} the video bus carries.
wire [2:0]  colour_dot = {colour_cell[0], colour_cell[2], colour_cell[1]};

// Both arrays have one cycle of latency, so the read mux select has to be
// delayed with the data. The CPU holds an address for a whole machine cycle
// (32 clk_sys), so a registered select is settled long before it is sampled.
wire [7:0]  rom_q;
wire [7:0]  cart_q;
wire [7:0]  sram_q;
wire [7:0]  pl1_q;
reg         rom_sel_q, cart_sel_q, ram_sel_q, pl1_sel_q;
always @(posedge clk_sys) begin
	rom_sel_q  <= rom_sel | rom_hi;
	cart_sel_q <= cart_sel;
	ram_sel_q  <= ram_sel;
	pl1_sel_q  <= vis_pl1;
end
// Open bus reads back as $FF, matching MAME's unmap_value_high and the likely
// floating-bus behaviour of the real machine (nothing drives the lines, and
// the last DMA-driven byte was usually high). Cartridge data has priority over
// firmware wherever the active machine's page mask says a cartridge is present.
assign ram_q = pl1_sel_q  ? pl1_q
             : ram_sel_q  ? sram_q
             : cart_sel_q ? cart_q
             : rom_sel_q  ? rom_q : 8'hFF;

////////////////// CARTRIDGE LOADER /////////////////////////////////////////
//
// Raw .bin/.rom images are a flat copy to $0400 on Studio machines and $0800 on
// the Visicom. .st2 images are paged: a 256-byte header followed by 256-byte
// blocks, each block's target page taken from the table at header offsets 64-127
// (docs/cartridge.txt).
//
// The format is detected purely from the "RCA2" magic in the first four bytes.
// The OSD extension index above ioctl_index[5:0] is deliberately not used.

// Index 0 is bootN.rom autoload (slot in ioctl_index[7:6]); index 2 is the
// OSD "Load Firmware" entry, whose upper bits carry the picked file's extension
// index instead of a slot, so it routes to the selected machine's slot below.
// F3's main .ch8 file uses index $0003. Its configured chip8.bin companion is
// sent first at supplemental index $0103. The separate F4 OSD row sends a
// manually selected interpreter at index $0004. Both fill the independent
// fifth slot without activating it.
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

// Byte at ioctl_addr belongs to block (addr>>8)-1; its page comes from the table.
wire  [5:0] st2_blk   = ioctl_addr[13:8] - 6'd1;
wire  [7:0] st2_pg    = st2_page[st2_blk];

// On a Studio, a page is loadable if it is cartridge space inside the 4k bank
// we model: not system ROM ($00-$03), not RAM ($08-$09), and below $10.
// $0C/$0D ARE legal --
// race.st2 pages ROM over the default RAM mirror there, which is why the memory
// map calls $C00-$DFF "RAM/ROM". $00 is also the format's "unused block" marker.
// Page $0B is the CDP1864's colour RAM, not cartridge space, so a cartridge must
// not be able to page ROM over it on that machine. (On the Studio II $0B is an
// ordinary cartridge window and stays loadable, which is why this is gated.)
// On the Visicom RAM is not in this bank at all -- it sits at $1000 and above --
// so its cartridge owns $08-$0F while resident firmware and games remain in
// $00-$07. Every one of Emma 02's six Visicom cartridges pages exactly $08-$0F.
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

// Marcel van Tongeren's interpreter translates the two discontiguous Studio
// ROM windows into CHIP-8 program space $0200-$0AFF. Ordinary .ch8 files begin
// at virtual $0200, so file bytes $000-$4FF land at physical $0300-$07FF and
// $500-$8FF land at $0C00-$0FFF. Larger programs are outside its model.
wire [11:0] ch8_a = (ioctl_addr < 25'h500)
	               ? (12'h300 + ioctl_addr[11:0])
	               : (12'hC00 + (ioctl_addr[11:0] - 12'h500));
wire        ch8_we = ch8_dl && ioctl_wr && chip8_fw_loaded &&
	                 !machine_visicom && (ioctl_addr < 25'h900);

// Studio cartridges may claim $04-$07 and $0A-$0F; $08/$09 are RAM, and $0B
// remains colour RAM on Studio III. Visicom cartridges use $08-$0F. Do not
// count the first three undecided magic bytes as raw data: at byte 3 the format
// is known, and a real ST2 header must not make a low page look supplied by its
// "RCA2" signature.
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

// ---- Native firmware, cartridge BRAMs, and CHIP-8 interpreter ---------------
//
// MiSTer auto-loads boot0.rom through boot3.rom with ioctl_index[5:0]==0 and
// the slot in ioctl_index[7:6]. Each native firmware BRAM only accepts writes
// for its own slot. Each machine also owns an independent cartridge BRAM, so
// F1 can never overwrite resident firmware. MiSTer Main can send the
// user-supplied chip8.bin automatically from beside an F3 selection at
// supplemental index $0103, or the user can cache it manually through F4 at
// index $0004. That universal Studio-family interpreter goes into the fifth
// firmware/program BRAM.
//
// Mapping matches the OSD Machine row (status[14:13] / `machine`):
//   0 Studio II        → boot0.rom
//   1 Studio III PAL   → boot1.rom
//   2 Studio III NTSC  → boot2.rom
//   3 Visicom          → boot3.rom
//
// Manual "Load Firmware" (F2) lands in the *currently selected* machine's
// slot: pick the machine, Apply, then load its firmware. (It cannot ride
// ioctl_index[7:6] the way boot autoload does -- menu loads put the file's
// extension index there, so a .rom would always land in slot 1.)
//
// Cartridge downloads (ioctl index 1) are written only into the *currently
// selected* machine's cartridge BRAM. Cartridge page ownership is kept with
// the same machine slot and determines where that BRAM overlays firmware/RAM.

wire [1:0]  bios_slot = fw_dl ? machine : ioctl_index[7:6];
wire [11:0] chip8_dl_a = ch8_dl ? ch8_a : ioctl_addr[11:0];

// BIOS write: only the matching firmware BRAM
wire        bios_we0 = bios_dl && ioctl_wr && (bios_slot == 2'd0);
wire        bios_we1 = bios_dl && ioctl_wr && (bios_slot == 2'd1);
wire        bios_we2 = bios_dl && ioctl_wr && (bios_slot == 2'd2);
wire        bios_we3 = bios_dl && ioctl_wr && (bios_slot == 2'd3);
wire        bios_we4 = chip8_fw_dl && ioctl_wr && (ioctl_addr < 25'h300);

// Cart write: only into the cartridge BRAM that belongs to the active machine
wire        cart_we0 = cart_we && (machine == 2'd0);
wire        cart_we1 = cart_we && (machine == 2'd1);
wire        cart_we2 = cart_we && (machine == 2'd2);
wire        cart_we3 = cart_we && (machine == 2'd3);

wire        we4 = bios_we4 | ch8_we;

wire [7:0]  rom0_q, rom1_q, rom2_q, rom3_q, rom4_q;
wire [7:0]  cart0_q, cart1_q, cart2_q, cart3_q;

// A truncated or absent cached interpreter must not accept a .ch8 file. A
// valid interpreter is
// 768 bytes, ending at $02FF; starting a replacement invalidates the old copy
// until that final required byte arrives. Loading it never activates CHIP-8.
initial chip8_fw_loaded = 1'b0;
always @(posedge clk_sys) begin
	if (!ioctl_download) chip8_fw_start_seen <= 1'b0;
	else if (bios_we4 && (ioctl_addr == 25'd0)) chip8_fw_start_seen <= 1'b1;

	if (chip8_fw_dl && !dl_d) chip8_fw_loaded <= 1'b0;
	else if (bios_we4 && chip8_fw_start_seen && (ioctl_addr == 25'h2FF)) chip8_fw_loaded <= 1'b1;

	if (!ioctl_download) chip8_write_seen <= 1'b0;
	else if (ch8_we)     chip8_write_seen <= 1'b1;

	// Unload removes the active game regardless of whether it came through the
	// native cartridge path or CHIP-8. Keep chip8_fw_loaded intact so the cached
	// interpreter remains available for the next .ch8 selection.
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

dpram #(8, 12) rom4
(
	.clock(clk_sys),
	.ram_cs(1'b1),
	.address_a((ch8_dl || chip8_fw_dl) ? chip8_dl_a : ram_a[11:0]),
	.wren_a(we4),
	.data_a(ioctl_dout),
	.q_a(rom4_q),
	.ram_cs_b(1'b0),
	.wren_b(1'b0),
	.address_b(12'd0),
	.data_b(),
	.q_b()
);

// Four cartridge BRAMs are addressed independently from firmware. Old bytes
// may remain physically present after replacement or unload, but are invisible
// unless the corresponding active-machine cart_page bit is set.
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

// CPU (and DMA) reads the shared CHIP-8 image when active, otherwise firmware
// from the selected native machine. Visicom can never select rom4.
assign rom_q = chip8_active ? rom4_q :
	           (machine == 2'd0) ? rom0_q :
	           (machine == 2'd1) ? rom1_q :
	           (machine == 2'd2) ? rom2_q : rom3_q;

// Cartridge reads always come from the selected native machine's independent
// cartridge BRAM. cart_sel/cart_page decides whether this data is visible.
assign cart_q = (machine == 2'd0) ? cart0_q :
	            (machine == 2'd1) ? cart1_q :
	            (machine == 2'd2) ? cart2_q : cart3_q;

// The RAM: 512 bytes ($0800-$08FF program/system, $0900-$09FF display on the
// Studio II and III; $1000-$11FF on the Visicom, whose bit plane 0 is its top
// half). The Visicom's plane 1 is the separate 256-byte array below.
// Selected by A9 = 0, so the address inside it is just A8-A0.
// Add a port-B writer used to clear VRAM on CLEAR without resetting the Pixie
reg [8:0] clear_addr_b = 9'd0;
reg       clear_active = 1'b0;

// The wipe drives port A, not port B. Port B writing is what stopped this array
// inferring as block RAM: two active write ports mean mixed-port read-during-
// write, which an M10K cannot honour, and Quartus reported
//
//   Info (276009): RAM logic "...|dpram:sram|mem" is uninferred due to
//                  unsupported read-during-write behavior
//
// and built all 512 bytes out of logic instead -- 6,119 ALUTs and 4,104
// registers, most of the whole core. The ROM dpram and the Visicom's sram2 use
// this same module with port B tied off and both infer cleanly, which is what
// makes this the fix rather than a ramstyle attribute.
//
// Safe on port A because CLEAR is folded into reset, so the CPU is held in reset
// for the whole wipe and is not driving the bus.
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

	// Port B is tied off entirely, which is what lets this infer as block RAM.
	// Do not give it a write or a read without re-checking the inferred-
	// altsyncram list in output_files/Studio-II.map.rpt (see AGENTS.md, RAM inference).
	.ram_cs_b(1'b0),
	.wren_b(1'b0),
	.address_b(9'd0),
	.data_b(),
	.q_b()
);

// The Visicom's second bit plane: 256 bytes at $1300-$13FF, read every cycle at
// A7-A0 so the video has it during DMA and the CPU has it at $13xx.
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

// SC is driven by the CPU's output port, so it must be a net -- declaring it a reg with an
// initial value of 2'b10 meant the 1861 saw a constant "DMA" state code.
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
    // Emma 02 StudioIII/standard-ntsc.xml: INP 1 enables video; OUT 1
    // steps the 1862 background only. Studio II alone disables on OUT 1.
    // Visicom enables on OUT 1 and has no display-off port.
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

// ---- CDP1864, the colour machines' video ---------------------------------
// Both parts are instantiated and the active one selected, rather than making
// one module's geometry runtime-switchable: the 1861's timing is delicately
// tuned and documented as such, and both parts are tiny. See the header of
// rtl/pixie/cdp1864.v.
//
// Note the different I/O decode. On the 1864 the display is turned off by INP 4,
// not OUT 1 -- OUT 1 is taken over by the background colour step. The datasheet
// gives the opcodes: 61 or 69 enable interrupt and DMA, 6C disables them.
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
// The CDP1864 integrates this; the NTSC Studio III has it as a separate CDP1863
// beside its 1861 and 1862. Same latch on OUT 4 and the same gate on Q either
// way, differing only by one division stage -- so one instance serves both, with
// div4 picking the chain. Straight from the datasheet's control-line truth table
// and Weisbecker's Studio III notes ("64 instruction sets sound frequency
// (inverse)", "Q gates sound output").
wire aud_tone;
cdp1863 cdp1863
(
    .clk     (clk_sys),
    .cpu_ce  (cpu_ce),
    .reset   (video_reset | (preserve_sync_reset & ~clear_key)),
    // The 1864's integrated generator has an extra divide-by-4 that the
    // standalone 1863 does not, so the same latch sounds four times higher on
    // the NTSC machine. MAME: cdp1864 f = clk/8/4/(latch+1)/2 against cdp1863
    // f = clk/8/(latch+1)/2 from its clock2 input, which is where TPB goes.
    .div4    ((machine == MACHINE_S3_PAL) ||
              ((machine == MACHINE_S3_NTSC) && ntsc_pal_pitch)),
    .tone_we (out4),
    .tone_d  (cpu_dout),
    .aoe     (Q),
    .aud     (aud_tone)
);

// ---- select ---------------------------------------------------------------
// The Studio II's 1861 has no colour, so every channel follows its single dot
// bit -- white on black, unchanged from before the video path widened.
wire       video_dot;
wire       DMAO_61, INT_61, EFx_61;
wire       VSync_61, HSync_61, VBlank_61, HBlank_61, de_61, bde_61;
wire       bhb_61, bvb_61;
wire [2:0] col61_dot, col61_bgc;
wire       col61_bg;
wire [2:0] video_61;
wire       bg_61;

// The CDP1862 beside the 1861, fitted only on the NTSC Studio III. On a Studio II
// `enable` is low and it passes the luminance bit straight through as white.
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

// The Visicom's four colours do not fit a 1-bit-per-channel bus, so the exact
// palette is applied at the top level (Studio-II.sv) from vis_index. What
// goes out here is the nearest 3-bit approximation, which is what the Verilator
// harness captures -- the four colours stay distinguishable in a PNG or an
// ASCII dump, which is all that side needs.
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
