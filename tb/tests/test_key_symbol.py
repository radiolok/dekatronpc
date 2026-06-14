"""
Tests for KeyToSymbol module — combinational conversion of numeric key to symbol.

KeyToSymbol uses OpcodeToSymbol({BFISA, BinaryToHex(numericKey)}) to map
a one-hot encoded numeric key (0-F) plus ISA selection to an ASCII symbol.
"""

import cocotb
from cocotb.triggers import Timer

import logging
log = logging.getLogger(__name__)


@cocotb.test()
async def test_key_symbol_zero(dut):
    """Key 0 (one-hot bit 0) with BFISA=1 should produce symbol '0'."""
    dut.numericKey.value = 0x0001  # key 0
    dut.BFISA.value = 1
    await Timer(1, unit="ns")
    sym = int(dut.symbol.value)
    log.info(f"Key 0, BFISA=1 -> symbol={sym:#x} ({chr(sym) if 32 <= sym < 127 else '?'})")
    # OpcodeToSymbol({1, 4'h0}) = "N" (5'h10 → 0x4E)
    assert sym == ord("N"), f"Expected 'N' (0x4E), got {sym:#x}"


@cocotb.test()
async def test_key_symbol_one(dut):
    """Key 1 (one-hot bit 1) with BFISA=1 should produce symbol 'H'."""
    dut.numericKey.value = 0x0002  # key 1
    dut.BFISA.value = 1
    await Timer(1, unit="ns")
    sym = int(dut.symbol.value)
    # OpcodeToSymbol({1, 4'h1}) = "H" (5'h11 → 0x48)
    assert sym == ord("H"), f"Expected 'H' (0x48), got {sym:#x}"


@cocotb.test()
async def test_key_symbol_bfisa_plus(dut):
    """Key 2 with BFISA=1 -> '+'."""
    dut.numericKey.value = 0x0004  # key 2 (one-hot)
    dut.BFISA.value = 1
    await Timer(1, unit="ns")
    sym = int(dut.symbol.value)
    # OpcodeToSymbol({1, 4'h2}) = "+" (5'h12 → 0x2B)
    assert sym == ord("+"), f"Expected '+' (0x2B), got {sym:#x}"


@cocotb.test()
async def test_key_symbol_bfisa_minus(dut):
    """Key 3 with BFISA=1 -> '-'."""
    dut.numericKey.value = 0x0008  # key 3
    dut.BFISA.value = 1
    await Timer(1, unit="ns")
    sym = int(dut.symbol.value)
    # OpcodeToSymbol({1, 4'h3}) = "-" (5'h13 → 0x2D)
    assert sym == ord("-"), f"Expected '-' (0x2D), got {sym:#x}"


@cocotb.test()
async def test_key_symbol_debug_isa(dut):
    """Key 0 with BFISA=0 (debug ISA) -> 'N'."""
    dut.numericKey.value = 0x0001  # key 0
    dut.BFISA.value = 0
    await Timer(1, unit="ns")
    sym = int(dut.symbol.value)
    # OpcodeToSymbol({0, 4'h0}) = "N" (5'h00 → casez 5'h?0 → "N")
    assert sym == ord("N"), f"Expected 'N' (0x4E), got {sym:#x}"


@cocotb.test()
async def test_key_symbol_no_key(dut):
    """When numericKey=0, symbol should be 'N' (via BinaryToHex default)."""
    dut.numericKey.value = 0x0000
    dut.BFISA.value = 1
    await Timer(1, unit="ns")
    sym = int(dut.symbol.value)
    # BinaryToHex(0) = 0, OpcodeToSymbol({1, 0}) = "N"
    assert sym == ord("N"), f"Expected 'N' (0x4E) for no key, got {sym:#x}"


@cocotb.test()
async def test_key_symbol_all_hex_digits(dut):
    """Test all 16 one-hot keys (0-F) with BFISA=1."""
    # Expected symbols from OpcodeToSymbol for opcodes {1, hex_digit}
    # 5'h10..5'h1F (BFISA=1)
    # casez mappings: 5'h?0→"N", 5'h?1→"H", 5'h02→"+", 5'h03→"-",
    #   5'h04→">", 5'h05→"<", 5'h06→"[", 5'h07→"]",
    #   5'h08→".", 5'h09→",", 5'h?A→"0", 5'h0B→"A",
    #   5'h0C→"R", 5'h0D→"r", 5'h?E→"D", 5'h?F→"B",
    #   5'h1B→"M" (exact match overrides casez ?A for 5'h0B)
    expected_bf = {
        0:  "N",  1:  "H",  2:  "+",  3:  "-",
        4:  ">",  5:  "<",  6:  "[",  7:  "]",
        8:  ".",  9:  ",",  10: "0",  11: "M",
        12: "G",  13: "P",  14: "D",  15: "B",
    }

    for digit in range(16):
        onehot = 1 << digit
        dut.numericKey.value = onehot
        dut.BFISA.value = 1
        await Timer(1, unit="ns")
        sym = int(dut.symbol.value)
        expected_ch = expected_bf[digit]
        assert sym == ord(expected_ch), (
            f"Key {digit}: expected '{expected_ch}' ({ord(expected_ch):#x}), got {sym:#x}"
        )


@cocotb.test()
async def test_key_symbol_multiple_keys(dut):
    """When multiple one-hot bits are set, symbol should still be valid (BinaryToHex finds first)."""
    # Key 5 (onehot 0x20) and key A (onehot 0x100) both pressed
    dut.numericKey.value = 0x0120  # bits 5 and 8
    dut.BFISA.value = 1
    await Timer(1, unit="ns")
    sym = int(dut.symbol.value)
    # BinaryToHex with multiple bits set falls to default case => 0
    # So OpcodeToSymbol({1, 0}) = "N"
    log.info(f"Multiple keys -> symbol={sym:#x} ({chr(sym) if 32 <= sym < 127 else '?'})")
