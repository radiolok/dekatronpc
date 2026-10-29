* DekatronPC vacuum-tube standard-cell library (SPICE behavioral models).
* Simulation companion to vtube_cells.lib and vtube_cells.v.
*
* Logic convention: low = 0 V, high = 1 V, switching threshold = 0.5 V.
* Combinational cells are modeled as ideal behavioral voltage sources
* (ngspice E devices). Storage cells (LATCH_J2N16, DFF_J2N16, DFFRN_J2N16X7, DFFSN_J2N16X7) use the
* XSPICE d_latch / d_dff code models and therefore require ngspice built
* with XSPICE support. ngspice auto-inserts analog/digital bridges at the
* mixed-signal boundaries between these two domains.
*
* Cell names, port names and port order match vtube_cells.lib.

.SUBCKT BUF_6N16B A Y
E1 Y 0 VALUE = { (v(A) > 0.5) ? 1 : 0 }
.ENDS BUF_6N16B

.SUBCKT BUF_6J2B A Y
E1 Y 0 VALUE = { (v(A) > 0.5) ? 1 : 0 }
.ENDS BUF_6J2B

.SUBCKT NOT_6N16B A Y
E1 Y 0 VALUE = { (v(A) > 0.5) ? 0 : 1 }
.ENDS NOT_6N16B

.SUBCKT NOT_6J2B A Y
E1 Y 0 VALUE = { (v(A) > 0.5) ? 0 : 1 }
.ENDS NOT_6J2B

.SUBCKT NAND2_N16X7 A B Y
E1 Y 0 VALUE = { ((v(A) > 0.5) && (v(B) > 0.5)) ? 0 : 1 }
.ENDS NAND2_N16X7

.SUBCKT AND2_N16X7 A B Y
E1 Y 0 VALUE = { ((v(A) > 0.5) && (v(B) > 0.5)) ? 1 : 0 }
.ENDS AND2_N16X7

.SUBCKT NAND2_J2 A B Y
E1 Y 0 VALUE = { ((v(A) > 0.5) && (v(B) > 0.5)) ? 0 : 1 }
.ENDS NAND2_J2

.SUBCKT NAND4_N16X7 A B C D Y
E1 Y 0 VALUE = { ((v(A) > 0.5) && (v(B) > 0.5) && (v(C) > 0.5) && (v(D) > 0.5)) ? 0 : 1 }
.ENDS NAND4_N16X7

.SUBCKT A1OOI_N16X7 A B C Y
E1 Y 0 VALUE = { (((v(A) > 0.5) && (v(B) > 0.5)) || (v(C) > 0.5)) ? 0 : 1 }
.ENDS A1OOI_N16X7

.SUBCKT A2OOI_N16X7 A B C D Y
E1 Y 0 VALUE = { (((v(A) > 0.5) && (v(B) > 0.5)) || (v(C) > 0.5) || (v(D) > 0.5)) ? 0 : 1 }
.ENDS A2OOI_N16X7

.SUBCKT OR2_N16 A B Y
E1 Y 0 VALUE = { ((v(A) > 0.5) || (v(B) > 0.5)) ? 1 : 0 }
.ENDS OR2_N16

.SUBCKT OR2_N16X7 A B Y
E1 Y 0 VALUE = { ((v(A) > 0.5) || (v(B) > 0.5)) ? 1 : 0 }
.ENDS OR2_N16X7

.SUBCKT OR4_N16X7 A B C D Y
E1 Y 0 VALUE = { ((v(A) > 0.5) || (v(B) > 0.5) || (v(C) > 0.5) || (v(D) > 0.5)) ? 1 : 0 }
.ENDS OR4_N16X7

.SUBCKT OR10_X7 A B C D E F G H K L Y
E1 Y 0 VALUE = { ((v(A) > 0.5) || (v(B) > 0.5) || (v(C) > 0.5) || (v(D) > 0.5) || (v(E) > 0.5) || (v(F) > 0.5) || (v(G) > 0.5) || (v(H) > 0.5) || (v(K) > 0.5) || (v(L) > 0.5)) ? 1 : 0 }
.ENDS OR10_X7

.SUBCKT NOR2_N16 A B Y
E1 Y 0 VALUE = { ((v(A) > 0.5) || (v(B) > 0.5)) ? 0 : 1 }
.ENDS NOR2_N16

.SUBCKT NOR4_N16 A B C D Y
E1 Y 0 VALUE = { ((v(A) > 0.5) || (v(B) > 0.5) || (v(C) > 0.5) || (v(D) > 0.5)) ? 0 : 1 }
.ENDS NOR4_N16

.SUBCKT NOR2_N16X7 A B Y
E1 Y 0 VALUE = { ((v(A) > 0.5) || (v(B) > 0.5)) ? 0 : 1 }
.ENDS NOR2_N16X7

.SUBCKT NOR4_N16X7 A B C D Y
E1 Y 0 VALUE = { ((v(A) > 0.5) || (v(B) > 0.5) || (v(C) > 0.5) || (v(D) > 0.5)) ? 0 : 1 }
.ENDS NOR4_N16X7

.SUBCKT LATCH_J2N16 C D Q
.model latch1 d_latch
Alatch D C null null Q nQ latch1
.ENDS LATCH_J2N16

* falling edge: the clock goes through an inverter
.SUBCKT DFF_J2N16 C D Q
.model dffinv1 d_inverter
Ainv C nC dffinv1
.model dff1 d_dff
Adff D nC null null Q nQ dff1
.ENDS DFF_J2N16

* asynchronous clear / preset, active low, falling edge (the clock through an inverter)
.SUBCKT DFFRN_J2N16X7 C D RN Q
.model dffrninv d_inverter
Ainv C nC dffrninv
Ainr RN nRN dffrninv
.model dffrn1 d_dff
Adff D nC null nRN Q nQ dffrn1
.ENDS DFFRN_J2N16X7

.SUBCKT DFFSN_J2N16X7 C D SN Q
.model dffsninv d_inverter
Ainv C nC dffsninv
Ains SN nSN dffsninv
.model dffsn1 d_dff
Adff D nC nSN null Q nQ dffsn1
.ENDS DFFSN_J2N16X7

* Guide gate of a dekatron decade, one per guide: J2 pentode, two control grids (guide G and EN): Y = G & EN
.SUBCKT GUIDE_EN_J2 EN G Y
E1 Y 0 VALUE = { ((v(G) > 0.5) && (v(EN) > 0.5)) ? 1 : 0 }
.ENDS GUIDE_EN_J2

.SUBCKT TIEHI H
V1 H 0 DC 1
.ENDS TIEHI

.SUBCKT TIELO L
V1 L 0 DC 0
.ENDS TIELO
