module async_fifo #(
    parameter data_width = 16,
    parameter addr       = 8        // Address width (Depth = 2^8 = 256 words)
)(
    input  wire                  wr_clk,
    input  wire                  rd_clk,
    input  wire                  rst_n,

    input  wire                  wr_en,
    input  wire [data_width-1:0] wr_data,
    output wire                  full,

    input  wire                  rd_en,
    output wire [data_width-1:0] rd_data,
    output wire                  empty
);

    localparam DEPTH = 1 << addr;

    reg [data_width-1:0] mem [0:DEPTH-1];

    reg [addr:0] wr_bin, wr_gray;
    reg [addr:0] wr_gray_sync1, wr_gray_sync2;

    reg [addr:0] rd_bin, rd_gray;
    reg [addr:0] rd_gray_sync1, rd_gray_sync2;

    always @(posedge wr_clk) begin
        if (wr_en && !full)
            mem[wr_bin[addr-1:0]] <= wr_data;
    end

    assign rd_data = mem[rd_bin[addr-1:0]];

    wire [addr:0] wr_bin_next  = wr_bin + (wr_en & ~full);
    wire [addr:0] wr_gray_next = (wr_bin_next >> 1) ^ wr_bin_next;

    always @(posedge wr_clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_bin  <= 0;
            wr_gray <= 0;
        end else begin
            wr_bin  <= wr_bin_next;
            wr_gray <= wr_gray_next;
        end
    end

    wire [addr:0] rd_bin_next  = rd_bin + (rd_en & ~empty);
    wire [addr:0] rd_gray_next = (rd_bin_next >> 1) ^ rd_bin_next;

    always @(posedge rd_clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_bin  <= 0;
            rd_gray <= 0;
        end else begin
            rd_bin  <= rd_bin_next;
            rd_gray <= rd_gray_next;
        end
    end

    always @(posedge rd_clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_gray_sync1 <= 0;
            wr_gray_sync2 <= 0;
        end else begin
            wr_gray_sync1 <= wr_gray;
            wr_gray_sync2 <= wr_gray_sync1;
        end
    end

    always @(posedge wr_clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_gray_sync1 <= 0;
            rd_gray_sync2 <= 0;
        end else begin
            rd_gray_sync1 <= rd_gray;
            rd_gray_sync2 <= rd_gray_sync1;
        end
    end

    assign full = (wr_gray_next == {~rd_gray_sync2[addr:addr-1], rd_gray_sync2[addr-2:0]});

    assign empty = (rd_gray_next == wr_gray_sync2);

endmodule