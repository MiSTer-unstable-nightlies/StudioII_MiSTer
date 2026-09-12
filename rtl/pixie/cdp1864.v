//============================================================================
//
//  CDP1864 "PAL Compatible Color TV Interface".
//
//  Written 2026 by Alan Steremberg. Structure, and all of the DMA/INT/EFx
//  timing detail, is derived from this repo's rtl/pixie/cdp1861.v. Both parts
//  have no frame buffer and share the same CPU/DMA contract. Geometry and colour
//  follow the RCA datasheet, MAME's cdp1864 device by Curt Coder (BSD-3-Clause),
//  and Emma 02's machine XML.
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or (at your option)
//  any later version.
//
//============================================================================
//
// Keep shared DMA, INT/EF and horizontal timing consistent with cdp1861.v.
// Tone generation is implemented by cdp1863.v with div4 enabled.
//
//============================================================================

`default_nettype none

module cdp1864
(
    input             clk,          // pixel-rate domain
    input             ce_pix,       // one pulse per pixel time
    input             cpu_ce,       // one pulse per CPU machine cycle (8 pixel times)
    input             reset,

    // ---- CPU side -------------------------------------------------------
    input       [1:0] SC,           // 1802 state code: 2'b10 == DMA cycle
    input       [7:0] data_in,      // luminance byte the CPU put on the bus this DMA cycle
    input       [2:0] colour_in,    // {R,G,B} from colour RAM for that same byte
    input             con,          // Color On: colour RAM has been written (see below)
    input             disp_on,      // INP 1
    input             disp_off,     // INP 4 on this machine, not OUT 1
    input             bg_step,      // OUT 1: step the background colour

    output            DMAO,         // DMA-OUT request, active high
    output reg        INT,          // interrupt request, active high
    output reg        EFx,          // display status -> EF1, active high

    // ---- video side -----------------------------------------------------
    output            csync,
    // DE for the 64x192 bitmap alone; video_de is the whole raster. The harness
    // captures this so its frames stay 64x192 and the recorded scores keep their
    // meaning.
    output            bitmap_de,
    output            bitmap_hblank,
    output            bitmap_vblank,
    output      [2:0] video,        // {R,G,B}
    // BCKGND. Datasheet: "This output indicates that the color selected by the
    // RGB outputs is due to background color select rather than a one bit in a
    // display luminance byte. BCKGND may be used to lower the luminance of the
    // background color so that the same color may be used for display of data."
    // So it is not a fourth colour -- it is a brightness qualifier on the three.
    // Blanked (held high on the real pin) during blanking; here it simply reads
    // low outside the raster, since there is no colour to qualify.
    output            bckgnd,
    output reg        VSync,
    output reg        HSync,
    output reg        VBlank,
    output reg        HBlank,
    output            video_de
);

// ---------------------------------------------------------------------------
// Geometry
// ---------------------------------------------------------------------------
localparam PIXELS_PER_LINE   = 112;                   // 14 machine cycles, as the 1861
localparam LINES_PER_FRAME   = 312;                   // PAL. INLACE low = 312 non-interlaced.

// Emma 02 uses lines 76..267; RCA Fig. 4 and MAME disagree on placement.
// Verify against hardware before moving this window.
localparam DISPLAY_START     = 76;
localparam DISPLAY_END       = 268;                   // one past the last (192 lines)
localparam INT_START         = DISPLAY_START - 2;     // 74
localparam EFX_TOP_START     = DISPLAY_START - 4;     // 72
localparam EFX_BOT_START     = DISPLAY_END   - 4;     // 264

// Same line length, CPU, and ISR structure as the 1861; keep its interrupt/EF
// leads and parity adaptation synchronized.
localparam INT_LEAD          = 8;
localparam EFX_LEAD          = 8;
localparam DMA_ADAPT         = 1;

localparam DMA_START         = 16;
localparam ACTIVE_START      = DMA_START + 24;        // 40
localparam ACTIVE_END        = ACTIVE_START + 64;     // 104
localparam DE_START          = ACTIVE_START;
localparam DE_END            = DE_START + 64;

// Full-raster blanking; preserve bitmap/DMA phase when adjusting porches.
// Timing limitations and geometry: docs/analog-video.md.
localparam HSYNC_START       = 8;
localparam HSYNC_END         = 16;
localparam H_ACTIVE_START    = 24;
// RCA Fig. 4 specifies 20H blanking; Fig. 6 specifies 24H. This uses 20H.
localparam VSYNC_END         = 4;
localparam VBLANK_END        = 20;

// ---------------------------------------------------------------------------
// Counters
// ---------------------------------------------------------------------------
reg [7:0] hcount;
reg [8:0] vcount;

always @(posedge clk) begin
    if (reset) begin
        hcount <= 8'd0;
        vcount <= 9'd0;
    end
    else if (ce_pix) begin
        if (hcount == PIXELS_PER_LINE - 1) begin
            hcount <= 8'd0;
            vcount <= (vcount == LINES_PER_FRAME - 1) ? 9'd0 : vcount + 9'd1;
        end
        else hcount <= hcount + 8'd1;
    end
end

// ---------------------------------------------------------------------------
// INP 1 enables display; INP 4 disables it. OUT 1 steps background colour.
// ---------------------------------------------------------------------------
reg display_enabled;
always @(posedge clk) begin
    if (reset)         display_enabled <= 1'b0;
    else if (disp_off) display_enabled <= 1'b0;
    else if (disp_on)  display_enabled <= 1'b1;
end

// ---------------------------------------------------------------------------
// Background order follows Emma 02; bckgnd qualifies its lower luminance.
// ---------------------------------------------------------------------------
reg [1:0] bg_index;
always @(posedge clk) begin
    if (reset)        bg_index <= 2'd0;
    else if (bg_step) bg_index <= bg_index + 2'd1;
end

reg [2:0] bg_colour;
always @(*) begin
    case (bg_index)
        2'd0:    bg_colour = 3'b001;   // blue
        2'd1:    bg_colour = 3'b000;   // black
        2'd2:    bg_colour = 3'b010;   // green
        default: bg_colour = 3'b100;   // red
    endcase
end

wire line_displayed = (vcount >= DISPLAY_START) && (vcount < DISPLAY_END);

// ---------------------------------------------------------------------------
// CDP1864 latches colour and luminance in the same DMA cycle.
// ---------------------------------------------------------------------------
reg dma_early;
always @(posedge clk) begin
    if (reset) dma_early <= 1'b0;
    else if (ce_pix && hcount == 4)
        dma_early <= (DMA_ADAPT != 0) && (vcount > DISPLAY_START) && (vcount < DISPLAY_END) && (SC == 2'b00);
end

assign DMAO = display_enabled && line_displayed &&
              (hcount >= (dma_early ? DMA_START - 8 : DMA_START)) && (dma_cnt < 4'd7);

reg  [7:0] linebuf [0:7];
reg  [2:0] colbuf  [0:7];
// CON follows colour-memory writes and is latched per DMA byte.
reg  [7:0] conbuf;
reg  [3:0] dma_cnt;

always @(posedge clk) begin
    if (reset) begin
        dma_cnt <= 4'd0;
    end
    else begin
        if (ce_pix && (hcount == PIXELS_PER_LINE - 1)) begin
            dma_cnt <= 4'd0;
        end
        if (cpu_ce && (SC == 2'b10) && (dma_cnt < 4'd8)) begin
            linebuf[dma_cnt[2:0]] <= data_in;
            colbuf [dma_cnt[2:0]] <= colour_in;
            conbuf [dma_cnt[2:0]] <= con;
            dma_cnt <= dma_cnt + 4'd1;
        end
    end
end

// ---------------------------------------------------------------------------
// Pixel shifter
// ---------------------------------------------------------------------------
reg [7:0] shift_reg;
reg [2:0] shift_col;
reg       shift_con;
wire in_active = line_displayed && (hcount >= ACTIVE_START) && (hcount < ACTIVE_END);

always @(posedge clk) begin
    if (reset) begin
        shift_reg <= 8'd0;
        shift_col <= 3'd0;
        shift_con <= 1'b0;
    end
    else if (ce_pix) begin
        if (in_active) begin
            if (hcount[2:0] == 3'd0) begin
                shift_reg <= linebuf[hcount[5:3] - 3'd5];   // ACTIVE_START/8 == 5
                shift_col <= colbuf [hcount[5:3] - 3'd5];
                shift_con <= conbuf [hcount[5:3] - 3'd5];
            end
            else shift_reg <= {shift_reg[6:0], 1'b0};
        end
        else shift_reg <= 8'd0;
    end
end

reg in_active_d;
always @(posedge clk) begin
    if (reset)       in_active_d <= 1'b0;
    else if (ce_pix) in_active_d <= in_active;
end

// RCA Fig. 4: background fills the active raster outside the bitmap.
wire [2:0] border = (display_enabled && colour_on_seen) ? bg_colour : 3'b000;
assign video = in_raster
                 ? ((display_enabled && in_active_d)
                      ? (shift_con ? (shift_reg[7] ? shift_col : bg_colour)
                                   : (shift_reg[7] ? 3'b111    : 3'b000))
                      : border)
                 : 3'b000;

// Qualify background luminance only after colour is enabled.
assign bckgnd = in_raster && display_enabled && colour_on_seen &&
                !(in_active_d && shift_con && shift_reg[7]);

// CON latched once, for the border: the per-byte conbuf only covers the bitmap.
reg colour_on_seen;
always @(posedge clk) begin
    if (reset)    colour_on_seen <= 1'b0;
    else if (con) colour_on_seen <= 1'b1;
end

// Inside the visible raster (the delayed forms track the shifter's one-pixel lag).
reg in_raster;
always @(posedge clk) begin
    if (reset)       in_raster <= 1'b0;
    else if (ce_pix) in_raster <= (hcount >= H_ACTIVE_START) && (vcount >= VBLANK_END);
end

// ---------------------------------------------------------------------------
// INT/EF timing uses the same lead and DMA phase as cdp1861.v.
// ---------------------------------------------------------------------------
always @(posedge clk) begin
    if (reset) begin
        HSync <= 1'b0; VSync <= 1'b0;
        HBlank <= 1'b1; VBlank <= 1'b1;
        INT <= 1'b0;   EFx <= 1'b0;
    end
    else if (ce_pix) begin
        HSync  <= (hcount >= HSYNC_START) && (hcount < HSYNC_END);
        // VSYNC_START is zero; an explicit unsigned lower-bound comparison is
        // always true. The 1861 still needs both bounds for its 254..257 pulse.
        VSync  <= (vcount < VSYNC_END);
        HBlank <= (hcount < H_ACTIVE_START);
        VBlank <= (vcount < VBLANK_END);

        INT <= display_enabled &&
               (((vcount == INT_START - 1)     && (hcount >= 112 - INT_LEAD)) ||
                ((vcount >= INT_START) && (vcount < DISPLAY_START) &&
                 !((vcount == DISPLAY_START - 1) && (hcount >= 112 - INT_LEAD))));

        EFx <= display_enabled &&
               ((((vcount == EFX_TOP_START - 1) && (hcount >= 112 - EFX_LEAD)) ||
                 ((vcount >= EFX_TOP_START) && (vcount < DISPLAY_START) &&
                  !((vcount == DISPLAY_START - 1) && (hcount >= 112 - EFX_LEAD)))) ||
                (((vcount == EFX_BOT_START - 1) && (hcount >= 112 - EFX_LEAD)) ||
                 ((vcount >= EFX_BOT_START) && (vcount < DISPLAY_END) &&
                  !((vcount == DISPLAY_END - 1) && (hcount >= 112 - EFX_LEAD)))));
    end
end

assign csync    = ~(HSync ^ VSync);
assign video_de = ~(VBlank | HBlank);

// Capture-only bitmap window; video_de covers the full active raster.
reg bitmap_de_r, bitmap_hblank_r, bitmap_vblank_r;
always @(posedge clk) begin
    if (reset) begin
        bitmap_de_r     <= 1'b0;
        bitmap_hblank_r <= 1'b1;
        bitmap_vblank_r <= 1'b1;
    end
    else if (ce_pix) begin
        bitmap_de_r     <= line_displayed &&
                           (hcount >= DE_START) && (hcount < DE_END);
        bitmap_hblank_r <= (hcount < DE_START) || (hcount >= DE_END);
        bitmap_vblank_r <= !line_displayed;
    end
end
assign bitmap_de     = bitmap_de_r;
assign bitmap_hblank = bitmap_hblank_r;
assign bitmap_vblank = bitmap_vblank_r;

endmodule

`default_nettype wire
