# usage: synt_dpc.tcl <file_with_v_list> <top_level_module> [options]
#   -bb <module>        keep <module> as a black box: its instances stay in the
#                       netlist with their parameters (netlist simulation puts
#                       the RTL model back, see synth_sim.sh)
#   -p <name> <value>   override a parameter of the top module
#   -div                insert the HV -> LV dividers (DIV_HL cells) after mapping
#                       and check the signal levels (div_insert.py, doc/hv_lv_dividers.md)
#   -D <name>[=<value>] define a preprocessor macro, e.g. DEKATRON_DELAY_MODEL
#                       (the netlist instantiates DekatronTubeDelay); without
#                       a value it is 1
#   -flat               also write <top>_flat.json: the written netlist read
#                       back and flattened through the board boundaries, with
#                       the cell names of <top>_synth.v (vtube_sta.py loads,
#                       vtube_sdf.py -j)
# Without options the flow is the tube-count flow used by run_tests.sh -s.
if { $argc < 2 } {
  puts "call script <file_with_v_list> <top_level_module> \[-bb <module>\] \[-p <name> <value>\]"
  exit 1
}
yosys -import

set script_dir [file dirname [file normalize [info script]]]
set top        [lindex $argv 1]

set blackboxes {}
set top_params {}
set defines {}
set div 0
set flat 0
for {set i 2} {$i < $argc} {incr i} {
  switch -- [lindex $argv $i] {
    -bb { lappend blackboxes [lindex $argv [incr i]] }
    -p  { lappend top_params [lindex $argv [incr i]] [lindex $argv [incr i]] }
    -D  { lappend defines [lindex $argv [incr i]] }
    -div { set div 1 }
    -flat { set flat 1 }
    default { puts "unknown option [lindex $argv $i]"; exit 1 }
  }
}

yosys read -define SYNTH=1
foreach def $defines {
  if {[string first "=" $def] >= 0} {
    yosys read -define $def
  } else {
    yosys read -define $def=1
  }
}

set cell_lib "$script_dir/../../sch/logic/vtube_cells.lib"

set fp [open [lindex $argv 0] r]
set file_data [read $fp]
close $fp
# Relative paths in the list are relative to the list itself
set list_dir [file dirname [file normalize [lindex $argv 0]]]

set data [split $file_data "\n"]
set tb_suffix "_tb"
foreach line $data {
  if {[string first $tb_suffix $line] == -1} {
    if {$line ne ""} {
      puts $line
      yosys read_verilog -sv [file join $list_dir $line]
    }
  }
}
yosys read_liberty -lib $cell_lib
foreach bb $blackboxes {
  yosys setattr -mod -set blackbox 1 $bb
}
foreach {name value} $top_params {
  yosys chparam -set $name $value $top
}
hierarchy -check
# FSM extraction and recoding happen inside synth; a separate fsm pass after
# it is a no-op. The encoding is set in RTL with (* fsm_encoding = "binary" *)
# on the state register: one-hot costs about 219 tubes more on 7-tube
# triggers (doc/tube_count_reduction.md §17.2).
yosys synth -top $top
yosys proc

yosys dfflibmap -liberty $cell_lib
# DFF_J2N16 takes the falling edge: dfflibmap puts a $_NOT_ before every such
# trigger. Merge them into one inverter per clock net, or ABC keeps one output
# per trigger and drives each through a BUF_N16. In the machine the clock is
# inverted once at the generator (sch/logic/DFF_J2N16/README.md).
yosys opt_merge

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
set netlist_json ${top}_qn.json
# HV -> LV dividers as DIV_HL cells, one per HV net and grid class; P&R places them
if {$div} {
  exec python3 $script_dir/div_insert.py -l $cell_lib -i ${top}_qn.json -o ${top}_div.json >@ stdout
  set netlist_json ${top}_div.json
}
yosys design -reset
yosys read_liberty -lib $cell_lib
yosys read_json $netlist_json
yosys hierarchy -top $top
file delete ${top}_premap.json ${top}_qn.json ${top}_cells_sim.v
if {$div} { file delete ${top}_div.json }

yosys write_verilog ${top}_synth.v

# Flat netlist with the names of the file above (write_verilog renames the
# $-names, so it is read back): the sources only as headers, for the port
# directions of the black boxes
if {$flat} {
  yosys design -save final
  yosys design -reset
  yosys read -define SYNTH=1
  foreach def $defines {
    if {[string first "=" $def] >= 0} { yosys read -define $def } else { yosys read -define $def=1 }
  }
  yosys read_liberty -lib $cell_lib
  foreach line $data {
    if {[string first $tb_suffix $line] == -1 && $line ne ""} {
      yosys read_verilog -sv -lib [file join $list_dir $line]
    }
  }
  yosys read_verilog -overwrite ${top}_synth.v
  yosys hierarchy -top $top
  yosys setattr -mod -unset keep_hierarchy *
  yosys flatten
  yosys opt_clean -purge
  yosys write_json ${top}_flat.json
  yosys design -load final
}
#
# # show
yosys show -format dot -lib ${top}_synth.v -prefix $top
yosys tee -o  $top.json stat -liberty $cell_lib -json
#yosys ltp
