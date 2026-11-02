"""
Tests for KeyToSymbol module — combinational conversion of numeric key to symbol.

KeyToSymbol uses OpcodeToSymbol(BinaryToHex(numericKey)): a one-hot encoded
numeric key (0-F) is an ISA16 opcode (doc/isa16.md), printed as its symbol.
"""

import cocotb
from cocotb.triggers import Timer

import logging
log = logging.getLogger(__name__)

ISA16_SYMBOLS = " H+-><[].,0SAP{}"


@cocotb.test()
async def test_key_symbol_all_hex_digits(dut):
    """All 16 one-hot keys (0-F) give the ISA16 symbol of that opcode."""
    for digit in range(16):
        dut.numericKey.value = 1 << digit
        await Timer(1, unit="ns")
        sym = int(dut.symbol.value)
        exp = ord(ISA16_SYMBOLS[digit])
        assert sym == exp, f"Key {digit:X}: expected {chr(exp)!r}, got {sym:#x}"


@cocotb.test()
async def test_key_symbol_no_key(dut):
    """When numericKey=0, BinaryToHex gives 0 and the symbol is space (NOP)."""
    dut.numericKey.value = 0
    await Timer(1, unit="ns")
    assert int(dut.symbol.value) == ord(" ")


@cocotb.test()
async def test_key_symbol_multiple_keys(dut):
    """Several keys at once: BinaryToHex falls to its default 0 -> space."""
    dut.numericKey.value = 0x0120  # bits 5 and 8
    await Timer(1, unit="ns")
    sym = int(dut.symbol.value)
    log.info(f"Multiple keys -> symbol={sym:#x}")
    assert sym == ord(" ")
