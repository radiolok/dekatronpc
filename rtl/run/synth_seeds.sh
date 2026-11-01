#!/bin/bash
# Tube count of the given blocks over several &deepsyn seeds, in parallel.
# usage: synth_seeds.sh [-f <file list>] [-o <out dir>] [-s "<seeds>"] [-a "<synt_dpc.tcl options>"] <block>...
#   -f  RTL file list (default ../DekatronPC/DPC.files)
#   -o  directory for the runs (default a temporary one, removed at the end)
#   -s  seeds (default "0 1 2")
#   -a  extra synt_dpc.tcl options, e.g. "-flatglue"
# Prints tubes per block and seed, the per-seed total and the mean.
set -Eeuo pipefail
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd -P)
files=${script_dir}/../DekatronPC/DPC.files
out=""
seeds="0 1 2"
extra=""
while getopts "f:o:s:a:" o; do
  case $o in
    f) files=$(realpath "$OPTARG") ;;
    o) out=$OPTARG ;;
    s) seeds=$OPTARG ;;
    a) extra=$OPTARG ;;
    *) exit 1 ;;
  esac
done
shift $((OPTIND-1))
blocks=("$@")
keep=1
if [ -z "$out" ]; then out=$(mktemp -d); keep=0; fi
mkdir -p "$out"
py=${script_dir}/.venv/bin/python
lib=${DPC_CELL_LIB:-${script_dir}/../../sch/logic/vtube_cells.lib}
for s in $seeds; do
  for b in "${blocks[@]}"; do
    d=$out/$b.s$s; mkdir -p "$d"
    ( cd "$d" && echo "tcl ${script_dir}/synt_dpc.tcl $files $b $extra" | DPC_ABC_SEED=$s yosys > yosys.log 2>&1 \
        || echo "FAIL $b seed $s (see $d/yosys.log)" ) &
  done
done
wait
printf "%-14s" "seed"; for b in "${blocks[@]}"; do printf "%12s" "$b"; done; printf "%10s\n" "total"
sum=0; n=0
for s in $seeds; do
  printf "%-14s" "$s"; t=0
  for b in "${blocks[@]}"; do
    v=$(cd $out/$b.s$s && $py ${script_dir}/dpc_stat.py -j $b.json -l $lib 2>/dev/null | awk -F'\t+' '/^Total/{print $2}')
    printf "%12s" "$v"; t=$(echo "$t + ${v:-0}" | bc)
  done
  printf "%10s\n" "$t"; sum=$(echo "$sum + $t" | bc); n=$((n+1))
done
echo "mean total: $(echo "scale=1; $sum / $n" | bc)"
[ $keep = 1 ] || rm -rf "$out"
