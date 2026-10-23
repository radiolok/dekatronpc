# Harwell Dekatron Computer (1951): what is useful for DekatronPC

Source: R. C. M. Barnes, E. H. Cooke-Yarborough, D. G. A. Thomas, "An Electronic Digital
Computor Using Cold Cathode Counting Tubes for Storage", Electronic Engineering, August 1951.
Copies: doc/Harwell-ee-1951-txt.pdf (retyped text with figures 1–8),
witch_dev/documentation/harwell-ee-1951-txt (plain text).

The machine (later WITCH) has 90 stores of 8 digits + sign on dekatrons, relay sequence
control, and a pulse-train arithmetic unit. Most of the article covers relay sequencing and
decimal arithmetic that DekatronPC does not need, because its counters are reversible and
it executes Brainfuck. Three points apply directly to the dekatron stack, and a few are
background for the loader and the tube boards.

## 1. Gate one guide per decade, not two (tube count, REQ-PULSE-007, REQ-MOD-009)

Harwell selects a store by coincidence. The "tens" relay connects Guide 2 of **all 90
dekatrons** in a group of ten stores to the pulse lines. The "units" relay connects Guide 1
only to the selected store. "Only those of the selected address receive pulses on both
guides and the position of the discharge can change only in this one address." The article
also states: "If pulses are applied to one guide only, the discharge returns to the same
cathode after each pulse."

The same applies to one counter in DekatronPC. Today every DekatronModule has two
`GUIDE_EN_J2` cells (one per guide), which makes 30 cells for 15 decades (IP 5, Loop 2,
AP 5, Data 3). If `GuideB` goes ungated to every decade of the counter and only `GuideA`
passes through the J2 gated by `En`, then:

| Direction | Selected decade (En = 1) | Other decades (En = 0) |
|---|---|---|
| Forward: A, then B | A, B → +1 | only B in phase 2 → back to the same cathode within phase 3 |
| Backward: B, then A | B, A → −1 | only B in phase 1 → back to the same cathode within phase 2 |

The tube model already supports this: DekatronTubeV2 says "только B и снятие -> возврат на
исходный катод". The carry chain is unaffected because `en_chain` is built from the
registered `zeroes_q`/`nines_q`, not from live cathodes, and an unselected decade is back
on its main cathode by the next `Clk` edge. This needs the same condition as a normal step:
the fall window (phase 3) must hold `FALL_STEP_HS` (REQ-PULSE-002).

Estimate: **−15 tubes** (one J2 per decade). This is the same +15 that the owner's
correction added in §17.7 of doc/tube_count_reduction.md, recovered in another way.

Costs and risks:
- The shared `GuideB` driver of a counter now drives up to 5 guide groups. Its load stays
  small next to Harwell's 90 tubes on one line, but it needs to be accounted for in
  `vtube_timing.json`.
- Every decade of the counter flickers to a guide on every step. Readout is not affected
  (`Out` is only valid on the edge), but the panel glow and guide-cathode wear change.
- It must be confirmed on the experimental A110 cell that a single guide pulse at 1 MHz
  reliably returns the discharge (OPEN-013/014).

Status: proposal; the owner decides (it changes REQ-PULSE-007).

Owner, 2026-10-23: Harwell only counts forward, so an ungated guide B may not carry over
to a reversible counter. Reply: direction is set only by the order of A and B in the
selected decade (REQ-PULSE-003). An unselected decade sees B alone in both directions
(phase 2 forward, phase 1 backward), and a lone guide pulse returns the discharge whatever
the counting direction. DekatronTubeV2 already encodes this: from a main cathode `gb && !ga`
gives `3k -> 3k-1` (MOVE_BACK), and with no guides `on_gb` gives `3k-1 -> 3k` (MOVE_FWD).
**Rejected by the owner, 2026-10-23:** two J2 keys per decade stay. The four counters
sit in different boxes, and every decade is the same board (unification). TRS REQ-PULSE-007.

## 2. Guide overlap vs. gap (OPEN-013)

On the guide pulse timing (Fig. 3: two 1.5 ms pulses, guides rest at +60 V and swing to
−60 V): "It is not necessary for the two guide pulses to overlap, but it is important that
any time interval between the end of the first pulse and the start of the second should not
be comparable with the de-ionization time of the Dekatron tube. A small overlap has been
provided as a precaution against possible failures."

DekatronPC treats it the other way round. DekatronPhaseGen raises `$error` on a Phase1/Phase2
overlap ("Фазы не должны перекрываться ни при каких условиях"), and DekatronTubeV2 treats
`guides_both` as illegal: the discharge does not move and `illegal_q` is set. Per Harwell,
the dangerous case is a gap between the phases, when the discharge starts falling back from
guide A, not an overlap. With the 3/3/4 split, Phase1 and Phase2 are adjacent, so a
real RC timing circuit can produce either a small gap or a small overlap at the junction.

Proposal for OPEN-013 calibration:
- Measure both cases on the experimental cell: a gap of tens of ns and an overlap of tens of
  ns at the A→B junction.
- If overlap is harmless, as Harwell found, make a small overlap the design margin. In the
  model, allow `guides_both` while the discharge is on a guide (stay there, move to the
  second guide when the first one is released), and relax the PhaseGen check to "no gap
  longer than X".

Status: a question for calibration. The model does not change until the measurement is done.

Owner, 2026-10-23: the guide pulses must overlap. Guide A is t0–t3 and guide B is t3–t6,
and in the real circuit the edges overlap at t3. This also settles the gap that
doc/vtube_sdf_timing.md §3.2 found in the netlist: Phase2 = `Win12 & ~Win1` starts 150 ns
after Phase1 ends because it passes through NOT + AND.

**Done 2026-10-23 (TRS v0.11, REQ-PULSE-008):**
- `DekatronPhaseGen`: Phase2 is its own `OneShot`, started by `Impulse` with the new
  `FALL = 1` parameter on the fall of Phase1. The NOT + NOR2 are gone (≈ −1.5 tubes per
  counter by liberty area; synthesis not rerun). In exchange there is one more timing
  element (a differentiating RC on the trailing edge), which ABC does not count. The overlap
  `$error` became a gap `$error`. The phases now touch at the same instant in both models;
  the lengths have not changed.
- `DekatronTubeV2`, `DekatronTubeDelay`, `DekatronTubeV2_assertions`: both guides at once
  are legal while the discharge is on a guide (it stays, then moves on when the first guide is
  released). Both guides while the discharge is on a main cathode are still an error.
- `DekatronTubeV2_tb`: UT-GUIDE-002 is now the legal case. UT-GUIDE-003/004 step with a 1 and
  2 hsClk overlap A→B and B→A. The header comment was being parsed as a Verilator
  metacomment, so the testbench did not build; it is fixed, and the testbench needs
  `-CFLAGS -fcoroutines` with g++ 11 and `+verilator+error+limit+100000` at run time.
  Three failures (UT-RSTN-005, UT-RSTN-006, UT-PERF in FAST) are the same as at HEAD and are
  not related to this change.
- cocotb `test_pulse_sender`: "no overlap" became "no gap"; 4/4 pass.
- Icarus, clocked and delay models: Dekatron, Counter, IpLine, ApLine, MachineCtrl,
  DekatronPC on helloworld and program.bfk all pass. `synth_sim.sh -d Dekatron` and
  `-d Counter` pass. The Counter netlist's PhaseGen holds only the timing elements.
- Sheet 2 of the schemes has been redrawn; doc/vtube_sdf_timing.md §3.2 is marked resolved.
  Finding §3.1 there is still open.

## 3. Random start position after power-on

"…the Dekatron tubes may light in any position." Harwell clears every store by a transfer
cycle after switch-on. DekatronPC has an `INIT_DIGIT` parameter (the initial position in the
model) and the hard_rst/soft_rst lines held by the panel time relay. The real machine
therefore needs a guaranteed reset pulse on power-up, through the same relay, before the
first instruction. Otherwise the counters start from arbitrary values. It is worth adding a
test that starts the model from a random `INIT_DIGIT` and checks that a Hard Reset brings
every counter to its reset value (IP = 99900, the rest 0).

Owner, 2026-10-23: confirmed. Every dekatron lights at random, which is why the reset exists:
the reset line cuts all other cathodes off the circuit, so the discharge can only settle on
the intended one. In the model this is `reset0_i`/`resetN_i`.

**Done 2026-10-23 (TRS v0.11, REQ-DEK-017):**
- `define DEKATRON_RANDOM_INIT` puts each tube (`DekatronTubeV2`, `DekatronTubeDelay`) on a
  random main cathode (`$urandom % 10`) at time 0.
- `Counter_tb` has a second counter configured as IP (5 decades, `HARD_RST_D_CNT = 3`) and
  checks it after every reset: hard → 99900, soft → 0. Under the define it starts with a
  hard reset and then a soft reset. In the run used here the data counter lit at 996, outside
  0–255, and the reset still cleared it. This passes in both models, with and without the
  define, and `run_tests.sh -t`/`-d` now also run `Counter` with it.
- `DekatronPC_tb` on helloworld passes with a random start, because its initial Soft Reset
  clears everything. `IpLine_tb` and `ApLine_tb` tie the reset lines to 0, so a random start
  does not apply to them.

## 4. Background, no action now

- **Checked asynchronous sequence.** Each relay step is proven complete before the next one
  starts, and the machine stops on the first fault. This is the same idea as the Valid/Ready
  handshake (AGENTS §4) and confirms it.
- **2-out-of-5 tape code.** Digits are two holes out of five, the separator is one hole, and
  block marks are three holes. A skipped or doubled tape row turns a digit into a separator
  or the reverse, and this is detected. This is a possible integrity check for the external
  loader or punch (REQ-AUTH allows non-tube loaders); BF opcodes fit in 10 of the 2-of-5
  codes plus separators.
- **Reading by rotation.** Ten guide pulse pairs turn the discharge one full revolution, and
  the pulse on the single output cathode splits the train into digit and complement. This
  needs only a zero-cathode tube and no positional decoder, but it costs 10 steps per read.
  DekatronPC reads all cathodes within one clock, so this does not apply.
- **Translator (GS11A + metal rectifiers → 2-of-5 code).** It uses a diode matrix in the
  codec, which REQ-AUTH-002 forbids in the compute path, so it is only a historical
  reference.
- **Cold-cathode triode practice.** HT is removed from the trigger triode's anode between
  operations "to minimize the chance of spurious triggering". This is a note for tube
  boards with gas triodes, if any appear.
- **Nines complement with end-around carry, sign tube, multiplication/division by repeated
  addition, random rounding from a free-running scale of two.** These are not needed
  because the counters are reversible and the ISA is Brainfuck.

## Questions for the owner

1. Item 1: should one ungated guide per decade be tried in the RTL (−15 tubes, changes
   REQ-PULSE-007)?
2. Item 2: should "overlap vs. gap at the A→B junction" be added to the OPEN-013 calibration
   plan?
3. Item 3: should a power-up reset test from a random dekatron position be added?
