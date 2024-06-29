create_clock -name FPGA_CLK_50 -period 20 [get_ports {FPGA_CLK_50}]
create_clock -name hsClk -period 20 [get_nets {hsClk}]
create_clock -name Clock_1us -period 1000 [get_ports {Clock_1us}]
create_clock -name Clock_1ms -period 1000000 [get_ports {Clock_1ms}]
create_clock -name Clock_1s -period 1000000000 [get_ports {Clock_1s}]
create_clock -name Clk_10MHz -period 100 [get_nets {clock_divider_hsClk|clock_out}]
create_clock -name Clk_1MHz -period 1000 [get_nets {clock_divider_us|clock_out clock_divider_Clk|clock_out}]
create_clock -name Clk_100KHz -period 10000 [get_nets {clock_divider_10us|clock_out}]
create_clock -name Clk_1KHz -period 1000000 [get_nets {clock_divider_ms|clock_out}]
create_clock -name Clk_250Hz -period 4000000 [get_nets {*clock_divider_4ms|clock_out}]
create_clock -name Clk_1Hz -period 1000000000 [get_nets {clock_divider_s|clock_out}]


