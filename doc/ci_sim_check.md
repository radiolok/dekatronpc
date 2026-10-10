# CI `sim` job: Icarus 12 failure and tests that did not test

Date: 2026-10-07. Scope: the `sim` job of `.github/workflows/docker-image.yml`
(`rtl/run/run_tests.sh -t` inside the Docker image). Requirements: REQ-VER-029,
REQ-GM-002.

## 1. Why CI failed

```
IpLine_tb.sv:441: sorry: break statements not supported.
IpLine_tb.sv:456: syntax error
```

The Docker image is `ubuntu:26.04` with the distro `iverilog`, which is
**Icarus 12.0**. It doesn't support `break`/`continue`; Icarus 13 (devel) does.
The local machine had 13.0-devel, so the new `IpLine_tb` and `MachineCtrl_tb`
passed locally and failed in CI. `MachineCtrl_tb.sv` had three `continue`s
(lines 358, 359, 477) and would have failed right after IpLine.

Fix: the loops are rewritten without `break`/`continue` (a `stop` flag in the
loop condition, `if` around the body). Behaviour is unchanged: IpLine still
makes 400 fetches with 131 scans.

Rule for testbenches run by `run_tests.sh`: **target Icarus 12**, so no
`break`/`continue`. To reproduce CI locally without Docker, build Icarus
`v12_0` from source (`git archive v12_0`, `sh autoconf.sh && ./configure
--prefix=... && make install`) and put it first in `PATH`.

## 2. Tests that passed without checking

Fixing the syntax wasn't enough. Three checks in the same job passed without
testing anything.

### 2.1 `DekatronPC_tb.sv` (Icarus): the program scenario never ran

- `check_bootloader` sits under `` `ifdef TRY_PROGRAM ``, and no config
  defined it. The "hello" and "program" runs were the same IP-key test, and
  `EXPECTED_OUTPUT` was never compared. The reported "5us" was also wrong: the
  timescale is 100 ns, so `$time/1000` is in units of 100 µs.
- With `TRY_PROGRAM` turned on, three problems showed up (already noted in
  `doc/tube_count_reduction.md` §12):
  - `generate_rom.py` puts no ISA1 at the start. Loading starts in Debug ISA,
    where the first `>` (0x4) is EOT, so only `++++++++++[` was loaded. Fix:
    the testbench loader sends `ISA1` (0xF) before the program
    (`$readmemh(..., InsnMem, 1)`).
  - `read_tx` read `tx_vld` right after the handshake edge, when the Moore FSM
    had already dropped it, so 11 of 13 characters were lost. Fix: `tx_rdy` is
    raised and held, and `tx_vld`/`tx_data` are sampled on the falling edge of
    `Clk`.
  - `check_ip_moving` ran after the program with `RunOnSoftRst = 1` left over,
    so its soft reset ran the program again. Fix: it clears `RunOnSoftRst`.
- The watchdog did `$error` + `$finish`, which exits 0 in Icarus, so a hang
  counted as a pass. It is now `$fatal`.

Now `DekatronPC_tb_cfg_hello.svh` and `_cfg_program.svh` define `TRY_PROGRAM`.
Both programs load through the bootloader, run and print the expected text.
Negative check: an `EXPECTED_OUTPUT` with one wrong character fails with exit
code 1.

### 2.2 `DekatronPC_tb.cpp` (Verilator + dpcrun): nothing was compared

`veremul` printed `CPU_CLK_UNHALTED = 12, IRET = 0` and exited 0. Causes:

1. The program memory (`IpMemory`, bank tree) has no preload. `-DIPMEMFILE` is
   no longer used anywhere in the RTL, so the RTL ran an empty memory.
2. `rst_n` was never pulsed, and the Run key was pressed while the power-on and
   soft-reset time relay was still busy, so it was lost. The RTL never left
   halt.
3. `run_tests.sh` didn't pass `-s`, so there was no per-step comparison, and
   the program always exited `EXIT_SUCCESS`.

Fix:

- Start-up follows the panel. A `rst_n` pulse leads to the power-on Hard Reset
  and a halt. The SoftRst key gives IP = 0 in BF ISA. Then the
  `InsnLoadingStart` key, and the program (`dpc::assemble()`, ending in HALT,
  ISA0, EOT) goes over `InsnIn`/`InsnInValid`/`InsnInReady`. With
  `SoftRstOnEOT = RunOnSoftRst = 1`, the EOT gives a Soft Reset and the program
  starts. That matches `softReset()` + `run()` in the model.
- RTL `IRET` also counts the opcodes accepted during loading and isn't cleared
  by Soft Reset. It is compared relative to its value at the end of the load.
- Final verdict: both machines halted, the RTL retired at least one instruction,
  and the final state and terminal output match. Otherwise the exit code is 1.
  Without `-s` the model runs to halt and only the final state is compared.
- `run_tests.sh` runs with `-s`. The per-step trace goes to
  `<program>.steps.log`, and its tail is printed on failure.

Result (Verilator 5.034):

| Program | Instructions compared | Output |
|---|---|---|
| `helloworld.bfk` | 400 | `Hello World!\n` |
| `program.bfk` | 5771 | `Hello from program.bfk!` |

Negative check: one corrupted opcode in the stream sent to the RTL is caught at
the first differing step (`tx_data_bcd 2 != model 4`). Without `-s` the final
verdict catches it.

The RTL matches the golden model on both programs, which is the first real
step-by-step comparison (REQ-GM-002). Not run: `rot13.bfk`,
`fractal.bfk` (commented out in `run_tests.sh`; rot13 needs input).
`pi.bfk` was added later with `-n` (no VCD), see `doc/pi_step_check.md`.

## 3. Unit testbenches (checked, no change)

`Dekatron_tb`, `Counter_tb`, `IpLine_tb`, `ApLine_tb`, `MachineCtrl_tb` count
errors, end with `$fatal` on failure, and have `$fatal` timeouts. Icarus 12
returns exit code 1 on `$fatal` and 0 on `$error`, which was checked.

## 4. Verification of the fix

A clean export of HEAD plus the changed files, `run_tests.sh -t` with Icarus
12.0 and Verilator 5.034: exit 0, all seven Icarus tests pass, and both
golden-model comparisons PASS. Verilator `--lint-only` for DekatronPC and
Emulator is clean.
