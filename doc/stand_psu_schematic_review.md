# Test stand power supply: schematic review

Date: 2026-10-07. Scope: KiCad project `sch/stand/stand.kicad_pro` (was `sch/stand/stand/` at the first review)
(root sheet `stand.kicad_sch` plus three instances of `psu.kicad_sch`:
PSU_200v, PSU_120v, PSU_80v). The side files `stand_v2.kicad_sch` and
`untitled.kicad_sch` are not part of the project hierarchy and were not reviewed.
Requirements: TRS §15 (REQ-STAND-*, REQ-PWR-*, REQ-SAFE-*).

Method: `kicad-cli` 10.0.6 (ERC, netlist export, PDF plot, DRC with schematic
parity), then a manual net-by-net reading of the exported netlist against the
datasheets (TL494, TL431, PC817, LM317, LM337). No simulation was run. The AC
input voltages of the converters are not stated in the schematic, so the
numbers below that depend on them are given as formulas plus an example.

## 1. What the schematic contains

| Block | Parts | Function |
|---|---|---|
| Root, top | J10, D34–D37, C40, U10 LM317, R57/R58/R59, J14 (6.8k pot) | Positive linear rail, about +5.1…+29.8 V |
| Root, bottom | J11, D39–D41/D44, C42, U11 LM337, R62/R60/R61, J15 (6.8k pot) | Negative linear rail, about −5.1…−29.8 V |
| psu.kicad_sch ×3 | Bridge D1–D4 + C1 330 µF/315 V; TL494 push-pull, 2× IRFBE30S, EL33 transformer; bridge HER108 + C14; TL431 + PC817 feedback; Q1 + 1 Ω current limit; 12 V aux via R1, 18 V zener, 7812 | Isolated adjustable HV outputs, nominally 200 / 120 / 80 V |

The ±regulators, protection diodes, ADJ bypass capacitors and their discharge
diodes, bridge orientations and capacitor polarities are all correct (checked
pin by pin, including the LM317 1-ADJ/2-OUT/3-IN and LM337 1-ADJ/2-IN/3-OUT
TO-220 pinouts, TL431LP TO-92 1-REF/2-A/3-K and 2N3904 EBC footprint).

## 2. ERC result

172 violations, of which 163 are only "library not in the current configuration"
(the global symbol and footprint tables are not set up on this machine; not a
design fault). The remaining 9:

- 8 × `power_pin_not_driven` (U10/U11 IN, U3/U4/U7 IN, U1/U4/U7 GND). The rails
  come from rectifiers, not power symbols. Cosmetic: add `PWR_FLAG` symbols.
- 1 × `unconnected_wire_endpoint`: a 3.8 mm stub at (234.95, 81.28)–(234.95, 85.09)
  in `psu.kicad_sch`, next to R9/OC1. The R9→OC1 connection itself is fine;
  delete the stub.

So ERC finds no wiring errors. The real problems are in circuit design and are
listed below.

## 3. Findings, by severity

### Critical: the converter cannot work as drawn

**C1. The voltage loop has the wrong sign (positive feedback).**
The two TL494 error amplifiers are disabled (1IN+/2IN+ at GND, 1IN−/2IN− at
REF), so FB (pin 3) is set only by R13 (4.7k, FB→REF 5 V) and the PC817
transistor (collector OC1.4→FB, emitter OC1.3→GND). In the TL494, higher FB
means a shorter pulse (≈0.5 V gives maximum duty, ≈3.5 V gives zero).
- Output above setpoint → TL431 conducts → LED on → transistor pulls FB low →
  **maximum duty** → output rises further.
- Output below setpoint (including start-up) → TL431 off → LED off → FB pulled up
  to about 5 V → zero duty.

So the loop either does not start, or (with FB partly loaded by the error-amplifier
sink current) starts, then latches at maximum duty with no regulation. The output
then rises to Vbus·Ns/Np_half (≈1.12·Vbus), limited only by the transformer.
Fix: swap the roles: transistor collector to REF (pin 14), emitter to FB,
R13 from FB to GND (the usual TL494 + opto arrangement).

**C2. The current limit is wired for the wrong loop sign, and becomes wrong once
C1 is fixed.** Q1 (base at J2.1, emitter at the return, sensing R24 = 1 Ω)
pulls TL431 REF low on overcurrent. With today's inverted opto this shuts the
converter down, which is the right effect for the wrong reason. After the C1 fix,
pulling REF low turns the LED off, which gives **maximum** duty in overcurrent.
Fix: connect the Q1 collector to the TL431 cathode (U2-K), in parallel with the
TL431, so that overcurrent drives the LED on. Also add a base resistor (≈100–470 Ω).
The trip point is about 0.6–0.7 A, far above REQ-PWR-004's 0.1 A. For a tube
stand, R24 ≈ 6.8 Ω (≈0.1 A) is probably what is wanted. **Question to the owner.**

**C3. The TL431 cathode sees the full output voltage.** The LED and TL431 are fed
straight from +Vout through R9 (18k). The TL431 is rated V_KA ≤ 37 V. When it is
off (start-up, overcurrent, transients) its cathode floats to almost Vout
(80–200 V). When it regulates, V_KA = Vout − V_LED − I_LED·R9. Only about 1 mA
of LED current is needed to pull FB through R13, so V_KA would sit near Vout.
This is an overvoltage on the TL431 in every instance. Fix: supply the LED +
TL431 from a low-voltage rail derived from Vout (for example an
R + 12–15 V zener shunt, or a small transistor follower), with R9 recalculated
for 1–5 mA. The same rail can then power Q1's collector path.

**C4. The 12 V auxiliary supply cannot deliver the gate-drive current.** The TL494
VCC comes from the HV bus through R1, an 18 V zener (D5, DO-35 ≈ 0.5 W) and a
7812. The load on it is dominated by the gate pull-downs R20/R21 = 68 Ω on E1/E2:
when an output is on, (12 − ~1.5) V / 68 Ω ≈ 154 mA. With about 45 % duty per
output, that averages ≈ 140 mA, plus about 10 mA for the TL494: ≈ 150 mA.
R1 then dissipates (Vbus − 18 V) × 0.15 A. At Vbus = 200 V that is about 27 W,
in a DIN0918 (≈2 W) footprint. R1's value is also unspecified (value "R" in all
three instances). As drawn, the rail will collapse, and the MOSFETs will run in
linear mode at low gate voltage. Fix: power the 12 V from a separate
low-voltage winding (the stand already has AC inputs for the ±rails), and raise
the pull-downs to about 1 kΩ with a PNP turn-off transistor (or a diode +
pull-down) per gate, so gate drive costs milliamps, not 150 mA.

**C5. The 4.7 nF snubbers burn tens of watts.** C3/C13 (4.7 nF/630 V) +
R22/R23 (1k, DIN0414 ≈ 1 W) + D7/D6 sit from each drain to GND. In a
centre-tapped push-pull each drain swings 0 → 2·Vbus. A RC/RCD snubber
dissipates about C·V²·f: at Vbus = 200 V, 4.7 nF · (400 V)² · 50 kHz ≈ 38 W
per transistor (bounded a little by R·C = 4.7 µs against a 10 µs half-period).
In addition, the diode is reversed relative to a classic RCD turn-off snubber:
anode is at GND, so it does not speed up charging on turn-off. It does let the
capacitor dump CV² straight into the MOSFET at turn-on, with no resistance.
Fix: a 100–470 pF RC snubber sized against the measured ringing, or an RCD
clamp from drain to +Vbus; in any case, recalculate R power.
Also: the capacitor voltage rating of 630 V is below 2·Vbus + spike as soon
as Vbus > ~280 V.

### Major: values and requirements

**M1. Per-instance values exist only as text notes.** The notes on the PSU sheet
give R7 = 91k / 51k / 24k, R9 = 18k / 11k / 5.6k and transformer turns per
version, but the components carry 91k and 18k in all three instances, and the
BOM/netlist lists them 3×. Use separate sheet files (or KiCad variants) so the
BOM is correct.

**M2. The output range does not reach the nominal voltage in any version.**
Vout = 2.5 V · (1 + R7 / (R8 + R_pot)), with R8 = 1.5k and R_pot = 0…6.8k
(J4 "Voltage", with pins 1–2 joined: a rheostat in the lower leg).

| Version | R7 (note) | R_pot = 0 (max) | R_pot = 6.8k (min) | Needed R8 for nominal |
|---|---|---|---|---|
| 200v | 91k | 154 V | 30 V | ≤ 1.15k |
| 120v | 51k | 87.5 V | 17.9 V | ≤ 1.08k |
| 80v | 24k | 42.5 V | 9.7 V | ≤ 0.78k |

REQ-PWR-004 (50–200 V) is therefore not met. Fix: R8 ≈ 1.0k with a smaller pot,
or move the pot into the upper leg. With a pot in the lower leg, a broken wiper
or unplugged J4 sends REF high: after the C1 fix this shuts the converter down
(safe), but with today's wiring it gives maximum output.

**M3. Linear rail range: a disconnected pot gives the full input voltage.**
On the LM317 (and the LM337 mirror) the pot J14 is in parallel with R58 = 12k.
The range is 1.25·(1 + (R58‖R_pot + 680)/220) ≈ 5.1…29.8 V. If J14 is
disconnected, the setpoint becomes 73 V, so the output goes to Vin − dropout.
If this rail heats tubes (6.3 V), that is an overvoltage on every heater.
Prefer a topology where an open pot gives the minimum voltage. Note also:
LM317/337 are ≤ 1.5 A with 1 A 1N4007 bridges, so neither rail meets
REQ-PWR-001 (6.3 V, ≥ 6 A). The LM337 range (≥ −30 V, 40 V in-out limit) does
not cover REQ-PWR-006 (−20…−70 V). **Question to the owner:** which rails
feed the heaters and the bias, and are REQ-PWR-001/005/006 supposed to be on
another board?

**M4. Bus capacitor rating vs input.** C1/C4/C28 are 330 µF/**315 V**. If the
200v converter is fed from 220–230 V mains directly, the bus is 311–325 V
nominal and about 357 V at +10 % mains, above the rating. The turns notes
(Ns/Np_half ≈ 1.12 for all three versions, Np = 50/30/20) suggest each version
gets a different, lower AC input, but that is not written anywhere.
**Question to the owner:** what AC voltage goes to J1/J3/J7, and is it from an
isolating transformer?

**M5. Shared heatsink.** On the PCB, `radiator1` sits between U10 (LM317, tab =
OUT) and U11 (LM337, tab = IN). On one bare heatsink these tabs short +Vout to
the negative input. REQ-SAFE-005 requires insulated flanges; nothing in the
schematic or PCB records the insulators. Add a note or BOM line (mica/silpad +
bushing) for both, and for the 7812s if they share it.

### Minor

- No fuse, inrush limiter (NTC) or EMI filter on any input. With 330 µF on a
  rectified high-voltage bus, the inrush current is large.
- No HV presence indicator (REQ-SAFE-002), and no explicit bleeder on the
  330 µF bus (REQ-SAFE-004): it only discharges through the R1/zener path. The
  output bleeds through R7 and R9 only.
- Soft-start (C7 1 µF, R10‖R11 ≈ 0.9 kΩ) is ≈ 0.9 ms, short for charging an
  82 µF/200 V output. Consider about 10× more.
- DTC rest level 5·1k/11k = 0.45 V: dead time is fine. Oscillator
  RT = 10k, CT = 1.1 nF: ≈ 100 kHz, 50 kHz per switch, reasonable for EL33.
- No primary-side current sensing: a transformer short or saturation is caught
  only on the secondary (C2), and only after the fix.
- R8/R34/R49 values are written `1.5к` with a Cyrillic "к". BOM tools and
  SPICE will not parse it; use `1.5k`.
- R1/R2/R3 value is `R` (unspecified).
- Symbol `Transformer_SP_1S` is described as 1 secondary, matching the
  netlist. D6/D7 labels overlap the `IRFBE30S` text on the sheet; cosmetic.

## 4. PCB parity (outside the schematic scope, noted for completeness)

DRC with schematic parity (`kicad-cli pcb drc --schematic-parity`, library
warnings ignored): 5 unconnected items, among them the **positive output
rectifier cathodes** D8–D10, D19–D21 and D30–D32 not joined in all three
converters, a Q7 drain track ending at x = −423 mm (off-board), and a D39 pad.
The 4 "extra footprints" and 8 hole-clearance errors are the reference-less
mounting holes. 39 courtyard overlaps; HV creepage was not checked.

## 5. Suggested order of work

1. Decide the input voltages and current limits (M4, C2), and which rails serve
   REQ-PWR-001/005/006 (M3).
2. Rework the feedback: opto polarity (C1), Q1 to the TL431 cathode (C2),
   low-voltage rail for the TL431/LED (C3), R8 and the pot (M2).
3. Rework gate drive and the 12 V auxiliary supply (C4), and the snubbers (C5).
4. Split the PSU sheet per version (M1), fix values (`R`, `1.5к`), add PWR_FLAGs,
   delete the wire stub.
5. Then fix the PCB opens, and check HV creepage and heatsink insulation.

Reproduce: `kicad-cli sch erc --severity-all stand.kicad_sch`,
`kicad-cli sch export netlist stand.kicad_sch`,
`kicad-cli pcb drc --schematic-parity stand.kicad_pcb` in `sch/stand/stand/`.

## 6. Re-check after the owner's fixes (2026-10-07)

The project moved to `sch/stand/` (the `stand/` subfolder is gone). The netlist
was re-exported and diffed against the first review; the changes are present in
all three instances.

| Item | Change in the netlist | Verdict |
|---|---|---|
| C1 | OC1 collector (pin 4) → REF, emitter (pin 3) → FB, R13 4.7k FB → GND | **Fixed.** LED on → FB up → shorter pulse. |
| C2 | Q1 collector → TL431 cathode/LED cathode, base through R51 470 Ω | **Fixed.** Overcurrent now drives the LED on, so duty drops. Trip ≈ 0.6 A kept by owner decision (soft limit). |
| C3 | D38/D47/D48 18 V zener from the R9/LED-anode node to the output return | **Fixed** for the TL431 rating: V_KA ≤ 18 − V_LED ≈ 17 V. Remaining notes below. |
| C4 | none yet | Open; proposal below. |
| C5 | D7/D6 anode at the drain, R22/R23 drain → node, C3/C13 node → +Vbus | **Not fixed**, see below. |

**C3 notes.** (a) R9 now carries the zener current: at 200 V out,
(200 − 18)/18k ≈ 10 mA and 1.8 W in a DIN0516 (≈2 W): use 3 W or 2 × 9.1k.
D38 dissipates about 0.18 W: fine in DO-35. (b) The TL431 needs ≥ 1 mA
cathode current to regulate (datasheet I_min), but the LED needs only a fraction
of that to pull FB up. Add about 1 kΩ across the opto LED so the TL431 always
has its bias. (c) At low setpoints the R9 branch gives little current, for
example (30 − 18)/18k ≈ 0.7 mA at 30 V: then the lowest usable output is about
20–40 V. This is fine for the 200 V version, but check it when R9 is set per version (M1).

**C5 is still a dv/dt snubber, not a clamp.** R22 sits across D7, so the
capacitor charges through D7 on turn-off and discharges through R22 on
turn-on. Referenced to +Vbus, the node still swings from 0 to 2·Vbus each
cycle, so R22 still dissipates about ½·C·(2·Vbus)²·f ≈ ½ · 4.7 nF · (400 V)² ·
50 kHz ≈ 19 W at Vbus = 200 V. Two ways to fix it:
- **RCD clamp:** move R22 so it is across C3 (node → +Vbus) instead of across D7.
  C then charges to about Vbus + overshoot and stays there, so it only absorbs
  the leakage spike. R dissipates about (Vbus + ΔV)²/R, so it has to be large:
  for example 10 nF/630 V, 47–100 kΩ / 2 W. One clamp (C‖R) can serve both
  drains through D6 and D7.
- **Keep the RC/RCD snubber:** but with C ≈ 100–220 pF (≈ 0.4–0.9 W).

### C4 proposal: buffer the TL494 outputs

The 150 mA comes from the 68 Ω static pull-downs, not from the MOSFETs.
IRFBE30 gate charge is about 78 nC, so 78 nC · 50 kHz ≈ 4 mA per transistor
on average. Put an NPN/PNP emitter-follower pair (BC337/BC327 or
2N4401/2N4403) behind each output:

```
            VCC 12 V
               |
               C   NPN
 E1 ──┬─────── B
      |        E ──┬── R18 10 Ω ──┬── G (Q4)
      |        E ──┘              |
      |        B   PNP          10k (G–S)
      |        C                  |
    R20 2.2k   |                 GND
      |       GND
     GND
(the two bases are joined at E1; the two emitters are joined)
```

- Each TL494 output now sources only about 5 mA into R20, against 154 mA before.
- Turn-off goes through the PNP at hFE × 5 mA ≈ 0.5 A peak. This is much
  faster than the 68 Ω pull-down was.
- The 10 kΩ gate–source resistor at each MOSFET keeps it off while VCC is absent.

12 V budget after the change: TL494 ~7 mA, 7812 quiescent ~5 mA, gates ~8 mA,
R20/R21 ~5 mA, REF loads ~1.5 mA, so about 25–30 mA.
Then R1 = (Vbus − 18 V)/30 mA, and P(R1) = (Vbus − 18 V) · 30 mA: for example
6.2 kΩ and 5.5 W at Vbus = 200 V, or 9.7 kΩ and 8.8 W at 310 V. Use a
wirewound part of ≥ 10 W.
D5 then has to absorb the full R1 current whenever the TL494 is not switching:
18 V · 30 mA = 0.54 W, more than a DO-35 can take, so use a 1 W part
(1N4746A, DO-41).
Optional:
- Replace the 18 V zener + 7812 with a single 15 V / 1.3 W zener
  (1N4744A). That saves the 7812's ~5 mA.
- The usual way to remove the R1 heat entirely is a few-turn auxiliary winding
  on T1. R1 then only starts the converter (a few mA), and the winding powers
  VCC once it runs. It stays inside the converter, with no external supply.

### Still open from §3

M1 (per-instance values, R7/R9 are still 91k/18k in all instances),
M2 (R8 1.5k caps the outputs at 154/87/42 V), M3–M5, the minor items, and the
3.8 mm wire stub at (234.95, 81.28) in `psu.kicad_sch`.

## 7. Second re-check (2026-10-07)

Netlist diffed against §6.

**C4: fixed.** Each TL494 output drives a BC337/BC327 pair: the bases are joined
at E1/E2 with R20/R21 = 1k to GND, the NPN collector goes to VCC and the PNP
collector to GND, and the joined emitters drive R18/R19 10 Ω to the gate. The
CBE TO-92 pinout matches the BC337/BC327 parts. Output drive is now
≈ 10 mA per TL494 output instead of 154 mA. One leftover: there is no
gate–source resistor at Q4/Q5 (about 10k), so a gate floats while VCC is absent.

**C5: fixed.** There is now one shared RCD clamp: D6 and D7 run from the drains
to a common node, with C3 10 nF/630 V and R22 47k in parallel from that node to +Vbus.
C13/R23 were removed. R22 dissipates about (Vbus + overshoot)²/47k: about 1.0 W
in the 200v version, which is at the limit of the DIN0414 footprint (≈1 W). Use
2 W there; the 120v and 80v versions are at ≤ 0.45 W.

**M1: accepted by owner.** The three copies are soldered by hand with
per-version values from the sheet notes, so the BOM showing 91k/18k ×3 is known
and acceptable.

**M4: closed.** The inputs are now documented: J10/J11 24 V RMS, and J1 136 / 80 / 56 V RMS for
the 200v / 120v / 80v converters. Peak bus ≈ √2·V − 1.4 V:

| Version | Vbus nominal (+10 %) | Max output ≈ Vbus·Ns/Np − 2.4 V, nominal / −10 % mains | R1 for 30 mA, P(R1) |
|---|---|---|---|
| 200v | 191 V (212 V) | 211 V / 190 V | 5.6k, ≈ 5.2 W |
| 120v | 112 V (124 V) | 124 V / 111 V | 3.0k, ≈ 2.8 W |
| 80v | 78 V (86 V) | 87 V / 78 V | 2.0k, ≈ 1.8 W |

- All bus capacitors (315 V), output capacitors (315 V) and the 630 V clamp
  capacitor have margin. The IRFBE30 drain stays ≤ 2·212 V + spike.
- With no output choke, the output peak-charges, so the maximum is set by the
  turns ratio, not the duty. Each version reaches its nominal voltage with about 5 % headroom
  at nominal mains, but not at −10 % mains or under heavy load.
- R1 can now be sized (the table assumes the 25–30 mA budget from §6). Pick
  about 2× the power rating.
- **D5 (18 V, DO-35 0.5 W) is still too small.** While the converter idles
  (output at setpoint, no load, pulses near zero) the zener takes all of R1's
  current: 18 V · 30 mA ≈ 0.55 W, more at +10 % mains. Use a 1 W zener
  (1N4746A, DO-41).
- ±rails: 24 V RMS gives ≈ 32.5 V DC (36 V at +10 %). This is within LM317/337's
  40 V input–output limit across the whole 5–30 V range. At low output voltages
  the regulator dissipates (32.5 − Vout)·I, for example ≈ 26 W at 6.3 V/1 A, so the
  heatsink must be sized for that.

**M5: closed.** One of the two TO-220s is fully isolated (REQ-SAFE-005). The
heatsink is then at the other part's tab potential (LM317 OUT or LM337 IN,
≤ 36 V), so keep it off the chassis.

**Still open:**
- M2: R8 = 1.5k caps the outputs at 154 / 87 / 42 V. It needs R8 + R_pot,min ≤ 1.15k / 1.08k / 0.78k.
- M3: an open pot drives the LM317/337 rails to full input. Also unanswered: which rails cover REQ-PWR-001/005/006.
- Minor: R1 value still `R`, `1.5к` (Cyrillic), the 3.8 mm wire stub in psu.kicad_sch.
- New, minor: the transformer footprint link `User:EL33` does not
  exist in `User.pretty` (the file is `EL33_1Prx2+1S.kicad_mod`). The PCB still
  holds an embedded copy, but "Update PCB from Schematic" will fail on T1–T3.

## 8. Third re-check (2026-10-07)

Changes: R8 now has per-version values (1.1k / 1.1k / 0.82k), R1 has per-version
values (10k / 4.7k / 3k), and both have sheet notes. Owner information: heater
power goes from the transformer straight to the edge connectors
(REQ-PWR-001), and the 300–500 V dekatron supply is a separate PWM module
mounted on top of this board (REQ-PWR-005; the PCB has mounting holes for it).

**M2.** Range with R_pot = 0…6.8k: Vout = 2.5·(1 + R7/(R8 + R_pot)).

| Version | R7 / R8 | Range | Turns limit (nominal mains) | R8 for nominal |
|---|---|---|---|---|
| 200v | 91k / 1.1k | 31…209 V | 211 V | ≤ 1.15k: OK |
| 120v | 51k / 1.1k | 19…118 V | 124 V | ≤ 1.08k: **1.0k** |
| 80v | 24k / 0.82k | 10…76 V | 87 V | ≤ 0.77k: **0.75k** |

The 120v and 80v versions still stop 2–4 V short of nominal. Before tolerances
(TL431 ±1–2 %, resistors ±1 %) the 200v version sits at 209 V, and the turns ratio
leaves it only about 1 % headroom at nominal mains. So at its top setting it
runs near maximum duty (see the R1 note).

**M3: closed, no defect.** The divider is R57 (220 Ω, OUT–ADJ) over
R58 + R59 in series to GND. The pot (J14 pins 1–2 at ADJ, pin 3 at the
R58/R59 node) is **in parallel with R58**, so
V = 1.25·(1 + (R58‖R_pot + R59)/R57): 5.1 V at R_pot = 0, 29.8 V at 6.8k.
A disconnected pot leaves R58 + R59 = 12.68k, which gives a setpoint of 73 V.
The regulator cannot reach that, so it saturates at its input, ≈ 32.5 V − dropout
≈ 30 V. That is the same as the pot's top end. Heaters are not on these
rails, so this is harmless. The LM317/LM337 rails cover REQ-PWR-007
(+10 V/−20 V), but −30 V is the limit, so they **do not cover the −20…−70 V bias
(REQ-PWR-006)**. Question to the owner: where does the bias come from?

**R1 and the 12 V budget.**

| Version | R1 | I(R1) nominal | P(R1) nominal / +10 % mains | D5 idle, +10 % |
|---|---|---|---|---|
| 200v | 10k | 17 mA | 3.0 W / 3.8 W | 0.35 W |
| 120v | 4.7k | 20 mA | 1.9 W / 2.4 W | 0.41 W |
| 80v | 3k | 20 mA | 1.2 W / 1.5 W | 0.41 W |

- **R1 footprint:** DIN0918 (18 × 9 mm) is a ≈ 2 W body. The 200v R1 (3–3.8 W) and the
  120v R1 (≈ 2.4 W at high mains) are over it: use a 5 W part with its footprint
  (for example a cement/wirewound R_Axial_Power_L25.0mm).
- **D5:** idle dissipation is now ≤ 0.41 W, within the DO-35 0.5 W rating but with
  little margin when hot. A 1 W zener is still advisable, though no longer critical.
- **Budget at full duty is about 30 mA**: TL494 ~6 mA, 7812 quiescent ~5 mA,
  gate charge 2 × 78 nC × 50 kHz ≈ 8 mA, R20/R21 1k ≈ 10 mA, REF loads
  ≈ 1 mA. R1 now supplies only 17–20 mA. At light load this is fine (short
  pulses), but during start-up and near the top setting the 18 V node sags, the 7812
  drops out and gate drive falls below the 10 V the IRFBE30 needs. The 200v
  version near 209 V is the worst case. Cheapest fix: **R20/R21 → 4.7k**.
  Then the PNP still gets ≈ 2 mA of base current (≈ 200 mA turn-off peak),
  and the budget drops to about 22 mA. Optionally replace the 7812 with a 78L12
  (≈ 3 mA quiescent). For the 200v version, also consider R1 ≈ 8.2k / 5 W.

**Still open (minor):** a 10k gate–source resistor at each MOSFET; R22 2 W in the 200v version;
the `User:EL33` footprint link (file is `EL33_1Prx2+1S`); the wire stub
at (234.95, 81.28) in psu.kicad_sch; the REQ-PWR-006 bias source.

## 9. Bench fault: converter halted, FB ≈ 4 V (2026-10-25)

Symptom (owner): the channels worked on the first power-up. Now FB (TL494 pin 3)
sits at about 4 V, so duty is zero and there is no output. The PC817 transistor
does not ring out as shorted; R13 (FB → GND) is in place.

What the netlist says (channel 1; OC2/U6 and OC3/U9 are the same):

- FB is high only if something sources ≈ 0.85 mA (4 V / 4.7k) into it: the
  opto transistor (OC1.4 at REF → OC1.3 at FB), or the TL494 error amplifiers
  (their outputs are wired to pin 3; inputs 1/16 at GND, 2/15 at REF, so they
  should sit low), or a leak to the neighbouring pin 2 (1IN−, tied to REF).
  4 V from 5 V over 4.7k fits ≈ 1.2 kΩ to REF.
- The opto LED is fed only from the output: +Vout (C14+) → R9 18k → LED →
  TL431 / Q1 → C14−. With no voltage on C14 the LED cannot light, so the
  opto cannot be the source. A diode-mode or continuity test does not show
  a PC817 fault either way; check it under power.

Split the problem with two measurements under power:

1. Voltage across the opto LED (OC1 pin 1 → pin 2). About 1.0–1.2 V means the
   LED is lit and the cause is on the secondary side; about 0 V means it is on
   the TL494 side.
2. Vout across C14 itself (D10-K to D11-A), not at J2: J2.1 sits behind the
   R24 1 Ω shunt.

LED lit, secondary-side candidates:
- **R24 open** (1 Ω shunt). With a load on J2, J2.1 is pulled to +Vout through
  the load, Q1 gets base current through R51 and saturates, the LED is fully on,
  and the converter halts. J2 then shows 0 V. An inrush into a capacitive load or
  a short on the first run can open it. Check R24 with power off.
- **Q1 C–E or U2 TL431 K–A shorted**: the LED lights as soon as Vout passes
  ≈ 1–2 V, so the output stays at a few volts.
- **Pot J4 open** (unplugged, broken wire or wiper): the lower divider leg is
  only R8, the setpoint drops to ≈ 2.5 V and the output stays near zero.
  Measure R between J4.1 and J4.3.

LED dark, TL494-side candidates:
- A bridge, flux residue or leak between pins 2 and 3 (they are adjacent).
- A damaged error amplifier: check pins 1/16 = 0 V, 2/15/14 = 5 V, VCC (pin 12) = 12 V.
- Final check: lift OC1 pin 3 (or pin 4). If FB stays at 4 V, the TL494 or the
  board is at fault. If FB falls and the converter starts, the loop is open, so the
  output goes to the turns-ratio maximum (≈ 211 V on the 200v version). Run it only
  briefly, with a load or a reduced input.

## 10. Bench fault: "cricket" mid-range, ringing, one MOSFET at 100 °C (2026-11-01)

Owner's bench report: 120v channel, Vout set to 100 V, load 3 × 2.2k in
parallel (733 Ω, ≈ 136 mA, ≈ 14 W). Regulation works, but in the middle of the
pot range the converter chirps ("cricket"), the primaries ring hard, and one of
the two IRFBE30 reaches about 100 °C. The transformer was rewound bifilar, so the
two primary halves match. There are two scope shots of the two drains (50 V/div, 10 µs/div).

### What the shots show

- **Each pulse has three phases.** A short on-pulse comes first: one drain is at 0, the
  other is at 2·Vbus, with a turn-on spike to −20 / +281 V. Next, the drains cross over within 4–5 µs
  into a **flat plateau with the opposite polarity**: the drain that was on sits
  above Vbus and the other sits below it. Last, once the plateau ends, a sine ring at
  41–80 kHz decays over several periods. This is the waveform of a DCM flyback: during the plateau the
  magnetizing current dumps into C14 through the other bridge diagonal, so
  the plateau is the reflected output (half-primary ≈ (Vout + 2·Vf)·Np_half/Ns).
  When the current reaches zero, Lm rings with the drain, winding and diode
  capacitances. There is no output choke (C14 sits straight on the bridge), so
  the converter is not a forward push-pull. The plant is a
  peak-charge/flyback hybrid whose duty → Vout gain is very high and nonlinear.
  The ring itself is lossless. The trouble is that the next turn-on lands at a random
  phase of it.
- **Pulses are skipped, and the ones that remain land on the same transistor.** In both
  shots, every pulse pulls the **CH2 (cyan)** drain to 0. The spacing is about
  20 µs (shot 1) and about 37 µs (shot 2). By formula, RT = 10k and CT = 1.1 nF give
  an oscillator period of ≈ 10 µs, so that would be 2 and ≈ 4 periods. The 10.1 shot
  points to ≈ 18.5 µs (≈ 54 kHz) instead, so it is 1 and 2 periods; pin 5 still
  has to be measured. Either way, shot 2 has the same output firing every 2nd period. The TL494 steering flip-flop toggles
  on every oscillator period whether or not a pulse comes out. So when the
  loop lets a pulse through only every even period, all pulses go to
  one output. The core then sees unipolar volt-seconds, which the ring only partly resets. The flux
  walks toward saturation, the current in that MOSFET grows, and it heats up. **Prediction
  to check: the hot MOSFET is the one probed by CH2.**
- The audible chirp is the envelope of this pulse skipping: bursts at a
  kHz rate, and the loop is limit-cycling, not regulating.

### Why the loop limit-cycles (from the netlist)

- The opto LED (OC1.1 → OC1.2) sits between the D38 18 V zener node and the
  TL431 cathode **with no series resistor**. The anode is held stiff, so the LED
  current is set by V_K across the LED dynamic resistance alone (≈ 50–100 Ω at
  0.5–1 mA). About 60 mV of swing at K covers the whole FB range. As a result:
  - The opto stage gain is CTR·R13/r_LED ≈ 4.7k/100 ≈ 50 instead of the
    usual 2–5.
  - C15 (10 nF) + R25 (100 Ω) from K to REF barely acts as an integrator, because
    K hardly moves.
- Rough loop gain: integrator 1/(2π·R7·C15) ≈ 310 Hz (R7 = 51k) × opto
  ≈ 50 × PWM ≈ 0.15 /V × divider 2.5/100 × plant ≈ 300…1000 V per unit duty
  (peak charge, no choke). That puts crossover at ≈ 15…55 kHz, at or above the
  switching frequency. The PC817 pole (a few kHz with 4.7k) adds phase lag.
  The result is a limit cycle, and its frequency moves with the operating point,
  which explains why it appears only in part of the pot range.

### Fixes, in order

1. **Now, to protect the MOSFETs:** don't leave it running in the chirp region, and confirm
   which drain is on which MOSFET (see the prediction above).
2. **Make the loop slower** (no PCB change needed; can be soldered on):
   - Put a resistor **R_LED ≈ 1.5k in series with the LED** (between the D38/R9
     node and OC1.1). Gain falls to CTR·4.7k/1.5k ≈ 3 (×15 lower), and K now
     swings by volts, so C15 works. Headroom: 18 − 1.1 − 1.5 ≈ 15 V at K ≥ 2.5 V.
   - Put ≈ 1k across the LED (also in §6 C3b), for the TL431's 1 mA bias.
   - Add **10 nF from FB to GND** (across R13): this sets the opto pole on purpose at
     ≈ 3.4 kHz instead of leaving it to the PC817 parasitics.
   - After that, check the transient on the scope with a load step (for example, switching
     one of the 2.2k resistors). If it still chirps, raise C15 to 47–100 nF and R25 to
     4.7–10k (type II).
3. **Add an output choke** (the proper fix for the topology): an L between the bridge and C14.
   The bridge then works as the freewheel path, Vout ≈ 2·D·Vbus·Ns/Np_half
   becomes linear in D, and the plateau and ring go away in CCM.
   I_crit = Vout·(1 − Vout/Vpk)·T_osc/(2L). For the 120v version (Vpk ≈ 127 V)
   with L = 2 mH: ≈ 53 mA at 100 V and ≈ 76 mA at 50 V. So 2–3 mH / ≥ 0.3 A on a
   gapped core, plus a bleeder of 10–20 mA so that idle stays out of deep pulse skipping.
4. Optional: a small gap in the EL33 (0.1–0.2 mm) makes the core more tolerant of
   residual volt-second imbalance. The TL494 has no flux balancing of its own
   (current-mode controllers such as the UC3846 do).

### What to measure next

- At 1–5 ms/div, both drains in the chirp mode, to see the burst envelope.
- At 100 V, the plateau level ΔV = |V_drainA − V_drainB|/2. With
  Ns/Np_half = 34/30 it should be ≈ (100 + 2)/1.13 ≈ 90 V. If it is much lower,
  the rewound turns ratio does not match the note (shot 1 gives ≈ 43 V, but
  the Vout at which it was taken is not known).
- Vbus (C1) under load. Expected ≈ 112 V from 80 V RMS. The 2·Vbus level in the shots
  reads about 240–256 V.

### 10.1 After the LED series resistor (2026-11-01)

The owner added 1.6k in series with the opto LED. The chirp and the hard ringing
are gone, and the MOSFET runs cooler. The 1k across the LED and the 10 nF on FB have not
been added yet. There is a new shot: CH2 is a drain at 50 V/div. CH1 is the other drain at 20 V/div,
clipped above ≈ 126 V, so only its lower part can be read.

- The pulses now **alternate** between the two MOSFETs, about 18.5 µs apart. The full
  cycle is 37 µs (26.9 kHz). Pulse skipping and the flux walk have stopped.
- With RT = 10k and CT = 1.1 nF the oscillator should run at 91–100 kHz. Alternating
  pulses 18.5 µs apart mean either an oscillator at ≈ 54 kHz with every period
  used, or regular skipping by an odd number of periods. The note in §10 has been corrected for this.
  To be measured: the sawtooth on pin 5 (CT).
- Each cycle has the same structure. The on-time is very short: a near-vertical drop to 0
  (ON) on the CH2 drain. The drain then ramps up to the plateau over ≈ 6 µs. That fits a small magnetizing current
  charging ≈ 1 nF of node capacitance (Coss + winding + diodes). Next comes a plateau at
  ≈ 156 V. Both drains together average ≈ Vbus ≈ 114 V there, so the half-winding sits at ≈ 42 V. That is below the
  reflected output (≈ 90 V), so the plateau is most likely the **RCD clamp**
  (C3 sits at ≈ 40–45 V above Vbus), not the output. The drain then rings down
  as Lm·C at ≈ 55 kHz. The next turn-on on CH2 lands close to the valley (−17 V,
  the body diode conducts), which is soft switching.
- This is the normal DCM waveform of a push-pull **without an output choke**.
  It cannot turn into a square wave. Energy goes out as short current
  spikes, limited only by the leakage inductance. 13.6 W at 18.5 µs per pulse needs
  ≈ 2.8 µC primary charge per pulse, so a pulse of about 1 µs carries several amperes peak. Those amperes
  flow through R_DS(on) ≈ 3 Ω (hot ≈ 5 Ω) of the IRFBE30, which is the remaining heat source.
- **With a choke** the drains become a square wave: the ON drain at 0, the other at
  2·Vbus, and both at Vbus during the dead time. The primary current is then ≈ n·I_out
  ≈ 0.15 A flat-topped. Trade-off: Vout,max ≈ 2·D_max·n·Vbus ≈ 0.9 · 127 ≈ 114 V
  at nominal mains for the 120v version. To keep 120 V, raise Ns from 34 to ≈ 38 turns.
  The 200v (56/50) and 80v (23/20) versions need the same ≈ +10 %.

Next measurements: CT pin 5 frequency; the gate of one MOSFET (CH1, 5 V/div)
against its drain, to read t_on; and both drains at 50 V/div.

### 10.2 Owner changes and the R17 floor (2026-11-01)

Facts from the owner:
- CT is 2.2 nF on the board, not 1.1 nF, so f_osc ≈ 50 kHz and each output runs at ≈ 25 kHz.
  The owner will go back to 1.1 nF. That halves the volt-seconds per pulse at a given duty,
  so the core has twice the margin against saturation. The choke sizing in §10 already
  assumes T_osc = 10 µs.
- R17 (the 120v copy of R9: +Vout → D47 18 V zener → opto LED) was doubled to fight heat at
  high Vout. Note value 11k, now 22k: at 118 V the dissipation falls from 0.9 W to 0.45 W.
- The on-time really is tiny at 733 Ω. Without a choke the duty scales with load. With a choke
  it is ≈ Vout/(n·Vbus) whatever the load is (in CCM).

**The R17 floor.** The R17 branch has to feed the LED and the TL431 bias. To cut the
duty, FB needs ≈ 3 V over R13 4.7k, so I_C ≈ 0.65 mA. At CTR ≈ 0.5–1 for low currents that takes
I_LED ≈ 1 mA, plus about 1 mA for the bias resistor across the LED, so ≈ 2 mA in total. Regulation
therefore holds only above Vout ≈ 18 V + 2 mA·R17:

| R17 | Lowest regulated Vout (≈) | P(R17) at 118 V |
|---|---|---|
| 11k | 40 V | 0.9 W |
| 22k | 62 V | 0.45 W |

Below that floor the loop cannot pull FB up. The duty grows until Vout rises far enough to supply
the R17 current. In other words, a low setpoint gives an overvoltage, not a lower output.
Options: keep 22k only if the 120v channel is never set below ≈ 60 V. Otherwise use 11–12k
rated 2 W. A constant-current source (e.g. a DN2540 depletion MOSFET at ≈ 2.5 mA) keeps both the
floor and the heat low across the whole range. The series LED resistor (1.6k) sets only the loop gain,
not the current budget, so it does not need to follow R17. With 22k, use ≈ 2.2k (≈ 0.5 mA) as the bias
resistor across the LED, not 1k.

**Fitting the choke on the existing PCB.** Lift the + leg of C14 (C25 in the 120v
copy) and put the choke between the pad and the leg. The rectifier side stays on the pad, while
C14+, R7/R33, R9/R17 and J2/J6 stay on the leg. The bridge still provides the freewheel path.

**Choke from a salvaged ring (owner's core).** The core is a grey toroid with one white face, probably a
powdered-iron ATX choke core. About 15 bifilar turns measure 8.8 µH at 1 kHz. That gives A_L ≈ 39 nH/N² with
the strands in parallel (15 turns), or ≈ 10 nH/N² with them in series (30 turns). L = A_L·N², so
1 mH needs ≈ 160 turns (or ≈ 320 turns at 10 nH/N²), and 2.2 mH needs ≈ 240 (≈ 470).
L ≈ 0.5–1 mH is already usable. At 100 V it stays in DCM below ≈ 0.1–0.2 A, but
a DCM buck is still well behaved, and the primary peak current falls by an order of magnitude against
the choke-less case. Bias at 160 turns × 0.15 A = 24 A·turns, which is a few Oe on a T80-size
ring, so powdered iron keeps its µ. Use wire of 0.25–0.3 mm.

Corrected owner data: 21 bifilar turns, ring 15.5 × 8 × 6 mm (≈ T60 size: Ae ≈ 22.5 mm²,
le ≈ 35.6 mm, so A_L ≈ 0.79·µ nH/N²). With the strands in parallel this gives A_L ≈ 20 nH/N² (µ ≈ 25);
in series it gives ≈ 5 nH/N² (µ ≈ 6, an RF mix such as -2/-6). 8.8 µH at 1 kHz is only ≈ 55 mΩ of reactance, so
re-measure at 10–100 kHz. Turns for 1 mH: ≈ 225 (µ 25) or ≈ 450 (µ 6). The window (≈ 50 mm²,
≈ 40 % fill) takes ≈ 230 turns of 0.25 mm or ≈ 380 turns of 0.2 mm. So the target is ≈ 1 mH with
0.2–0.25 mm wire if µ ≈ 25, or ≈ 0.5 mH (≈ 320 turns of 0.2 mm) if µ ≈ 6. The flux swing does not depend on L:
ΔB ≈ (n·Vbus − Vout)·t_on/(N·Ae) ≈ 40 mT at 225 turns in CCM. Check the ring temperature
after 10 minutes.

### 10.3 With the output choke (2026-11-01)

Owner measurement (120v copy, choke fitted; CT was already 1 nF, see the correction below): 120 V in, 164 mA in
(19.7 W). At the top pot setting the output is only 80 V at 110 mA (8.8 W), η ≈ 45 %. The MOSFETs are at ≈ 50 °C,
the transformer windings show an almost clean square wave, and the transformer runs hot. Only a 1 nF CT
part is on hand.

- **Expected maximum** with the choke: Vout ≈ 2·D_max·n·Vbus − drops. The DTC rest level of 0.45 V gives
  D_max ≈ 0.4 per output, so ≈ 0.8 · 1.13 · 120 ≈ 109 V. The choke (≈ 2 Ω), the diodes and R_DS(on)
  reflected to the secondary together drop only ≈ 2–3 V at 0.11 A. The missing ≈ 25 V and the hot transformer
  point to **core saturation**. With the choke the duty is now near the maximum (no longer short
  spikes), and at f_osc ≈ 54 kHz one half-period can last up to t_on ≈ 0.8·T_osc ≈ 15 µs:
  ΔB = Vbus·t_on/(Np_half·Ae) = 120·15 µs/(30·Ae). For an Ae of 100 mm² that is ≈ 0.6 T peak-to-peak,
  i.e. Bpk ≈ 0.3 T, at the ferrite's saturation level when hot. The core saturates late in each
  half-period, the winding voltage collapses (the volt-seconds per half-period hit their cap,
  so Vout tops out), and the magnetizing current spikes heat the core, the copper and the MOSFETs.
- **Fix: CT = 1 nF.** That gives f_osc ≈ 1.1/(10k·1 nF) ≈ 110 kHz, 55 kHz per output, and ΔB halves to
  Bpk ≈ 0.15 T. The same reasoning applies to the other copies (Vbus·Np_half: 200v
  ≈ 190 V / 50 turns, which is the same ratio). The choke I_crit halves as well.
- Saturation check: put 0.47–1 Ω in the centre-tap (or bus) lead and look at the current. The
  current ramp turns sharply upward at the end of each half-period when the core saturates.
  Equivalently, the drain of the ON MOSFET lifts off 0 before turn-off.
- **Fixed overhead**: R1 (4.7k) from 120 V draws ≈ 22 mA, ≈ 2.6 W for the 12 V
  supply, i.e. 13 % of the input at this load. The R7/R8, R17 and clamp bleeders add ≈ 0.3–0.5 W.
  So even with an ideal power stage η stays ≤ 85 % at 9 W. The auxiliary winding for VCC (§6)
  would remove the R1 loss.
- Open: the Ae of the "EL33" core. The owner should check it against the core datasheet or measure it.

**Correction (owner, same day).** CT was already 1 nF during that measurement, and the choke is ≈ 100
turns of 0.48 mm on the T60 ring (≈ 0.2 mH at A_L ≈ 20 nH/N²; I_crit ≈ 0.7 A at 80 V, so at 110 mA it runs in DCM). The transformer
still heats strongly. So "saturation because of the 2.2 nF CT" is withdrawn. At 1 nF:
t_on ≤ 0.8·T_osc ≈ 7.3 µs and ΔB = 120·7.3 µs/(30·Ae). That is near saturation (Bpk ≥ 0.25 T) only
if Ae ≲ 60 mm². The Ae of the "EL33" core is unknown (the footprint only gives a body of ≈ 37 × 30 mm).
A DCM choke would push Vout up toward n·Vbus at light load, not cap it at 80 V,
so the choke does not explain the 80 V ceiling.

Candidates and the measurement that separates them:

| Candidate | Signature |
|---|---|
| Core saturation (small Ae, or Vbus above 120 V) | Current in the centre tap hooks upward at the end of each half-period; the core, not the copper, is hot |
| DC flux walk (voltage-mode push-pull, unequal halves) | The two halves of the centre-tap current differ; one MOSFET runs warmer |
| Unsuitable or lossy core material (salvaged ferrite, powdered iron) | Hot core at no load, no hook in the current |
| Damaged insulation or a shorted turn after the bifilar rewind (adjacent wires of the two halves are ≈ Vbus apart, 2·Vbus p-p) | High no-load input current, a local hot spot in the winding, low Vout at all settings |
| 12 V auxiliary supply sagging at full duty (R1 4.7k gives ≈ 22 mA against a ≈ 30 mA budget, §8) | VCC (pin 12) < 12 V and a slow gate edge at the top setting; caps duty and Vout |

First tests: Vbus on C1 and VCC on pin 12 at the top setting under load; input current and
transformer temperature with **no load** (only the bleeders); the centre-tap current through 0.47–1 Ω;
core vs winding temperature; centre-leg dimensions → Ae.

### 10.4 Owner data: real winding, no-load test (2026-11-01)

The owner reports:
- Vbus = 120 V DC; VCC at pin 12 = 12 V.
- No load: 70 mA in (8.4 W); the transformer is barely warm and the MOSFETs are as warm as under load.
- Under load the winding (not the core) seems to be what gets warm.
- Centre leg 10 × 12 mm, so Ae ≈ 120 mm².
- Actual winding: primary 2 × 48 bifilar, secondary 50 (not the 30/34 of the sheet note).

- **Saturation is ruled out.** ΔB = 120 V · 7.3 µs/(48 · 120 mm²) ≈ 0.15 T, Bpk ≈ 0.08 T.
  Core loss at 55 kHz is a fraction of a watt.
- **Turns ratio** 50/48 = 1.04, so n·Vbus ≈ 125 V. With the choke in CCM,
  Vout,max ≈ 0.8 · 125 − drops ≈ 95–100 V. The measured 80 V at 110 mA is therefore not a
  turns or saturation limit. Next check: the no-load Vout at the top pot setting. If it is also
  ≈ 80 V, the limit is the divider (R33/R34 values actually fitted). If it is higher, something
  in series drops ≈ 15–20 V at 0.11 A.
- **Load-independent loss ≈ 5.8 W** (8.4 W minus R1 ≈ 2.6 W), and it lands in the MOSFETs. The most likely source
  is the **bifilar primary**. Corresponding turns of the two halves carry the same EMF but sit
  at the two drain potentials, so the wires are ±Vbus apart (240 V p-p) along their whole length.
  ≈ 2 × 2.9 m of touching enamel wire gives C_bf ≈ 1–2 nF. Each turn-on discharges it
  through the MOSFET: P ≈ ½·C·(2·Vbus)²·f_turn-on,total ≈ ½ · 1.8 nF · 240² · 110 kHz ≈ 5.7 W, which matches.
  Bifilar push-pull primaries are a low-voltage (12–48 V) technique. Check: separate the
  two halves at the centre tap and measure the capacitance between them with the LCR meter.
  Fix: wind the halves separately. Either half A / secondary / half B (the secondary between them
  also cuts the leakage to it), or the two halves side by side in a split bobbin. The halves stay
  equal by turn count. Bifilar is not needed for that. The higher leakage between the halves goes into the RCD clamp (watch R22).
- The load-dependent part is ≈ 2.6 W. With a 0.2 mH choke the converter runs in DCM, so the current is peaky. Copper
  loss at these currents is ≤ 0.1 W, so a warm winding more likely gets its heat from the
  dielectric loss of the bifilar insulation or from the MOSFETs and the board next to it. The centre-tap current
  measurement (§10.3) is still pending.

### 10.5 The 80 V under load is a duty limit (2026-11-01)

No-load Vout at the top pot setting is 114 V. That is the setpoint ceiling, 2.5·(1 + R7/R8) with tolerances.
So the divider does not cause the 80 V seen under load.
With L ≈ 0.2 mH, R = 733 Ω and T_osc ≈ 9 µs: K = 2L/(R·T) ≈ 0.06 < 1 − D, so the stage runs in DCM, and
M = 2/(1 + √(1 + 4K/D²)). At D = 0.8 this gives M ≈ 0.92, i.e. Vout ≈ 115 V under load. Getting 80 V (M = 0.64)
needs D ≈ 0.26. Something holds the duty down at ≈ 1/3 of its maximum. The candidates, in order:
1. The bench supply is in current limit (≈ 164 mA in): Vbus sags. Measure Vbus on C1 under load and look at the
   CC lamp.
2. The current limit (Q1, R24 = 1 Ω on the return after C14 trips at ≈ 0.6 A): measure the voltage across
   R24 and Q1's V_BE. At 0.11 A it should show 0.11 V. If R24 was changed to ≈ 5–6.8 Ω, the limit trips at ≈ 0.1 A
   (80 V/733 Ω = 109 mA).
3. VCC or gate drive sagging under load at full duty (pin 12 was read at 12 V, but the operating point is not known).

Capacitive-loss test without rewinding: the no-load input power minus the R1 share scales as Vbus²
if the bifilar capacitance is the cause. Compare the no-load currents at 60 V and 120 V on the bus.

On the bifilar choice: a push-pull is sensitive to **volt-second** imbalance between the halves
(flux walk). Equal turn counts settle the winding side of that, and the larger sources are the
MOSFETs and the drive timing. Bifilar also cuts the leakage between the halves, which is the right trade-off at
12–48 V. At 120 V the inter-half capacitance costs more. Here Bpk ≈ 0.08 T, so the
core has a large margin against walk. Sectioned halves with equal turns, plus an optional
0.1 mm gap, are enough.

**Old transformer (owner).** The first transformer had the primary halves wound one after the other
(sectioned). With it, one MOSFET overheated badly. Rewinding bifilar did not change that. The overheating
dates from before the LED series resistor, when the loop was skipping pulses and all of them landed on one
MOSFET (§10). So it was a loop effect, not winding asymmetry. Refitting the old transformer now
is a direct A/B test of the bifilar capacitance. Compare the no-load input current at the same Vbus and
setpoint, and the temperatures of both MOSFETs. The old one is 50 + 50 / 56 turns (all transformers follow the 200v note): Bpk ≈ 120·7.3 µs/(2·50·120 mm²)
≈ 0.07 T and n·Vbus ≈ 134 V. Expect larger turn-off spikes (more leakage between halves).
Watch the clamp R22.

### 10.6 The 80v channel with a sectioned primary (2026-11-01)

Owner measurement: 80 V DC in at 0.175 A (14 W); 80 V out at 110 mA (8.8 W), η ≈ 63 %. After 30 min
the MOSFETs are at 35–40 °C and the transformer is warm. Turns: 50 + 50 / 56, the 200v winding (all transformers were wound to the 200v note), so n·Vbus ≈ 90 V.

- Loss budget, 5.2 W in total. R1 (3k) from 80 V takes ≈ 21 mA, ≈ 1.7 W. The bleeders take ≈ 0.2 W. Diodes
  ≈ 0.3 W. That leaves ≈ 3 W for the MOSFETs, the transformer, the clamp and the choke (if fitted).
  On the 120v channel the same split gave ≈ 8 W of converter loss with only ≈ 5.8 W at no load. That is consistent
  with the bifilar-capacitance explanation (§10.4).
- Transformer: copper loss at 0.11 A is ≤ 0.1 W even with peaky (choke-less) current and a proximity factor
  of a few. Core: ΔB ≤ 80 V · 7.3 µs/(50 · 120 mm²) ≈ 0.1 T, so Bpk ≤ 0.05 T at 55 kHz, with
  negligible core loss. The warmth comes mostly from copper (≈ 3 + 3 + 3.4 m of 0.42 mm, several layers, peaky current) and from heat
  conducted from the board. An EE33-size
  part at 1–2 W settles at ≈ +25–40 K. "Warm" is expected. A reading above 80–90 °C would point to a poor core material.
- Asked: whether this channel has an output choke, the transformer temperature, and the no-load input current
  (expected ≈ 25–30 mA, mostly R1).

Answers: no output choke on the 80v channel; the transformer is at ≈ 45 °C after 30 min; no-load input is 36 mA
(2.9 W). Without R1 (≈ 1.7 W) that leaves ≈ 1.2 W of no-load converter loss. Scaled by Vbus² to 120 V this would be
≈ 2.7 W, against 5.8 W measured on the bifilar 120v channel. The excess, ≈ 3 W, fits the bifilar inter-half
capacitance. The turn counts are nearly the same (48 vs 50 per half), so the comparison is fair.
The load-dependent loss is ≈ 2.3 W at 8.8 W out. Verdict: the sectioned transformer is fine. Refit the old one in
the 120v channel. Apply the loop fix (LED series resistor, 10 nF on FB) and CT = 1 nF to the 80v and
200v channels as well. The 80v channel works without a choke because Vout/(n·Vbus) ≈ 0.89, so the pulses
are not very short.

**Winding layout of the sectioned transformers (owner).** About 25 turns per layer, wound in the order
P1 (2 layers), P2 (2 layers), S (≈ 2.3 layers). P1 is separated from S by P2, so the
**P1–S leakage is larger than the P2–S leakage**. The two halves then get unequal turn-off spikes
and unequal commutation losses. That is the real winding asymmetry a push-pull is sensitive to (the turn
counts themselves are equal). The difference in mean turn length (P1 inner, P2 outer) adds a small copper-R
imbalance. The bifilar rewind removed the leakage asymmetry but added ≈ 3 W of capacitive
loss at 120 V. The middle ground is a **P1 – S – P2 sandwich**: each half has one interface with S, so the
leakage is symmetric and lower overall, the proximity loss is lower, and the halves stay ≈ 2·Vbus apart
only through the secondary layers and tape, not wire to wire. Check before rewinding: compare the turn-off spike heights on
the two drains (scope, both channels at the same V/div). If they differ by more than ≈ 20–30 %, or one MOSFET still runs
warmer with the loop fixed, rewind as P1–S–P2 with insulating tape between primary and secondary.

## 11. 200v channel: one MOSFET overheats (2026-11-04)

The owner reports that one MOSFET of the 200v channel overheats badly and the other much less. There is a scope shot of both
drains. Yellow is the hot MOSFET and cyan the cool one; both are at ≈ 100 V/div (read from the MAX values and the
grid). The channel frequency is 65.2 kHz (period 15.3 µs). The output voltage, the load and the choke status are not given.
The transformer is the common 50 + 50 / 56 sectioned winding (P1-P1-P2-P2-S).

What the shot shows (one period):
- **Yellow ON** ≈ 5.3 µs: its drain is at 0 and cyan at ≈ 590 V = 2·Vbus, so **Vbus ≈ 285–295 V**. The 200v design
  assumes 136 V RMS in, i.e. ≈ 191 V. During the last ≈ 2 µs the yellow drain **curls up to ≈ 25 V** (and the cyan top
  sags by the same amount). With R_DS(on) ≈ 3–5 Ω (hot) that is **≈ 5–8 A**: the
  magnetizing current runs away, so the core saturates at the end of every yellow pulse.
- **Yellow OFF**: a leakage ring to 359 V, then a flat level at ≈ 280 V = Vbus, which means **no** voltage on its half.
  During the same ≈ 10 µs the cyan drain sits at about −10…−29 V, below 0, so the **cyan body diode conducts**.
  The large saturation current freewheels through the cyan half back into the bus. The core is still
  saturated, so no voltage couples into the yellow half. The cyan gate pulse falls inside this diode
  interval, so it barely resets the flux. There is no dead-time plateau at Vbus on either drain.
- The result is a DC flux offset (flux walk) toward the yellow polarity. Each yellow pulse
  ends in saturation, with amperes in the yellow MOSFET (conduction loss I²·R_DS plus turn-off at high current).
  The cyan MOSFET turns on with zero voltage (its diode is already conducting) and runs cool.

Volt-seconds: ΔB = 285 V · 5.3 µs/(50 · 120 mm²) ≈ 0.25 T p-p, i.e. Bpk ≈ 0.13 T when balanced. That is
fine by itself, but only ≈ 0.15–0.2 T is left for an offset before a hot ferrite saturates. A small
volt-second imbalance between the halves is enough to use that up. Possible sources:
the two MOSFETs (turn-off delay, R_DS), the BC337/BC327 drivers, the TL494 output pulse widths, and the
unequal P1/P2 leakage to S (§10.6).

Tests, cheapest first:
1. Stop running this channel at that bus voltage. Feed it the design ≈ 136 V RMS (Vbus ≈ 191 V) and
   recheck. ΔB then drops by 1/3. Ask: what input gives 285 V?
2. **Swap the two MOSFETs.** If the heat follows the part, it is the MOSFET (slower turn-off, higher R_DS). If the heat stays
   on the yellow side, it is the drive or the winding.
3. Both gates at once (CH1/CH2, 5 V/div): compare the pulse widths and the fall times. A difference of ≥ 0.1–0.2 µs out of
   5.3 µs is already a ≈ 2–4 % imbalance.
4. Remedies: a 0.1–0.2 mm gap in the core, so a DC imbalance current gives less offset flux and the
   resistive balancing works before saturation; the P1–S–P2 sandwich; a lower Vbus; or current-mode control
   (UC3846/UC3825), which balances the flux inherently.

### 11.1 Correction and gate shot (2026-11-04)

The owner measures **Vbus = 200 V**, so the "Vbus ≈ 285 V" reading above is withdrawn. The check is that the mean of each
drain must equal Vbus, by volt-second balance of each half. From the drain shot, yellow is
≈ 280 V × 147/225 ≈ 185 V and cyan ≈ 585 V × 75/225 ≈ 195 V, i.e. ≈ 200 V for both. So the scale is right and
the 280 V level is **not** Vbus. Re-reading the shot with Vbus = 200 V:
- Yellow ON: the yellow half has +200 V, and cyan sits at 200 + 200·N_c/N_y ≈ 590 V, so **N_c/N_y ≈ 1.95**.
- Cyan conducting (gate or body diode): the cyan half has +200 V, and yellow sits at 200 + 200·N_y/N_c ≈ 280 V,
  so **N_c/N_y ≈ 2.5**.
- Volt-second balance: the yellow ON time is 5.3 µs and the cyan conduction time is ≈ 10 µs, so N_c/N_y ≈ 1.9.

All three readings say the **two primary halves differ by about 2×**. The hot (yellow) half has the fewer turns. Its
V/turn and flux rate are about twice as high, so it saturates at the end of each pulse. The flux is then balanced by the cyan body
diode, which keeps conducting after the cyan gate pulse ends. Likely cause: the centre tap
was brought out at the wrong layer boundary, or the layer order/phasing inside one half is wrong. The owner states
that all transformers are wound 50 + 50 / 56 to the note. That matches the earlier channels; this is a 200v-channel-specific fault.
Check with power off: the LCR inductance of each half should be equal (L ∝ N², so 2× the turns gives 4× the L).
Alternatively, feed one half from a generator (a few V, 10–50 kHz) and compare the voltages on the two halves.

Gate shot (2 V/div, 10 µs/div): the duty is 35.3 % (yellow) and 35.8 % (cyan), so the TL494 and the drivers are
balanced (≈ 70 ns difference) and do not cause the asymmetry. But:
- **The gate high level is only ≈ 6.5–7 V** (12 V expected minus a ≈ 0.7 V follower drop). That is the
  12 V supply sagging. R1 = 10k from 200 V gives ≈ 18 mA against a ≈ 33 mA budget at 71 kHz (R20/R21 1k ≈ 10 mA,
  gates 2 × 78 nC × 71 kHz ≈ 11 mA, TL494 ≈ 7 mA, 7812 ≈ 5 mA), as predicted in §8. At 7 V the IRFBE30 is
  not fully enhanced: R_DS rises well above the 3 Ω rating and it goes linear at the saturation current. Fix: R20/R21 → 4.7k,
  R1 ≈ 6.8k / 10 W (≈ 5.8 W at 200 V), or better an auxiliary winding for VCC.
- The **off-state yellow gate rings from −3 V to ≈ +3 V** whenever cyan turns off (Miller coupling of the
  large yellow-drain dv/dt). That reaches V_GS(th) (2–4 V), so the MOSFET partly turns on while its drain is at hundreds of volts.
  The cyan gate rings much less. Fix: a 10k gate–source resistor at each MOSFET (still open, §8), a lower-impedance
  turn-off (e.g. R18/R19 10 Ω with a diode across for faster turn-off), and a short gate loop.

### 11.2 Turns are equal; the 12 V sag (2026-11-04)

The owner confirms the halves are equal within one turn, so the "2× turns" reading of §11.1 is withdrawn. With equal
turns, the different half voltages (390 V against 200 V, and 80 V against 200 V) mean the halves are **not coupled** during those
intervals. The core is deep in saturation for a large part of the cycle, and the voltages are divided by the leakage and
saturated inductances carrying large currents. The drain means (≈ Vbus) still hold. The open question is the
source of the DC offset. With the TL494 widths equal, the candidates are the following:
- **Gate drive at ≈ 7 V.** With V_GS(th) spread over 2–4 V (IRFBE30), two parts at 7 V can differ several times in
  R_DS. The I·R_DS drop subtracts from the volt-seconds of one half, so the flux walks, and at saturation current
  the weaker MOSFET goes linear.
- **Miller turn-on of the yellow gate** (+3 V rings when cyan turns off): it adds conduction on the yellow side.

Why the 12 V supply sags now and did not before: CT went from 2.2 nF to 1 nF, so the frequency rose from ≈ 27 to ≈ 71 kHz, and the duty is
now ≈ 35 % per side. Gate charge went from ≈ 4 to ≈ 11 mA, and the R20/R21 base current scales with duty. R1 = 10k gives ≈ 18 mA from 200 V
against a ≈ 33 mA budget.

R1 options (Vbus = 200 V, 18 V node):

| Change | R1 total | I | P (R1 parts) | Note |
|---|---|---|---|---|
| 10k ‖ 15k (owner) | 6k | ≈ 30 mA | 3.3 + 2.2 W | both ≥ 5 W parts; D5 idle 0.55 W, so a 1 W zener |
| R20/R21 → 4.7k, 10k ‖ 27k | 7.3k | ≈ 25 mA | 3.3 + 1.2 W | budget falls to ≈ 25 mA; less heat |
| Auxiliary winding on T1 | — | — | — | removes the loss; R1 stays as start-up only |

R1 = 10k already dissipates 3.3 W in a ≈ 2 W DIN0918 footprint (§8).
Order: fix the 12 V (and fit the 10k gate–source resistors), then re-shoot both drains. If one side is still hot, swap the
MOSFETs to see whether the heat follows the part.

Owner decision: no auxiliary winding in this iteration. The R1 parts on the board are rated 5 W, so 10k ‖ 15k (3.3 + 2.2 W) is
within rating. The remaining check is D5: at idle it takes ≈ 0.55 W. The 7812 drops (18 − 12) V · 30 mA ≈ 0.2 W, which is fine.

### 11.3 After the 12 V fix: 54 W at no load (2026-11-04)

State: 15k fitted in parallel with R1, a 1 W zener, R20/R21 still 1k; 12 V is present and the gates reach ≈ 11 V. At **Vbus 200 V with no load the
input is ≈ 300 mA (60 W)**, of which ≈ 30 mA is R1, so the power stage loses ≈ 54 W with no load. The 80v channel loses ≈ 1.2 W.

Drain shot (≈ 100 V/div, 75.7 kHz). The picture is the same as in §11:
- While yellow conducts, the cyan drain sits flat at ≈ 600 V. That is the **RCD clamp level**: C3 is at ≈ 400 V over Vbus,
  so R22 (47k) dissipates ≈ 3.4 W against a ≈ 1 W part. Check R22/C3 temperature.
- While the cyan side conducts (gate, then body diode), the yellow drain sits at ≈ 280 V. Only ≈ 80 V of the 200 V on the
  cyan half couples into the yellow half, so the coupled voltage collapses to ≈ 40 % in that polarity. That means a large current
  flowing through the leakage in that polarity: a heavy load on one half-cycle (a shorted output diode, a shorted turn) or
  a saturated core.
- Every ≈ 7 periods there is an irregular event: a narrow cyan spike instead of a plateau.

Gate shot (≈ 11 V high): mostly alternating with dead time, but at the same ≈ 7-period rhythm **yellow gets
two pulses in a row**. Each such event comes with a large spike on both gates (MAX 16 V), and the counters read yellow
113.5 kHz against cyan 74.9 kHz. The TL494 steering flip-flop is being double-clocked, most likely by noise on CT/GND from the
fault currents. That feeds extra volt-seconds into the yellow side. It is probably a consequence, but it is self-reinforcing.
The earlier gate shot (§11.1, low VCC) was clean.

54 W at no load is a fault, not a tuning issue. Tests, all at reduced Vbus (50–100 V) from a current-limited
supply:
1. Sweep the no-load input current against Vbus. If it rises smoothly from zero, the cause is a short or shoot-through. If it is
   small and then takes off above some voltage, it is flux (saturation onset).
2. **Disconnect the secondary** (lift the bridge input or the choke/C14). If the no-load current becomes normal, the fault is on the
   secondary side: check D8–D11 (200v copy) in diode mode, C14, and the output. If not, it is primary-side.
3. LCR: each primary half and the secondary, L and Q at 10–100 kHz, against the identical 80v-channel transformer as a
   reference. A shorted turn shows as a several-times lower L and a low Q.
4. Diode check of D6/D7 (clamp), and the temperature of C3/R22.
5. Then swap the MOSFETs.
Decoupling at the TL494 (100 nF at VCC and REF next to the pins, a short CT/RT return to pin 7) is worth doing anyway, against the
double clocking.

### 11.4 Root cause found: the halves are not equal (2026-11-04)

At Vbus 30 V the no-load input is already ≈ 120 mA, and the thermal camera shows only the MOSFETs hot. The LCR gives **1.5 mH on one half and
6.5 mH on the other** ("Q" 0.011 and 0.018; that is probably the dissipation factor D = 1/Q, so Q ≈ 90 and 55, and there is no
sign of a shorted turn). L ∝ N², so the ratio of 4.3 means **≈ 2.1× the effective turns**. That matches the drain-voltage
reading of §11.1 (N_c/N_y ≈ 1.9–2.5), which was withdrawn there only because the owner counted equal turns.
With unequal halves, no duty pattern balances the flux: each period walks it, and only saturation
current and the body diode bring it back. That happens at any Vbus, which is why there are 120 mA already at 30 V.
A wiring mix-up fits the number well: one "half" being P2 + S in series (50 + 56 = 106 turns, i.e. 2.12×,
L ratio 4.5). Check the old transformer: the primary to secondary resistance must be open (isolation), and each winding
should be measured on its own with the others open.

The owner is winding a new transformer. Acceptance checks before fitting it:
- L of P1 and P2 equal within ≈ 5 % (one turn in 50 is ≈ 4 % of L); L(S) ≈ (56/50)² ≈ 1.25 × L(P).
- Phasing: L of P1 + P2 in series through the centre tap ≈ 4 × L(half). ≈ 0 means the halves are in antiphase.
- Ratio: a few volts at 10–50 kHz on P1 from a generator gives P2 ≈ 1.00× and S ≈ 1.12×.
- Primary to secondary open at ≥ 500 V (insulation tape between the sections); the P1–S–P2 sandwich is preferred (§10.6).
