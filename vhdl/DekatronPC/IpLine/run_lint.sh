verilator --top-module IpLine --lint-only  -Wall \
	IpLine.sv \
	../Dekatron/BcdToBin.v \
    ../Dekatron/BinToBcd.v  \
	../Dekatron/Dekatron.sv  \
	../Dekatron/DekatronCarrySignal.sv  \
	../Dekatron/DekatronCounter.sv  \
	../Dekatron/DekatronModule.sv  \
	../Dekatron/DekatronPulseAllow.sv  \
	../Dekatron/DekatronPulseSender.sv \
	../../programs/looptest/looptest.sv \
	../../Logic/RsLatch.sv
