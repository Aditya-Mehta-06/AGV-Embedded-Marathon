module top_module
(
    input wire clk_50MHz,
    input wire pclk_camera,
    input wire pclk_vga,
    input wire rst_n,

    // OV7670 camera interface
    input wire cam_vsync,
    input wire cam_href,
    input wire [7:0] cam_data,
    output wire cam_sioc,
    inout wire cam_siod,

    // VGA output
    output wire [4:0] vga_r,
    output wire [5:0] vga_g,
    output wire [4:0] vga_b,
    output wire vga_hsync,
    output wire vga_vsync
);

    // Camera capture signals
    wire [15:0] captured_pixel;
    wire pixel_valid;
    wire frame_start;

    // Frame buffer signals
    wire [15:0] display_pixel;
    wire [8:0] addr_row;
    wire [8:0] addr_col;
    wire rd;

    // SCCB configuration signals
    wire config_done;
    wire sccb_busy;
    wire sccb_error;

    // Capture pixels from OV7670
    ov7670_capture camera_capture
    (
        .pclk(pclk_camera),
        .reset(~rst_n),
        .vsync(cam_vsync),
        .href(cam_href),
        .camera_data(cam_data),
        .pixel_data(captured_pixel),
        .pixel_valid(pixel_valid),
        .frame_start(frame_start)
    );

    // Store captured pixels and provide pixels for VGA
    buffer_module frame_buffer
    (
        .pclk(pclk_camera),
        .rst_n(rst_n),
        .pixel_data(captured_pixel),
        .pixel_valid(pixel_valid),
        .addr_col(addr_col),
        .addr_row(addr_row),
        .rd(rd),
        .rd_en(),
        .frame_data(display_pixel)
    );

    // Generate VGA timing and output RGB signals
    top_vga vga_display
    (
        .pclk_vga(pclk_vga),
        .rst_n(rst_n),
        .pixel_data(display_pixel),
        .addr_row(addr_row),
        .addr_col(addr_col),
        .vga_r(vga_r),
        .vga_g(vga_g),
        .vga_b(vga_b),
        .vga_hsync(vga_hsync),
        .vga_vsync(vga_vsync),
        .rd(rd)
    );

    // Configure OV7670 registers through SCCB
    sccb_top camera_config
    (
        .clk_50MHz(clk_50MHz),
        .reset(~rst_n),
        .sioc(cam_sioc),
        .siod(cam_siod),
        .config_done(config_done),
        .busy(sccb_busy),
        .error(sccb_error)
    );

endmodule

