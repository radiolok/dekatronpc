# DekatronPC UVM Test Infrastructure

Cocotb-based layered testbench for the DekatronPC processor — a vacuum-tube computer implemented in SystemVerilog.

## Quick Start

```bash
cd vhdl/tb
make test_compare SIM=icarus        # single test
make test_insn_decoder SIM=icarus   # single test
make regression                     # full suite (~40 targets)
```

## Requirements

- Python 3.8+ with `cocotb>=2.0`, `pyuvm`, `cocotb-coverage`, `pytest`
- Icarus Verilog (iverilog) for module-level tests
- Verilator for full DPC/Emulator integration tests

```bash
pip install cocotb pyuvm cocotb-coverage pytest
```

## Directory Structure

```
vhdl/tb/
├── Makefile              # 40+ test targets for icarus and verilator
├── conftest.py           # Shared fixtures: clocks, reset, BCD utils
├── env/                  # UVM environments (base, dpc, emul)
├── agent/                # UVM agent stubs
├── scoreboard/           # Scoreboard stubs (CppMachine wrapper planned)
├── sequence/             # Sequence stubs
├── coverage/             # Coverage collector stubs
├── tests/                # All test modules (28 files, ~200 test functions)
│   ├── Impulse_wrapper.sv
│   ├── OneShot_wrapper.sv
│   ├── BinaryToHex_wrapper.sv
│   ├── OpcodeToSymbol_wrapper.sv
│   ├── SymbolToOpcode_wrapper.sv
│   ├── In12CathodeToPin_wrapper.sv
│   ├── uart_loopback_wrapper.sv
│   ├── test_compare.py
│   ├── test_impulse.py
│   ├── test_oneshot.py
│   ├── test_rs_latch.py
│   ├── test_clock_divider.py
│   ├── test_bcd_counter.py
│   ├── test_up_counter.py
│   ├── test_add.py
│   ├── test_dekatron_modules.py
│   ├── test_dekatron_carry.py
│   ├── test_dekatron_pulse.py
│   ├── test_dekatron_unit.py
│   ├── test_dekatron_counter.py
│   ├── test_ram.py
│   ├── test_ip_memory.py
│   ├── test_rom.py
│   ├── test_insn_loop_detect.py
│   ├── test_insn_decoder.py
│   ├── test_sequencer.py
│   ├── test_ms6205.py
│   ├── test_keyboard.py
│   ├── test_io_register.py
│   ├── test_uart.py
│   ├── test_uart_rx.py
│   ├── test_uart_loopback.py
│   ├── test_key_symbol.py
│   ├── test_seg7.py
│   └── test_conversions.py
└── utils/                # BCD conversion helpers, reset sequences
```

## Test Phases

| Phase | Modules | Tests | Status |
|-------|---------|-------|--------|
| 1. Logic Primitives | Compare, Impulse, OneShot, RsLatch, ClockDivider, BCDCounter, UpCounter, add | ~30 | Done |
| 2. Dekatron Subsystem | BcdToBin, BinToBcd, WriteAmp, CarrySignal, PulseSender, Dekatron, DekatronModule, DekatronCounter | ~47 | Done |
| 3. Memory | RAM, IpMemory, ROM | ~14 | Done |
| 4. DPC Core | InsnLoopDetector, InsnDecoder, ApLine (stub), IpLine (stub) | ~39 | Done |
| 5. Emulator Peripherals | Sequencer, MS6205, Keyboard, io_register, UART TX/RX/Loopback, KeyToSymbol, segment7 | ~47 | Done |
| 6. Conversions | AsciiToBcd, BcdToAscii, BcdToBinEnc, BinaryToHex, OpcodeToSymbol, SymbolToOpcode, In12CathodeToPin | ~18 | Done |
| 7. Integration | DekatronPC full (Verilator only), Emulator full | — | Stubs |

## Running Tests

### Single test
```bash
make test_compare SIM=icarus
```

### Multiple tests (selected)
```bash
for t in compare impulse add insn_decoder; do
    make test_$t SIM=icarus
done
```

### Full regression
```bash
make regression
```

### Verilator (for DPC integration)
```bash
make test_dpc SIM=verilator EXTRA_ARGS="--timing -Wno-fatal -DEMULATOR=1"
```

## Key Conventions

- **Signal access**: `int(dut.signal.value)` — not `.value.integer`
- **Timers**: `await Timer(N, unit="ns")` — not `units=`
- **Clock**: `Clock(dut.Clk, period, unit="ns")` + `cocotb.start_soon(clock.start())`
- **Reset**: 3-phase async reset via `dut.Rst_n.value = 0/1`
- **Ready/Request handshake**: level-based protocol — assert Request, wait for Ready, deassert Request

## Known RTL Bugs Captured by Tests

1. **add.sv typo** (`vhdl/Logic/add.sv:12`): `{c0, y}` → fixed to `{co, y}` with `assign` instead of broken `always_comb`. Test `test_add_exhaustive` validates 256 input combinations.

2. **OneShot DELAY=1 counter bug** (`vhdl/Logic/OneShot.sv`): `WIDTH=$clog2(1)=1` produces 2-bit counter rolling after 4 ticks instead of 1. Test `test_oneshot_basic` documents this.

3. **Sequencer race condition** (`vhdl/Emulator/Sequencer.sv`): Dual `negedge` blocks create non-deterministic behavior. Tests use ±1 cycle tolerance sampling.

## Wrapper Modules

Some modules have output signals named identically to the module (e.g., `Impulse` module has `output wire Impulse`). Cocotb VPI resolution can confuse the module name with the signal name. Wrapper modules (`*_wrapper.sv`) rename the output to `pulse_out` to avoid this collision.

## Future Work

- **RAM test parameterization**: Default ROWS=30000 causes slow reset initialization. Override with smaller ROWS for faster simulation.
- **CppMachine shared library**: Compile `dpcrun.cpp` as `libdpcrun.so` for Python ctypes scoreboard integration.
- **Coverage collection**: Enable Verilator `--coverage` and integrate `cocotb-coverage` functional coverage groups.
- **DekatronModule standalone test**: Module instantiation needs `parameters.sv` and full Dekatron subsystem sources.
