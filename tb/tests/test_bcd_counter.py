"""
Tests for BCDCounterX1 and BCDCounter modules.

BCDCounterX1: single BCD digit counter (0-9 with carry at 8)
BCDCounter: multi-digit BCD counter with carry chain
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import Timer, RisingEdge, FallingEdge

import logging
log = logging.getLogger(__name__)


@cocotb.test()
async def test_bcd_counter_x1_basic(dut):
    """BCDCounterX1: counts 0→9→0 with co at count=8."""
    clock = Clock(dut.Clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    dut.Rst_n.value = 0
    dut.ci.value = 0
    for _ in range(5):
        await RisingEdge(dut.Clk)
    dut.Rst_n.value = 1
    for _ in range(3):
        await RisingEdge(dut.Clk)

    dut.ci.value = 1

    seq = []
    for i in range(20):
        seq.append((int(dut.count.value), int(dut.co.value)))
        await RisingEdge(dut.Clk)

    log.info(f"BCDCounterX1 sequence: {seq[:15]}")
    counts = [c for c, _ in seq]
    unique = set(counts)
    assert unique.issubset({0, 1, 2, 3, 4, 5, 6, 7, 8, 9}), f"Unexpected values: {unique}"
    assert 0 in counts and 9 in counts, "Counter should cover full 0-9 range"


@cocotb.test()
async def test_bcd_counter_x1_ci_off(dut):
    """BCDCounterX1: ci=0 freezes the counter."""
    clock = Clock(dut.Clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    dut.Rst_n.value = 0
    dut.ci.value = 0
    for _ in range(5):
        await RisingEdge(dut.Clk)
    dut.Rst_n.value = 1
    for _ in range(3):
        await RisingEdge(dut.Clk)

    dut.ci.value = 1
    for _ in range(3):
        await RisingEdge(dut.Clk)

    # Turn off ci first, then read frozen value
    dut.ci.value = 0
    await RisingEdge(dut.Clk)  # This edge sees ci=0, no increment
    frozen = int(dut.count.value)

    for _ in range(5):
        await RisingEdge(dut.Clk)

    assert int(dut.count.value) == frozen, f"Count should stay {frozen} when ci=0"


@cocotb.test()
async def test_bcd_counter_x1_carry(dut):
    """BCDCounterX1: co asserted at count=8."""
    clock = Clock(dut.Clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    dut.Rst_n.value = 0
    dut.ci.value = 0
    for _ in range(5):
        await RisingEdge(dut.Clk)
    dut.Rst_n.value = 1
    for _ in range(3):
        await RisingEdge(dut.Clk)

    dut.ci.value = 1

    for i in range(30):
        val = int(dut.count.value)
        co = int(dut.co.value)
        # co is non-blocking: (count==8) means co=1 when count transitions to 9
        # co=1 should appear when count==9 (carry for next digit rolling over)
        if val == 9:
            assert co == 1, f"co should be 1 when count=9 (carry to next digit), got co={co}"
        if val == 0 and i > 9:
            # After the first full cycle, co should be 0 when count=0
            pass
        await RisingEdge(dut.Clk)
