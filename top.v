`timescale 1ns/1ps
module top #(
    // start-up timing (50 MHz cycles). Shrink in simulation.
    parameter RESET_CYCLES      = 50_000,   // 1 ms camera hardware reset
    parameter WAIT_CYCLES       = 100_000,  // 2 ms before SCCB
    parameter [23:0] SCCB_RESET_DELAY = 24'd10000000   // wait after COM7 soft reset
)(
    input  wire        rst_n,       // active low
    input  wire        clk_cam,    
    input  wire        clk_vga,
    input  wire        CLK_50MHz,

    // OV7670
    output wire        cam_xclk,
    input  wire        cam_pclk,
    input  wire        cam_vsync,
    input  wire        cam_href,
    input  wire [7:0]  cam_data,
    output wire        cam_reset_n,
    output wire        cam_pwdn,
    output wire        cam_sioc,
    inout  wire        cam_siod,

    // VGA (resistor DAC)
    output wire [4:0]  vga_r,
    output wire [5:0]  vga_g,
    output wire [4:0]  vga_b,
    output wire        vga_hs,
    output wire        vga_vs
);
    assign cam_xclk = clk_cam;
    wire sys_rst_n  = rst_n;
    wire rst_n_vga  = rst_n;

    // ------------------------------------------ camera power-up + SCCB handshake
    wire sccb_start, sccb_done, cam_ready;

    init_ctrl #(
        .RESET_CYCLES (RESET_CYCLES),
        .WAIT_CYCLES  (WAIT_CYCLES)
    ) u_init (
        .clk         (CLK_50MHz),
        .rst_n       (sys_rst_n),
        .sccb_done   (sccb_done),
        .cam_reset_n (cam_reset_n),
        .cam_pwdn    (cam_pwdn),
        .sccb_start  (sccb_start),
        .cam_ready   (cam_ready)
    );

    sccb_cfg #(.DELAY_COUNT(SCCB_RESET_DELAY)) u_sccb (
        .clk_50MHz (CLK_50MHz),
        .rst_n (sys_rst_n),
        .start (sccb_start),
        .done  (sccb_done),
        .sioc  (cam_sioc),
        .siod  (cam_siod)
    );

    // ------------------------------------------------------ capture + decimation
    wire        fb_we;
    wire [14:0] fb_waddr;
    wire [15:0] fb_wdata;
    wire [4:0]  frame_cnt;

    cam_capture u_cap (
        .pclk      (cam_pclk),
        .enable    (cam_ready),
        .vsync     (cam_vsync),
        .href      (cam_href),
        .din       (cam_data),
        .we        (fb_we),
        .waddr     (fb_waddr),
        .wdata     (fb_wdata),
        .frame_cnt (frame_cnt)
    );

    // ------------------------------------------------------------ frame buffer
    wire [14:0] fb_raddr;
    wire [15:0] fb_rdata;

    frame_buffer u_fb (
        .wclk (cam_pclk), .we(fb_we), .waddr(fb_waddr), .wdata(fb_wdata),
        .rclk (clk_vga),  .raddr(fb_raddr), .rdata(fb_rdata)
    );

    // --------------------------------------------------------------------- VGA
    vga_ctrl u_vga (
        .clk    (clk_vga),
        .rst_n  (rst_n_vga),
        .pix    (fb_rdata),
        .raddr  (fb_raddr),
        .vga_r  (vga_r),
        .vga_g  (vga_g),
        .vga_b  (vga_b),
        .vga_hs (vga_hs),
        .vga_vs (vga_vs),
        .vga_de ()
    );


endmodule
