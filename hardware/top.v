`timescale 1ns/1ps
module top #(
    // start-up timing (50 MHz cycles). Shrink in simulation.
    parameter RESET_CYCLES      = 50_000,   // 1 ms camera hardware reset
    parameter WAIT_CYCLES       = 100_000,  // 2 ms before SCCB
    parameter [23:0] SCCB_RESET_DELAY = 24'd10000000   // wait after COM7 soft reset
)(
    //input  wire        rst_n,       // active low
    //input  wire        clk_cam,    
    //input  wire        clk_vga,
    input wire CLK_50MHz,
    input wire key_n,   //physical key KEY[0] present in fpga, 0 when pressed
    input wire key1_n,   // KEY[1], released = sobel mode
    output wire [2:0] LED,


    // OV7670
    output wire        cam_xclk,
    input  wire        cam_pclk,
    input  wire        cam_vsync,
    input  wire        cam_href,
    input  wire [7:0]  cam_data,
    output wire        cam_reset_n,
    output wire        cam_sioc,
    inout  wire        cam_siod,

    // VGA (resistor DAC)
    output wire [4:0]  vga_r,
    output wire [5:0]  vga_g,
    output wire [4:0]  vga_b,
    output wire        vga_hs,
    output wire        vga_vs
);
    // assign cam_xclk = clk_cam;
    // wire sys_rst_n  = rst_n;
    // wire rst_n_vga  = rst_n;

    //hardware implementation
    wire clk_vga, pll_locked;

    pll_clocks u_pll (
        .areset(1'b0), 
        .inclk0(CLK_50MHz),
        .c0(cam_xclk), 
        .c1(clk_vga), 
        .locked(pll_locked)
    );

    // power-on reset: held low ~1.3 ms and until the PLL is locked
    reg [15:0] por = 16'd0;
    wire por_done = &por;
    always @(posedge CLK_50MHz) 
        if (!por_done) 
            por <= por + 1'b1;

    reg [1:0] lk = 2'b00;
    always @(posedge CLK_50MHz) 
        lk <= {lk[0], pll_locked & por_done & key_n};

    wire sys_rst_n = lk[1]; //0 when pressed

    reg [1:0] rv = 2'b00;                       // reset for the VGA clock domain
    always @(posedge clk_vga or negedge sys_rst_n)
        if (!sys_rst_n) 
            rv <= 2'b00;
        else
            rv <= {rv[0], 1'b1};

    wire rst_n_vga = rv[1];

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
    wire        cap_we;
    wire [14:0] cap_waddr;
    wire [15:0] cap_wdata;

    cam_capture u_cap (
        .pclk      (cam_pclk),
        .enable    (cam_ready),
        .vsync     (cam_vsync),
        .href      (cam_href),
        .din       (cam_data),
        .we        (cap_we),
        .waddr     (cap_waddr),
        .wdata     (cap_wdata)
    );

    // ------------------------------------------------------------ frame buffer
    wire [14:0] fb_raddr;
    wire [15:0] fb_rdata;

    wire fb_we;
    wire [14:0] fb_waddr;
    wire [15:0] fb_wdata;

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

    // --------------------------------------------------------------------- sobel
    wire [7:0] gray, p0, p1, p2, p3, p4, p5, p6, p7, p8;
    wire signed [11:0] gx, gy;
    wire [10:0] mag;
    wire        s_we;
    wire [15:0] s_wdata;
    wire [14:0] s_waddr;

    gray_scale g0 (
        .pixel_data(cap_wdata),
        .gray_pixel_data(gray)
    );

    sobel_line_buffer lb0 ( 
        .pclk(cam_pclk), .gray_pixel_data(gray), .we(cap_we), .waddr(cap_waddr),
        .we_buff(s_we), .wdata_buff(s_wdata), .waddr_buff(s_waddr),
        .p0(p0), .p1(p1), .p2(p2), .p3(p3), .p4(p4), .p5(p5), .p6(p6), .p7(p7), .p8(p8),
        .mag(mag)
    );

    gradiant_calc gc0 (
        .p0(p0), .p1(p1), .p2(p2), .p3(p3), .p4(p4), .p5(p5), .p6(p6), .p7(p7), .p8(p8),
        .gx(gx), .gy(gy), .mag(mag)
    );


   reg [1:0] em = 2'b00;
   always @(posedge cam_pclk)   //synchronizer
    em <= {em[0], key1_n};

   wire sobel_mode = em[1];

   assign fb_we = sobel_mode ? s_we : cap_we;
   assign fb_waddr = sobel_mode ? s_waddr : cap_waddr;
   assign fb_wdata = sobel_mode ? s_wdata : cap_wdata;

   // --------------------------------------------------------------------- LED
   // on when booting up, pll not locked, reset pressed
   assign LED[0] = ~sys_rst_n;

    // camera active indication
    reg [21:0] cnt_6m = 22'd0;
    always @(posedge cam_pclk or negedge sys_rst_n)
        if (!sys_rst_n) 
            cnt_6m <= 22'd0;
        else
            cnt_6m <= cnt_6m + 1'b1;

    assign LED[1] = cnt_6m[21]; // this LED shows that pclk is active

    // cga active indication
    reg [23:0] cnt_25m = 24'd0; 
    always @(posedge clk_vga or negedge sys_rst_n)   // technically it shows that vga pll is active
    if (!sys_rst_n) 
            cnt_25m <= 24'd0;
    else
        cnt_25m <= cnt_25m + 1'b1;

    assign LED[2] = cnt_25m[23];





endmodule
