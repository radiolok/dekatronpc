#!/usr/bin/env bash
set -Eeuo pipefail

script_dir=$(readlink -f "$(dirname "$0")")
project_dir="$script_dir/quartus"
project_name="Emulator"
log_file="$project_dir/build.log"

quartus_sh=""
quartus_pgm=""
exe=""

info() { echo -e "\e[32m[INFO]\e[0m  $*"; }
warn() { echo -e "\e[33m[WARN]\e[0m  $*"; }
die()  { echo -e "\e[31m[ERROR]\e[0m $*"; exit 1; }

find_quartus() {
    local quartus_bin_dir

    case "$OSTYPE" in
        msys|cygwin) quartus_bin_dir=bin64 ; exe=".exe" ;;
        linux-gnu)   quartus_bin_dir=bin   ; exe=""    ;;
        *)           quartus_bin_dir=bin64 ; exe=".exe" ;;
    esac

    # 1. QUARTUS_ROOTDIR env var
    # MSYS automatically converts C:\foo\bar -> /c/foo/bar for inherited env vars
    if [ -n "${QUARTUS_ROOTDIR-}" ] && [ -d "$QUARTUS_ROOTDIR" ]; then
        if [ -x "$QUARTUS_ROOTDIR/$quartus_bin_dir/quartus_sh$exe" ]; then
            quartus_sh="$QUARTUS_ROOTDIR/$quartus_bin_dir/quartus_sh$exe"
            quartus_pgm="$QUARTUS_ROOTDIR/$quartus_bin_dir/quartus_pgm$exe"
            export PATH="${PATH:+$PATH:}$QUARTUS_ROOTDIR/$quartus_bin_dir"
            return 0
        fi
    fi

    # 2. quartus_sh in PATH
    local found
    found=$(command -v quartus_sh 2>/dev/null) || true
    if [ -n "$found" ]; then
        found=$(readlink -f "$found")
        local parent_dir bin_dir_name
        parent_dir=$(dirname "$found")
        bin_dir_name=$(basename "$parent_dir")
        local quartus_root
        quartus_root=$(dirname "$parent_dir")
        if [ "$bin_dir_name" = "$quartus_bin_dir" ] && [ "$(basename "$quartus_root")" = "quartus" ]; then
            quartus_sh="$found"
            quartus_pgm="$quartus_root/$quartus_bin_dir/quartus_pgm$exe"
            export QUARTUS_ROOTDIR="$quartus_root"
            return 0
        fi
    fi

    # 3. Search standard install locations
    local search_parents=()
    if [ "$OSTYPE" = "msys" ] || [ "$OSTYPE" = "cygwin" ]; then
        search_parents=(/c /d /e)
    elif [ "$OSTYPE" = "linux-gnu" ]; then
        search_parents=("$HOME" /opt /tools)
    fi

    for parent in "${search_parents[@]}"; do
        for dirname in intelFPGA_lite intelFPGA altera; do
            local dir="$parent/$dirname"
            if [ -d "$dir" ]; then
                local ver_dir
                ver_dir=$(find "$dir" -mindepth 1 -maxdepth 1 -type d -name '[0-9]*' 2>/dev/null | sort -V | tail -1)
                local qsh="$ver_dir/quartus/$quartus_bin_dir/quartus_sh$exe"
                if [ -n "$ver_dir" ] && [ -x "$qsh" ]; then
                    quartus_sh="$qsh"
                    quartus_pgm="$ver_dir/quartus/$quartus_bin_dir/quartus_pgm$exe"
                    export QUARTUS_ROOTDIR="$ver_dir/quartus"
                    export PATH="${PATH:+$PATH:}$ver_dir/quartus/$quartus_bin_dir"
                    return 0
                fi
            fi
        done
    done

    return 1
}

build() {
    if ! find_quartus; then
        die "Quartus not found."$'\n'"Set QUARTUS_ROOTDIR or add quartus_sh to PATH."$'\n'"Expected: C:/intelFPGA_lite/<version>/quartus/bin64/quartus_sh.exe"
    fi

    info "Using Quartus: $quartus_sh"
    info "Project: $project_dir/$project_name.qpf"

    cd "$project_dir"
    > "$log_file"

    info "Starting compilation (log: $log_file)..."
    "$quartus_sh" --no_banner --flow compile "$project_name" 2>&1 | tee -a "$log_file"

    if [ -f "$project_dir/$project_name.sof" ]; then
        info "Bitstream generated: $project_dir/$project_name.sof"
    else
        warn "$project_name.sof not found. Check $log_file"
    fi
}

clean() {
    info "Cleaning build artifacts in $project_dir..."
    cd "$project_dir"
    rm -rf db incremental_db greybox_tmp *.done *.rpt *.summary *.smsg *.pin *.qws
    rm -f "$project_name.sof" "$project_name.pof" "$project_name.jic" "$project_name.jdi"
    rm -f build.log
    info "Clean complete."
}

program() {
    if ! find_quartus; then
        die "Quartus not found."
    fi

    local sof="$project_dir/$project_name.sof"
    if [ ! -f "$sof" ]; then
        die "$project_name.sof not found. Run build first."
    fi

    info "Programming FPGA with $sof..."
    "$quartus_pgm" -c "USB-Blaster" -m jtag -o "p;$sof"
    info "Programming complete."
}

case "${1:-build}" in
    build)   build ;;
    clean)   clean ;;
    program) program ;;
    *)
        echo "Usage: $0 {build|clean|program}"
        echo "  build   - compile bitstream (default)"
        echo "  clean   - remove build artifacts"
        echo "  program - program FPGA via USB-Blaster"
        exit 1
        ;;
esac
