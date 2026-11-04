# What each non-Brainfuck instruction costs in tubes

Date: 2026-11-02. Branch `tube_opt_1000`. Context: the road below 1000 tubes
(doc/tube_count_1000.md §7, TRS §22).

> **Note (branch `ISA16`, TRS v0.42).** The owner chose the 16-instruction set of
> doc/isa16.md. The `DPC_CUT_*` harness described below was removed from the RTL;
> the numbers stay as a reference, and §5 no longer reproduces on the current tree.

## 1. Method

Every instruction outside plain Brainfuck is wrapped in a `DPC_CUT_<NAME>` define.
A define turns its opcodes into NOP in **all three** blocks that decode them, so the
saving is not underestimated:

| Define | Opcodes | Blocks touched |
|---|---|---|
| `DPC_CUT_HALT` | 0x01/0x11 HALT (and its bell) | MachineCtrl |
| `DPC_CUT_BELL` | 0x02 BELL | MachineCtrl |
| `DPC_CUT_SOT` | 0x05 SOT | MachineCtrl |
| `DPC_CUT_EOT` | 0x04 EOT in the load stream, SoftRstOnEOT | MachineCtrl, IpLine |
| `DPC_CUT_SOTEOT` | both of the above (rtl/parameters.sv) | |
| `DPC_CUT_DLOOP` | Debug `{ }` test AP: they test the cell instead | MachineCtrl |
| `DPC_CUT_CLRL` | 0x08 CLRL | MachineCtrl, IpLine |
| `DPC_CUT_CLRI` | 0x09 CLRI | MachineCtrl, IpLine |
| `DPC_CUT_CLRD` | 0x0A CLRD (Debug) | MachineCtrl, ApLine |
| `DPC_CUT_CLRA` | 0x0B CLRA | MachineCtrl, ApLine |
| `DPC_CUT_HRST` / `DPC_CUT_SRST` | 0x0C / 0x0D | MachineCtrl |
| `DPC_CUT_ISA` | 0x0E/0x0F ISA0/ISA1 (in both modes and in loading) | MachineCtrl |
| `DPC_CUT_BFCLRD` | 0x1A `[-]` | MachineCtrl, ApLine |
| `DPC_CUT_CLRML` / `LOAD` / `STORE` | 0x1B / 0x1C / 0x1D | MachineCtrl, ApLine |

The defines are off in every normal build. They stay in the RTL as the experiment
harness. Verilator lint is clean with none of them and with all of them (only expected
UNUSED warnings). Nothing was simulated with a cut: these are synthesis numbers only.

Flow: `synt_dpc.tcl` (the `run_tests.sh -s` flow), one block per run, `-D DPC_CUT_*`.

**Noise.** Seeds alone are not enough. Changing the text of *any* module shifts the
global Yosys `autoidx`, which renames cells and reorders the ABC input. A block whose
RTL did not change moved by up to ±10 tubes in its 16-seed mean (IpLine in two
configurations with identical IpLine RTL: 366.6 vs 376.3). The final wave therefore
also perturbs `autoidx` on purpose: an unused dummy module of 0/7/14/21/28 lines is
read first. Every configuration is 5 perturbations × 8 seeds = 40 runs per block, and
only the touched blocks are synthesized. Base means: MachineCtrl 307.7, IpLine 380.4,
ApLine 469.7. The standard error of a total is 1–2 tubes.
With the defines off, the restructured RTL (split case items, separate `op_*` wires)
against HEAD 73d16e2 on the same 8 seeds, without the perturbation: MachineCtrl
309.6 vs 307.6, IpLine 385.6 vs 380.1, ApLine 470.2 vs 464.0. The ApLine gap of
+6 sits at the edge of the autoidx noise. All Δ in §2 are measured against the
restructured base, so the gap does not affect them.
Totals: waves 1–4, about 1250 runs (8–16 seeds); wave 5, 1640 runs. Each block
synthesizes in about 4 s.

## 2. Results (wave 5, 40 runs per block, Δ tubes against base)

| Cut | MC | IpLine | ApLine | **Total** | ±SE |
|---|---|---|---|---|---|
| ALL (16 defines) | −51.5 | −22.2 | −21.9 | **−95.6** | 1.4 |
| EOT | −9.2 | −17.3 | | **−26.5** | 1.6 |
| CLRL | +0.4 | −14.8 | | **−14.4** | 1.6 |
| CLRML + LOAD + STORE | −0.2 | | −11.8 | **−12.0** | 1.1 |
| HRST + SRST | −8.8 | | | **−8.8** | 0.9 |
| CLRML | +1.5 | | −9.3 | −7.8 | 1.1 |
| CLRA | +1.5 | | −8.4 | −6.9 | 1.0 |
| ISA0/ISA1 | −6.6 | | | −6.6 | 0.8 |
| SOT | −6.0 | | | −6.0 | 0.9 |
| HALT | −6.0 | | | −6.0 | 0.9 |
| CLRL + CLRI | −2.2 | −2.4 | | −4.6 | 1.4 |
| HRST | −3.3 | | | −3.3 | 0.9 |
| DLOOP | −2.7 | | | −2.7 | 0.9 |
| CLRD (Debug) | −0.4 | | −2.0 | −2.4 | 1.1 |
| LOAD | +2.1 | | −4.4 | −2.3 | 1.2 |
| SRST | +0.3 | | | +0.3 | 1.0 |
| BELL | +0.4 | | | +0.4 | 0.9 |
| `[-]` | +2.8 | | −0.5 | +2.4 | 1.1 |
| STORE | +1.9 | | +2.1 | +4.0 | 1.0 |
| CLRI | +1.9 | +2.8 | | +4.7 | 1.6 |
| **R_Ce** = SOT CLRL HRST SRST | −13.1 | −13.8 | | **−26.9** | 1.7 |
| **R_BCe** = R_Ce + BELL CLRML LOAD STORE | −19.2 | −13.7 | −11.9 | **−44.8** | 1.8 |

Observations:

- **EOT is the most expensive instruction (−26.5).** Most of it sits in IpLine: the
  5-bit compare of `{insn_mode, insn_in}`, the `eot_q` trigger, the gating of
  `mem_valid`, plus the EOT branch and SoftRstOnEOT in MachineCtrl. The SOT opcode
  alone costs only 6.
- **CLRL (−14.4) is almost all IpLine**: the `S_CLR_LOOP` state and the set-to-zero
  path of the Loop counter.
- **CLRI costs nothing, and cutting it makes things worse (+4.7).** Cutting CLRL and
  CLRI together saves only 4.6 against 14.4 for CLRL alone. Cause: when states become
  unreachable, Yosys `fsm_recode` re-encodes the IpLine FSM from the hand-picked
  4-bit codes to sequential 3-bit codes (log: `0000 -> 000, 1000 -> 001, …`). The new
  encoding is worse. Every cut that removes IpLine states hides the same effect, so a
  state-code search after a cut (as in doc/tube_count_reduction.md §17) would give a
  few more tubes.
- Several ApLine cuts are cheap or negative (`[-]`, STORE, LOAD alone): the ApLine
  decoder shares terms, so one opcode removed leaves the others' logic in place.
  CLRML + LOAD + STORE together give −12.
- The cuts add up roughly: the singles sum to about −85; ALL gives −95.6.

## 3. What the bootloader and the owner's decisions allow

The bootloader (`rtl/programs/bootloader.bfk` = `DA0B<D{0B<D}BH`) uses **ISA0/ISA1,
CLRA, CLRD (Debug), `{ }` (AP test) and HALT**. Cutting any of these needs a new
bootloader. Each is worth at most 6–7 tubes.

TC-O7 was rejected by the owner (2026-11-01): program loading stays in the machine,
and the machine must start up by itself through SoftRstOnEOT. **EOT therefore cannot
simply go.** It could be replaced by a separate "end of load" line from the external
loader (allowed to be non-tube, REQ-AUTH). The loader would drive it like the panel
key `key_insn_loading_stop` today, and MachineCtrl would apply SoftRstOnEOT to that
line. This changes the Emulator ↔ DekatronPC interface (TRS Appendix B) and needs the
owner. The cost of the new line in MachineCtrl has not been measured.

Unused by the bootloader and not touched by TC-O7:

| Set | Δ | What is lost |
|---|---|---|
| CLRL | −14 | Loop counter and the overflow flag clear only on reset (REQ-CNT-007 recovery = reset) |
| HRST + SRST opcodes | −9 | Resets only from the panel and on EOT |
| SOT opcode | −6 | Loading starts only from the panel key or loader line |
| CLRML + LOAD + STORE | −12 | BF extensions: explicit MemLock control |
| **all of the above (R_BCe)** | **−44.8** | |
| + EOT as a loader line | ≈ −26 more, minus the cost of the line | Appendix B change |

Against the current 1150.1 (TRS v0.40, with the dekatron module), R_BCe gives
≈ 1105. EOT moved to a line would give ≈ 1080.

## 4. Open questions for the owner

1. Which of the R_BCe set may go (each is a change to the ISA table and the TRS)?
2. Should EOT become a loader line (Appendix B, breaking change)?
3. Is a bootloader rewrite allowed, for example ISA switching through SRST instead of
   ISA0/ISA1? That is worth only 6–7 tubes.

## 5. Reproducing

Scripts are in the session scratchpad and are not committed. The essence:

```sh
cd rtl/run
echo "tcl synt_dpc.tcl <list> MachineCtrl -D DPC_CUT_EOT" | DPC_ABC_SEED=0 yosys
.venv/bin/python dpc_stat.py -j MachineCtrl.json -l ../../sch/logic/vtube_cells.lib
```

`<list>` is DPC.files with absolute paths, optionally with a dummy module file first
(the autoidx perturbation). `synth_seeds.sh -a "-D DPC_CUT_X"` works too, but without
the perturbation it reports ±5 tubes of noise as signal.
