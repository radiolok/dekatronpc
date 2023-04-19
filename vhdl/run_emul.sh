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

verilator -Wall --coverage --trace --top Emulator --cc ${EmulFiles} ${DPCfiles} \
-GDIVIDE_TO_1US=1 -GDIVIDE_TO_1MS=10 -GDIVIDE_TO_4MS=30 -GDIVIDE_TO_1S=1000  \
--timescale 100ns/100ps \
--exe DekatronPC/tests/Emulator.sv/Emulator_tb.cpp

make -j`nproc` -C obj_dir -f VEmulator.mk VEmulator
./obj_dir/VEmulator
