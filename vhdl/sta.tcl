set sdc_file $::env(SDC_FILE)
set design $::env(DESIGN)
set liberty $::env(LIBERTY)
set vcd_file $::env(VCD)
set scope $::env(SCOPE)
set spef_file $::env(SPEF_FILE)

read_liberty ${liberty}
read_verilog ${design}.v
link_design ${design}
read_sdc $sdc_file
read_spef ${spef_file}
read_power_activities -scope ${scope} -vcd ${vcd_file}
report_power