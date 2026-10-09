module sccb_controller
(
input        clk,
input        reset,
input        start,
input  [7:0] reg_addr,
input  [7:0] reg_data,
output       sioc,
inout        siod,
output       busy,
output reg   done,
output       error
);

reg [7:0] counter;
reg [3:0] present_state;
reg [7:0] tx_byte;
reg [2:0] bit_index;

reg sioc_reg;
reg siod_drive_low;

localparam ST_IDLE       = 4'd0;
localparam ST_START      = 4'd1;
localparam ST_START_HOLD = 4'd2;
localparam ST_DEV_ADDR   = 4'd3;
localparam ST_ACK1       = 4'd4;
localparam ST_REG_ADDR   = 4'd5;
localparam ST_ACK2       = 4'd6;
localparam ST_REG_DATA   = 4'd7;
localparam ST_ACK3       = 4'd8;
localparam ST_STOP_SETUP = 4'd9;
localparam ST_STOP_HIGH  = 4'd10;

wire tick = (counter == 8'd250);

assign siod = siod_drive_low ? 1'b0 : 1'bz;

assign sioc  = sioc_reg;
assign busy  = (present_state != ST_IDLE);
assign error = 1'b0;

always @(posedge clk)
begin
    if (reset)
        counter <= 0;
    else if (tick)
        counter <= 0;
    else
        counter <= counter + 1'b1;
end

always @(posedge clk)
begin
    if (reset)
    begin
        present_state <= ST_IDLE;
        sioc_reg      <= 1'b1;
        siod_drive_low <= 1'b0;
        tx_byte       <= 8'd0;
        bit_index     <= 3'd0;
        done          <= 1'b0;
    end
    else
    begin
        done <= 1'b0;

        if (tick)
        begin
            case (present_state)

                ST_IDLE:
                begin
                    sioc_reg <= 1'b1;
                    siod_drive_low <= 1'b0;

                    if (start)
                    begin
                        tx_byte <= {7'h21, 1'b0};
                        present_state <= ST_START;
                    end
                end

                ST_START:
                begin
                    sioc_reg <= 1'b1;
                    siod_drive_low <= 1'b1;
                    present_state <= ST_START_HOLD;
                end

                ST_START_HOLD:
                begin
                    sioc_reg <= 1'b0;
                    bit_index <= 3'd7;
                    siod_drive_low <= ~tx_byte[7];
                    present_state <= ST_DEV_ADDR;
                end

                // Transmit device address, MSB first.
                ST_DEV_ADDR:
                begin
                    if (!sioc_reg)
                    begin
                        sioc_reg <= 1'b1;
                    end
                    else
                    begin
                        sioc_reg <= 1'b0;

                        if (bit_index == 0)
                        begin
                            siod_drive_low <= 1'b0;
                            present_state <= ST_ACK1;
                        end
                        else
                        begin
                            bit_index <= bit_index - 1'b1;
                            siod_drive_low <= ~tx_byte[bit_index - 1'b1];
                        end
                    end
                end

                ST_ACK1:
                begin
                    if (!sioc_reg)
                        sioc_reg <= 1'b1;
                    else
                    begin
                        sioc_reg <= 1'b0;
                        tx_byte <= reg_addr;
                        bit_index <= 3'd7;
                        siod_drive_low <= ~reg_addr[7];
                        present_state <= ST_REG_ADDR;
                    end
                end

                ST_REG_ADDR:
                begin
                    if (!sioc_reg)
                        sioc_reg <= 1'b1;
                    else
                    begin
                        sioc_reg <= 1'b0;

                        if (bit_index == 0)
                        begin
                            siod_drive_low <= 1'b0;
                            present_state <= ST_ACK2;
                        end
                        else
                        begin
                            bit_index <= bit_index - 1'b1;
                            siod_drive_low <= ~tx_byte[bit_index - 1'b1];
                        end
                    end
                end

                ST_ACK2:
                begin
                    if (!sioc_reg)
                        sioc_reg <= 1'b1;
                    else
                    begin
                        sioc_reg <= 1'b0;
                        tx_byte <= reg_data;
                        bit_index <= 3'd7;
                        siod_drive_low <= ~reg_data[7];
                        present_state <= ST_REG_DATA;
                    end
                end

                ST_REG_DATA:
                begin
                    if (!sioc_reg)
                        sioc_reg <= 1'b1;
                    else
                    begin
                        sioc_reg <= 1'b0;

                        if (bit_index == 0)
                        begin
                            siod_drive_low <= 1'b0;
                            present_state <= ST_ACK3;
                        end
                        else
                        begin
                            bit_index <= bit_index - 1'b1;
                            siod_drive_low <= ~tx_byte[bit_index - 1'b1];
                        end
                    end
                end

                ST_ACK3:
                begin
                    if (!sioc_reg)
                        sioc_reg <= 1'b1;
                    else
                    begin
                        sioc_reg <= 1'b0;
                        siod_drive_low <= 1'b1;
                        present_state <= ST_STOP_SETUP;
                    end
                end

                ST_STOP_SETUP:
                begin
                    sioc_reg <= 1'b1;
                    present_state <= ST_STOP_HIGH;
                end

                ST_STOP_HIGH:
                begin
                    sioc_reg <= 1'b1;
                    siod_drive_low <= 1'b0;
                    done <= 1'b1;
                    present_state <= ST_IDLE;
                end

                default:
                begin
                    present_state <= ST_IDLE;
                    sioc_reg <= 1'b1;
                    siod_drive_low <= 1'b0;
                end

            endcase
        end
    end
end

endmodule
