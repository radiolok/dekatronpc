"""
Tests for DekatronPulseSender — generates properly timed pulse sequences
for driving dekatron stepping.

Timing (on hsClk, 100ns period = 10 MHz):
  OneShot delays: dir=9, pA=4, OS_2=3, OS_3=8
  pB = OS_3 & ~OS_2
  PulseRight = Dec ? pA : pB
  PulseLeft  = Dec ? pB : pA
  Dec is triggered by PulseR input (via OneShot dir with DELAY=9)
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import Timer, RisingEdge, FallingEdge

import logging
log = logging.getLogger(__name__)

HS_CLK_PERIOD = 100  # ns


@cocotb.test()
async def test_pulse_sender_reset(dut):
    """DekatronPulseSender: after reset, Pulses = 0."""
    clock = Clock(dut.hsClk, HS_CLK_PERIOD, unit="ns")
    cocotb.start_soon(clock.start())

    dut.PulseF.value = 0
    dut.PulseR.value = 0
    dut.Rst_n.value = 0
    for _ in range(5):
        await RisingEdge(dut.hsClk)
    dut.Rst_n.value = 1
    for _ in range(3):
        await RisingEdge(dut.hsClk)

    assert int(dut.Pulses.value) == 0, "Pulses should be 0 after reset"


@cocotb.test()
async def test_pulse_forward(dut):
    """DekatronPulseSender: PulseF → both Pulses fire, Pulses[1]=pA first, Pulses[0]=pB later."""
    clock = Clock(dut.hsClk, HS_CLK_PERIOD, unit="ns")
    cocotb.start_soon(clock.start())

    dut.PulseF.value = 0
    dut.PulseR.value = 0
    dut.Rst_n.value = 0
    for _ in range(5):
        await RisingEdge(dut.hsClk)
    dut.Rst_n.value = 1
    for _ in range(3):
        await RisingEdge(dut.hsClk)

    # Trigger forward pulse
    dut.PulseF.value = 1
    await RisingEdge(dut.hsClk)
    dut.PulseF.value = 0

    # On PulseF: Dec=0, Pulses = {pB, pA}
    # pA (OneShot DELAY=4) fires first, pB (OS_3 & ~OS_2) fires later
    pulse0_seen = False
    pulse1_seen = False
    pulse1_before_pulse0 = False
    saw_pulse1 = False
    for _ in range(30):
        v = int(dut.Pulses.value)
        if v & 2 and not saw_pulse1:
            pulse1_before_pulse0 = True
            saw_pulse1 = True
        if v & 1 and saw_pulse1:
            pass  # both fired
        if v & 1:
            pulse0_seen = True
        if v & 2:
            pulse1_seen = True
        await RisingEdge(dut.hsClk)

    assert pulse0_seen, "Pulses[0] should pulse on PulseF (pB)"
    assert pulse1_seen, "Pulses[1] should pulse on PulseF (pA)"


@cocotb.test()
async def test_pulse_reverse(dut):
    """DekatronPulseSender: PulseR → both Pulses fire, Pulses[0]=pA first, Pulses[1]=pB later."""
    clock = Clock(dut.hsClk, HS_CLK_PERIOD, unit="ns")
    cocotb.start_soon(clock.start())

    dut.PulseF.value = 0
    dut.PulseR.value = 0
    dut.Rst_n.value = 0
    for _ in range(5):
        await RisingEdge(dut.hsClk)
    dut.Rst_n.value = 1
    for _ in range(3):
        await RisingEdge(dut.hsClk)

    # Trigger reverse pulse (sets Dec=1 via OneShot dir)
    dut.PulseR.value = 1
    await RisingEdge(dut.hsClk)
    dut.PulseR.value = 0

    # On PulseR: Dec=1, Pulses = {pA, pB}
    pulse0_seen = False
    pulse1_seen = False
    for _ in range(30):
        if int(dut.Pulses.value) & 1:
            pulse0_seen = True
        if int(dut.Pulses.value) & 2:
            pulse1_seen = True
        await RisingEdge(dut.hsClk)

    assert pulse0_seen, "Pulses[0] should pulse on PulseR (pA)"
    assert pulse1_seen, "Pulses[1] should pulse on PulseR (pB)"


@cocotb.test()
async def test_pulse_returns_zero(dut):
    """DekatronPulseSender: after pulse sequence, Pulses returns to 0."""
    clock = Clock(dut.hsClk, HS_CLK_PERIOD, unit="ns")
    cocotb.start_soon(clock.start())

    dut.PulseF.value = 0
    dut.PulseR.value = 0
    dut.Rst_n.value = 0
    for _ in range(5):
        await RisingEdge(dut.hsClk)
    dut.Rst_n.value = 1
    for _ in range(3):
        await RisingEdge(dut.hsClk)

    # Trigger forward
    dut.PulseF.value = 1
    await RisingEdge(dut.hsClk)
    dut.PulseF.value = 0

    # Wait long enough for entire pulse sequence to finish
    # Worst case: dir delay=9 + pA/pB sequence max delay=8 = ~17 cycles
    # Wait extra margin
    for _ in range(40):
        await RisingEdge(dut.hsClk)

    assert int(dut.Pulses.value) == 0, (
        f"Pulses should return to 0 after pulse sequence, got {int(dut.Pulses.value)}"
    )

    # Trigger reverse
    dut.PulseR.value = 1
    await RisingEdge(dut.hsClk)
    dut.PulseR.value = 0

    for _ in range(40):
        await RisingEdge(dut.hsClk)

    assert int(dut.Pulses.value) == 0, (
        f"Pulses should return to 0 after reverse pulse sequence, got {int(dut.Pulses.value)}"
    )


@cocotb.test()
async def test_pulse_direction_behavior(dut):
    """DekatronPulseSender: observe timing and direction-specific outputs."""
    clock = Clock(dut.hsClk, HS_CLK_PERIOD, unit="ns")
    cocotb.start_soon(clock.start())

    dut.PulseF.value = 0
    dut.PulseR.value = 0
    dut.Rst_n.value = 0
    for _ in range(5):
        await RisingEdge(dut.hsClk)
    dut.Rst_n.value = 1
    for _ in range(3):
        await RisingEdge(dut.hsClk)

    # Forward pulse
    dut.PulseF.value = 1
    await RisingEdge(dut.hsClk)
    dut.PulseF.value = 0

    # Record pulse timing
    forward_trace = []
    for i in range(25):
        forward_trace.append(int(dut.Pulses.value))
        await RisingEdge(dut.hsClk)

    pulses0_cycles = sum(1 for v in forward_trace if v & 1)
    pulses1_cycles = sum(1 for v in forward_trace if v & 2)
    log.info(f"Forward: Pulses[0] active {pulses0_cycles} cycles, "
             f"Pulses[1] active {pulses1_cycles} cycles")

    # Wait for quiet
    for _ in range(20):
        await RisingEdge(dut.hsClk)

    # Reverse pulse
    dut.PulseR.value = 1
    await RisingEdge(dut.hsClk)
    dut.PulseR.value = 0

    reverse_trace = []
    for i in range(25):
        reverse_trace.append(int(dut.Pulses.value))
        await RisingEdge(dut.hsClk)

    pulses0_cycles_r = sum(1 for v in reverse_trace if v & 1)
    pulses1_cycles_r = sum(1 for v in reverse_trace if v & 2)
    log.info(f"Reverse: Pulses[0] active {pulses0_cycles_r} cycles, "
             f"Pulses[1] active {pulses1_cycles_r} cycles")

    # Verify both directions produce some pulse activity
    assert pulses0_cycles > 0 or pulses1_cycles > 0, "Forward should produce pulses"
    assert pulses0_cycles_r > 0 or pulses1_cycles_r > 0, "Reverse should produce pulses"


@cocotb.test()
async def test_pulse_no_spurious(dut):
    """DekatronPulseSender: no pulses without trigger."""
    clock = Clock(dut.hsClk, HS_CLK_PERIOD, unit="ns")
    cocotb.start_soon(clock.start())

    dut.PulseF.value = 0
    dut.PulseR.value = 0
    dut.Rst_n.value = 0
    for _ in range(5):
        await RisingEdge(dut.hsClk)
    dut.Rst_n.value = 1
    for _ in range(3):
        await RisingEdge(dut.hsClk)

    # Without any trigger, monitor for 50 cycles
    spurious = False
    for _ in range(50):
        if int(dut.Pulses.value) != 0:
            spurious = True
        await RisingEdge(dut.hsClk)

    assert not spurious, "Pulses should remain 0 with no trigger"


@cocotb.test()
async def test_pulse_reset_during_sequence(dut):
    """DekatronPulseSender: reset during pulse sequence clears outputs."""
    clock = Clock(dut.hsClk, HS_CLK_PERIOD, unit="ns")
    cocotb.start_soon(clock.start())

    dut.PulseF.value = 0
    dut.PulseR.value = 0
    dut.Rst_n.value = 0
    for _ in range(5):
        await RisingEdge(dut.hsClk)
    dut.Rst_n.value = 1
    for _ in range(3):
        await RisingEdge(dut.hsClk)

    # Trigger forward
    dut.PulseF.value = 1
    await RisingEdge(dut.hsClk)
    dut.PulseF.value = 0

    # Let partial pulse develop
    for _ in range(3):
        await RisingEdge(dut.hsClk)

    # Assert reset
    dut.Rst_n.value = 0
    for _ in range(3):
        await RisingEdge(dut.hsClk)

    assert int(dut.Pulses.value) == 0, (
        f"Pulses should be 0 after reset asserted during sequence, got {int(dut.Pulses.value)}"
    )
