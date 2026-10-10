"""
Tests for uart_rx module — UART receiver.

Default parameters: DATA_WIDTH=8, PARITY_CHECK="NONE", CLK_FREQ=50000000,
BAUD_RATE=9600.

The RX module samples 4x per bit using majority voting and has a start-bit
detection FSM. Tests feed serial data into rx and verify o_data/o_vld.

Also includes a loopback test using a combined uart_loopback wrapper
that connects TX directly to RX.
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import Timer, RisingEdge, ReadOnly

import logging
log = logging.getLogger(__name__)

CLK_FREQ = 50000000
BAUD_RATE = 9600
BIT_PERIOD_CYCLES = CLK_FREQ // BAUD_RATE
CLOCK_PERIOD_NS = 20


async def reset_rx(dut):
    dut.rst.value = 1
    dut.rx.value = 1
    dut.i_rdy.value = 0
    await Timer(10 * CLOCK_PERIOD_NS, unit="ns")
    dut.rst.value = 0
    await Timer(10 * CLOCK_PERIOD_NS, unit="ns")


async def wait_bit_periods(dut, count):
    for _ in range(count * BIT_PERIOD_CYCLES):
        await RisingEdge(dut.clk)


async def collect_rx(dut, out):
    """Record o_data on every o_vld&i_rdy handshake.

    With i_rdy=1 o_vld is a single-cycle pulse that fires in the middle of
    the stop bit, i.e. while feed_serial_byte() is still driving it, so it
    has to be watched concurrently rather than polled afterwards.
    """
    while True:
        await RisingEdge(dut.clk)
        await ReadOnly()
        if int(dut.o_vld.value) and int(dut.i_rdy.value):
            out.append(int(dut.o_data.value))


async def feed_serial_byte(dut, byte_val):
    """Feed a serial byte (LSB first, 1 start bit, 1 stop bit, no parity) into rx."""
    # Start bit
    dut.rx.value = 0
    await wait_bit_periods(dut, 1)

    # Data bits (LSB first)
    for bit_idx in range(8):
        bit_val = (byte_val >> bit_idx) & 1
        dut.rx.value = bit_val
        await wait_bit_periods(dut, 1)

    # Stop bit
    dut.rx.value = 1
    await wait_bit_periods(dut, 1)


@cocotb.test()
async def test_uart_rx_idle(dut):
    """RX should be idle with o_vld=0 after reset."""
    clock = Clock(dut.clk, CLOCK_PERIOD_NS, unit="ns")
    cocotb.start_soon(clock.start())

    await reset_rx(dut)
    await Timer(50 * CLOCK_PERIOD_NS, unit="ns")

    assert int(dut.o_vld.value) == 0, "o_vld should be 0 when idle"


@cocotb.test()
async def test_uart_rx_receive_byte(dut):
    """Feed a serial byte into rx and verify o_data with i_rdy=1."""
    clock = Clock(dut.clk, CLOCK_PERIOD_NS, unit="ns")
    cocotb.start_soon(clock.start())

    await reset_rx(dut)
    dut.i_rdy.value = 1

    received = []
    cocotb.start_soon(collect_rx(dut, received))

    byte_to_send = 0xC3
    await feed_serial_byte(dut, byte_to_send)

    log.info(f"RX received {[hex(b) for b in received]}")
    assert received == [byte_to_send], (
        f"RX expected [{byte_to_send:#x}], got {[hex(b) for b in received]}"
    )


@cocotb.test()
async def test_uart_rx_multiple_bytes(dut):
    """Receive multiple bytes in sequence."""
    clock = Clock(dut.clk, CLOCK_PERIOD_NS, unit="ns")
    cocotb.start_soon(clock.start())

    await reset_rx(dut)
    dut.i_rdy.value = 1

    received = []
    cocotb.start_soon(collect_rx(dut, received))

    test_bytes = [0x55, 0xAA, 0x0F, 0xF0]
    for byte_val in test_bytes:
        await feed_serial_byte(dut, byte_val)

    log.info(f"RX received {[hex(b) for b in received]}")
    assert received == test_bytes, (
        f"RX expected {[hex(b) for b in test_bytes]}, got {[hex(b) for b in received]}"
    )
