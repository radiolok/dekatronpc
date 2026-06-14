"""
Tests for the InsnLoopDetector module.

InsnLoopDetector: combinational loop instruction detector.
- isLoopInsn = ~Insn[3] & Insn[2] & Insn[1]  (matches 4'b011x)
- LoopOpen = isLoopInsn & ~Insn[0]  (opcode 0x6 = '[')
- LoopClose = isLoopInsn & Insn[0]  (opcode 0x7 = ']')
"""

import cocotb
from cocotb.triggers import Timer

import logging
log = logging.getLogger(__name__)


@cocotb.test()
async def test_exhaustive_all_opcodes(dut):
    """Exhaustively test all 16 opcodes for LoopOpen/LoopClose."""
    for insn in range(16):
        dut.Insn.value = insn
        await Timer(1, unit="ns")

        is_loop = (insn & 0b1110) == 0b0110  # ~bit3 & bit2 & bit1
        expected_open = 1 if (is_loop and (insn & 1) == 0) else 0
        expected_close = 1 if (is_loop and (insn & 1) == 1) else 0

        got_open = int(dut.LoopOpen.value)
        got_close = int(dut.LoopClose.value)

        assert got_open == expected_open, (
            f"Insn=0x{insn:X}: expected LoopOpen={expected_open}, got {got_open}"
        )
        assert got_close == expected_close, (
            f"Insn=0x{insn:X}: expected LoopClose={expected_close}, got {got_close}"
        )


@cocotb.test()
async def test_loop_open(dut):
    """Insn=0x6 ('[') → LoopOpen=1, LoopClose=0."""
    dut.Insn.value = 0x6
    await Timer(1, unit="ns")
    assert int(dut.LoopOpen.value) == 1, "Insn=0x6 should assert LoopOpen"
    assert int(dut.LoopClose.value) == 0, "Insn=0x6 should deassert LoopClose"


@cocotb.test()
async def test_loop_close(dut):
    """Insn=0x7 (']') → LoopOpen=0, LoopClose=1."""
    dut.Insn.value = 0x7
    await Timer(1, unit="ns")
    assert int(dut.LoopOpen.value) == 0, "Insn=0x7 should deassert LoopOpen"
    assert int(dut.LoopClose.value) == 1, "Insn=0x7 should assert LoopClose"


@cocotb.test()
async def test_non_loop_opcodes(dut):
    """All non-loop opcodes produce LoopOpen=0 and LoopClose=0."""
    for insn in range(16):
        if insn in (0x6, 0x7):
            continue
        dut.Insn.value = insn
        await Timer(1, unit="ns")
        assert int(dut.LoopOpen.value) == 0, (
            f"Insn=0x{insn:X}: LoopOpen should be 0, got {int(dut.LoopOpen.value)}"
        )
        assert int(dut.LoopClose.value) == 0, (
            f"Insn=0x{insn:X}: LoopClose should be 0, got {int(dut.LoopClose.value)}"
        )
