`timescale 1ns/1ps
module cam_capture #(
    parameter OUT_PIX = 19200                 // 160*120
)(
    input  wire        pclk,
    input  wire        enable,                // async to pclk (synchronised inside)
    input  wire        vsync,
    input  wire        href,
    input  wire [7:0]  din,
    output reg         we        = 1'b0,
    output reg  [14:0] waddr     = 15'd0,
    output reg  [15:0] wdata     = 16'd0
);
    reg        en_s1 = 1'b0, en_s2 = 1'b0;
    reg        vsync_d = 1'b0;
    reg        armed = 1'b0, phase = 1'b0;
    reg [7:0]  hi = 8'd0;
    reg [14:0] pix_addr = 15'd0;

    always @(posedge pclk) 
    begin
        en_s1   <= enable;
        en_s2   <= en_s1;
        vsync_d <= vsync;
        we      <= 1'b0;

        if (!en_s2) 
        begin
            armed <= 1'b0; 
            phase <= 1'b0; 
            pix_addr <= 15'd0; 
        end
        else if (vsync) 
        begin                        // VSYNC high = new frame starting
            armed    <= 1'b1;
            phase    <= 1'b0;
            pix_addr <= 15'd0;
        end
        else if (armed) 
        begin
            if (href) 
            begin
                if (!phase) 
                begin                    // first byte: RRRRRGGG
                    hi <= din;
                    phase <= 1'b1;
                end 
                else 
                begin                       // second byte: GGGBBBBB
                    phase <= 1'b0;
                    if (pix_addr < OUT_PIX) 
                    begin
                        we       <= 1'b1;
                        waddr    <= pix_addr;
                        wdata    <= {hi, din};
                        pix_addr <= pix_addr + 1'b1;
                    end
                end
            end
            else phase <= 1'b0;                      // between lines
        end
    end
endmodule