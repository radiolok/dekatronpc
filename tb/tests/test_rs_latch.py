"""
Tests for RsLatch and Rs3Latch_en modules.

RsLatch: basic SR latch, Q = 1 on S, Q = 0 on R
Rs3Latch_en: 3-input latch with enable, Qa/Qb outputs
"""

import cocotb
from cocotb.triggers import Timer

import logging
log = logging.getLogger(__name__)


@cocotb.test()
async def test_rs_latch_set(dut):
    """RsLatch: Q=1 after S=1, Q stays 1 after S=0."""
    dut.S.value = 0
    dut.R.value = 0
    await Timer(10, unit="ns")

    dut.S.value = 1
    await Timer(10, unit="ns")
    assert dut.Q.value == 1, "Q should be 1 after S=1"

    dut.S.value = 0
    await Timer(10, unit="ns")
    assert dut.Q.value == 1, "Q should stay 1 after S deasserted"


@cocotb.test()
async def test_rs_latch_reset(dut):
    """RsLatch: Q=0 after R=1."""
    dut.S.value = 0
    dut.R.value = 0
    await Timer(10, unit="ns")

    # Set first
    dut.S.value = 1
    await Timer(10, unit="ns")
    dut.S.value = 0

    dut.R.value = 1
    await Timer(10, unit="ns")
    assert dut.Q.value == 0, "Q should be 0 after R=1"


@cocotb.test()
async def test_rs_latch_sr_priority(dut):
    """RsLatch: when both S=1 and R=1, Q=0 (R has priority)."""
    dut.S.value = 0
    dut.R.value = 0
    await Timer(10, unit="ns")

    dut.S.value = 1
    dut.R.value = 1
    await Timer(10, unit="ns")
    assert dut.Q.value == 0, "Q should be 0 when S=1 and R=1 (R wins)"


@cocotb.test()
async def test_rs_latch_exhaustive(dut):
    """RsLatch: exhaustive S/R combination test."""
    # Test initial state
    dut.S.value = 0
    dut.R.value = 0
    await Timer(10, unit="ns")

    # Set
    dut.S.value = 1
    dut.R.value = 0
    await Timer(10, unit="ns")
    assert dut.Q.value == 1

    # Hold
    dut.S.value = 0
    dut.R.value = 0
    await Timer(10, unit="ns")
    assert dut.Q.value == 1

    # Reset
    dut.S.value = 0
    dut.R.value = 1
    await Timer(10, unit="ns")
    assert dut.Q.value == 0

    # Hold (should stay 0)
    dut.S.value = 0
    dut.R.value = 0
    await Timer(10, unit="ns")
    assert dut.Q.value == 0

    # Both: R wins
    dut.S.value = 1
    dut.R.value = 1
    await Timer(10, unit="ns")
    assert dut.Q.value == 0
