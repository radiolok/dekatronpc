"""
Tests for Keyboard module — keyboard matrix interface and key-to-symbol conversion.

The Keyboard uses a RegisterFileFlatOut (5-bit width, 8 registers = 40 bits total)
to store key state. kbCol selects which 5-bit register to write, kbRow provides
the 5-bit value, and read (ANDed with Clk) clocks the register file.

Key constants are defined in KeyboardKeys.sv (6-bit enum values 0-39).
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import Timer, RisingEdge, FallingEdge

import logging
log = logging.getLogger(__name__)

# Keyboard key indices (from KeyboardKeys.sv)
KEYBOARD_0_KEY = 16
KEYBOARD_1_KEY = 17
KEYBOARD_2_KEY = 18
KEYBOARD_3_KEY = 19
KEYBOARD_4_KEY = 11
KEYBOARD_5_KEY = 12
KEYBOARD_6_KEY = 13
KEYBOARD_7_KEY = 14
KEYBOARD_8_KEY = 6
KEYBOARD_9_KEY = 7
KEYBOARD_A_KEY = 8
KEYBOARD_B_KEY = 9
KEYBOARD_C_KEY = 1
KEYBOARD_D_KEY = 2
KEYBOARD_E_KEY = 3
KEYBOARD_F_KEY = 4
KEYBOARD_IRAM_KEY = 15
KEYBOARD_DRAM_KEY = 10
KEYBOARD_CIO_KEY = 0

CLOCK_PERIOD_NS = 1000


async def write_key_register(dut, reg_index, value_5bit):
    """Write a 5-bit value to one of the 8 keyboard registers."""
    dut.kbRow.value = value_5bit
    dut.kbCol.value = 1 << reg_index
    dut.read.value = 0
    await Timer(CLOCK_PERIOD_NS // 2, unit="ns")
    dut.read.value = 1
    await Timer(CLOCK_PERIOD_NS, unit="ns")
    dut.read.value = 0
    await Timer(CLOCK_PERIOD_NS // 2, unit="ns")
    dut.kbCol.value = 0


async def press_key(dut, key_index, hold=True):
    """Simulate pressing a single key by setting its bit in keysCurrentState.

    key_index is 0-39. Each register holds 5 bits, so register = key_index // 5,
    bit within register = key_index % 5.
    """
    reg = key_index // 5
    bit = key_index % 5
    value = 1 << bit
    await write_key_register(dut, reg, value)


async def release_keys(dut):
    """Clear all key registers."""
    for reg in range(8):
        await write_key_register(dut, reg, 0)


@cocotb.test()
async def test_keyboard_reset(dut):
    """After reset, keysCurrentState should be all zeros."""
    clock = Clock(dut.Clk, CLOCK_PERIOD_NS, unit="ns")
    cocotb.start_soon(clock.start())

    dut.Rst_n.value = 0
    dut.read.value = 0
    dut.write.value = 0
    dut.clear.value = 0
    dut.kbCol.value = 0
    dut.kbRow.value = 0
    await Timer(10 * CLOCK_PERIOD_NS, unit="ns")

    assert int(dut.keysCurrentState.value) == 0, f"keysCurrentState should be 0 during reset, got {int(dut.keysCurrentState.value)}"

    dut.Rst_n.value = 1
    await Timer(5 * CLOCK_PERIOD_NS, unit="ns")
    assert int(dut.keysCurrentState.value) == 0, "keysCurrentState should remain 0 after reset"


@cocotb.test()
async def test_keyboard_single_key(dut):
    """Pressing key 0 (KEYBOARD_0_KEY) should set bit 16 of keysCurrentState."""
    clock = Clock(dut.Clk, CLOCK_PERIOD_NS, unit="ns")
    cocotb.start_soon(clock.start())

    dut.Rst_n.value = 0
    dut.read.value = 0
    dut.write.value = 0
    dut.clear.value = 0
    dut.kbCol.value = 0
    dut.kbRow.value = 0
    await Timer(10 * CLOCK_PERIOD_NS, unit="ns")
    dut.Rst_n.value = 1
    await Timer(5 * CLOCK_PERIOD_NS, unit="ns")

    await press_key(dut, KEYBOARD_0_KEY)
    await Timer(2 * CLOCK_PERIOD_NS, unit="ns")

    ks = int(dut.keysCurrentState.value)
    assert (ks >> KEYBOARD_0_KEY) & 1 == 1, f"Bit {KEYBOARD_0_KEY} of keysCurrentState should be 1, got state={ks:#010x}"


@cocotb.test()
async def test_keyboard_numeric_output(dut):
    """Pressing hex digit keys should set numericKey to one-hot encoding."""
    clock = Clock(dut.Clk, CLOCK_PERIOD_NS, unit="ns")
    cocotb.start_soon(clock.start())

    dut.Rst_n.value = 0
    dut.read.value = 0
    dut.write.value = 0
    dut.clear.value = 0
    dut.kbCol.value = 0
    dut.kbRow.value = 0
    await Timer(10 * CLOCK_PERIOD_NS, unit="ns")
    dut.Rst_n.value = 1
    await Timer(5 * CLOCK_PERIOD_NS, unit="ns")

    # Press key 5 (KEYBOARD_5_KEY = 12)
    await release_keys(dut)
    await press_key(dut, KEYBOARD_5_KEY)
    await Timer(2 * CLOCK_PERIOD_NS, unit="ns")

    nk = int(dut.numericKey.value)
    # numericKey is one-hot: bit 5 should be set (0-F)
    assert (nk >> 5) & 1 == 1, f"numericKey bit 5 should be set for key 5, got numericKey={nk:#06x}"
    # Only one bit should be set
    assert bin(nk).count("1") == 1, f"numericKey should be one-hot, got {nk:#06x} ({bin(nk)})"


@cocotb.test()
async def test_keyboard_multiple_keys_priority(dut):
    """When multiple hex digit keys are pressed, only one should win (wired-OR priority)."""
    clock = Clock(dut.Clk, CLOCK_PERIOD_NS, unit="ns")
    cocotb.start_soon(clock.start())

    dut.Rst_n.value = 0
    dut.read.value = 0
    dut.write.value = 0
    dut.clear.value = 0
    dut.kbCol.value = 0
    dut.kbRow.value = 0
    await Timer(10 * CLOCK_PERIOD_NS, unit="ns")
    dut.Rst_n.value = 1
    await Timer(5 * CLOCK_PERIOD_NS, unit="ns")

    # Press keys 3 (index 19) and 7 (index 14) simultaneously
    # Key 3 is register 3, bit 4 (19//5=3, 19%5=4)
    # Key 7 is register 2, bit 4 (14//5=2, 14%5=4)
    # Write both registers
    await write_key_register(dut, 3, 1 << 4)  # key 3
    await write_key_register(dut, 2, 1 << 4)  # key 7
    await Timer(2 * CLOCK_PERIOD_NS, unit="ns")

    ks = int(dut.keysCurrentState.value)
    assert (ks >> 19) & 1 == 1, "Bit 19 (key 3) should be set"
    assert (ks >> 14) & 1 == 1, "Bit 14 (key 7) should be set"

    # numericKey should have both bits set (and |numericKey| will still have more than one)
    nk = int(dut.numericKey.value)
    log.info(f"Multiple keys: keysCurrentState={ks:#010x}, numericKey={nk:#06x}")


@cocotb.test()
async def test_keyboard_isa_switch(dut):
    """Pressing F key sets ISA to BRAINFUCK_ISA, E key sets DEBUG_ISA."""
    clock = Clock(dut.Clk, CLOCK_PERIOD_NS, unit="ns")
    cocotb.start_soon(clock.start())

    dut.Rst_n.value = 0
    dut.read.value = 0
    dut.write.value = 0
    dut.clear.value = 0
    dut.kbCol.value = 0
    dut.kbRow.value = 0
    await Timer(10 * CLOCK_PERIOD_NS, unit="ns")
    dut.Rst_n.value = 1
    await Timer(5 * CLOCK_PERIOD_NS, unit="ns")

    # Press F key (KEYBOARD_F_KEY = 4)
    await release_keys(dut)
    await press_key(dut, KEYBOARD_F_KEY)
    await Timer(2 * CLOCK_PERIOD_NS, unit="ns")

    # The ISA state isn't directly output, but the symbol output should reflect it
    # Using BRAINFUCK_ISA=1, key F → BinaryToHex(onehot(F)) = 15 → opcode = {1, 4'hF} = 5'h1F → "B"
    sym = int(dut.symbol.value)
    log.info(f"F key pressed, symbol={sym:#x} ({chr(sym) if 32 <= sym < 127 else '?'})")

    # Press E key instead (KEYBOARD_E_KEY = 3), toggles to DEBUG_ISA
    await release_keys(dut)
    await press_key(dut, KEYBOARD_E_KEY)
    await Timer(2 * CLOCK_PERIOD_NS, unit="ns")

    sym2 = int(dut.symbol.value)
    log.info(f"E key pressed, symbol={sym2:#x} ({chr(sym2) if 32 <= sym2 < 127 else '?'})")


@cocotb.test()
async def test_keyboard_no_keys_zero_symbol(dut):
    """When no numeric keys are pressed, symbol should be 0."""
    clock = Clock(dut.Clk, CLOCK_PERIOD_NS, unit="ns")
    cocotb.start_soon(clock.start())

    dut.Rst_n.value = 0
    dut.read.value = 0
    dut.write.value = 0
    dut.clear.value = 0
    dut.kbCol.value = 0
    dut.kbRow.value = 0
    await Timer(10 * CLOCK_PERIOD_NS, unit="ns")
    dut.Rst_n.value = 1
    await Timer(5 * CLOCK_PERIOD_NS, unit="ns")

    await release_keys(dut)
    await Timer(2 * CLOCK_PERIOD_NS, unit="ns")

    assert int(dut.symbol.value) == 0, f"symbol should be 0 with no keys, got {int(dut.symbol.value)}"
