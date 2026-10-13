`timescale 1ns/1ps
// =============================================================================
// Self-checking testbench for top.v  (OV7670 -> frame buffer -> VGA, + Sobel)
//
// What it contains
//   * 50 MHz clock, reset button (key_n) and mode button (key1_n)
//   * Behavioural OV7670: PCLK = XCLK/4, QQVGA RGB565, 2 bytes/pixel,
//     VSYNC high = frame start, HREF high = valid data, garbage when HREF low
//   * SCCB slave: decodes every write, ACKs it, compares with the expected
//     register table, checks the 100 kHz clock
//   * Checkers:
//       - capture : address sequence, pixel data, 19200 pixels/frame
//       - sobel   : write count/frame, interior of frame buffer vs golden model
//       - frame buffer contents (raw mode and sobel mode)
//       - VGA     : hsync/vsync period + width, de count, every visible pixel
//                   against the frame buffer (4x upscale)
//       - LEDs, reset button behaviour, re-configuration after reset
//
// Simulation uses pll_clocks_sim.v instead of the Quartus altpll wrapper.
// =============================================================================

`define FAIL(msg) begin errors = errors + 1; $display("[%0t] FAIL: %0s", $time, msg); end

module tb_top;

    // ------------------------------------------------------------ parameters
    // short start-up delays so the simulation does not take forever
    localparam                RESET_CYCLES     = 500;
    localparam                WAIT_CYCLES      = 1000;
    localparam         [23:0] SCCB_RESET_DELAY = 24'd2000;

    localparam IMG_W        = 160;
    localparam IMG_H        = 120;
    localparam NPIX         = 19200;
    localparam LINE_PCLKS   = 400;          // 320 active + 80 blanking
    localparam VS_LINES     = 3;
    localparam BP_LINES     = 10;
    localparam FP_LINES     = 5;
    localparam N_CFG_REGS   = 19;
    localparam SOBEL_WRITES = 158 * 118;    // window needs x>=2, y>=2
    localparam VGA_PIX      = 640 * 480;
    localparam SIM_TIMEOUT_NS = 400_000_000;   // 400 ms of simulated time

    integer errors = 0;

    // ----------------------------------------------------------------- DUT io
    reg         CLK_50MHz = 1'b0;
    reg         key_n     = 1'b1;     // reset button, 0 = pressed
    reg         key1_n    = 1'b0;     // 0 = raw colour, 1 = sobel
    wire [2:0]  LED;

    wire        cam_xclk;
    reg         cam_pclk  = 1'b0;
    reg         cam_vsync = 1'b0;
    reg         cam_href  = 1'b0;
    reg  [7:0]  cam_data  = 8'h00;
    wire        cam_reset_n;
    wire        cam_sioc;
    wire        cam_siod;
    pullup (cam_siod);                // open-drain bus needs a pull-up

    wire [4:0]  vga_r;
    wire [5:0]  vga_g;
    wire [4:0]  vga_b;
    wire        vga_hs, vga_vs;

    top #(
        .RESET_CYCLES     (RESET_CYCLES),
        .WAIT_CYCLES      (WAIT_CYCLES),
        .SCCB_RESET_DELAY (SCCB_RESET_DELAY)
    ) dut (
        .CLK_50MHz   (CLK_50MHz),
        .key_n       (key_n),
        .key1_n      (key1_n),
        .LED         (LED),
        .cam_xclk    (cam_xclk),
        .cam_pclk    (cam_pclk),
        .cam_vsync   (cam_vsync),
        .cam_href    (cam_href),
        .cam_data    (cam_data),
        .cam_reset_n (cam_reset_n),
        .cam_sioc    (cam_sioc),
        .cam_siod    (cam_siod),
        .vga_r       (vga_r),
        .vga_g       (vga_g),
        .vga_b       (vga_b),
        .vga_hs      (vga_hs),
        .vga_vs      (vga_vs)
    );

    wire clk_vga = dut.clk_vga;       // PLL c1, used by the VGA monitors

    always #10 CLK_50MHz = ~CLK_50MHz;

    // =========================================================================
    // Test image + golden models
    // =========================================================================
    // pixel (x,y) of the test image, RGB565.
    //   white rectangle in the middle (gives strong edges for sobel),
    //   elsewhere a smooth ramp with the pixel index in the blue field so that
    //   address mistakes show up.
    function [15:0] pix;
        input integer x;
        input integer y;
        integer idx;
        begin
            idx = y * IMG_W + x;
            if (x >= 40 && x < 120 && y >= 30 && y < 90)
                pix = 16'hFFFF;
            else
                pix = {x[7:3], y[6:1], idx[4:0]};
        end
    endfunction

    // same arithmetic as gray_scale.v
    function integer gray8;
        input [15:0] p;
        reg [7:0] r8, g8, b8;
        begin
            r8 = {p[15:11], p[15:13]};
            g8 = {p[10:5],  p[10:9]};
            b8 = {p[4:0],   p[4:2]};
            gray8 = (77 * r8 + 150 * g8 + 29 * b8) >> 8;
        end
    endfunction

    // expected frame-buffer word for the sobel output centred on (cx,cy)
    function [15:0] sobel_px;
        input integer cx;
        input integer cy;
        integer p0, p1, p2, p3, p5, p6, p7, p8;
        integer gx, gy, m, e;
        begin
            p0 = gray8(pix(cx - 1, cy - 1));
            p1 = gray8(pix(cx    , cy - 1));
            p2 = gray8(pix(cx + 1, cy - 1));
            p3 = gray8(pix(cx - 1, cy    ));
            p5 = gray8(pix(cx + 1, cy    ));
            p6 = gray8(pix(cx - 1, cy + 1));
            p7 = gray8(pix(cx    , cy + 1));
            p8 = gray8(pix(cx + 1, cy + 1));
            gx = p2 + 2 * p5 + p8 - p0 - 2 * p3 - p6;
            gy = p6 + 2 * p7 + p8 - p0 - 2 * p1 - p2;
            if (gx < 0) gx = -gx;
            if (gy < 0) gy = -gy;
            m = gx + gy;
            e = (m > 255) ? 255 : m;
            sobel_px = {e[7:3], e[7:2], e[7:3]};
        end
    endfunction

    // =========================================================================
    // Behavioural OV7670
    // =========================================================================
    // PCLK = XCLK / 4
    reg [1:0] pdiv = 2'd0;
    always @(posedge cam_xclk) begin
        pdiv <= pdiv + 1'b1;
        if (pdiv[0]) cam_pclk <= ~cam_pclk;
    end

    task tick;
        begin
            @(negedge cam_pclk);        // outputs change on PCLK falling edge
        end
    endtask

    integer     cyc, fy, fk;
    reg  [15:0] pv;

    initial begin
        forever begin
            // camera is held in reset by the FPGA: nothing happens
            while (cam_reset_n !== 1'b1) @(negedge cam_pclk);

            // VSYNC high for a few lines
            cam_href = 1'b0;
            for (cyc = 0; cyc < VS_LINES * LINE_PCLKS; cyc = cyc + 1) begin
                cam_vsync = 1'b1;
                cam_data  = 8'h55;
                tick;
            end
            cam_vsync = 1'b0;

            // back porch lines
            for (cyc = 0; cyc < BP_LINES * LINE_PCLKS; cyc = cyc + 1) begin
                cam_data = 8'hAA;
                tick;
            end

            // active lines
            for (fy = 0; fy < IMG_H; fy = fy + 1) begin
                for (fk = 0; fk < LINE_PCLKS; fk = fk + 1) begin
                    if (fk < 2 * IMG_W) begin
                        pv       = pix(fk / 2, fy);
                        cam_href = 1'b1;
                        cam_data = (fk % 2 == 0) ? pv[15:8] : pv[7:0];
                    end else begin
                        cam_href = 1'b0;
                        cam_data = 8'hAA;           // garbage while HREF low
                    end
                    tick;
                end
            end
            cam_href = 1'b0;

            // front porch
            for (cyc = 0; cyc < FP_LINES * LINE_PCLKS; cyc = cyc + 1) begin
                cam_data = 8'hAA;
                tick;
            end
        end
    end

    // =========================================================================
    // SCCB slave + checker (sampled on the 50 MHz clock)
    // =========================================================================
    reg [7:0] exp_reg [0:N_CFG_REGS-1];
    reg [7:0] exp_val [0:N_CFG_REGS-1];
    initial begin
        exp_reg[ 0] = 8'h12; exp_val[ 0] = 8'h80;
        exp_reg[ 1] = 8'h12; exp_val[ 1] = 8'h80;
        exp_reg[ 2] = 8'h11; exp_val[ 2] = 8'h00;
        exp_reg[ 3] = 8'h3A; exp_val[ 3] = 8'h04;
        exp_reg[ 4] = 8'h12; exp_val[ 4] = 8'h04;
        exp_reg[ 5] = 8'h17; exp_val[ 5] = 8'h13;
        exp_reg[ 6] = 8'h18; exp_val[ 6] = 8'h01;
        exp_reg[ 7] = 8'h32; exp_val[ 7] = 8'hB6;
        exp_reg[ 8] = 8'h19; exp_val[ 8] = 8'h02;
        exp_reg[ 9] = 8'h1A; exp_val[ 9] = 8'h7A;
        exp_reg[10] = 8'h03; exp_val[10] = 8'h0A;
        exp_reg[11] = 8'h0C; exp_val[11] = 8'h04;
        exp_reg[12] = 8'h3E; exp_val[12] = 8'h1A;
        exp_reg[13] = 8'h40; exp_val[13] = 8'hD0;
        exp_reg[14] = 8'h15; exp_val[14] = 8'h00;
        exp_reg[15] = 8'h1E; exp_val[15] = 8'h00;
        exp_reg[16] = 8'h3D; exp_val[16] = 8'h88;
        exp_reg[17] = 8'h72; exp_val[17] = 8'h22;
        exp_reg[18] = 8'h73; exp_val[18] = 8'hF2;
    end

    reg        sda_low = 1'b0;                       // slave pulls SDA low (ACK)
    assign cam_siod = sda_low ? 1'b0 : 1'bz;

    reg        scl_p = 1'b1, sda_p = 1'b1;
    reg        scl_now, sda_now;
    reg        in_xfer = 1'b0;
    integer    bitcnt = 0, bytecnt = 0;
    integer    sccb_writes = 0, widx = 0;
    reg [7:0]  shreg = 8'h00, rx0 = 8'h00, rx1 = 8'h00, rx2 = 8'h00;
    time       t_scl_rise = 0;

    // a new configuration pass starts every time the camera is reset
    always @(negedge cam_reset_n) begin
        widx        = 0;
        sccb_writes = 0;
    end

    always @(posedge CLK_50MHz) begin
        scl_now = (cam_sioc === 1'b0) ? 1'b0 : 1'b1;
        sda_now = (cam_siod === 1'b0) ? 1'b0 : 1'b1;

        if (scl_now && scl_p && sda_p && !sda_now) begin
            // START condition
            in_xfer = 1'b1;
            bitcnt  = 0;
            bytecnt = 0;
        end
        else if (scl_now && scl_p && !sda_p && sda_now) begin
            // STOP condition
            if (in_xfer) begin
                if (bytecnt != 3) begin
                    `FAIL("SCCB transfer is not exactly 3 bytes")
                end else begin
                    if (rx0 !== 8'h42) begin
                        $display("      device address byte = 0x%02h (expected 0x42)", rx0);
                        `FAIL("SCCB wrong device address")
                    end
                    if (widx < N_CFG_REGS) begin
                        if (rx1 !== exp_reg[widx] || rx2 !== exp_val[widx]) begin
                            $display("      write %0d: got 0x%02h=0x%02h, expected 0x%02h=0x%02h",
                                     widx, rx1, rx2, exp_reg[widx], exp_val[widx]);
                            `FAIL("SCCB register write mismatch")
                        end else begin
                            $display("  SCCB write %2d: reg 0x%02h = 0x%02h  ok", widx, rx1, rx2);
                        end
                    end else begin
                        `FAIL("more SCCB writes than expected")
                    end
                    sccb_writes = sccb_writes + 1;
                    widx        = widx + 1;
                end
                in_xfer = 1'b0;
            end
        end
        else begin
            if (scl_now && !scl_p) begin
                // SCL rising edge: sample data bit / ACK clock
                if (in_xfer) begin
                    if (bitcnt < 8) shreg = {shreg[6:0], sda_now};
                    bitcnt = bitcnt + 1;
                    if (t_scl_rise != 0 && ($time - t_scl_rise) < 15000) begin
                        if (($time - t_scl_rise) < 9900 || ($time - t_scl_rise) > 10100) begin
                            `FAIL("SCCB clock period is not 10 us (100 kHz)")
                        end
                    end
                    t_scl_rise = $time;
                end
            end
            if (!scl_now && scl_p) begin
                // SCL falling edge: drive ACK after 8 bits, release after it
                if (in_xfer) begin
                    if (bitcnt == 8) begin
                        sda_low = 1'b1;
                    end else if (bitcnt == 9) begin
                        sda_low = 1'b0;
                        bitcnt  = 0;
                        if      (bytecnt == 0) rx0 = shreg;
                        else if (bytecnt == 1) rx1 = shreg;
                        else if (bytecnt == 2) rx2 = shreg;
                        bytecnt = bytecnt + 1;
                    end
                end
            end
        end

        scl_p = scl_now;
        sda_p = sda_now;
    end

    // =========================================================================
    // Capture / sobel-stream monitor (camera clock domain)
    // =========================================================================
    integer pix_cnt   = 0;
    integer s_cnt     = 0;
    integer frame_cnt = 0;
    integer cap_msgs  = 0;

    always @(posedge cam_pclk) begin
        if (dut.cap_we) begin
            if (dut.cap_waddr == 15'd0) begin
                pix_cnt = 0;
                s_cnt   = 0;
            end

            if (dut.cap_waddr !== pix_cnt[14:0]) begin
                if (cap_msgs < 5) $display("      capture waddr = %0d, expected %0d", dut.cap_waddr, pix_cnt);
                cap_msgs = cap_msgs + 1;
                `FAIL("capture address sequence broken")
            end
            if (dut.cap_wdata !== pix(dut.cap_waddr % IMG_W, dut.cap_waddr / IMG_W)) begin
                if (cap_msgs < 5) $display("      capture data at %0d = 0x%04h, expected 0x%04h",
                                           dut.cap_waddr, dut.cap_wdata,
                                           pix(dut.cap_waddr % IMG_W, dut.cap_waddr / IMG_W));
                cap_msgs = cap_msgs + 1;
                `FAIL("capture pixel data wrong")
            end

            pix_cnt = pix_cnt + 1;

            if (dut.s_we) begin
                s_cnt = s_cnt + 1;
                if (dut.s_waddr < 15'd161 || dut.s_waddr > 15'd19038) begin
                    `FAIL("sobel write address out of range")
                end
            end

            if (dut.cap_waddr == NPIX - 1) begin
                frame_cnt = frame_cnt + 1;
                if (pix_cnt != NPIX) begin
                    `FAIL("frame did not contain 19200 pixels")
                end
                if (s_cnt != SOBEL_WRITES) begin
                    $display("      sobel writes per frame = %0d, expected %0d", s_cnt, SOBEL_WRITES);
                    `FAIL("wrong number of sobel writes per frame")
                end
            end
        end
    end

    // =========================================================================
    // VGA monitors (pixel clock domain)
    // =========================================================================
    // ---- sync timing ----------------------------------------------------
    integer hs_cnt = 0, hs_low_cnt = 0, vs_lines = 0, vs_low_lines = 0, de_in_frame = 0;
    integer vga_frames_ok = 0;
    reg     hs_p = 1'b1, vs_p = 1'b1, hs_seen = 1'b0, vs_seen = 1'b0;

    always @(posedge clk_vga) begin
        hs_p <= vga_hs;
        vs_p <= vga_vs;

        if (dut.u_vga.vga_de) de_in_frame = de_in_frame + 1;

        // horizontal
        if (hs_p && !vga_hs) begin                 // hsync falling edge
            if (hs_seen && hs_cnt != 800) begin
                $display("      hsync period = %0d clocks (expected 800)", hs_cnt);
                `FAIL("hsync period wrong")
            end
            hs_cnt     = 0;
            hs_low_cnt = 0;
            hs_seen    = 1'b1;
            vs_lines   = vs_lines + 1;
            if (!vga_vs) vs_low_lines = vs_low_lines + 1;
        end
        if (!hs_p && vga_hs && hs_seen) begin      // hsync rising edge
            if (hs_low_cnt != 96) begin
                $display("      hsync low = %0d clocks (expected 96)", hs_low_cnt);
                `FAIL("hsync pulse width wrong")
            end
        end
        hs_cnt = hs_cnt + 1;
        if (!vga_hs) hs_low_cnt = hs_low_cnt + 1;

        // vertical
        if (vs_p && !vga_vs) begin                 // vsync falling edge
            if (vs_seen) begin
                if (vs_lines != 525) begin
                    $display("      lines per frame = %0d (expected 525)", vs_lines);
                    `FAIL("vsync period wrong")
                end
                if (de_in_frame != VGA_PIX) begin
                    $display("      visible pixels per frame = %0d (expected %0d)", de_in_frame, VGA_PIX);
                    `FAIL("visible window size wrong")
                end
                if (vs_lines == 525 && de_in_frame == VGA_PIX) vga_frames_ok = vga_frames_ok + 1;
            end
            vs_lines     = 0;
            vs_low_lines = 0;
            de_in_frame  = 0;
            vs_seen      = 1'b1;
        end
        if (!vs_p && vga_vs && vs_seen) begin      // vsync rising edge
            if (vs_low_lines != 2) begin
                $display("      vsync low for %0d lines (expected 2)", vs_low_lines);
                `FAIL("vsync pulse width wrong")
            end
        end
    end

    // ---- read address must stay inside the buffer -----------------------
    always @(posedge clk_vga)
        if (dut.fb_raddr >= NPIX) begin
            `FAIL("VGA read address outside frame buffer")
        end

    // ---- every visible pixel against the frame buffer -------------------
    reg         vga_check_en = 1'b0;
    reg         vga_sync_ok  = 1'b0;
    reg         de_p = 1'b0, vs_p2 = 1'b1;
    integer     ox = 0, oy = 0, chk_pix = 0, vga_msgs = 0, eaddr;
    reg  [15:0] exp_pixel;

    always @(posedge clk_vga) begin
        de_p  <= dut.u_vga.vga_de;
        vs_p2 <= vga_vs;

        if (vs_p2 && !vga_vs) begin
            ox          = 0;
            oy          = 0;
            vga_sync_ok = 1'b1;
        end
        else if (dut.u_vga.vga_de) begin
            if (vga_sync_ok && vga_check_en) begin
                eaddr     = (oy / 4) * IMG_W + (ox / 4);
                exp_pixel = dut.u_fb.mem[eaddr];
                if ({vga_r, vga_g, vga_b} !== exp_pixel) begin
                    if (vga_msgs < 5)
                        $display("      VGA (x=%0d,y=%0d) = 0x%04h, buffer[%0d] = 0x%04h",
                                 ox, oy, {vga_r, vga_g, vga_b}, eaddr, exp_pixel);
                    vga_msgs = vga_msgs + 1;
                    `FAIL("VGA pixel differs from frame buffer")
                end
                chk_pix = chk_pix + 1;
            end
            ox = ox + 1;
        end
        else begin
            ox = 0;
            if (de_p) oy = oy + 1;                 // end of an active line
        end
    end

    // ---- during blanking the RGB outputs must be black ------------------
    always @(posedge clk_vga)
        if (vga_sync_ok && !dut.u_vga.vga_de && ({vga_r, vga_g, vga_b} !== 16'h0000)) begin
            `FAIL("RGB not black outside the visible area")
        end

    // =========================================================================
    // Frame buffer content checks
    // =========================================================================
    task check_raw_mem;
        integer a, bad;
        begin
            bad = 0;
            for (a = 0; a < NPIX; a = a + 1) begin
                if (dut.u_fb.mem[a] !== pix(a % IMG_W, a / IMG_W)) begin
                    if (bad < 5)
                        $display("      raw mem[%0d] = 0x%04h, expected 0x%04h",
                                 a, dut.u_fb.mem[a], pix(a % IMG_W, a / IMG_W));
                    bad = bad + 1;
                end
            end
            if (bad != 0) begin
                $display("      %0d bad pixels", bad);
                `FAIL("frame buffer content wrong in raw mode")
            end else begin
                $display("[%0t] PASS: frame buffer holds the camera image (raw mode)", $time);
            end
        end
    endtask

    task check_sobel_mem;
        integer cx, cy, bad, nonzero;
        reg [15:0] e;
        begin
            bad = 0;
            nonzero = 0;
            for (cy = 1; cy <= IMG_H - 2; cy = cy + 1) begin
                for (cx = 1; cx <= IMG_W - 2; cx = cx + 1) begin
                    e = sobel_px(cx, cy);
                    if (e != 16'h0000) nonzero = nonzero + 1;
                    if (dut.u_fb.mem[cy * IMG_W + cx] !== e) begin
                        if (bad < 5)
                            $display("      sobel mem[%0d] (x=%0d,y=%0d) = 0x%04h, expected 0x%04h",
                                     cy * IMG_W + cx, cx, cy, dut.u_fb.mem[cy * IMG_W + cx], e);
                        bad = bad + 1;
                    end
                end
            end
            if (nonzero < 200) begin
                `FAIL("golden sobel image is almost empty - test pattern problem")
            end
            if (bad != 0) begin
                $display("      %0d bad pixels", bad);
                `FAIL("frame buffer content wrong in sobel mode")
            end else begin
                $display("[%0t] PASS: frame buffer holds the sobel edges (%0d non-zero pixels)", $time, nonzero);
            end
        end
    endtask

    // =========================================================================
    // Reset-low time of the camera (used by the reset-button test)
    // =========================================================================
    time t_rst_start = 0, t_rst_low = 0;
    always @(negedge cam_reset_n) t_rst_start = $time;
    always @(posedge cam_reset_n) t_rst_low   = $time - t_rst_start;

    // =========================================================================
    // Main sequence
    // =========================================================================
    integer f0;

    initial begin
        $timeformat(-3, 3, " ms", 12);
        if ($test$plusargs("vcd")) begin
            $dumpfile("tb_top.vcd");
            $dumpvars(1, tb_top);
        end
    end

    initial begin : watchdog
        #(SIM_TIMEOUT_NS);
        $display("[%0t] TIMEOUT - the testbench did not finish", $time);
        $display("*** FAILED (timeout) ***");
        $finish;
    end

    initial begin : main
        // ---- 1. power-up ------------------------------------------------
        #1000;
        if (LED[0] !== 1'b1) begin
            `FAIL("LED0 should be on at power-up / while in reset")
        end
        wait (LED[0] === 1'b0);
        $display("[%0t] reset released, LED0 off", $time);

        // ---- 2. SCCB configuration ---------------------------------------
        wait (dut.cam_ready === 1'b1);
        #1000;
        $display("[%0t] cam_ready asserted after %0d SCCB writes", $time, sccb_writes);
        if (sccb_writes != N_CFG_REGS) begin
            `FAIL("wrong number of SCCB writes before cam_ready")
        end

        // ---- 3. raw colour mode ------------------------------------------
        $display("[%0t] --- raw colour mode (KEY1 pressed) ---", $time);
        f0 = frame_cnt;
        wait (frame_cnt >= f0 + 2);
        #500;
        check_raw_mem;

        chk_pix = 0;
        vga_check_en = 1'b1;
        wait (chk_pix >= VGA_PIX);
        vga_check_en = 1'b0;
        $display("[%0t] VGA output checked against buffer (raw mode), %0d pixels", $time, chk_pix);

        // ---- 4. sobel mode -----------------------------------------------
        $display("[%0t] --- sobel mode (KEY1 released) ---", $time);
        key1_n = 1'b1;
        f0 = frame_cnt;
        wait (frame_cnt >= f0 + 2);
        #500;
        check_sobel_mem;

        chk_pix = 0;
        vga_check_en = 1'b1;
        wait (chk_pix >= VGA_PIX);
        vga_check_en = 1'b0;
        $display("[%0t] VGA output checked against buffer (sobel mode), %0d pixels", $time, chk_pix);

        if (vga_frames_ok < 2) begin
            `FAIL("fewer than 2 complete VGA frames with correct sync timing")
        end else begin
            $display("[%0t] PASS: %0d VGA frames with correct sync timing", $time, vga_frames_ok);
        end

        // ---- 5. LEDs (counters are pushed close to rollover) -------------
        $display("[%0t] --- LED blink check ---", $time);
        dut.cnt_6m = 22'h1FFFF0;                  // bit 21 rises after 16 PCLKs
        #10_000;
        if (LED[1] !== 1'b1) begin `FAIL("LED1 did not turn on (PCLK counter)") end
        dut.cnt_6m = 22'h3FFFF0;                  // wraps, bit 21 falls
        #10_000;
        if (LED[1] !== 1'b0) begin `FAIL("LED1 did not turn off (PCLK counter)") end

        dut.cnt_25m = 24'h7FFFF0;                 // bit 23 rises after 16 VGA clocks
        #5_000;
        if (LED[2] !== 1'b1) begin `FAIL("LED2 did not turn on (VGA counter)") end
        dut.cnt_25m = 24'hFFFFF0;                 // wraps
        #5_000;
        if (LED[2] !== 1'b0) begin `FAIL("LED2 did not turn off (VGA counter)") end
        $display("[%0t] LED1/LED2 toggling checked", $time);

        // ---- 6. reset button ---------------------------------------------
        $display("[%0t] --- reset button ---", $time);
        key_n = 1'b0;
        #2000;
        if (LED[0] !== 1'b1)        begin `FAIL("LED0 not on while reset pressed")       end
        if (cam_reset_n !== 1'b0)   begin `FAIL("camera reset not asserted by KEY0")     end
        if (dut.cam_ready !== 1'b0) begin `FAIL("cam_ready not cleared by reset")        end
        #20_000;
        key_n = 1'b1;
        wait (LED[0] === 1'b0);
        wait (dut.cam_ready === 1'b1);            // SCCB re-configures the camera
        #1000;
        if (t_rst_low < RESET_CYCLES * 20) begin
            $display("      cam_reset_n low for %0d ns, expected >= %0d ns", t_rst_low, RESET_CYCLES * 20);
            `FAIL("camera reset pulse too short")
        end
        if (sccb_writes != N_CFG_REGS) begin
            `FAIL("camera was not fully re-configured after reset")
        end else begin
            $display("[%0t] PASS: reset button restarts camera init and SCCB configuration", $time);
        end

        f0 = frame_cnt;
        wait (frame_cnt >= f0 + 1);
        $display("[%0t] capture works again after reset", $time);

        // ---- summary -------------------------------------------------------
        #1000;
        $display("");
        if (errors == 0) $display("*** ALL CHECKS PASSED ***");
        else             $display("*** %0d CHECK(S) FAILED ***", errors);
        $finish;
    end

endmodule
