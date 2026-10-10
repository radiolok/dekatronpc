"""
Tests for OneShot module — pulse generator with configurable delay.

Uses OneShot_test_wrapper to avoid cocotb name collision with the output signal.
With IMP_ON_EN=1 a one-cycle En yields an Impulse exactly DELAY cycles long
(the En cycle plus count=1..DELAY-1). The wrapper default is DELAY=1.
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import Timer, RisingEdge, ReadOnly

import logging
log = logging.getLogger(__name__)


@cocotb.test()
async def test_oneshot_basic(dut):
    """OneShot: En triggers Impulse that stays high for DELAY cycles."""
    clock = Clock(dut.Clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    dut.Rst_n.value = 0
    dut.En.value = 0
    for _ in range(5):
        await RisingEdge(dut.Clk)
    dut.Rst_n.value = 1
    for _ in range(3):
        await RisingEdge(dut.Clk)

    DELAY = 1  # OneShot_test_wrapper default

    # One-cycle En; En must be released, otherwise Impulse = |count | En
    # simply follows En.
    dut.En.value = 1
    await RisingEdge(dut.Clk)
    await ReadOnly()
    pulse_width = int(dut.pulse_out.value)
    await RisingEdge(dut.Clk)
    dut.En.value = 0

    for _ in range(20):
        await ReadOnly()
        pulse_width += int(dut.pulse_out.value)
        await RisingEdge(dut.Clk)

    log.info(f"OneShot (DELAY={DELAY}) pulse width: {pulse_width} cycles")
    assert pulse_width == DELAY, f"expected {DELAY}-cycle pulse, got {pulse_width}"


@cocotb.test()
async def test_oneshot_retrigger(dut):
    """OneShot: second En after pulse ends should retrigger."""
    clock = Clock(dut.Clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    dut.Rst_n.value = 0
    dut.En.value = 0
    for _ in range(5):
        await RisingEdge(dut.Clk)
    dut.Rst_n.value = 1
    for _ in range(3):
        await RisingEdge(dut.Clk)

    # First trigger
    dut.En.value = 1
    await RisingEdge(dut.Clk)

    # Wait for pulse to end
    for _ in range(20):
        await RisingEdge(dut.Clk)
        if int(dut.pulse_out.value) == 0:
            break

    dut.En.value = 0
    for _ in range(3):
        await RisingEdge(dut.Clk)

    # Second trigger
    dut.En.value = 1
    pulse_seen = False
    for _ in range(10):
        if int(dut.pulse_out.value) == 1:
            pulse_seen = True
        await RisingEdge(dut.Clk)

    assert pulse_seen, "Second trigger should produce a pulse"


@cocotb.test()
async def test_oneshot_reset(dut):
    """OneShot: reset clears internal count, En=0 gives Impulse=0; En=1 dominates."""
    clock = Clock(dut.Clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    dut.Rst_n.value = 0
    dut.En.value = 0
    for _ in range(5):
        await RisingEdge(dut.Clk)
    dut.Rst_n.value = 1
    for _ in range(3):
        await RisingEdge(dut.Clk)

    # Trigger pulse, then immediately set En=0 and reset
    dut.En.value = 1
    await RisingEdge(dut.Clk)
    dut.En.value = 0

    dut.Rst_n.value = 0
    await RisingEdge(dut.Clk)
    await RisingEdge(dut.Clk)
    # Note: Impulse = (|count) | En. After reset, count=0. If En=0, Impulse=0.
    assert int(dut.pulse_out.value) == 0, "Pulse should be 0 when En=0 and count cleared by reset"
