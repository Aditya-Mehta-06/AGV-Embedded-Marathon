module vga_output
(
    input [15:0] pixel_data,
    input active_video,
    input hsync,
    input vsync,

    output [4:0] vga_r,
    output [5:0] vga_g,
    output [4:0] vga_b,
    output vga_hsync,
    output vga_vsync
);

    assign vga_r = active_video ? pixel_data[15:11] : 5'b0;

    assign vga_g = active_video ? pixel_data[10:5] : 6'b0;

    assign vga_b = active_video ? pixel_data[4:0] : 5'b0;


    assign vga_hsync = hsync;

    assign vga_vsync = vsync;



endmodule
