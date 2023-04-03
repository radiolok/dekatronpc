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

exit
echo "IpCounter Test"
iverilog -g2012 -o IpCounter -s IpCounter_tb.sv tb/IpCounter_tb.sv $SourceFiles
