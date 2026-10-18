// HPS inputs are driven by emu_reset_test. FPGA clocks share the test clock.
module pll (
    input refclk, rst,
    output outclk_0, outclk_1
);
assign outclk_0 = refclk;
assign outclk_1 = refclk;
endmodule

module hps_io #(parameter CONF_STR = "", CONF_STR_BRAM = 0) (
    input clk_sys,
    inout [45:0] HPS_BUS,
    inout [35:0] EXT_BUS,
    inout [21:0] gamma_bus,
    output reg forced_scandoubler = 0,
    output reg ioctl_download = 0,
    output reg [15:0] ioctl_index = 0,
    output reg ioctl_wr = 0,
    output reg [24:0] ioctl_addr = 0,
    output reg [7:0] ioctl_dout = 0,
    output reg [1:0] buttons = 0,
    output reg [127:0] status = 0,
    input [127:0] status_in,
    input status_set,
    input [15:0] status_menumask,
    output reg [10:0] ps2_key = 0,
    output reg [31:0] joystick_0 = 0, joystick_1 = 0,
    output reg [15:0] joystick_l_analog_0 = 0, joystick_r_analog_0 = 0,
    output reg [15:0] joystick_l_analog_1 = 0, joystick_r_analog_1 = 0
);
endmodule
