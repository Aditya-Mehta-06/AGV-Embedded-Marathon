module gradiant_calc (
    input  [7:0] p0, p1, p2, p3, p4, p5, p6, p7, p8,

    output [11:0] gx,
    output [11:0] gy,
    output [10:0] mag
);

    // sum can reach upto 1020, therefore the extra bits
    assign gx = $signed({4'b0, p2}) + $signed({3'b0, p5, 1'b0}) + $signed({4'b0, p8})
                     - $signed({4'b0, p0}) - $signed({3'b0, p3, 1'b0}) - $signed({4'b0, p6});

    assign gy = $signed({4'b0, p6}) + $signed({3'b0, p7, 1'b0}) + $signed({4'b0, p8})
                     - $signed({4'b0, p0}) - $signed({3'b0, p1, 1'b0}) - $signed({4'b0, p2});

    wire [11:0] ax = gx[11]? -gx : gx;  //absolute values
    wire [11:0] ay = gy[11]? -gy : gy;

    wire [11:0] sum = ax + ay;
    assign mag = sum[10:0]; //exclude sign bit
   
endmodule
