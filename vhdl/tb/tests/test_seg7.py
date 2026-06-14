"""
Tests for segment7 module — combinational 7-segment display decoder.

Converts a 4-bit hex input to a 7-bit segment pattern (active-high segments).
Segments: {a, b, c, d, e, f, g} (7 bits, MSB = a).
"""

import cocotb
from cocotb.triggers import Timer

import logging
log = logging.getLogger(__name__)

# Expected segment patterns from segment7.sv
# Order: seg[6:0] = {a, b, c, d, e, f, g}
SEG_PATTERNS = {
    0x0: 0b0111111,
    0x1: 0b0000110,
    0x2: 0b1011011,
    0x3: 0b1001111,
    0x4: 0b1100110,
    0x5: 0b1101101,
    0x6: 0b1111101,
    0x7: 0b0000111,
    0x8: 0b1111111,
    0x9: 0b1101111,
    0xA: 0b1110111,
    0xB: 0b1111100,
    0xC: 0b0111001,
    0xD: 0b1011110,
    0xE: 0b1111001,
    0xF: 0b1110001,
}


@cocotb.test()
async def test_seg7_digits_0_to_9(dut):
    """Verify segment patterns for BCD digits 0-9."""
    for digit in range(10):
        dut.hex.value = digit
        await Timer(1, unit="ns")
        actual = int(dut.seg.value)
        expected = SEG_PATTERNS[digit]
        assert actual == expected, (
            f"Digit {digit}: expected seg={expected:#09b}, got {actual:#09b}"
        )


@cocotb.test()
async def test_seg7_hex_a_to_f(dut):
    """Verify segment patterns for hex digits A-F."""
    for digit in range(0xA, 0x10):
        dut.hex.value = digit
        await Timer(1, unit="ns")
        actual = int(dut.seg.value)
        expected = SEG_PATTERNS[digit]
        assert actual == expected, (
            f"Digit {digit:#x}: expected seg={expected:#09b}, got {actual:#09b}"
        )


@cocotb.test()
async def test_seg7_all_inputs(dut):
    """Exhaustive test of all 16 input values."""
    for i in range(16):
        dut.hex.value = i
        await Timer(1, unit="ns")
        actual = int(dut.seg.value)
        expected = SEG_PATTERNS[i]
        assert actual == expected, (
            f"Input {i:#x}: expected seg={expected:#09b}, got {actual:#09b}"
        )


@cocotb.test()
async def test_seg7_zero_all_off(dut):
    """Quick check: input 0 should have segments a,b,c,d,e,f on, g off."""
    dut.hex.value = 0
    await Timer(1, unit="ns")
    actual = int(dut.seg.value)
    # 0b0111111 = segments a-f on, g off
    assert actual == 0b0111111, f"Digit 0: expected 0b0111111, got {actual:#09b}"


@cocotb.test()
async def test_seg7_eight_all_on(dut):
    """Quick check: input 8 should have all segments on."""
    dut.hex.value = 8
    await Timer(1, unit="ns")
    actual = int(dut.seg.value)
    assert actual == 0b1111111, f"Digit 8: expected 0b1111111 (all on), got {actual:#09b}"


@cocotb.test()
async def test_seg7_one_segments(dut):
    """Quick check: input 1 should have only segments b and c on."""
    dut.hex.value = 1
    await Timer(1, unit="ns")
    actual = int(dut.seg.value)
    assert actual == 0b0000110, f"Digit 1: expected 0b0000110 (b,c on), got {actual:#09b}"
