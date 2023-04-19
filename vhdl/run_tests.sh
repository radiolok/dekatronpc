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
	iverilog -g2012 -o ${1}UT -s ${1}_tb DekatronPC/tests/${1}.sv/${1}_tb.sv $DPCfiles
	./${1}UT
}

synt() {
	current_dir=$(pwd)

	files_path=${current_dir}/DPC.files

	rm -f *.dot
	touch ${1}.txt
	chmod 777 ${1}.txt
	echo 'tcl '${script_dir}'/synt_dpc.tcl '${files_path}' '${1}'' > ${1}.txt
	cat ${1}.txt
	yosys < ${1}.txt

	cd ${current_dir}

}

DPCfiles=$(cat DPC.files)

EmulFiles=$(cat Emul.files)

emul Dekatron

emul Counter

#emul IpLine

emul ApLine

echo ${DPCfiles}

echo EmulFiles ${EmulFiles}

verilator --top-module Emulator --lint-only -Wall ${EmulFiles} ${DPCfiles}

verilator --top-module DekatronPC --lint-only  -Wall ${DPCfiles}

verilator -Wall --coverage --trace --top DekatronPC --cc ${DPCfiles} \
--timescale 100ns/100ps \
--exe DekatronPC/tests/DekatronPC.sv/DekatronPC_tb.cpp

make -j`nproc` -C obj_dir -f VDekatronPC.mk VDekatronPC
./obj_dir/VDekatronPC

verilator_coverage -write-info logs/DPC.info logs/coverage_DPC.dat

genhtml logs/DPC.info --output-directory coverage

synt DekatronPC

exit
for file in $(ls *.dot); do
		gvpr -f $script_dir/split $file
	done
	rm -f *.png

	for file in $(ls *.dot); do 
		echo $file; dot -Tpng $file -O
	done
