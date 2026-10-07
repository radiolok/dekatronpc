#!/bin/bash
# Gate-level simulation: the Icarus tests of run_tests.sh -t, run against the
# Yosys netlist of the DUT instead of its RTL.
#
#   synth_sim.sh [-n] [test ...]
#     -n    skip synthesis, reuse the netlists in synth_sim/<test>/
#     test  Dekatron Counter IpLine ApLine MachineCtrl DekatronPC
#           (default: all of them; DekatronPC runs helloworld and program.bfk
#           on one netlist)
#
# Each DUT is synthesized by synt_dpc.tcl, the same flow as run_tests.sh -s,
# with the parameters its testbench uses (-p). Behavioural models of parts
# that are not tube logic are empty or stubbed under SYNTH; they stay black
# boxes (-bb) and come back from RTL in simulation:
#   DekatronTubeV2   the tube itself
#   OneShot, Impulse hs_clk pulse timing (phase generator, write window)
#   RstTimeRelay     time relay in the reset lines (extracted from DekatronPC.sv)
#   Ram, IpMemory    memory (ferrite)
# Library cells are simulated with rtl/vtube/vtube_cells.v.
#
# Output goes to rtl/run/synth_sim/: one directory per test with the netlist,
# synthesis log, simulation log and VCD. The exit code is the number of
# failed runs; a summary is printed at the end.
set -uo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd -P)
root_dir=$(cd "${script_dir}/.." && pwd -P)
work_dir=${script_dir}/synth_sim
cell_lib=${root_dir}/vtube/vtube_cells.lib
cell_models=${root_dir}/vtube/vtube_cells.v
dpc_files=${root_dir}/DekatronPC/DPC.files

do_synth=1
all_tests=(Dekatron Counter IpLine ApLine MachineCtrl DekatronPC)

while getopts "nh" opt; do
	case ${opt} in
	n) do_synth=0 ;;
	*) sed -n '2,23p' "$0"; exit 1 ;;
	esac
done
shift $((OPTIND - 1))
tests=("$@")
[ ${#tests[@]} -eq 0 ] && tests=("${all_tests[@]}")

# Per-test setup: synthesized top, its parameters (must match the testbench
# instantiation), black boxes, RTL put back in simulation, simulation runs.
# A run is "name|bfk program|iverilog defines".
config() {
	top=""; params=(); bbs=(DekatronTubeV2 OneShot Impulse); rtl=(); runs=()
	case $1 in
	Dekatron)
		top=DekatronModule
		params=(READ=1 WRITE=1 TOP_LIMIT_MODE=1 TOP_PIN_OUT=9 INIT_DIGIT=0 EXT_PHASES=0)
		runs=("Dekatron||") ;;
	Counter)
		top=DekatronCounter
		params=(D_NUM=3 TOP_LIMIT_MODE=1 "TOP_VALUE=12'h255")
		runs=("Counter||") ;;
	IpLine)
		top=IpLine
		params=(HARD_RST_D_CNT=3 LOOP_READ=1)
		runs=("IpLine|${root_dir}/programs/looptest.bfk|") ;;
	ApLine)
		top=ApLine
		rtl=(${root_dir}/DekatronPC/RAM.sv)
		runs=("ApLine||") ;;
	MachineCtrl)
		top=MachineCtrl
		params=(EN_EMULATOR=1)
		runs=("MachineCtrl||") ;;
	DekatronPC)
		top=DekatronPC
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
	echo "  sim   ${name}"
	iverilog -g2012 -o "${dir}/${name}_netlist" -DIPMEMFILE -DSIMPLEBOOT ${defines} \
		-s "${tb}_tb" \
		"${root_dir}/parameters.sv" \
		"${root_dir}/tests/${tb}.sv/${tb}_tb.sv" "${tb_files[@]}" \
		"${dir}/${top}_synth.v" "${cell_models}" \
		"${root_dir}/DekatronPC/Dekatron/DekatronTubeV2.sv" \
		"${root_dir}/DekatronPC/Dekatron/DekatronTubeV2_assertions.sv" \
		"${root_dir}/Logic/OneShot.sv" "${root_dir}/Logic/Impulse.sv" \
		"${root_dir}/Logic/ClockDivider.sv" \
		"${rtl[@]}" > "${dir}/${name}_compile.log" 2>&1 \
		|| { cat "${dir}/${name}_compile.log"; return 2; }
	(cd "${dir}" && vvp -n "./${name}_netlist" > "${name}_sim.log" 2>&1) \
		|| { tail -n 20 "${dir}/${name}_sim.log"; return 1; }
	tail -n 3 "${dir}/${name}_sim.log"
}

mkdir -p "${work_dir}"
summary=()
failed=0
for test in "${tests[@]}"; do
	echo "== ${test}"
	config "${test}" || { failed=$((failed + 1)); summary+=("${test}: unknown"); continue; }
	dir=${work_dir}/${test}
	mkdir -p "${dir}"
	if [ ${do_synth} -ne 0 ] || [ ! -f "${dir}/${top}_synth.v" ]; then
		if ! synth "${dir}"; then
			failed=$((failed + 1)); summary+=("${test}: SYNTH FAILED (${dir}/synth.log)")
			continue
		fi
	fi
	for run in "${runs[@]}"; do
		IFS='|' read -r name bfk defines <<< "${run}"
		simulate "${dir}" "${name}" "${bfk}" "${defines}"
		case $? in
		0) summary+=("${name}: PASS") ;;
		2) failed=$((failed + 1)); summary+=("${name}: COMPILE FAILED (${dir}/${name}_compile.log)") ;;
		*) failed=$((failed + 1)); summary+=("${name}: FAIL (${dir}/${name}_sim.log)") ;;
		esac
	done
done

echo
echo "== Netlist simulation summary"
printf '  %s\n' "${summary[@]}"
exit ${failed}
