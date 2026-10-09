module buffer_module
(
    input pclk,
    input rst_n,
    input [15:0] pixel_data,
    input pixel_valid,
    input [8:0] addr_col,
    input [8:0] addr_row,
    input rd,

    output reg rd_en,
    output reg [15:0] frame_data
);

    reg [15:0] frame [0:119][0:159];
    reg [8:0] counter_column;
    reg [7:0] counter_row;

    always @(posedge pclk or negedge rst_n)
    begin
        if (!rst_n)
        begin
            counter_column <= 0;
            counter_row <= 0;
            rd_en <= 0;
        end
        else
        begin
            rd_en <= 0;

            if (pixel_valid)
            begin
                if (counter_row < 120)
                begin
                    if (counter_column < 160)
                    begin
                        frame[counter_row][counter_column] <= pixel_data;
                        rd_en <= 1'b1;
                        counter_column <= counter_column + 1'b1;
                    end
                    else
                    begin
                        counter_column <= 0;
                        counter_row <= counter_row + 1'b1;
                    end
                end
                else
                begin
                    counter_row <= 0;
                    counter_column <= 0;
                end
            end
        end
    end

    always @(*)
    begin
        if (!rst_n)
        begin
            frame_data = 16'd0;
        end
        else if (rd && addr_row < 120 && addr_col < 160)
        begin
            frame_data = frame[addr_row][addr_col];
        end
        else
        begin
            frame_data = 16'd0;
        end
    end

endmodule
