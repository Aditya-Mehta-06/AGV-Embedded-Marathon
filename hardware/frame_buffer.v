`timescale 1ns/1ps
module frame_buffer #(
    parameter AW    = 15,   //addresswidth - 15 bit number to count till 19200
    parameter DW    = 16,   //datawidth - 16 bits
    parameter DEPTH = 19200 //total pixels
)(
    input  wire          wclk,
    input  wire          we,    // data written only after a pixel is completely constructed
    input  wire [AW-1:0] waddr,
    input  wire [DW-1:0] wdata,

    input  wire          rclk,
    input  wire [AW-1:0] raddr,
    output reg  [DW-1:0] rdata
);
    (* ramstyle = "M9K, no_rw_check" *) reg [DW-1:0] mem [0:DEPTH-1];

    // synthesis translate_off
    integer i;
    initial begin
        for (i = 0; i < DEPTH; i = i + 1) mem[i] = {DW{1'b0}};
        rdata = {DW{1'b0}};
    end
    // synthesis translate_on

    always @(posedge wclk) if (we) mem[waddr] <= wdata;
    always @(posedge rclk) rdata <= mem[raddr];
endmodule
