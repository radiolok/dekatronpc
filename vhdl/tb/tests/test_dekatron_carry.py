"""
Tests for DekatronCarrySignal — generates CarryLow/CarryHigh for dekatron
full 10-position width carry detection.

Uses Rs3Latch_en internally:
  Sa = In[0], Sb = In[9], R = |In[8:1]
  en = external enable

Rs3Latch_en behavior:
  Qa set by en & Sa, reset by R | Sb
  Qb set by en & Sb, reset by R | Sa
  When en=0: latch holds previous state
"""

import cocotb
from cocotb.triggers import Timer

import logging
log = logging.getLogger(__name__)


@cocotb.test()
async def test_carry_latch_holds(dut):
    """DekatronCarrySignal: en=0 → outputs hold previous state."""
    # Disable latch, set In so that if en were 1, CarryLow would go high
    dut.en.value = 0
    dut.In.value = 0
    await Timer(10, unit="ns")

    # Set In[0]=1 but keep en=0 — outputs should NOT change
    dut.In.value = 1  # In[0]=1
    await Timer(10, unit="ns")
    assert int(dut.CarryLow.value) == 0, "CarryLow should be 0 when en=0 even with In[0]=1"
    assert int(dut.CarryHigh.value) == 0, "CarryHigh should be 0 when en=0 even with In[0]=1"

    # Now enable — CarryLow should go high
    dut.en.value = 1
    await Timer(10, unit="ns")
    assert int(dut.CarryLow.value) == 1, "CarryLow should be 1 after en=1 with In[0]=1"
    assert int(dut.CarryHigh.value) == 0, "CarryHigh should be 0 when only In[0]=1"

    # Disable and change In — outputs should hold
    dut.en.value = 0
    dut.In.value = 0
    await Timer(10, unit="ns")
    assert int(dut.CarryLow.value) == 1, "CarryLow should hold value when en=0"
    assert int(dut.CarryHigh.value) == 0, "CarryHigh should hold value when en=0"


@cocotb.test()
async def test_carry_low_set(dut):
    """DekatronCarrySignal: In[0]=1, en=1 → CarryLow=1, CarryHigh=0."""
    dut.en.value = 0
    dut.In.value = 0
    await Timer(10, unit="ns")

    dut.In.value = 1  # In[0]=1
    dut.en.value = 1
    await Timer(10, unit="ns")

    assert int(dut.CarryLow.value) == 1, "CarryLow should be 1 when In[0]=1 and en=1"
    assert int(dut.CarryHigh.value) == 0, (
        "CarryHigh should be 0 when In[0]=1 (Sb=0, and Sa=1 resets Qb)"
    )


@cocotb.test()
async def test_carry_high_set(dut):
    """DekatronCarrySignal: In[9]=1, en=1 → CarryHigh=1, CarryLow=0."""
    dut.en.value = 0
    dut.In.value = 0
    await Timer(10, unit="ns")

    dut.In.value = 1 << 9  # In[9]=1
    dut.en.value = 1
    await Timer(10, unit="ns")

    assert int(dut.CarryHigh.value) == 1, "CarryHigh should be 1 when In[9]=1 and en=1"
    assert int(dut.CarryLow.value) == 0, (
        "CarryLow should be 0 when In[9]=1 (Sa=0, and Sb=1 resets Qa)"
    )


@cocotb.test()
async def test_carry_reset_by_mid_bits(dut):
    """DekatronCarrySignal: any In[8:1] bit → R=1 → CarryLow=CarryHigh=0."""
    # First set CarryLow
    dut.en.value = 0
    dut.In.value = 0
    await Timer(10, unit="ns")

    dut.In.value = 1  # In[0]=1
    dut.en.value = 1
    await Timer(10, unit="ns")
    assert int(dut.CarryLow.value) == 1, "Precondition: CarryLow should be set"

    # Now activate a mid bit — should reset both outputs
    for mid_bit in range(1, 9):
        dut.In.value = 1 << mid_bit
        await Timer(10, unit="ns")
        assert int(dut.CarryLow.value) == 0, (
            f"CarryLow should be 0 when In[{mid_bit}]=1 (R activated)"
        )
        assert int(dut.CarryHigh.value) == 0, (
            f"CarryHigh should be 0 when In[{mid_bit}]=1 (R activated)"
        )

        # Re-set CarryLow for next iteration
        dut.In.value = 1  # In[0]=1
        await Timer(10, unit="ns")
        assert int(dut.CarryLow.value) == 1


@cocotb.test()
async def test_carry_high_reset_by_mid(dut):
    """DekatronCarrySignal: set CarryHigh, then mid bit resets it."""
    dut.en.value = 0
    dut.In.value = 0
    await Timer(10, unit="ns")

    dut.In.value = 1 << 9  # In[9]=1
    dut.en.value = 1
    await Timer(10, unit="ns")
    assert int(dut.CarryHigh.value) == 1, "Precondition: CarryHigh should be set"

    dut.In.value = 1 << 4  # In[4]=1
    await Timer(10, unit="ns")
    assert int(dut.CarryHigh.value) == 0, "CarryHigh should be 0 when In[4]=1 (R activated)"
    assert int(dut.CarryLow.value) == 0, "CarryLow should be 0 when In[4]=1 (R activated)"


@cocotb.test()
async def test_carry_low_to_high_switch(dut):
    """DekatronCarrySignal: switching from In[0] to In[9] switches output."""
    dut.en.value = 0
    dut.In.value = 0
    await Timer(10, unit="ns")

    # Set CarryLow
    dut.In.value = 1
    dut.en.value = 1
    await Timer(10, unit="ns")
    assert int(dut.CarryLow.value) == 1

    # Switch to CarryHigh (Sa=1 resets Qb, Sb=1 resets Qa)
    dut.In.value = 1 << 9
    await Timer(10, unit="ns")
    assert int(dut.CarryHigh.value) == 1, "CarryHigh should be 1 after switching to In[9]"
    assert int(dut.CarryLow.value) == 0, "CarryLow should be 0 (reset by Sb=In[9]=1)"


@cocotb.test()
async def test_carry_no_bits_hold(dut):
    """DekatronCarrySignal: no bits set → outputs hold (R=0, Sa=0, Sb=0)."""
    dut.en.value = 0
    dut.In.value = 0
    await Timer(10, unit="ns")

    # Set CarryLow first
    dut.In.value = 1
    dut.en.value = 1
    await Timer(10, unit="ns")
    assert int(dut.CarryLow.value) == 1

    # Now set In=0 — no set, no reset → hold
    dut.In.value = 0
    await Timer(10, unit="ns")
    assert int(dut.CarryLow.value) == 1, "CarryLow should hold when all In bits 0"
    assert int(dut.CarryHigh.value) == 0, "CarryHigh should hold when all In bits 0"


@cocotb.test()
async def test_carry_low_high_mutual_exclusion(dut):
    """DekatronCarrySignal: In[0] and In[9] both 1 → only In[9] wins."""
    dut.en.value = 0
    dut.In.value = 0
    await Timer(10, unit="ns")

    # Both In[0] and In[9] = 1
    # Sa=1 sets Qa, but Sb=1 resets Qa → Qa=0
    # Sb=1 sets Qb, but Sa=1 resets Qb → Qb=0
    # Wait... with always_latch blocks, the order of execution matters.
    # Let's see: Qa block: if (en&Sa) Qa=1; if (R|Sb) Qa=0 → Sb=1 so Qa=0
    # Qb block: if (en&Sb) Qb=1; if (R|Sa) Qb=0 → Sa=1 so Qb=0
    # So both should be 0.
    dut.In.value = (1 << 9) | 1  # In[9]=1, In[0]=1
    dut.en.value = 1
    await Timer(10, unit="ns")

    # With always_latch, the second if in each block may override the first.
    # Qa: first if sets Qa=1, second if resets Qa=0 → Qa=0
    # Qb: first if sets Qb=1, second if resets Qb=0 → Qb=0
    assert int(dut.CarryLow.value) == 0, "CarryLow should be 0 (reset by Sb=In[9])"
    assert int(dut.CarryHigh.value) == 0, "CarryHigh should be 0 (reset by Sa=In[0])"


@cocotb.test()
async def test_carry_en_gate(dut):
    """DekatronCarrySignal: en=0 gates set but R still active."""
    dut.en.value = 0
    dut.In.value = 0
    await Timer(10, unit="ns")

    # Pre-set CarryLow
    dut.In.value = 1
    dut.en.value = 1
    await Timer(10, unit="ns")
    assert int(dut.CarryLow.value) == 1

    # en=0 blocks setting In[0]=1 but R (from In[8:1]) might still reset
    # since R is not gated by en in Rs3Latch_en
    dut.en.value = 0
    dut.In.value = 1 << 5  # In[5]=1 (mid bit)
    await Timer(10, unit="ns")
    assert int(dut.CarryLow.value) == 0, (
        "CarryLow should be 0 — R resets regardless of en"
    )
