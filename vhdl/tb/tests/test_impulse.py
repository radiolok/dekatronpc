"""
Tests for Impulse module — single-cycle edge detector.

Uses Impulse_test_wrapper to avoid cocotb name collision
between the module name "Impulse" and the output signal name "Impulse".
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import Timer, RisingEdge

import random
import logging
log = logging.getLogger(__name__)


@cocotb.test()
async def test_impulse_basic(dut):
    """Impulse: output should be exactly 1 cycle wide on En 0→1 edge."""
    clock = Clock(dut.Clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    dut.Rst_n.value = 0
    dut.En.value = 0
    for _ in range(5):
        await RisingEdge(dut.Clk)
    dut.Rst_n.value = 1
    for _ in range(3):
        await RisingEdge(dut.Clk)

    dut.En.value = 1
    await RisingEdge(dut.Clk)
    assert int(dut.pulse_out.value) == 1, "Impulse should be 1 on first cycle after En rises"

    await RisingEdge(dut.Clk)
    assert int(dut.pulse_out.value) == 0, "Impulse should be 0 on second cycle (En unchanged)"


@cocotb.test()
async def test_impulse_retrigger(dut):
    """Impulse: should generate pulse again after En drops and rises."""
    clock = Clock(dut.Clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    dut.Rst_n.value = 0
    dut.En.value = 0
    for _ in range(5):
        await RisingEdge(dut.Clk)
    dut.Rst_n.value = 1
    for _ in range(3):
        await RisingEdge(dut.Clk)

    dut.En.value = 1
    await RisingEdge(dut.Clk)
    assert int(dut.pulse_out.value) == 1

    for _ in range(3):
        await RisingEdge(dut.Clk)
    dut.En.value = 0
    for _ in range(2):
        await RisingEdge(dut.Clk)

    dut.En.value = 1
    await RisingEdge(dut.Clk)
    assert int(dut.pulse_out.value) == 1, "Second Impulse should be 1 after retrigger"


@cocotb.test()
async def test_impulse_random(dut):
    """Impulse: random En toggling, verify single-cycle pulse each time."""
    clock = Clock(dut.Clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    dut.Rst_n.value = 0
    dut.En.value = 0
    for _ in range(5):
        await RisingEdge(dut.Clk)
    dut.Rst_n.value = 1
    for _ in range(3):
        await RisingEdge(dut.Clk)

    random.seed(42)
    prev_en = 0
    pulse_count = 0
    prev_cycle_en = 0

    for i in range(200):
        if random.random() < 0.4:
            prev_en = 1 - prev_en
        dut.En.value = prev_en
        await RisingEdge(dut.Clk)

        rising_edge = prev_en == 1 and prev_cycle_en == 0
        if rising_edge:
            assert int(dut.pulse_out.value) == 1, f"Missed impulse at cycle {i}"
            pulse_count += 1
        elif prev_cycle_en == 1 and prev_en == 1:
            assert int(dut.pulse_out.value) == 0, f"Spurious impulse at cycle {i}"

        prev_cycle_en = prev_en

    log.info(f"Impulse random: {pulse_count} pulses over 200 cycles")


@cocotb.test()
async def test_impulse_reset(dut):
    """Impulse: reset clears internal state, pulse on first En after reset."""
    clock = Clock(dut.Clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    dut.Rst_n.value = 0
    dut.En.value = 0
    for _ in range(5):
        await RisingEdge(dut.Clk)
    dut.Rst_n.value = 1
    for _ in range(3):
        await RisingEdge(dut.Clk)

    dut.En.value = 1
    await RisingEdge(dut.Clk)
    assert int(dut.pulse_out.value) == 1, "Impulse after reset with En=1 should pulse"

    # Stay high, pulse should end
    await RisingEdge(dut.Clk)
    assert int(dut.pulse_out.value) == 0, "Pulse should be single-cycle"
