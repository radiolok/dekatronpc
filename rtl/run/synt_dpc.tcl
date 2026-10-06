if { $argc != 2 } {
  puts "call script <file_with_v_list> <top_level_module>".
} else {
}
yosys -import

set script_dir [file dirname [file normalize [info script]]]
set top        [lindex $argv 1]

yosys read -define SYNTH=1

set cell_lib "$script_dir/../vtube/vtube_cells.lib"

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
yosys read_liberty -lib $cell_lib
hierarchy -check
# FSM extraction and recoding happen inside synth; a separate fsm pass after
# it is a no-op. Encoding was measured: binary/onehot give the same count.
yosys synth -top $top
yosys proc

yosys dfflibmap -liberty $cell_lib

# Simulation models of the library cells, for the equivalence check below
yosys design -save mapped
yosys design -reset
yosys read_liberty -ignore_miss_func $cell_lib
yosys write_verilog -noattr ${top}_cells_sim.v
yosys design -load mapped

# Area-oriented mapping. In tubes only area counts; the default ABC script
# for -liberty is delay-oriented. &deepsyn stops after 50 steps without
# improvement (-J keeps the result reproducible), -T caps the runtime.
# equiv_opt runs the mapping on a copy, proves it against the pre-ABC
# netlist of the top module (-async2sync: the triggers have asynchronous
# set/reset) and restores the design, so the mapping is then run for real.
yosys equiv_opt -assert -async2sync -map ${top}_cells_sim.v \
    abc -liberty $cell_lib -script $script_dir/abc_area.abc
yosys abc -liberty $cell_lib -script $script_dir/abc_area.abc
yosys opt
yosys clean

# A tube trigger has the inverted output for free: inverters on Q go to QN
yosys write_json ${top}_premap.json
exec python3 $script_dir/qn_absorb.py -l $cell_lib -i ${top}_premap.json -o ${top}_qn.json >@ stdout
yosys design -reset
yosys read_liberty -lib $cell_lib
yosys read_json ${top}_qn.json
yosys hierarchy -top $top
file delete ${top}_premap.json ${top}_qn.json ${top}_cells_sim.v

yosys write_verilog ${top}_synth.v
#
# # show
yosys show -format dot -lib ${top}_synth.v -prefix $top
yosys tee -o  $top.json stat -liberty $cell_lib -json
#yosys ltp
