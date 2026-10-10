`timescale 1ns/1ps
module vga_ctrl (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [15:0] pix,
    output reg  [14:0] raddr,
    output reg  [4:0]  vga_r,
    output reg  [5:0]  vga_g,
    output reg  [4:0]  vga_b,
    output reg         vga_hs,
    output reg         vga_vs,
    output reg         vga_de
);
    localparam H_ACT = 640, H_FP = 16, H_SYNC = 96, H_BP = 48, H_TOT = 800;
    localparam V_ACT = 480, V_FP = 10, V_SYNC = 2,  V_BP = 33, V_TOT = 525;

    reg [9:0] hcnt, vcnt;

    always @(posedge clk or negedge rst_n) 
    begin
        if (!rst_n) 
        begin
            hcnt <= 10'd0; vcnt <= 10'd0;
        end 
        else if (hcnt == H_TOT-1) 
        begin
            hcnt <= 10'd0;
            vcnt <= (vcnt == V_TOT-1) ? 10'd0 : vcnt + 1'b1;
        end 
        else
            hcnt <= hcnt + 1'b1;
    end

    wire active = (hcnt < H_ACT) && (vcnt < V_ACT);
    wire hs_n   = ~((hcnt >= H_ACT + H_FP) && (hcnt < H_ACT + H_FP + H_SYNC));  // active low
    wire vs_n   = ~((vcnt >= V_ACT + V_FP) && (vcnt < V_ACT + V_FP + V_SYNC));  // active low


    wire [14:0] xd     = {7'd0, hcnt[9:2]}; // trick to get same address for 4 consecutive pixels
    wire [14:0] yd     = {7'd0, vcnt[9:2]};
    wire [14:0] addr_c = (yd << 7) + (yd << 5) + xd;    // = yd*160 + xd, yd*160 = yd*128 + yd*32

    reg de1, //display in active area
        hs1, //hsync is on for VGA
        vs1, //vsync is on for VGA
        de2, //store previous clock data
        hs2, 
        vs2;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            raddr <= 15'd0;
            de1 <= 1'b0; hs1 <= 1'b1; vs1 <= 1'b1;
            de2 <= 1'b0; hs2 <= 1'b1; vs2 <= 1'b1;
            vga_r <= 5'd0; vga_g <= 6'd0; vga_b <= 5'd0;
            vga_hs <= 1'b1; vga_vs <= 1'b1; vga_de <= 1'b0;
        end 
        else 
        begin
            // stage 1: address to RAM
            raddr <= active ? addr_c : 15'd0;
            de1 <= active; 
            hs1 <= hs_n; 
            vs1 <= vs_n;

            // stage 2: RAM data appears (pix) alongside de2/hs2/vs2
            de2 <= de1;    
            hs2 <= hs1;  
            vs2 <= vs1;

            // stage 3: output registers
            vga_r  <= de2 ? pix[15:11] : 5'd0;
            vga_g  <= de2 ? pix[10:5]  : 6'd0;
            vga_b  <= de2 ? pix[4:0]   : 5'd0;
            vga_hs <= hs2; 
            vga_vs <= vs2; 
            vga_de <= de2;
        end
    end
endmodule
