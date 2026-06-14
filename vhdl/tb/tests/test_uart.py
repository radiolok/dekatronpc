"""
Tests for uart_tx module — UART transmitter.

Default parameters: DATA_WIDTH=8, PARITY_CHECK="NONE", CLK_FREQ=50000000,
STOP_BITS=1, BAUD_RATE=9600.
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import Timer, RisingEdge

import logging
log = logging.getLogger(__name__)

CLK_FREQ = 50000000
BAUD_RATE = 9600
BIT_PERIOD_CYCLES = CLK_FREQ // BAUD_RATE
CLOCK_PERIOD_NS = 20


async def reset_tx(dut):
    dut.rst.value = 1
    dut.i_vld.value = 0
    dut.i_data.value = 0
    await Timer(10 * CLOCK_PERIOD_NS, unit="ns")
    dut.rst.value = 0
    await Timer(10 * CLOCK_PERIOD_NS, unit="ns")


@cocotb.test()
async def test_uart_tx_idle(dut):
    """TX line should be high (idle) after reset and when no transmission."""
    clock = Clock(dut.clk, CLOCK_PERIOD_NS, unit="ns")
    cocotb.start_soon(clock.start())

    await reset_tx(dut)
    await Timer(50 * CLOCK_PERIOD_NS, unit="ns")

    assert int(dut.tx.value) == 1, f"TX should be idle high, got {int(dut.tx.value)}"
    assert int(dut.o_rdy.value) == 1, "o_rdy should be high when idle"


@cocotb.test()
async def test_uart_tx_transmit_byte(dut):
    """Transmit a byte and verify the serial output waveform."""
    clock = Clock(dut.clk, CLOCK_PERIOD_NS, unit="ns")
    cocotb.start_soon(clock.start())

    await reset_tx(dut)

    dut.i_data.value = 0xA5
    dut.i_vld.value = 1
    await RisingEdge(dut.clk)
    dut.i_vld.value = 0

    for _ in range(10):
        await RisingEdge(dut.clk)
        if int(dut.o_rdy.value) == 0:
            break

    found_start = False
    for _ in range(BIT_PERIOD_CYCLES + 10):
        await RisingEdge(dut.clk)
        if int(dut.tx.value) == 0:
            found_start = True
            break
    assert found_start, "Start bit (TX=0) not detected"

    skip_cycles = BIT_PERIOD_CYCLES + BIT_PERIOD_CYCLES // 2
    for _ in range(skip_cycles):
        await RisingEdge(dut.clk)

    received = 0
    for bit_idx in range(8):
        received |= (int(dut.tx.value) << bit_idx)
        for _ in range(BIT_PERIOD_CYCLES):
            await RisingEdge(dut.clk)

    assert received == 0xA5, f"Expected 0xA5, got {received:#x}"
    assert int(dut.tx.value) == 1, "Stop bit should be high"

    log.info(f"TX transmit 0xA5 successful, received={received:#x}")


@cocotb.test()
async def test_uart_tx_ready_flag(dut):
    """o_rdy should be low during transmission and high when done."""
    clock = Clock(dut.clk, CLOCK_PERIOD_NS, unit="ns")
    cocotb.start_soon(clock.start())

    await reset_tx(dut)
    assert int(dut.o_rdy.value) == 1, "o_rdy should be 1 initially"

    dut.i_data.value = 0x55
    dut.i_vld.value = 1
    await RisingEdge(dut.clk)
    dut.i_vld.value = 0

    for _ in range(20):
        await RisingEdge(dut.clk)
        if int(dut.o_rdy.value) == 0:
            break
    assert int(dut.o_rdy.value) == 0, "o_rdy should go low during transmission"

    for _ in range(BIT_PERIOD_CYCLES * 12):
        await RisingEdge(dut.clk)
        if int(dut.o_rdy.value) == 1:
            break
    assert int(dut.o_rdy.value) == 1, "o_rdy should go high after transmission"


@cocotb.test()
async def test_uart_tx_multiple_bytes(dut):
    """Transmit multiple bytes back-to-back."""
    clock = Clock(dut.clk, CLOCK_PERIOD_NS, unit="ns")
    cocotb.start_soon(clock.start())

    await reset_tx(dut)

    test_bytes = [0x00, 0xFF, 0xAA, 0x55, 0x12, 0x34]
    for byte_val in test_bytes:
        for _ in range(BIT_PERIOD_CYCLES * 12):
            await RisingEdge(dut.clk)
            if int(dut.o_rdy.value) == 1:
                break
        assert int(dut.o_rdy.value) == 1, f"TX should be ready before sending {byte_val:#x}"

        dut.i_data.value = byte_val
        dut.i_vld.value = 1
        await RisingEdge(dut.clk)
        dut.i_vld.value = 0

        for _ in range(10):
            await RisingEdge(dut.clk)
            if int(dut.o_rdy.value) == 0:
                break

    log.info(f"Multiple byte transmission: {[hex(b) for b in test_bytes]} sent")
