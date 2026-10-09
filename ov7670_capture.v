module ov7670_capture
(
    input         pclk,
    input         reset,

    input         vsync,
    input         href,
    input [7:0]   camera_data,

    output reg [15:0] pixel_data,
    output reg       pixel_valid,
    output reg       frame_start
);

reg [7:0] byte_high;
reg byte_toggle;


	always @(posedge pclk)
	begin
		if(reset)
		begin
			byte_high <= 0;
			byte_toggle <= 0;
			pixel_data <= 0;
			pixel_valid <= 0;
			frame_start <= 0;
		end
		
		else if(href)
		begin
		frame_start <= 0;
		pixel_valid <= 0;

			if(!byte_toggle)
			begin
				byte_high <= camera_data;
				byte_toggle <= 1'b1;
				frame_start <= vsync;
			end
			
			else
			begin
				pixel_data <= {byte_high, camera_data};
				pixel_valid <= 1;
				byte_toggle <= 0;
			end
		end
		
		else if(!href)
		begin
			byte_toggle <= 0;
		end
		
	end
	
	

endmodule
