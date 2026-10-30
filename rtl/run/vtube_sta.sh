#!/bin/bash
# Static timing analysis of the DekatronPC tube netlist (doc/vtube_sta.md).
#
#   vtube_sta.sh [-n] [-- vtube_sta.py options]
#     -n    reuse the netlist in sta/ (skip synthesis, about 20 s)
#     options after -- go to vtube_sta.py, e.g. -- -p 33 --derate 1.2
#
# 1. synthesis by synt_dpc.tcl as in synth_sim.sh -t: delay model of the
#    dekatron, phase start delay 22, the same black boxes (tube, OneShot,
#    Impulse, Ram, IpMemory, RstTimeRelay);
# 2. Yosys flattens the netlist through the board boundaries into JSON;
# 3. vtube_liberty.py builds sch/logic/vtube_cells_timing.lib from
#    vtube_cells.lib and vtube_timing.json;
# 4. vtube_sta.py writes the report to sta/DekatronPC_sta.md.
set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd -P)
root_dir=$(cd "${script_dir}/.." && pwd -P)
cell_dir=$(cd "${root_dir}/../sch/logic" && pwd -P)
work_dir=${script_dir}/sta

do_synth=1
while getopts "nh" opt; do
	case ${opt} in
	n) do_synth=0 ;;
	*) sed -n '2,15p' "$0"; exit 1 ;;
	esac
done
shift $((OPTIND - 1))
[ "${1:-}" = "--" ] && shift

mkdir -p "${work_dir}"
if [ ${do_synth} -ne 0 ]; then
	sed "s|^\.\./|${root_dir}/|" "${root_dir}/DekatronPC/DPC.files" > "${work_dir}/DPC.files"
	echo "${root_dir}/DekatronPC/Dekatron/DekatronTubeDelay.sv" >> "${work_dir}/DPC.files"
	echo "  synth DekatronPC"
	(cd "${work_dir}" && echo "tcl ${script_dir}/synt_dpc.tcl ${work_dir}/DPC.files DekatronPC \
		-bb DekatronTubeDelay -bb OneShot -bb Impulse -bb Ram -bb IpMemory -bb RstTimeRelay \
		-D DEKATRON_DELAY_MODEL -D DEKATRON_PHASE_DELAY_HS=22 -p EN_EMULATOR 0" \
		| yosys > synth.log 2>&1) || { tail -n 20 "${work_dir}/synth.log"; exit 1; }
	# Port directions of the black boxes come from their RTL headers
	awk '/^module RstTimeRelay/,/^endmodule/' "${root_dir}/DekatronPC/DekatronPC.sv" > "${work_dir}/RstTimeRelay.sv"
	echo "  flatten"
	(cd "${work_dir}" && yosys -q -p "
		read_liberty -lib ${cell_dir}/vtube_cells.lib
		read_verilog -sv -lib -DSYNTH -DDEKATRON_DELAY_MODEL ${root_dir}/parameters.sv \
			${root_dir}/DekatronPC/Dekatron/DekatronTubeDelay.sv ${root_dir}/Logic/Impulse.sv \
			${root_dir}/Logic/OneShot.sv ${root_dir}/DekatronPC/RAM.sv ${root_dir}/DekatronPC/IpMemory.sv \
			RstTimeRelay.sv
		read_verilog DekatronPC_synth.v
		hierarchy -top DekatronPC
		setattr -mod -unset keep_hierarchy *
		flatten
		opt_clean -purge
		write_json DekatronPC_flat.json" > flatten.log 2>&1) || { tail -n 20 "${work_dir}/flatten.log"; exit 1; }
fi
python3 "${script_dir}/vtube_liberty.py"
python3 "${script_dir}/vtube_sta.py" -n "${work_dir}/DekatronPC_flat.json" -o "${work_dir}/DekatronPC_sta.md" "$@" \
	| grep -E '^## |minimum Clk period|^\| [0-9.]+ kHz'
echo "  report: ${work_dir}/DekatronPC_sta.md"
