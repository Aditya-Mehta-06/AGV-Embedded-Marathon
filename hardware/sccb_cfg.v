`timescale 1ns/1ps
module sccb_cfg #(
    parameter [23:0] DELAY_COUNT = 24'd10000000
)(
    input  wire clk_50MHz,        // 50 MHz
    input  wire rst_n,
    input  wire start,
    output wire done,
    output wire sioc,
    inout  wire siod
);
    wire reset = ~rst_n;

    wire       c_start, c_busy, c_done, cfg_done, siod_o;
    wire [6:0] dev_addr;
    wire [7:0] reg_addr, reg_data;

    sccb_configure #(.DELAY_COUNT(DELAY_COUNT)) u_cfg (
        .clk_50MHz    (clk_50MHz),
        .reset        (reset),
        .done         (c_done),
        .busy         (c_busy),
        .start_config (start),
        .start        (c_start),
        .config_done  (cfg_done),
        .dev_addr     (dev_addr),
        .reg_addr     (reg_addr),
        .reg_data     (reg_data)
    );

    sccb_controller u_ctl (
        .clk_50MHz   (clk_50MHz),
        .reset       (reset),
        .start       (c_start),
        .device_addr (dev_addr),
        .reg_addr    (reg_addr),
        .reg_data    (reg_data),
        .sioc        (sioc),
        .siod        (siod_o),
        .busy        (c_busy),
        .done        (c_done)
    );

    assign siod = siod_o ? 1'bz : 1'b0; //ACK bit

    // turn config_done into a one-cycle pulse
    reg cfg_done_d;
    always @(posedge clk_50MHz or negedge rst_n)
    begin
        if (!rst_n) cfg_done_d <= 1'b0;
        else        cfg_done_d <= cfg_done;
    end
    assign done = cfg_done & ~cfg_done_d;
endmodule
