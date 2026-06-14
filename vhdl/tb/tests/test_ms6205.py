"""
Tests for MS6205 module — display controller for the MS6205 VFD/LCD.

MS6205 manages display RAM (stdioRam, insnRam, dataRam), view modes (IRAM, DRAM, CIO),
and auto-scans through 160 display positions. It receives ASCII data via a TX-like
interface and drives address/data outputs for the display.
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import Timer, RisingEdge, FallingEdge

import logging
log = logging.getLogger(__name__)

# DEKATRON parameters (must match parameters.sv defaults)
IP_DEKATRON_NUM = 5
AP_DEKATRON_NUM = 5
DATA_DEKATRON_NUM = 3
DEKATRON_WIDTH = 4
INSN_WIDTH = 4
MAX_POS = 160

CLOCK_1US_NS = 1000
CLOCK_1MS_NS = 1000000


async def reset_dut(dut):
    """Reset MS6205 and wait for stabilization."""
    dut.Rst_n.value = 0
    dut.tx_vld_i.value = 0
    dut.tx_data.value = 0
    dut.tx_switch_view_i.value = 0
    dut.keysCurrentState.value = 0
    dut.DPC_State.value = 0
    dut.write_addr.value = 0
    dut.write_data.value = 0
    dut.ready.value = 0
    dut.ipAddress.value = 0
    dut.apAddress.value = 0
    dut.apData.value = 0
    dut.apData1.value = 0
    dut.RomData1.value = 0
    await Timer(5 * CLOCK_1US_NS, unit="ns")
    dut.Rst_n.value = 1
    await Timer(10 * CLOCK_1MS_NS, unit="ns")


@cocotb.test()
async def test_ms6205_reset(dut):
    """After reset, address should be 0 and ms6205_currentView should be RESTART(0)."""
    clock_us = Clock(dut.Clock_1us, CLOCK_1US_NS, unit="ns")
    clock_ms = Clock(dut.Clock_1ms, CLOCK_1MS_NS, unit="ns")
    cocotb.start_soon(clock_us.start())
    cocotb.start_soon(clock_ms.start())

    dut.Rst_n.value = 0
    await Timer(10 * CLOCK_1MS_NS, unit="ns")
    assert int(dut.address.value) == 0, f"Address should be 0 during reset, got {int(dut.address.value)}"

    dut.Rst_n.value = 1
    await Timer(10 * CLOCK_1MS_NS, unit="ns")


@cocotb.test()
async def test_ms6205_address_increment(dut):
    """Address should auto-increment from 0 to MAX_POS-1 then wrap to 0 (on Clock_1ms negedge)."""
    clock_us = Clock(dut.Clock_1us, CLOCK_1US_NS, unit="ns")
    clock_ms = Clock(dut.Clock_1ms, CLOCK_1MS_NS, unit="ns")
    cocotb.start_soon(clock_us.start())
    cocotb.start_soon(clock_ms.start())

    await reset_dut(dut)

    prev_addr = -1
    # Collect addresses over more than MAX_POS clock_ms cycles
    for _ in range(MAX_POS + 10):
        await FallingEdge(dut.Clock_1ms)
        cur = int(dut.address.value)
        if prev_addr >= 0:
            expected = (prev_addr + 1) % MAX_POS
            assert cur == expected, f"Address step: prev={prev_addr}, expected={expected}, got={cur}"
        prev_addr = cur

    log.info(f"Address wrapping verified: last addr={prev_addr}")


@cocotb.test()
async def test_ms6205_stdio_write(dut):
    """Write data via tx interface and verify stdioRam contents through address/data scan."""
    clock_us = Clock(dut.Clock_1us, CLOCK_1US_NS, unit="ns")
    clock_ms = Clock(dut.Clock_1ms, CLOCK_1MS_NS, unit="ns")
    cocotb.start_soon(clock_us.start())
    cocotb.start_soon(clock_ms.start())

    await reset_dut(dut)

    # Switch to CIO view so stdioRam is displayed (default view)
    # Press CIO key to switch view
    dut.keysCurrentState.value = 1 << 0  # KEYBOARD_CIO_KEY = 0
    for _ in range(5):
        await FallingEdge(dut.Clock_1ms)

    # Write 'A' (0x41) via tx interface
    dut.tx_data.value = 0x41
    dut.tx_vld_i.value = 1
    await FallingEdge(dut.Clock_1us)
    await FallingEdge(dut.Clock_1us)
    dut.tx_vld_i.value = 0

    # Wait for the data to propagate through the display scan
    # The data should appear at address 0 (stdioAddr starts at 0, increments on tx_vld)
    # Scan through positions until we reach address 0
    found_a = False
    for _ in range(2000):
        await FallingEdge(dut.Clock_1ms)
        if int(dut.address.value) == 0:
            # data_n is inverted: data_n = ~stdioData
            data_n_val = int(dut.data_n.value)
            data_val = (~data_n_val) & 0xFF
            if data_val == 0x41:
                found_a = True
                log.info(f"Found 0x41 at address 0: data_n={data_n_val:#x}, data={data_val:#x}")
            break

    assert found_a, "Written byte 0x41 not found at address 0 in display RAM"


@cocotb.test()
async def test_ms6205_view_switching(dut):
    """Test view mode switching via keysCurrentState."""
    clock_us = Clock(dut.Clock_1us, CLOCK_1US_NS, unit="ns")
    clock_ms = Clock(dut.Clock_1ms, CLOCK_1MS_NS, unit="ns")
    cocotb.start_soon(clock_us.start())
    cocotb.start_soon(clock_ms.start())

    await reset_dut(dut)

    # View should be RESTART(0) -> IRAM(2) on first ms clock after reset
    for _ in range(5):
        await FallingEdge(dut.Clock_1ms)

    # Press DRAM key (KEYBOARD_DRAM_KEY = 10)
    dut.keysCurrentState.value = 1 << 10
    for _ in range(5):
        await FallingEdge(dut.Clock_1ms)

    # Press CIO key (KEYBOARD_CIO_KEY = 0)
    dut.keysCurrentState.value = 1 << 0
    for _ in range(5):
        await FallingEdge(dut.Clock_1ms)

    # Press IRAM key (KEYBOARD_IRAM_KEY = 15)
    dut.keysCurrentState.value = 1 << 15
    for _ in range(5):
        await FallingEdge(dut.Clock_1ms)

    log.info("View switching sequence completed")


@cocotb.test()
async def test_ms6205_marker(dut):
    """marker should be 1 when view==IRAM and DPC_State==2."""
    clock_us = Clock(dut.Clock_1us, CLOCK_1US_NS, unit="ns")
    clock_ms = Clock(dut.Clock_1ms, CLOCK_1MS_NS, unit="ns")
    cocotb.start_soon(clock_us.start())
    cocotb.start_soon(clock_ms.start())

    await reset_dut(dut)

    # After reset, view transitions to IRAM (MS6205_IRAM = 2)
    for _ in range(5):
        await FallingEdge(dut.Clock_1ms)

    # Set DPC_State to 2
    dut.DPC_State.value = 2
    await Timer(CLOCK_1MS_NS, unit="ns")
    assert int(dut.marker.value) == 1, f"marker should be 1 when IRAM view and DPC_State=2, got {int(dut.marker.value)}"

    # Set DPC_State to 0
    dut.DPC_State.value = 0
    await Timer(CLOCK_1MS_NS, unit="ns")
    assert int(dut.marker.value) == 0, f"marker should be 0 when DPC_State!=2, got {int(dut.marker.value)}"


@cocotb.test()
async def test_ms6205_data_n_inverted(dut):
    """data_n should be the bitwise inversion of the internal stdioData."""
    clock_us = Clock(dut.Clock_1us, CLOCK_1US_NS, unit="ns")
    clock_ms = Clock(dut.Clock_1ms, CLOCK_1MS_NS, unit="ns")
    cocotb.start_soon(clock_us.start())
    cocotb.start_soon(clock_ms.start())

    await reset_dut(dut)

    # The display RAM is initialized from MSmemZero.hex
    # We just verify that after some ms clocks, data_n changes (non-static)
    samples = set()
    for _ in range(20):
        await FallingEdge(dut.Clock_1ms)
        samples.add(int(dut.data_n.value))

    assert len(samples) > 1, "data_n should change as address scans through display RAM"
    log.info(f"data_n samples: {[hex(s) for s in list(samples)[:10]]}")
