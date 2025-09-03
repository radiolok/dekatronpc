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
    wget && \
    rm -rf /var/lib/apt/lists

RUN apt-get update -y &&  DEBIAN_FRONTEND=noninteractive apt-get install -y \
    gperf g++ bison ccache \
    libgoogle-perftools-dev numactl perl-doc help2man \
    libfl2 libfl-dev \
    libncursesw5-dev && \
    rm -rf /var/lib/apt/lists

RUN wget https://github.com/verilator/verilator/archive/refs/tags/v5.040.tar.gz && \
    tar -xvf v5.040.tar.gz && cd verilator-5.040 && \
    autoconf && ./configure && make -j `nproc` && make install && \
    cd / && rm -rf /verilator-5.040 && rm -rf v5.040.tar.gz


RUN apt-get update -y &&  DEBIAN_FRONTEND=noninteractive apt-get install -y \
    libreadline-dev gawk tcl-dev libffi-dev \
	graphviz xdot pkg-config libboost-system-dev \
	libboost-python-dev libboost-filesystem-dev && \
    rm -rf /var/lib/apt/lists

RUN git clone https://github.com/YosysHQ/yosys.git && \
    cd yosys && git checkout 0.56 && git submodule update --init && \
    make config-gcc && make -j `nproc` && make install && \
    pip install liberty-parser && \
    cd / && rm -rf /yosys

RUN apt-get update -y && DEBIAN_FRONTEND=noninteractive apt-get install -y \
    iverilog && \
    rm -rf /var/lib/apt/lists

RUN mkdir -p /var/vhdl

WORKDIR /var/vhdl
