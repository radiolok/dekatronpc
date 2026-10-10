#!/bin/bash
# build_fpga.sh — command-line FPGA bitstream build for the Emulator (DE0-Nano-SoC, Cyclone V).
#
# Generates a Quartus project in rtl/quartus_build/ from rtl/quartus/Emulator.qsf (device, pins,
# partitions) and the same source lists the simulators use (Emulator/Emul.files, DekatronPC/DPC.files),
# so the stale file list in Emulator.qsf never leaks into the build. The GUI project in rtl/quartus/
# is not touched.
#
# The build directory must sit directly under rtl/: the file lists use ../X paths and FirmwareLoader /
# MS6205 call $readmemh("../...hex"), which Quartus resolves relative to the project directory.
#
# Works with a native Linux Quartus or, under WSL, with the Windows install (quartus_*.exe).
# See doc/fpga_build.md.
set -Eeuo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd -P)
root_dir=$(cd "${script_dir}/.." && pwd -P)
qsf_src=${root_dir}/quartus/Emulator.qsf
sdc_src=../quartus/Emulator.sdc
build_dir=${root_dir}/quartus_build
rev=Emulator

stage=compile
quartus_bin=${QUARTUS_BIN:-}
macros=()
make_rbf=0
program=0
cable=1
jtag_index=2   # DE0-Nano-SoC JTAG chain: 1 = HPS (SOCVHPS), 2 = FPGA (5CSEMA4)
gen_fw=1
dry_run=0
jobs=ALL

msg() { echo >&2 -e "${1-}"; }
die() { msg "build_fpga: $1"; exit "${2-1}"; }

usage() {
	cat <<EOF
Usage: $(basename "$0") [options] [stage]

Stages (default: compile):
  elab      analysis & elaboration only (syntax, hierarchy, parameters)
  syn       analysis & synthesis (quartus_map)
  compile   syn + fit + asm + sta -> quartus_build/output_files/${rev}.sof
  program   program an existing .sof over JTAG, no rebuild

Options:
  -q, --quartus DIR   Quartus bin directory (default: \$QUARTUS_BIN, PATH,
                      ~/intelFPGA_lite/*/quartus/bin, /mnt/c/intelFPGA_lite/*/quartus/bin64)
  -D NAME[=VAL]       extra Verilog macro (repeatable); EMULATOR=True is always set
  -j N                processors for Quartus (default: ALL)
  -p, --program       program the board after a successful compile
  -c, --cable N|NAME  JTAG cable for programming (default: 1; list with --list-cables)
  -i, --index N       device index in the JTAG chain (default: 2, the FPGA on DE0-Nano-SoC)
  --rbf               also write output_files/${rev}.rbf (compressed, for HPS/FPP loading)
  --no-fw             do not regenerate firmware hex files from rtl/programs/*.bfk
  --list-cables       list JTAG cables and exit
  -n, --dry-run       write the project, print the commands, do not run Quartus
  -h, --help          this help
EOF
	exit 0
}

parse_params() {
	while :; do
		case "${1-}" in
		-h | --help) usage ;;
		-q | --quartus) quartus_bin="${2-}"; shift ;;
		-D) macros+=("${2-}"); shift ;;
		-D?*) macros+=("${1#-D}") ;;
		-j) jobs="${2-}"; shift ;;
		-p | --program) program=1 ;;
		-c | --cable) cable="${2-}"; shift ;;
		-i | --index) jtag_index="${2-}"; shift ;;
		--rbf) make_rbf=1 ;;
		--no-fw) gen_fw=0 ;;
		--list-cables) stage=list-cables ;;
		-n | --dry-run) dry_run=1 ;;
		-?*) die "unknown option: $1 (see --help)" ;;
		"") break ;;
		*) stage="$1" ;;
		esac
		shift
	done
	case "${stage}" in
	elab | syn | compile | program | list-cables) ;;
	*) die "unknown stage: ${stage} (see --help)" ;;
	esac
}

# Finds the Quartus bin directory and sets exe (".exe" for the Windows install under WSL).
find_quartus() {
	local cand
	if [ -n "${quartus_bin}" ]; then
		cand=("${quartus_bin}")
	elif command -v quartus_sh >/dev/null; then
		cand=("$(dirname "$(command -v quartus_sh)")")
	elif command -v quartus_sh.exe >/dev/null; then
		cand=("$(dirname "$(command -v quartus_sh.exe)")")
	else
		# newest version first
		mapfile -t cand < <(ls -d ~/intelFPGA_lite/*/quartus/bin ~/intelFPGA/*/quartus/bin \
			/opt/intelFPGA_lite/*/quartus/bin /opt/intelFPGA/*/quartus/bin \
			/mnt/c/intelFPGA_lite/*/quartus/bin64 /mnt/c/intelFPGA/*/quartus/bin64 2>/dev/null | sort -rV)
	fi
	for d in "${cand[@]}"; do
		if [ -x "${d}/quartus_sh" ]; then quartus_bin=$d; exe=""; return; fi
		if [ -x "${d}/quartus_sh.exe" ]; then quartus_bin=$d; exe=".exe"; return; fi
	done
	die "Quartus not found; pass --quartus DIR or set QUARTUS_BIN"
}

q() {
	local tool=$1; shift
	msg ">> ${tool} $*"
	[ ${dry_run} -eq 1 ] && return 0
	(cd "${build_dir}" && "${quartus_bin}/${tool}${exe}" "$@")
}

gen_firmware() {
	# Same images as run_emul.sh: FirmwareLoader instances in Emulator.sv read ../load_firmware_*.hex
	local p=${root_dir}/programs gen=${root_dir}/run/generate_rom.py
	python3 "${gen}" -f "${p}/helloworld.bfk" "${p}/fibonachi.bfk" "${p}/pi.bfk" "${p}/rot13.bfk" \
		"${p}/triangle.bfk" "${p}/fractal.bfk" -o "${root_dir}/firmware.hex" --hex --pack >/dev/null
	python3 "${gen}" -f "${p}/program.bfk" -o "${root_dir}/load_firmware.hex" --hex >/dev/null
	python3 "${gen}" -f "${p}/helloworld.bfk" -o "${root_dir}/load_firmware_hello.hex" --hex >/dev/null
	python3 "${gen}" -f "${p}/pi.bfk" -o "${root_dir}/load_firmware_pi.hex" --hex >/dev/null
}

gen_project() {
	mkdir -p "${build_dir}"
	cat >"${build_dir}/${rev}.qpf" <<EOF
QUARTUS_VERSION = "23.1"
PROJECT_REVISION = "${rev}"
EOF
	{
		echo "# Generated by rtl/run/build_fpga.sh from quartus/Emulator.qsf, Emulator/Emul.files and"
		echo "# DekatronPC/DPC.files. Do not edit: the next build overwrites it."
		grep -vE -- '-name (SYSTEMVERILOG_FILE|VERILOG_FILE|SDC_FILE|VERILOG_MACRO|SEARCH_PATH|NUM_PARALLEL_PROCESSORS|LAST_QUARTUS_VERSION|PROJECT_OUTPUT_DIRECTORY|VERILOG_CONSTANT_LOOP_LIMIT) ' "${qsf_src}"
		echo
		echo "set_global_assignment -name NUM_PARALLEL_PROCESSORS ${jobs}"
		echo "set_global_assignment -name PROJECT_OUTPUT_DIRECTORY output_files"
		# RamBank zero-init loops over a whole bank (10^4 cells in IpMemory); Quartus default is 5000
		echo "set_global_assignment -name VERILOG_CONSTANT_LOOP_LIMIT 100000"
		echo "set_global_assignment -name VERILOG_MACRO \"EMULATOR=True\""
		for m in "${macros[@]}"; do
			echo "set_global_assignment -name VERILOG_MACRO \"${m}\""
		done
		echo "set_global_assignment -name SDC_FILE ${sdc_src}"
		local f
		# DPC first: parameters.sv defines the package the Emulator layer imports
		for f in $(cat "${root_dir}/DekatronPC/DPC.files" "${root_dir}/Emulator/Emul.files"); do
			case "${f}" in
			*_assertions.sv) continue ;;   # only bound under ASSERTIONS, simulation-only
			*.sv) echo "set_global_assignment -name SYSTEMVERILOG_FILE ${f}" ;;
			*.v) echo "set_global_assignment -name VERILOG_FILE ${f}" ;;
			*) die "unknown source type: ${f}" ;;
			esac
			[ -f "${build_dir}/${f}" ] || die "missing source: ${f}"
		done
	} >"${build_dir}/${rev}.qsf"
}

summary() {
	local o=${build_dir}/output_files
	[ ${dry_run} -eq 1 ] && return 0
	for s in map fit sta; do
		if [ -f "${o}/${rev}.${s}.summary" ]; then
			msg "---- ${rev}.${s}.summary"
			tr -d '\r' <"${o}/${rev}.${s}.summary" >&2
		fi
	done
	[ -f "${o}/${rev}.sof" ] && msg "---- bitstream: ${o}/${rev}.sof"
	return 0
}

do_program() {
	[ ${dry_run} -eq 1 ] || [ -f "${build_dir}/output_files/${rev}.sof" ] \
		|| die "no ${build_dir}/output_files/${rev}.sof; run the compile stage first"
	q quartus_pgm -c "${cable}" -m JTAG -o "p;output_files/${rev}.sof@${jtag_index}"
}

parse_params "$@"
find_quartus
msg "Quartus: ${quartus_bin}"

case "${stage}" in
list-cables)
	q quartus_pgm -l
	exit 0
	;;
program)
	do_program
	exit 0
	;;
esac

[ ${gen_fw} -eq 1 ] && gen_firmware
gen_project
msg "Project: ${build_dir}/${rev}.qsf"

trap summary EXIT
case "${stage}" in
elab) q quartus_map "${rev}" --analysis_and_elaboration ;;
syn) q quartus_map "${rev}" ;;
compile)
	q quartus_map "${rev}"
	q quartus_fit "${rev}"
	q quartus_asm "${rev}"
	q quartus_sta "${rev}"
	if [ ${make_rbf} -eq 1 ]; then
		q quartus_cpf -c -o bitstream_compression=on "output_files/${rev}.sof" "output_files/${rev}.rbf"
	fi
	[ ${program} -eq 1 ] && do_program
	;;
esac
exit 0
