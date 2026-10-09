module top_vga (
    input pclk_vga,
    input reset,
    input [15:0] pixel_data,

    output [4:0] vga_r,
    output [5:0] vga_g,
    output [4:0] vga_b,
    output vga_hsync,
    output vga_vsync
);

    wire hsync;
    wire vsync;
    wire active_video;

    vga_timing vga_timing_inst (
        .pclk_vga(pclk_vga),
        .reset(reset),
        .hsync(hsync),
        .vsync(vsync),
        .active_video(active_video)
    );

    vga_output vga_output_inst (
        .pixel_data(pixel_data),
        .active_video(active_video),
        .hsync(hsync),
        .vsync(vsync),
        .vga_r(vga_r),
        .vga_g(vga_g),
        .vga_b(vga_b),
        .vga_hsync(vga_hsync),
        .vga_vsync(vga_vsync)
    );

endmodule
