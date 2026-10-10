#!/bin/bash
set -Eeuo pipefail

trap cleanup SIGINT SIGTERM ERR EXIT

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd -P)
cd "${script_dir}"
root_dir=${script_dir}/..
# C++ golden model lives in the bfutils submodule
dpcrun_dir=${root_dir}/../bfutils/dpcrun
echo ${root_dir}

png=0
synt=0
sim=0
cov=0
uvm=0
gate=0
delay=0

cleanup() {
    local exit_code=$?
    trap - SIGINT SIGTERM ERR EXIT
    exit $exit_code

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
	 msg "-u uvm"
	 msg "-g gate-level: RTL tests on the synthesized netlists (synth_sim.sh)"
	 msg "-d delay model: the Icarus tests and pi.bfk with DekatronTubeDelay (no hsClk)"
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
	-u | --uvm) uvm=1 ;;
	-g | --gate) gate=1 ;;
	-d | --delay) delay=1 ;;
    -?*) die "Unknown option: $1" ;;
    *) break ;;
    esac
    shift
  done

  args=("$@")

  return 0
}

if [ "$#" -eq 0 ]; then
    echo "Error: No arguments provided."
    sim=1
fi

veremul() {
	#Warning: trace gives ~10% slowdown
	TRACE="--trace -DSIM_TRACE"
	#TRACE=""

	#Warning: coverage gives 10x slowdown!
	#COVERAGE="--coverage -DSIM_COV"
	COVERAGE=""

	files=$(cat ${1})
	bf_file=${2}
	# extra testbench flags, e.g. -n: no VCD (pi.bfk would write tens of GB)
	tb_flags=${3:-}

	python3 ${root_dir}/run/generate_rom.py -f ${bf_file} -o ${root_dir}/firmware.hex --hex
	# EN_EMULATOR drives IRET and LoopCount, which the golden-model compare needs
	verilator -Wall ${COVERAGE} ${TRACE} --top DekatronPC --cc ${files} \
	"-GEN_EMULATOR=1'b1" \
	../libdpcrun.a  -CFLAGS -I${dpcrun_dir} -DEMULATOR=1 -DIPMEMFILE\
	--timescale 1us/1ns rules.vlt \
	--exe ${root_dir}/tests/DekatronPC.sv/DekatronPC_tb.cpp

	make -j`nproc` -C obj_dir -f VDekatronPC.mk VDekatronPC
	# -s: compare with the golden model after every instruction (REQ-GM-002);
	# the per-step trace goes to stderr, the verdict is the exit code
	local steps=${bf_file##*/}.steps.log
	./obj_dir/VDekatronPC -f ${bf_file} -s ${tb_flags} 2> ${steps} || { tail -n 20 ${steps}; return 1; }
}

parse_params "$@"

python3 -c "open('${root_dir}/zeros.txt','w').write('\n'.join(['00']*30000))"
python3 ${root_dir}/Functions/TableGenerate.py -d ${root_dir}/Functions
python3 ${root_dir}/run/generate_rom.py -f ${root_dir}/programs/looptest.bfk -o ${root_dir}/firmware.hex --hex

if [ ${sim} -ne 0 ]; then

	DPCfiles=$(cat ${root_dir}/DekatronPC/DPC.files)

	EmulFiles=$(cat ${root_dir}/Emulator/Emul.files)

	verilator --top-module DekatronPC --lint-only  -Wall ${DPCfiles} rules.vlt

	verilator --top-module Emulator --lint-only -DEMULATOR=1 -Wall ${EmulFiles} ${DPCfiles} rules.vlt

	./emul Dekatron

	./emul Counter

	./emul IpLine ${root_dir}/programs/looptest.bfk

	./emul ApLine

	./emul MachineCtrl

	./emul DekatronPC ${root_dir}/programs/helloworld.bfk ${root_dir}/tests/DekatronPC.sv/DekatronPC_tb_cfg_hello.svh
	./emul DekatronPC ${root_dir}/programs/program.bfk ${root_dir}/tests/DekatronPC.sv/DekatronPC_tb_cfg_program.svh

	bf_file=${root_dir}/programs/helloworld.bfk
	g++ -o dpcrun -DEXEC ${dpcrun_dir}/dpcrun.cpp
	./dpcrun -f ${bf_file}
	g++ -c ${dpcrun_dir}/dpcrun.cpp
	ar rvs libdpcrun.a dpcrun.o

	veremul ${root_dir}/DekatronPC/DPC.files ${bf_file}

	veremul ${root_dir}/DekatronPC/DPC.files ${root_dir}/programs/program.bfk

	# 221 386 steps, ~22 s (doc/pi_step_check.md)
	veremul ${root_dir}/DekatronPC/DPC.files ${root_dir}/programs/pi.bfk -n

	#veremul ${root_dir}/DekatronPC/DPC.files ${root_dir}/programs/fractal.bfk

	#veremul ${root_dir}/DekatronPC/DPC.files ${root_dir}/programs/rot13.bfk

	if [ ! -d vcd ]; then
		mkdir vcd
	else
		rm -f sch/*.vcd
	fi

	mv -v *.vcd vcd/
	mv -v *UT  vcd/
fi

# Icarus tests with the delay-based dekatron model (DekatronTubeDelay: #N
# delays, no hsClk), plus pi.bfk on the whole DekatronPC. Binaries and VCDs
# go to delay/ so they don't mix with the clocked-model ones in vcd/.
if [ ${delay} -ne 0 ]; then
	export DEKATRON_MODEL=delay
	tests_dir=${root_dir}/tests/DekatronPC.sv
	./emul Dekatron
	./emul Counter
	./emul IpLine ${root_dir}/programs/looptest.bfk
	./emul ApLine
	./emul MachineCtrl
	./emul DekatronPC ${root_dir}/programs/helloworld.bfk ${tests_dir}/DekatronPC_tb_cfg_hello.svh
	./emul DekatronPC ${root_dir}/programs/program.bfk ${tests_dir}/DekatronPC_tb_cfg_program.svh
	# 3.17 M clk cycles; no VCD (it would take gigabytes)
	EMUL_DEFINES=-DNO_VCD ./emul DekatronPC ${root_dir}/programs/pi.bfk ${tests_dir}/DekatronPC_tb_cfg_pi.svh
	unset DEKATRON_MODEL
	mkdir -p delay
	mv -f *.vcd *UT delay/
fi

if [ ${cov} -ne 0 ]; then
	verilator_coverage -write-info logs/DPC.info logs/coverage_DPC.dat
	genhtml logs/DPC.info --output-directory coverage
fi

if [ ${synt} -ne 0 ]; then

	rm -f *.dot
	./synth IpLine
	./synth ApLine
	./synth MachineCtrl
	python3 dpc_stat.py -j IpLine.json,ApLine.json,MachineCtrl.json -l ../vtube/vtube_cells.lib
fi

if [ ${gate} -ne 0 ]; then
	./synth_sim.sh
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

if [ ${uvm} -ne 0 ]; then
	tb_dir=${root_dir}/../tb
	[ -f /var/venv/bin/activate ] && source /var/venv/bin/activate
	make -C ${tb_dir} regression
fi