// Controller profiles translate gamepad inputs into Studio II keypad masks.
//
// MiSTer joystick bits, per the CONF_STR "J1,..." list in Studio-II.sv:
//   [0]=right [1]=left [2]=down [3]=up   [4]=Fire   [5]=Extra   [6]=Start
//   [7]=Select(CLEAR, folded into reset by the top level)
//   [17:8]=A0..A9   [27:18]=B0..B9.
// Direct A0..B9 bindings are ORed with profile outputs.

// Profile IDs must match the OSD list in Studio-II.sv.
localparam [3:0] MAP_NONE       = 4'd0;   // no controller mapping; keep keypad/OSK input only
localparam [3:0] MAP_CROSS      = 4'd1;   // 2/8/4/6 + 5 fire, both pads
localparam [3:0] MAP_SPACEWAR   = 4'd2;   // fire A2, steer B4/B6
localparam [3:0] MAP_FREEWAY    = 4'd3;   // Studio II uses A for speed and B to steer;
                                          // Visicom puts every control on B
localparam [3:0] MAP_BOWLING    = 4'd4;   // roll 5, hook 2/8 on the active A/B pad
localparam [3:0] MAP_BASEBALL   = 4'd5;   // bat A5; pitch B5 straight, B2/B8 curve
localparam [3:0] MAP_HOMEBREW   = 4'd6;   // Paul Robson's 1P games: 8-way on pad A
                                          // (diagonals are keys 1/3/7/9), fire B0
localparam [3:0] MAP_VIS_ART    = 4'd7;   // Visicom Doodle/Patterns: directions B,
	                                          // Fire B5, Extra B0
localparam [3:0] MAP_8WAY       = 4'd8;   // CROSS plus diagonals: 1/3/7/9, fire 5 + extra 0
localparam [3:0] MAP_DOODLE     = 4'd9;   // Doodle/Patterns: B-side 8-way, fire 5, extra 0
localparam [3:0] MAP_HB2P       = 4'd10;  // Hockey/Combat: cross and fire 0 on each pad
localparam [3:0] MAP_RACE       = 4'd11;  // Race: keypad B steering on 4/6,
                                          // accelerate 2, brake 5
localparam [3:0] MAP_TENNIS     = 4'd12;  // 8-way: Auto uses B, 1P mirrors A/B,
                                          // 2P splits pads; Start stays A1.
localparam [3:0] MAP_CHIP8      = 4'd13;  // common CHIP-8 movement cluster: 5/7/8/9
                                          // on pad A; Start 1, Fire F, Extra 0.
localparam [3:0] MAP_CLIMB      = 4'd14;  // Climber/Outbreak: A-side movement, Fire
                                          // replays on B1, Extra modifies left/right
                                          // with matching B4/B6 for Outbreak speed
localparam [3:0] MAP_EXPLORER   = 4'd15;  // Space Explorer: B-side 8-way, Fire A0,
                                          // Extra locks with B5

// Non-key value in cached cartridge metadata selects the shared firmware menu.
localparam [3:0] START_S3_MENU = 4'd14;

reg [3:0] map_profile = MAP_NONE;
reg [3:0] start_key   = 4'd1;

// Per-machine cartridge metadata survives ordinary reset and firmware loads.
reg [3:0] cart_profile_s2      = MAP_8WAY;
reg [3:0] cart_profile_s3_pal  = MAP_8WAY;
reg [3:0] cart_profile_s3_ntsc = MAP_8WAY;
reg [3:0] cart_profile_vis     = MAP_8WAY;

reg cart_pad_b_s2      = 1'b0;
reg cart_pad_b_s3_pal  = 1'b0;
reg cart_pad_b_s3_ntsc = 1'b0;
reg cart_pad_b_vis     = 1'b0;
wire cart_pad_b = (machine == MACHINE_STUDIO2) ? cart_pad_b_s2
                : (machine == MACHINE_S3_PAL) ? cart_pad_b_s3_pal
                : (machine == MACHINE_S3_NTSC) ? cart_pad_b_s3_ntsc
                : cart_pad_b_vis;

reg [3:0] cart_start_s2      = 4'd1;
reg [3:0] cart_start_s3_pal  = 4'd1;
reg [3:0] cart_start_s3_ntsc = 4'd1;
reg [3:0] cart_start_vis     = 4'd0;

reg cart_profile_valid_s2      = 1'b0;
reg cart_profile_valid_s3_pal  = 1'b0;
reg cart_profile_valid_s3_ntsc = 1'b0;
reg cart_profile_valid_vis     = 1'b0;

wire cart_profile_valid = (machine == MACHINE_STUDIO2) ? cart_profile_valid_s2
                        : (machine == MACHINE_S3_PAL)  ? cart_profile_valid_s3_pal
                        : (machine == MACHINE_S3_NTSC) ? cart_profile_valid_s3_ntsc
                        :                                cart_profile_valid_vis;

// ---- CRC16-CCITT over the cartridge image, computed during cartridge load ----
// Download CRC is separate from per-machine cartridge metadata.
reg [15:0] cart_crc = 16'hFFFF;
reg        dl_d;
reg        cart_dl_d = 1'b0;
wire       dl_done      = dl_d & ~ioctl_download;  // generic download falling edge
wire       cart_dl_start = cart_dl & ~cart_dl_d;
wire       cart_dl_done  = cart_dl_d & ~cart_dl;

always @(posedge clk_sys) begin
	integer i;
	reg [15:0] c;

	dl_d      <= ioctl_download;
	cart_dl_d <= cart_dl;

	if (cart_dl_start)
		cart_crc <= 16'hFFFF;

	if (cart_dl && ioctl_wr) begin
		c = (ioctl_addr == 0) ? 16'hFFFF : cart_crc;
		c = c ^ {ioctl_dout, 8'h00};
		for (i = 0; i < 8; i = i + 1)
			c = c[15] ? ((c << 1) ^ 16'h1021) : (c << 1);
		cart_crc <= c;
	end
end

// ---- CRC -> profile + Start key ---------------------------------------------
// Unknown cartridges use the neutral eight-way layout.
function automatic [8:0] resolve_cart_profile(
	input [15:0] crc,
	input        visicom
);
	reg [3:0] p;
	reg [3:0] s;
	reg b;
	begin
		p = MAP_8WAY;
		s = visicom ? 4'd0 : 4'd1;
		b = 1'b0;

		case (crc)
`include "studio2_cart_profiles.svh"
		default: ;
		endcase

		resolve_cart_profile = {b, p, s};
	end
endfunction

wire [8:0] resolved_cart_profile = resolve_cart_profile(cart_crc, machine_visicom);

// Active profile registers are also exposed to the simulation harness.
reg [1:0] profile_machine_d = MACHINE_STUDIO2;

always @(posedge clk_sys) begin
	profile_machine_d <= machine;

	// Switching machines selects that machine's remembered cartridge profile.
	if (profile_machine_d != machine) begin
		case (machine)
		MACHINE_STUDIO2: begin
			map_profile <= cart_profile_s2;
			start_key   <= cart_start_s2;
		end
		MACHINE_S3_PAL: begin
			map_profile <= cart_profile_s3_pal;
			start_key   <= cart_start_s3_pal;
		end
		MACHINE_S3_NTSC: begin
			map_profile <= cart_profile_s3_ntsc;
			start_key   <= cart_start_s3_ntsc;
		end
		default: begin
			map_profile <= cart_profile_vis;
			start_key   <= cart_start_vis;
		end
		endcase
	end

	// Starting a replacement immediately invalidates only this machine's old
	// profile. The new result becomes resident when the cartridge completes.
	if (cart_dl_start) begin
		case (machine)
		MACHINE_STUDIO2: cart_profile_valid_s2      <= 1'b0;
		MACHINE_S3_PAL:  cart_profile_valid_s3_pal  <= 1'b0;
		MACHINE_S3_NTSC: cart_profile_valid_s3_ntsc <= 1'b0;
		MACHINE_VISICOM: cart_profile_valid_vis     <= 1'b0;
		endcase
	end

	if (cart_dl_done) begin
		map_profile <= resolved_cart_profile[7:4];
		start_key   <= resolved_cart_profile[3:0];

		case (machine)
		MACHINE_STUDIO2: begin
			cart_profile_s2       <= resolved_cart_profile[7:4];
			cart_pad_b_s2         <= resolved_cart_profile[8];
			cart_start_s2         <= resolved_cart_profile[3:0];
			cart_profile_valid_s2 <= 1'b1;
		end
		MACHINE_S3_PAL: begin
			cart_profile_s3_pal       <= resolved_cart_profile[7:4];
			cart_pad_b_s3_pal         <= resolved_cart_profile[8];
			cart_start_s3_pal         <= resolved_cart_profile[3:0];
			cart_profile_valid_s3_pal <= 1'b1;
		end
		MACHINE_S3_NTSC: begin
			cart_profile_s3_ntsc       <= resolved_cart_profile[7:4];
			cart_pad_b_s3_ntsc         <= resolved_cart_profile[8];
			cart_start_s3_ntsc         <= resolved_cart_profile[3:0];
			cart_profile_valid_s3_ntsc <= 1'b1;
		end
		MACHINE_VISICOM: begin
			cart_profile_vis       <= resolved_cart_profile[7:4];
			cart_pad_b_vis         <= resolved_cart_profile[8];
			cart_start_vis         <= resolved_cart_profile[3:0];
			cart_profile_valid_vis <= 1'b1;
		end
		endcase
	end

	// The cartridge loader owns BRAM residency; this block owns profile validity.
	if (cart_unload) begin
		case (machine)
		MACHINE_STUDIO2: cart_profile_valid_s2      <= 1'b0;
		MACHINE_S3_PAL:  cart_profile_valid_s3_pal  <= 1'b0;
		MACHINE_S3_NTSC: cart_profile_valid_s3_ntsc <= 1'b0;
		MACHINE_VISICOM: cart_profile_valid_vis     <= 1'b0;
		endcase
	end
end

// ---- built-in games -------------------------------------------------------
// Only the first recognized menu key selects a profile; keys are reused in play.

wire       no_cart = !chip8_active && !cart_profile_valid;
wire       cart_s3_menu = !chip8_active && cart_profile_valid &&
                         is_studio3 && (start_key == START_S3_MENU);
wire       firmware_menu = no_cart || cart_s3_menu;
reg        builtin_sel;
reg  [3:0] builtin_profile;
reg  [3:0] builtin_start_key;

// Unload restores the selected machine's resident-firmware mapping.
reg [3:0] resident_profile_s2      = MAP_8WAY;
reg [3:0] resident_profile_s3_pal  = MAP_8WAY;
reg [3:0] resident_profile_s3_ntsc = MAP_8WAY;
reg [3:0] resident_profile_vis     = MAP_8WAY;

reg [3:0] resident_start_s2      = 4'd1;
reg [3:0] resident_start_s3_pal  = 4'd1;
reg [3:0] resident_start_s3_ntsc = 4'd1;
reg [3:0] resident_start_vis     = 4'd1;

wire [3:0] resident_profile = (machine == MACHINE_STUDIO2) ? resident_profile_s2
                            : (machine == MACHINE_S3_PAL)  ? resident_profile_s3_pal
                            : (machine == MACHINE_S3_NTSC) ? resident_profile_s3_ntsc
                            :                                resident_profile_vis;
wire [3:0] resident_start_key = (machine == MACHINE_STUDIO2) ? resident_start_s2
                              : (machine == MACHINE_S3_PAL)  ? resident_start_s3_pal
                              : (machine == MACHINE_S3_NTSC) ? resident_start_s3_ntsc
                              :                                resident_start_vis;

// Firmware selection accepts both physical and on-screen keypad input.
wire [9:0] builtin_padA = playerA | osk_a;
wire        builtin_start_press = start_press | osk_a[active_start_key];

always @(posedge clk_sys) begin
	if (reset || (cart_unload && cart_s3_menu)) begin
		// Re-arm selection while retaining the remembered resident mapping.
		builtin_sel       <= 1'b0;
		builtin_profile   <= (cart_s3_menu && !cart_unload) ? MAP_DOODLE : resident_profile;
		builtin_start_key <= (cart_s3_menu && !cart_unload) ? 4'd1 : resident_start_key;
	end
	else if (firmware_menu && !builtin_sel) begin
		case (machine)
		MACHINE_STUDIO2: begin
			if      (builtin_padA[1] || (builtin_start_press && (active_start_key == 4'd1))) begin builtin_profile <= MAP_DOODLE; builtin_sel <= 1'b1; end  // Doodle
			else if (builtin_padA[2] || (builtin_start_press && (active_start_key == 4'd2))) begin builtin_profile <= MAP_DOODLE; builtin_sel <= 1'b1; end  // Patterns
			else if (builtin_padA[3]) begin builtin_profile <= MAP_BOWLING; builtin_sel <= 1'b1; end  // Bowling
			else if (builtin_padA[4]) begin builtin_profile <= MAP_FREEWAY; builtin_sel <= 1'b1; end  // Freeway
			else if (builtin_padA[5]) begin builtin_profile <= MAP_8WAY; builtin_sel <= 1'b1; end  // Addition
		end
		MACHINE_S3_PAL, MACHINE_S3_NTSC: begin
			if      (builtin_padA[1] || (builtin_start_press && (active_start_key == 4'd1))) begin builtin_profile <= MAP_DOODLE; builtin_sel <= 1'b1; end  // Doodle
			else if (builtin_padA[2] || (builtin_start_press && (active_start_key == 4'd2))) begin builtin_profile <= MAP_DOODLE; builtin_sel <= 1'b1; end  // Patterns
			else if (builtin_padA[3]) begin builtin_profile <= MAP_BOWLING; builtin_sel <= 1'b1; end  // Bowling
			else if (builtin_padA[4] || builtin_padA[5]) begin // Blackjack
				builtin_profile   <= MAP_8WAY;
				builtin_start_key <= builtin_padA[4] ? 4'd4 : 4'd5;
				builtin_sel       <= 1'b1;
			end
		end
		MACHINE_VISICOM: begin
			if (builtin_padA[1] || (builtin_start_press && (active_start_key == 4'd1))) begin
				builtin_profile   <= MAP_VIS_ART; // Doodle
				builtin_start_key <= 4'd1;
				builtin_sel       <= 1'b1;
			end
			else if (builtin_padA[2]) begin
				builtin_profile <= MAP_BOWLING; // Bowling
				builtin_sel     <= 1'b1;
			end
			else if (builtin_padA[3]) begin
				builtin_profile   <= MAP_VIS_ART; // Patterns
				builtin_start_key <= 4'd3;
				builtin_sel       <= 1'b1;
			end
			else if (builtin_padA[4]) begin
				builtin_profile <= MAP_FREEWAY; // Freeway
				builtin_sel     <= 1'b1;
			end
			else if (builtin_padA[7]) begin
				builtin_profile <= MAP_8WAY; // Addition
				builtin_sel     <= 1'b1;
			end
		end
		endcase
	end
end

// Firmware replacement invalidates selection because its menu may differ.
reg builtin_sel_d = 1'b0;
reg resident_fw_dl_d = 1'b0;
wire resident_fw_dl = ioctl_download && (ioctl_index[5:0] == 6'd2);
wire resident_fw_dl_start = resident_fw_dl && !resident_fw_dl_d;

always @(posedge clk_sys) begin
	builtin_sel_d   <= builtin_sel;
	resident_fw_dl_d <= resident_fw_dl;

	if (resident_fw_dl_start) begin
		case (machine)
		MACHINE_STUDIO2: begin
			resident_profile_s2 <= MAP_8WAY;
			resident_start_s2   <= 4'd1;
		end
		MACHINE_S3_PAL: begin
			resident_profile_s3_pal <= MAP_8WAY;
			resident_start_s3_pal   <= 4'd1;
		end
		MACHINE_S3_NTSC: begin
			resident_profile_s3_ntsc <= MAP_8WAY;
			resident_start_s3_ntsc   <= 4'd1;
		end
		MACHINE_VISICOM: begin
			resident_profile_vis <= MAP_8WAY;
			resident_start_vis   <= 4'd1;
		end
		endcase
	end
	else if (no_cart && builtin_sel && !builtin_sel_d) begin
		case (machine)
		MACHINE_STUDIO2: begin
			resident_profile_s2 <= builtin_profile;
			resident_start_s2   <= builtin_start_key;
		end
		MACHINE_S3_PAL: begin
			resident_profile_s3_pal <= builtin_profile;
			resident_start_s3_pal   <= builtin_start_key;
		end
		MACHINE_S3_NTSC: begin
			resident_profile_s3_ntsc <= builtin_profile;
			resident_start_s3_ntsc   <= builtin_start_key;
		end
		MACHINE_VISICOM: begin
			resident_profile_vis <= builtin_profile;
			resident_start_vis   <= builtin_start_key;
		end
		endcase
	end
end

// ---- effective profile ------------------------------------------------------
// Manual selection overrides detection without changing the detected profile.
assign     auto_profile = chip8_active ? MAP_CHIP8 : (firmware_menu ? builtin_profile : map_profile);
wire [3:0] profile      = joy_manual ? joy_override : auto_profile;

// ---- profile -> keypad presses ---------------------------------------------
// A/B masks describe keypad actions; Players controls their joystick sources.

function automatic [9:0] map_cross(input [31:0] j);
	reg [9:0] k;
	begin
		k = 10'd0;
		if (j[3]) k[2] = 1'b1;
		if (j[2]) k[8] = 1'b1;
		if (j[1]) k[4] = 1'b1;
		if (j[0]) k[6] = 1'b1;
		map_cross = k;
	end
endfunction

function automatic [9:0] map_8way(input [31:0] j);
	reg [9:0] k;
	begin
		case (j[3:0])
		4'b1010: begin k = 10'd0; k[1] = 1'b1; end // up+left
		4'b1001: begin k = 10'd0; k[3] = 1'b1; end // up+right
		4'b0110: begin k = 10'd0; k[7] = 1'b1; end // down+left
		4'b0101: begin k = 10'd0; k[9] = 1'b1; end // down+right
		default:  k = map_cross(j);
		endcase
		map_8way = k;
	end
endfunction

function automatic [9:0] map_padA(input [3:0] prof, input [31:0] j);
	reg [9:0] k;
	begin
		k = 10'd0;
		case (prof)
		MAP_CROSS: begin
			k = map_cross(j);
			if (j[4]) k[5] = 1'b1;
			if (j[5]) k[0] = 1'b1;           // Extra
		end
		MAP_SPACEWAR:                        // fire
			if (j[4]) k[2] = 1'b1;
		MAP_FREEWAY: begin                   // throttle/brake
			if (!machine_visicom) begin
				if (j[3]) k[2] = 1'b1;   if (j[2]) k[8] = 1'b1;
				if (j[4]) k[2] = 1'b1;   if (j[5]) k[0] = 1'b1;
			end
		end
		MAP_BOWLING: begin                   // roll straight, or hook up/down
			if (j[4]) k[5] = 1'b1;
			if (j[3]) k[2] = 1'b1;   if (j[2]) k[8] = 1'b1;
		end
		MAP_VIS_ART: ;                         // drawing and colour controls are on B
		MAP_BASEBALL:                        // bat
			if (j[4]) k[5] = 1'b1;
		MAP_HOMEBREW: begin
			// Berzerk uses the corner keys for diagonal movement.
			k = map_8way(j);
		end
		MAP_HB2P: begin                      // own pad: cross + fire on 0
			k = map_cross(j);
			if (j[4]) k[0] = 1'b1;
		end
		MAP_RACE: ;                         // Race reads gameplay controls on keypad B
		MAP_8WAY: begin                      // CROSS + 8-way diagonals: 1/3/7/9 on corners
			k = map_8way(j);
			if (j[4]) k[5] = 1'b1;
			if (j[5]) k[0] = 1'b1;
		end
		MAP_DOODLE: begin                   // Doodle/Patterns: B-side 8-way, single-player
			k = map_8way(j);
			if (j[4]) k[5] = 1'b1;
			if (j[5]) k[0] = 1'b1;
		end
		MAP_TENNIS: begin
			k = map_8way(j);
			if (j[4]) k[5] = 1'b1;   if (j[5]) k[0] = 1'b1;
		end
		MAP_CHIP8: begin                     // common WASD-shaped CHIP-8 cluster
			if (j[3]) k[5] = 1'b1;   if (j[2]) k[8] = 1'b1;
			if (j[1]) k[7] = 1'b1;   if (j[0]) k[9] = 1'b1;
			if (j[5]) k[0] = 1'b1;           // Extra
		end
		MAP_CLIMB: begin
			k = map_8way(j);
		end
		MAP_EXPLORER:
			if (j[4]) k[0] = 1'b1;           // Fire
		default: ;
		endcase
		map_padA = k;
	end
endfunction

function automatic [9:0] map_padB(input [3:0] prof, input [31:0] j);
	reg [9:0] k;
	begin
		k = 10'd0;
		case (prof)
		MAP_CROSS: begin
			k = map_cross(j);
			if (j[4]) k[5] = 1'b1;
			if (j[5]) k[0] = 1'b1;           // Extra
		end
		MAP_SPACEWAR: begin                  // steering
			if (j[1]) k[4] = 1'b1;   if (j[0]) k[6] = 1'b1;
		end
		MAP_FREEWAY: begin
			if (j[1]) k[4] = 1'b1;   if (j[0]) k[6] = 1'b1;
			if (machine_visicom) begin
				if (j[3]) k[2] = 1'b1;   if (j[2]) k[8] = 1'b1;
				if (j[4]) k[2] = 1'b1;           // accelerate independently
				if (j[5]) k[5] = 1'b1;           // License B
				if (j[6]) k[0] = 1'b1;           // License A
			end
			else if (j[6]) k[0] = 1'b1;       // Studio II normal
		end
		MAP_BOWLING: begin                   // active player rolls from either keypad
			if (j[4]) k[5] = 1'b1;
			if (j[3]) k[2] = 1'b1;   if (j[2]) k[8] = 1'b1;
		end
		MAP_BASEBALL: begin                  // pitch
			if (j[4]) k[5] = 1'b1;
			if (j[3]) k[2] = 1'b1;   if (j[2]) k[8] = 1'b1;
		end
		MAP_HOMEBREW: begin
			// Invaders fires on B0 and restarts on A0; Pacman reads down on B8.
			k = map_cross(j);
			if (j[4]) k[0] = 1'b1;
		end
		MAP_HB2P: begin                      // own pad: cross + fire on 0
			k = map_cross(j);
			if (j[4]) k[0] = 1'b1;
		end
		MAP_RACE: begin                    // Race: B4/B6 steer, B2 accelerate, B5 brake
			if (j[1]) k[4] = 1'b1;
			if (j[0]) k[6] = 1'b1;
			if (j[3] || j[4]) k[2] = 1'b1;   // Up or Fire: accelerate
			if (j[2] || j[5]) k[5] = 1'b1;   // Down or Extra: brake
		end
		MAP_VIS_ART: begin                   // movement draws; 5/0 select colour/state
			k = map_8way(j);
			if (j[4]) k[5] = 1'b1;           // next colour
			if (j[5]) k[0] = 1'b1;           // previous colour / flashing
		end
		MAP_8WAY: begin                      // CROSS + 8-way diagonals: 1/3/7/9 on corners
			k = map_8way(j);
			if (j[4]) k[5] = 1'b1;
			if (j[5]) k[0] = 1'b1;
		end
		MAP_DOODLE: begin                   // Doodle/Patterns: B-side 8-way, single-player
			k = map_8way(j);
			if (j[4]) k[5] = 1'b1;
			if (j[5]) k[0] = 1'b1;
		end
		MAP_TENNIS: begin                    // movement, racket-size setup, and pause
			k = map_8way(j);
			if (j[4]) k[5] = 1'b1;   if (j[5]) k[0] = 1'b1;
		end
		MAP_CHIP8:                           // Fire = virtual F = physical B6
			if (j[4]) k[6] = 1'b1;
		MAP_CLIMB: begin
			if (j[4]) k[1] = 1'b1;           // replay after game over
			if (j[5] && j[1]) k[4] = 1'b1;  // Outbreak double-speed modifier
			if (j[5] && j[0]) k[6] = 1'b1;
		end
		MAP_EXPLORER: begin
			k = map_8way(j);
			if (j[5]) k[5] = 1'b1;           // lock target
		end
		default: ;
		endcase
		map_padB = k;
	end
endfunction

wire profile_1p = (profile == MAP_SPACEWAR) || (profile == MAP_FREEWAY) ||
	              (profile == MAP_BOWLING)  || (profile == MAP_NONE) ||
	              (profile == MAP_HOMEBREW) || (profile == MAP_VIS_ART) ||
                  (profile == MAP_8WAY)     || (profile == MAP_DOODLE) ||
                  (profile == MAP_RACE)     || (profile == MAP_TENNIS) ||
                  (profile == MAP_CHIP8)    || (profile == MAP_CLIMB) ||
                  (profile == MAP_EXPLORER);
wire one_player = (players == 2'd1) || ((players == 2'd0) && profile_1p);
wire [31:0] joyB_input = one_player ? joystick_0 : joystick_1;

// Direct keypad bindings and Start accept either controller, independent of Players.
reg [9:0] directA, directB;
integer dk;
always @* begin
	for (dk = 0; dk < 10; dk = dk + 1) begin
		directA[dk] = joystick_0[8+dk]  | joystick_1[8+dk];
		directB[dk] = joystick_0[18+dk] | joystick_1[18+dk];
	end
end
wire       start_press = joystick_0[6] | joystick_1[6];
wire [3:0] active_start_key = (profile == MAP_TENNIS) ? 4'd1
	                         : cart_s3_menu ? 4'd1
	                         : ((profile == MAP_VIS_ART) && no_cart && builtin_sel) ? builtin_start_key
	                         : no_cart ? ((profile == MAP_DOODLE) ? 4'd1 : resident_start_key)
	                         : (((profile == MAP_DOODLE) || (profile == MAP_CHIP8)) ? 4'd1
	                                                                                 : start_key);
wire       builtin_keypad_only = no_cart && builtin_sel && (builtin_profile == MAP_NONE);
wire       start_enabled = (active_start_key < 4'd10) && (profile != MAP_FREEWAY) &&
	                       (profile != MAP_EXPLORER) && !builtin_keypad_only;
wire       start_on_b = (profile == MAP_RACE);
wire [9:0] start_keys_a = (start_enabled && start_press && !start_on_b)
	                        ? (10'd1 << active_start_key) : 10'd0;
wire [9:0] start_keys_b = (start_enabled && start_press && start_on_b)
	                        ? (10'd1 << active_start_key) : 10'd0;

// Eight-way layout and its normal keypad are independent of Players routing.
wire eightway_pad_b = firmware_menu
                   ? (is_studio3 && (builtin_profile == MAP_8WAY) &&
                      ((builtin_start_key == 4'd4) || (builtin_start_key == 4'd5)))
                   : cart_pad_b;
wire eightway_auto = (profile == MAP_8WAY) && (players == 2'd0);

// Gunfighter/Tennis keeps B-only Auto; explicit 1P mirrors both pads.
wire [9:0] joyA = ((profile == MAP_NONE) ? 10'd0
	            : ((profile == MAP_TENNIS) && (players == 2'd0)) ? 10'd0
	            : (eightway_auto && eightway_pad_b) ? 10'd0
	            : ((profile == MAP_DOODLE) ? 10'd0
	                                      : map_padA(profile, joystick_0)));

wire [9:0] joyB = ((profile == MAP_NONE) ? 10'd0
	            : (eightway_auto && !eightway_pad_b) ? 10'd0
	            : ((profile == MAP_DOODLE) ? map_padB(MAP_DOODLE, joystick_0)
	                                      : map_padB(profile, joyB_input)));
wire [9:0] joyA_active = joyA | directA | start_keys_a;
wire [9:0] joyB_active = joyB | directB | start_keys_b;
