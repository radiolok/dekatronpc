if { $argc != 2 } {
  puts "The add.tcl script requires two args to be inputed."
  puts "For example, tclsh add.tcl path_to_verilog_file  top_module_name".
  puts "Please try again."
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
yosys opt
#
# # low-level synthesis
yosys techmap
yosys opt
#

set yosys_path "$::env(HOME)/yosys"
set cell_lib "$yosys_path/examples/cmos/cmos_cells.lib"
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
# # write intermediate language
yosys write_ilang [lindex $argv 1]_ilang.txt
#
# # show
yosys show -format dot -lib [lindex $argv 1]_synth.v -prefix [lindex $argv 1]
yosys stat
yosys stat -liberty $cell_lib 
exec dot -Tsvg [lindex $argv 1].dot > [lindex $argv 1].svg
yosys ltp
