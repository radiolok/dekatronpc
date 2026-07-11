FROM ubuntu:26.04

RUN apt-get update -y && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    python3 \
    python-is-python3 \
    python3-pip \
    python3-venv \
    verilator \
    yosys \
    iverilog \
    g++ \
    make \
    libncurses-dev \
    graphviz \
    && rm -rf /var/lib/apt/lists

RUN python3 -m venv /var/venv && \
    /var/venv/bin/pip install liberty-parser cocotb pyuvm pytest

WORKDIR /var/rtl/run
