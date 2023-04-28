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
# read design
hierarchy -check
yosys synth -top [lindex $argv 1]
#
# # high-level synthesis
yosys proc 
yosys opt 
yosys memory
yosys opt
yosys fsm
#yosys flatten
yosys opt
#
# # low-level synthesis
yosys techmap
yosys opt
#

set cell_lib "vtube_cells.lib"
# # map to target architecture
yosys read_liberty -lib $cell_lib 
yosys dfflibmap -liberty $cell_lib 
yosys abc -liberty $cell_lib 
#
# # split larger signals
yosys splitnets -ports
yosys opt
#
# # cleanup
yosys clean
#
# # write synthesized design
yosys write_verilog [lindex $argv 1]_synth.v
#
# # show
yosys show -format dot -lib [lindex $argv 1]_synth.v -prefix [lindex $argv 1]
yosys tee -o vtube.json stat -liberty $cell_lib -json
#yosys ltp
