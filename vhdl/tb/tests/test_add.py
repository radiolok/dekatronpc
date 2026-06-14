"""
Tests for the add module.

add: parameterized-width adder with carry-in and carry-out.
Interface: ci, a, b → y, co
WIDTH default = 3.
"""

import cocotb
from cocotb.triggers import Timer

import logging
log = logging.getLogger(__name__)


@cocotb.test()
async def test_add_exhaustive(dut):
    """add: exhaustive test for all combinations (3-bit width, 256 combos)."""
    for a in range(8):
        for b in range(8):
            for ci in range(2):
                dut.a.value = a
                dut.b.value = b
                dut.ci.value = ci
                await Timer(1, unit="ns")

                expected_sum = (a + b + ci) & 0x7
                expected_co = 1 if (a + b + ci) > 7 else 0

                y_val = int(dut.y.value)
                co_val = int(dut.co.value)

                if y_val != expected_sum or co_val != expected_co:
                    log.error(
                        f"add {a}+{b}+{ci}: expected sum={expected_sum} co={expected_co}, "
                        f"got y={y_val} co={co_val}"
                    )
                    assert False, f"add failure: {a}+{b}+{ci}"


@cocotb.test()
async def test_add_zero(dut):
    """add: zero inputs produce zero outputs."""
    dut.a.value = 0
    dut.b.value = 0
    dut.ci.value = 0
    await Timer(1, unit="ns")
    assert dut.y.value == 0, "0+0=0"
    assert dut.co.value == 0, "no carry on 0+0"


@cocotb.test()
async def test_add_overflow(dut):
    """add: test overflow cases."""
    # 7+1+0 = 8 → y=0, co=1
    dut.a.value = 7
    dut.b.value = 1
    dut.ci.value = 0
    await Timer(1, unit="ns")
    assert dut.y.value == 0, f"7+1 = 8, y should be 0 (mod 8)"
    assert dut.co.value == 1, "7+1 should produce carry"


@cocotb.test()
async def test_add_ci(dut):
    """add: carry-in works."""
    # 5+2+1 = 8 → y=0, co=1
    dut.a.value = 5
    dut.b.value = 2
    dut.ci.value = 1
    await Timer(1, unit="ns")
    assert dut.y.value == 0, f"5+2+1=8, y should be 0"
    assert dut.co.value == 1, "5+2+1 should produce carry"


@cocotb.test()
async def test_add_no_overflow(dut):
    """add: no overflow case."""
    # 3+2+0 = 5 → y=5, co=0
    dut.a.value = 3
    dut.b.value = 2
    dut.ci.value = 0
    await Timer(1, unit="ns")
    assert dut.y.value == 5, f"3+2=5"
    assert dut.co.value == 0, "3+2 should not produce carry"
