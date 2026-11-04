# External inputs on the falling Clk edge (TRS §22 item 19, v0.48)

The owner's rule (TRS v0.46, Appendix B): on the rising Clk edge the data of every `Emu → DPC`
input is guaranteed readable; an external source changes data and valid/ready **only on the
falling edge**. The tube triggers `DFF_J2N16` capture through the clock inverter, about 250 ns
after the rising edge, so a source that changes on the rising edge races the short paths to D
(found at `eot_q` in `synth_sim.sh -t`, `doc/tube_count_below_1000.md` §13). TRS §22 item 19
asked for three things: the emulator follows the rule, the other testbenches are checked, and the
other short paths from external inputs to D are found (hold STA on the inputs).

## 1. Emulator (`rtl/Emulator/Emulator.sv`)

Every source in the emulator runs on the rising edge of `Clock_1MHz`: the firmware loaders, the
keyboard opcode input, the receive buffer, the UART and the consul handshake. All their outputs to
DekatronPC now pass one register on the **falling** edge of `Clock_1MHz` (`dpc_in_q`, a packed
struct):

| Field | Port of DekatronPC | Source |
|---|---|---|
| `insn`, `insn_vld` | `InsnIn`, `InsnInValid` | keyboard / firmware loaders / Verilator port, by `selector` |
| `rx_data_bcd`, `rx_vld` | `rx_data_bcd`, `rx_vld` | receive buffer (REQ-UART-008) |
| `tx_rdy` | `tx_rdy` | UART or consul |
| `halt`, `run`, `step`, `next_ip`, `prev_ip`, `next_app` | panel keys | keyboard |
| `load_start`, `load_stop` | `InsnLoadingStart/Stop` | keyboard (selector 1010) |

The register is transparent in cycles: a source sets a value on rising edge N, the register takes
it at N + ½, and DekatronPC samples it at N + 1, exactly as before. The sources still look at
`InsnInReady`, `rx_rdy`, `InsnInLoading` and `tx_vld` on the rising edge, and those come from
DekatronPC triggers, so the handshakes are unchanged. Two groups stay out of the register:

- the reset lines `rst_n`, `SoftRstKey`, `HardRstKey`: they go to the asynchronous time relay
  (`RstTimeRelay`) and have no edge discipline;
- the switches (`EchoMode`, `RunOn*Rst`, `SoftRstOnEOT`, `Bell*`): constants in the emulator
  today (OPEN-011); when they become real switches they are slow levels.

The emulator applies the rule always, not only once tube blocks are connected: it costs one FPGA
register per bit and changes nothing in cycles. `verilator --lint-only` of Emulator is clean.

## 2. Testbenches

A testbench input models either an **external source** (loader, terminal, panel) or an **internal
master** (the glue that drives a block inside the machine). Only the first kind falls under the
rule. An internal master is a trigger of the machine: it changes on the rising edge plus its
clock-to-Q, and some block inputs require exactly that. `DekatronCounter`'s `step_f`/`step_r` and
the write lines are combinational from `valid`, and the step command must stand over the whole
cycle from the edge through both phases; a `valid` changed at the falling edge would cut the phase
in the middle.

| Testbench | External inputs | Before | Now |
|---|---|---|---|
| Dekatron_tb, Counter_tb | none (the counter's master is glue) | rising edge | unchanged, correct |
| IpLine_tb | loader `insn_in`/`insn_in_valid`/`insn_loading`, keys ±IP | falling edge | unchanged |
| ApLine_tb | terminal `rx_data` (with `op`/`valid` on the falling edge) | falling edge | unchanged |
| MachineCtrl_tb | keys, switches, `rx_vld`, `tx_rdy` | rising edge + 1 ns | **falling edge**: `tick()` ends on the falling edge; the terminal drops `rx_vld` on the falling edge after the handshake (`rx_take`) |
| DekatronPC_tb | loader and `tx_rdy` (falling since v0.46); keys Run, ±IP | keys on the rising edge (NBA) | **Run and ±IP on the falling edge**; SoftRst/HardRst keys stay on the rising edge (§5) |
| cocotb (`tb/`) | none on the tube blocks | — | no change: block tests of primitives, memories and emulator peripherals, zero-delay RTL only |

The models of IpLine/ApLine and of the reset relay inside MachineCtrl_tb are internal masters and
stay on the rising edge. ApLine_tb drives `op`/`valid` on the falling edge although they come from
MachineCtrl in the machine; this passes because ApLine registers `valid` (the counter command comes
from its own state, `data_valid = (in_dset | in_dop) & go`), and it was not changed.

## 3. Short paths from the inputs: input timing in the STA

`rtl/run/vtube_sta.py` used to leave every input port untimed. It now launches each input port
(except `Clk` and the reset lines) as its own arrival class `in:<port>` and checks it on its own,
with the input changed at T/2:

- trigger or latch D: `T/2 + late + setup ≤ T + clock at C` and `T/2 + early ≥ clock at C + hold`;
- memory input: `T/2 + late ≤ T`;
- a gate where the input meets a guide phase: the input must stand over the whole pulse,
  `−T/2 + late ≤ lead` and `T/2 + early ≥ trail`.

For each port the report gives the period it needs and, for comparison, the hold slack if the
source changed it **at the rising edge** (`early − clock at C − hold`). The new row of the summary
table, "external inputs changed on the falling edge", is not part of the minimum period. The rest of
the report is unchanged (8969 ns as synthesized, 8069 ns fitted).

Result on the current netlist (`vtube_sta.sh -n`, fitted phases 600 ns, phase delay 2400 ns; as
synthesized with 3300 ns the worst input needs 8986 ns):

The last column is the trigger with the smallest rising-edge slack for that input.

| Input | Reaches | Needs T ≥ | Rising-edge hold slack | At |
|---|---|---|---|---|
| InsnInValid | memory, phase gate, trigger | 7186 ns | 184 ns | `eot_q` (IpLine) |
| Halt | trigger | 5163 ns | 140 ns | `insn_loading` |
| InsnLoadingStart | trigger | 4927 ns | 286 ns | `insn_loading` |
| rx_vld | trigger | 4908 ns | 467 ns | `state[1]` (MachineCtrl) |
| Run | trigger | 4900 ns | 618 ns | `state[2]` (MachineCtrl) |
| Step | trigger | 4898 ns | 178 ns | `one_step` |
| tx_rdy | trigger | 4810 ns | 481 ns | `op_q[0]` (load enable `op_end`) |
| RunOnSoftRst / RunOnHardRst | trigger | 3840 ns | ≈ 1270 ns | `state[2]` (MachineCtrl) |
| EchoMode | trigger | 3496 ns | 763 ns | `op_q[0]` |
| InsnLoadingStop | trigger | 2992 ns | 140 ns | `insn_loading` |
| SoftRstOnEOT | trigger | 2731 ns | 294 ns | `rst_soft` |
| keyPrevIp | trigger | 1405 ns | 341 ns | `dir_q` (IpLine) |
| InsnIn | memory, trigger | 1278 ns | **29 ns** | `eot_q` (IpLine) |
| keyNextIp | trigger | 470 ns | −235 ns | `key_next_s` (IpLine) |

What it says:

1. **With falling-edge sources every input fits at 100 kHz.** The worst is `InsnInValid` into the
   step command of the IP counter: `key_mode = S_INSN_IN & insn_loading & ~insn_in_valid` gates
   `ip_valid` (the ±IP keys while the machine waits for an opcode, TC-N3). An input that reaches a
   phase gate has to stand from the previous falling edge to the end of the phases, so it needs
   `T ≥ 2 · (trail − early)`. As synthesized that is 8986 ns, 17 ns above the minimum of the rest of
   the machine (8969 ns); at 100 kHz the margin is about 1 µs. Any faster clock would have to take
   this path into account: either `ip_valid` must not depend on `insn_in_valid`, or the input must
   be registered.
2. **The rising-edge race is real but thin.** `InsnIn → eot_q` keeps only 29 ns with the input
   changed on the rising edge: the TC-N2 race that `synth_sim.sh -t` showed (the simulator's delays
   differ a few ns from the STA's). The other slacks are 140–600 ns: not violations, but they only
   hold with tube spread if the sources keep to the falling edge.
3. **`keyNextIp` −235 ns is expected.** It is the synchronizer `key_next_s` behind `KEYDB_N16`; a
   key is asynchronous anyway, and the synchronizer is there for exactly that (TC-N3).
4. **The panel keys Halt, Run, Step and InsnLoadingStart/Stop have no synchronizer.** In
   MachineCtrl they go straight into the D of several triggers at once: the state bits (`S_HALT`,
   `S_IDLE`, `S_FETCH_W`, `S_CIN_WAIT`, `s_next`), `insn_loading`, `one_step`; `halt_key` also goes
   combinationally into `ip_valid` and `ap_valid`. In the emulator they are synchronous (keyboard on `Clock_1MHz`, now through
   `dpc_in_q`). On the real panel a key is asynchronous to Clk: a press inside the aperture can give
   different values to different state bits, which means a wrong or undefined state. **An open
   question for the owner** (TRS §22 item 19): a synchronizer trigger per key (`DFF_J2N16`, as
   `key_next_s` for +IP) or another scheme.

## 4. Checks

Run on a 24-thread / 31 GB machine (the full set is mandatory, AGENTS.md §1):

| Check | Result |
|---|---|
| `./emul MachineCtrl` | pass |
| `verilator --lint-only` Emulator | clean |
| `./run_tests.sh -t` (run again after the reset-key revert, also `-d`) | pass (Icarus tests; Verilator DekatronPC_tb matches dpcrun on helloworld, program.bfk, pi.bfk) |
| `./run_tests.sh -d` | pass |
| `./run_tests.sh -s` | pass, 1052.5 tubes (seed 0, RTL of the machine unchanged) |
| `./synth_sim.sh` | 7/7 pass |
| `./synth_sim.sh -t` | with the reset keys on the falling edge: Dekatron, Counter pass, DekatronPC hello/program **fail** (§5); with the reset keys back on the rising edge: 4/4 pass, 0 setup / 0 hold violations |
| `cd tb && make regression` | 34/34 pass |
| `./vtube_sta.sh -n` | 8969 ns as synthesized (unchanged), input section added |

`synth_seeds.sh` was not run: no RTL of the machine changed, so the tube count cannot move.

## 5. The reset keys and the asynchronous relay

The first `synth_sim.sh -t` run had the SoftRst/HardRst keys of DekatronPC_tb on the falling edge
too, and both DekatronPC runs failed: one setup violation at `machineCtrl` `state[3]` (D changed
13.5 ns before C at 240 300 ns), then the machine went to `S_CIN_WAIT` instead of `S_HALT` and the
testbench timed out. The cause is not the input rule. `RstTimeRelay` releases `rst_busy`
asynchronously, a fixed time after the key is released; MachineCtrl leaves `S_RST_WAIT` on
`~rst_busy` with no synchronizer (TRS §22 item 14). Moving the key by half a period moved the
release to 239 050 ns, 1 µs before the rising edge at 240 050 ns, while the path
`~rst_busy → state` takes about 1.24 µs: the new state reached D 286 ns after the edge, inside the
capture of the clock inverter. With the key on the rising edge the release fell 6 µs before an edge,
which is why it passed before: by luck of alignment.

The reset keys drive the asynchronous relay, not clocked logic, so they are not under the falling-edge
rule; the emulator leaves them out of `dpc_in_q` for the same reason (§1). DekatronPC_tb keeps them
on the rising edge as before. The real fix is the synchronizer on `rst_busy` (TRS §22 item 14, a
tube-count change), **for the owner to decide**; a real relay releases at any moment, and a release
whose new state reaches the state bits within the setup window (310 ns) plus the spread of their
path delays before the capture can leave some bits old and others new, an undefined state.

## 6. Synchronizers in MachineCtrl (TRS v0.49)

Owner, 2026-11-03: synchronizers on `DFF_J2N16`, one per signal, as `key_next_s` for +IP. A gate
`NAND(key, Clk)` would not do: it stores nothing, its output follows the key through the whole high
half of Clk (including the capture ≈ 250 ns after the edge) and drops to a pulse every falling
edge. The cheaper alternative, a `LATCH_J2N16` transparent while Clk is high (3.5 tubes: its output
changes only in the first half of the cycle), was declined in favour of a cell that the STA and the
netlist checks already cover.

`MachineCtrl` registers `halt_key`, `step_key`, `run_key`, `key_insn_loading_start`,
`key_insn_loading_stop` and `rst_busy` on the rising edge (`*_s`) and uses only the registered
copies. A press or a relay release takes effect one cycle later. The registers have no reset: at
power-up the reset lines hold the machine in `S_RST_WAIT` for many cycles. `soft_rst`/`hard_rst`
drop together with `rst_busy`, but in `S_RST_WAIT` none of MachineCtrl's D inputs depend on them
(the state stays until `rst_busy_s` falls; `rst_soft`, `insn_loading`, `one_step`, `pf_q` keep
the values the lines set), so the one synchronizer is enough for MachineCtrl. The asynchronous
release of the lines in the counters, IpLine and ApLine is TRS §22 item 15 and is not touched.

DekatronPC_tb now presses the reset keys on the falling edge again, the scenario that failed in §5,
and `synth_sim.sh -t` passes it.

| Check | Result |
|---|---|
| `verilator --lint-only` DekatronPC | clean |
| `./emul MachineCtrl` | pass |
| `./synth_sim.sh -t` | 4/4, 0 setup / 0 hold (reset keys on the falling edge) |
| `./run_tests.sh -t` | pass, matches dpcrun on helloworld, program.bfk, pi.bfk |
| `./run_tests.sh -d` | pass |
| `./run_tests.sh -s` | 1098.5 tubes (seed 0; MachineCtrl 244 → 290) |
| `./synth_sim.sh` | 7/7 |
| `cd tb && make regression` | 34/34 |
| `./synth_seeds.sh -s "0 1 2 3" IpLine ApLine MachineCtrl` | 1053.2 → **1099.3** (+46.1; 6 × 7 = 42 plus ABC drift) |
| `./vtube_sta.sh` | minimum 8828 ns as synthesized (was 8969), 8028 fitted; inputs: the keys now reach only their synchronizers (rising-edge slack −341 ns, expected for a synchronizer); worst input still `InsnInValid` → IP step gate, 8986 ns, about 1 µs margin at 100 kHz |
