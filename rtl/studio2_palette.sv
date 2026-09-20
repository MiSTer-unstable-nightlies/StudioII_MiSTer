module studio2_palette
(
	input             clk_sys,
	input       [1:0] machine,
	input       [2:0] video,
	input             video_bg,
	input       [1:0] vis_index,
	input       [2:0] studio2_select,
	input       [2:0] studio3_select,
	input       [2:0] visicom_select,
	input             studio2_download,
	input             studio3_download,
	input             visicom_download,
	input             ioctl_wr,
	input      [24:0] ioctl_addr,
	input       [7:0] ioctl_data,
	output reg [23:0] rgb
);

localparam [127:0] STUDIO2_ORIGINAL = 128'hFFFFFFAAAAAA55555500000000000000;
localparam [127:0] STUDIO2_AMBER    = 128'hFFBF5AD885186B390000000000000000;
localparam [127:0] STUDIO2_GREEN    = 128'h8FFF6352C9391F681700000000000000;
localparam [127:0] STUDIO2_INVERTED = 128'h000000555555AAAAAAFFFFFF00000000;

localparam [127:0] VISICOM_BALANCED         = 128'hD14C38B9B43D5A93D511320C00000000;
localparam [127:0] VISICOM_BOXART_ADJUSTED  = 128'hBC674AC4AD39678CC621391A00000000;
localparam [127:0] VISICOM_EMMA02           = 128'hFF7070D0FF7070D0FF00400000000000;
localparam [127:0] VISICOM_FLIP             = 128'hC74C32B5A443627FB61F361800000000;
localparam [127:0] VISICOM_MAME             = 128'hEF454AB9C42FAFDFE400400000000000;
localparam [127:0] VISICOM_MANUALS_ADJUSTED = 128'hC54A32B9B4384D91B51B351100000000;
localparam [127:0] VISICOM_NICOLE_EXPRESS   = 128'hD52E18AFB72B2688F200260000000000;

localparam [191:0] STUDIO3_ORIGINAL = {
	24'hFFFFFF, 24'hFFFF00, 24'hFF00FF, 24'hFF0000,
	24'h00FFFF, 24'h00FF00, 24'h0000FF, 24'h000000
};
localparam [191:0] STUDIO3_PROTOTYPE = {
	24'hD8D5B5, 24'hD6A328, 24'hB56B73, 24'hD95718,
	24'h2A9DA2, 24'h126044, 24'h123C62, 24'h000000
};
localparam [191:0] STUDIO3_WARM = {
	24'hE6DFC8, 24'hD7B646, 24'hB6779F, 24'hC95A42,
	24'h5BB7B1, 24'h52965B, 24'h325FA7, 24'h080706
};
localparam [191:0] STUDIO3_COOL = {
	24'hDCE7F5, 24'hC9C65A, 24'hA479C2, 24'hCF596E,
	24'h54BFC8, 24'h3F9C83, 24'h3B78C6, 24'h05080C
};

// Commit only complete files. Extra bytes are ignored, so common 24-byte
// RGB888 .pal files remain accepted without coupling colour changes to reset.
reg [127:0] studio2_stage = STUDIO2_ORIGINAL;
reg [127:0] studio2_custom = STUDIO2_ORIGINAL;
always @(posedge clk_sys) begin
	if (studio2_download && ioctl_wr && (ioctl_addr < 25'd16)) begin
		studio2_stage <= {studio2_stage[119:0], ioctl_data};
		if (ioctl_addr == 25'd15)
			studio2_custom <= {studio2_stage[119:0], ioctl_data};
	end
end

reg [127:0] visicom_stage = VISICOM_BALANCED;
reg [127:0] visicom_custom = VISICOM_BALANCED;
always @(posedge clk_sys) begin
	if (visicom_download && ioctl_wr) begin
		case (ioctl_addr)
		25'd0:  visicom_stage[127:120] <= ioctl_data;
		25'd1:  visicom_stage[119:112] <= ioctl_data;
		25'd2:  visicom_stage[111:104] <= ioctl_data;
		25'd3:  visicom_stage[103:96]  <= ioctl_data;
		25'd4:  visicom_stage[95:88]   <= ioctl_data;
		25'd5:  visicom_stage[87:80]   <= ioctl_data;
		25'd6:  visicom_stage[79:72]   <= ioctl_data;
		25'd7:  visicom_stage[71:64]   <= ioctl_data;
		25'd8:  visicom_stage[63:56]   <= ioctl_data;
		25'd9:  visicom_stage[55:48]   <= ioctl_data;
		25'd10: visicom_stage[47:40]   <= ioctl_data;
		25'd11: visicom_stage[39:32]   <= ioctl_data;
		25'd15: visicom_custom <= visicom_stage;
		default: ;
		endcase
	end
end

reg [191:0] studio3_stage = STUDIO3_ORIGINAL;
reg [191:0] studio3_custom = STUDIO3_ORIGINAL;
reg  [15:0] studio3_byte_stage = 16'h0000;
always @(posedge clk_sys) begin
	if (studio3_download && ioctl_wr) begin
		case (ioctl_addr)
		25'd0, 25'd3, 25'd6, 25'd9, 25'd12, 25'd15, 25'd18, 25'd21:
			studio3_byte_stage[15:8] <= ioctl_data;
		25'd1, 25'd4, 25'd7, 25'd10, 25'd13, 25'd16, 25'd19, 25'd22:
			studio3_byte_stage[7:0] <= ioctl_data;
		25'd2:  studio3_stage[23:0]    <= {studio3_byte_stage, ioctl_data};
		25'd5:  studio3_stage[47:24]   <= {studio3_byte_stage, ioctl_data};
		25'd8:  studio3_stage[71:48]   <= {studio3_byte_stage, ioctl_data};
		25'd11: studio3_stage[95:72]   <= {studio3_byte_stage, ioctl_data};
		25'd14: studio3_stage[119:96]  <= {studio3_byte_stage, ioctl_data};
		25'd17: studio3_stage[143:120] <= {studio3_byte_stage, ioctl_data};
		25'd20: studio3_stage[167:144] <= {studio3_byte_stage, ioctl_data};
		25'd23: begin
			studio3_stage[191:168] <= {studio3_byte_stage, ioctl_data};
			studio3_custom <= {studio3_byte_stage, ioctl_data, studio3_stage[167:0]};
		end
		default: ;
		endcase
	end
end

reg [127:0] studio2_palette;
always @(*) begin
	case (studio2_select)
	3'd0:    studio2_palette = STUDIO2_ORIGINAL;
	3'd1:    studio2_palette = STUDIO2_AMBER;
	3'd2:    studio2_palette = STUDIO2_GREEN;
	3'd3:    studio2_palette = STUDIO2_INVERTED;
	3'd4:    studio2_palette = studio2_custom;
	default: studio2_palette = STUDIO2_ORIGINAL;
	endcase
end

reg [127:0] visicom_palette;
always @(*) begin
	case (visicom_select)
	3'd0:    visicom_palette = VISICOM_BALANCED;
	3'd1:    visicom_palette = VISICOM_BOXART_ADJUSTED;
	3'd2:    visicom_palette = VISICOM_EMMA02;
	3'd3:    visicom_palette = VISICOM_FLIP;
	3'd4:    visicom_palette = VISICOM_MAME;
	3'd5:    visicom_palette = VISICOM_MANUALS_ADJUSTED;
	3'd6:    visicom_palette = VISICOM_NICOLE_EXPRESS;
	3'd7:    visicom_palette = visicom_custom;
	default: visicom_palette = VISICOM_BALANCED;
	endcase
end

function [23:0] studio3_lookup;
	input [191:0] palette;
	input [2:0] index;
	begin
		case (index)
		3'd0:    studio3_lookup = palette[23:0];
		3'd1:    studio3_lookup = palette[47:24];
		3'd2:    studio3_lookup = palette[71:48];
		3'd3:    studio3_lookup = palette[95:72];
		3'd4:    studio3_lookup = palette[119:96];
		3'd5:    studio3_lookup = palette[143:120];
		3'd6:    studio3_lookup = palette[167:144];
		default: studio3_lookup = palette[191:168];
		endcase
	end
endfunction

function [7:0] studio3_bg_half;
	input [7:0] color;
	begin
		studio3_bg_half = (color == 8'hFF) ? 8'h80 : {1'b0, color[7:1]};
	end
endfunction

wire [23:0] studio2_rgb = video[2] ? studio2_palette[127:104]
	                                       : studio2_palette[55:32];
reg [23:0] visicom_rgb;
always @(*) begin
	case (vis_index)
	2'd0:    visicom_rgb = visicom_palette[55:32];
	2'd1:    visicom_rgb = visicom_palette[79:56];
	2'd2:    visicom_rgb = visicom_palette[103:80];
	default: visicom_rgb = visicom_palette[127:104];
	endcase
end

reg [191:0] studio3_palette;
always @(*) begin
	case (studio3_select)
	3'd0:    studio3_palette = STUDIO3_ORIGINAL;
	3'd1:    studio3_palette = STUDIO3_PROTOTYPE;
	3'd2:    studio3_palette = STUDIO3_WARM;
	3'd3:    studio3_palette = STUDIO3_COOL;
	3'd4:    studio3_palette = studio3_custom;
	default: studio3_palette = STUDIO3_ORIGINAL;
	endcase
end

wire [23:0] studio3_selected = studio3_lookup(studio3_palette, video);
wire [23:0] studio3_rgb = video_bg
	? {studio3_bg_half(studio3_selected[23:16]),
	   studio3_bg_half(studio3_selected[15:8]),
	   studio3_bg_half(studio3_selected[7:0])}
	: studio3_selected;

always @(*) begin
	case (machine)
	2'd0:    rgb = studio2_rgb;
	2'd3:    rgb = visicom_rgb;
	default: rgb = studio3_rgb;
	endcase
end

endmodule
