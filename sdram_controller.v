module sdram_controller #(
    parameter data_width = 16
)(
    // Clock and reset
    input  wire                  clk,
    input  wire                  rst_n,

    // Write FIFO interface
    input  wire [data_width-1:0] wr_data,
    input  wire                  wr_empty,
    output wire                  wr_rd_en,

    // Read FIFO interface
    output reg  [data_width-1:0] rd_data,
    output reg                   rd_wr_en,
    input  wire                  rd_full,

    // Status
    output reg                   init_done,

    // SDRAM control pins
    output wire                  sdram_clk,
    output reg                   sdram_cke,
    output reg                   sdram_cs_n,
    output reg                   sdram_ras_n,
    output reg                   sdram_cas_n,
    output reg                   sdram_we_n,

    // SDRAM address pins
    output reg  [12:0]           sdram_addr,
    output reg  [1:0]            sdram_ba,

    // SDRAM data pins
    inout  wire [15:0]           sdram_dq,
    output reg  [1:0]            sdram_dqm
);

    parameter init_wait = 4'd0,
              init_pre = 4'd1,
              init_ar1 = 4'd2,
              init_ar2 = 4'd3,
              init_mrs = 4'd4,
              idle = 4'd5,
              activate = 4'd6,
              wait_rcd = 4'd7,
              write = 4'd8,
              read = 4'd9,
              wait_cas = 4'd10,
              read_data = 4'd11,
              precharge = 4'd12,
              wait_rp = 4'd13,
              refresh = 4'd14;


    parameter nop_cmd = 4'b0111,
              active_cmd = 4'b0011,
              read_cmd = 4'b0100,
              write_cmd = 4'b0101,
              pre_cmd = 4'b0010,
              refresh_cmd = 4'b0001,
              mrs_cmd = 4'b0000;

    reg [3:0] state, next_state;
    reg [3:0] command;

    always @(*)
    begin

        {sdram_cs_n, sdram_ras_n, sdram_cas_n, sdram_we_n} = nop_cmd;

        case(command)

            active_cmd:
            begin
                {sdram_cs_n, sdram_ras_n, sdram_cas_n, sdram_we_n} = active_cmd;
            end

            read_cmd:
            begin
                {sdram_cs_n, sdram_ras_n, sdram_cas_n, sdram_we_n} = read_cmd;
            end

            write_cmd:
            begin
                {sdram_cs_n, sdram_ras_n, sdram_cas_n, sdram_we_n} = write_cmd;
            end

            pre_cmd:
            begin
                {sdram_cs_n, sdram_ras_n, sdram_cas_n, sdram_we_n} = pre_cmd;
            end

            refresh_cmd:
            begin
                {sdram_cs_n, sdram_ras_n, sdram_cas_n, sdram_we_n} = refresh_cmd;
            end

            mrs_cmd:
            begin
                {sdram_cs_n, sdram_ras_n, sdram_cas_n, sdram_we_n} = mrs_cmd;
            end

        endcase

        
    end


endmodule
