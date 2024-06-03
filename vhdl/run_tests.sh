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

usage() {
	 msg "-h help"
	 msg "-v verbose"
	 msg "-p png"
	 msg "-s synt"
	 msg "-c coverage"
	 msg "-t sim"
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
	-c | --coverage) cov=1 ;;
	-t | --sim) sim=1 ;;
    -?*) die "Unknown option: $1" ;;
    *) break ;;
    esac
    shift
  done

  args=("$@")

  return 0
}

veremul() {
	#Warning: trace gives ~10% slowdown
	TRACE="--trace -DSIM_TRACE"
	#TRACE=""

	#Warning: coverage gives 10x slowdown!
	#COVERAGE="--coverage -DSIM_COV"
	COVERAGE=""

	files=$(cat ${1})
	bf_file=${2}

	python3 ${script_dir}/programs/generate_rom.py -f ${bf_file} -o ${script_dir}/firmware.hex --hex
	verilator -Wall ${COVERAGE} ${TRACE} --top DekatronPC --cc ${files} \
	../libdpcrun.a  -DEMULATOR=1\
	--timescale 1us/1ns \
	--exe DekatronPC/tests/DekatronPC.sv/DekatronPC_tb.cpp  -LDFLAGS -lncurses

	make -j`nproc` -C obj_dir -f VDekatronPC.mk VDekatronPC
	./obj_dir/VDekatronPC -f ${bf_file}
}

parse_params "$@"

python3 ${script_dir}/Functions/TableGenerate.py -d ${script_dir}/Functions
python3 ${script_dir}/programs/generate_rom.py -f programs/looptest/looptest.bfk -o ${script_dir}/firmware.hex --hex

if [ ${sim} -ne 0 ]; then	

	DPCfiles=$(cat DPC.files)

	EmulFiles=$(cat Emul.files)

	verilator --top-module Emulator --lint-only -Wall ${EmulFiles} ${DPCfiles}

	verilator --top-module DekatronPC --lint-only  -Wall ${DPCfiles}
	
	./emul Dekatron

	./emul Counter

	./emul IpLine programs/looptest/looptest.bfk

	./emul ApLine

	bf_file=programs/helloworld/helloworld.bfk

	g++ -o dpcrun -DEXEC DekatronPC/tests/DekatronPC.sv/dpcrun.cpp
	./dpcrun -f ${bf_file}
	g++ -c DekatronPC/tests/DekatronPC.sv/dpcrun.cpp
	ar rvs libdpcrun.a dpcrun.o

	veremul DPC.files ${bf_file}
	
	veremul DPC.files programs/pi/pi.bfk

	#veremul DPC.files programs/fractal.bfk

	#veremul DPC.files programs/rot13/rot13.bfk

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

	rm -f *.dot
	./synth IpLine
	./synth ApLine
	./synth InsnDecoder
	python3 dpc_stat.py -j IpLine.json,ApLine.json,InsnDecoder.json -l vtube_cells.lib
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