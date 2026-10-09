module sccb_controller
(
	input clk_50MHz,
	input reset,
	input start,
	input [6:0] device_addr,
	input [7:0] reg_addr,
	input [7:0] reg_data,
	
	output reg sioc,
	output reg siod,
	output reg busy,
	output reg done
);

localparam IDLE = 2'b00;
localparam START = 2'b01; 
localparam SEND_BYTE = 2'b10;
localparam STOP = 2'b11;

reg [1:0] present_state;
reg [7:0] tick;
reg pulse; // pulses at half cycle
reg has_started; // tells if start signal was sent

reg [1:0] byte_sel; // which of the 3 bytes is being sent currently, 00, 01, 10 for device addr, reg addr, reg data respectively
reg [3:0] bit_index; // which bit of the curren byte is being sent 0 for MSB
reg [7:0] shift_reg; // initially holds the current byte being send but is shifted every clock cycle and only MSB is sent
reg [1:0] phase; // either send or hold phase for SEND_BYTE state

always @(posedge clk_50MHz or posedge reset) // clock logic
begin
	if (reset)
	begin
		tick <= 8'd0;
        pulse <= 1'b0;
	end

	else if (tick == 8'd249) // a short pulse (50MHz_clk wide) is generated at every half 100kHz cycle
	begin
		tick <= 8'd0;
		pulse <= 1'b1;
	end
	
	else
	begin
		tick <= tick + 8'd1;
    	pulse <= 1'b0;
	end
end

always @(posedge clk_50MHz or posedge reset) // to not miss start pulse, as soon as it is pulsed, a reg is turned on
begin
    if (reset)
        has_started <= 1'b0;

    else if (pulse && present_state == IDLE && has_started)
        has_started <= 1'b0;   // consumed by FSM — clear takes priority

    else if (start)
        has_started <= 1'b1;   // new request latched
end

always @(posedge clk_50MHz or posedge reset) // main protocol logic
begin
		if(reset) 
		begin
			present_state <= IDLE;
            sioc <= 1'b1;
            siod <= 1'b1;
            busy <= 1'b0;
            done <= 1'b0;
            byte_sel <= 2'b00;
            bit_index <= 4'd0;
            shift_reg <= 8'd0;
            phase <= 2'b00;
		end
			
		else
		begin
			done <= 1'b0;

			if(pulse) //executed every half cycle
			begin
				case(present_state)
					IDLE:
					begin
						sioc <= 1'b1;
                        siod <= 1'b1;
                        if (has_started)
						begin
                            shift_reg <= {device_addr, 1'b0}; // write bit = 0
                            byte_sel <= 2'b00;
                            bit_index <= 4'd0;
                            busy <= 1'b1;
                            present_state <= START;
                        end
					end

					START: // START condition: sioc 0 while sioc is 1
					begin
                        sioc <= 1'b1;
                        siod <= 1'b0;
                        phase <= 2'b00; // SEND_BYTE begins in setup phase
                        present_state <= SEND_BYTE;
                    end

					SEND_BYTE:
					begin
						if (phase == 2'b00) // SETUP half: sioc low, place next bit on siod
						begin
                            sioc <= 1'b0;
                            siod <= (bit_index == 4'd8) ? 1'b1 : shift_reg[7];
                            phase <= 2'b01;
						end

						else
						begin
							sioc  <= 1'b1;
                            phase <= 2'b00;

							if(bit_index == 4'd8)
							begin
								bit_index <= 4'd0;

								case(byte_sel)
									2'b00:
									begin 
										shift_reg <= reg_addr;
										byte_sel <= 2'b01;
									end

									2'b01:
									begin 
										shift_reg <= reg_data;
										byte_sel <= 2'b10;
									end

									2'b10:
									begin 
										present_state <= STOP; 
									end

									default: //just a safety net (claude)
										present_state <= IDLE;

								endcase
							end

							else
							begin
								bit_index <= bit_index + 4'd1;
								shift_reg <= shift_reg << 1;
							end
						end
					end

					STOP:
						// STOP sequence required: 1) sioc brought low first, siod forced low
                        // 2) sioc raised, 
						// 3) then siod raised
                        // the rising edge of siod while sioc is high indicates stop
					begin
						case (phase) //same phase variable is used both in send byte and stop but independently ofcourse
                            2'b00: // 1)
							begin 
								sioc <= 1'b0; 
								siod <= 1'b0; 
								phase <= 2'b01; 
							end

                            2'b01: // 2)
							begin 
								sioc <= 1'b1;
								phase <= 2'b10; 
							end

                            2'b10:
							begin
                                siod  <= 1'b1; // STOP edge
                                busy  <= 1'b0;
                                done  <= 1'b1; // one-cycle pulse
                                phase <= 2'b00;
                            	present_state <= IDLE;
                            end

							default:
								present_state <= IDLE;

                        endcase
					end

					default:
						present_state <= IDLE;
				endcase
			end
			
		end
			
end

endmodule
