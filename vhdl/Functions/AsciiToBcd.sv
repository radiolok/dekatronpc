module AsciiToBcd(
   input wire [7:0] ascii,
   output reg [11:0] bcd
);
always_comb
  case(ascii)
    8'h0: bcd = 12'h0; //  
    8'h1: bcd = 12'h1; //  
    8'h2: bcd = 12'h2; //  
    8'h3: bcd = 12'h3; //  
    8'h4: bcd = 12'h4; //  
    8'h5: bcd = 12'h5; //  
    8'h6: bcd = 12'h6; //  
    8'h7: bcd = 12'h7; //  
    8'h8: bcd = 12'h8; //  
    8'h9: bcd = 12'h9; //  
    8'ha: bcd = 12'h10; //  
    8'hb: bcd = 12'h11; //  
    8'hc: bcd = 12'h12; //  
    8'hd: bcd = 12'h13; //  
    8'he: bcd = 12'h14; //  
    8'hf: bcd = 12'h15; //  
    8'h10: bcd = 12'h16; //  
    8'h11: bcd = 12'h17; //  
    8'h12: bcd = 12'h18; //  
    8'h13: bcd = 12'h19; //  
    8'h14: bcd = 12'h20; //  
    8'h15: bcd = 12'h21; //  
    8'h16: bcd = 12'h22; //  
    8'h17: bcd = 12'h23; //  
    8'h18: bcd = 12'h24; //  
    8'h19: bcd = 12'h25; //  
    8'h1a: bcd = 12'h26; //  
    8'h1b: bcd = 12'h27; //  
    8'h1c: bcd = 12'h28; //  
    8'h1d: bcd = 12'h29; //  
    8'h1e: bcd = 12'h30; //  
    8'h1f: bcd = 12'h31; //  
    8'h20: bcd = 12'h32; //  
    8'h21: bcd = 12'h33; //! 
    8'h22: bcd = 12'h34; //" 
    8'h23: bcd = 12'h35; //# 
    8'h24: bcd = 12'h36; //$ 
    8'h25: bcd = 12'h37; //% 
    8'h26: bcd = 12'h38; //& 
    8'h27: bcd = 12'h39; //' 
    8'h28: bcd = 12'h40; //( 
    8'h29: bcd = 12'h41; //) 
    8'h2a: bcd = 12'h42; //* 
    8'h2b: bcd = 12'h43; //+ 
    8'h2c: bcd = 12'h44; //, 
    8'h2d: bcd = 12'h45; //- 
    8'h2e: bcd = 12'h46; //. 
    8'h2f: bcd = 12'h47; /// 
    8'h30: bcd = 12'h48; //0 
    8'h31: bcd = 12'h49; //1 
    8'h32: bcd = 12'h50; //2 
    8'h33: bcd = 12'h51; //3 
    8'h34: bcd = 12'h52; //4 
    8'h35: bcd = 12'h53; //5 
    8'h36: bcd = 12'h54; //6 
    8'h37: bcd = 12'h55; //7 
    8'h38: bcd = 12'h56; //8 
    8'h39: bcd = 12'h57; //9 
    8'h3a: bcd = 12'h58; //: 
    8'h3b: bcd = 12'h59; //; 
    8'h3c: bcd = 12'h60; //< 
    8'h3d: bcd = 12'h61; //= 
    8'h3e: bcd = 12'h62; //> 
    8'h3f: bcd = 12'h63; //? 
    8'h40: bcd = 12'h64; //@ 
    8'h41: bcd = 12'h65; //A 
    8'h42: bcd = 12'h66; //B 
    8'h43: bcd = 12'h67; //C 
    8'h44: bcd = 12'h68; //D 
    8'h45: bcd = 12'h69; //E 
    8'h46: bcd = 12'h70; //F 
    8'h47: bcd = 12'h71; //G 
    8'h48: bcd = 12'h72; //H 
    8'h49: bcd = 12'h73; //I 
    8'h4a: bcd = 12'h74; //J 
    8'h4b: bcd = 12'h75; //K 
    8'h4c: bcd = 12'h76; //L 
    8'h4d: bcd = 12'h77; //M 
    8'h4e: bcd = 12'h78; //N 
    8'h4f: bcd = 12'h79; //O 
    8'h50: bcd = 12'h80; //P 
    8'h51: bcd = 12'h81; //Q 
    8'h52: bcd = 12'h82; //R 
    8'h53: bcd = 12'h83; //S 
    8'h54: bcd = 12'h84; //T 
    8'h55: bcd = 12'h85; //U 
    8'h56: bcd = 12'h86; //V 
    8'h57: bcd = 12'h87; //W 
    8'h58: bcd = 12'h88; //X 
    8'h59: bcd = 12'h89; //Y 
    8'h5a: bcd = 12'h90; //Z 
    8'h5b: bcd = 12'h91; //[ 
    8'h5c: bcd = 12'h92; //\ 
    8'h5d: bcd = 12'h93; //] 
    8'h5e: bcd = 12'h94; //^ 
    8'h5f: bcd = 12'h95; //_ 
    8'h60: bcd = 12'h96; //` 
    8'h61: bcd = 12'h97; //a 
    8'h62: bcd = 12'h98; //b 
    8'h63: bcd = 12'h99; //c 
    8'h64: bcd = 12'h100; //d 
    8'h65: bcd = 12'h101; //e 
    8'h66: bcd = 12'h102; //f 
    8'h67: bcd = 12'h103; //g 
    8'h68: bcd = 12'h104; //h 
    8'h69: bcd = 12'h105; //i 
    8'h6a: bcd = 12'h106; //j 
    8'h6b: bcd = 12'h107; //k 
    8'h6c: bcd = 12'h108; //l 
    8'h6d: bcd = 12'h109; //m 
    8'h6e: bcd = 12'h110; //n 
    8'h6f: bcd = 12'h111; //o 
    8'h70: bcd = 12'h112; //p 
    8'h71: bcd = 12'h113; //q 
    8'h72: bcd = 12'h114; //r 
    8'h73: bcd = 12'h115; //s 
    8'h74: bcd = 12'h116; //t 
    8'h75: bcd = 12'h117; //u 
    8'h76: bcd = 12'h118; //v 
    8'h77: bcd = 12'h119; //w 
    8'h78: bcd = 12'h120; //x 
    8'h79: bcd = 12'h121; //y 
    8'h7a: bcd = 12'h122; //z 
    8'h7b: bcd = 12'h123; //{ 
    8'h7c: bcd = 12'h124; //| 
    8'h7d: bcd = 12'h125; //} 
    8'h7e: bcd = 12'h126; //~ 
    8'h7f: bcd = 12'h127; // 
    8'h80: bcd = 12'h128; // 
    8'h81: bcd = 12'h129; // 
    8'h82: bcd = 12'h130; // 
    8'h83: bcd = 12'h131; // 
    8'h84: bcd = 12'h132; // 
    8'h85: bcd = 12'h133; // 
    8'h86: bcd = 12'h134; // 
    8'h87: bcd = 12'h135; // 
    8'h88: bcd = 12'h136; // 
    8'h89: bcd = 12'h137; // 
    8'h8a: bcd = 12'h138; // 
    8'h8b: bcd = 12'h139; // 
    8'h8c: bcd = 12'h140; // 
    8'h8d: bcd = 12'h141; // 
    8'h8e: bcd = 12'h142; // 
    8'h8f: bcd = 12'h143; // 
    8'h90: bcd = 12'h144; // 
    8'h91: bcd = 12'h145; // 
    8'h92: bcd = 12'h146; // 
    8'h93: bcd = 12'h147; // 
    8'h94: bcd = 12'h148; // 
    8'h95: bcd = 12'h149; // 
    8'h96: bcd = 12'h150; // 
    8'h97: bcd = 12'h151; // 
    8'h98: bcd = 12'h152; // 
    8'h99: bcd = 12'h153; // 
    8'h9a: bcd = 12'h154; // 
    8'h9b: bcd = 12'h155; // 
    8'h9c: bcd = 12'h156; // 
    8'h9d: bcd = 12'h157; // 
    8'h9e: bcd = 12'h158; // 
    8'h9f: bcd = 12'h159; // 
    8'ha0: bcd = 12'h160; //  
    8'ha1: bcd = 12'h161; //¡ 
    8'ha2: bcd = 12'h162; //¢ 
    8'ha3: bcd = 12'h163; //£ 
    8'ha4: bcd = 12'h164; //¤ 
    8'ha5: bcd = 12'h165; //¥ 
    8'ha6: bcd = 12'h166; //¦ 
    8'ha7: bcd = 12'h167; //§ 
    8'ha8: bcd = 12'h168; //¨ 
    8'ha9: bcd = 12'h169; //© 
    8'haa: bcd = 12'h170; //ª 
    8'hab: bcd = 12'h171; //« 
    8'hac: bcd = 12'h172; //¬ 
    8'had: bcd = 12'h173; //­ 
    8'hae: bcd = 12'h174; //® 
    8'haf: bcd = 12'h175; //¯ 
    8'hb0: bcd = 12'h176; //° 
    8'hb1: bcd = 12'h177; //± 
    8'hb2: bcd = 12'h178; //² 
    8'hb3: bcd = 12'h179; //³ 
    8'hb4: bcd = 12'h180; //´ 
    8'hb5: bcd = 12'h181; //µ 
    8'hb6: bcd = 12'h182; //¶ 
    8'hb7: bcd = 12'h183; //· 
    8'hb8: bcd = 12'h184; //¸ 
    8'hb9: bcd = 12'h185; //¹ 
    8'hba: bcd = 12'h186; //º 
    8'hbb: bcd = 12'h187; //» 
    8'hbc: bcd = 12'h188; //¼ 
    8'hbd: bcd = 12'h189; //½ 
    8'hbe: bcd = 12'h190; //¾ 
    8'hbf: bcd = 12'h191; //¿ 
    8'hc0: bcd = 12'h192; //À 
    8'hc1: bcd = 12'h193; //Á 
    8'hc2: bcd = 12'h194; //Â 
    8'hc3: bcd = 12'h195; //Ã 
    8'hc4: bcd = 12'h196; //Ä 
    8'hc5: bcd = 12'h197; //Å 
    8'hc6: bcd = 12'h198; //Æ 
    8'hc7: bcd = 12'h199; //Ç 
    8'hc8: bcd = 12'h200; //È 
    8'hc9: bcd = 12'h201; //É 
    8'hca: bcd = 12'h202; //Ê 
    8'hcb: bcd = 12'h203; //Ë 
    8'hcc: bcd = 12'h204; //Ì 
    8'hcd: bcd = 12'h205; //Í 
    8'hce: bcd = 12'h206; //Î 
    8'hcf: bcd = 12'h207; //Ï 
    8'hd0: bcd = 12'h208; //Ð 
    8'hd1: bcd = 12'h209; //Ñ 
    8'hd2: bcd = 12'h210; //Ò 
    8'hd3: bcd = 12'h211; //Ó 
    8'hd4: bcd = 12'h212; //Ô 
    8'hd5: bcd = 12'h213; //Õ 
    8'hd6: bcd = 12'h214; //Ö 
    8'hd7: bcd = 12'h215; //× 
    8'hd8: bcd = 12'h216; //Ø 
    8'hd9: bcd = 12'h217; //Ù 
    8'hda: bcd = 12'h218; //Ú 
    8'hdb: bcd = 12'h219; //Û 
    8'hdc: bcd = 12'h220; //Ü 
    8'hdd: bcd = 12'h221; //Ý 
    8'hde: bcd = 12'h222; //Þ 
    8'hdf: bcd = 12'h223; //ß 
    8'he0: bcd = 12'h224; //à 
    8'he1: bcd = 12'h225; //á 
    8'he2: bcd = 12'h226; //â 
    8'he3: bcd = 12'h227; //ã 
    8'he4: bcd = 12'h228; //ä 
    8'he5: bcd = 12'h229; //å 
    8'he6: bcd = 12'h230; //æ 
    8'he7: bcd = 12'h231; //ç 
    8'he8: bcd = 12'h232; //è 
    8'he9: bcd = 12'h233; //é 
    8'hea: bcd = 12'h234; //ê 
    8'heb: bcd = 12'h235; //ë 
    8'hec: bcd = 12'h236; //ì 
    8'hed: bcd = 12'h237; //í 
    8'hee: bcd = 12'h238; //î 
    8'hef: bcd = 12'h239; //ï 
    8'hf0: bcd = 12'h240; //ð 
    8'hf1: bcd = 12'h241; //ñ 
    8'hf2: bcd = 12'h242; //ò 
    8'hf3: bcd = 12'h243; //ó 
    8'hf4: bcd = 12'h244; //ô 
    8'hf5: bcd = 12'h245; //õ 
    8'hf6: bcd = 12'h246; //ö 
    8'hf7: bcd = 12'h247; //÷ 
    8'hf8: bcd = 12'h248; //ø 
    8'hf9: bcd = 12'h249; //ù 
    8'hfa: bcd = 12'h250; //ú 
    8'hfb: bcd = 12'h251; //û 
    8'hfc: bcd = 12'h252; //ü 
    8'hfd: bcd = 12'h253; //ý 
    8'hfe: bcd = 12'h254; //þ 
    8'hff: bcd = 12'h255; //ÿ 
    default: bcd = {12'bx};
  endcase
endmodule
