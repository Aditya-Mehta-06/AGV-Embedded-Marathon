module sccb_configure #(
    parameter [23:0] DELAY_COUNT = 24'd10000000  // wait after COM7 reset 
)
(
    input clk_50MHz,
    input reset,
    input done,
    input busy, //not used anywhere
    input start_config, //signal to start configuration, it should be a pulse

    output reg start,
    output reg config_done, //signals that all the registers have been setup
    output [6:0] dev_addr,
    output reg [7:0] reg_addr,
    output reg [7:0] reg_data

);

reg [4:0] index;
reg last_entry;
reg [2:0] present_state;
reg [23:0] delay_counter;
reg is_reset;

localparam IDLE = 3'd0; //each state explained where they are implemented
localparam START = 3'd1;
localparam NEXT = 3'd2;
localparam WAIT = 3'd3;
localparam RESET_WAIT = 3'd4;

// DELAY_COUNT is now a module parameter (see header)

assign dev_addr = 7'h21;    //devce address -> fixed


// register ROM
always @(*) begin
        last_entry = 1'b0;
        is_reset = 1'b0;

        case (index)
            5'd0  : begin reg_addr = 8'h12; reg_data = 8'h80; is_reset = 1'b1; end   // COM7: reset
            5'd1  : begin reg_addr = 8'h12; reg_data = 8'h80; is_reset = 1'b1; end   // COM7: reset again
            5'd2  : begin reg_addr = 8'h11; reg_data = 8'h80; end   // CLKRC: bypass prescaler, PCLK = XCLK
            5'd3  : begin reg_addr = 8'h3A; reg_data = 8'h04; end   // TSLB
            5'd4  : begin reg_addr = 8'h12; reg_data = 8'h04; end   // COM7: VGA + RGB output (was 8'h00 = YUV)
            5'd5  : begin reg_addr = 8'h17; reg_data = 8'h13; end   // HSTART
            5'd6  : begin reg_addr = 8'h18; reg_data = 8'h01; end   // HSTOP
            5'd7  : begin reg_addr = 8'h32; reg_data = 8'h36; end   // HREF
            5'd8  : begin reg_addr = 8'h19; reg_data = 8'h02; end   // VSTART
            5'd9  : begin reg_addr = 8'h1A; reg_data = 8'h7A; end   // VSTOP
            5'd10 : begin reg_addr = 8'h03; reg_data = 8'h0A; end   // VREF
            5'd11 : begin reg_addr = 8'h0C; reg_data = 8'h04; end   // COM3
            5'd12 : begin reg_addr = 8'h3E; reg_data = 8'h1A; end   // COM14
            5'd13 : begin reg_addr = 8'h40; reg_data = 8'hD0; end   // COM15: RGB565
            5'd14 : begin reg_addr = 8'h15; reg_data = 8'h00; end   // COM10: sync polarity
            5'd15 : begin reg_addr = 8'h1E; reg_data = 8'h00; end   // MVFP
            5'd16 : begin reg_addr = 8'h3D; reg_data = 8'h88; end   // COM13
            5'd17 : begin reg_addr = 8'h72; reg_data = 8'h22; end                      // DCWCTR: downsample H and V by 4
            5'd18 : begin reg_addr = 8'h73; reg_data = 8'hF2; last_entry = 1'b1; end   // PCLK divide by 4
            default: begin reg_addr = 8'h00; reg_data = 8'h00; end
        endcase
    end



always @(posedge clk_50MHz or posedge reset)
begin
    if (reset)
    begin
        present_state <= IDLE;
        index <= 5'd0;
        start <= 1'b0;
        config_done <= 1'b0;
        delay_counter <= 24'd0;
    end

    else 
    begin
        start <= 1'b0;

        case(present_state)
            IDLE:   //default state before starting and after finishing configuration of camera or after reset
            begin
                if(start_config)
                begin
                    index <= 5'd0;
                    present_state <= START;
                    config_done <= 1'b0;
                end
            end

            START:  //gives signal to sccb_controller to start sending data for every index in ROM register
            begin
                start <= 1'b1;
                present_state <= WAIT;
            end

            WAIT:   //waits until sccb has sent all the bytes of previous index
            begin
                if(done)
                begin
                    if(is_reset)
                    begin
                        present_state <= RESET_WAIT;
                    end
                    else
                        present_state <= NEXT;
                end
            end

            RESET_WAIT: //special wait stage after every rese signal
            begin
                if(delay_counter == DELAY_COUNT)
                begin
                    delay_counter <= 24'd0;
                    present_state <= NEXT;
                end
                else
                    delay_counter <= delay_counter + 24'd1;
            end

            NEXT:   //changes the index by 1 and sends FSM to START state
            begin
                if(!last_entry)
                begin
                    index <= index + 5'd1;
                    present_state <= START;
                end

                else
                begin
                    config_done <= 1'b1;
                    present_state <= IDLE;
                end
            end

            default:    //safety net (claude)
            begin
                present_state <= IDLE;
            end
        endcase
    end
end

endmodule