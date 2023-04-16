`ifndef INSN_VALUES
   `define INSN_VALUES

typedef enum bit [0:0]{
    INSN_DEBUG_MODE  = 1'b0,
    INSN_BRAINFUCK_MODE = 1'b1
} mode_t;

typedef enum bit [4:0]  {
    INSN_NOP            = 5'hx0,//No operation - Must be in both ISA set
    INSN_HALT           = 5'hx1,//Stop machine - Must be in both ISA set
  //INSN_RES0           = 5'h02,
  //INSN_RES1           = 5'h03,
  //INSN_RES2           = 5'h04,
  //INSN_RES3           = 5'h05,
    INSN_LABEG          = 5'h06,//If AP==0 skip loop
    INSN_LAEND          = 5'h07,//If AP!=0 repeat loop
    INSN_CLRL           = 5'h08,//Reset Loop Counter
    INSN_CLRI           = 5'h09,//Reset IP Counter
    INSN_CLRD           = 5'hxA,//Reset Data Counter
    INSN_CLRA           = 5'h0B,//Reset AP Counter
  //INSN_RES4           = 5'h0C,
    INSN_RST            = 5'h0D,//Hard Reset
    INSN_DEBUG          = 5'hxE,//Switch to Debug Mode - Must be in both ISA set
    INSN_BRAINFUCK      = 5'hxF,//Switch to Brainfuck Mode - Must be in both ISA set

  //INSN_NOP            = 5'hx0,
  //INSN_HALT           = 5'hx1,
    INSN_INC            = 5'h12,// +1
    INSN_DEC            = 5'h13,// -1
    INSN_AINC           = 5'h14,// >
    INSN_ADEC           = 5'h15,// <
    INSN_LBEG           = 5'h16,// [
    INSN_LEND           = 5'h17,// ]
    INSN_COUT           = 5'h18,// .
    INSN_CIN            = 5'h19,// ,
  //INSN_CLRD           = 5'hxA,
    INSN_CLRML          = 5'h1B,//Clear memory Lock
    INSN_LOAD           = 5'h1C,//Explicit Load from current memory cell to Data Counter
    INSN_STORE          = 5'h1D//Explicit Store from Data Counter to current memory cell
  //INSN_DEBUG          = 5'hxE,
  //INSN_BRAINFUCK      = 5'hxF
} insn_t;

`endif
