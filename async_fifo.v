module async_fifo #(
    parameter int data_width = 16,
    parameter int addr = 4
)
(
    input wr_clk,
    input rd_clk,
    input rst_n,

    input wr_en,
    input  [data_width-1:0] wr_data,
    output full,

    input rd_en,
    output [data_width-1:0] rd_data,
    output empty

);

    reg [data_width-1:0] mem [0:(1<<addr)-1];

    reg [addr:0] wr_bin;
    reg [addr:0] wr_gray;
    reg [addr:0] wr_gray_sync1;
    reg [addr:0] wr_gray_sync2;
    reg [addr:0] wr_bin_next;
    reg [addr:0] wr_gray_next;

    reg [addr:0] rd_bin;
    reg [addr:0] rd_gray;
    reg [addr:0] rd_gray_sync1;
    reg [addr:0] rd_gray_sync2;
    reg [addr:0] rd_bin_next;
    reg [addr:0] rd_gray_next;


    always @(*)
    begin

        wr_bin_next = wr_bin;

        if(wr_en && !full)
        begin
            wr_bin_next = wr_bin + 1;
        end

        wr_gray_next = (wr_bin_next >> 1) ^ wr_bin_next;
    end

    always @(*)
    begin

        rd_bin_next = rd_bin;

        if(rd_en && !empty)
        begin
            rd_bin_next = rd_bin + 1;
        end

        rd_gray_next = (rd_bin_next >> 1) ^ rd_bin_next;
    end

    always @(posedge wr_clk or negedge rst_n)
    begin

        if (!rst_n)
        begin
            wr_bin <= 0;
            wr_gray <= 0;
        end

        else if (wr_en && !full)
        begin
            mem[wr_bin] <= wr_data;
            wr_bin <= wr_bin_next;
            wr_gray <= wr_gray_next;
        end

    end

    always @(posedge rd_clk or negedge rst_n)
    begin

        if(!rst_n)
        begin
            rd_bin <= 0;
            rd_gray <= 0;
        end

        else if(rd_en && !empty)
        begin
            rd_data <= mem[rd_bin];
            rd_bin <= rd_bin_next;
            rd_gray <= rd_gray_next;
        end
    end

    always @(posedge rd_clk or negedge rst_n)
    begin
        if(!rst_n)
        begin
            wr_gray_sync1 <= 0;
            wr_gray_sync2 <= 0;
        end

        else
        begin
            wr_gray_sync1 <= wr_gray;
            wr_gray_sync2 <= wr_gray_sync1;
        end
    end

    always @(posedge wr_clk or negedge rst_n)
    begin
        if(!rst_n)
        begin
            rd_gray_sync1 <= 0;
            rd_gray_sync2 <= 0;
        end

        else
        begin
            rd_gray_sync1 <= rd_gray;
            rd_gray_sync2 <= rd_gray_sync1;
        end
    end

    assign full = (wr_gray[addr:addr-1] != rd_gray_sync2[addr:addr-1]) && (wr_gray[2:0] == rd_gray_sync2[2:0]);
    assign empty = (rd_gray == wr_gray_sync2);

endmodule
