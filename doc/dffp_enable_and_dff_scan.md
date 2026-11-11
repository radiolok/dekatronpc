# DFFP_J2N16 on the carry enables; DFF → DFFP scan (TRS v0.60 proposal)

## 1. Carry enables: LATCH_J2N16 → DFFP_J2N16 (done)

`DekatronCounter` enable per decade (`enLatch[e]`) was a D latch open in `CmdWin` (Clk edge → phase start). The latch closes at the fall of the window, so it takes D at exactly the instant `PhaseStart` rises. `DFFP_J2N16` clocked by `PhaseStart` does the same job (C = `cmd_win`, which `DekatronPhaseGen` now outputs as `PhaseStart`, not as the window `WinDelay`). Same 3.5 tubes, the extra window level is gone.

Cost: DFFP setup is 424 ns against 194 ns for the latch, so the phase start delay must grow. `vtube_sta.sh` fitted 2300 ns (was 1900); default is now **2500 ns** (`parameters.sv`, `vtube_sta.sh`, `synth_sim.sh -t`). RTL default was 0 and raced `dec` against the DFFP at the Clk edge (Counter_tb failed), so it is 2500 too.

`vtube_sta.py`: a trigger whose clock arrives later than `DELAYED_CLK_NS` (500 ns, i.e. the command window) is checked in the same cycle (setup against its own edge, like the latch gating). Before this the checker reported a false hold of −1570 ns.

Results: min Clk period 7858 ns (127 kHz; 7358 before), 100 kHz meets with 2142 ns. Total 1064 tubes (IpLine 365, ApLine 435.5, MachineCtrl 263.5), DFFP 19, DFF 29. `run_tests.sh -d`, `-s`, `synth_sim.sh`, `synth_sim.sh -t`: pass. Not run yet: `make regression`, `run_tests.sh -t`, `synth_seeds.sh`.

## 2. DFF_J2N16 scan (29 flip-flops)

Method: in the flat netlist swap one DFF to DFFP (C on Clk itself) and rerun STA at 2500 ns. Fanout limit of DFFP Q is 6.

- Keep as DFF: Q fanout > 6 (apLine `_304_` 8, ipLine `_330_` state[2] 10, machineCtrl `_299_` 7); tube-class D (cathode reading, ~7.4–7.8 µs) where DFFP's setup raises the minimum period by 77–375 ns (ipLine `_323_`, `_325_`, `_329_`, `_331_`).
- Suitable (22): apLine 6, ipLine 5 (`_324_ _326_ _327_ _328_ _332_`), machineCtrl 11. Single swaps change T_min by 0…+10 ns.
- All 22 together: T_min 7912 ns (+54), hold slack 16 → 128 ns, external-input need 3642 → 4441 ns (still < 7858). Saving 22 × 3.5 = **77 tubes**.

Not applied in section 2 as a netlist pass (see 3). Most Q nets lose their RTL names after FSM recoding and ABC (`machineCtrl._138_` …), so a by-name or attribute swap does not hold across seeds. Options: (a) explicit `DFFP_J2N16` instances for the registers that keep names, (b) a netlist pass chosen by structure + STA. Needs an owner decision.

## 3. Explicit DFFP instances (owner decision, applied)

Owner chose option (a). The registers are now `DFFP_J2N16` instances; each former `always_ff` became `always_comb` with `x_d` defaults plus the instance.

- ApLine: `state[2:0]`, `mem_here_q` (`lock_q` stays a DFF: fanout 8). DekatronCounter: `zero_q`, `at_top_q`.
- IpLine: `ip_counted_q`, `eot_q`, `key_moved_q`, `state[0]` (`state[1]`, `state[2]`, `scanning_q`, `halt_pending_q`, `overflow_q`, `dir_q` stay DFF).
- MachineCtrl: `op_q[3:0]`, `state[3:0]`, `pf_q`, `insn_loading`, `one_step`, `rst_soft`.

Result: DFFP 41, DFF 7 (was 19 / 29). Tubes **987.5** (was 1064; IpLine 354, ApLine 414.5, MachineCtrl 219). Seeds 0..3 total 987.5 / 982.5 / 981.0 / 981.5, mean 983.1. Min Clk period 8065 ns (124 kHz), hold slack 217 ns, 100 kHz meets.

Passing: `make regression` (34/34, venv ~/.venvs/dekatronpc), `run_tests.sh -t`, `-d`, `-s`, `synth_sim.sh`, `synth_sim.sh -t`.

Open: `Clk` now drives 30 DFFP clock pins (≈ 29 grids) on one net; the HV clock driver / clock tree for them is not designed (each C ≈ 2.8 pF).
