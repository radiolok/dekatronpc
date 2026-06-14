"""
Tests for DekatronCarrySignal module (rtl/ version without en port).

NOTE: Test adjusted for rtl/ RTL version — RsLatch holds previous state when S=R=0,
so exhaustive test resets latches between positions via mid-bit instead of
sequentially chaining positions where latch state carries over.

DekatronCarrySignal: generates CarryLow/CarryHigh from 10-position dekatron output.
Uses RsLatch (not Rs3Latch_en) — purely combinational latches.
Interface: In[9:0] → CarryLow, CarryHigh
"""

import cocotb
from cocotb.triggers import Timer

import logging
log = logging.getLogger(__name__)


@cocotb.test()
async def test_carry_low_set(dut):
    """In[0]=1 → CarryLow=1, CarryHigh=0."""
    dut.In.value = (1 << 0)
    await Timer(1, unit="ns")
    assert int(dut.CarryLow.value) == 1
    assert int(dut.CarryHigh.value) == 0


@cocotb.test()
async def test_carry_high_set(dut):
    """In[9]=1 → CarryHigh=1, CarryLow=0."""
    dut.In.value = (1 << 9)
    await Timer(1, unit="ns")
    assert int(dut.CarryHigh.value) == 1
    assert int(dut.CarryLow.value) == 0


@cocotb.test()
async def test_carry_reset_by_mid(dut):
    """Any mid bit (In[8:1]) resets both CarryLow and CarryHigh."""
    # Set low first
    dut.In.value = (1 << 0)
    await Timer(1, unit="ns")
    # Then set a mid bit
    dut.In.value = (1 << 5)
    await Timer(1, unit="ns")
    assert int(dut.CarryLow.value) == 0
    assert int(dut.CarryHigh.value) == 0


@cocotb.test()
async def test_carry_low_to_high_switch(dut):
    """Switching from position 0 to position 9."""
    dut.In.value = (1 << 0)
    await Timer(1, unit="ns")
    assert int(dut.CarryLow.value) == 1

    dut.In.value = (1 << 9)
    await Timer(1, unit="ns")
    assert int(dut.CarryLow.value) == 0
    assert int(dut.CarryHigh.value) == 1


@cocotb.test()
async def test_carry_no_bits(dut):
    """No bits set: latches hold previous state (S=0,R=0)."""
    # Set high first, then go to zero
    dut.In.value = (1 << 9)
    await Timer(1, unit="ns")
    assert int(dut.CarryHigh.value) == 1

    dut.In.value = 0
    await Timer(1, unit="ns")
    # RsLatch: S=0,R=0 → holds previous value
    assert int(dut.CarryHigh.value) == 1, "Latch should hold when no bits set"


@cocotb.test()
async def test_carry_exhaustive(dut):
    """Test all single-position inputs independently with clean latch state."""
    for pos in range(10):
        # Reset latches to known state via mid-bit (any In[8:1] resets both)
        dut.In.value = (1 << 5)
        await Timer(1, unit="ns")
        # Now set the position under test
        dut.In.value = (1 << pos)
        await Timer(1, unit="ns")
        if pos == 0:
            assert int(dut.CarryLow.value) == 1
            assert int(dut.CarryHigh.value) == 0
        elif pos == 9:
            assert int(dut.CarryLow.value) == 0
            assert int(dut.CarryHigh.value) == 1
        else:
            assert int(dut.CarryLow.value) == 0
            assert int(dut.CarryHigh.value) == 0
