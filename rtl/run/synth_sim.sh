#!/bin/bash
# Gate-level simulation: the Icarus tests of run_tests.sh -t, run against the
# Yosys netlist of the DUT instead of its RTL.
#
#   synth_sim.sh [-n] [-t | -p] [-c NS] [-o NS] [-w NS] [test ...]
#     -n    skip synthesis, reuse the netlists in synth_sim/<test>/
#     -d    accepted for compatibility: the netlist is always the tube
#           machine with the delay-based dekatron model DekatronTubeDelay
#           (DEKATRON_DELAY_MODEL, #N delays in ns) and has no hsClk at all
#           (TRS v0.25); hsClk exists only for the clocked model of the FPGA
#           emulator and the RTL simulations without delays
#     -t    tube delays: every cell gets the delays of the
#           liberty tables (vtube_cells_timing.lib, from vtube_timing.json)
#           at the load of its output net, through SDF (iverilog -gspecify,
#           vtube_sdf.py -l -j, the same delays as vtube_sta.py), and every
#           trigger a setup/hold checker; a run
#           with violations fails. Default tests: Dekatron Counter
#           DekatronPC. Output in synth_sim_timing/ (doc/vtube_sdf_timing.md)
#     -p    power (doc/vtube_power.md): the netlist with the HV -> LV
#           dividers (synt_dpc.tcl -div), the phase timing of the tube
#           build (-o 2500 -w 1000, as -t), and the VCD of the DUT streamed
#           through a FIFO into vtube_power_vcd (nothing on disk, so pi.bfk
#           works too); the state times times the cell currents of
#           sch/logic/vtube_power.json give <run>_power.md: current, voltage
#           and power per rail (heater, plates, screens, bias, dekatron
#           anodes) and per block. Tests: DekatronPC (helloworld and
#           program.bfk, the default), Pi. Output in synth_sim_power/
#     -o NS phase start delay after the Clk edge, ns (DEKATRON_PHASE_DELAY_NS,
#           REQ-PULSE-009): at least the worst step command path. Default
#           0 (RTL), 2500 under -t: the longest step command with the SPICE
#           cell delays and the plate chokes settles within it (vtube_sta.sh
#           fits it, doc/vtube_sta.md §3; 3300 before TRS v0.59)
#     -w NS width of each guide phase, ns (DEKATRON_PHASE1_NS /
#           DEKATRON_PHASE2_NS). Default 1000 (RTL and -t, owner, TRS v0.59;
#           was 3000 / 600): a tube gate of DekatronPulseSender does not pass
#           a pulse shorter than its own delay (doc/vtube_sta.md §6)
#     -c NS Clk period in ns of the testbenches (default CLK_PERIOD_NS =
#           10000, the 100 kHz Clk of TRS v0.24)
#     test  Dekatron Counter IpLine ApLine MachineCtrl DekatronPC Pi
#           (default: all but Pi; DekatronPC runs helloworld and program.bfk
#           on one netlist, Pi runs pi.bfk on the same DekatronPC netlist,
#           about 3.2 M clk cycles)
#
# Each DUT is synthesized by synt_dpc.tcl, the same flow as run_tests.sh -s,
# with the parameters its testbench uses (-p). Behavioural models of parts
# that are not tube logic are empty or stubbed under SYNTH; they stay black
# boxes (-bb) and come back from RTL in simulation:
#   DekatronTubeDelay the tube itself
#   OneShot, Impulse RC pulse timing of the phase generator, in ns
#   RstTimeRelay     time relay in the reset lines (extracted from DekatronPC.sv)
#   Ram, IpMemory    memory (ferrite)
# Library cells are simulated with sch/logic/vtube_cells.v.
#
# Output goes to rtl/run/synth_sim/: one directory per test with the netlist,
# synthesis log, simulation log and VCD. The exit code is the number of
# failed runs; a summary is printed at the end.
set -uo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd -P)
root_dir=$(cd "${script_dir}/.." && pwd -P)
work_dir=${script_dir}/synth_sim
cell_dir=$(cd "${root_dir}/../sch/logic" && pwd -P)
cell_lib=${cell_dir}/vtube_cells.lib
cell_models=${cell_dir}/vtube_cells.v
cell_timing=${cell_dir}/vtube_timing.json
dpc_files=${root_dir}/DekatronPC/DPC.files

do_synth=1
timing=0
power=0
clk_ns=""
all_tests=(Dekatron Counter IpLine ApLine MachineCtrl DekatronPC)

phase_delay=""
phase_width=""
while getopts "ndtpc:o:w:h" opt; do
	case ${opt} in
	n) do_synth=0 ;;
	d) ;;
	t) timing=1 ;;
	p) power=1 ;;
	c) clk_ns=${OPTARG} ;;
	o) phase_delay=${OPTARG} ;;
	w) phase_width=${OPTARG} ;;
	*) sed -n '2,55p' "$0"; exit 1 ;;
	esac
done
shift $((OPTIND - 1))
tests=("$@")
[ ${timing} -ne 0 ] && [ ${power} -ne 0 ] && { echo "-t and -p exclude each other"; exit 1; }
[ $((timing + power)) -ne 0 ] && [ -z "${phase_delay}" ] && phase_delay=2500
[ $((timing + power)) -ne 0 ] && [ -z "${phase_width}" ] && phase_width=1000
if [ ${#tests[@]} -eq 0 ]; then
	tests=("${all_tests[@]}")
	[ ${timing} -ne 0 ] && tests=(Dekatron Counter DekatronPC)
	[ ${power} -ne 0 ] && tests=(DekatronPC)
fi

# Dekatron model: always the delay-based DekatronTubeDelay, no hsClk. It is
# not in DPC.files (Verilator and Quartus never see it); synt_dpc.tcl adds
# it to synthesis, and the simulation list gets it here.
tube=DekatronTubeDelay
tube_rtl=(${root_dir}/DekatronPC/Dekatron/DekatronTubeDelay.sv)
synth_defs=()
# NETLIST_SIM: the testbench runs on a netlist (one parameter set per
# synthesized module, e.g. Counter_tb drops its second, IP-like counter)
sim_defs="-DNETLIST_SIM -DDEKATRON_DELAY_MODEL"
[ -n "${clk_ns}" ] && sim_defs+=" -DCLK_NS=${clk_ns}"
if [ ${timing} -ne 0 ]; then
	work_dir=${script_dir}/synth_sim_timing
	sim_defs+=" -gspecify"
	# delays at the load of each net: flat netlist + table liberty
	synth_defs+=(-flat)
	python3 "${script_dir}/vtube_liberty.py" > /dev/null
fi
if [ ${power} -ne 0 ]; then
	work_dir=${script_dir}/synth_sim_power
	synth_defs+=(-div)
	mkdir -p "${work_dir}"
	gcc -O2 -o "${work_dir}/vtube_power_vcd" "${script_dir}/vtube_power_vcd.c" || exit 1
fi
mkdir -p "${work_dir}"
# Phase timing of the tube build, ns: macros read by DekatronPhaseGen (the
# OneShot black boxes keep them as DELAY_NS), the same in synthesis and
# in the simulation of the black boxes
[ -n "${phase_delay}" ] && synth_defs+=(-D DEKATRON_PHASE_DELAY_NS=${phase_delay}) \
	&& sim_defs+=" -DDEKATRON_PHASE_DELAY_NS=${phase_delay}"
[ -n "${phase_width}" ] && synth_defs+=(-D DEKATRON_PHASE1_NS=${phase_width} -D DEKATRON_PHASE2_NS=${phase_width}) \
	&& sim_defs+=" -DDEKATRON_PHASE1_NS=${phase_width} -DDEKATRON_PHASE2_NS=${phase_width}"

# Per-test setup: synthesized top, its parameters (must match the testbench
# instantiation), black boxes, RTL put back in simulation, simulation runs.
# A run is "name|bfk program|iverilog defines". netdir is the netlist
# directory (Pi shares the DekatronPC netlist).
config() {
	top=""; params=(); bbs=(${tube} OneShot Impulse); rtl=(); runs=(); netdir=$1; dut=
	case $1 in
	Dekatron)
		dut=Dekatron_tb.dek
		top=DekatronModule
		params=(READ=1 WRITE=1 TOP_LIMIT_MODE=1 TOP_PIN_OUT=9 INIT_DIGIT=0)
		# The pulse sender is the counter's since T5; the testbench has its own
		rtl=(${root_dir}/DekatronPC/Dekatron/DekatronPulseSender.sv
		     ${root_dir}/DekatronPC/Dekatron/DekatronPhaseGen.sv)
		runs=("Dekatron||") ;;
	Counter)
		dut=Counter_tb.counter
		top=DekatronCounter
		params=(D_NUM=3 TOP_LIMIT_MODE=1 "TOP_VALUE=12'h255")
		runs=("Counter||") ;;
	IpLine)
		dut=IpLine_tb.ipLine
		top=IpLine
		params=(HARD_RST_D_CNT=3 LOOP_READ=1)   # 9990, ISA16 (doc/isa16.md)
		runs=("IpLine|${root_dir}/programs/looptest.bfk|") ;;
	ApLine)
		dut=ApLine_tb.apLine
		top=ApLine
		rtl=(${root_dir}/DekatronPC/RAM.sv)
		runs=("ApLine||") ;;
	MachineCtrl)
		dut=MachineCtrl_tb.dut
		top=MachineCtrl
		params=(EN_EMULATOR=1)
		runs=("MachineCtrl||") ;;
	DekatronPC|Pi)
		dut=DekatronPC_tb.dekatronPC
		top=DekatronPC
		netdir=DekatronPC
		params=(EN_EMULATOR=0)
		bbs+=(Ram IpMemory RstTimeRelay)
		# RstTimeRelay shares DekatronPC.sv with the synthesized top
		awk '/^module RstTimeRelay/,/^endmodule/' ${root_dir}/DekatronPC/DekatronPC.sv \
			> ${work_dir}/RstTimeRelay.sv
		rtl=(${work_dir}/RstTimeRelay.sv
		     ${root_dir}/DekatronPC/RAM.sv ${root_dir}/DekatronPC/IpMemory.sv
		     ${root_dir}/programs/bootloader/bootloader.sv
		     $(sed "s|^\.\./|${root_dir}/|" ${root_dir}/tests/DekatronPC.sv/DekatronPC_tb.files))
		local cfg=${root_dir}/tests/DekatronPC.sv
		if [ "$1" = Pi ]; then
			# No VCD: pi.bfk would write gigabytes
			runs=("DekatronPC_pi|${root_dir}/programs/pi.bfk|-DNO_VCD -DADDINCLUDE=\"${cfg}/DekatronPC_tb_cfg_pi.svh\"")
			return 0
		fi
		runs=("DekatronPC_hello|${root_dir}/programs/helloworld.bfk|-DADDINCLUDE=\"${cfg}/DekatronPC_tb_cfg_hello.svh\""
		      "DekatronPC_program|${root_dir}/programs/program.bfk|-DADDINCLUDE=\"${cfg}/DekatronPC_tb_cfg_program.svh\"") ;;
	*)
		echo "unknown test $1"; return 1 ;;
	esac
}

synth() {
	local dir=$1
	local args=()
	for bb in "${bbs[@]}"; do args+=(-bb "${bb}"); done
	args+=("${synth_defs[@]}")
	for p in "${params[@]}"; do args+=(-p "${p%%=*}" "${p#*=}"); done
	echo "  synth ${top} ${args[*]}"
	# Same call as the synth script: the TCL flow with arguments, through
	# the yosys shell
	(cd "${dir}" && echo "tcl ${script_dir}/synt_dpc.tcl ${dpc_files} ${top} ${args[*]}" \
		| yosys > synth.log 2>&1) || { tail -n 20 "${dir}/synth.log"; return 1; }
	local prep=()
	for p in "${params[@]}"; do prep+=(-p "${p}"); done
	python3 "${script_dir}/synth_sim_prep.py" -l "${cell_lib}" -c "${cell_models}" \
		-n "${dir}/${top}_synth.v" -t "${top}" "${prep[@]}"
}

simulate() {
	local dir=$1 name=$2 bfk=$3 defines=$4
	local tb=$name
	[[ ${name} == DekatronPC_* ]] && tb=DekatronPC
	# Testbenches read ../firmware.hex relative to the run directory
	if [ -n "${bfk}" ]; then
		python3 "${script_dir}/generate_rom.py" -f "${bfk}" -o "${work_dir}/firmware.hex" --hex > /dev/null
	fi
	local tb_files=()
	if [ -f "${root_dir}/tests/${tb}.sv/${tb}_tb.files" ] && [ "${tb}" != DekatronPC ]; then
		tb_files=($(sed "s|^\.\./|${root_dir}/|" "${root_dir}/tests/${tb}.sv/${tb}_tb.files"))
	fi
	local sdf=()
	if [ ${timing} -ne 0 ]; then
		python3 "${script_dir}/vtube_sdf.py" -c "${cell_models}" -T "${cell_timing}" \
			-n "${dir}/${top}_synth.v" -t "${top}" -s "${dut}" -o "${dir}/sdf" \
			-l "${cell_dir}/vtube_cells_timing.lib" -j "${dir}/${top}_flat.json" || return 2
		sdf=(-s vtube_sdf "${dir}/sdf/vtube_sdf.sv" "${cell_dir}/vtube_timing_check.v")
	fi
	echo "  sim   ${name}${clk_ns:+ (Clk ${clk_ns} ns)}"
	local fifo=${dir}/${name}.vcd.fifo
	if [ ${power} -ne 0 ]; then
		[ "${tb}" = DekatronPC ] || { echo "-p: only DekatronPC and Pi"; return 2; }
		python3 "${script_dir}/vtube_power.py" plan -n "${dir}/${top}_synth.v" -t "${top}" -s "${dut}" \
			-l "${cell_lib}" -m "${cell_dir}/vtube_power.json" -o "${dir}/${name}_plan" \
			-w "${clk_ns:-10000}" || return 2
		defines+=" -DPOWER_VCD=\"${fifo}\""
	fi
	iverilog -g2012 -o "${dir}/${name}_netlist" -DIPMEMFILE -DSIMPLEBOOT ${sim_defs} ${defines} \
		-s "${tb}_tb" "${sdf[@]}" \
		"${root_dir}/parameters.sv" \
		"${root_dir}/tests/${tb}.sv/${tb}_tb.sv" "${tb_files[@]}" \
		"${dir}/${top}_synth.v" "${cell_models}" \
		"${tube_rtl[@]}" \
		"${root_dir}/Logic/OneShot.sv" "${root_dir}/Logic/Impulse.sv" \
		"${root_dir}/Logic/ClockDivider.sv" \
		"${rtl[@]}" > "${dir}/${name}_compile.log" 2>&1 \
		|| { cat "${dir}/${name}_compile.log"; return 2; }
	# With tube delays a failing netlist can ring and write a VCD of many
	# GB (Counter at 1 us: 7.6 GB): cap files at 2 GB under -t
	local fsize=unlimited
	[ ${timing} -ne 0 ] && fsize=2000000
	local reader=
	if [ ${power} -ne 0 ]; then
		rm -f "${fifo}"; mkfifo "${fifo}"
		"${work_dir}/vtube_power_vcd" "${dir}/${name}_plan.txt" "${fifo}" "${dir}/${name}_power.txt" &
		reader=$!
	fi
	if ! (cd "${dir}" && ulimit -f ${fsize} && vvp -n "./${name}_netlist" > "${name}_sim.log" 2>&1); then
		[ -n "${reader}" ] && { kill ${reader} 2>/dev/null; wait ${reader} 2>/dev/null; rm -f "${fifo}"; }
		tail -n 20 "${dir}/${name}_sim.log"; return 1
	fi
	tail -n 3 "${dir}/${name}_sim.log"
	if [ -n "${reader}" ]; then
		wait ${reader}; local rc=$?
		rm -f "${fifo}"
		[ ${rc} -eq 0 ] || return 1
		python3 "${script_dir}/vtube_power.py" report -p "${dir}/${name}_plan" -r "${dir}/${name}_power.txt" \
			-o "${dir}/${name}_power.md" --title "Потребление: ${name}" > /dev/null || return 1
		echo "  power ${dir}/${name}_power.md"
	fi
	if [ ${timing} -ne 0 ]; then
		# Annotation problems and setup/hold violations fail the run
		grep -q "SDF ERROR\|SDF WARNING" "${dir}/${name}_sim.log" && return 3
		grep -q "^VTUBE TIMING: 0 setup, 0 hold" "${dir}/${name}_sim.log" || return 3
	fi
	return 0
}

mkdir -p "${work_dir}"
summary=()
failed=0
declare -A synthesized=()
for test in "${tests[@]}"; do
	echo "== ${test}"
	config "${test}" || { failed=$((failed + 1)); summary+=("${test}: unknown"); continue; }
	dir=${work_dir}/${netdir}
	mkdir -p "${dir}"
	if [ -z "${synthesized[${netdir}]:-}" ] && \
	   { [ ${do_synth} -ne 0 ] || [ ! -f "${dir}/${top}_synth.v" ]; }; then
		if ! synth "${dir}"; then
			failed=$((failed + 1)); summary+=("${test}: SYNTH FAILED (${dir}/synth.log)")
			continue
		fi
	fi
	synthesized[${netdir}]=1
	for run in "${runs[@]}"; do
		IFS='|' read -r name bfk defines <<< "${run}"
		simulate "${dir}" "${name}" "${bfk}" "${defines}"
		case $? in
		0) summary+=("${name}: PASS") ;;
		2) failed=$((failed + 1)); summary+=("${name}: COMPILE FAILED (${dir}/${name}_compile.log)") ;;
		3) failed=$((failed + 1)); summary+=("${name}: TIMING FAILED (${dir}/${name}_sim.log)") ;;
		*) failed=$((failed + 1)); summary+=("${name}: FAIL (${dir}/${name}_sim.log)") ;;
		esac
	done
done

echo
echo "== Netlist simulation summary"
printf '  %s\n' "${summary[@]}"
exit ${failed}
