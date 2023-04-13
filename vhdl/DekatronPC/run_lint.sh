#!/bin/bash
set -Eeuo pipefail

trap cleanup SIGINT SIGTERM ERR EXIT

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd -P)


cleanup() {
    trap - SIGINT SIGTERM ERR EXIT
    exit

}

synt() {
	current_dir=$(pwd)
	files_path=${current_dir}/files

	rm -f *.dot
	touch ${1}.txt
	chmod 777 ${1}.txt
	echo 'tcl '${script_dir}'/run_synt_cmos.tcl '${files_path}' '${1}'' > ${1}.txt
	cat ${1}.txt
	yosys < ${1}.txt

	cd ${current_dir}

}

SourceFiles="IpLine/IpLine.sv \
	IpLine/IpCounter.sv \
	IpLine/InsnLoopDetector.sv \
	IpLine/ROM.sv \
	RAM.sv \
	Dekatron/BcdToBin.v \
    Dekatron/BinToBcd.v  \
	Dekatron/Dekatron.sv  \
	Dekatron/DekatronCarrySignal.sv  \
	Dekatron/DekatronCounter.sv  \
	Dekatron/DekatronModule.sv  \
	Dekatron/DekatronPulseAllow.sv  \
	Dekatron/DekatronPulseSender.sv \
	ApLine/ApLine.sv \
	../programs/looptest/looptest.sv \
	../programs/helloworld/helloworld.sv \
	../Logic/RsLatch.sv \
	../Logic/ClockDivider.sv"

verilator --top-module IpLine --lint-only  -Wall ${SourceFiles}

echo "Dekatron Test"
iverilog -g2012 -o DekatronUT -s Dekatron_tb tests/Dekatron.sv/Dekatron_tb.sv $SourceFiles
./DekatronUT

echo "Counter Test"
iverilog -g2012 -o CounterUT -s Counter_tb tests/Counter.sv/Counter_tb.sv $SourceFiles
./CounterUT

echo "IpLine Test"
iverilog -g2012 -o IpLineUT -s IpLine_tb tests/IpLine.sv/IpLine_tb.sv $SourceFiles
./IpLineUT

synt IpLine

synt ApLine


for file in $(ls *.dot); do
		gvpr -f $script_dir/split $file
	done
	rm -f *.png

	for file in $(ls *.dot); do 
		echo $file; dot -Tpng $file -O
	done