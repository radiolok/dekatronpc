"""
UART loopback test: connects TX directly to RX via uart_loopback_wrapper.

Verifies that data transmitted through uart_tx is correctly received by uart_rx.
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


async def collect_rx(dut, out):
    """Record rx_o_data on every rx_o_vld pulse.

    The wrapper ties RX i_rdy to 1, so rx_o_vld is a single-cycle pulse in the
    middle of the stop bit; it must be watched concurrently, not polled after
    TX reports ready.
    """
    while True:
        await RisingEdge(dut.clk)
        await ReadOnly()
        if int(dut.rx_o_vld.value):
            out.append(int(dut.rx_o_data.value))


async def send_byte(dut, byte_val):
    """Wait for TX ready, hand over one byte, wait until TX is ready again."""
    for _ in range(BIT_PERIOD_CYCLES * 12):
        await RisingEdge(dut.clk)
        if int(dut.o_rdy.value) == 1:
            break
    dut.i_data.value = byte_val
    dut.i_vld.value = 1
    await RisingEdge(dut.clk)
    dut.i_vld.value = 0
    for _ in range(20):
        await RisingEdge(dut.clk)
        if int(dut.o_rdy.value) == 0:
            break
    for _ in range(BIT_PERIOD_CYCLES * 12):
        await RisingEdge(dut.clk)
        if int(dut.o_rdy.value) == 1:
            break


@cocotb.test()
async def test_uart_loopback(dut):
    """Transmit a byte through TX, verify RX receives the same byte."""
    clock = Clock(dut.clk, CLOCK_PERIOD_NS, unit="ns")
    cocotb.start_soon(clock.start())

    dut.rst.value = 1
    dut.i_vld.value = 0
    dut.i_data.value = 0
    await Timer(10 * CLOCK_PERIOD_NS, unit="ns")
    dut.rst.value = 0
    await Timer(10 * CLOCK_PERIOD_NS, unit="ns")

    received = []
    cocotb.start_soon(collect_rx(dut, received))

    await send_byte(dut, 0x5A)
    # TX reports ready at the end of its stop bit; let RX finish sampling.
    for _ in range(BIT_PERIOD_CYCLES):
        await RisingEdge(dut.clk)

    log.info(f"Loopback received {[hex(b) for b in received]}")
    assert received == [0x5A], f"Loopback expected [0x5a], got {[hex(b) for b in received]}"


@cocotb.test()
async def test_uart_loopback_multiple(dut):
    """Loopback test with multiple bytes."""
    clock = Clock(dut.clk, CLOCK_PERIOD_NS, unit="ns")
    cocotb.start_soon(clock.start())

    dut.rst.value = 1
    dut.i_vld.value = 0
    dut.i_data.value = 0
    await Timer(10 * CLOCK_PERIOD_NS, unit="ns")
    dut.rst.value = 0
    await Timer(10 * CLOCK_PERIOD_NS, unit="ns")

    received = []
    cocotb.start_soon(collect_rx(dut, received))

    test_bytes = [0x12, 0x34, 0xAB, 0xCD]
    for byte_val in test_bytes:
        await send_byte(dut, byte_val)
    for _ in range(BIT_PERIOD_CYCLES):
        await RisingEdge(dut.clk)

    log.info(f"Loopback received {[hex(b) for b in received]}")
    assert received == test_bytes, (
        f"Loopback expected {[hex(b) for b in test_bytes]}, got {[hex(b) for b in received]}"
    )
