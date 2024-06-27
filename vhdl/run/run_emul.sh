#!/bin/bash
set -Eeuo pipefail

trap cleanup SIGINT SIGTERM ERR EXIT

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd -P)
root_dir=${script_dir}/..

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

DPCfiles=$(cat ${root_dir}/DekatronPC/DPC.files)

EmulFiles=$(cat ${root_dir}/Emulator/Emul.files)

bf_file=${root_dir}/programs/helloworld/helloworld.bfk
#bf_file=programs/rot13/rot13.bfk

verilator -Wall --trace --top Emulator --clk FPGA_CLK_50 --cc ${EmulFiles} ${DPCfiles} \
-GDIVIDE_TO_1US=1 --timescale 1us/10ns  +define+EMULATOR -DVERILATOR=1 \
--exe ${root_dir}/DekatronPC/tests/Emulator.sv/Emulator_tb.cpp -LDFLAGS -lncurses

make -j`nproc` -C obj_dir -f VEmulator.mk VEmulator
python ${root_dir}/programs/generate_rom.py -f ${bf_file} --hex -o firmware.hex
./obj_dir/VEmulator
