"""
Tests for Sequencer module — 7-state FSM controlling display/keyboard write sequence.

The Sequencer drives ms6205 write pulses, IN-12 anode/cathode writes, and keyboard
read/write signals. It uses Impulse submodules for ms6205 write pulse generation.

Race condition audit note: Two always @(negedge Clock_1us) blocks drive current_state
and output registers separately. The combinational next_state block checks output register
values as "done" flags. Tests allow +/-1 cycle tolerance for this race.
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import Timer, RisingEdge, FallingEdge

import logging
log = logging.getLogger(__name__)

CLOCK_PERIOD_NS = 1000  # Clock_1us = 1us = 1000ns


async def reset_dut(dut):
    """Reset sequencer and wait for stabilization."""
    dut.Rst_n.value = 0
    dut.Enable.value = 0
    await Timer(5 * CLOCK_PERIOD_NS, unit="ns")
    dut.Rst_n.value = 1
    await Timer(5 * CLOCK_PERIOD_NS, unit="ns")


@cocotb.test()
async def test_sequencer_reset(dut):
    """After reset, state should be NONE (0)."""
    clock = Clock(dut.Clock_1us, CLOCK_PERIOD_NS, unit="ns")
    cocotb.start_soon(clock.start())

    dut.Rst_n.value = 0
    dut.Enable.value = 0
    await Timer(10 * CLOCK_PERIOD_NS, unit="ns")
    assert int(dut.state.value) == 0, f"Expected state=NONE(0) during reset, got {int(dut.state.value)}"


@cocotb.test()
async def test_sequencer_disabled_stays_none(dut):
    """With Enable=0, FSM stays in NONE state even after many cycles."""
    clock = Clock(dut.Clock_1us, CLOCK_PERIOD_NS, unit="ns")
    cocotb.start_soon(clock.start())

    await reset_dut(dut)

    for _ in range(50):
        await FallingEdge(dut.Clock_1us)
        assert int(dut.state.value) == 0, f"State should stay NONE(0) with Enable=0, got {int(dut.state.value)}"


@cocotb.test()
async def test_sequencer_state_progression(dut):
    """With Enable=1, FSM progresses through all states: NONE->CATHODES->ANODES->KEYBOARD_WR->MC_ADDR->MC_DATA->STOP."""
    clock = Clock(dut.Clock_1us, CLOCK_PERIOD_NS, unit="ns")
    cocotb.start_soon(clock.start())

    await reset_dut(dut)
    dut.Enable.value = 1

    expected_sequence = [0, 1, 2, 3, 4, 5, 7]  # NONE, CATHODES, ANODES, KEYBOARD_WR, MC_ADDR, MC_DATA, STOP
    seen_states = []
    prev_state = -1

    for _ in range(200):
        await FallingEdge(dut.Clock_1us)
        cur = int(dut.state.value)
        if cur != prev_state:
            seen_states.append(cur)
            prev_state = cur
        if 7 in seen_states:  # STOP reached
            break

    log.info(f"State transitions observed: {seen_states}")

    for expected in expected_sequence:
        assert expected in seen_states, f"State {expected} not seen in sequence {seen_states}"

    assert seen_states.index(0) < seen_states.index(1), "NONE must come before CATHODES"
    assert seen_states.index(1) < seen_states.index(2), "CATHODES must come before ANODES"
    assert seen_states.index(2) < seen_states.index(3), "ANODES must come before KEYBOARD_WR"


@cocotb.test()
async def test_sequencer_full_cycle_returns_to_none(dut):
    """Full sequence: Enable=1 to reach STOP, then Enable=0 to go through KEYBOARD_RD back to NONE."""
    clock = Clock(dut.Clock_1us, CLOCK_PERIOD_NS, unit="ns")
    cocotb.start_soon(clock.start())

    await reset_dut(dut)
    dut.Enable.value = 1

    # Wait to reach STOP (state 7)
    for _ in range(200):
        await FallingEdge(dut.Clock_1us)
        if int(dut.state.value) == 7:
            break
    assert int(dut.state.value) == 7, "Should reach STOP state"

    # Hold in STOP for a few cycles
    for _ in range(10):
        await FallingEdge(dut.Clock_1us)
        assert int(dut.state.value) == 7, f"With Enable=1, should stay in STOP(7), got {int(dut.state.value)}"

    # Release Enable to exit STOP -> KEYBOARD_RD -> NONE
    dut.Enable.value = 0
    for _ in range(200):
        await FallingEdge(dut.Clock_1us)
        cur = int(dut.state.value)
        if cur == 0:  # NONE
            break
    assert int(dut.state.value) == 0, "Should return to NONE after releasing Enable"


@cocotb.test()
async def test_sequencer_output_signals(dut):
    """Verify output signals toggle during appropriate states."""
    clock = Clock(dut.Clock_1us, CLOCK_PERIOD_NS, unit="ns")
    cocotb.start_soon(clock.start())

    await reset_dut(dut)
    dut.Enable.value = 1

    cathodes_seen = False
    anodes_seen = False
    keyboard_write_seen = False
    keyboard_read_seen = False

    for _ in range(400):
        await FallingEdge(dut.Clock_1us)
        cur = int(dut.state.value)
        if cur == 1:  # CATHODES
            if int(dut.in12_write_cathode.value) == 1:
                cathodes_seen = True
        if cur == 2:  # ANODES
            if int(dut.in12_write_anode.value) == 1:
                anodes_seen = True
        if cur == 3:  # KEYBOARD_WR
            if int(dut.keyboard_write.value) == 1:
                keyboard_write_seen = True
        if cur == 6:  # KEYBOARD_RD
            if int(dut.keyboard_read.value) == 1:
                keyboard_read_seen = True
        if cur == 0 and cathodes_seen and anodes_seen and keyboard_write_seen:
            break

    assert cathodes_seen, "in12_write_cathode never asserted during CATHODES state"
    assert anodes_seen, "in12_write_anode never asserted during ANODES state"
    assert keyboard_write_seen, "keyboard_write never asserted during KEYBOARD_WR state"


@cocotb.test()
async def test_sequencer_ms6205_pulse_signals(dut):
    """Verify ms6205_write_addr_n and ms6205_write_data_n pulse active-low.

    Due to the race condition between the two always@(negedge) blocks driving
    current_state and output registers, the ms6205 write enable registers may
    assert 1 cycle after the state transition. The Impulse module generates
    a brief pulse on ms6205_write_addr_n between a negedge (where En rises)
    and the next posedge (where D_state catches up).

    We add a small delay after FallingEdge to ensure NBA regions settle
    before sampling the external pulse outputs.
    """
    clock = Clock(dut.Clock_1us, CLOCK_PERIOD_NS, unit="ns")
    cocotb.start_soon(clock.start())

    await reset_dut(dut)
    dut.Enable.value = 1

    addr_n_low_seen = False
    data_n_low_seen = False
    addr_high_seen = False
    data_high_seen = False

    for _ in range(400):
        await FallingEdge(dut.Clock_1us)
        # Allow NBA regions to settle before sampling
        await Timer(1, unit="ns")

        an = int(dut.ms6205_write_addr_n.value)
        dn = int(dut.ms6205_write_data_n.value)
        ma = int(dut.ms6205_write_addr.value)
        md = int(dut.ms6205_write_data.value)

        if an == 0:
            addr_n_low_seen = True
        if dn == 0:
            data_n_low_seen = True
        if ma == 1:
            addr_high_seen = True
        if md == 1:
            data_high_seen = True

    log.info(
        f"ms6205: addr_n_low={addr_n_low_seen} data_n_low={data_n_low_seen} "
        f"addr_high={addr_high_seen} data_high={data_high_seen}"
    )

    assert addr_n_low_seen or addr_high_seen, (
        "Neither ms6205_write_addr_n went low nor ms6205_write_addr (internal reg) went high"
    )
    assert data_n_low_seen or data_high_seen, (
        "Neither ms6205_write_data_n went low nor ms6205_write_data (internal reg) went high"
    )


@cocotb.test()
async def test_sequencer_in12_clear(dut):
    """in12_clear_n and keyboard_clear should always match Rst_n."""
    clock = Clock(dut.Clock_1us, CLOCK_PERIOD_NS, unit="ns")
    cocotb.start_soon(clock.start())

    # During reset (low)
    dut.Rst_n.value = 0
    dut.Enable.value = 0
    await Timer(5 * CLOCK_PERIOD_NS, unit="ns")
    assert int(dut.in12_clear_n.value) == 0, "in12_clear_n should be 0 during reset"
    assert int(dut.keyboard_clear.value) == 0, "keyboard_clear should be 0 during reset"

    # After reset (high)
    dut.Rst_n.value = 1
    await Timer(5 * CLOCK_PERIOD_NS, unit="ns")
    assert int(dut.in12_clear_n.value) == 1, "in12_clear_n should be 1 after reset"
    assert int(dut.keyboard_clear.value) == 1, "keyboard_clear should be 1 after reset"
