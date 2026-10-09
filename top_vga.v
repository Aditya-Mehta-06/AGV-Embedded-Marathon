module top_vga (
    input pclk_vga,
    input rst_n,
    input [15:0] pixel_data,

    output [8:0] addr_row,
    output [8:0] addr_col,
    output [4:0] vga_r,
    output [5:0] vga_g,
    output [4:0] vga_b,
    output vga_hsync,
    output vga_vsync,
    output rd
);

    wire hsync;
    wire vsync;
    wire active_video;
    wire [8:0] h_count,
    wire [8:0] v_count;

    vga_timing vga_timing_inst (
        .pclk_vga(pclk_vga),
        .rst_n(rst_n),
        .h_count(h_count),
        .v_count(v_count),
        .hsync(hsync),
        .vsync(vsync),
        .active_video(active_video)
    );

    vga_output vga_output_inst (
        .pclk_vga(pclk_vga),
        .rst_n(rst_n),
        .pixel_data(pixel_data),
        .active_video(active_video),
        .hsync(hsync),
        .vsync(vsync),
        .h_count(h_count),
        .v_count(v_count),
        .addr_row(addr_row),
        .addr_col(addr_col),
        .vga_r(vga_r),
        .vga_g(vga_g),
        .vga_b(vga_b),
        .vga_hsync(vga_hsync),
        .vga_vsync(vga_vsync),
        .rd(rd)
    );

endmodule
