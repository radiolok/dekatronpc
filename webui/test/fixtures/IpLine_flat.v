/* Yosys flatten of IpLine_synth.v (reference for test/parsers/verilog.test.ts):
   hierarchy -top IpLine; setattr -mod -unset keep_hierarchy *; flatten; opt_clean -purge; write_verilog -noattr */

module IpLine(Rst_n, Clk, hsClk, HaltRq, dataIsZeroed, key_next_app_i, Request, Ready, IpAddress, LoopCount, RomRequest, RomReady, RomData, Insn);
  input Clk;
  wire Clk;
  input HaltRq;
  wire HaltRq;
  wire IP_Dec;
  wire IP_Ready;
  wire IP_Request;
  wire [2:0] \IP_counter.Nines ;
  wire \IP_counter.PulseF ;
  wire \IP_counter.PulseR ;
  wire [1:0] \IP_counter.Pulses ;
  wire [2:0] \IP_counter.SetTopZero ;
  wire [3:0] \IP_counter.TopOut ;
  wire \IP_counter.Zero ;
  wire [3:0] \IP_counter.Zeroes ;
  wire \IP_counter._00_ ;
  wire \IP_counter._01_ ;
  wire \IP_counter._02_ ;
  wire \IP_counter._03_ ;
  wire \IP_counter._04_ ;
  wire \IP_counter._05_ ;
  wire \IP_counter._06_ ;
  wire \IP_counter._07_ ;
  wire \IP_counter._08_ ;
  wire \IP_counter._09_ ;
  wire \IP_counter._10_ ;
  wire \IP_counter._11_ ;
  wire \IP_counter._12_ ;
  wire \IP_counter._13_ ;
  wire \IP_counter._14_ ;
  wire \IP_counter._15_ ;
  wire \IP_counter._16_ ;
  wire \IP_counter._17_ ;
  wire \IP_counter._18_ ;
  wire \IP_counter._19_ ;
  wire \IP_counter._20_ ;
  wire \IP_counter._21_ ;
  wire \IP_counter._22_ ;
  wire \IP_counter._23_ ;
  wire \IP_counter._24_ ;
  wire \IP_counter._25_ ;
  wire \IP_counter._26_ ;
  wire \IP_counter._27_ ;
  wire \IP_counter._28_ ;
  wire \IP_counter._29_ ;
  wire \IP_counter._30_ ;
  wire \IP_counter._31_ ;
  wire \IP_counter._32_ ;
  wire \IP_counter._Request ;
  wire \IP_counter.dek[0].DekNine ;
  wire \IP_counter.dek[0].DekZero ;
  wire \IP_counter.dek[0].dModule.InPosDek_n ;
  wire [9:0] \IP_counter.dek[0].dModule.OutPos ;
  wire [1:0] \IP_counter.dek[0].dModule.Pulses ;
  wire \IP_counter.dek[0].dModule.Reading.binToDbc._0_ ;
  wire \IP_counter.dek[0].dModule.Reading.binToDbc._1_ ;
  wire \IP_counter.dek[0].dModule.pulseSender.Dec ;
  wire \IP_counter.dek[0].dModule.pulseSender.OS_2 ;
  wire \IP_counter.dek[0].dModule.pulseSender.OS_3 ;
  wire \IP_counter.dek[0].dModule.pulseSender.PulseAny ;
  wire \IP_counter.dek[0].dModule.pulseSender._00_ ;
  wire \IP_counter.dek[0].dModule.pulseSender._01_ ;
  wire \IP_counter.dek[0].dModule.pulseSender._02_ ;
  wire \IP_counter.dek[0].dModule.pulseSender._03_ ;
  wire \IP_counter.dek[0].dModule.pulseSender._04_ ;
  wire \IP_counter.dek[0].dModule.pulseSender._05_ ;
  wire [1:0] \IP_counter.dek[0].dModule.pulseSender._Pulses ;
  wire \IP_counter.dek[0].dModule.pulseSender.pA ;
  wire [1:0] \IP_counter.dek[0].npulses ;
  wire \IP_counter.dek[1].DekNine ;
  wire \IP_counter.dek[1].DekZero ;
  wire \IP_counter.dek[1].dModule.InPosDek_n ;
  wire [9:0] \IP_counter.dek[1].dModule.OutPos ;
  wire [1:0] \IP_counter.dek[1].dModule.Pulses ;
  wire \IP_counter.dek[1].dModule.Reading.binToDbc._0_ ;
  wire \IP_counter.dek[1].dModule.Reading.binToDbc._1_ ;
  wire \IP_counter.dek[1].dModule.pulseSender.Dec ;
  wire \IP_counter.dek[1].dModule.pulseSender.OS_2 ;
  wire \IP_counter.dek[1].dModule.pulseSender.OS_3 ;
  wire \IP_counter.dek[1].dModule.pulseSender.PulseAny ;
  wire \IP_counter.dek[1].dModule.pulseSender._00_ ;
  wire \IP_counter.dek[1].dModule.pulseSender._01_ ;
  wire \IP_counter.dek[1].dModule.pulseSender._02_ ;
  wire \IP_counter.dek[1].dModule.pulseSender._03_ ;
  wire \IP_counter.dek[1].dModule.pulseSender._04_ ;
  wire \IP_counter.dek[1].dModule.pulseSender._05_ ;
  wire [1:0] \IP_counter.dek[1].dModule.pulseSender._Pulses ;
  wire \IP_counter.dek[1].dModule.pulseSender.pA ;
  wire [1:0] \IP_counter.dek[1].npulses ;
  wire \IP_counter.dek[2].DekNine ;
  wire \IP_counter.dek[2].DekZero ;
  wire \IP_counter.dek[2].dModule.InPosDek_n ;
  wire [9:0] \IP_counter.dek[2].dModule.OutPos ;
  wire [1:0] \IP_counter.dek[2].dModule.Pulses ;
  wire \IP_counter.dek[2].dModule.Reading.binToDbc._0_ ;
  wire \IP_counter.dek[2].dModule.Reading.binToDbc._1_ ;
  wire \IP_counter.dek[2].dModule.pulseSender.Dec ;
  wire \IP_counter.dek[2].dModule.pulseSender.OS_2 ;
  wire \IP_counter.dek[2].dModule.pulseSender.OS_3 ;
  wire \IP_counter.dek[2].dModule.pulseSender.PulseAny ;
  wire \IP_counter.dek[2].dModule.pulseSender._00_ ;
  wire \IP_counter.dek[2].dModule.pulseSender._01_ ;
  wire \IP_counter.dek[2].dModule.pulseSender._02_ ;
  wire \IP_counter.dek[2].dModule.pulseSender._03_ ;
  wire \IP_counter.dek[2].dModule.pulseSender._04_ ;
  wire \IP_counter.dek[2].dModule.pulseSender._05_ ;
  wire [1:0] \IP_counter.dek[2].dModule.pulseSender._Pulses ;
  wire \IP_counter.dek[2].dModule.pulseSender.pA ;
  wire [1:0] \IP_counter.dek[2].npulses ;
  wire \IP_counter.dek[3].DekNine ;
  wire \IP_counter.dek[3].dModule.InPosDek_n ;
  wire [9:0] \IP_counter.dek[3].dModule.OutPos ;
  wire [1:0] \IP_counter.dek[3].dModule.Pulses ;
  wire \IP_counter.dek[3].dModule.Reading.binToDbc._0_ ;
  wire \IP_counter.dek[3].dModule.Reading.binToDbc._1_ ;
  wire \IP_counter.dek[3].dModule.pulseSender.Dec ;
  wire \IP_counter.dek[3].dModule.pulseSender.OS_2 ;
  wire \IP_counter.dek[3].dModule.pulseSender.OS_3 ;
  wire \IP_counter.dek[3].dModule.pulseSender.PulseAny ;
  wire \IP_counter.dek[3].dModule.pulseSender._00_ ;
  wire \IP_counter.dek[3].dModule.pulseSender._01_ ;
  wire \IP_counter.dek[3].dModule.pulseSender._02_ ;
  wire \IP_counter.dek[3].dModule.pulseSender._03_ ;
  wire \IP_counter.dek[3].dModule.pulseSender._04_ ;
  wire \IP_counter.dek[3].dModule.pulseSender._05_ ;
  wire [1:0] \IP_counter.dek[3].dModule.pulseSender._Pulses ;
  wire \IP_counter.dek[3].dModule.pulseSender.pA ;
  wire [2:0] \IP_counter.next ;
  wire [2:0] \IP_counter.state ;
  wire \IP_counter.write_set ;
  wire \IP_counter.writed_n ;
  output [3:0] Insn;
  wire [3:0] Insn;
  output [19:0] IpAddress;
  wire [19:0] IpAddress;
  output [11:0] LoopCount;
  wire [11:0] LoopCount;
  wire LoopInsnClose;
  wire LoopInsnCloseInternal;
  wire LoopInsnOpen;
  wire LoopInsnOpenInternal;
  wire Loop_Dec;
  wire Loop_Ready;
  wire Loop_Request;
  wire Loop_Zero;
  wire [1:0] \Loop_counter.Nines ;
  wire \Loop_counter.PulseF ;
  wire \Loop_counter.PulseR ;
  wire [1:0] \Loop_counter.Pulses ;
  wire [2:0] \Loop_counter.SetTopZero ;
  wire [2:0] \Loop_counter.TopOut ;
  wire [2:0] \Loop_counter.Zeroes ;
  wire \Loop_counter._00_ ;
  wire \Loop_counter._01_ ;
  wire \Loop_counter._02_ ;
  wire \Loop_counter._03_ ;
  wire \Loop_counter._04_ ;
  wire \Loop_counter._05_ ;
  wire \Loop_counter._06_ ;
  wire \Loop_counter._07_ ;
  wire \Loop_counter._08_ ;
  wire \Loop_counter._09_ ;
  wire \Loop_counter._10_ ;
  wire \Loop_counter._11_ ;
  wire \Loop_counter._12_ ;
  wire \Loop_counter._13_ ;
  wire \Loop_counter._14_ ;
  wire \Loop_counter._15_ ;
  wire \Loop_counter._16_ ;
  wire \Loop_counter._17_ ;
  wire \Loop_counter._18_ ;
  wire \Loop_counter._19_ ;
  wire \Loop_counter._20_ ;
  wire \Loop_counter._21_ ;
  wire \Loop_counter._22_ ;
  wire \Loop_counter._23_ ;
  wire \Loop_counter._24_ ;
  wire \Loop_counter._25_ ;
  wire \Loop_counter._Request ;
  wire \Loop_counter.dek[0].DekNine ;
  wire \Loop_counter.dek[0].DekZero ;
  wire \Loop_counter.dek[0].dModule.InPosDek_n ;
  wire [9:0] \Loop_counter.dek[0].dModule.OutPos ;
  wire [1:0] \Loop_counter.dek[0].dModule.Pulses ;
  wire \Loop_counter.dek[0].dModule.pulseSender.Dec ;
  wire \Loop_counter.dek[0].dModule.pulseSender.OS_2 ;
  wire \Loop_counter.dek[0].dModule.pulseSender.OS_3 ;
  wire \Loop_counter.dek[0].dModule.pulseSender.PulseAny ;
  wire \Loop_counter.dek[0].dModule.pulseSender._00_ ;
  wire \Loop_counter.dek[0].dModule.pulseSender._01_ ;
  wire \Loop_counter.dek[0].dModule.pulseSender._02_ ;
  wire \Loop_counter.dek[0].dModule.pulseSender._03_ ;
  wire \Loop_counter.dek[0].dModule.pulseSender._04_ ;
  wire \Loop_counter.dek[0].dModule.pulseSender._05_ ;
  wire [1:0] \Loop_counter.dek[0].dModule.pulseSender._Pulses ;
  wire \Loop_counter.dek[0].dModule.pulseSender.pA ;
  wire [1:0] \Loop_counter.dek[0].npulses ;
  wire \Loop_counter.dek[1].DekNine ;
  wire \Loop_counter.dek[1].DekZero ;
  wire \Loop_counter.dek[1].dModule.InPosDek_n ;
  wire [9:0] \Loop_counter.dek[1].dModule.OutPos ;
  wire [1:0] \Loop_counter.dek[1].dModule.Pulses ;
  wire \Loop_counter.dek[1].dModule.pulseSender.Dec ;
  wire \Loop_counter.dek[1].dModule.pulseSender.OS_2 ;
  wire \Loop_counter.dek[1].dModule.pulseSender.OS_3 ;
  wire \Loop_counter.dek[1].dModule.pulseSender.PulseAny ;
  wire \Loop_counter.dek[1].dModule.pulseSender._00_ ;
  wire \Loop_counter.dek[1].dModule.pulseSender._01_ ;
  wire \Loop_counter.dek[1].dModule.pulseSender._02_ ;
  wire \Loop_counter.dek[1].dModule.pulseSender._03_ ;
  wire \Loop_counter.dek[1].dModule.pulseSender._04_ ;
  wire \Loop_counter.dek[1].dModule.pulseSender._05_ ;
  wire [1:0] \Loop_counter.dek[1].dModule.pulseSender._Pulses ;
  wire \Loop_counter.dek[1].dModule.pulseSender.pA ;
  wire [1:0] \Loop_counter.dek[1].npulses ;
  wire \Loop_counter.dek[2].DekNine ;
  wire \Loop_counter.dek[2].DekZero ;
  wire \Loop_counter.dek[2].dModule.InPosDek_n ;
  wire [9:0] \Loop_counter.dek[2].dModule.OutPos ;
  wire [1:0] \Loop_counter.dek[2].dModule.Pulses ;
  wire \Loop_counter.dek[2].dModule.pulseSender.Dec ;
  wire \Loop_counter.dek[2].dModule.pulseSender.OS_2 ;
  wire \Loop_counter.dek[2].dModule.pulseSender.OS_3 ;
  wire \Loop_counter.dek[2].dModule.pulseSender.PulseAny ;
  wire \Loop_counter.dek[2].dModule.pulseSender._00_ ;
  wire \Loop_counter.dek[2].dModule.pulseSender._01_ ;
  wire \Loop_counter.dek[2].dModule.pulseSender._02_ ;
  wire \Loop_counter.dek[2].dModule.pulseSender._03_ ;
  wire \Loop_counter.dek[2].dModule.pulseSender._04_ ;
  wire \Loop_counter.dek[2].dModule.pulseSender._05_ ;
  wire [1:0] \Loop_counter.dek[2].dModule.pulseSender._Pulses ;
  wire \Loop_counter.dek[2].dModule.pulseSender.pA ;
  wire [2:0] \Loop_counter.next ;
  wire [2:0] \Loop_counter.state ;
  wire \Loop_counter.write_set ;
  wire \Loop_counter.writed_n ;
  output Ready;
  wire Ready;
  input Request;
  wire Request;
  input [3:0] RomData;
  wire [3:0] RomData;
  input RomReady;
  wire RomReady;
  output RomRequest;
  wire RomRequest;
  input Rst_n;
  wire Rst_n;
  wire _000_;
  wire _001_;
  wire _002_;
  wire _003_;
  wire _004_;
  wire _005_;
  wire _006_;
  wire _007_;
  wire _008_;
  wire _009_;
  wire _010_;
  wire _011_;
  wire _012_;
  wire _013_;
  wire _014_;
  wire _015_;
  wire _016_;
  wire _017_;
  wire _018_;
  wire _019_;
  wire _020_;
  wire _021_;
  wire _022_;
  wire _023_;
  wire _024_;
  wire _025_;
  wire _026_;
  wire _027_;
  wire _028_;
  wire _029_;
  wire _030_;
  wire _031_;
  wire _032_;
  wire _033_;
  wire _034_;
  wire _035_;
  wire _036_;
  wire _037_;
  wire _038_;
  wire _039_;
  wire _040_;
  wire _041_;
  wire _042_;
  wire _043_;
  wire _044_;
  wire _045_;
  wire _046_;
  wire _047_;
  wire _048_;
  wire _049_;
  wire _050_;
  wire _051_;
  wire _052_;
  wire _053_;
  wire _054_;
  wire _055_;
  wire _056_;
  wire _057_;
  wire _058_;
  wire _059_;
  wire _060_;
  wire _061_;
  wire _062_;
  wire _063_;
  wire _064_;
  wire _065_;
  wire _066_;
  wire _067_;
  wire _068_;
  wire _069_;
  wire _070_;
  wire _071_;
  wire _072_;
  wire _073_;
  wire _074_;
  wire _075_;
  wire _076_;
  wire _077_;
  wire _078_;
  wire _079_;
  wire _080_;
  wire _081_;
  wire _082_;
  wire _083_;
  wire _084_;
  wire _085_;
  wire _086_;
  wire _087_;
  wire _088_;
  wire _089_;
  wire _090_;
  wire _091_;
  wire _092_;
  wire _093_;
  wire _094_;
  wire _095_;
  wire _096_;
  wire _097_;
  wire _098_;
  wire _099_;
  wire _100_;
  wire _101_;
  wire _102_;
  wire _103_;
  wire _104_;
  wire _105_;
  wire _106_;
  wire _107_;
  wire _108_;
  wire _109_;
  wire _110_;
  wire _111_;
  wire _112_;
  wire _113_;
  wire _114_;
  wire _115_;
  wire _116_;
  wire _117_;
  wire _118_;
  wire _119_;
  wire _120_;
  wire _121_;
  wire _122_;
  wire _123_;
  wire _124_;
  wire _125_;
  input dataIsZeroed;
  wire dataIsZeroed;
  input hsClk;
  wire hsClk;
  wire \insnLoopDetector._0_ ;
  wire \insnLoopDetector._1_ ;
  wire \insnLoopDetector._2_ ;
  wire \insnLoopDetectorInternal._0_ ;
  wire \insnLoopDetectorInternal._1_ ;
  wire \insnLoopDetectorInternal._2_ ;
  input key_next_app_i;
  wire key_next_app_i;
  wire prevApp;
  wire [2:0] state;
  NOT_6N16B \IP_counter._33_  (
    .A(\IP_counter.Zeroes [2]),
    .Y(\IP_counter._00_ )
  );
  NOT_6N16B \IP_counter._34_  (
    .A(\IP_counter.state [2]),
    .Y(\IP_counter._01_ )
  );
  NOT_6N16B \IP_counter._35_  (
    .A(\IP_counter.state [1]),
    .Y(\IP_counter._02_ )
  );
  NOT_6N16B \IP_counter._36_  (
    .A(\IP_counter.state [0]),
    .Y(\IP_counter._03_ )
  );
  NOT_6N16B \IP_counter._37_  (
    .A(\IP_counter.Pulses [0]),
    .Y(\IP_counter._04_ )
  );
  NOT_6N16B \IP_counter._38_  (
    .A(\IP_counter.Pulses [1]),
    .Y(\IP_counter._05_ )
  );
  NOT_6N16B \IP_counter._39_  (
    .A(\IP_counter.Nines [2]),
    .Y(\IP_counter._06_ )
  );
  NOT_6N16B \IP_counter._40_  (
    .A(\IP_counter._Request ),
    .Y(\IP_counter._07_ )
  );
  NOT_6N16B \IP_counter._41_  (
    .A(1'h0),
    .Y(\IP_counter._08_ )
  );
  NAND2_J2 \IP_counter._42_  (
    .A(\IP_counter.Zeroes [3]),
    .B(\IP_counter.Zeroes [2]),
    .Y(\IP_counter._09_ )
  );
  NAND2_J2 \IP_counter._43_  (
    .A(\IP_counter.Zeroes [0]),
    .B(\IP_counter.Zeroes [1]),
    .Y(\IP_counter._10_ )
  );
  NOR2_N16 \IP_counter._44_  (
    .A(\IP_counter._09_ ),
    .B(\IP_counter._10_ ),
    .Y(\IP_counter.Zero )
  );
  AND2_N16X7 \IP_counter._45_  (
    .A(\IP_counter.state [2]),
    .B(\IP_counter.writed_n ),
    .Y(\IP_counter._11_ )
  );
  AND2_N16X7 \IP_counter._46_  (
    .A(\IP_counter.state [0]),
    .B(\IP_counter._11_ ),
    .Y(\IP_counter._12_ )
  );
  AND2_N16X7 \IP_counter._47_  (
    .A(\IP_counter._02_ ),
    .B(\IP_counter._12_ ),
    .Y(\IP_counter.SetTopZero [0])
  );
  NAND2_J2 \IP_counter._48_  (
    .A(\IP_counter.state [1]),
    .B(\IP_counter._11_ ),
    .Y(\IP_counter._13_ )
  );
  NOR2_N16 \IP_counter._49_  (
    .A(\IP_counter.state [0]),
    .B(\IP_counter._13_ ),
    .Y(\IP_counter.SetTopZero [1])
  );
  NOR2_N16 \IP_counter._50_  (
    .A(\IP_counter._03_ ),
    .B(\IP_counter._13_ ),
    .Y(\IP_counter.SetTopZero [2])
  );
  NAND2_J2 \IP_counter._51_  (
    .A(\IP_counter._01_ ),
    .B(\IP_counter.state [1]),
    .Y(\IP_counter._14_ )
  );
  NOR2_N16 \IP_counter._52_  (
    .A(\IP_counter.state [0]),
    .B(\IP_counter._14_ ),
    .Y(\IP_counter.PulseF )
  );
  NAND4_N16X7 \IP_counter._53_  (
    .A(\IP_counter._01_ ),
    .B(\IP_counter.state [1]),
    .C(\IP_counter._03_ ),
    .D(\IP_counter.Nines [0]),
    .Y(\IP_counter._15_ )
  );
  NOR2_N16 \IP_counter._54_  (
    .A(\IP_counter._03_ ),
    .B(\IP_counter._14_ ),
    .Y(\IP_counter.PulseR )
  );
  NAND4_N16X7 \IP_counter._55_  (
    .A(\IP_counter._01_ ),
    .B(\IP_counter.state [1]),
    .C(\IP_counter.state [0]),
    .D(\IP_counter.Zeroes [0]),
    .Y(\IP_counter._16_ )
  );
  AND2_N16X7 \IP_counter._56_  (
    .A(\IP_counter._15_ ),
    .B(\IP_counter._16_ ),
    .Y(\IP_counter._17_ )
  );
  A1OOI_N16X7 \IP_counter._57_  (
    .A(\IP_counter._15_ ),
    .B(\IP_counter._16_ ),
    .C(\IP_counter._04_ ),
    .Y(\IP_counter.dek[0].npulses [0])
  );
  A1OOI_N16X7 \IP_counter._58_  (
    .A(\IP_counter._15_ ),
    .B(\IP_counter._16_ ),
    .C(\IP_counter._05_ ),
    .Y(\IP_counter.dek[0].npulses [1])
  );
  NAND4_N16X7 \IP_counter._59_  (
    .A(\IP_counter._01_ ),
    .B(\IP_counter.state [1]),
    .C(\IP_counter._03_ ),
    .D(\IP_counter.Nines [1]),
    .Y(\IP_counter._18_ )
  );
  NAND4_N16X7 \IP_counter._60_  (
    .A(\IP_counter._01_ ),
    .B(\IP_counter.state [1]),
    .C(\IP_counter.state [0]),
    .D(\IP_counter.Zeroes [1]),
    .Y(\IP_counter._19_ )
  );
  AND2_N16X7 \IP_counter._61_  (
    .A(\IP_counter._18_ ),
    .B(\IP_counter._19_ ),
    .Y(\IP_counter._20_ )
  );
  NAND2_J2 \IP_counter._62_  (
    .A(\IP_counter._18_ ),
    .B(\IP_counter._19_ ),
    .Y(\IP_counter._21_ )
  );
  AND2_N16X7 \IP_counter._63_  (
    .A(\IP_counter.dek[0].npulses [0]),
    .B(\IP_counter._21_ ),
    .Y(\IP_counter.dek[1].npulses [0])
  );
  AND2_N16X7 \IP_counter._64_  (
    .A(\IP_counter.dek[0].npulses [1]),
    .B(\IP_counter._21_ ),
    .Y(\IP_counter.dek[1].npulses [1])
  );
  NOR4_N16 \IP_counter._65_  (
    .A(\IP_counter.state [2]),
    .B(\IP_counter._02_ ),
    .C(\IP_counter.state [0]),
    .D(\IP_counter._06_ ),
    .Y(\IP_counter._22_ )
  );
  NOR4_N16 \IP_counter._66_  (
    .A(\IP_counter._00_ ),
    .B(\IP_counter.state [2]),
    .C(\IP_counter._02_ ),
    .D(\IP_counter._03_ ),
    .Y(\IP_counter._23_ )
  );
  NOR2_N16 \IP_counter._67_  (
    .A(\IP_counter._22_ ),
    .B(\IP_counter._23_ ),
    .Y(\IP_counter._24_ )
  );
  NOR4_N16 \IP_counter._68_  (
    .A(\IP_counter._04_ ),
    .B(\IP_counter._17_ ),
    .C(\IP_counter._20_ ),
    .D(\IP_counter._24_ ),
    .Y(\IP_counter.dek[2].npulses [0])
  );
  NOR4_N16 \IP_counter._69_  (
    .A(\IP_counter._05_ ),
    .B(\IP_counter._17_ ),
    .C(\IP_counter._20_ ),
    .D(\IP_counter._24_ ),
    .Y(\IP_counter.dek[2].npulses [1])
  );
  OR2_N16 \IP_counter._70_  (
    .A(\IP_counter.state [2]),
    .B(\IP_counter.state [0]),
    .Y(\IP_counter._25_ )
  );
  NOR4_N16 \IP_counter._71_  (
    .A(\IP_counter.state [2]),
    .B(\IP_counter.state [1]),
    .C(\IP_counter.state [0]),
    .D(\IP_counter._07_ ),
    .Y(\IP_counter._26_ )
  );
  NAND2_J2 \IP_counter._72_  (
    .A(IP_Dec),
    .B(\IP_counter._26_ ),
    .Y(\IP_counter._27_ )
  );
  OR2_N16 \IP_counter._73_  (
    .A(1'h0),
    .B(1'h0),
    .Y(\IP_counter._28_ )
  );
  A1OOI_N16X7 \IP_counter._74_  (
    .A(\IP_counter._26_ ),
    .B(\IP_counter._28_ ),
    .C(\IP_counter._12_ ),
    .Y(\IP_counter._29_ )
  );
  NAND2_J2 \IP_counter._75_  (
    .A(\IP_counter._27_ ),
    .B(\IP_counter._29_ ),
    .Y(\IP_counter.next [0])
  );
  NAND2_J2 \IP_counter._76_  (
    .A(1'h0),
    .B(\IP_counter._08_ ),
    .Y(\IP_counter._30_ )
  );
  NAND2_J2 \IP_counter._77_  (
    .A(\IP_counter._26_ ),
    .B(\IP_counter._30_ ),
    .Y(\IP_counter._31_ )
  );
  NAND2_J2 \IP_counter._78_  (
    .A(\IP_counter._13_ ),
    .B(\IP_counter._31_ ),
    .Y(\IP_counter.next [1])
  );
  NAND2_J2 \IP_counter._79_  (
    .A(\IP_counter._13_ ),
    .B(\IP_counter._29_ ),
    .Y(\IP_counter.next [2])
  );
  OR2_N16 \IP_counter._80_  (
    .A(\IP_counter.Pulses [1]),
    .B(IP_Request),
    .Y(\IP_counter._32_ )
  );
  NOR4_N16 \IP_counter._81_  (
    .A(\IP_counter.state [1]),
    .B(\IP_counter.Pulses [0]),
    .C(\IP_counter._25_ ),
    .D(\IP_counter._32_ ),
    .Y(IP_Ready)
  );
  DFFSR_n \IP_counter._82_  (
    .C(Clk),
    .D(\IP_counter.dek[1].DekNine ),
    .Q(\IP_counter.Nines [1]),
    .R(Rst_n),
    .S(1'h0)
  );
  DFFSR_n \IP_counter._83_  (
    .C(Clk),
    .D(\IP_counter.dek[1].DekZero ),
    .Q(\IP_counter.Zeroes [1]),
    .R(Rst_n),
    .S(1'h0)
  );
  DFFSR_n \IP_counter._84_  (
    .C(Clk),
    .D(\IP_counter.dek[2].DekNine ),
    .Q(\IP_counter.Nines [2]),
    .R(Rst_n),
    .S(1'h0)
  );
  DFFSR_n \IP_counter._85_  (
    .C(Clk),
    .D(\IP_counter.dek[2].DekZero ),
    .Q(\IP_counter.Zeroes [2]),
    .R(Rst_n),
    .S(1'h0)
  );
  DFFSR_n \IP_counter._86_  (
    .C(Clk),
    .D(\IP_counter.dek[0].DekZero ),
    .Q(\IP_counter.Zeroes [0]),
    .R(Rst_n),
    .S(1'h0)
  );
  DFFSR_n \IP_counter._87_  (
    .C(Clk),
    .D(\IP_counter.TopOut [3]),
    .Q(\IP_counter.Zeroes [3]),
    .R(Rst_n),
    .S(1'h0)
  );
  DFFSR_n \IP_counter._88_  (
    .C(Clk),
    .D(\IP_counter.next [0]),
    .Q(\IP_counter.state [0]),
    .R(Rst_n),
    .S(1'h0)
  );
  DFFSR_n \IP_counter._89_  (
    .C(Clk),
    .D(\IP_counter.next [1]),
    .Q(\IP_counter.state [1]),
    .R(Rst_n),
    .S(1'h0)
  );
  DFFSR_n \IP_counter._90_  (
    .C(Clk),
    .D(\IP_counter.next [2]),
    .Q(\IP_counter.state [2]),
    .R(Rst_n),
    .S(1'h0)
  );
  DFFSR_n \IP_counter._91_  (
    .C(Clk),
    .D(\IP_counter.dek[0].DekNine ),
    .Q(\IP_counter.Nines [0]),
    .R(Rst_n),
    .S(1'h0)
  );
  OR2_N16 \IP_counter.dek[0].dModule.Reading.binToDbc._2_  (
    .A(\IP_counter.TopOut [0]),
    .B(\IP_counter.dek[0].dModule.OutPos [7]),
    .Y(\IP_counter.dek[0].dModule.Reading.binToDbc._0_ )
  );
  OR4_N16X7 \IP_counter.dek[0].dModule.Reading.binToDbc._3_  (
    .A(\IP_counter.dek[0].dModule.OutPos [3]),
    .B(\IP_counter.dek[0].dModule.OutPos [1]),
    .C(\IP_counter.dek[0].DekNine ),
    .D(\IP_counter.dek[0].dModule.Reading.binToDbc._0_ ),
    .Y(IpAddress[0])
  );
  OR4_N16X7 \IP_counter.dek[0].dModule.Reading.binToDbc._4_  (
    .A(\IP_counter.dek[0].dModule.OutPos [3]),
    .B(\IP_counter.dek[0].dModule.OutPos [7]),
    .C(\IP_counter.dek[0].dModule.OutPos [2]),
    .D(\IP_counter.dek[0].dModule.OutPos [6]),
    .Y(IpAddress[1])
  );
  OR2_N16 \IP_counter.dek[0].dModule.Reading.binToDbc._5_  (
    .A(\IP_counter.dek[0].dModule.OutPos [6]),
    .B(\IP_counter.dek[0].dModule.OutPos [4]),
    .Y(\IP_counter.dek[0].dModule.Reading.binToDbc._1_ )
  );
  OR2_N16 \IP_counter.dek[0].dModule.Reading.binToDbc._6_  (
    .A(\IP_counter.dek[0].dModule.Reading.binToDbc._0_ ),
    .B(\IP_counter.dek[0].dModule.Reading.binToDbc._1_ ),
    .Y(IpAddress[2])
  );
  OR2_N16 \IP_counter.dek[0].dModule.Reading.binToDbc._7_  (
    .A(\IP_counter.dek[0].DekNine ),
    .B(\IP_counter.dek[0].dModule.OutPos [8]),
    .Y(IpAddress[3])
  );
  NOT_6N16B \IP_counter.dek[0].dModule._0_  (
    .A(\IP_counter.SetTopZero [0]),
    .Y(\IP_counter.dek[0].dModule.InPosDek_n )
  );
  Dekatron \IP_counter.dek[0].dModule.dekatron  (
    .In_n({ 9'h1ff, \IP_counter.dek[0].dModule.InPosDek_n  }),
    .Out({ \IP_counter.dek[0].DekNine , \IP_counter.dek[0].dModule.OutPos [8:6], \IP_counter.TopOut [0], \IP_counter.dek[0].dModule.OutPos [4:1], \IP_counter.dek[0].DekZero  }),
    .Pulses(\IP_counter.dek[0].dModule.Pulses ),
    .Rst_n(Rst_n),
    .hsClk(hsClk)
  );
  NOT_6N16B \IP_counter.dek[0].dModule.pulseSender._06_  (
    .A(\IP_counter.dek[0].dModule.pulseSender.OS_2 ),
    .Y(\IP_counter.dek[0].dModule.pulseSender._00_ )
  );
  NOT_6N16B \IP_counter.dek[0].dModule.pulseSender._07_  (
    .A(\IP_counter.dek[0].dModule.pulseSender.Dec ),
    .Y(\IP_counter.dek[0].dModule.pulseSender._01_ )
  );
  OR2_N16 \IP_counter.dek[0].dModule.pulseSender._08_  (
    .A(\IP_counter.dek[0].dModule.pulseSender._Pulses [1]),
    .B(\IP_counter.dek[0].dModule.pulseSender._Pulses [0]),
    .Y(\IP_counter.dek[0].dModule.pulseSender.PulseAny )
  );
  A1OOI_N16X7 \IP_counter.dek[0].dModule.pulseSender._09_  (
    .A(\IP_counter.dek[0].dModule.pulseSender.OS_3 ),
    .B(\IP_counter.dek[0].dModule.pulseSender._00_ ),
    .C(\IP_counter.dek[0].dModule.pulseSender.Dec ),
    .Y(\IP_counter.dek[0].dModule.pulseSender._02_ )
  );
  NOR2_N16 \IP_counter.dek[0].dModule.pulseSender._10_  (
    .A(\IP_counter.dek[0].dModule.pulseSender.pA ),
    .B(\IP_counter.dek[0].dModule.pulseSender._01_ ),
    .Y(\IP_counter.dek[0].dModule.pulseSender._03_ )
  );
  NOR2_N16 \IP_counter.dek[0].dModule.pulseSender._11_  (
    .A(\IP_counter.dek[0].dModule.pulseSender._02_ ),
    .B(\IP_counter.dek[0].dModule.pulseSender._03_ ),
    .Y(\IP_counter.dek[0].dModule.Pulses [1])
  );
  NOR2_N16 \IP_counter.dek[0].dModule.pulseSender._12_  (
    .A(\IP_counter.dek[0].dModule.pulseSender.pA ),
    .B(\IP_counter.dek[0].dModule.pulseSender.Dec ),
    .Y(\IP_counter.dek[0].dModule.pulseSender._04_ )
  );
  A1OOI_N16X7 \IP_counter.dek[0].dModule.pulseSender._13_  (
    .A(\IP_counter.dek[0].dModule.pulseSender.OS_3 ),
    .B(\IP_counter.dek[0].dModule.pulseSender._00_ ),
    .C(\IP_counter.dek[0].dModule.pulseSender._01_ ),
    .Y(\IP_counter.dek[0].dModule.pulseSender._05_ )
  );
  NOR2_N16 \IP_counter.dek[0].dModule.pulseSender._14_  (
    .A(\IP_counter.dek[0].dModule.pulseSender._04_ ),
    .B(\IP_counter.dek[0].dModule.pulseSender._05_ ),
    .Y(\IP_counter.dek[0].dModule.Pulses [0])
  );
  OneShot #(
    .DELAY(32'sd9)
  ) \IP_counter.dek[0].dModule.pulseSender.dir  (
    .Clk(hsClk),
    .En(\IP_counter.Pulses [1]),
    .Impulse(\IP_counter.dek[0].dModule.pulseSender.Dec ),
    .Rst_n(Rst_n)
  );
  OneShot #(
    .DELAY(32'sd4)
  ) \IP_counter.dek[0].dModule.pulseSender.os_1  (
    .Clk(hsClk),
    .En(\IP_counter.dek[0].dModule.pulseSender.PulseAny ),
    .Impulse(\IP_counter.dek[0].dModule.pulseSender.pA ),
    .Rst_n(Rst_n)
  );
  OneShot #(
    .DELAY(32'sd3)
  ) \IP_counter.dek[0].dModule.pulseSender.os_2  (
    .Clk(hsClk),
    .En(\IP_counter.dek[0].dModule.pulseSender.PulseAny ),
    .Impulse(\IP_counter.dek[0].dModule.pulseSender.OS_2 ),
    .Rst_n(Rst_n)
  );
  OneShot #(
    .DELAY(32'sd8)
  ) \IP_counter.dek[0].dModule.pulseSender.os_3  (
    .Clk(hsClk),
    .En(\IP_counter.dek[0].dModule.pulseSender.PulseAny ),
    .Impulse(\IP_counter.dek[0].dModule.pulseSender.OS_3 ),
    .Rst_n(Rst_n)
  );
  Impulse \IP_counter.dek[0].dModule.pulseSender.pulsesImpDec  (
    .Clk(hsClk),
    .En(\IP_counter.Pulses [1]),
    .Impulse(\IP_counter.dek[0].dModule.pulseSender._Pulses [1]),
    .Rst_n(Rst_n)
  );
  Impulse \IP_counter.dek[0].dModule.pulseSender.pulsesImpInc  (
    .Clk(hsClk),
    .En(\IP_counter.Pulses [0]),
    .Impulse(\IP_counter.dek[0].dModule.pulseSender._Pulses [0]),
    .Rst_n(Rst_n)
  );
  OR2_N16 \IP_counter.dek[1].dModule.Reading.binToDbc._2_  (
    .A(\IP_counter.TopOut [1]),
    .B(\IP_counter.dek[1].dModule.OutPos [7]),
    .Y(\IP_counter.dek[1].dModule.Reading.binToDbc._0_ )
  );
  OR4_N16X7 \IP_counter.dek[1].dModule.Reading.binToDbc._3_  (
    .A(\IP_counter.dek[1].dModule.OutPos [3]),
    .B(\IP_counter.dek[1].dModule.OutPos [1]),
    .C(\IP_counter.dek[1].DekNine ),
    .D(\IP_counter.dek[1].dModule.Reading.binToDbc._0_ ),
    .Y(IpAddress[4])
  );
  OR4_N16X7 \IP_counter.dek[1].dModule.Reading.binToDbc._4_  (
    .A(\IP_counter.dek[1].dModule.OutPos [3]),
    .B(\IP_counter.dek[1].dModule.OutPos [7]),
    .C(\IP_counter.dek[1].dModule.OutPos [2]),
    .D(\IP_counter.dek[1].dModule.OutPos [6]),
    .Y(IpAddress[5])
  );
  OR2_N16 \IP_counter.dek[1].dModule.Reading.binToDbc._5_  (
    .A(\IP_counter.dek[1].dModule.OutPos [6]),
    .B(\IP_counter.dek[1].dModule.OutPos [4]),
    .Y(\IP_counter.dek[1].dModule.Reading.binToDbc._1_ )
  );
  OR2_N16 \IP_counter.dek[1].dModule.Reading.binToDbc._6_  (
    .A(\IP_counter.dek[1].dModule.Reading.binToDbc._0_ ),
    .B(\IP_counter.dek[1].dModule.Reading.binToDbc._1_ ),
    .Y(IpAddress[6])
  );
  OR2_N16 \IP_counter.dek[1].dModule.Reading.binToDbc._7_  (
    .A(\IP_counter.dek[1].DekNine ),
    .B(\IP_counter.dek[1].dModule.OutPos [8]),
    .Y(IpAddress[7])
  );
  NOT_6N16B \IP_counter.dek[1].dModule._0_  (
    .A(\IP_counter.SetTopZero [0]),
    .Y(\IP_counter.dek[1].dModule.InPosDek_n )
  );
  Dekatron \IP_counter.dek[1].dModule.dekatron  (
    .In_n({ 9'h1ff, \IP_counter.dek[1].dModule.InPosDek_n  }),
    .Out({ \IP_counter.dek[1].DekNine , \IP_counter.dek[1].dModule.OutPos [8:6], \IP_counter.TopOut [1], \IP_counter.dek[1].dModule.OutPos [4:1], \IP_counter.dek[1].DekZero  }),
    .Pulses(\IP_counter.dek[1].dModule.Pulses ),
    .Rst_n(Rst_n),
    .hsClk(hsClk)
  );
  NOT_6N16B \IP_counter.dek[1].dModule.pulseSender._06_  (
    .A(\IP_counter.dek[1].dModule.pulseSender.OS_2 ),
    .Y(\IP_counter.dek[1].dModule.pulseSender._00_ )
  );
  NOT_6N16B \IP_counter.dek[1].dModule.pulseSender._07_  (
    .A(\IP_counter.dek[1].dModule.pulseSender.Dec ),
    .Y(\IP_counter.dek[1].dModule.pulseSender._01_ )
  );
  OR2_N16 \IP_counter.dek[1].dModule.pulseSender._08_  (
    .A(\IP_counter.dek[1].dModule.pulseSender._Pulses [1]),
    .B(\IP_counter.dek[1].dModule.pulseSender._Pulses [0]),
    .Y(\IP_counter.dek[1].dModule.pulseSender.PulseAny )
  );
  A1OOI_N16X7 \IP_counter.dek[1].dModule.pulseSender._09_  (
    .A(\IP_counter.dek[1].dModule.pulseSender.OS_3 ),
    .B(\IP_counter.dek[1].dModule.pulseSender._00_ ),
    .C(\IP_counter.dek[1].dModule.pulseSender.Dec ),
    .Y(\IP_counter.dek[1].dModule.pulseSender._02_ )
  );
  NOR2_N16 \IP_counter.dek[1].dModule.pulseSender._10_  (
    .A(\IP_counter.dek[1].dModule.pulseSender.pA ),
    .B(\IP_counter.dek[1].dModule.pulseSender._01_ ),
    .Y(\IP_counter.dek[1].dModule.pulseSender._03_ )
  );
  NOR2_N16 \IP_counter.dek[1].dModule.pulseSender._11_  (
    .A(\IP_counter.dek[1].dModule.pulseSender._02_ ),
    .B(\IP_counter.dek[1].dModule.pulseSender._03_ ),
    .Y(\IP_counter.dek[1].dModule.Pulses [1])
  );
  NOR2_N16 \IP_counter.dek[1].dModule.pulseSender._12_  (
    .A(\IP_counter.dek[1].dModule.pulseSender.pA ),
    .B(\IP_counter.dek[1].dModule.pulseSender.Dec ),
    .Y(\IP_counter.dek[1].dModule.pulseSender._04_ )
  );
  A1OOI_N16X7 \IP_counter.dek[1].dModule.pulseSender._13_  (
    .A(\IP_counter.dek[1].dModule.pulseSender.OS_3 ),
    .B(\IP_counter.dek[1].dModule.pulseSender._00_ ),
    .C(\IP_counter.dek[1].dModule.pulseSender._01_ ),
    .Y(\IP_counter.dek[1].dModule.pulseSender._05_ )
  );
  NOR2_N16 \IP_counter.dek[1].dModule.pulseSender._14_  (
    .A(\IP_counter.dek[1].dModule.pulseSender._04_ ),
    .B(\IP_counter.dek[1].dModule.pulseSender._05_ ),
    .Y(\IP_counter.dek[1].dModule.Pulses [0])
  );
  OneShot #(
    .DELAY(32'sd9)
  ) \IP_counter.dek[1].dModule.pulseSender.dir  (
    .Clk(hsClk),
    .En(\IP_counter.dek[0].npulses [1]),
    .Impulse(\IP_counter.dek[1].dModule.pulseSender.Dec ),
    .Rst_n(Rst_n)
  );
  OneShot #(
    .DELAY(32'sd4)
  ) \IP_counter.dek[1].dModule.pulseSender.os_1  (
    .Clk(hsClk),
    .En(\IP_counter.dek[1].dModule.pulseSender.PulseAny ),
    .Impulse(\IP_counter.dek[1].dModule.pulseSender.pA ),
    .Rst_n(Rst_n)
  );
  OneShot #(
    .DELAY(32'sd3)
  ) \IP_counter.dek[1].dModule.pulseSender.os_2  (
    .Clk(hsClk),
    .En(\IP_counter.dek[1].dModule.pulseSender.PulseAny ),
    .Impulse(\IP_counter.dek[1].dModule.pulseSender.OS_2 ),
    .Rst_n(Rst_n)
  );
  OneShot #(
    .DELAY(32'sd8)
  ) \IP_counter.dek[1].dModule.pulseSender.os_3  (
    .Clk(hsClk),
    .En(\IP_counter.dek[1].dModule.pulseSender.PulseAny ),
    .Impulse(\IP_counter.dek[1].dModule.pulseSender.OS_3 ),
    .Rst_n(Rst_n)
  );
  Impulse \IP_counter.dek[1].dModule.pulseSender.pulsesImpDec  (
    .Clk(hsClk),
    .En(\IP_counter.dek[0].npulses [1]),
    .Impulse(\IP_counter.dek[1].dModule.pulseSender._Pulses [1]),
    .Rst_n(Rst_n)
  );
  Impulse \IP_counter.dek[1].dModule.pulseSender.pulsesImpInc  (
    .Clk(hsClk),
    .En(\IP_counter.dek[0].npulses [0]),
    .Impulse(\IP_counter.dek[1].dModule.pulseSender._Pulses [0]),
    .Rst_n(Rst_n)
  );
  OR2_N16 \IP_counter.dek[2].dModule.Reading.binToDbc._2_  (
    .A(\IP_counter.TopOut [2]),
    .B(\IP_counter.dek[2].dModule.OutPos [7]),
    .Y(\IP_counter.dek[2].dModule.Reading.binToDbc._0_ )
  );
  OR4_N16X7 \IP_counter.dek[2].dModule.Reading.binToDbc._3_  (
    .A(\IP_counter.dek[2].dModule.OutPos [3]),
    .B(\IP_counter.dek[2].dModule.OutPos [1]),
    .C(\IP_counter.dek[2].DekNine ),
    .D(\IP_counter.dek[2].dModule.Reading.binToDbc._0_ ),
    .Y(IpAddress[8])
  );
  OR4_N16X7 \IP_counter.dek[2].dModule.Reading.binToDbc._4_  (
    .A(\IP_counter.dek[2].dModule.OutPos [3]),
    .B(\IP_counter.dek[2].dModule.OutPos [7]),
    .C(\IP_counter.dek[2].dModule.OutPos [2]),
    .D(\IP_counter.dek[2].dModule.OutPos [6]),
    .Y(IpAddress[9])
  );
  OR2_N16 \IP_counter.dek[2].dModule.Reading.binToDbc._5_  (
    .A(\IP_counter.dek[2].dModule.OutPos [6]),
    .B(\IP_counter.dek[2].dModule.OutPos [4]),
    .Y(\IP_counter.dek[2].dModule.Reading.binToDbc._1_ )
  );
  OR2_N16 \IP_counter.dek[2].dModule.Reading.binToDbc._6_  (
    .A(\IP_counter.dek[2].dModule.Reading.binToDbc._0_ ),
    .B(\IP_counter.dek[2].dModule.Reading.binToDbc._1_ ),
    .Y(IpAddress[10])
  );
  OR2_N16 \IP_counter.dek[2].dModule.Reading.binToDbc._7_  (
    .A(\IP_counter.dek[2].DekNine ),
    .B(\IP_counter.dek[2].dModule.OutPos [8]),
    .Y(IpAddress[11])
  );
  NOT_6N16B \IP_counter.dek[2].dModule._0_  (
    .A(\IP_counter.SetTopZero [0]),
    .Y(\IP_counter.dek[2].dModule.InPosDek_n )
  );
  Dekatron \IP_counter.dek[2].dModule.dekatron  (
    .In_n({ 9'h1ff, \IP_counter.dek[2].dModule.InPosDek_n  }),
    .Out({ \IP_counter.dek[2].DekNine , \IP_counter.dek[2].dModule.OutPos [8:6], \IP_counter.TopOut [2], \IP_counter.dek[2].dModule.OutPos [4:1], \IP_counter.dek[2].DekZero  }),
    .Pulses(\IP_counter.dek[2].dModule.Pulses ),
    .Rst_n(Rst_n),
    .hsClk(hsClk)
  );
  NOT_6N16B \IP_counter.dek[2].dModule.pulseSender._06_  (
    .A(\IP_counter.dek[2].dModule.pulseSender.OS_2 ),
    .Y(\IP_counter.dek[2].dModule.pulseSender._00_ )
  );
  NOT_6N16B \IP_counter.dek[2].dModule.pulseSender._07_  (
    .A(\IP_counter.dek[2].dModule.pulseSender.Dec ),
    .Y(\IP_counter.dek[2].dModule.pulseSender._01_ )
  );
  OR2_N16 \IP_counter.dek[2].dModule.pulseSender._08_  (
    .A(\IP_counter.dek[2].dModule.pulseSender._Pulses [1]),
    .B(\IP_counter.dek[2].dModule.pulseSender._Pulses [0]),
    .Y(\IP_counter.dek[2].dModule.pulseSender.PulseAny )
  );
  A1OOI_N16X7 \IP_counter.dek[2].dModule.pulseSender._09_  (
    .A(\IP_counter.dek[2].dModule.pulseSender.OS_3 ),
    .B(\IP_counter.dek[2].dModule.pulseSender._00_ ),
    .C(\IP_counter.dek[2].dModule.pulseSender.Dec ),
    .Y(\IP_counter.dek[2].dModule.pulseSender._02_ )
  );
  NOR2_N16 \IP_counter.dek[2].dModule.pulseSender._10_  (
    .A(\IP_counter.dek[2].dModule.pulseSender.pA ),
    .B(\IP_counter.dek[2].dModule.pulseSender._01_ ),
    .Y(\IP_counter.dek[2].dModule.pulseSender._03_ )
  );
  NOR2_N16 \IP_counter.dek[2].dModule.pulseSender._11_  (
    .A(\IP_counter.dek[2].dModule.pulseSender._02_ ),
    .B(\IP_counter.dek[2].dModule.pulseSender._03_ ),
    .Y(\IP_counter.dek[2].dModule.Pulses [1])
  );
  NOR2_N16 \IP_counter.dek[2].dModule.pulseSender._12_  (
    .A(\IP_counter.dek[2].dModule.pulseSender.pA ),
    .B(\IP_counter.dek[2].dModule.pulseSender.Dec ),
    .Y(\IP_counter.dek[2].dModule.pulseSender._04_ )
  );
  A1OOI_N16X7 \IP_counter.dek[2].dModule.pulseSender._13_  (
    .A(\IP_counter.dek[2].dModule.pulseSender.OS_3 ),
    .B(\IP_counter.dek[2].dModule.pulseSender._00_ ),
    .C(\IP_counter.dek[2].dModule.pulseSender._01_ ),
    .Y(\IP_counter.dek[2].dModule.pulseSender._05_ )
  );
  NOR2_N16 \IP_counter.dek[2].dModule.pulseSender._14_  (
    .A(\IP_counter.dek[2].dModule.pulseSender._04_ ),
    .B(\IP_counter.dek[2].dModule.pulseSender._05_ ),
    .Y(\IP_counter.dek[2].dModule.Pulses [0])
  );
  OneShot #(
    .DELAY(32'sd9)
  ) \IP_counter.dek[2].dModule.pulseSender.dir  (
    .Clk(hsClk),
    .En(\IP_counter.dek[1].npulses [1]),
    .Impulse(\IP_counter.dek[2].dModule.pulseSender.Dec ),
    .Rst_n(Rst_n)
  );
  OneShot #(
    .DELAY(32'sd4)
  ) \IP_counter.dek[2].dModule.pulseSender.os_1  (
    .Clk(hsClk),
    .En(\IP_counter.dek[2].dModule.pulseSender.PulseAny ),
    .Impulse(\IP_counter.dek[2].dModule.pulseSender.pA ),
    .Rst_n(Rst_n)
  );
  OneShot #(
    .DELAY(32'sd3)
  ) \IP_counter.dek[2].dModule.pulseSender.os_2  (
    .Clk(hsClk),
    .En(\IP_counter.dek[2].dModule.pulseSender.PulseAny ),
    .Impulse(\IP_counter.dek[2].dModule.pulseSender.OS_2 ),
    .Rst_n(Rst_n)
  );
  OneShot #(
    .DELAY(32'sd8)
  ) \IP_counter.dek[2].dModule.pulseSender.os_3  (
    .Clk(hsClk),
    .En(\IP_counter.dek[2].dModule.pulseSender.PulseAny ),
    .Impulse(\IP_counter.dek[2].dModule.pulseSender.OS_3 ),
    .Rst_n(Rst_n)
  );
  Impulse \IP_counter.dek[2].dModule.pulseSender.pulsesImpDec  (
    .Clk(hsClk),
    .En(\IP_counter.dek[1].npulses [1]),
    .Impulse(\IP_counter.dek[2].dModule.pulseSender._Pulses [1]),
    .Rst_n(Rst_n)
  );
  Impulse \IP_counter.dek[2].dModule.pulseSender.pulsesImpInc  (
    .Clk(hsClk),
    .En(\IP_counter.dek[1].npulses [0]),
    .Impulse(\IP_counter.dek[2].dModule.pulseSender._Pulses [0]),
    .Rst_n(Rst_n)
  );
  OR2_N16 \IP_counter.dek[3].dModule.Reading.binToDbc._2_  (
    .A(\IP_counter.dek[3].dModule.OutPos [5]),
    .B(\IP_counter.dek[3].dModule.OutPos [7]),
    .Y(\IP_counter.dek[3].dModule.Reading.binToDbc._0_ )
  );
  OR4_N16X7 \IP_counter.dek[3].dModule.Reading.binToDbc._3_  (
    .A(\IP_counter.dek[3].dModule.OutPos [3]),
    .B(\IP_counter.dek[3].dModule.OutPos [1]),
    .C(\IP_counter.dek[3].DekNine ),
    .D(\IP_counter.dek[3].dModule.Reading.binToDbc._0_ ),
    .Y(IpAddress[12])
  );
  OR4_N16X7 \IP_counter.dek[3].dModule.Reading.binToDbc._4_  (
    .A(\IP_counter.dek[3].dModule.OutPos [3]),
    .B(\IP_counter.dek[3].dModule.OutPos [7]),
    .C(\IP_counter.dek[3].dModule.OutPos [2]),
    .D(\IP_counter.dek[3].dModule.OutPos [6]),
    .Y(IpAddress[13])
  );
  OR2_N16 \IP_counter.dek[3].dModule.Reading.binToDbc._5_  (
    .A(\IP_counter.dek[3].dModule.OutPos [6]),
    .B(\IP_counter.dek[3].dModule.OutPos [4]),
    .Y(\IP_counter.dek[3].dModule.Reading.binToDbc._1_ )
  );
  OR2_N16 \IP_counter.dek[3].dModule.Reading.binToDbc._6_  (
    .A(\IP_counter.dek[3].dModule.Reading.binToDbc._0_ ),
    .B(\IP_counter.dek[3].dModule.Reading.binToDbc._1_ ),
    .Y(IpAddress[14])
  );
  OR2_N16 \IP_counter.dek[3].dModule.Reading.binToDbc._7_  (
    .A(\IP_counter.dek[3].DekNine ),
    .B(\IP_counter.dek[3].dModule.OutPos [8]),
    .Y(IpAddress[15])
  );
  NOT_6N16B \IP_counter.dek[3].dModule._0_  (
    .A(\IP_counter.SetTopZero [0]),
    .Y(\IP_counter.dek[3].dModule.InPosDek_n )
  );
  Dekatron \IP_counter.dek[3].dModule.dekatron  (
    .In_n({ 9'h1ff, \IP_counter.dek[3].dModule.InPosDek_n  }),
    .Out({ \IP_counter.dek[3].DekNine , \IP_counter.dek[3].dModule.OutPos [8:1], \IP_counter.TopOut [3] }),
    .Pulses(\IP_counter.dek[3].dModule.Pulses ),
    .Rst_n(Rst_n),
    .hsClk(hsClk)
  );
  NOT_6N16B \IP_counter.dek[3].dModule.pulseSender._06_  (
    .A(\IP_counter.dek[3].dModule.pulseSender.OS_2 ),
    .Y(\IP_counter.dek[3].dModule.pulseSender._00_ )
  );
  NOT_6N16B \IP_counter.dek[3].dModule.pulseSender._07_  (
    .A(\IP_counter.dek[3].dModule.pulseSender.Dec ),
    .Y(\IP_counter.dek[3].dModule.pulseSender._01_ )
  );
  OR2_N16 \IP_counter.dek[3].dModule.pulseSender._08_  (
    .A(\IP_counter.dek[3].dModule.pulseSender._Pulses [1]),
    .B(\IP_counter.dek[3].dModule.pulseSender._Pulses [0]),
    .Y(\IP_counter.dek[3].dModule.pulseSender.PulseAny )
  );
  A1OOI_N16X7 \IP_counter.dek[3].dModule.pulseSender._09_  (
    .A(\IP_counter.dek[3].dModule.pulseSender.OS_3 ),
    .B(\IP_counter.dek[3].dModule.pulseSender._00_ ),
    .C(\IP_counter.dek[3].dModule.pulseSender.Dec ),
    .Y(\IP_counter.dek[3].dModule.pulseSender._02_ )
  );
  NOR2_N16 \IP_counter.dek[3].dModule.pulseSender._10_  (
    .A(\IP_counter.dek[3].dModule.pulseSender.pA ),
    .B(\IP_counter.dek[3].dModule.pulseSender._01_ ),
    .Y(\IP_counter.dek[3].dModule.pulseSender._03_ )
  );
  NOR2_N16 \IP_counter.dek[3].dModule.pulseSender._11_  (
    .A(\IP_counter.dek[3].dModule.pulseSender._02_ ),
    .B(\IP_counter.dek[3].dModule.pulseSender._03_ ),
    .Y(\IP_counter.dek[3].dModule.Pulses [1])
  );
  NOR2_N16 \IP_counter.dek[3].dModule.pulseSender._12_  (
    .A(\IP_counter.dek[3].dModule.pulseSender.pA ),
    .B(\IP_counter.dek[3].dModule.pulseSender.Dec ),
    .Y(\IP_counter.dek[3].dModule.pulseSender._04_ )
  );
  A1OOI_N16X7 \IP_counter.dek[3].dModule.pulseSender._13_  (
    .A(\IP_counter.dek[3].dModule.pulseSender.OS_3 ),
    .B(\IP_counter.dek[3].dModule.pulseSender._00_ ),
    .C(\IP_counter.dek[3].dModule.pulseSender._01_ ),
    .Y(\IP_counter.dek[3].dModule.pulseSender._05_ )
  );
  NOR2_N16 \IP_counter.dek[3].dModule.pulseSender._14_  (
    .A(\IP_counter.dek[3].dModule.pulseSender._04_ ),
    .B(\IP_counter.dek[3].dModule.pulseSender._05_ ),
    .Y(\IP_counter.dek[3].dModule.Pulses [0])
  );
  OneShot #(
    .DELAY(32'sd9)
  ) \IP_counter.dek[3].dModule.pulseSender.dir  (
    .Clk(hsClk),
    .En(\IP_counter.dek[2].npulses [1]),
    .Impulse(\IP_counter.dek[3].dModule.pulseSender.Dec ),
    .Rst_n(Rst_n)
  );
  OneShot #(
    .DELAY(32'sd4)
  ) \IP_counter.dek[3].dModule.pulseSender.os_1  (
    .Clk(hsClk),
    .En(\IP_counter.dek[3].dModule.pulseSender.PulseAny ),
    .Impulse(\IP_counter.dek[3].dModule.pulseSender.pA ),
    .Rst_n(Rst_n)
  );
  OneShot #(
    .DELAY(32'sd3)
  ) \IP_counter.dek[3].dModule.pulseSender.os_2  (
    .Clk(hsClk),
    .En(\IP_counter.dek[3].dModule.pulseSender.PulseAny ),
    .Impulse(\IP_counter.dek[3].dModule.pulseSender.OS_2 ),
    .Rst_n(Rst_n)
  );
  OneShot #(
    .DELAY(32'sd8)
  ) \IP_counter.dek[3].dModule.pulseSender.os_3  (
    .Clk(hsClk),
    .En(\IP_counter.dek[3].dModule.pulseSender.PulseAny ),
    .Impulse(\IP_counter.dek[3].dModule.pulseSender.OS_3 ),
    .Rst_n(Rst_n)
  );
  Impulse \IP_counter.dek[3].dModule.pulseSender.pulsesImpDec  (
    .Clk(hsClk),
    .En(\IP_counter.dek[2].npulses [1]),
    .Impulse(\IP_counter.dek[3].dModule.pulseSender._Pulses [1]),
    .Rst_n(Rst_n)
  );
  Impulse \IP_counter.dek[3].dModule.pulseSender.pulsesImpInc  (
    .Clk(hsClk),
    .En(\IP_counter.dek[2].npulses [0]),
    .Impulse(\IP_counter.dek[3].dModule.pulseSender._Pulses [0]),
    .Rst_n(Rst_n)
  );
  Impulse \IP_counter.pulsesImpDec  (
    .Clk(Clk),
    .En(\IP_counter.PulseR ),
    .Impulse(\IP_counter.Pulses [1]),
    .Rst_n(Rst_n)
  );
  Impulse \IP_counter.pulsesImpInc  (
    .Clk(Clk),
    .En(\IP_counter.PulseF ),
    .Impulse(\IP_counter.Pulses [0]),
    .Rst_n(Rst_n)
  );
  Impulse \IP_counter.reqPulse  (
    .Clk(Clk),
    .En(IP_Request),
    .Impulse(\IP_counter._Request ),
    .Rst_n(Rst_n)
  );
  OneShot #(
    .DELAY(32'sd100)
  ) \IP_counter.writeOneShot  (
    .Clk(hsClk),
    .En(\IP_counter.write_set ),
    .Impulse(\IP_counter.writed_n ),
    .Rst_n(Rst_n)
  );
  Impulse \IP_counter.writeimpulse  (
    .Clk(Clk),
    .En(\IP_counter.state [2]),
    .Impulse(\IP_counter.write_set ),
    .Rst_n(Rst_n)
  );
  NOT_6N16B \Loop_counter._26_  (
    .A(\Loop_counter.state [2]),
    .Y(\Loop_counter._00_ )
  );
  NOT_6N16B \Loop_counter._27_  (
    .A(\Loop_counter.state [0]),
    .Y(\Loop_counter._01_ )
  );
  NOT_6N16B \Loop_counter._28_  (
    .A(\Loop_counter.Pulses [0]),
    .Y(\Loop_counter._02_ )
  );
  NOT_6N16B \Loop_counter._29_  (
    .A(\Loop_counter.Pulses [1]),
    .Y(\Loop_counter._03_ )
  );
  NOT_6N16B \Loop_counter._30_  (
    .A(\Loop_counter.Zeroes [1]),
    .Y(\Loop_counter._04_ )
  );
  NOT_6N16B \Loop_counter._31_  (
    .A(\Loop_counter._Request ),
    .Y(\Loop_counter._05_ )
  );
  NOT_6N16B \Loop_counter._32_  (
    .A(1'h0),
    .Y(\Loop_counter._06_ )
  );
  NAND2_J2 \Loop_counter._33_  (
    .A(\Loop_counter.Zeroes [2]),
    .B(\Loop_counter.Zeroes [0]),
    .Y(\Loop_counter._07_ )
  );
  NOR2_N16 \Loop_counter._34_  (
    .A(\Loop_counter._04_ ),
    .B(\Loop_counter._07_ ),
    .Y(Loop_Zero)
  );
  AND2_N16X7 \Loop_counter._35_  (
    .A(\Loop_counter.state [2]),
    .B(\Loop_counter.writed_n ),
    .Y(\Loop_counter._08_ )
  );
  AND2_N16X7 \Loop_counter._36_  (
    .A(\Loop_counter.state [0]),
    .B(\Loop_counter._08_ ),
    .Y(\Loop_counter._09_ )
  );
  NAND2_J2 \Loop_counter._37_  (
    .A(\Loop_counter.state [0]),
    .B(\Loop_counter._08_ ),
    .Y(\Loop_counter._10_ )
  );
  NOR2_N16 \Loop_counter._38_  (
    .A(\Loop_counter.state [1]),
    .B(\Loop_counter._10_ ),
    .Y(\Loop_counter.SetTopZero [0])
  );
  NAND2_J2 \Loop_counter._39_  (
    .A(\Loop_counter.state [1]),
    .B(\Loop_counter._08_ ),
    .Y(\Loop_counter._11_ )
  );
  NOR2_N16 \Loop_counter._40_  (
    .A(\Loop_counter.state [0]),
    .B(\Loop_counter._11_ ),
    .Y(\Loop_counter.SetTopZero [1])
  );
  NOR2_N16 \Loop_counter._41_  (
    .A(\Loop_counter._01_ ),
    .B(\Loop_counter._11_ ),
    .Y(\Loop_counter.SetTopZero [2])
  );
  NAND2_J2 \Loop_counter._42_  (
    .A(\Loop_counter._00_ ),
    .B(\Loop_counter.state [1]),
    .Y(\Loop_counter._12_ )
  );
  NOR2_N16 \Loop_counter._43_  (
    .A(\Loop_counter.state [0]),
    .B(\Loop_counter._12_ ),
    .Y(\Loop_counter.PulseF )
  );
  NAND4_N16X7 \Loop_counter._44_  (
    .A(\Loop_counter._00_ ),
    .B(\Loop_counter.state [1]),
    .C(\Loop_counter._01_ ),
    .D(\Loop_counter.Nines [0]),
    .Y(\Loop_counter._13_ )
  );
  NOR2_N16 \Loop_counter._45_  (
    .A(\Loop_counter._01_ ),
    .B(\Loop_counter._12_ ),
    .Y(\Loop_counter.PulseR )
  );
  NAND4_N16X7 \Loop_counter._46_  (
    .A(\Loop_counter._00_ ),
    .B(\Loop_counter.state [1]),
    .C(\Loop_counter.state [0]),
    .D(\Loop_counter.Zeroes [0]),
    .Y(\Loop_counter._14_ )
  );
  A1OOI_N16X7 \Loop_counter._47_  (
    .A(\Loop_counter._13_ ),
    .B(\Loop_counter._14_ ),
    .C(\Loop_counter._02_ ),
    .Y(\Loop_counter.dek[0].npulses [0])
  );
  A1OOI_N16X7 \Loop_counter._48_  (
    .A(\Loop_counter._13_ ),
    .B(\Loop_counter._14_ ),
    .C(\Loop_counter._03_ ),
    .Y(\Loop_counter.dek[0].npulses [1])
  );
  NAND4_N16X7 \Loop_counter._49_  (
    .A(\Loop_counter._00_ ),
    .B(\Loop_counter.state [1]),
    .C(\Loop_counter._01_ ),
    .D(\Loop_counter.Nines [1]),
    .Y(\Loop_counter._15_ )
  );
  NAND4_N16X7 \Loop_counter._50_  (
    .A(\Loop_counter._00_ ),
    .B(\Loop_counter.state [1]),
    .C(\Loop_counter.state [0]),
    .D(\Loop_counter.Zeroes [1]),
    .Y(\Loop_counter._16_ )
  );
  NAND2_J2 \Loop_counter._51_  (
    .A(\Loop_counter._15_ ),
    .B(\Loop_counter._16_ ),
    .Y(\Loop_counter._17_ )
  );
  AND2_N16X7 \Loop_counter._52_  (
    .A(\Loop_counter.dek[0].npulses [0]),
    .B(\Loop_counter._17_ ),
    .Y(\Loop_counter.dek[1].npulses [0])
  );
  AND2_N16X7 \Loop_counter._53_  (
    .A(\Loop_counter.dek[0].npulses [1]),
    .B(\Loop_counter._17_ ),
    .Y(\Loop_counter.dek[1].npulses [1])
  );
  OR2_N16 \Loop_counter._54_  (
    .A(\Loop_counter.state [2]),
    .B(\Loop_counter.state [0]),
    .Y(\Loop_counter._18_ )
  );
  NOR4_N16 \Loop_counter._55_  (
    .A(\Loop_counter.state [2]),
    .B(\Loop_counter.state [1]),
    .C(\Loop_counter.state [0]),
    .D(\Loop_counter._05_ ),
    .Y(\Loop_counter._19_ )
  );
  NAND2_J2 \Loop_counter._56_  (
    .A(Loop_Dec),
    .B(\Loop_counter._19_ ),
    .Y(\Loop_counter._20_ )
  );
  OR2_N16 \Loop_counter._57_  (
    .A(1'h0),
    .B(1'h0),
    .Y(\Loop_counter._21_ )
  );
  A1OOI_N16X7 \Loop_counter._58_  (
    .A(\Loop_counter._19_ ),
    .B(\Loop_counter._21_ ),
    .C(\Loop_counter._09_ ),
    .Y(\Loop_counter._22_ )
  );
  NAND2_J2 \Loop_counter._59_  (
    .A(\Loop_counter._20_ ),
    .B(\Loop_counter._22_ ),
    .Y(\Loop_counter.next [0])
  );
  NAND2_J2 \Loop_counter._60_  (
    .A(\Loop_counter._06_ ),
    .B(1'h0),
    .Y(\Loop_counter._23_ )
  );
  NAND2_J2 \Loop_counter._61_  (
    .A(\Loop_counter._19_ ),
    .B(\Loop_counter._23_ ),
    .Y(\Loop_counter._24_ )
  );
  NAND2_J2 \Loop_counter._62_  (
    .A(\Loop_counter._11_ ),
    .B(\Loop_counter._24_ ),
    .Y(\Loop_counter.next [1])
  );
  NAND2_J2 \Loop_counter._63_  (
    .A(\Loop_counter._11_ ),
    .B(\Loop_counter._22_ ),
    .Y(\Loop_counter.next [2])
  );
  OR2_N16 \Loop_counter._64_  (
    .A(\Loop_counter.Pulses [1]),
    .B(Loop_Request),
    .Y(\Loop_counter._25_ )
  );
  NOR4_N16 \Loop_counter._65_  (
    .A(\Loop_counter.state [1]),
    .B(\Loop_counter.Pulses [0]),
    .C(\Loop_counter._18_ ),
    .D(\Loop_counter._25_ ),
    .Y(Loop_Ready)
  );
  DFFSR_n \Loop_counter._66_  (
    .C(Clk),
    .D(\Loop_counter.dek[1].DekZero ),
    .Q(\Loop_counter.Zeroes [1]),
    .R(Rst_n),
    .S(1'h0)
  );
  DFFSR_n \Loop_counter._67_  (
    .C(Clk),
    .D(\Loop_counter.dek[2].DekZero ),
    .Q(\Loop_counter.Zeroes [2]),
    .R(Rst_n),
    .S(1'h0)
  );
  DFFSR_n \Loop_counter._68_  (
    .C(Clk),
    .D(\Loop_counter.next [0]),
    .Q(\Loop_counter.state [0]),
    .R(Rst_n),
    .S(1'h0)
  );
  DFFSR_n \Loop_counter._69_  (
    .C(Clk),
    .D(\Loop_counter.next [1]),
    .Q(\Loop_counter.state [1]),
    .R(Rst_n),
    .S(1'h0)
  );
  DFFSR_n \Loop_counter._70_  (
    .C(Clk),
    .D(\Loop_counter.next [2]),
    .Q(\Loop_counter.state [2]),
    .R(Rst_n),
    .S(1'h0)
  );
  DFFSR_n \Loop_counter._71_  (
    .C(Clk),
    .D(\Loop_counter.dek[0].DekNine ),
    .Q(\Loop_counter.Nines [0]),
    .R(Rst_n),
    .S(1'h0)
  );
  DFFSR_n \Loop_counter._72_  (
    .C(Clk),
    .D(\Loop_counter.dek[0].DekZero ),
    .Q(\Loop_counter.Zeroes [0]),
    .R(Rst_n),
    .S(1'h0)
  );
  DFFSR_n \Loop_counter._73_  (
    .C(Clk),
    .D(\Loop_counter.dek[1].DekNine ),
    .Q(\Loop_counter.Nines [1]),
    .R(Rst_n),
    .S(1'h0)
  );
  NOT_6N16B \Loop_counter.dek[0].dModule._0_  (
    .A(\Loop_counter.SetTopZero [0]),
    .Y(\Loop_counter.dek[0].dModule.InPosDek_n )
  );
  Dekatron \Loop_counter.dek[0].dModule.dekatron  (
    .In_n({ 9'h1ff, \Loop_counter.dek[0].dModule.InPosDek_n  }),
    .Out({ \Loop_counter.dek[0].DekNine , \Loop_counter.dek[0].dModule.OutPos [8:6], \Loop_counter.TopOut [0], \Loop_counter.dek[0].dModule.OutPos [4:1], \Loop_counter.dek[0].DekZero  }),
    .Pulses(\Loop_counter.dek[0].dModule.Pulses ),
    .Rst_n(Rst_n),
    .hsClk(hsClk)
  );
  NOT_6N16B \Loop_counter.dek[0].dModule.pulseSender._06_  (
    .A(\Loop_counter.dek[0].dModule.pulseSender.OS_2 ),
    .Y(\Loop_counter.dek[0].dModule.pulseSender._00_ )
  );
  NOT_6N16B \Loop_counter.dek[0].dModule.pulseSender._07_  (
    .A(\Loop_counter.dek[0].dModule.pulseSender.Dec ),
    .Y(\Loop_counter.dek[0].dModule.pulseSender._01_ )
  );
  OR2_N16 \Loop_counter.dek[0].dModule.pulseSender._08_  (
    .A(\Loop_counter.dek[0].dModule.pulseSender._Pulses [1]),
    .B(\Loop_counter.dek[0].dModule.pulseSender._Pulses [0]),
    .Y(\Loop_counter.dek[0].dModule.pulseSender.PulseAny )
  );
  A1OOI_N16X7 \Loop_counter.dek[0].dModule.pulseSender._09_  (
    .A(\Loop_counter.dek[0].dModule.pulseSender.OS_3 ),
    .B(\Loop_counter.dek[0].dModule.pulseSender._00_ ),
    .C(\Loop_counter.dek[0].dModule.pulseSender.Dec ),
    .Y(\Loop_counter.dek[0].dModule.pulseSender._02_ )
  );
  NOR2_N16 \Loop_counter.dek[0].dModule.pulseSender._10_  (
    .A(\Loop_counter.dek[0].dModule.pulseSender.pA ),
    .B(\Loop_counter.dek[0].dModule.pulseSender._01_ ),
    .Y(\Loop_counter.dek[0].dModule.pulseSender._03_ )
  );
  NOR2_N16 \Loop_counter.dek[0].dModule.pulseSender._11_  (
    .A(\Loop_counter.dek[0].dModule.pulseSender._02_ ),
    .B(\Loop_counter.dek[0].dModule.pulseSender._03_ ),
    .Y(\Loop_counter.dek[0].dModule.Pulses [1])
  );
  NOR2_N16 \Loop_counter.dek[0].dModule.pulseSender._12_  (
    .A(\Loop_counter.dek[0].dModule.pulseSender.pA ),
    .B(\Loop_counter.dek[0].dModule.pulseSender.Dec ),
    .Y(\Loop_counter.dek[0].dModule.pulseSender._04_ )
  );
  A1OOI_N16X7 \Loop_counter.dek[0].dModule.pulseSender._13_  (
    .A(\Loop_counter.dek[0].dModule.pulseSender.OS_3 ),
    .B(\Loop_counter.dek[0].dModule.pulseSender._00_ ),
    .C(\Loop_counter.dek[0].dModule.pulseSender._01_ ),
    .Y(\Loop_counter.dek[0].dModule.pulseSender._05_ )
  );
  NOR2_N16 \Loop_counter.dek[0].dModule.pulseSender._14_  (
    .A(\Loop_counter.dek[0].dModule.pulseSender._04_ ),
    .B(\Loop_counter.dek[0].dModule.pulseSender._05_ ),
    .Y(\Loop_counter.dek[0].dModule.Pulses [0])
  );
  OneShot #(
    .DELAY(32'sd9)
  ) \Loop_counter.dek[0].dModule.pulseSender.dir  (
    .Clk(hsClk),
    .En(\Loop_counter.Pulses [1]),
    .Impulse(\Loop_counter.dek[0].dModule.pulseSender.Dec ),
    .Rst_n(Rst_n)
  );
  OneShot #(
    .DELAY(32'sd4)
  ) \Loop_counter.dek[0].dModule.pulseSender.os_1  (
    .Clk(hsClk),
    .En(\Loop_counter.dek[0].dModule.pulseSender.PulseAny ),
    .Impulse(\Loop_counter.dek[0].dModule.pulseSender.pA ),
    .Rst_n(Rst_n)
  );
  OneShot #(
    .DELAY(32'sd3)
  ) \Loop_counter.dek[0].dModule.pulseSender.os_2  (
    .Clk(hsClk),
    .En(\Loop_counter.dek[0].dModule.pulseSender.PulseAny ),
    .Impulse(\Loop_counter.dek[0].dModule.pulseSender.OS_2 ),
    .Rst_n(Rst_n)
  );
  OneShot #(
    .DELAY(32'sd8)
  ) \Loop_counter.dek[0].dModule.pulseSender.os_3  (
    .Clk(hsClk),
    .En(\Loop_counter.dek[0].dModule.pulseSender.PulseAny ),
    .Impulse(\Loop_counter.dek[0].dModule.pulseSender.OS_3 ),
    .Rst_n(Rst_n)
  );
  Impulse \Loop_counter.dek[0].dModule.pulseSender.pulsesImpDec  (
    .Clk(hsClk),
    .En(\Loop_counter.Pulses [1]),
    .Impulse(\Loop_counter.dek[0].dModule.pulseSender._Pulses [1]),
    .Rst_n(Rst_n)
  );
  Impulse \Loop_counter.dek[0].dModule.pulseSender.pulsesImpInc  (
    .Clk(hsClk),
    .En(\Loop_counter.Pulses [0]),
    .Impulse(\Loop_counter.dek[0].dModule.pulseSender._Pulses [0]),
    .Rst_n(Rst_n)
  );
  NOT_6N16B \Loop_counter.dek[1].dModule._0_  (
    .A(\Loop_counter.SetTopZero [0]),
    .Y(\Loop_counter.dek[1].dModule.InPosDek_n )
  );
  Dekatron \Loop_counter.dek[1].dModule.dekatron  (
    .In_n({ 9'h1ff, \Loop_counter.dek[1].dModule.InPosDek_n  }),
    .Out({ \Loop_counter.dek[1].DekNine , \Loop_counter.dek[1].dModule.OutPos [8:6], \Loop_counter.TopOut [1], \Loop_counter.dek[1].dModule.OutPos [4:1], \Loop_counter.dek[1].DekZero  }),
    .Pulses(\Loop_counter.dek[1].dModule.Pulses ),
    .Rst_n(Rst_n),
    .hsClk(hsClk)
  );
  NOT_6N16B \Loop_counter.dek[1].dModule.pulseSender._06_  (
    .A(\Loop_counter.dek[1].dModule.pulseSender.OS_2 ),
    .Y(\Loop_counter.dek[1].dModule.pulseSender._00_ )
  );
  NOT_6N16B \Loop_counter.dek[1].dModule.pulseSender._07_  (
    .A(\Loop_counter.dek[1].dModule.pulseSender.Dec ),
    .Y(\Loop_counter.dek[1].dModule.pulseSender._01_ )
  );
  OR2_N16 \Loop_counter.dek[1].dModule.pulseSender._08_  (
    .A(\Loop_counter.dek[1].dModule.pulseSender._Pulses [1]),
    .B(\Loop_counter.dek[1].dModule.pulseSender._Pulses [0]),
    .Y(\Loop_counter.dek[1].dModule.pulseSender.PulseAny )
  );
  A1OOI_N16X7 \Loop_counter.dek[1].dModule.pulseSender._09_  (
    .A(\Loop_counter.dek[1].dModule.pulseSender.OS_3 ),
    .B(\Loop_counter.dek[1].dModule.pulseSender._00_ ),
    .C(\Loop_counter.dek[1].dModule.pulseSender.Dec ),
    .Y(\Loop_counter.dek[1].dModule.pulseSender._02_ )
  );
  NOR2_N16 \Loop_counter.dek[1].dModule.pulseSender._10_  (
    .A(\Loop_counter.dek[1].dModule.pulseSender.pA ),
    .B(\Loop_counter.dek[1].dModule.pulseSender._01_ ),
    .Y(\Loop_counter.dek[1].dModule.pulseSender._03_ )
  );
  NOR2_N16 \Loop_counter.dek[1].dModule.pulseSender._11_  (
    .A(\Loop_counter.dek[1].dModule.pulseSender._02_ ),
    .B(\Loop_counter.dek[1].dModule.pulseSender._03_ ),
    .Y(\Loop_counter.dek[1].dModule.Pulses [1])
  );
  NOR2_N16 \Loop_counter.dek[1].dModule.pulseSender._12_  (
    .A(\Loop_counter.dek[1].dModule.pulseSender.pA ),
    .B(\Loop_counter.dek[1].dModule.pulseSender.Dec ),
    .Y(\Loop_counter.dek[1].dModule.pulseSender._04_ )
  );
  A1OOI_N16X7 \Loop_counter.dek[1].dModule.pulseSender._13_  (
    .A(\Loop_counter.dek[1].dModule.pulseSender.OS_3 ),
    .B(\Loop_counter.dek[1].dModule.pulseSender._00_ ),
    .C(\Loop_counter.dek[1].dModule.pulseSender._01_ ),
    .Y(\Loop_counter.dek[1].dModule.pulseSender._05_ )
  );
  NOR2_N16 \Loop_counter.dek[1].dModule.pulseSender._14_  (
    .A(\Loop_counter.dek[1].dModule.pulseSender._04_ ),
    .B(\Loop_counter.dek[1].dModule.pulseSender._05_ ),
    .Y(\Loop_counter.dek[1].dModule.Pulses [0])
  );
  OneShot #(
    .DELAY(32'sd9)
  ) \Loop_counter.dek[1].dModule.pulseSender.dir  (
    .Clk(hsClk),
    .En(\Loop_counter.dek[0].npulses [1]),
    .Impulse(\Loop_counter.dek[1].dModule.pulseSender.Dec ),
    .Rst_n(Rst_n)
  );
  OneShot #(
    .DELAY(32'sd4)
  ) \Loop_counter.dek[1].dModule.pulseSender.os_1  (
    .Clk(hsClk),
    .En(\Loop_counter.dek[1].dModule.pulseSender.PulseAny ),
    .Impulse(\Loop_counter.dek[1].dModule.pulseSender.pA ),
    .Rst_n(Rst_n)
  );
  OneShot #(
    .DELAY(32'sd3)
  ) \Loop_counter.dek[1].dModule.pulseSender.os_2  (
    .Clk(hsClk),
    .En(\Loop_counter.dek[1].dModule.pulseSender.PulseAny ),
    .Impulse(\Loop_counter.dek[1].dModule.pulseSender.OS_2 ),
    .Rst_n(Rst_n)
  );
  OneShot #(
    .DELAY(32'sd8)
  ) \Loop_counter.dek[1].dModule.pulseSender.os_3  (
    .Clk(hsClk),
    .En(\Loop_counter.dek[1].dModule.pulseSender.PulseAny ),
    .Impulse(\Loop_counter.dek[1].dModule.pulseSender.OS_3 ),
    .Rst_n(Rst_n)
  );
  Impulse \Loop_counter.dek[1].dModule.pulseSender.pulsesImpDec  (
    .Clk(hsClk),
    .En(\Loop_counter.dek[0].npulses [1]),
    .Impulse(\Loop_counter.dek[1].dModule.pulseSender._Pulses [1]),
    .Rst_n(Rst_n)
  );
  Impulse \Loop_counter.dek[1].dModule.pulseSender.pulsesImpInc  (
    .Clk(hsClk),
    .En(\Loop_counter.dek[0].npulses [0]),
    .Impulse(\Loop_counter.dek[1].dModule.pulseSender._Pulses [0]),
    .Rst_n(Rst_n)
  );
  NOT_6N16B \Loop_counter.dek[2].dModule._0_  (
    .A(\Loop_counter.SetTopZero [0]),
    .Y(\Loop_counter.dek[2].dModule.InPosDek_n )
  );
  Dekatron \Loop_counter.dek[2].dModule.dekatron  (
    .In_n({ 9'h1ff, \Loop_counter.dek[2].dModule.InPosDek_n  }),
    .Out({ \Loop_counter.dek[2].DekNine , \Loop_counter.dek[2].dModule.OutPos [8:6], \Loop_counter.TopOut [2], \Loop_counter.dek[2].dModule.OutPos [4:1], \Loop_counter.dek[2].DekZero  }),
    .Pulses(\Loop_counter.dek[2].dModule.Pulses ),
    .Rst_n(Rst_n),
    .hsClk(hsClk)
  );
  NOT_6N16B \Loop_counter.dek[2].dModule.pulseSender._06_  (
    .A(\Loop_counter.dek[2].dModule.pulseSender.OS_2 ),
    .Y(\Loop_counter.dek[2].dModule.pulseSender._00_ )
  );
  NOT_6N16B \Loop_counter.dek[2].dModule.pulseSender._07_  (
    .A(\Loop_counter.dek[2].dModule.pulseSender.Dec ),
    .Y(\Loop_counter.dek[2].dModule.pulseSender._01_ )
  );
  OR2_N16 \Loop_counter.dek[2].dModule.pulseSender._08_  (
    .A(\Loop_counter.dek[2].dModule.pulseSender._Pulses [1]),
    .B(\Loop_counter.dek[2].dModule.pulseSender._Pulses [0]),
    .Y(\Loop_counter.dek[2].dModule.pulseSender.PulseAny )
  );
  A1OOI_N16X7 \Loop_counter.dek[2].dModule.pulseSender._09_  (
    .A(\Loop_counter.dek[2].dModule.pulseSender.OS_3 ),
    .B(\Loop_counter.dek[2].dModule.pulseSender._00_ ),
    .C(\Loop_counter.dek[2].dModule.pulseSender.Dec ),
    .Y(\Loop_counter.dek[2].dModule.pulseSender._02_ )
  );
  NOR2_N16 \Loop_counter.dek[2].dModule.pulseSender._10_  (
    .A(\Loop_counter.dek[2].dModule.pulseSender.pA ),
    .B(\Loop_counter.dek[2].dModule.pulseSender._01_ ),
    .Y(\Loop_counter.dek[2].dModule.pulseSender._03_ )
  );
  NOR2_N16 \Loop_counter.dek[2].dModule.pulseSender._11_  (
    .A(\Loop_counter.dek[2].dModule.pulseSender._02_ ),
    .B(\Loop_counter.dek[2].dModule.pulseSender._03_ ),
    .Y(\Loop_counter.dek[2].dModule.Pulses [1])
  );
  NOR2_N16 \Loop_counter.dek[2].dModule.pulseSender._12_  (
    .A(\Loop_counter.dek[2].dModule.pulseSender.pA ),
    .B(\Loop_counter.dek[2].dModule.pulseSender.Dec ),
    .Y(\Loop_counter.dek[2].dModule.pulseSender._04_ )
  );
  A1OOI_N16X7 \Loop_counter.dek[2].dModule.pulseSender._13_  (
    .A(\Loop_counter.dek[2].dModule.pulseSender.OS_3 ),
    .B(\Loop_counter.dek[2].dModule.pulseSender._00_ ),
    .C(\Loop_counter.dek[2].dModule.pulseSender._01_ ),
    .Y(\Loop_counter.dek[2].dModule.pulseSender._05_ )
  );
  NOR2_N16 \Loop_counter.dek[2].dModule.pulseSender._14_  (
    .A(\Loop_counter.dek[2].dModule.pulseSender._04_ ),
    .B(\Loop_counter.dek[2].dModule.pulseSender._05_ ),
    .Y(\Loop_counter.dek[2].dModule.Pulses [0])
  );
  OneShot #(
    .DELAY(32'sd9)
  ) \Loop_counter.dek[2].dModule.pulseSender.dir  (
    .Clk(hsClk),
    .En(\Loop_counter.dek[1].npulses [1]),
    .Impulse(\Loop_counter.dek[2].dModule.pulseSender.Dec ),
    .Rst_n(Rst_n)
  );
  OneShot #(
    .DELAY(32'sd4)
  ) \Loop_counter.dek[2].dModule.pulseSender.os_1  (
    .Clk(hsClk),
    .En(\Loop_counter.dek[2].dModule.pulseSender.PulseAny ),
    .Impulse(\Loop_counter.dek[2].dModule.pulseSender.pA ),
    .Rst_n(Rst_n)
  );
  OneShot #(
    .DELAY(32'sd3)
  ) \Loop_counter.dek[2].dModule.pulseSender.os_2  (
    .Clk(hsClk),
    .En(\Loop_counter.dek[2].dModule.pulseSender.PulseAny ),
    .Impulse(\Loop_counter.dek[2].dModule.pulseSender.OS_2 ),
    .Rst_n(Rst_n)
  );
  OneShot #(
    .DELAY(32'sd8)
  ) \Loop_counter.dek[2].dModule.pulseSender.os_3  (
    .Clk(hsClk),
    .En(\Loop_counter.dek[2].dModule.pulseSender.PulseAny ),
    .Impulse(\Loop_counter.dek[2].dModule.pulseSender.OS_3 ),
    .Rst_n(Rst_n)
  );
  Impulse \Loop_counter.dek[2].dModule.pulseSender.pulsesImpDec  (
    .Clk(hsClk),
    .En(\Loop_counter.dek[1].npulses [1]),
    .Impulse(\Loop_counter.dek[2].dModule.pulseSender._Pulses [1]),
    .Rst_n(Rst_n)
  );
  Impulse \Loop_counter.dek[2].dModule.pulseSender.pulsesImpInc  (
    .Clk(hsClk),
    .En(\Loop_counter.dek[1].npulses [0]),
    .Impulse(\Loop_counter.dek[2].dModule.pulseSender._Pulses [0]),
    .Rst_n(Rst_n)
  );
  Impulse \Loop_counter.pulsesImpDec  (
    .Clk(Clk),
    .En(\Loop_counter.PulseR ),
    .Impulse(\Loop_counter.Pulses [1]),
    .Rst_n(Rst_n)
  );
  Impulse \Loop_counter.pulsesImpInc  (
    .Clk(Clk),
    .En(\Loop_counter.PulseF ),
    .Impulse(\Loop_counter.Pulses [0]),
    .Rst_n(Rst_n)
  );
  Impulse \Loop_counter.reqPulse  (
    .Clk(Clk),
    .En(Loop_Request),
    .Impulse(\Loop_counter._Request ),
    .Rst_n(Rst_n)
  );
  OneShot #(
    .DELAY(32'sd100)
  ) \Loop_counter.writeOneShot  (
    .Clk(hsClk),
    .En(\Loop_counter.write_set ),
    .Impulse(\Loop_counter.writed_n ),
    .Rst_n(Rst_n)
  );
  Impulse \Loop_counter.writeimpulse  (
    .Clk(Clk),
    .En(\Loop_counter.state [2]),
    .Impulse(\Loop_counter.write_set ),
    .Rst_n(Rst_n)
  );
  NOT_6N16B _126_ (
    .A(state[1]),
    .Y(_082_)
  );
  NOT_6N16B _127_ (
    .A(state[0]),
    .Y(_083_)
  );
  NOT_6N16B _128_ (
    .A(state[2]),
    .Y(_084_)
  );
  NOT_6N16B _129_ (
    .A(Request),
    .Y(_085_)
  );
  NOT_6N16B _130_ (
    .A(HaltRq),
    .Y(_086_)
  );
  NOT_6N16B _131_ (
    .A(RomReady),
    .Y(_087_)
  );
  NOT_6N16B _132_ (
    .A(LoopInsnClose),
    .Y(_088_)
  );
  NOT_6N16B _133_ (
    .A(Loop_Zero),
    .Y(_089_)
  );
  NOT_6N16B _134_ (
    .A(key_next_app_i),
    .Y(_090_)
  );
  NOT_6N16B _135_ (
    .A(IpAddress[18]),
    .Y(_091_)
  );
  NOT_6N16B _136_ (
    .A(IpAddress[16]),
    .Y(_092_)
  );
  NOT_6N16B _137_ (
    .A(IP_Dec),
    .Y(_093_)
  );
  NOT_6N16B _138_ (
    .A(Loop_Dec),
    .Y(_094_)
  );
  OR2_N16 _139_ (
    .A(state[1]),
    .B(state[0]),
    .Y(_095_)
  );
  NOR2_N16 _140_ (
    .A(state[2]),
    .B(_095_),
    .Y(_096_)
  );
  OR2_N16 _141_ (
    .A(state[2]),
    .B(_095_),
    .Y(_097_)
  );
  NOR2_N16 _142_ (
    .A(Request),
    .B(_097_),
    .Y(Ready)
  );
  NOR2_N16 _143_ (
    .A(_090_),
    .B(prevApp),
    .Y(_098_)
  );
  OR2_N16 _144_ (
    .A(_090_),
    .B(prevApp),
    .Y(_099_)
  );
  NOR2_N16 _145_ (
    .A(_092_),
    .B(_099_),
    .Y(_100_)
  );
  NOR2_N16 _146_ (
    .A(IpAddress[17]),
    .B(IpAddress[16]),
    .Y(_101_)
  );
  NAND2_J2 _147_ (
    .A(_091_),
    .B(_101_),
    .Y(_102_)
  );
  NAND2_J2 _148_ (
    .A(IpAddress[19]),
    .B(_102_),
    .Y(_103_)
  );
  A1OOI_N16X7 _149_ (
    .A(_098_),
    .B(_103_),
    .C(IpAddress[16]),
    .Y(_104_)
  );
  NOR2_N16 _150_ (
    .A(_100_),
    .B(_104_),
    .Y(_000_)
  );
  NAND2_J2 _151_ (
    .A(IpAddress[17]),
    .B(_100_),
    .Y(_105_)
  );
  NAND2_J2 _152_ (
    .A(IpAddress[19]),
    .B(_098_),
    .Y(_106_)
  );
  OR2_N16 _153_ (
    .A(IpAddress[17]),
    .B(_100_),
    .Y(_107_)
  );
  AND2_N16X7 _154_ (
    .A(_105_),
    .B(_107_),
    .Y(_108_)
  );
  AND2_N16X7 _155_ (
    .A(_106_),
    .B(_108_),
    .Y(_001_)
  );
  NOR2_N16 _156_ (
    .A(_091_),
    .B(_105_),
    .Y(_109_)
  );
  NAND2_J2 _157_ (
    .A(_091_),
    .B(_105_),
    .Y(_110_)
  );
  NAND2_J2 _158_ (
    .A(_106_),
    .B(_110_),
    .Y(_111_)
  );
  NOR2_N16 _159_ (
    .A(_109_),
    .B(_111_),
    .Y(_002_)
  );
  NOR2_N16 _160_ (
    .A(IpAddress[19]),
    .B(_109_),
    .Y(_112_)
  );
  NOR2_N16 _161_ (
    .A(_099_),
    .B(_103_),
    .Y(_113_)
  );
  NOR2_N16 _162_ (
    .A(_112_),
    .B(_113_),
    .Y(_003_)
  );
  NOR2_N16 _163_ (
    .A(state[1]),
    .B(_083_),
    .Y(_114_)
  );
  NAND2_J2 _164_ (
    .A(_082_),
    .B(state[0]),
    .Y(_115_)
  );
  NOR2_N16 _165_ (
    .A(_086_),
    .B(_097_),
    .Y(_116_)
  );
  OR2_N16 _166_ (
    .A(state[2]),
    .B(_116_),
    .Y(_117_)
  );
  NAND2_J2 _167_ (
    .A(Request),
    .B(_086_),
    .Y(_118_)
  );
  NAND2_J2 _168_ (
    .A(_096_),
    .B(_118_),
    .Y(_119_)
  );
  NAND2_J2 _169_ (
    .A(_084_),
    .B(_119_),
    .Y(_120_)
  );
  NAND2_J2 _170_ (
    .A(state[1]),
    .B(_084_),
    .Y(_121_)
  );
  NOR2_N16 _171_ (
    .A(state[0]),
    .B(_121_),
    .Y(_122_)
  );
  NOR4_N16 _172_ (
    .A(_082_),
    .B(state[0]),
    .C(state[2]),
    .D(RomReady),
    .Y(_123_)
  );
  NOR4_N16 _173_ (
    .A(_085_),
    .B(HaltRq),
    .C(RomReady),
    .D(_097_),
    .Y(_124_)
  );
  OR2_N16 _174_ (
    .A(_123_),
    .B(_124_),
    .Y(_125_)
  );
  NAND4_N16X7 _175_ (
    .A(state[1]),
    .B(_083_),
    .C(_084_),
    .D(RomReady),
    .Y(_016_)
  );
  OR2_N16 _176_ (
    .A(LoopInsnCloseInternal),
    .B(LoopInsnOpenInternal),
    .Y(_017_)
  );
  NOR2_N16 _177_ (
    .A(Loop_Zero),
    .B(_017_),
    .Y(_018_)
  );
  NOR2_N16 _178_ (
    .A(_016_),
    .B(_018_),
    .Y(_019_)
  );
  NAND2_J2 _179_ (
    .A(state[1]),
    .B(state[0]),
    .Y(_020_)
  );
  NOT_6N16B _180_ (
    .A(_020_),
    .Y(_021_)
  );
  AND2_N16X7 _181_ (
    .A(_089_),
    .B(_017_),
    .Y(_022_)
  );
  NOR2_N16 _182_ (
    .A(_016_),
    .B(_022_),
    .Y(_023_)
  );
  NOR2_N16 _183_ (
    .A(_087_),
    .B(_097_),
    .Y(_024_)
  );
  NAND2_J2 _184_ (
    .A(RomReady),
    .B(_096_),
    .Y(_025_)
  );
  NOR2_N16 _185_ (
    .A(_088_),
    .B(dataIsZeroed),
    .Y(_026_)
  );
  OR2_N16 _186_ (
    .A(_088_),
    .B(dataIsZeroed),
    .Y(_027_)
  );
  AND2_N16X7 _187_ (
    .A(LoopInsnOpen),
    .B(dataIsZeroed),
    .Y(_028_)
  );
  NOR4_N16 _188_ (
    .A(_118_),
    .B(_025_),
    .C(_026_),
    .D(_028_),
    .Y(_029_)
  );
  NOR4_N16 _189_ (
    .A(state[2]),
    .B(Request),
    .C(HaltRq),
    .D(_095_),
    .Y(_030_)
  );
  OR4_N16X7 _190_ (
    .A(_123_),
    .B(_124_),
    .C(_023_),
    .D(_030_),
    .Y(_031_)
  );
  OR2_N16 _191_ (
    .A(state[2]),
    .B(_020_),
    .Y(_032_)
  );
  NOT_6N16B _192_ (
    .A(_032_),
    .Y(_033_)
  );
  NOR2_N16 _193_ (
    .A(Loop_Ready),
    .B(_032_),
    .Y(_034_)
  );
  A1OOI_N16X7 _194_ (
    .A(Loop_Ready),
    .B(_022_),
    .C(_032_),
    .Y(_035_)
  );
  NOR4_N16 _195_ (
    .A(_120_),
    .B(_125_),
    .C(_019_),
    .D(_035_),
    .Y(_036_)
  );
  OR4_N16X7 _196_ (
    .A(_120_),
    .B(_125_),
    .C(_019_),
    .D(_035_),
    .Y(_037_)
  );
  NAND2_J2 _197_ (
    .A(_115_),
    .B(_036_),
    .Y(_038_)
  );
  NOR2_N16 _198_ (
    .A(_089_),
    .B(_032_),
    .Y(_039_)
  );
  NOR4_N16 _199_ (
    .A(_114_),
    .B(_027_),
    .C(_037_),
    .D(_039_),
    .Y(_040_)
  );
  A1OOI_N16X7 _200_ (
    .A(_115_),
    .B(_036_),
    .C(_093_),
    .Y(_041_)
  );
  OR2_N16 _201_ (
    .A(_040_),
    .B(_041_),
    .Y(_004_)
  );
  NAND2_J2 _202_ (
    .A(IP_Request),
    .B(_037_),
    .Y(_042_)
  );
  NAND2_J2 _203_ (
    .A(_038_),
    .B(_042_),
    .Y(_005_)
  );
  NOR2_N16 _204_ (
    .A(state[2]),
    .B(_115_),
    .Y(_043_)
  );
  NOR4_N16 _205_ (
    .A(state[1]),
    .B(_083_),
    .C(state[2]),
    .D(IP_Ready),
    .Y(_044_)
  );
  NOR4_N16 _206_ (
    .A(_120_),
    .B(_021_),
    .C(_024_),
    .D(_044_),
    .Y(_045_)
  );
  NOR2_N16 _207_ (
    .A(RomRequest),
    .B(_045_),
    .Y(_046_)
  );
  NOR2_N16 _208_ (
    .A(_122_),
    .B(_046_),
    .Y(_006_)
  );
  NOR2_N16 _209_ (
    .A(_034_),
    .B(_044_),
    .Y(_047_)
  );
  NOR2_N16 _210_ (
    .A(_084_),
    .B(_095_),
    .Y(_048_)
  );
  OR2_N16 _211_ (
    .A(_084_),
    .B(_095_),
    .Y(_049_)
  );
  NOR2_N16 _212_ (
    .A(_085_),
    .B(_049_),
    .Y(_050_)
  );
  OR2_N16 _213_ (
    .A(_123_),
    .B(_030_),
    .Y(_051_)
  );
  NOR2_N16 _214_ (
    .A(_050_),
    .B(_051_),
    .Y(_052_)
  );
  OR2_N16 _215_ (
    .A(_050_),
    .B(_051_),
    .Y(_053_)
  );
  NAND2_J2 _216_ (
    .A(state[2]),
    .B(HaltRq),
    .Y(_054_)
  );
  NOR2_N16 _217_ (
    .A(_020_),
    .B(_054_),
    .Y(_055_)
  );
  NOR2_N16 _218_ (
    .A(state[0]),
    .B(_089_),
    .Y(_056_)
  );
  NOR2_N16 _219_ (
    .A(_121_),
    .B(_056_),
    .Y(_057_)
  );
  NOR4_N16 _220_ (
    .A(_116_),
    .B(_024_),
    .C(_055_),
    .D(_057_),
    .Y(_058_)
  );
  OR2_N16 _221_ (
    .A(_053_),
    .B(_058_),
    .Y(_059_)
  );
  NAND2_J2 _222_ (
    .A(_047_),
    .B(_059_),
    .Y(_007_)
  );
  NAND2_J2 _223_ (
    .A(_047_),
    .B(_052_),
    .Y(_060_)
  );
  NOR4_N16 _224_ (
    .A(HaltRq),
    .B(_087_),
    .C(_026_),
    .D(_028_),
    .Y(_061_)
  );
  OR2_N16 _225_ (
    .A(_097_),
    .B(_061_),
    .Y(_062_)
  );
  NAND2_J2 _226_ (
    .A(_122_),
    .B(_022_),
    .Y(_063_)
  );
  NAND2_J2 _227_ (
    .A(_062_),
    .B(_063_),
    .Y(_064_)
  );
  NOR4_N16 _228_ (
    .A(_043_),
    .B(_055_),
    .C(_060_),
    .D(_064_),
    .Y(_065_)
  );
  A1OOI_N16X7 _229_ (
    .A(_082_),
    .B(_060_),
    .C(_065_),
    .Y(_008_)
  );
  A2OOI_N16X7 _230_ (
    .A(Loop_Zero),
    .B(_122_),
    .C(_055_),
    .D(_116_),
    .Y(_066_)
  );
  NOR2_N16 _231_ (
    .A(_060_),
    .B(_066_),
    .Y(_067_)
  );
  OR2_N16 _232_ (
    .A(_050_),
    .B(_067_),
    .Y(_009_)
  );
  NAND2_J2 _233_ (
    .A(RomData[0]),
    .B(_048_),
    .Y(_068_)
  );
  NAND2_J2 _234_ (
    .A(Insn[0]),
    .B(_049_),
    .Y(_069_)
  );
  NAND2_J2 _235_ (
    .A(_068_),
    .B(_069_),
    .Y(_010_)
  );
  NAND2_J2 _236_ (
    .A(RomData[1]),
    .B(_048_),
    .Y(_070_)
  );
  NAND2_J2 _237_ (
    .A(Insn[1]),
    .B(_049_),
    .Y(_071_)
  );
  NAND2_J2 _238_ (
    .A(_070_),
    .B(_071_),
    .Y(_011_)
  );
  NAND2_J2 _239_ (
    .A(RomData[2]),
    .B(_048_),
    .Y(_072_)
  );
  NAND2_J2 _240_ (
    .A(Insn[2]),
    .B(_049_),
    .Y(_073_)
  );
  NAND2_J2 _241_ (
    .A(_072_),
    .B(_073_),
    .Y(_012_)
  );
  NAND2_J2 _242_ (
    .A(RomData[3]),
    .B(_048_),
    .Y(_074_)
  );
  NAND2_J2 _243_ (
    .A(Insn[3]),
    .B(_049_),
    .Y(_075_)
  );
  NAND2_J2 _244_ (
    .A(_074_),
    .B(_075_),
    .Y(_013_)
  );
  NOR4_N16 _245_ (
    .A(state[0]),
    .B(_117_),
    .C(_029_),
    .D(_031_),
    .Y(_076_)
  );
  OR2_N16 _246_ (
    .A(LoopInsnOpenInternal),
    .B(_027_),
    .Y(_077_)
  );
  OR2_N16 _247_ (
    .A(LoopInsnCloseInternal),
    .B(_026_),
    .Y(_078_)
  );
  NAND4_N16X7 _248_ (
    .A(_122_),
    .B(_076_),
    .C(_077_),
    .D(_078_),
    .Y(_079_)
  );
  OR2_N16 _249_ (
    .A(_094_),
    .B(_076_),
    .Y(_080_)
  );
  NAND2_J2 _250_ (
    .A(_079_),
    .B(_080_),
    .Y(_014_)
  );
  NOR2_N16 _251_ (
    .A(Loop_Request),
    .B(_076_),
    .Y(_081_)
  );
  NOR2_N16 _252_ (
    .A(_033_),
    .B(_081_),
    .Y(_015_)
  );
  DFFSR_n _253_ (
    .C(Clk),
    .D(_000_),
    .Q(IpAddress[16]),
    .R(Rst_n),
    .S(1'h0)
  );
  DFFSR_n _254_ (
    .C(Clk),
    .D(_001_),
    .Q(IpAddress[17]),
    .R(Rst_n),
    .S(1'h0)
  );
  DFFSR_n _255_ (
    .C(Clk),
    .D(_002_),
    .Q(IpAddress[18]),
    .R(Rst_n),
    .S(1'h0)
  );
  DFFSR_n _256_ (
    .C(Clk),
    .D(_003_),
    .Q(IpAddress[19]),
    .R(Rst_n),
    .S(1'h0)
  );
  DFFSR_n _257_ (
    .C(Clk),
    .D(_004_),
    .Q(IP_Dec),
    .R(Rst_n),
    .S(1'h0)
  );
  DFFSR_n _258_ (
    .C(Clk),
    .D(_005_),
    .Q(IP_Request),
    .R(Rst_n),
    .S(1'h0)
  );
  DFFSR_n _259_ (
    .C(Clk),
    .D(_006_),
    .Q(RomRequest),
    .R(Rst_n),
    .S(1'h0)
  );
  DFFSR_n _260_ (
    .C(Clk),
    .D(_007_),
    .Q(state[0]),
    .R(Rst_n),
    .S(1'h0)
  );
  DFFSR_n _261_ (
    .C(Clk),
    .D(_008_),
    .Q(state[1]),
    .R(Rst_n),
    .S(1'h0)
  );
  DFFSR_n _262_ (
    .C(Clk),
    .D(_009_),
    .Q(state[2]),
    .R(Rst_n),
    .S(1'h0)
  );
  DFFSR_n _263_ (
    .C(Clk),
    .D(_010_),
    .Q(Insn[0]),
    .R(Rst_n),
    .S(1'h0)
  );
  DFFSR_n _264_ (
    .C(Clk),
    .D(_011_),
    .Q(Insn[1]),
    .R(Rst_n),
    .S(1'h0)
  );
  DFFSR_n _265_ (
    .C(Clk),
    .D(_012_),
    .Q(Insn[2]),
    .R(Rst_n),
    .S(1'h0)
  );
  DFFSR_n _266_ (
    .C(Clk),
    .D(_013_),
    .Q(Insn[3]),
    .R(Rst_n),
    .S(1'h0)
  );
  DFFSR_n _267_ (
    .C(Clk),
    .D(key_next_app_i),
    .Q(prevApp),
    .R(Rst_n),
    .S(1'h0)
  );
  DFFSR_n _268_ (
    .C(Clk),
    .D(_014_),
    .Q(Loop_Dec),
    .R(Rst_n),
    .S(1'h0)
  );
  DFFSR_n _269_ (
    .C(Clk),
    .D(_015_),
    .Q(Loop_Request),
    .R(Rst_n),
    .S(1'h0)
  );
  NOT_6N16B \insnLoopDetector._3_  (
    .A(Insn[2]),
    .Y(\insnLoopDetector._0_ )
  );
  NOT_6N16B \insnLoopDetector._4_  (
    .A(Insn[1]),
    .Y(\insnLoopDetector._1_ )
  );
  NOT_6N16B \insnLoopDetector._5_  (
    .A(Insn[0]),
    .Y(\insnLoopDetector._2_ )
  );
  NOR4_N16 \insnLoopDetector._6_  (
    .A(\insnLoopDetector._0_ ),
    .B(Insn[3]),
    .C(\insnLoopDetector._1_ ),
    .D(Insn[0]),
    .Y(LoopInsnOpen)
  );
  NOR4_N16 \insnLoopDetector._7_  (
    .A(\insnLoopDetector._0_ ),
    .B(Insn[3]),
    .C(\insnLoopDetector._1_ ),
    .D(\insnLoopDetector._2_ ),
    .Y(LoopInsnClose)
  );
  NOT_6N16B \insnLoopDetectorInternal._3_  (
    .A(RomData[2]),
    .Y(\insnLoopDetectorInternal._0_ )
  );
  NOT_6N16B \insnLoopDetectorInternal._4_  (
    .A(RomData[1]),
    .Y(\insnLoopDetectorInternal._1_ )
  );
  NOT_6N16B \insnLoopDetectorInternal._5_  (
    .A(RomData[0]),
    .Y(\insnLoopDetectorInternal._2_ )
  );
  NOR4_N16 \insnLoopDetectorInternal._6_  (
    .A(\insnLoopDetectorInternal._0_ ),
    .B(RomData[3]),
    .C(\insnLoopDetectorInternal._1_ ),
    .D(RomData[0]),
    .Y(LoopInsnOpenInternal)
  );
  NOR4_N16 \insnLoopDetectorInternal._7_  (
    .A(\insnLoopDetectorInternal._0_ ),
    .B(RomData[3]),
    .C(\insnLoopDetectorInternal._1_ ),
    .D(\insnLoopDetectorInternal._2_ ),
    .Y(LoopInsnCloseInternal)
  );
  assign { \Loop_counter.dek[0].dModule.OutPos [9], \Loop_counter.dek[0].dModule.OutPos [5], \Loop_counter.dek[0].dModule.OutPos [0] } = { \Loop_counter.dek[0].DekNine , \Loop_counter.TopOut [0], \Loop_counter.dek[0].DekZero  };
  assign { \IP_counter.dek[0].dModule.OutPos [9], \IP_counter.dek[0].dModule.OutPos [5], \IP_counter.dek[0].dModule.OutPos [0] } = { \IP_counter.dek[0].DekNine , \IP_counter.TopOut [0], \IP_counter.dek[0].DekZero  };
  assign { \Loop_counter.dek[1].dModule.OutPos [9], \Loop_counter.dek[1].dModule.OutPos [5], \Loop_counter.dek[1].dModule.OutPos [0] } = { \Loop_counter.dek[1].DekNine , \Loop_counter.TopOut [1], \Loop_counter.dek[1].DekZero  };
  assign { \Loop_counter.dek[2].dModule.OutPos [9], \Loop_counter.dek[2].dModule.OutPos [5], \Loop_counter.dek[2].dModule.OutPos [0] } = { \Loop_counter.dek[2].DekNine , \Loop_counter.TopOut [2], \Loop_counter.dek[2].DekZero  };
  assign { \IP_counter.dek[1].dModule.OutPos [9], \IP_counter.dek[1].dModule.OutPos [5], \IP_counter.dek[1].dModule.OutPos [0] } = { \IP_counter.dek[1].DekNine , \IP_counter.TopOut [1], \IP_counter.dek[1].DekZero  };
  assign { \IP_counter.dek[2].dModule.OutPos [9], \IP_counter.dek[2].dModule.OutPos [5], \IP_counter.dek[2].dModule.OutPos [0] } = { \IP_counter.dek[2].DekNine , \IP_counter.TopOut [2], \IP_counter.dek[2].DekZero  };
  assign { \IP_counter.dek[3].dModule.OutPos [9], \IP_counter.dek[3].dModule.OutPos [0] } = { \IP_counter.dek[3].DekNine , \IP_counter.TopOut [3] };
  assign LoopCount = 12'hxxx;
endmodule
