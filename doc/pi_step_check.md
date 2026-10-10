# pi.bfk: step-by-step check of the RTL against the golden model

Date: 2026-10-08. RTL at `2f91d76` (with P3 prefetch), bfutils `651cb62`.
Requirements: REQ-GM-002, REQ-PERF-003, REQ-CNT-005 / OPEN-001, REQ-MEM-DATA-005.

## 1. Result

`rtl/programs/pi.bfk` runs to HALT on the full `DekatronPC` in Verilator and
matches the golden model `dpcrun` on **every one of 221 386 retired
instructions** (`DekatronPC_tb.cpp -s`): IRET, IP (prefetch-aware), AP,
Data counter (`tx_data_bcd`), LoopCount and terminal output. Exit code 0:

```
VDekatronPC Done. state.CPU_CLK_UNHALTED = 3171964, IRET=221386
  Clk        3171964 cycles,    144.567 kHz simulated (slowdown 6.9x)
  IRET        221386 insns,    10090.0 insn/s
PASS: RTL matches the model, output "3.141
"
```

Wall time 22 s; the Verilator build took about 1 min.

## 2. Why this counts as proof

1. **Every step compared, by the testbench.** `compareStates()` runs after each
   retire. Any difference ends the run with a non-zero exit code.
2. **The step log re-checked separately.** A short script read all 221 386
   lines of the log and compared both columns again (RTL, model). It found 0
   mismatches. On 161 251 steps IP is model IP + 1: that's the P3 prefetch,
   which the testbench accepts by design. The last step's status is `Halted`.
3. **A third reference, independent of dpcrun.** A plain Python Brainfuck
   interpreter (8-bit cells, unbounded tape) prints the same `'3.141\n'`.
   It executes 198 594 BF operations (the same figure as TRS §4.4), with 17 076
   backward jumps and 5 715 forward skips. The machine's IRET reconciles
   exactly: 198 594 + 17 076 + 5 715 + 1 (HALT) = 221 386. The machine stops
   a loop scan on the matching bracket and then executes that bracket, so it
   costs one extra retire per jump.
4. **Output is correct.** π = 3.14159…; the program prints 4 digits, `3.141`.

## 3. What the run covers

- 221 386 instructions and about 3.17 M clk cycles. 55 723 memory reads and
  43 354 writes (dpcrun count, lazy reads, REQ-APV2-001).
- **AP wrap below zero.** The 6th instruction is `<` from cell 0. The program
  uses cell −1 as a scratch cell and crosses the 0 ↔ top boundary 19 times.
  It touches 66 cells.
- 6 COUT, no CIN.
- Loop scans with up to 11 levels of nesting (TRS §4.4). **Gap:** retires
  happen only after a scan finishes, so the compare always sees
  `LoopCount = 0`. The counter's values *during* the scan are not checked
  against the model here. IpLine_tb covers them.

## 4. Finding: AP limit in RTL vs model (OPEN-001)

The first run failed at instruction 6: `FATAL: ApAddress 99999 != model 29999`.

- RTL: in `ApLine.sv` the AP counter is a `DekatronCounter` with
  `TOP_LIMIT_MODE = 0`. The `AP_TOP_VALUE = 29999` parameter is declared but
  not connected, so AP wraps 0 ↔ 99999. The data `Ram` uses
  `D_NUM = AP_DEKATRON_NUM`, which gives 100 000 cells. The owner confirmed
  that the RTL now works with 100k data RAM.
- dpcrun: `Config::apTop` defaults to `AP_TOP_BF = 29999`.

The program's result doesn't depend on the limit: cell −1 is just a spare
cell. `dpcrun -a 99999` gives the same output and instruction count. The
testbench now builds the model with `apTop = 99999`, as in the RTL, and
`-a <top>` overrides it. OPEN-001 itself is still open: it decides whether
AP stays at 99999 or gets a 29999 top limit back. If it goes to 29999,
connect `AP_TOP_VALUE` with `TOP_LIMIT_MODE = 1` in ApLine and run the tb
with `-a 29999`.

## 5. Testbench changes (`rtl/tests/DekatronPC.sv/DekatronPC_tb.cpp`)

- `-n`: no VCD dump. A full trace of pi would be tens of GB. The default
  (trace on) is unchanged for `run_tests.sh`.
- `-a <top>`: the model's AP limit, default 99999 to match the RTL.

## 6. Reproduce

```
cd rtl/run
g++ -c ../../bfutils/dpcrun/dpcrun.cpp -o dpcrun.o && ar rcs libdpcrun.a dpcrun.o
python3 generate_rom.py -f ../programs/pi.bfk -o ../firmware.hex --hex
verilator -Wall --trace -DSIM_TRACE --top DekatronPC --cc $(cat ../DekatronPC/DPC.files) \
  "-GEN_EMULATOR=1'b1" ../libdpcrun.a -CFLAGS -I$(realpath ../../bfutils/dpcrun) \
  -DEMULATOR=1 -DIPMEMFILE --timescale 1us/1ns rules.vlt \
  --exe ../tests/DekatronPC.sv/DekatronPC_tb.cpp --Mdir obj_pi
make -j8 -C obj_pi -f VDekatronPC.mk VDekatronPC
./obj_pi/VDekatronPC -f ../programs/pi.bfk -s -n </dev/null 2>pi.steps.log
```

The same `obj_pi` binary runs any program: the program is loaded over
`InsnIn` at run time.

`run_tests.sh -t` runs pi too: `veremul` takes extra testbench flags as its
third argument, and pi gets `-n`. The step log is `rtl/run/pi.bfk.steps.log`.
