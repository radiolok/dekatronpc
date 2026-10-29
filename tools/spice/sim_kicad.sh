#!/usr/bin/env bash
# Simulate a KiCad testbench from the command line, the same netlist the KiCad simulator runs.
# usage: tools/spice/sim_kicad.sh sch/logic/NOR2_N16/NOR2_N16_tb.kicad_sch [out_dir]
# kicad-cli leaves ${KIPRJMOD} empty, so the model path is fixed up to the project directory.
# Text directives on the sheet (.tran, .meas) go into the netlist; .meas results are printed.
set -euo pipefail
HERE=$(dirname "$(realpath "$0")")
SCH=$(realpath "$1")
OUT=${2:-$(mktemp -d)}
PRJ=$(dirname "$SCH")
NAME=$(basename "$SCH" .kicad_sch)
mkdir -p "$OUT"
[ -f "$PRJ/$NAME.kicad_pro" ] || { echo "no $PRJ/$NAME.kicad_pro: kicad-cli needs the project file next to the sheet" >&2; exit 1; }
kicad-cli sch export netlist --format spice -o "$OUT/$NAME.cir" "$SCH" 2>/dev/null \
  || { echo "kicad-cli netlist export failed for $SCH" >&2; exit 1; }
sed -i "s|^\.include \"/\.\./|.include \"$PRJ/../|" "$OUT/$NAME.cir"
cd "$OUT"
python3 "$HERE/ngrun.py" "$NAME.cir" run \
  | grep -E '^[a-z_0-9]+ +=|[Ee]rror' || true
echo "netlist: $OUT/$NAME.cir"
