`timescale 1ns/1ps

module tb_ov7670_capture;

    reg        pclk;
    reg        reset;
    reg        vsync;
    reg        href;
    reg [7:0]  camera_data;

    wire [15:0] pixel_data;
    wire        pixel_valid;
    wire        frame_start;

    ov7670_capture dut (
        .pclk        (pclk),
        .reset       (reset),
        .vsync       (vsync),
        .href        (href),
        .camera_data (camera_data),
        .pixel_data  (pixel_data),
        .pixel_valid (pixel_valid),
        .frame_start (frame_start)
    );

    // Clock: 10 ns period
    initial begin
        pclk = 1'b0;
        forever #5 pclk = ~pclk;
    end

    // Monitor
    always @(posedge pclk) begin
        $display("TIME=%0t RESET=%b VSYNC=%b HREF=%b DATA=%h PIXEL=%h VALID=%b FRAME_START=%b",
                 $time,
                 reset,
                 vsync,
                 href,
                 camera_data,
                 pixel_data,
                 pixel_valid,
                 frame_start);
    end

    initial begin

        // ========================================================
        // INITIAL
        // ========================================================
        reset       = 1'b1;
        vsync       = 1'b0;
        href        = 1'b0;
        camera_data = 8'h00;

        // ========================================================
        // TEST 1: RESET
        // ========================================================
        $display("");
        $display("========================================");
        $display("TEST 1: RESET");
        $display("========================================");

        repeat(2) @(posedge pclk);
        #1;

        if (pixel_data !== 16'h0000)
            $display("FAIL: pixel_data is not zero after reset");
        else
            $display("PASS: pixel_data reset");

        if (pixel_valid !== 1'b0)
            $display("FAIL: pixel_valid is not zero after reset");
        else
            $display("PASS: pixel_valid reset");

        if (frame_start !== 1'b0)
            $display("FAIL: frame_start is not zero after reset");
        else
            $display("PASS: frame_start reset");

        if (dut.byte_high !== 8'h00)
            $display("FAIL: byte_high is not zero after reset");
        else
            $display("PASS: byte_high reset");

        if (dut.byte_toggle !== 1'b0)
            $display("FAIL: byte_toggle is not zero after reset");
        else
            $display("PASS: byte_toggle reset");


        // ========================================================
        // RELEASE RESET
        // ========================================================
        reset = 1'b0;


        // ========================================================
        // TEST 2: HREF LOW
        // ========================================================
        $display("");
        $display("========================================");
        $display("TEST 2: HREF LOW");
        $display("========================================");

        href        = 1'b0;
        vsync       = 1'b0;
        camera_data = 8'hAA;

        @(posedge pclk);
        #1;

        if (dut.byte_toggle !== 1'b0)
            $display("FAIL: byte_toggle should be 0");
        else
            $display("PASS: byte_toggle = 0");


        // ========================================================
        // TEST 3: FIRST BYTE
        // ========================================================
        $display("");
        $display("========================================");
        $display("TEST 3: FIRST BYTE");
        $display("========================================");

        href        = 1'b1;
        vsync       = 1'b0;
        camera_data = 8'h12;

        @(posedge pclk);
        #1;

        if (dut.byte_high !== 8'h12)
            $display("FAIL: byte_high is %h, expected 12",
                     dut.byte_high);
        else
            $display("PASS: byte_high = 12");

        if (dut.byte_toggle !== 1'b1)
            $display("FAIL: byte_toggle should be 1");
        else
            $display("PASS: byte_toggle = 1");


        // ========================================================
        // TEST 4: SECOND BYTE -> PIXEL
        // ========================================================
        $display("");
        $display("========================================");
        $display("TEST 4: SECOND BYTE / PIXEL");
        $display("========================================");

        camera_data = 8'h34;

        @(posedge pclk);
        #1;

        if (pixel_data !== 16'h1234)
            $display("FAIL: pixel_data = %h, expected 1234",
                     pixel_data);
        else
            $display("PASS: pixel_data = 1234");

        if (pixel_valid !== 1'b1)
            $display("FAIL: pixel_valid should be 1");
        else
            $display("PASS: pixel_valid = 1");

        if (dut.byte_toggle !== 1'b0)
            $display("FAIL: byte_toggle should be 0");
        else
            $display("PASS: byte_toggle = 0");


        // ========================================================
        // TEST 5: MULTIPLE PIXELS
        // ========================================================
        $display("");
        $display("========================================");
        $display("TEST 5: MULTIPLE PIXELS");
        $display("========================================");

        // Pixel 1 = ABCD
        camera_data = 8'hAB;
        @(posedge pclk);

        camera_data = 8'hCD;
        @(posedge pclk);
        #1;

        if (pixel_data !== 16'hABCD)
            $display("FAIL: Pixel 1 = %h, expected ABCD",
                     pixel_data);
        else
            $display("PASS: Pixel 1 = ABCD");


        // Pixel 2 = 1234
        camera_data = 8'h12;
        @(posedge pclk);

        camera_data = 8'h34;
        @(posedge pclk);
        #1;

        if (pixel_data !== 16'h1234)
            $display("FAIL: Pixel 2 = %h, expected 1234",
                     pixel_data);
        else
            $display("PASS: Pixel 2 = 1234");


        // Pixel 3 = 5678
        camera_data = 8'h56;
        @(posedge pclk);

        camera_data = 8'h78;
        @(posedge pclk);
        #1;

        if (pixel_data !== 16'h5678)
            $display("FAIL: Pixel 3 = %h, expected 5678",
                     pixel_data);
        else
            $display("PASS: Pixel 3 = 5678");


        // ========================================================
        // TEST 6: HREF LOW MID-PIXEL
        // ========================================================
        $display("");
        $display("========================================");
        $display("TEST 6: HREF LOW MID-PIXEL");
        $display("========================================");

        // First byte
        href        = 1'b1;
        camera_data = 8'hAA;

        @(posedge pclk);

        // HREF becomes low before second byte
        href        = 1'b0;
        camera_data = 8'hBB;

        @(posedge pclk);
        #1;

        if (dut.byte_toggle !== 1'b0)
            $display("FAIL: byte_toggle should reset");
        else
            $display("PASS: byte_toggle reset");


        // ========================================================
        // TEST 7: NEW PIXEL AFTER HREF LOW
        // ========================================================
        $display("");
        $display("========================================");
        $display("TEST 7: NEW PIXEL AFTER HREF LOW");
        $display("========================================");

        href        = 1'b1;
        camera_data = 8'hCC;

        @(posedge pclk);

        camera_data = 8'hDD;

        @(posedge pclk);
        #1;

        if (pixel_data !== 16'hCCDD)
            $display("FAIL: pixel_data = %h, expected CCDD",
                     pixel_data);
        else
            $display("PASS: pixel_data = CCDD");


        // ========================================================
        // TEST 8: VSYNC HIGH
        // ========================================================
        $display("");
        $display("========================================");
        $display("TEST 8: VSYNC HIGH / FRAME START");
        $display("========================================");

        href        = 1'b1;
        vsync       = 1'b1;
        camera_data = 8'h11;

        @(posedge pclk);
        #1;

        if (frame_start !== 1'b1)
            $display("FAIL: frame_start should be 1");
        else
            $display("PASS: frame_start = 1");


        // ========================================================
        // TEST 9: COMPLETE PIXEL WITH VSYNC HIGH
        // ========================================================
        $display("");
        $display("========================================");
        $display("TEST 9: PIXEL DURING VSYNC");
        $display("========================================");

        camera_data = 8'h22;

        @(posedge pclk);
        #1;

        if (pixel_data !== 16'h1122)
            $display("FAIL: pixel_data = %h, expected 1122",
                     pixel_data);
        else
            $display("PASS: pixel_data = 1122");


        // ========================================================
        // TEST 10: NEW LINE
        // ========================================================
        $display("");
        $display("========================================");
        $display("TEST 10: NEW LINE");
        $display("========================================");

        vsync       = 1'b0;
        href        = 1'b0;
        camera_data = 8'hFF;

        @(posedge pclk);

        href        = 1'b1;
        camera_data = 8'h55;

        @(posedge pclk);

        camera_data = 8'h66;

        @(posedge pclk);
        #1;

        if (pixel_data !== 16'h5566)
            $display("FAIL: pixel_data = %h, expected 5566",
                     pixel_data);
        else
            $display("PASS: pixel_data = 5566");


        // ========================================================
        // FINISH
        // ========================================================
        $display("");
        $display("========================================");
        $display("ALL TESTS COMPLETED");
        $display("========================================");

        #20;
        $finish;

    end

endmodule