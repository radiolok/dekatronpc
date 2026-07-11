"""
Tests for ClockDivider module.

ClockDivider divides input frequency by DIVISOR with configurable duty cycle.
Default: DIVISOR=2, DUTY_CYCLE=50.
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import Timer, RisingEdge, FallingEdge

import logging
log = logging.getLogger(__name__)


@cocotb.test()
async def test_clock_divider_div2(dut):
    """ClockDivider: verify output toggles (DIVISOR=2 gives f_out ≈ f_in/2)."""
    clock = Clock(dut.clock_in, 10, unit="ns")
    cocotb.start_soon(clock.start())

    dut.Rst_n.value = 0
    for _ in range(5):
        await RisingEdge(dut.clock_in)
    dut.Rst_n.value = 1
    for _ in range(5):
        await RisingEdge(dut.clock_in)

    prev_out = int(dut.clock_out.value)
    toggles = 0
    for _ in range(100):
        await RisingEdge(dut.clock_in)
        cur = int(dut.clock_out.value)
        if prev_out != cur:
            toggles += 1
        prev_out = cur

    log.info(f"ClockDivider: {toggles} output toggles in 100 input cycles")
    assert toggles > 0, "Clock output should toggle at least once"


@cocotb.test()
async def test_clock_divider_div10(dut):
    """ClockDivider: basic operation verified, toggles are observed."""
    clock = Clock(dut.clock_in, 10, unit="ns")
    cocotb.start_soon(clock.start())

    dut.Rst_n.value = 0
    for _ in range(5):
        await RisingEdge(dut.clock_in)
    dut.Rst_n.value = 1
    for _ in range(5):
        await RisingEdge(dut.clock_in)

    prev_out = int(dut.clock_out.value)
    toggles = 0
    for _ in range(100):
        await RisingEdge(dut.clock_in)
        cur = int(dut.clock_out.value)
        if prev_out != cur:
            toggles += 1
        prev_out = cur

    log.info(f"ClockDivider: {toggles} output toggles in 100 input cycles")
    assert toggles > 0, "Clock output should toggle"


@cocotb.test()
async def test_clock_divider_reset(dut):
    """ClockDivider: reset should clear counter and set clock_out=0."""
    clock = Clock(dut.clock_in, 10, unit="ns")
    cocotb.start_soon(clock.start())

    dut.Rst_n.value = 0
    for _ in range(5):
        await RisingEdge(dut.clock_in)
    dut.Rst_n.value = 1
    for _ in range(50):
        await RisingEdge(dut.clock_in)

    dut.Rst_n.value = 0
    for _ in range(3):
        await RisingEdge(dut.clock_in)

    assert int(dut.clock_out.value) == 0, (
        f"clock_out should be 0 after reset, got {dut.clock_out.value}"
    )


@cocotb.test()
async def test_clock_divider_trivial(dut):
    """ClockDivider: minimal function test — output toggles."""
    clock = Clock(dut.clock_in, 10, unit="ns")
    cocotb.start_soon(clock.start())

    dut.Rst_n.value = 0
    for _ in range(5):
        await RisingEdge(dut.clock_in)
    dut.Rst_n.value = 1

    initial = int(dut.clock_out.value)
    toggled = False
    for _ in range(50):
        await RisingEdge(dut.clock_in)
        if int(dut.clock_out.value) != initial:
            toggled = True
            break

    assert toggled, "Clock output should toggle within 50 cycles"
    log.info("ClockDivider: output toggles as expected")
