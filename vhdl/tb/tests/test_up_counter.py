"""
Tests for UpCounter module.

UpCounter: counts 0→TOP-1→0 on each Tick input.
Default TOP=9, WIDTH=4.
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import Timer, RisingEdge

import logging
log = logging.getLogger(__name__)


@cocotb.test()
async def test_up_counter_basic(dut):
    """UpCounter: counts 0→TOP-1→0."""
    clock = Clock(dut.Tick, 10, unit="ns")
    cocotb.start_soon(clock.start())

    dut.Rst_n.value = 0
    for _ in range(5):
        await RisingEdge(dut.Tick)
    dut.Rst_n.value = 1
    for _ in range(3):
        await RisingEdge(dut.Tick)

    values = []
    for _ in range(20):
        await RisingEdge(dut.Tick)
        values.append(int(dut.Count.value))

    log.info(f"UpCounter sequence: {values}")
    for i in range(len(values) - 1):
        # TOP=9 means wrap at count==TOP → 0, so sequence is 0,1,...,9,0,...
        if values[i] == 9:
            assert values[i + 1] == 0, f"Should wrap 9→0, got →{values[i+1]}"
        else:
            assert values[i + 1] == values[i] + 1, f"Sequence error at {values[i]}→{values[i+1]}"


@cocotb.test()
async def test_up_counter_reset(dut):
    """UpCounter: reset clears count to 0."""
    clock = Clock(dut.Tick, 10, unit="ns")
    cocotb.start_soon(clock.start())

    dut.Rst_n.value = 0
    for _ in range(5):
        await RisingEdge(dut.Tick)
    dut.Rst_n.value = 1

    for _ in range(10):
        await RisingEdge(dut.Tick)

    dut.Rst_n.value = 0
    for _ in range(3):
        await RisingEdge(dut.Tick)

    assert int(dut.Count.value) == 0, f"Count should be 0 after reset, got {dut.Count.value}"


@cocotb.test()
async def test_up_counter_wraparound(dut):
    """UpCounter: verify multiple wraparound cycles."""
    clock = Clock(dut.Tick, 10, unit="ns")
    cocotb.start_soon(clock.start())

    dut.Rst_n.value = 0
    for _ in range(5):
        await RisingEdge(dut.Tick)
    dut.Rst_n.value = 1
    for _ in range(3):
        await RisingEdge(dut.Tick)

    wraps = 0
    prev = -1
    for _ in range(30):
        await RisingEdge(dut.Tick)
        cur = int(dut.Count.value)
        if prev == 9 and cur == 0:
            wraps += 1
        prev = cur

    log.info(f"UpCounter: {wraps} wraps in 30 cycles")
    assert wraps >= 2, f"Should see at least 2 wraps from 8→0 in 30 cycles, got {wraps}"
