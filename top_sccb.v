module sccb_top
(
    input  wire clk_50MHz,
    input  wire reset,

    output wire sioc,
    inout  wire siod,

    output wire config_done,
    output wire busy,
    output wire error
);

wire start;
wire done;
wire controller_busy;

wire [6:0] dev_addr;
wire [7:0] reg_addr;
wire [7:0] reg_data;

reg start_config;

sccb_configure configure_inst
(
    .clk_50MHz(clk_50MHz),
    .reset(reset),
    .done(done),
    .busy(controller_busy),
    .start_config(start_config),
    .start(start),
    .config_done(config_done),
    .dev_addr(dev_addr),
    .reg_addr(reg_addr),
    .reg_data(reg_data)
);

sccb_controller controller_inst
(
    .clk(clk_50MHz),
    .reset(reset),
    .start(start),
    .reg_addr(reg_addr),
    .reg_data(reg_data),
    .sioc(sioc),
    .siod(siod),
    .busy(busy),
    .done(done),
    .error(error)
);

always @(posedge clk_50MHz)
begin
    if (reset)
        start_config <= 1'b0;
    else
        start_config <= 1'b1;
end

endmodule

