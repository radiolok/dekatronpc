create_clock -name Clk_50MHz -period 20 [get_ports {FPGA_CLK_50}]
create_clock -name Clk_10MHz -period 100 [get_nets {clock_divider_10MHz|clock_out Clock_10MHz}]
create_clock -name Clk_1MHz -period 1000 [get_nets {clock_divider_1MHz|clock_out Clock_1MHz}]
create_clock -name Clk_100KHz -period 10000 [get_nets {clock_divider_100KHz|clock_out Clock_100KHz}]
create_clock -name Clk_1KHz -period 1000000 [get_nets {clock_divider_1KHz|clock_out Clock_1KHz}]
create_clock -name Clk_250Hz -period 40000 [get_nets {*clock_divider_4ms|clock_out}]
create_clock -name Clk_1Hz -period 100000 [get_nets {clock_divider_1Hz|clock_out Clock_1Hz}]


