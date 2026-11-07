#!/bin/bash
# Source this before running any OpenFOAM command in this case.
# The v2206 build here is Intel-compiled (linux64IccDPInt32Opt) and needs
# the classic Intel runtime + Intel MPI.  Source the Intel MPI environment
# first so OpenFOAM's config.sh/mpi finds I_MPI_ROOT, then OpenFOAM itself.
source /opt/intel/oneapi/mpi/2021.17/env/vars.sh 2>/dev/null
source /opt/OpenFOAM-v2206/etc/bashrc 2>/dev/null
export LD_LIBRARY_PATH=/opt/intel/oneapi/compiler/2025.3/lib:$LD_LIBRARY_PATH
