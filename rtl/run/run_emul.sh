#!/bin/bash
set -Eeuo pipefail

trap cleanup SIGINT SIGTERM ERR EXIT

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd -P)
root_dir=${script_dir}/..

consul=0

cleanup() {
    trap - SIGINT SIGTERM ERR EXIT
    exit

}

emul() {
	echo "${1} Test"
	iverilog -g2012 -o ${1}UT -s ${1}_tb ${root_dir}/tests/${1}.sv/${1}_tb.sv $DPCfiles
	./${1}UT
}

usage() {
	 msg "-h help"
	 msg "-v verbose"
	 msg "--consul"
}

parse_params() {
  # default values of variables set from params
  flag=0
  param=''

  while :; do
    case "${1-}" in
    -h | --help) usage ;;
    -v | --verbose) set -x ;;
    --consul) consul=1 ;;
    -?*) die "Unknown option: $1" ;;
    *) break ;;
    esac
    shift
  done

  args=("$@")

  return 0
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
parse_params "$@"

DPCfiles=$(cat ${root_dir}/DekatronPC/DPC.files)

EmulFiles=$(cat ${root_dir}/Emulator/Emul.files)

bf_file="${root_dir}/programs/helloworld.bfk"
bf_file="${bf_file} ${root_dir}/programs/fibonachi.bfk"
bf_file="${bf_file} ${root_dir}/programs/pi.bfk"
bf_file="${bf_file} ${root_dir}/programs/rot13.bfk"
bf_file="${bf_file} ${root_dir}/programs/triangle.bfk"
bf_file="${bf_file} ${root_dir}/programs/fractal.bfk"
python ${root_dir}/run/generate_rom.py -f ${bf_file} -o ${root_dir}/firmware.hex --hex --pack
#python ${root_dir}/run/generate_rom.py -f ${bf_file} -o ${root_dir}/firmware.sv 

CONSUL=""
if [ ${consul} -ne 0 ]; then
	CONSUL="-CFLAGS -DCONSUL=1 +define+CONSUL"
fi

verilator -Wall --trace --top Emulator --clk FPGA_CLK_50 --cc ${EmulFiles} ${DPCfiles} \
-GDIVIDE_TO_01US=1 --timescale 1us/10ns ${CONSUL} +define+EMULATOR -DVERILATOR=1 \
--exe ${root_dir}/tests/Emulator.sv/Emulator_tb.cpp -LDFLAGS -lncurses

make -j`nproc` -C obj_dir -f VEmulator.mk VEmulator

./obj_dir/VEmulator
