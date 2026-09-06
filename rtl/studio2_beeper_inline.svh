//
// Behavioral model of the Q-gated NE555, fitted to the reference recordings in
// docs/beeper-status.md. The internal contour holds near 628.4Hz for 20ms, then
// descends to 505.2Hz; the output period is scaled as one curve for the selected
// console tuning. Q low reverses pitch through the audible release while a faster
// hidden control trajectory preserves the gap-dependent starts measured with
// FLiP's Q-Sound Test. A fresh Q-high drive contour prevents retriggers from
// accumulating pitch drop.
localparam [15:0] SND_HALF_TOP    = 16'd1400;
localparam [15:0] SND_HALF_BOTTOM = 16'd1741;
localparam [15:0] SND_HOLD_TICKS  = 16'd35205; // ~20ms
localparam [12:0] SND_RELEASE_STEP = 13'd600; // audible Q-low pitch recovery
localparam [15:0] SND_RETRIGGER_SETTLE = 16'd10561; // ~6ms live-to-control glide
localparam  [6:0] SND_RETRIGGER_TRACK_STEP = 7'd64;
localparam [12:0] SND_ATTACK_STEP  = 13'd14;  // ~2ms zero-to-full
localparam  [4:0] SND_DUTY_HIGH_PARTS = 5'd11;
localparam  [4:0] SND_DUTY_PARTS      = 5'd17;
localparam  [4:0] SND_DUTY_ROUND      = 5'd8;
// Q14 full-period multipliers. Original is the December 1976 RCA demonstration
// unit (0.9945 of the internal reference frequency). The three choices on
// either side are one, three, and six cumulative reciprocal 31:32 steps.
localparam [14:0] SND_TUNE_HIGHEST_Q14 = 15'd13617;
localparam [14:0] SND_TUNE_HIGHER_Q14  = 15'd14978;
localparam [14:0] SND_TUNE_HIGH_Q14    = 15'd15960;
localparam [14:0] SND_TUNE_MEDIUM_Q14  = 15'd16475;
localparam [14:0] SND_TUNE_LOW_Q14     = 15'd17006;
localparam [14:0] SND_TUNE_LOWER_Q14   = 15'd18121;
localparam [14:0] SND_TUNE_LOWEST_Q14  = 15'd19932;

reg [15:0] snd_half;          // audible oscillator period
reg [15:0] snd_drive_half;    // fresh Q-high contour
reg [15:0] snd_control_half;  // recovered control state for a retrigger
reg [15:0] snd_cnt;
reg [15:0] snd_cycle_base;    // selected tick length shared by one high/low pair
reg [14:0] snd_cycle_scale;   // tuning held for the same complete oscillator cycle
reg [12:0] snd_curve_cnt;
reg [15:0] snd_control_cnt;
reg [15:0] snd_on_ticks;
reg [12:0] snd_amp_cnt;
reg  [6:0] snd_track_cnt;
reg  [9:0] snd_eb_frac;
reg  [7:0] snd_amp;
reg        snd_q_prev;
reg        snd_out;

function automatic [14:0] snd_tune_period_scale(input [2:0] tuning);
begin
	case (tuning)
		3'd1: snd_tune_period_scale = SND_TUNE_HIGH_Q14;
		3'd2: snd_tune_period_scale = SND_TUNE_HIGHER_Q14;
		3'd3: snd_tune_period_scale = SND_TUNE_HIGHEST_Q14;
		3'd4: snd_tune_period_scale = SND_TUNE_LOWEST_Q14;
		3'd5: snd_tune_period_scale = SND_TUNE_LOWER_Q14;
		3'd6: snd_tune_period_scale = SND_TUNE_LOW_Q14;
		default: snd_tune_period_scale = SND_TUNE_MEDIUM_Q14;
	endcase
end
endfunction

// Divider-only approximation of the rounded ~190ms driven descent.
function automatic [12:0] snd_decay_interval(input [15:0] half_period);
begin
	if      (half_period < 16'd1443) snd_decay_interval = 13'd240;
	else if (half_period < 16'd1486) snd_decay_interval = 13'd280;
	else if (half_period < 16'd1529) snd_decay_interval = 13'd330;
	else if (half_period < 16'd1572) snd_decay_interval = 13'd410;
	else if (half_period < 16'd1615) snd_decay_interval = 13'd520;
	else if (half_period < 16'd1657) snd_decay_interval = 13'd740;
	else if (half_period < 16'd1699) snd_decay_interval = 13'd1600;
	else if (half_period < 16'd1715) snd_decay_interval = 13'd2400;
	else if (half_period < 16'd1727) snd_decay_interval = 13'd3400;
	else if (half_period < 16'd1735) snd_decay_interval = 13'd4800;
	else if (half_period < 16'd1740) snd_decay_interval = 13'd6800;
	else                              snd_decay_interval = 13'd8191;
end
endfunction

// Gap-dependent hidden recovery fitted to the controlled Q-Sound Test series.
function automatic [15:0] snd_control_interval(input [15:0] half_period);
begin
	if      (half_period >= 16'd1474) snd_control_interval = 16'd435;
	else if (half_period >= 16'd1445) snd_control_interval = 16'd2750;
	else if (half_period >= 16'd1418) snd_control_interval = 16'd3600;
	else if (half_period >= 16'd1410) snd_control_interval = 16'd9900;
	else if (half_period >= 16'd1406) snd_control_interval = 16'd15000;
	else if (half_period >= 16'd1404) snd_control_interval = 16'd25000;
	else if (half_period >= 16'd1402) snd_control_interval = 16'd45000;
	else                               snd_control_interval = 16'd65000;
end
endfunction

// Divider-only RC envelope: ~21ms prominent decay and ~96ms total tail.
function automatic [12:0] snd_release_interval(input [7:0] amplitude);
begin
	if      (amplitude >= 8'd192) snd_release_interval = 13'd170;
	else if (amplitude >= 8'd128) snd_release_interval = 13'd240;
	else if (amplitude >= 8'd64)  snd_release_interval = 13'd400;
	else if (amplitude >= 8'd32)  snd_release_interval = 13'd800;
	else if (amplitude >= 8'd16)  snd_release_interval = 13'd1600;
	else if (amplitude >= 8'd8)   snd_release_interval = 13'd3200;
	else                           snd_release_interval = 13'd5700;
end
endfunction

// Fractional terminal count for the 628.4Hz plateau; curves use integer periods.
wire [10:0] snd_eb_sum = {1'b0, snd_eb_frac} + 11'd574;
wire        snd_eb_long = (snd_eb_sum >= 11'd1024);
wire [15:0] snd_next_base = ((snd_half == SND_HALF_TOP) && !snd_eb_long)
	                         ? 16'd1400 : snd_half + 16'd1;

// Scale the complete period before splitting it into the measured 11:6 ratio.
// Explicitly widened operands retain all Q14 product bits. Rounding once per
// full period keeps the high and residual low phases on one common tuning.
wire [16:0] snd_base_full_ticks = {snd_cycle_base, 1'b0};
wire [31:0] snd_tune_product = ({15'd0, snd_base_full_ticks}
	                            * {17'd0, snd_cycle_scale});
wire [31:0] snd_tune_rounded = snd_tune_product + 32'd8192;
wire [16:0] snd_full_ticks = snd_tune_rounded[30:14];
wire [20:0] snd_high_scaled = ({4'd0, snd_full_ticks}
	                           * {16'd0, SND_DUTY_HIGH_PARTS})
	                           + {16'd0, SND_DUTY_ROUND};
wire [20:0] snd_high_quotient = snd_high_scaled / {16'd0, SND_DUTY_PARTS};
wire [16:0] snd_high_ticks = snd_high_quotient[16:0];
wire [16:0] snd_phase_ticks = snd_out ? snd_high_ticks
	                                  : snd_full_ticks - snd_high_ticks;
wire [15:0] snd_toggle_at = snd_phase_ticks[15:0] - 16'd1;

always @(posedge clk_sys) begin
	if (reset) begin
		snd_half       <= SND_HALF_TOP;
		snd_drive_half <= SND_HALF_TOP;
		snd_control_half <= SND_HALF_TOP;
		snd_cnt        <= 16'd0;
		snd_cycle_base <= 16'd1400;
		snd_cycle_scale <= SND_TUNE_MEDIUM_Q14;
		snd_curve_cnt  <= 13'd0;
		snd_control_cnt <= 16'd0;
		snd_on_ticks   <= 16'd0;
		snd_amp_cnt    <= 13'd0;
		snd_track_cnt  <= 7'd0;
		snd_eb_frac    <= 10'd0;
		snd_amp        <= 8'd0;
		snd_q_prev     <= 1'b0;
		snd_out        <= 1'b0;
	end
	else if (ce_pix) begin
		snd_q_prev <= Q;

		// Q edges establish the three continuous trajectories. The audible period
		// never jumps at an edge; the control and fresh-drive contours determine
		// where it moves afterward.
		if (Q != snd_q_prev) begin
			snd_amp_cnt <= 13'd0;
			if (Q) begin
				snd_on_ticks   <= 16'd0;
				snd_curve_cnt  <= 13'd0;
				snd_track_cnt  <= 7'd0;
				snd_drive_half <= SND_HALF_TOP;
			end
			else begin
				snd_on_ticks    <= 16'd0;
				snd_track_cnt   <= 7'd0;
				snd_control_half <= snd_half;
				snd_control_cnt <= 16'd0;
			end
		end

		if (!Q) begin
			// The audible release follows the slower Outbreak/Pac-Man upward tail.
			if (snd_half > SND_HALF_TOP) begin
				if (snd_curve_cnt >= SND_RELEASE_STEP-1'b1) begin
					snd_curve_cnt <= 13'd0;
					snd_half <= snd_half - 1'b1;
				end
				else snd_curve_cnt <= snd_curve_cnt + 1'b1;
			end
			else snd_curve_cnt <= 13'd0;

			// The hidden control recovers more quickly along the Gunfighter curve.
			if (!snd_q_prev) begin
				if (snd_control_half > SND_HALF_TOP) begin
					if (snd_control_cnt >= snd_control_interval(snd_control_half)-1'b1) begin
						snd_control_cnt <= 16'd0;
						snd_control_half <= snd_control_half - 1'b1;
					end
					else snd_control_cnt <= snd_control_cnt + 1'b1;
				end
				else snd_control_cnt <= 16'd0;
			end

			// Q gates the envelope, not the oscillator, so the pitch remains continuous.
			if (snd_amp != 8'd0) begin
				if (!snd_q_prev && (snd_amp_cnt >= snd_release_interval(snd_amp)-1'b1)) begin
					snd_amp_cnt <= 13'd0;
					snd_amp <= snd_amp - 1'b1;
				end
				else if (!snd_q_prev) snd_amp_cnt <= snd_amp_cnt + 1'b1;
			end
			else begin
				snd_amp_cnt <= 13'd0;
				snd_out <= 1'b0;
				// Once inaudible, keep the stopped oscillator with the recovered control.
				snd_half <= snd_control_half;
			end
		end
		else begin
			if (snd_q_prev) begin
				// For the first 6ms, glide to the gap-dependent recovered control state.
				if (snd_on_ticks < SND_RETRIGGER_SETTLE) begin
					if (snd_control_half > SND_HALF_TOP) begin
						if (snd_control_cnt >= snd_control_interval(snd_control_half)-1'b1) begin
							snd_control_cnt <= 16'd0;
							snd_control_half <= snd_control_half - 1'b1;
						end
						else snd_control_cnt <= snd_control_cnt + 1'b1;
					end
					else snd_control_cnt <= 16'd0;

					if (snd_half > snd_control_half) begin
						if (snd_track_cnt >= SND_RETRIGGER_TRACK_STEP-1'b1) begin
							snd_track_cnt <= 7'd0;
							snd_half <= snd_half - 1'b1;
						end
						else snd_track_cnt <= snd_track_cnt + 1'b1;
					end
					else snd_track_cnt <= 7'd0;

					if (snd_on_ticks >= SND_RETRIGGER_SETTLE-1'b1) begin
						snd_track_cnt <= 7'd0;
						snd_half <= snd_control_half;
					end
				end
				else begin
					snd_control_cnt <= 16'd0;
					snd_track_cnt <= 7'd0;
				end

				// The same note-age counter defines the 20ms upper-pitch crest.
				if (snd_on_ticks < SND_HOLD_TICKS) begin
					snd_on_ticks <= snd_on_ticks + 1'b1;
					snd_curve_cnt <= 13'd0;
				end
				else begin
					if (snd_drive_half < SND_HALF_BOTTOM) begin
						if (snd_curve_cnt >= snd_decay_interval(snd_drive_half)-1'b1) begin
							snd_curve_cnt <= 13'd0;
							snd_drive_half <= snd_drive_half + 1'b1;
							if (snd_drive_half >= snd_half) begin
								snd_half <= snd_drive_half + 1'b1;
								snd_control_half <= snd_drive_half + 1'b1;
								snd_control_cnt <= 16'd0;
							end
						end
						else snd_curve_cnt <= snd_curve_cnt + 1'b1;
					end
					else begin
						snd_drive_half <= SND_HALF_BOTTOM;
						if (snd_half < SND_HALF_BOTTOM) begin
							snd_half <= SND_HALF_BOTTOM;
							snd_control_half <= SND_HALF_BOTTOM;
						end
						snd_curve_cnt <= 13'd0;
					end
				end
			end

			if (snd_q_prev && snd_amp < 8'hFF) begin
				if (snd_amp_cnt >= SND_ATTACK_STEP-1'b1) begin
					snd_amp_cnt <= 13'd0;
					snd_amp <= snd_amp + 1'b1;
				end
				else snd_amp_cnt <= snd_amp_cnt + 1'b1;
			end
			else snd_amp_cnt <= 13'd0;
		end

		// Run one oscillator path for the driven sound and its fading release.
		if (Q || (snd_amp != 8'd0)) begin
			if (snd_cnt >= snd_toggle_at) begin
				snd_cnt <= 16'd0;
				snd_out <= ~snd_out;
				// A low-to-high edge starts the next complete oscillator cycle.
				// Select its base once so both phases use the same fractional period.
				if (!snd_out) begin
					snd_cycle_base <= snd_next_base;
					snd_cycle_scale <= snd_tune_period_scale(beeper_tune);
					if (snd_half == SND_HALF_TOP)
						snd_eb_frac <= snd_eb_sum[9:0]; // modulo 1024
					else
						snd_eb_frac <= 10'd0;
				end
			end
			else snd_cnt <= snd_cnt + 1'b1;
		end
	end
end

// Scale the 8-bit envelope by 24 (maximum 6120, close to the old +/-6000).
// Production Studio III machines use the CDP1864's fixed-level tone instead.
wire [13:0] snd_magnitude = ({6'd0, snd_amp} << 4) + ({6'd0, snd_amp} << 3);
wire signed [15:0] snd_sample = snd_out ? $signed({2'b00, snd_magnitude})
	                                   : -$signed({2'b00, snd_magnitude});
assign audio = is_studio3 ? (aud_tone ? 16'sd6000 : -16'sd6000) : snd_sample;

