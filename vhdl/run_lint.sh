#!/bin/bash
set -Eeuo pipefail

trap cleanup SIGINT SIGTERM ERR EXIT

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd -P)


cleanup() {
    trap - SIGINT SIGTERM ERR EXIT
    exit

}

emul() {
	echo "${1} Test"
	if [ ! -d build ]; then
		mkdir build
	fi
	iverilog -g2012 -o build/${1}UT -s ${1}_tb tests/${1}.sv/${1}_tb.sv $SourceFiles
	./build/${1}UT
}

synt() {
	current_dir=$(pwd)

	if [ ! -d build ]; then
		mkdir build
	fi
	cd build
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
	DekatronPC.sv \
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

EmulFiles=

verilator --top-module DekatronPC --lint-only  -Wall ${SourceFiles}


#verilator_coverage -write dpc.dat -read ${SourceFiles}

verilator -Wall --coverage --trace --top DekatronPC --cc ${SourceFiles} \
--timescale 100ns/100ps \
--exe tests/DekatronPC.sv/DekatronPC_tb.cpp \

make -C obj_dir -f VDekatronPC.mk VDekatronPC
./obj_dir/VDekatronPC

emul Dekatron

emul Counter

#emul IpLine

emul ApLine

emul DekatronPC

#synt IpLine

#synt ApLine

synt DekatronPC

exit
for file in $(ls *.dot); do
		gvpr -f $script_dir/split $file
	done
	rm -f *.png

	for file in $(ls *.dot); do 
		echo $file; dot -Tpng $file -O
	done
