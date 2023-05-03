#!/bin/bash
set -Eeuo pipefail

trap cleanup SIGINT SIGTERM ERR EXIT

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd -P)

png=0
synt=0
sim=0
cov=0

cleanup() {
    trap - SIGINT SIGTERM ERR EXIT
    exit

}

msg() {
  echo >&2 -e "${1-}"
}

die() {
  local msg=$1
  local code=${2-1} # default exit status 1
  msg "$msg"
  exit "$code"
}

parse_params() {
  # default values of variables set from params
  flag=0
  param=''

  while :; do
    case "${1-}" in
    -h | --help) usage ;;
    -v | --verbose) set -x ;;
    -p | --png) png=1 ;;
	-s | --synt) synt=1 ;;
	-с | --coverage) cov=1 ;;
	-t | --sim) sim=1 ;;
    -?*) die "Unknown option: $1" ;;
    *) break ;;
    esac
    shift
  done

  args=("$@")

  return 0
}

emul() {
	echo "${1} Test"
	DEF=""
	if [ $# -ge 2 ]; then
		DEF="-D${2}"
	fi
	echo $DEF
	iverilog ${DEF} -g2012 -o ${1}UT -s ${1}_tb DekatronPC/tests/${1}.sv/${1}_tb.sv $DPCfiles
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

parse_params "$@"

if [ ${sim} -ne 0 ]; then
	DPCfiles=$(cat DPC.files)

	EmulFiles=$(cat Emul.files)

	emul Dekatron

	emul Counter

	emul IpLine LOOP_TEST

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

	if [ ! -d vcd ]; then
		mkdir vcd
	else
		rm -f sch/*.vcd
	fi

	mv -v *.vcd vcd/
	mv -v *UT  vcd/
fi

if [ ${cov} -ne 0 ]; then
	verilator_coverage -write-info logs/DPC.info logs/coverage_DPC.dat
	genhtml logs/DPC.info --output-directory coverage
fi

if [ ${synt} -ne 0 ]; then
	synt DekatronPC
	python3 dpc_stat.py -j vtube.json -t DekatronPC -l vtube_cells.lib
fi

if [ ${png} -ne 0 ]; then
	for file in $(ls *.dot); do
			gvpr -f $script_dir/split $file
		done
		rm -f *.png

		for file in $(ls *.dot); do
			if [ $file == 'DekatronPC.dot' ]; then
				continue
			fi
			#echo $file; dot -Tpng $file -O
			echo $file; dot -Tsvg $file -O
		done

	if [ ! -d sch ]; then
		mkdir sch
	else
		rm -f sch/*.svg
		rm -f sch/*.png
		rm -f sch/*.dot
	fi

	mv *.svg sch/
	mv *.dot sch/
fi