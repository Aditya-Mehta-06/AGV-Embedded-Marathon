module gray_scale
(
    input [15:0] pixel_data,
    input pixel_valid,

    output reg [7:0] gray_pixel_data,
    output reg gray_pixel_data_vaild

);

    reg [7:0] red_8, green_8, blue_8;

    always @(*)
    begin

        red_8 = {pixel_data[15:11], pixel_data[15:13]};
        green_8 = {pixel_data[10:5], pixel_data[10:9]};
        blue_8 = {pixel_data[4:0], pixel_data[4:2]};

        if(pixel_valid)
        begin
            gray_pixel_data = (77 * red_8 + 150 * green_8 + 29 * blue_8) >> 8;
            gray_pixel_data_vaild = 1'b1;
        end

        else
        begin
            gray_pixel_data = 0;
            gray_pixel_data_vaild = 0;
        end
    end

endmodule
