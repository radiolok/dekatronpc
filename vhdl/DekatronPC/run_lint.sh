#!/bin/bash
set -Eeuo pipefail



SourceFiles="IpLine/IpLine.sv \
	IpLine/IpCounter.sv \
	IpLine/InsnLoopDetector.sv \
	IpLine/ROM.sv \
	IpLine/RAM.sv \
	Dekatron/BcdToBin.v \
        Dekatron/BinToBcd.v  \
	Dekatron/Dekatron.sv  \
	Dekatron/DekatronCarrySignal.sv  \
	Dekatron/DekatronCounter.sv  \
	Dekatron/DekatronModule.sv  \
	Dekatron/DekatronPulseAllow.sv  \
	Dekatron/DekatronPulseSender.sv \
	../programs/looptest/looptest.sv \
	../Logic/RsLatch.sv \
	../Logic/ClockDivider.sv"

verilator --top-module IpLine --lint-only  -Wall ${SourceFiles}


echo "Dekatron Test"
iverilog -g2012 -o DekatronUT -s Dekatron_tb tests/Dekatron.sv/Dekatron_tb.sv $SourceFiles
./DekatronUT

echo "Counter Test"
iverilog -g2012 -o CounterUT -s Counter_tb tests/Counter.sv/Counter_tb.sv $SourceFiles
./CounterUT
