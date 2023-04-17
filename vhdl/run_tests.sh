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
	iverilog -g2012 -o ${1}UT -s ${1}_tb DekatronPC/tests/${1}.sv/${1}_tb.sv $DPC_files
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

DPC_files=$(cat DPC.files)

EmulFiles=

verilator --top-module DekatronPC --lint-only  -Wall ${DPC_files}

verilator -Wall --coverage --trace --top DekatronPC --cc ${DPC_files} \
--timescale 100ns/100ps \
--exe DekatronPC/tests/DekatronPC.sv/DekatronPC_tb.cpp \

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
