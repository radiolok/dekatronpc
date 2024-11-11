iverilog -o Counter Counter_tb.sv \
	../../../Dekatron/DekCounter.sv \
	../../../Dekatron/dekatronModule.sv \
	../../../Dekatron/dekatronPulseSender.v \
	../../../Dekatron/dekatronCarrySignal.sv \
	../../../Logic/BcdToBinary.sv \
	../../../Dekatron/dekatron.v \
	-g2012
./Counter
