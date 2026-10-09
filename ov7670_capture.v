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
reg vsync_prev; // Changed for fifo


	always @(posedge pclk)
	begin
	if (reset)
	begin
	byte_high   <= 0;
	byte_toggle <= 0;
	pixel_data  <= 0;
	pixel_valid <= 0;
	frame_start <= 0;
	vsync_prev  <= 0;
	end
	else
	begin
	// Detect rising edge of VSYNC
	frame_start <= vsync && !vsync_prev;
	vsync_prev  <= vsync;
	
	    // Capture pixel bytes
	    pixel_valid <= 0;
	
	    if (href)
	    begin
	        if (!byte_toggle)
	        begin
	            byte_high   <= camera_data;
	            byte_toggle <= 1'b1;
	        end
	        else
	        begin
	            pixel_data  <= {byte_high, camera_data};
	            pixel_valid <= 1'b1;
	            byte_toggle <= 1'b0;
	        end
	    end
	    else
	    begin
	        byte_toggle <= 0;
	    end
	end

end
	
	

endmodule
