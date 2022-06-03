#!/bin/bash


set -Eeuo pipefail
trap cleanup SIGINT SIGTERM ERR EXIT

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd -P)


cleanup() {
    trap - SIGINT SIGTERM ERR EXIT
    exit

}

if [ "$#" -ne 2 ]; then
      echo "Set <test_dir> <top_level_module>"
    exit
fi

current_dir=$(pwd)
cd ${1}
iverilog -cfiles -g2012 -s${2} -o${2}
./${2}
cd ${current_dir}
