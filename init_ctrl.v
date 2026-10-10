`timescale 1ns/1ps
module init_ctrl #(
    parameter RESET_CYCLES = 50_000,
    parameter WAIT_CYCLES  = 100_000
)(
    input  wire clk,
    input  wire rst_n,
    input  wire sccb_done,
    output reg  cam_reset_n,
    output reg  cam_pwdn,
    output reg  sccb_start,
    output reg  cam_ready
);
    localparam [2:0] S_RST = 3'd0, S_WAIT = 3'd1, S_START = 3'd2,
                     S_BUSY = 3'd3, S_RUN = 3'd4;

    reg [2:0]  state;
    reg [31:0] cnt;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= S_RST;
            cnt         <= 32'd0;
            cam_reset_n <= 1'b0;
            cam_pwdn    <= 1'b0;      // 0 = normal operation
            sccb_start  <= 1'b0;
            cam_ready   <= 1'b0;
        end else begin
            sccb_start <= 1'b0;
            case (state)
                S_RST: begin
                    cam_reset_n <= 1'b0;
                    if (cnt == RESET_CYCLES-1) begin
                        cnt         <= 32'd0;
                        cam_reset_n <= 1'b1;
                        state       <= S_WAIT;
                    end else cnt <= cnt + 1'b1;
                end
                S_WAIT: begin
                    if (cnt == WAIT_CYCLES-1) begin
                        cnt   <= 32'd0;
                        state <= S_START;
                    end else cnt <= cnt + 1'b1;
                end
                S_START: begin
                    sccb_start <= 1'b1;
                    state      <= S_BUSY;
                end
                S_BUSY: begin
                    if (sccb_done) state <= S_RUN;
                end
                S_RUN: begin
                    cam_ready <= 1'b1;
                end
                default: state <= S_RST;
            endcase
        end
    end
endmodule
