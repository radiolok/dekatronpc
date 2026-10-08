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
