#!/bin/bash

set -x
pdk_dir=~/OpenLane/skywater-pdk

result=$(ls -td runs/* | head -1)

synthesis=${result}/results/synthesis/

netlist=$(ls ${synthesis}/ | grep .v)
netlist="${netlist%.*}"

netlist_file=$(find ${result}/results/final/ -name "${netlist}.v")

cp ${netlist_file} ./
netlist=$(basename ${netlist})

netlist="${netlist%.*}"

sources=$(ls src/*.sv)

iverilog -o dut -s ${netlist}_tb  -Isrc/ ${sources} RAM.sv ${netlist}_tb.sv -g2012
./dut

cat ${netlist}.v | grep sky130 | gawk '{print $1}'|sort|uniq > cellsFileInit

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd -P)

rm -rf cellsDirFile
rm -rf cellsFile
touch cellsFile
touch cellsDirFile
for line in $(cat cellsFileInit); do
	cell=$(find ${pdk_dir} -name "$line.v")
	cell_dir=$(dirname $cell)
	echo $cell >> cellsFile
	echo "-I$cell_dir" >> cellsDirFile
done

cells=$(cat cellsFile)
cellsDir=$(cat cellsDirFile)

iverilog -o dut -DFUNCTIONAL=1 -DUNIT_DELAY=0 -s ${netlist}_tb ${cellsDir} ${cells} src/parameters.sv src/ClockDivider.sv RAM.sv ${netlist}.v ${netlist}_tb.sv -g2012
./dut

sdc=$(find ${result}/results/final/sdc -name "${netlist}.sdc")
spef=$(find ${result}/results/final/spef -name "${netlist}.spef")

export DESIGN=${netlist}
export SDC_FILE=${sdc}
export VCD=${netlist}_tb.vcd
export LIBERTY=cts.lib
export SCOPE=${netlist}_tb/dut

export SPEF_FILE=${spef}

sta < sta.tcl