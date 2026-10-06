# cocotb/"UVM" testbench check (tb/)

Date: 2026-10-06. Branch `claude_nextGen`. Related: REQ-VER-029, REQ-VER-027, TRS §22.

## 1. Environment

| Tool | Version | Note |
|---|---|---|
| Icarus Verilog | 13.0 (devel) | already installed |
| Verilator | 5.034 | already installed, not needed for `make regression` |
| Python | 3.10.12 | |
| cocotb | 2.1.0 | installed into `~/.venvs/dekatronpc` |
| pyuvm | 5.0.0 | installed, but no test imports it (see §3) |
| pytest, liberty-parser | latest | same set as the CI image (`Dockerfile`) |

**Pitfall:** `cocotb-coverage` (listed in tb/README.md) pins `cocotb<2`. With it installed, pip
resolves cocotb 1.9.2 and the tests break (they use the 2.x `unit=` keyword). CI does not install
it, and `conftest.py` imports it inside `try`. Don't install it next to cocotb 2.x.

Setup used:

```bash
python3 -m venv ~/.venvs/dekatronpc
~/.venvs/dekatronpc/bin/pip install liberty-parser "cocotb>=2.0" pyuvm pytest
source ~/.venvs/dekatronpc/bin/activate && cd tb && make regression
```

## 2. Regression result

`make regression` (Icarus only, 34 targets, ~80 s on 24 cores): **34/34 targets pass, 0 failures.**
Per-target `TESTS=` lines were checked, so every listed cocotb test actually ran.

## 3. Findings

### 3.1 Tests that passed without checking anything (fixed)

These tests used `if ok: assert … else: log.warning(…)`, so a failure only printed a warning.

| Test | Cause | Fix |
|---|---|---|
| `test_uart_rx.test_uart_rx_receive_byte`, `test_uart_rx_multiple_bytes` | With `i_rdy=1`, `o_vld` is a one-cycle pulse in the middle of the stop bit, while `feed_serial_byte()` is still driving it. The poll loop started afterwards and always missed it. The multi-byte test checked nothing at all. | A background `collect_rx()` monitor records every `o_vld&i_rdy` handshake, then the test asserts the full byte list. |
| `test_uart_loopback.test_uart_loopback`, `_multiple` | Same issue: the wrapper ties RX `i_rdy` to 1. | Same monitor approach, plus a `send_byte()` helper. |
| `test_oneshot.test_oneshot_basic` | `En` was never released. With `IMP_ON_EN=1`, `Impulse = \|count \| En`, so it measured 20 cycles and only warned. | One-cycle `En`, then assert `width == DELAY` (1). |

After the fixes, all of these pass with real assertions. **The UART RX RTL and OneShot RTL are correct.**
The README's "known bug: OneShot DELAY=1 gives 4-cycle pulse" doesn't exist. With `DELAY_COMP=0`, the
counter clears on the same edge it would increment, which gives exactly one cycle. The README is corrected.

### 3.2 Still soft (not fixed, Emulator layer)

`test_ms6205` logs three warnings and still passes:

- the address scan saw only 1 unique address (expected ≥10);
- the written byte 0x41 is not found at address 0;
- `marker=1` while `DPC_State=0`.

Either the test drives MS6205 at the wrong rate or the block misbehaves. MS6205 is FPGA-only and low
priority, so this was left for a separate look.

### 3.3 "UVM" is in name only

No test imports `pyuvm`. `tb/env/dpc_env.py` (83 lines) is not used by any test, and `agent/`,
`scoreboard/`, `sequence/` and `coverage/` are one-line `__init__.py` stubs. All tests are plain
`@cocotb.test()` functions.

### 3.4 What the regression does and doesn't cover

- **Covered (current RTL):** DekatronPulseSender, DekatronCounter, Ram, IpMemory, ROM, Emulator peripherals, codecs.
- **Still in the regression, but these blocks are due for removal (TRS 19.4):** `dek_carry` (DekatronCarrySignal),
  `dekatron_unit` (Dekatron.sv), `insn_decoder` (InsnDecoder), `loop_detect` (InsnLoopDetector), `bcd_bin` (BcdToBinEnc).
- **Not covered (the TRS §22 priority 2 list):** ApLine, IpLine, MachineCtrl, DekatronModule, DekatronPC.
  The Makefile targets `test_ap_line`, `test_ip_line`, `test_dpc` and `test_dekatron_module` point at test files
  that don't exist (`test_ap_line.py`, `test_ip_line.py`, `test_dpc_integration.py`, `test_dekatron_module.py`).
  `test_dekatron_module` also lists `BcdToBin.v`, which no longer exists.
  `test_write_amp` targets the obsolete DekatronWriteAmp. None of these are in `make regression`.

### 3.5 Regression summary grouping (fixed)

The summary printed one row per test (`Logic 1`, `impulse 1`, …) because only the first word of each
`Group:` list carried the group name. The group name now carries forward, giving
Logic 7 / Dekatron 6 / Memory 3 / DPC 2 / Emulator 9 / Functions 7.

## 4. Changed files

- `tb/tests/test_uart_rx.py`, `tb/tests/test_uart_loopback.py`, `tb/tests/test_oneshot.py`: hard assertions (§3.1).
- `tb/Makefile`: summary grouping (§3.5).
- `tb/README.md`: removed the false OneShot bug and added the cocotb-coverage pitfall.

## 5. Suggested next steps

1. Write the missing ApLine / IpLine / MachineCtrl cocotb tests (REQ-VER-029, TRS §22 item 2). This is where a pyuvm
   env with a `dpcrun` scoreboard would pay off.
2. Make `test_ms6205` assert, then find out whether the test or the block is wrong.
3. Remove the dead Makefile targets, or create their tests, and drop the old-block targets when those modules are removed.
