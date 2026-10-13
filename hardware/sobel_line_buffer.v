module sobel_line_buffer
(
    input pclk,
    input [7:0] gray_pixel_data,
    input we,   //output of capture we
    input [14:0] waddr,    //output from capture

    output we_buff,   //write enabled output to buffer
    output [15:0] wdata_buff,   //output to buffer
    output [14:0] waddr_buff,

    output [7:0] p0, p1, p2, p3, p4, p5, p6, p7, p8,

    input [10:0] mag
);

reg [7:0] lb [0:321];
reg [7:0] col = 8'd0;   // 0-159
reg [6:0] row = 7'd0;   // 0-119

assign p0 = lb[0], p1 = lb[1], p2 = lb[2];
assign p3 = lb[160], p4 = lb[161], p5 = lb[162];
assign p6 = lb[320], p7 = lb[321], p8 = gray_pixel_data;

integer i;

initial
begin
    for(i=0; i<322; i = i + 1)
    begin
        lb[i] = 8'b0;
    end
end

//updating line bufffer elements
always @(posedge pclk)
begin
    if(we)
    begin
        lb[321] <= gray_pixel_data;
        for(i=0; i<321; i = i + 1)
            lb[i] <= lb[i+1];
    end
end

wire [7:0] x = (waddr == 15'd0) ? 8'd0 : col;   //to track the current pixel, row/col track the next pixel
wire [6:0] y = (waddr == 15'd0) ? 7'd0 : row;   //this also initializes the start of the frame  

// to track position of CURRENT pixel
always @(posedge pclk) 
begin
    if (we) 
    begin
        if (x == 8'd159) 
        begin 
            col <= 8'd0;
            row <= y + 7'd1; 
        end
        else
        begin
            col <= x + 8'd1;
            row <= y;
        end

    end
end

wire can_write = (x >= 8'd2) && (y >= 7'd2);      // full 3x3 window inside the image

assign we_buff = we & can_write;
assign waddr_buff = waddr - 15'd161;

wire [7:0] e = (mag > 11'd255) ? 8'd255 : mag[7:0];
assign wdata_buff = {e[7:3], e[7:2], e[7:3]};   // grey using rgb magnitudes


endmodule