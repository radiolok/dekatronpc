if { $argc != 2 } {
  puts "call script <file_with_v_list> <top_level_module>".
} else {
}
yosys -import

set fp [open [lindex $argv 0] r]
set file_data [read $fp]
close $fp

set data [split $file_data "\n"]
set tb_suffix "_tb"
foreach line $data {
  if {[string first $tb_suffix $line] == -1} {
    if {$line ne ""} { 
      puts $line
      yosys read_verilog -sv $line 
    }
  }
}
hierarchy -check
yosys synth -top [lindex $argv 1]

yosys proc
yosys flatten
set cell_lib "vtube_cells.lib"
yosys read_liberty -lib $cell_lib 
yosys dfflibmap -liberty $cell_lib 
yosys abc -liberty $cell_lib
yosys opt
yosys clean
yosys write_verilog [lindex $argv 1]_synth.v
#
# # show
yosys show -format dot -lib [lindex $argv 1]_synth.v -prefix [lindex $argv 1]
yosys tee -o  [lindex $argv 1].json stat -liberty $cell_lib -json
#yosys ltp
