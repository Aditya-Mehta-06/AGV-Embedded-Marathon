`timescale 1ns/1ps
//==============================================================================
// tb_top.v  -  self-checking system testbench
//
// DUT chain : init_ctrl -> sccb_cfg(sccb_configure + sccb_controller) -> OV7670
//             cam_capture -> frame_buffer -> vga_ctrl
//
// The testbench provides:
//   * CLK_50MHz (50 MHz), clk_cam (24 MHz, becomes cam_xclk), clk_vga (25 MHz)
//   * rst_n (active low) - replaces the key/PLL-lock you will add later
//   * a behavioural OV7670: SCCB slave (ACKs every byte), PCLK = XCLK/4,
//     and a 160x120 RGB565 frame generator (VSYNC/HREF/D[7:0]) that starts
//     streaming as soon as cam_reset_n is released (like the real sensor)
//
// Checks (each prints [FAIL][tag] on error, [INFO] on milestones):
//   INIT : camera reset width, wait before SCCB, pwdn, 1 start / 1 done pulse,
//          cam_ready only after all 19 registers were written
//   SCCB : START/STOP framing, device address 0x42, every reg/data pair vs the
//          ROM, 100 kHz SCL, ACK slot released by master, delay after COM7 reset
//   CAP  : no writes before cam_ready, waits for next VSYNC, 19200 sequential
//          writes per frame, data == expected RGB565, frame_cnt
//   FB   : full RAM contents compared with expected image after first frame
//   VGA  : hsync 96 / period 800, vsync 2 lines / period 525 lines, 640x480
//          active, blanking is black, every displayed pixel == RAM pixel
//          (160x120 upscaled x4); optional PPM dump of one frame
//
// Run (Icarus):
//   iverilog -g2005 -o sim tb_top.v top.v init_ctrl.v sccb_cfg.v \
//            sccb_configure.v sccb_controller.v cam_capture.v \
//            frame_buffer.v vga_ctrl.v
//   vvp sim
//==============================================================================
module tb_top;

    //--------------------------------------------------------------------------
    // Knobs
    //--------------------------------------------------------------------------
    parameter integer TB_RESET_CYCLES     = 50;       // shrunk from 50_000
    parameter integer TB_WAIT_CYCLES      = 100;      // shrunk from 100_000
    parameter [23:0]  TB_SCCB_RESET_DELAY = 24'd2000; // shrunk from 10_000_000
    parameter integer PATTERN_MODE        = 0;        // 0: unique per pixel (strict), 1: colour bars + ramps
    parameter integer HBLANK              = 40;       // pclk cycles between lines
    parameter integer VSYNC_LINES         = 3;
    parameter integer VBP_LINES           = 2;
    parameter integer VFP_LINES           = 2;
    parameter integer VGA_FRAMES_TO_CHECK = 1;        // full VGA frames compared pixel by pixel
    parameter integer TIMEOUT_MS          = 150;
    parameter integer DUMP_PPM            = 1;        // write vga_frame.ppm

    localparam integer W       = 160;
    localparam integer H       = 120;
    localparam integer NPIX    = 19200;
    localparam integer N_REGS  = 19;
    localparam integer LINE_TP = 2*W + HBLANK;        // pclk cycles per camera line

    //--------------------------------------------------------------------------
    // Signals
    //--------------------------------------------------------------------------
    reg         rst_n;
    reg         CLK_50MHz = 1'b0;
    reg         clk_cam   = 1'b0;
    reg         clk_vga   = 1'b0;

    wire        cam_xclk;
    reg         cam_pclk  = 1'b0;
    reg         cam_vsync = 1'b0;
    reg         cam_href  = 1'b0;
    reg  [7:0]  cam_data  = 8'd0;
    wire        cam_reset_n;
    wire        cam_pwdn;
    wire        cam_sioc;
    tri1        cam_siod;                // SCCB data line, with pull-up

    wire [4:0]  vga_r;
    wire [5:0]  vga_g;
    wire [4:0]  vga_b;
    wire        vga_hs, vga_vs;

    integer err_init = 0, err_sccb = 0, err_cap = 0, err_fb = 0, err_vga = 0;
    reg     mon_en = 1'b0;               // monitors start when reset is released
    time    t_rstn_release = 0;

    top #(
        .RESET_CYCLES     (TB_RESET_CYCLES),
        .WAIT_CYCLES      (TB_WAIT_CYCLES),
        .SCCB_RESET_DELAY (TB_SCCB_RESET_DELAY)
    ) dut (
        .rst_n       (rst_n),
        .clk_cam     (clk_cam),
        .clk_vga     (clk_vga),
        .CLK_50MHz   (CLK_50MHz),
        .cam_xclk    (cam_xclk),
        .cam_pclk    (cam_pclk),
        .cam_vsync   (cam_vsync),
        .cam_href    (cam_href),
        .cam_data    (cam_data),
        .cam_reset_n (cam_reset_n),
        .cam_pwdn    (cam_pwdn),
        .cam_sioc    (cam_sioc),
        .cam_siod    (cam_siod),
        .vga_r       (vga_r),
        .vga_g       (vga_g),
        .vga_b       (vga_b),
        .vga_hs      (vga_hs),
        .vga_vs      (vga_vs)
    );

    //--------------------------------------------------------------------------
    // Clocks and reset
    //--------------------------------------------------------------------------
    always #10      CLK_50MHz = ~CLK_50MHz;   // 50 MHz
    always #20.8333 clk_cam   = ~clk_cam;     // 24 MHz
    always #20      clk_vga   = ~clk_vga;     // 25 MHz

    initial begin
        $timeformat(-9, 0, " ns", 0);
        rst_n = 1'b1;
        #55  rst_n = 1'b0;                    // real 1->0 edge so async resets fire
        #200 rst_n = 1'b1;
        t_rstn_release = $time;
        mon_en = 1'b1;
        $display("[INFO] %t reset released", $time);
    end

    //--------------------------------------------------------------------------
    // Test image (shared by camera model and checkers)
    //--------------------------------------------------------------------------
    function [15:0] pix_fn;
        input integer x;
        input integer y;
        integer r, g, b, bar;
        begin
            if (PATTERN_MODE == 0) begin
                pix_fn = {y[6:0], x[7:0], (x[0] ^ y[0])};   // unique for every (x,y)
            end else begin
                if (y < 80) begin
                    bar = x / 20;
                    case (bar)
                        0: pix_fn = 16'hFFFF;
                        1: pix_fn = 16'hFFE0;
                        2: pix_fn = 16'h07FF;
                        3: pix_fn = 16'h07E0;
                        4: pix_fn = 16'hF81F;
                        5: pix_fn = 16'hF800;
                        6: pix_fn = 16'h001F;
                        default: pix_fn = 16'h0000;
                    endcase
                end else begin
                    r = (x * 31) / 159;
                    g = ((y - 80) * 63) / 39;
                    b = 31 - r;
                    pix_fn = {r[4:0], g[5:0], b[4:0]};
                end
            end
        end
    endfunction

    //--------------------------------------------------------------------------
    // Camera model : PCLK = XCLK/4 (runs only while cam_reset_n is high)
    //--------------------------------------------------------------------------
    reg [1:0] pclk_div = 2'd0;
    always @(posedge cam_xclk or negedge cam_reset_n) begin
        if (!cam_reset_n) begin
            pclk_div <= 2'd0;
            cam_pclk <= 1'b0;
        end else begin
            pclk_div <= pclk_div + 2'd1;
            if (pclk_div[0]) cam_pclk <= ~cam_pclk;      // toggles on div=1,3 -> /4
        end
    end

    // Camera model : frame generator. Outputs change on PCLK falling edge,
    // so the DUT samples stable data on the rising edge. Data is random junk
    // whenever HREF is low, to prove the capture logic gates on HREF.
    integer    cx, cy;
    reg [15:0] cpix;
    integer    cam_frame_num = 0;

    task send_frame;
        begin
            cam_frame_num = cam_frame_num + 1;
            @(negedge cam_pclk);
            cam_vsync = 1'b1;
            repeat (VSYNC_LINES*LINE_TP) begin
                @(negedge cam_pclk);
                cam_data = $random;
            end
            cam_vsync = 1'b0;
            repeat (VBP_LINES*LINE_TP) begin
                @(negedge cam_pclk);
                cam_data = $random;
            end
            for (cy = 0; cy < H; cy = cy + 1) begin
                for (cx = 0; cx < W; cx = cx + 1) begin
                    cpix     = pix_fn(cx, cy);
                    cam_href = 1'b1;
                    cam_data = cpix[15:8];               // RRRRRGGG
                    @(negedge cam_pclk);
                    cam_data = cpix[7:0];                // GGGBBBBB
                    @(negedge cam_pclk);
                end
                cam_href = 1'b0;
                repeat (HBLANK) begin
                    cam_data = $random;
                    @(negedge cam_pclk);
                end
            end
            repeat (VFP_LINES*LINE_TP) begin
                cam_data = $random;
                @(negedge cam_pclk);
            end
        end
    endtask

    initial begin
        @(posedge cam_reset_n);                          // sensor starts streaming after reset
        repeat (8) @(negedge cam_pclk);
        forever send_frame;
    end

    //--------------------------------------------------------------------------
    // Camera model : SCCB slave (write transactions only)
    //   frame = START, 0x42, reg, data, STOP ; slave ACKs every byte
    //--------------------------------------------------------------------------
    reg        slave_ack_low = 1'b0;
    assign cam_siod = slave_ack_low ? 1'b0 : 1'bz;

    reg        in_xfer   = 1'b0;
    integer    s_bitcnt  = 0, s_bytecnt = 0, wr_count = 0;
    reg [7:0]  s_shreg   = 8'd0, s_b0 = 8'd0, s_b1 = 8'd0, s_b2 = 8'd0;
    reg [7:0]  exp_addr [0:N_REGS-1];
    reg [7:0]  exp_data [0:N_REGS-1];
    reg [7:0]  cam_regs [0:255];
    time       t_xfer_start = 0, t_prev_stop = 0, t_scl_last = 0;
    time       t_gap = 0, t_dt = 0;
    time       t_cam_rst_rise = 0, t_first_start = 0, t_ready = 0;
    reg        scl_valid = 1'b0;

    // expected register ROM (mirror of sccb_configure.v - update if you change it)
    initial begin
        exp_addr[ 0] = 8'h12; exp_data[ 0] = 8'h80;
        exp_addr[ 1] = 8'h12; exp_data[ 1] = 8'h80;
        exp_addr[ 2] = 8'h11; exp_data[ 2] = 8'h80;
        exp_addr[ 3] = 8'h3A; exp_data[ 3] = 8'h04;
        exp_addr[ 4] = 8'h12; exp_data[ 4] = 8'h04;
        exp_addr[ 5] = 8'h17; exp_data[ 5] = 8'h13;
        exp_addr[ 6] = 8'h18; exp_data[ 6] = 8'h01;
        exp_addr[ 7] = 8'h32; exp_data[ 7] = 8'h36;
        exp_addr[ 8] = 8'h19; exp_data[ 8] = 8'h02;
        exp_addr[ 9] = 8'h1A; exp_data[ 9] = 8'h7A;
        exp_addr[10] = 8'h03; exp_data[10] = 8'h0A;
        exp_addr[11] = 8'h0C; exp_data[11] = 8'h04;
        exp_addr[12] = 8'h3E; exp_data[12] = 8'h1A;
        exp_addr[13] = 8'h40; exp_data[13] = 8'hD0;
        exp_addr[14] = 8'h15; exp_data[14] = 8'h00;
        exp_addr[15] = 8'h1E; exp_data[15] = 8'h00;
        exp_addr[16] = 8'h3D; exp_data[16] = 8'h88;
        exp_addr[17] = 8'h72; exp_data[17] = 8'h22;
        exp_addr[18] = 8'h73; exp_data[18] = 8'hF2;
    end

    // START: SDA falls while SCL high. The 1 ns settle delay filters the
    // master changing SDA and SCL in the same clock edge (SCL falling).
    always @(negedge cam_siod) if (mon_en) begin
        #1;
        if (cam_sioc === 1'b1) begin
            if (in_xfer) begin
                err_sccb = err_sccb + 1;
                if (err_sccb <= 10) $display("[FAIL][SCCB] %t START while a transfer is already open", $time);
            end
            in_xfer      = 1'b1;
            s_bitcnt     = 0;
            s_bytecnt    = 0;
            scl_valid    = 1'b0;
            t_xfer_start = $time;
            if (wr_count == 0 && t_first_start == 0) begin
                t_first_start = $time;
                $display("[INFO] %t first SCCB transaction starts", $time);
                if ((t_first_start - t_cam_rst_rise) < (TB_WAIT_CYCLES-1)*20) begin
                    err_init = err_init + 1;
                    $display("[FAIL][INIT] %t SCCB began only %0d ns after camera reset release (need >= %0d)",
                             $time, t_first_start - t_cam_rst_rise, (TB_WAIT_CYCLES-1)*20);
                end
            end
        end
    end

    // STOP: SDA rises while SCL high
    always @(posedge cam_siod) if (mon_en && in_xfer) begin
        #1;
        if (cam_sioc === 1'b1) begin
            in_xfer       = 1'b0;
            slave_ack_low = 1'b0;
            if (s_bytecnt != 3 || s_bitcnt != 0) begin
                err_sccb = err_sccb + 1;
                if (err_sccb <= 10) $display("[FAIL][SCCB] %t STOP after %0d bytes + %0d bits (expected 3 bytes)",
                                             $time, s_bytecnt, s_bitcnt);
            end else begin
                if (s_b0 !== 8'h42) begin
                    err_sccb = err_sccb + 1;
                    if (err_sccb <= 10) $display("[FAIL][SCCB] %t device byte = %h, expected 42", $time, s_b0);
                end
                cam_regs[s_b1] = s_b2;
                if (wr_count < N_REGS) begin
                    if (s_b1 !== exp_addr[wr_count] || s_b2 !== exp_data[wr_count]) begin
                        err_sccb = err_sccb + 1;
                        if (err_sccb <= 10) $display("[FAIL][SCCB] %t write #%0d got reg %h = %h, expected reg %h = %h",
                                    $time, wr_count, s_b1, s_b2, exp_addr[wr_count], exp_data[wr_count]);
                    end
                end else begin
                    err_sccb = err_sccb + 1;
                    if (err_sccb <= 10) $display("[FAIL][SCCB] %t extra register write (reg %h = %h)", $time, s_b1, s_b2);
                end
                if (wr_count > 0) begin
                    t_gap = t_xfer_start - t_prev_stop;
                    if (wr_count == 1 || wr_count == 2) begin       // after each COM7 soft reset
                        if (t_gap < TB_SCCB_RESET_DELAY*20) begin
                            err_sccb = err_sccb + 1;
                            if (err_sccb <= 10) $display("[FAIL][SCCB] %t gap after COM7 reset only %0d ns (need >= %0d)",
                                                         $time, t_gap, TB_SCCB_RESET_DELAY*20);
                        end
                    end else if (t_gap > 40000) begin
                        err_sccb = err_sccb + 1;
                        if (err_sccb <= 10) $display("[FAIL][SCCB] %t unexpected %0d ns gap between writes", $time, t_gap);
                    end
                end
                wr_count    = wr_count + 1;
                t_prev_stop = $time;
            end
        end
    end

    // Sample on SCL rising edge
    always @(posedge cam_sioc) if (mon_en && in_xfer) begin
        if (scl_valid) begin
            t_dt = $time - t_scl_last;
            if (t_dt < 9980 || t_dt > 10020) begin
                err_sccb = err_sccb + 1;
                if (err_sccb <= 10) $display("[FAIL][SCCB] %t SCL period %0d ns (expected 10000)", $time, t_dt);
            end
        end
        scl_valid  = 1'b1;
        t_scl_last = $time;

        if (s_bytecnt >= 3) begin
            // SCL pulse that is part of the STOP sequence (after the 3rd ACK): not a data bit
        end else if (s_bitcnt < 8) begin
            s_shreg  = {s_shreg[6:0], cam_siod};
            s_bitcnt = s_bitcnt + 1;
            if (s_bitcnt == 8) begin
                case (s_bytecnt)
                    0: s_b0 = s_shreg;
                    1: s_b1 = s_shreg;
                    2: s_b2 = s_shreg;
                    default: begin
                        err_sccb = err_sccb + 1;
                        if (err_sccb <= 10) $display("[FAIL][SCCB] %t more than 3 bytes in one transaction", $time);
                    end
                endcase
            end
        end else begin
            // 9th clock = ACK slot: master must have released SDA
            if (dut.u_sccb.siod_o !== 1'b1) begin
                err_sccb = err_sccb + 1;
                if (err_sccb <= 10) $display("[FAIL][SCCB] %t master still driving SDA during ACK slot", $time);
            end
            s_bitcnt  = 0;
            s_bytecnt = s_bytecnt + 1;
        end
    end

    // Drive ACK (SDA low) during the 9th clock
    always @(negedge cam_sioc) if (mon_en && in_xfer) slave_ack_low = (s_bitcnt == 8);

    //--------------------------------------------------------------------------
    // INIT monitors
    //--------------------------------------------------------------------------
    integer start_pulses = 0, done_pulses = 0;
    time    dly;

    always @(posedge cam_reset_n) if (mon_en) begin
        t_cam_rst_rise = $time;
        dly = $time - t_rstn_release;
        $display("[INFO] %t camera reset released (low for ~%0d ns)", $time, dly);
        if (dly < (TB_RESET_CYCLES-1)*20 || dly > (TB_RESET_CYCLES+3)*20) begin
            err_init = err_init + 1;
            $display("[FAIL][INIT] camera reset width %0d ns, expected ~%0d ns", dly, TB_RESET_CYCLES*20);
        end
    end

    always @(posedge CLK_50MHz) if (mon_en && cam_pwdn !== 1'b0) begin
        err_init = err_init + 1;
        if (err_init <= 10) $display("[FAIL][INIT] %t cam_pwdn not low", $time);
    end

    always @(posedge dut.sccb_start) if (mon_en) start_pulses = start_pulses + 1;
    always @(posedge dut.sccb_done)  if (mon_en) done_pulses  = done_pulses  + 1;

    always @(posedge dut.cam_ready) if (mon_en) begin
        t_ready = $time;
        if (wr_count != N_REGS) begin
            err_init = err_init + 1;
            $display("[FAIL][INIT] %t cam_ready rose after only %0d/%0d register writes", $time, wr_count, N_REGS);
        end else
            $display("[INFO] %t cam_ready asserted, all %0d registers written", $time, wr_count);
    end

    always @(negedge dut.cam_ready) if (mon_en && t_ready != 0) begin
        err_init = err_init + 1;
        $display("[FAIL][INIT] %t cam_ready dropped after being asserted", $time);
    end

    //--------------------------------------------------------------------------
    // CAP / FB monitors (sampled on cam_pclk, same view as the RAM write port)
    //--------------------------------------------------------------------------
    integer    ready_age = 0, cap_wr_cnt = 0, cap_frames_done = 0, vs_since_ready = 0;
    integer    fi, fb_bad;
    reg        armed_tb = 1'b0, vs_prev = 1'b0, fb_full_done = 1'b0;
    reg [15:0] exp_pix;
    event      fb_full_evt, fc_chk_evt;

    always @(posedge cam_pclk) begin
        if (mon_en) begin
            vs_prev <= cam_vsync;

            if (dut.cam_ready === 1'b1) ready_age = ready_age + 1;
            else                        ready_age = 0;

            // new frame seen by the camera while capture is enabled
            if (cam_vsync && !vs_prev && ready_age >= 3) begin
                if (armed_tb && cap_wr_cnt != NPIX) begin
                    err_cap = err_cap + 1;
                    if (err_cap <= 10) $display("[FAIL][CAP] %t frame ended with %0d writes (expected %0d)",
                                                $time, cap_wr_cnt, NPIX);
                end
                if (!armed_tb)
                    $display("[INFO] %t first VSYNC after cam_ready -> capture armed (camera frame #%0d)",
                             $time, cam_frame_num);
                armed_tb       = 1'b1;
                vs_since_ready = vs_since_ready + 1;
                cap_wr_cnt     = 0;
            end

            // frame-buffer write port
            if (dut.fb_we === 1'b1) begin
                if (!armed_tb) begin
                    err_cap = err_cap + 1;
                    if (err_cap <= 10) $display("[FAIL][CAP] %t write before cam_ready/VSYNC arming", $time);
                end else begin
                    if (dut.fb_waddr !== cap_wr_cnt[14:0]) begin
                        err_cap = err_cap + 1;
                        if (err_cap <= 10) $display("[FAIL][CAP] %t waddr = %0d, expected %0d",
                                                    $time, dut.fb_waddr, cap_wr_cnt);
                    end
                    exp_pix = pix_fn(dut.fb_waddr % W, dut.fb_waddr / W);
                    if (dut.fb_wdata !== exp_pix) begin
                        err_cap = err_cap + 1;
                        if (err_cap <= 10) $display("[FAIL][CAP] %t pixel %0d wdata = %h, expected %h",
                                                    $time, dut.fb_waddr, dut.fb_wdata, exp_pix);
                    end
                    cap_wr_cnt = cap_wr_cnt + 1;
                    if (cap_wr_cnt == NPIX) begin
                        cap_frames_done = cap_frames_done + 1;
                        -> fc_chk_evt;
                        if (cap_frames_done == 1) -> fb_full_evt;
                    end
                end
            end
        end
    end

    // frame_cnt: first armed VSYNC does not count, each later one adds 1
    always @(fc_chk_evt) begin
        #1;
        if (dut.frame_cnt !== ((vs_since_ready - 1) & 31)) begin
            err_cap = err_cap + 1;
            if (err_cap <= 10) $display("[FAIL][CAP] %t frame_cnt = %0d, expected %0d",
                                        $time, dut.frame_cnt, (vs_since_ready - 1) & 31);
        end
    end

    // Whole-RAM compare after the first complete captured frame
    always @(fb_full_evt) begin
        #1;
        fb_bad = 0;
        for (fi = 0; fi < NPIX; fi = fi + 1) begin
            if (dut.u_fb.mem[fi] !== pix_fn(fi % W, fi / W)) begin
                fb_bad = fb_bad + 1;
                if (fb_bad <= 5) $display("[FAIL][FB] mem[%0d] = %h, expected %h",
                                          fi, dut.u_fb.mem[fi], pix_fn(fi % W, fi / W));
            end
        end
        err_fb = err_fb + fb_bad;
        fb_full_done = 1'b1;
        $display("[INFO] %t first full frame captured; frame buffer scan: %0d mismatches", $time, fb_bad);
    end

    //--------------------------------------------------------------------------
    // VGA monitor
    //--------------------------------------------------------------------------
    wire        vga_de_w = dut.u_vga.vga_de;

    integer     x_cnt = 0, y_cnt = 0;
    integer     clk_since_hs_fall = 0, hs_low = 0, clk_since_vs_fall = 0, vs_low = 0;
    integer     frames_checked = 0, vga_pix_checked = 0, blank_bad = 0;
    reg         hs_d = 1'b1, vs_d = 1'b1, de_d = 1'b0, hs_seen = 1'b0, vs_seen = 1'b0;
    reg         pix_chk_on = 1'b0, vga_done = 1'b0;
    reg  [15:0] img [0:640*480-1];
    reg  [15:0] got_pix, vga_exp;

    task dump_ppm;
        integer i, fd;
        reg [15:0] p;
        begin
            fd = $fopen("vga_frame.ppm", "w");
            $fdisplay(fd, "P3");
            $fdisplay(fd, "640 480");
            $fdisplay(fd, "255");
            for (i = 0; i < 640*480; i = i + 1) begin
                p = img[i];
                $fdisplay(fd, "%0d %0d %0d", {p[15:11], p[15:13]}, {p[10:5], p[10:9]}, {p[4:0], p[4:2]});
            end
            $fclose(fd);
            $display("[INFO] wrote vga_frame.ppm");
        end
    endtask

    always @(posedge clk_vga) begin
        hs_d <= vga_hs;
        vs_d <= vga_vs;
        de_d <= vga_de_w;

        if (mon_en) begin
            clk_since_hs_fall = clk_since_hs_fall + 1;
            clk_since_vs_fall = clk_since_vs_fall + 1;
            if (!vga_hs) hs_low = hs_low + 1;
            if (!vga_vs) vs_low = vs_low + 1;

            // ---- hsync
            if (hs_d && !vga_hs) begin
                if (hs_seen && clk_since_hs_fall != 800) begin
                    err_vga = err_vga + 1;
                    if (err_vga <= 10) $display("[FAIL][VGA] %t hsync period %0d clocks (expected 800)", $time, clk_since_hs_fall);
                end
                hs_seen = 1'b1;
                clk_since_hs_fall = 0;
            end
            if (!hs_d && vga_hs) begin
                if (hs_low != 96) begin
                    err_vga = err_vga + 1;
                    if (err_vga <= 10) $display("[FAIL][VGA] %t hsync low for %0d clocks (expected 96)", $time, hs_low);
                end
                hs_low = 0;
            end

            // ---- vsync
            if (vs_d && !vga_vs) begin
                if (vs_seen && clk_since_vs_fall != 525*800) begin
                    err_vga = err_vga + 1;
                    if (err_vga <= 10) $display("[FAIL][VGA] %t vsync period %0d clocks (expected %0d)", $time, clk_since_vs_fall, 525*800);
                end
                vs_seen = 1'b1;
                clk_since_vs_fall = 0;
            end
            if (!vs_d && vga_vs) begin
                if (vs_low != 2*800) begin
                    err_vga = err_vga + 1;
                    if (err_vga <= 10) $display("[FAIL][VGA] %t vsync low for %0d clocks (expected %0d)", $time, vs_low, 2*800);
                end
                vs_low = 0;
            end

            // ---- active window start: 144 clocks after hsync falls (96 sync + 48 back porch)
            if (vga_de_w && !de_d && hs_seen && clk_since_hs_fall != 144) begin
                err_vga = err_vga + 1;
                if (err_vga <= 10) $display("[FAIL][VGA] %t active video starts %0d clocks after hsync fall (expected 144)", $time, clk_since_hs_fall);
            end

            // ---- pixels
            if (vga_de_w) begin
                if (pix_chk_on) begin
                    got_pix = {vga_r, vga_g, vga_b};
                    vga_exp = pix_fn(x_cnt / 4, y_cnt / 4);
                    vga_pix_checked = vga_pix_checked + 1;
                    if (got_pix !== vga_exp) begin
                        err_vga = err_vga + 1;
                        if (err_vga <= 10) $display("[FAIL][VGA] %t pixel (x=%0d,y=%0d) = %h, expected %h",
                                                    $time, x_cnt, y_cnt, got_pix, vga_exp);
                    end
                    if (x_cnt < 640 && y_cnt < 480) img[y_cnt*640 + x_cnt] = got_pix;
                end
                x_cnt = x_cnt + 1;
            end else begin
                if ({vga_r, vga_g, vga_b} !== 16'd0) begin
                    blank_bad = blank_bad + 1;
                    err_vga = err_vga + 1;
                    if (blank_bad <= 5) $display("[FAIL][VGA] %t non-black output during blanking: %h", $time, {vga_r, vga_g, vga_b});
                end
                if (de_d) begin                       // line just ended
                    if (x_cnt != 640) begin
                        err_vga = err_vga + 1;
                        if (err_vga <= 10) $display("[FAIL][VGA] %t line had %0d active pixels (expected 640)", $time, x_cnt);
                    end
                    x_cnt = 0;
                    y_cnt = y_cnt + 1;
                end
            end

            // ---- frame boundary (vsync falls after the active area)
            if (vs_d && !vga_vs) begin
                if (y_cnt != 480) begin
                    err_vga = err_vga + 1;
                    if (err_vga <= 10) $display("[FAIL][VGA] %t frame had %0d active lines (expected 480)", $time, y_cnt);
                end
                y_cnt = 0;
                if (pix_chk_on) begin
                    frames_checked = frames_checked + 1;
                    $display("[INFO] %t VGA frame %0d/%0d compared pixel by pixel", $time, frames_checked, VGA_FRAMES_TO_CHECK);
                    if (frames_checked == 1 && DUMP_PPM != 0) dump_ppm;
                    if (frames_checked >= VGA_FRAMES_TO_CHECK) begin
                        pix_chk_on = 1'b0;
                        vga_done   = 1'b1;
                    end
                end else if (fb_full_done && !vga_done) begin
                    pix_chk_on = 1'b1;               // next full frame is compared
                end
            end
        end
    end

    //--------------------------------------------------------------------------
    // End of simulation
    //--------------------------------------------------------------------------
    task final_report;
        integer total;
        begin
            if (wr_count != N_REGS)               err_sccb = err_sccb + 1;
            if (t_ready == 0)                     err_init = err_init + 1;
            if (start_pulses != 1)                err_init = err_init + 1;
            if (done_pulses  != 1)                err_init = err_init + 1;
            if (cap_frames_done < 1)              err_cap  = err_cap  + 1;
            if (!fb_full_done)                    err_fb   = err_fb   + 1;
            if (frames_checked < VGA_FRAMES_TO_CHECK) err_vga = err_vga + 1;
            total = err_init + err_sccb + err_cap + err_fb + err_vga;

            $display("");
            $display("==================== TEST SUMMARY ====================");
            $display(" INIT : sccb_start pulses=%0d (exp 1), sccb_done pulses=%0d (exp 1), cam_ready=%0d  -> %0d error(s)",
                     start_pulses, done_pulses, (t_ready != 0), err_init);
            $display(" SCCB : %0d/%0d register writes verified                        -> %0d error(s)",
                     wr_count, N_REGS, err_sccb);
            $display(" CAP  : %0d full frame(s) captured, %0d pixel writes in last frame -> %0d error(s)",
                     cap_frames_done, cap_wr_cnt, err_cap);
            $display(" FB   : RAM scan after first frame done=%0d                      -> %0d error(s)",
                     fb_full_done, err_fb);
            $display(" VGA  : %0d frame(s), %0d pixels compared                        -> %0d error(s)",
                     frames_checked, vga_pix_checked, err_vga);
            $display("------------------------------------------------------");
            if (total == 0) $display(" RESULT: PASS");
            else            $display(" RESULT: FAIL (%0d error(s))", total);
            $display("======================================================");
            $finish;
        end
    endtask

    initial begin
        wait (vga_done);
        #200;
        final_report;
    end

    initial begin
        #(TIMEOUT_MS * 1000000);
        $display("[FAIL] %t TIMEOUT - test did not complete within %0d ms", $time, TIMEOUT_MS);
        final_report;
    end

    //--------------------------------------------------------------------------
    // Waveforms (top-level only to keep the VCD small; widen if you need more)
    //--------------------------------------------------------------------------
    initial begin
        $dumpfile("tb_top.vcd");
        $dumpvars(1, tb_top);
        $dumpvars(1, dut);
    end

endmodule