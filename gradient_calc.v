module gradiant_calc (
    input [7:0] p0,
    input [7:0] p1,
    input [7:0] p2,
    input [7:0] p3,
    input [7:0] p4,
    input [7:0] p5,
    input [7:0] p6,
    input [7:0] p7,
    input [7:0] p8,

    output reg [11:0] gx,
    output reg [11:0] gy
);

    always @(*)
    begin

        gx = (p2 + (p5 << 1) + p8) - (p0 + (p3 << 1) + p6);
        gy = (p0 + (p1 << 1) + p2) - (p6 + (p7 << 1) + p8);
        
    end




endmodule
