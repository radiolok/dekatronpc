"""
Tests for the DekatronCounter module — the core BCD counter used by
IP, AP, Data, and Loop counters throughout the DPC.

This is the most important Dekatron subsystem test per the plan.
Replaces the legacy Counter_tb.sv.

DekatronCounter: multi-digit BCD counter with a Valid/Ready handshake:
- Valid is a level that is held until the transfer is accepted (Valid & Ready)
- Ready is independent of Valid (asserted in IDLE)
- INC/DEC: single-cycle operations (Ready stays high, 1 op/cycle)
- SET/SET_ZERO/SET_TOP: multi-cycle operations (Ready drops ~100 hsClk cycles)
- Operands (Dec/Set/SetZero/In) are latched on the accept cycle
- hsClk/Clk dual clock, carry chain across digits
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import Timer, RisingEdge, FallingEdge, ClockCycles

import logging
log = logging.getLogger(__name__)


# ============================================================
# Helpers: clocks, reset, Valid/Ready handshake driver
# ============================================================

async def start_clocks_and_reset(dut):
    """Start hs_clk (10x) and clk, then perform a reset sequence."""
    clock_hs = Clock(dut.hs_clk, 100, unit="ns")
    clock_clk = Clock(dut.clk, 1000, unit="ns")
    cocotb.start_soon(clock_hs.start())
    cocotb.start_soon(clock_clk.start(start_high=False))

    dut.rst_n.value = 0
    dut.valid.value = 0
    dut.dec.value = 0
    dut.set.value = 0
    dut.set_zero.value = 0
    getattr(dut, "in").value = 0

    for _ in range(100):
        await RisingEdge(dut.hs_clk)
    dut.rst_n.value = 1
    for _ in range(100):
        await RisingEdge(dut.hs_clk)


async def wait_ready(dut, timeout=1000):
    """Wait until ready is high, or fail."""
    for _ in range(timeout):
        if int(dut.ready.value) == 1:
            return
        await RisingEdge(dut.clk)
    raise AssertionError("ready did not assert within timeout")


async def handshake(dut, *, dec=0, set_=0, set_zero=0, in_val=0):
    """
    Perform one Valid/Ready transfer and wait for it to complete.

    Operands are qualified by valid and latched on the accept edge
    (valid & ready on a rising clk edge).
    """
    dut.dec.value = dec
    dut.set.value = set_
    dut.set_zero.value = set_zero
    getattr(dut, "in").value = in_val

    await wait_ready(dut)

    dut.valid.value = 1
    await RisingEdge(dut.clk)   # accept edge: valid & ready
    dut.valid.value = 0

    await wait_ready(dut)       # operation completes (ready rises again)
    # The fast-path result settles within one clk cycle after the accept
    # edge (hs_clk carry chain is < 10 hs_clk cycles).
    await ClockCycles(dut.clk, 1)


async def increment(dut, cycles=1):
    for _ in range(cycles):
        await handshake(dut, dec=0)


async def decrement(dut, cycles=1):
    for _ in range(cycles):
        await handshake(dut, dec=1)


async def set_value(dut, value):
    await handshake(dut, set_=1, in_val=value)


async def set_zero(dut):
    await handshake(dut, set_zero=1)


def bcd_digit(out_val, digit):
    """Extract one BCD digit (0 = least significant) from a packed BCD value."""
    return (out_val >> (4 * digit)) & 0xF


# ============================================================
# Tests
# ============================================================

@cocotb.test()
async def test_dcounter_reset(dut):
    """After reset: ready should be high and independent of valid."""
    await start_clocks_and_reset(dut)

    assert int(dut.ready.value) == 1, \
        f"ready should be 1 after reset, got {int(dut.ready.value)}"

    # ready must be independent of valid: asserting valid must not drop ready
    # while the counter is idle.
    dut.valid.value = 1
    await RisingEdge(dut.clk)
    assert int(dut.ready.value) == 1, \
        "ready must remain high while valid is asserted in IDLE"
    dut.valid.value = 0


@cocotb.test()
async def test_dcounter_increment(dut):
    """Increment test: count up one step per accepted transfer."""
    await start_clocks_and_reset(dut)

    for expected in range(1, 6):
        await increment(dut)
        out_val = int(dut.out.value)
        out_bcd_low = bcd_digit(out_val, 0)
        log.info(f"After {expected} increments: out={out_val:#x}, low digit={out_bcd_low}")
        assert out_bcd_low == expected, \
            f"Low digit should be {expected}, got {out_bcd_low}"


@cocotb.test()
async def test_dcounter_decrement(dut):
    """Decrement test: count down from a known position."""
    await start_clocks_and_reset(dut)

    await increment(dut, 3)
    out_after_inc = int(dut.out.value)
    log.info(f"After 3 increments: out={out_after_inc:#x}")
    assert bcd_digit(out_after_inc, 0) == 3, \
        f"Low digit should be 3, got {bcd_digit(out_after_inc, 0)}"

    await decrement(dut)
    out_after_dec = int(dut.out.value)
    log.info(f"After decrement: out={out_after_dec:#x}")
    assert bcd_digit(out_after_dec, 0) == 2, \
        f"Low digit should be 2, got {bcd_digit(out_after_dec, 0)}"


@cocotb.test()
async def test_dcounter_set_zero(dut):
    """set_zero: should reset counter to zero."""
    await start_clocks_and_reset(dut)

    await increment(dut, 7)
    out_before = int(dut.out.value)
    log.info(f"Before set_zero: {out_before:#x}")
    assert bcd_digit(out_before, 0) == 7

    await set_zero(dut)
    out_after = int(dut.out.value)
    log.info(f"After set_zero: {out_after:#x}")
    assert out_after == 0, f"set_zero should set out to 0, got {out_after:#x}"


@cocotb.test()
async def test_dcounter_set_value(dut):
    """set: should write in into the counter."""
    await start_clocks_and_reset(dut)

    await set_value(dut, 0x123)
    out_val = int(dut.out.value)
    log.info(f"After set 0x123: out={out_val:#x}")
    assert out_val == 0x123, f"set should write 0x123, got {out_val:#x}"


@cocotb.test()
async def test_dcounter_ready_independent(dut):
    """Verify the Valid/Ready protocol for a fast (INC) operation:
    - ready is high in IDLE
    - ready stays high while valid is asserted (independent of valid)
    - ready stays high after the transfer (single-cycle, no busy window)
    """
    await start_clocks_and_reset(dut)

    assert int(dut.ready.value) == 1, "ready should be high at idle"

    dut.valid.value = 1
    dut.dec.value = 0
    await RisingEdge(dut.clk)

    # During and immediately after the accept, ready must remain high.
    assert int(dut.ready.value) == 1, \
        "ready must stay high during/after a fast transfer"
    dut.valid.value = 0
    await RisingEdge(dut.clk)
    assert int(dut.ready.value) == 1, \
        "ready must return to high after the handshake"


@cocotb.test()
async def test_dcounter_back_to_back(dut):
    """Back-to-back increments: with valid held high, the counter must accept
    one operation every clk cycle (ready never drops)."""
    await start_clocks_and_reset(dut)

    dut.valid.value = 1
    dut.dec.value = 0

    n = 10
    for _ in range(n):
        assert int(dut.ready.value) == 1, \
            "ready must stay high during back-to-back fast transfers"
        await RisingEdge(dut.clk)

    # Let the final carry settle, then deassert valid.
    await ClockCycles(dut.clk, 1)
    dut.valid.value = 0

    out_val = int(dut.out.value)
    log.info(f"After {n} back-to-back cycles: out={out_val:#x}")
    assert bcd_digit(out_val, 0) == n % 10, \
        f"Low digit should be {n % 10} after {n} back-to-back cycles, " \
        f"got {bcd_digit(out_val, 0)}"
    assert bcd_digit(out_val, 1) == (n // 10) % 10, \
        f"Second digit should be {(n // 10) % 10}, got {bcd_digit(out_val, 1)}"


@cocotb.test()
async def test_dcounter_multi_digit_carry(dut):
    """Test carry propagation across multiple BCD digits."""
    await start_clocks_and_reset(dut)

    await increment(dut, 10)

    out_val = int(dut.out.value)
    low = bcd_digit(out_val, 0)
    high = bcd_digit(out_val, 1)
    log.info(f"After 10 increments: {out_val:#x}, low={low}, high={high}")
    assert low == 0, f"Low digit should be 0 after 10 increments, got {low}"
    assert high == 1, f"High digit should be 1 after 10 increments, got {high}"


@cocotb.test()
async def test_dcounter_in_latching(dut):
    """in must be latched on the accept edge. After the master deasserts valid
    and changes in, the counter must keep the latched value."""
    await start_clocks_and_reset(dut)

    # Start a set of 0x123.
    dut.set.value = 1
    getattr(dut, "in").value = 0x123
    await wait_ready(dut)
    dut.valid.value = 1
    await RisingEdge(dut.clk)   # accept: in should be latched here
    dut.valid.value = 0

    # Immediately change in before the (slow) write completes.
    getattr(dut, "in").value = 0x999
    await wait_ready(dut)

    out_val = int(dut.out.value)
    log.info(f"After set with in changed mid-write: out={out_val:#x}")
    assert out_val == 0x123, \
        f"set should latch 0x123 on accept, got {out_val:#x}"


@cocotb.test()
async def test_dcounter_no_pulse_without_valid(dut):
    """Verify that no changes occur without valid."""
    await start_clocks_and_reset(dut)

    initial = int(dut.out.value)

    for _ in range(100):
        await RisingEdge(dut.clk)

    final = int(dut.out.value)
    assert final == initial, \
        f"Counter should not change without valid: {initial:#x}→{final:#x}"
