module buffer_module
(
	input pclk,
	input reset;
	input [15:0] pixel_data,
	input [8:0] addr_col,
	input [8:0] addr_row,
	input rd,

	output reg rd_en,
	output reg [15:0] frame_data,

);

	reg [15:0] frame [0:119][0:159];
	reg [8:0] counter_column;
	reg [7:0] counter_row;
	reg byte_toggle;


	always @(posedge pclk)
	begin

		if(reset)
		begin
			counter_column <= 0;
			counter_row <= 0;
			byte_toggle <= 0;
		end

		else if(!byte_toggle)
		begin
			//
			byte_toggle <= 1'b1;
			rd_en <= 1'b1;
		end

		else if(byte_toggle)
		begin

		byte_toggle <= 0;

			if(counter_row <= 7'd119)
			begin

				if(counter_column <= 8'd159)
				begin
					frame[counter_row][counter_column] = pixel_data;
					counter_column <= counter_column + 1;
				end

				else
				begin
					counter_column <= 0;
					counter_row <= counter_row + 1;
				end

			end

			else
			begin
				counter_row <= 0;
			end
		end

	end

	always @(*)
	begin
		if(rd)
		begin
			frame_data = frame[addr_row][addr_col];
		end

		else
		begin
			frame_data = 16'd0;
		end
	end

endmodule
