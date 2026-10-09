module vga_timing (
    input   pclk_vga,
    input   reset,

    output [9:0]  h_count,
    output [9:0]  v_count,

    output  hsync,
    output  vsync,
    output  active_video
);

    parameter H_ACTIVE = 640;
    parameter H_FRONT_PORCH = 16;
    parameter H_SYNC = 96;
    parameter H_BACK_PORCH = 48;
    parameter H_TOTAL = H_ACTIVE + H_FRONT_PORCH + H_SYNC + H_BACK_PORCH;

    parameter V_ACTIVE = 480;
    parameter V_FRONT_PORCH = 10;
    parameter V_SYNC = 2;
    parameter V_BACK_PORCH = 33;
    parameter V_TOTAL = V_ACTIVE + V_FRONT_PORCH + V_SYNC + V_BACK_PORCH;


    always @(posedge pclk or posedge reset) 
    begin

        if (reset)
        begin
            h_count <= 0;
            v_count <= 0;
        end 

        else
        begin

            if (h_count == H_TOTAL - 1) 
            begin
                h_count <= 0;
                if (v_count == V_TOTAL - 1) begin
                    v_count <= 0;
                end else begin
                    v_count <= v_count + 1;
                end
            end

            else 
            begin
                h_count <= h_count + 1;
            end

        end
    end

    assign hsync = (h_count >= H_ACTIVE + H_FRONT_PORCH) && (h_count < H_ACTIVE + H_FRONT_PORCH + H_SYNC);

    assign vsync = (v_count >= V_ACTIVE + V_FRONT_PORCH) && (v_count < V_ACTIVE + V_FRONT_PORCH + V_SYNC);

    assign active_video = (h_count < H_ACTIVE) && (v_count < V_ACTIVE);




endmodule