"""
Trivial test to validate cocotb toolchain: Compare module.

This is the first test to run when setting up the infrastructure.
If this passes, cocotb + simulator integration is working correctly.
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import Timer, RisingEdge

import logging
log = logging.getLogger(__name__)


@cocotb.test()
async def test_compare_equal(dut):
    """Test Compare module: a == b should assert eq."""
    dut.a.value = 0x5
    dut.b.value = 0x5
    await Timer(10, unit="ns")
    assert dut.eq.value == 1, f"Expected eq=1 for a={dut.a.value}, b={dut.b.value}"


@cocotb.test()
async def test_compare_unequal(dut):
    """Test Compare module: a != b should deassert eq."""
    dut.a.value = 0x3
    dut.b.value = 0x7
    await Timer(10, unit="ns")
    assert dut.eq.value == 0, f"Expected eq=0 for a={dut.a.value}, b={dut.b.value}"


@cocotb.test()
async def test_compare_random(dut):
    """Test Compare module with random values (width=4, 0-15)."""
    for a_val in range(16):
        for b_val in range(16):
            dut.a.value = a_val
            dut.b.value = b_val
            await Timer(1, unit="ns")
            expected = 1 if a_val == b_val else 0
            assert dut.eq.value == expected, (
                f"eq mismatch: a={a_val}, b={b_val}, got={dut.eq.value}, expected={expected}"
            )


@cocotb.test()
async def test_compare_trivial(dut):
    """Minimal test to verify basic cocotb integration works."""
    dut.a.value = 0
    dut.b.value = 0
    await Timer(1, unit="ns")
    result = dut.eq.value
    log.info(f"Compare(0, 0) = {result}")
