module gray_scale
(
    input [15:0] pixel_data,    //wdata from capture

    output [7:0] gray_pixel_data    // input to line buffer
);

    wire [15:0] red_8 = {8'b0, pixel_data[15:11], pixel_data[15:13]};   // expanded to prevent overflow
    wire [15:0] green_8 = {8'b0, pixel_data[10:5], pixel_data[10:9]};
    wire [15:0] blue_8 = {8'b0, pixel_data[4:0], pixel_data[4:2]};

    wire [15:0] red_term   = (red_8 << 6) + (red_8 << 3) + (red_8 << 2) + red_8;    // 77*r
    wire [15:0] green_term = (green_8 << 7) + (green_8 << 4) + (green_8 << 2) + (green_8 << 1); // 150*g
    wire [15:0] blue_term  = (blue_8 << 5) - (blue_8 << 1) - blue_8;   // 29*g

    wire [15:0] sum = red_term + green_term + blue_term;

    assign gray_pixel_data = sum[15:8];  // sum/256

endmodule
