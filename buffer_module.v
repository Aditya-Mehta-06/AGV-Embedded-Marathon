module buffer_module
(
	input pclk,
	input reset;
	input [15:0] pixel_data,
	
);

reg [479:0] [639:0] [15:0] frame;
reg [9:0] counter_column;
reg [8:0] counter_row;
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
		end
		
		else if(byte_toggle)
		begin
		
		byte_toggle <= 0;
		
			if(counter_row <= 8'd479)
			begin
	
				if(counter_column <= 9'd639)
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

endmodule
