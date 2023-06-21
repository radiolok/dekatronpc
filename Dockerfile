FROM ubuntu:22.04 AS build

RUN rm /bin/sh && ln -s /bin/bash /bin/sh

RUN apt-get update -y && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    pkgconf \
    ca-certificates \
    software-properties-common \
    gnupg \
    gnupg2 \
    libnl-3-200 \
    libnl-route-3-200 \
    libhwloc-dev \
    libnuma1 \
    bzip2 \
    file \
    make \
    perl \
    tar \
    flex \
    git \
    curl \
    vim \
    openssh-client \
    libnuma-dev \
    build-essential \
    autoconf \
    automake \
    gfortran \
    python3 \
    python-is-python3 \
    python3-dev \
    python3-pip \
    python3-venv \
    libtool \
    wget

RUN DEBIAN_FRONTEND=noninteractive apt-get install -y \
    gperf g++ bison ccache \
    libgoogle-perftools-dev numactl perl-doc help2man \
    libfl2 libfl-dev \
    libncursesw5-dev && \
    rm -rf /var/lib/apt/lists

RUN git clone https://github.com/verilator/verilator && \
    cd verilator && git checkout v5.010 && \
    autoconf && ./configure && make -j `nproc` && make install

RUN apt-get update -y &&  DEBIAN_FRONTEND=noninteractive apt-get install -y \
    clang  libreadline-dev gawk tcl-dev libffi-dev \
	graphviz xdot pkg-config python3 libboost-system-dev \
	libboost-python-dev libboost-filesystem-dev && \
    rm -rf /var/lib/apt/lists

RUN git clone https://github.com/YosysHQ/yosys.git && \
    pip install liberty-parser && \
    cd yosys && make config-clang && make && make install 

RUN apt-get update -y && DEBIAN_FRONTEND=noninteractive apt-get install -y \
    iverilog && \
    rm -rf /var/lib/apt/lists

RUN rm -rf /yosys && rm -rf /verilator

RUN mkdir -p /var/vhdl

WORKDIR /var/vhdl
