`timescale 1ns/1ps

module emu_reset_test;
reg clk = 0;
reg reset = 0;
always #10 clk = !clk;

emu dut (.CLK_50M(clk), .RESET(reset));

task automatic settle;
    repeat (300) @(negedge clk);
endtask

task automatic download(input [15:0] index, input [7:0] data);
    dut.hps_io.ioctl_index = index;
    dut.hps_io.ioctl_addr = 0;
    dut.hps_io.ioctl_download = 1;
    repeat (2) @(negedge clk);
    dut.hps_io.ioctl_wr = 1;
    dut.hps_io.ioctl_dout = data;
    @(negedge clk);
    dut.hps_io.ioctl_wr = 0;
    dut.hps_io.ioctl_download = 0;
    settle();
endtask

task automatic apply_machine(input [1:0] machine);
    dut.hps_io.status[14:13] = machine;
    dut.hps_io.status[15] = 1;
    repeat (2) @(negedge clk);
    dut.hps_io.status[15] = 0;
    settle();
endtask

initial begin
    settle();
    if (!dut.reset) $fatal(1, "Missing BIOS must hold reset");

    // Only one byte: BIOS-free startup must work for short CHIP-8 programs.
    download(16'd3, 8'h12);
    if (dut.rom_loaded || !dut.chip8_active || dut.reset || dut.video_reset)
        $fatal(1, "CHIP-8 must release reset without a BIOS");

    reset = 1;
    @(negedge clk);
    if (!dut.reset || !dut.video_reset) $fatal(1, "Hard reset must dominate CHIP-8");
    reset = 0;
    settle();
    if (dut.reset) $fatal(1, "CHIP-8 must survive hard reset");

    dut.hps_io.status[1] = 1;
    @(negedge clk);
    if (!dut.reset || dut.video_reset) $fatal(1, "CLEAR must preserve raster timing");
    dut.hps_io.status[1] = 0;
    settle();

    apply_machine(2'd3);
    if (dut.chip8_active || !dut.reset)
        $fatal(1, "Visicom must not bypass the BIOS requirement");
    apply_machine(2'd0);
    if (!dut.chip8_active || dut.reset) $fatal(1, "Returning to Studio II must resume CHIP-8");

    dut.hps_io.status[28] = 1;
    @(negedge clk);
    dut.hps_io.status[28] = 0;
    settle();
    if (dut.chip8_active || !dut.reset) $fatal(1, "Unload must restore the BIOS requirement");

    // Interpreter replacement alone must not enter CHIP-8 mode.
    download(16'd4, 8'h00);
    if (dut.chip8_active || !dut.reset) $fatal(1, "Interpreter load must not release reset");
    download(16'd3, 8'h12);
    if (dut.chip8_active || !dut.reset) $fatal(1, "Invalid interpreter must not enable CHIP-8");

    $display("PASS BIOS-free CHIP-8 reset");
    $finish;
end
endmodule
