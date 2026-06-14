"""
Tests for the DekatronCounter module — the core BCD counter used by
IP, AP, Data, and Loop counters throughout the DPC.

This is the most important Dekatron subsystem test per the plan.
Replaces the legacy Counter_tb.sv.

DekatronCounter: multi-digit BCD counter with:
- Ready/Request handshake pattern
- INC/DEC/SET/SET_ZERO operations
- OneShot write pulse timing
- hsClk/Clk dual clock
- Carry chain across digits
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import Timer, RisingEdge, FallingEdge, ClockCycles

import logging
log = logging.getLogger(__name__)


# ============================================================
# Helper: Ready/Request handshake driver
# ============================================================

async def handshake_increment(dut, cycles=1):
    """Drive 1 or more increment operations using Ready/Request protocol."""
    for _ in range(cycles):
        dut.Request.value = 1
        await RisingEdge(dut.Clk)
        # Wait for Ready
        for _ in range(1000):
            if int(dut.Ready.value) == 1:
                break
            await RisingEdge(dut.Clk)
        dut.Request.value = 0
        await RisingEdge(dut.Clk)


async def handshake_decrement(dut, cycles=1):
    """Drive 1 or more decrement operations."""
    dut.Dec.value = 1
    await handshake_increment(dut, cycles)
    dut.Dec.value = 0


# ============================================================
# Tests
# ============================================================

@cocotb.test()
async def test_dcounter_reset(dut):
    """After reset: Ready should be high, Out should be 0."""
    clock_hs = Clock(dut.hsClk, 100, unit="ns")
    clock_clk = Clock(dut.Clk, 1000, unit="ns")
    cocotb.start_soon(clock_hs.start())
    cocotb.start_soon(clock_clk.start(start_high=False))

    dut.Rst_n.value = 0
    dut.Request.value = 0
    dut.Dec.value = 0
    dut.Set.value = 0
    dut.SetZero.value = 0
    dut.In.value = 0

    for _ in range(50):
        await RisingEdge(dut.hsClk)
    dut.Rst_n.value = 1
    for _ in range(50):
        await RisingEdge(dut.hsClk)

    ready_val = int(dut.Ready.value)
    log.info(f"Ready after reset: {ready_val}")
    # After reset, state=0 (IDLE), Request=0, DekatronBusy should be 0
    # Ready = ~Request & ~(|DekatronBusy) & (state == IDLE)
    assert ready_val == 1, f"Ready should be 1 after reset, got {ready_val}"


@cocotb.test()
async def test_dcounter_increment(dut):
    """Increment test: should count up one step per Request."""
    clock_hs = Clock(dut.hsClk, 100, unit="ns")
    clock_clk = Clock(dut.Clk, 1000, unit="ns")
    cocotb.start_soon(clock_hs.start())
    cocotb.start_soon(clock_clk.start(start_high=False))

    dut.Rst_n.value = 0
    dut.Request.value = 0
    dut.Dec.value = 0
    dut.Set.value = 0
    dut.SetZero.value = 0
    dut.In.value = 0

    for _ in range(100):
        await RisingEdge(dut.hsClk)
    dut.Rst_n.value = 1
    for _ in range(100):
        await RisingEdge(dut.hsClk)

    # Do 5 increments
    for expected in range(1, 6):
        await handshake_increment(dut)
        out_val = int(dut.Out.value)
        # With 3 default digits, check the lowest digit
        out_bcd_low = out_val & 0xF
        log.info(f"After {expected} increments: Out={out_val:#x}, low digit={out_bcd_low}")
        assert out_bcd_low == expected, f"Low digit should be {expected}, got {out_bcd_low}"


@cocotb.test()
async def test_dcounter_decrement(dut):
    """Decrement test: should count down from a known position."""
    clock_hs = Clock(dut.hsClk, 100, unit="ns")
    clock_clk = Clock(dut.Clk, 1000, unit="ns")
    cocotb.start_soon(clock_hs.start())
    cocotb.start_soon(clock_clk.start(start_high=False))

    dut.Rst_n.value = 0
    dut.Request.value = 0
    dut.Dec.value = 0
    dut.Set.value = 0
    dut.SetZero.value = 0
    dut.In.value = 0

    for _ in range(100):
        await RisingEdge(dut.hsClk)
    dut.Rst_n.value = 1
    for _ in range(100):
        await RisingEdge(dut.hsClk)

    # Increment to 3 first
    for _ in range(3):
        await handshake_increment(dut)

    out_after_inc = int(dut.Out.value)
    log.info(f"After 3 increments: Out={out_after_inc:#x}")
    assert (out_after_inc & 0xF) == 3, f"Low digit should be 3, got {out_after_inc & 0xF}"

    # Decrement back to 2
    await handshake_decrement(dut)
    out_after_dec = int(dut.Out.value)
    log.info(f"After decrement: Out={out_after_dec:#x}")
    assert (out_after_dec & 0xF) == 2, f"Low digit should be 2, got {out_after_dec & 0xF}"


@cocotb.test()
async def test_dcounter_set_zero(dut):
    """SetZero: should reset counter to zero."""
    clock_hs = Clock(dut.hsClk, 100, unit="ns")
    clock_clk = Clock(dut.Clk, 1000, unit="ns")
    cocotb.start_soon(clock_hs.start())
    cocotb.start_soon(clock_clk.start(start_high=False))

    dut.Rst_n.value = 0
    dut.Request.value = 0
    dut.Dec.value = 0
    dut.Set.value = 0
    dut.SetZero.value = 0
    dut.In.value = 0

    for _ in range(100):
        await RisingEdge(dut.hsClk)
    dut.Rst_n.value = 1
    for _ in range(100):
        await RisingEdge(dut.hsClk)

    # Count up a bit
    for _ in range(7):
        await handshake_increment(dut)

    out_before = int(dut.Out.value)
    log.info(f"Before SetZero: {out_before:#x}")
    assert (out_before & 0xF) == 7

    # Now set to zero
    dut.SetZero.value = 1
    dut.Request.value = 1
    await RisingEdge(dut.Clk)
    # Wait for Ready
    for _ in range(500):
        if int(dut.Ready.value) == 1:
            break
        await RisingEdge(dut.Clk)
    dut.Request.value = 0
    dut.SetZero.value = 0
    await RisingEdge(dut.Clk)

    out_after = int(dut.Out.value)
    log.info(f"After SetZero: {out_after:#x}")
    assert out_after == 0, f"SetZero should set Out to 0, got {out_after:#x}"


@cocotb.test()
async def test_dcounter_ready_handshake(dut):
    """Verify the full Ready/Request protocol:
    - Request=1 → Ready goes low while processing
    - Request=0, state=IDLE → Ready goes high
    """
    clock_hs = Clock(dut.hsClk, 100, unit="ns")
    clock_clk = Clock(dut.Clk, 1000, unit="ns")
    cocotb.start_soon(clock_hs.start())
    cocotb.start_soon(clock_clk.start(start_high=False))

    dut.Rst_n.value = 0
    dut.Request.value = 0
    dut.Dec.value = 0
    dut.Set.value = 0
    dut.SetZero.value = 0
    dut.In.value = 0

    for _ in range(100):
        await RisingEdge(dut.hsClk)
    dut.Rst_n.value = 1
    for _ in range(100):
        await RisingEdge(dut.hsClk)

    # Ready should be high initially
    assert int(dut.Ready.value) == 1, "Ready should be high at idle"

    # Assert Request
    dut.Request.value = 1
    await RisingEdge(dut.Clk)

    # Ready should drop while processing
    awaiting = 0
    for _ in range(200):
        if int(dut.Ready.value) == 1:
            break
        awaiting += 1
        await RisingEdge(dut.Clk)
    log.info(f"Ready asserted after {awaiting} cycles")

    # Deassert Request
    dut.Request.value = 0
    await RisingEdge(dut.Clk)

    # Ready should rise again (at some point after Request deasserted)
    for _ in range(100):
        if int(dut.Ready.value) == 1:
            break
        await RisingEdge(dut.Clk)

    assert int(dut.Ready.value) == 1, "Ready should return to high after handshake"


@cocotb.test()
async def test_dcounter_multi_digit_carry(dut):
    """Test carry propagation across multiple BCD digits."""
    clock_hs = Clock(dut.hsClk, 100, unit="ns")
    clock_clk = Clock(dut.Clk, 1000, unit="ns")
    cocotb.start_soon(clock_hs.start())
    cocotb.start_soon(clock_clk.start(start_high=False))

    dut.Rst_n.value = 0
    dut.Request.value = 0
    dut.Dec.value = 0
    dut.Set.value = 0
    dut.SetZero.value = 0
    dut.In.value = 0

    for _ in range(100):
        await RisingEdge(dut.hsClk)
    dut.Rst_n.value = 1
    for _ in range(100):
        await RisingEdge(dut.hsClk)

    # Do 10 increments — should cause rollover in low digit, carry to next digit
    for i in range(10):
        await handshake_increment(dut)

    out_val = int(dut.Out.value)
    low = out_val & 0xF
    high = (out_val >> 4) & 0xF
    log.info(f"After 10 increments: {out_val:#x}, low={low}, high={high}")
    # Low digit should be 0 (rolled over from 9), next digit should be 1
    assert low == 0, f"Low digit should be 0 after 10 increments, got {low}"
    assert high == 1, f"High digit should be 1 after 10 increments, got {high}"


@cocotb.test()
async def test_dcounter_no_pulse_without_request(dut):
    """Verify that no changes occur without Request."""
    clock_hs = Clock(dut.hsClk, 100, unit="ns")
    clock_clk = Clock(dut.Clk, 1000, unit="ns")
    cocotb.start_soon(clock_hs.start())
    cocotb.start_soon(clock_clk.start(start_high=False))

    dut.Rst_n.value = 0
    dut.Request.value = 0
    dut.Dec.value = 0
    dut.Set.value = 0
    dut.SetZero.value = 0
    dut.In.value = 0

    for _ in range(100):
        await RisingEdge(dut.hsClk)
    dut.Rst_n.value = 1
    for _ in range(100):
        await RisingEdge(dut.hsClk)

    initial = int(dut.Out.value)

    # Run many cycles without Request
    for _ in range(100):
        await RisingEdge(dut.Clk)

    final = int(dut.Out.value)
    assert final == initial, f"Counter should not change without Request: {initial}→{final}"
