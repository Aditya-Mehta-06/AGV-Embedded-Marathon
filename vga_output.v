module vga_output
(
    input pclk_vga,
    input rst_n,
    input [15:0] pixel_data,
    input active_video,
    input hsync,
    input vsync,
    input [8:0] h_count,
    input [8:0] v_count,

    output [8:0] addr_row,
    output [8:0] addr_col,

    output reg [4:0] vga_r,
    output reg [5:0] vga_g,
    output reg [4:0] vga_b,
    output reg vga_hsync,
    output reg vga_vsync,
    output reg rd
);

    always @(*)
    begin
        if(!rst_n)
        begin

            vga_r = 0;
            vga_g = 0;
            vga_b = 0;
            vga_hsync = 0;
            vga_vsync = 0;
            addr_col = 0;
            addr_row = 0;
        end

        else if(active_video)
        begin

            vga_r = pixel_data[15:11];
            vga_g = pixel_data[10:5];
            vga_b = pixel_data[4:0];
            addr_col = h_count;
            addr_row = v_count;

        end

        else
        begin
            vga_r = 0;
            vga_g = 0;
            vga_b = 0;
            vga_hsync = 0;
            vga_vsync = 0;
            addr_col = 0;
            addr_row = 0;
        end

        vga_hsync = hsync;
        vga_vsync = vsync;
    end

    always @(posedge pclk_vga or negedge rst_n )
    begin
        if(!rst_n)
        begin
            rd <= 0;
        end

        else if(active_video)
        begin
            rd <= 1;
        end

        else
        begin
            rd <= 0;
        end
    end



endmodule
