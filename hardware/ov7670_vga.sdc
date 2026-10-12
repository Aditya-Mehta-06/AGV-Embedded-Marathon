create_clock -name CLK_50MHz -period 20.000  [get_ports CLK_50MHz]
create_clock -name cam_pclk  -period 166.667 [get_ports cam_pclk]
derive_pll_clocks
derive_clock_uncertainty

set_clock_groups -asynchronous \
    -group {CLK_50MHz} \
    -group [get_clocks {*|clk[1]}] \
    -group {cam_pclk}

set_input_delay -clock cam_pclk -max 15 [get_ports {cam_data[*] cam_href cam_vsync}]
set_input_delay -clock cam_pclk -min 0  [get_ports {cam_data[*] cam_href cam_vsync}]