"""
Tests for RAM module — synchronous memory with chip select.

RAM parameters:
  ROWS=30000, ADDR_WIDTH=$clog2(ROWS)=15, DATA_WIDTH=8
Ports:
  Rst_n, Clk, Address[ADDR_WIDTH-1:0], In[DATA_WIDTH-1:0],
  Out[DATA_WIDTH-1:0], WE, CS
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import Timer, RisingEdge

import random
import logging
log = logging.getLogger(__name__)


def _is_high_z(value):
    """Check if a BinaryValue represents all high-impedance bits."""
    binstr = value.binstr
    return all(c in ('z', 'Z') for c in binstr)


async def _ram_reset(dut):
    """Assert and deassert reset, then wait for stabilization."""
    dut.Rst_n.value = 1  # ensure clean 1→0 negedge
    dut.CS.value = 1
    dut.WE.value = 0
    dut.In.value = 0
    dut.Address.value = 0
    for _ in range(2):
        await RisingEdge(dut.Clk)
    dut.Rst_n.value = 0
    for _ in range(5):
        await RisingEdge(dut.Clk)
    dut.Rst_n.value = 1
    for _ in range(3):
        await RisingEdge(dut.Clk)


async def _ram_write(dut, address, data):
    """Write a single value to RAM."""
    dut.Address.value = address
    dut.In.value = data
    dut.WE.value = 1
    dut.CS.value = 1
    await RisingEdge(dut.Clk)


async def _ram_read(dut, address):
    """Read a single value from RAM and return the result."""
    dut.Address.value = address
    dut.WE.value = 0
    dut.CS.value = 1
    await RisingEdge(dut.Clk)
    await Timer(1, unit='ns')
    return int(dut.Out.value)


@cocotb.test()
async def test_ram_write_read(dut):
    """RAM: write random data to random addresses, read back, verify."""
    clock = Clock(dut.Clk, 1000, unit="ns")
    cocotb.start_soon(clock.start())
    await _ram_reset(dut)

    random.seed(42)

    # Collect test data — use first 100 addresses
    test_data = {}
    for _ in range(50):
        addr = random.randint(0, 99)
        data = random.randint(0, 255)
        test_data[addr] = data

    # Write phase
    for addr, data in test_data.items():
        await _ram_write(dut, addr, data)

    # Read back and verify
    for addr, expected in test_data.items():
        actual = await _ram_read(dut, addr)
        assert actual == expected, (
            f"RAM mismatch at address {addr}: expected {expected:#04x}, got {actual:#04x}"
        )

    log.info(f"RAM write/read: verified {len(test_data)} addresses")


@cocotb.test()
async def test_ram_cs_zero(dut):
    """RAM: CS=0 should give Hi-Z output on all data lines."""
    clock = Clock(dut.Clk, 1000, unit="ns")
    cocotb.start_soon(clock.start())
    await _ram_reset(dut)

    # Write some known data first
    await _ram_write(dut, 0, 0xA5)

    # Read with CS=1 to confirm data is there
    actual = await _ram_read(dut, 0)
    assert actual == 0xA5, f"Expected 0xA5, got {actual:#04x}"

    # Now read with CS=0 — output should be all-Z
    dut.Address.value = 0
    dut.WE.value = 0
    dut.CS.value = 0
    await RisingEdge(dut.Clk)

    assert _is_high_z(dut.Out.value), (
        f"CS=0: expected all-Z output, got {dut.Out.value.binstr}"
    )
    log.info("RAM CS=0: confirmed Hi-Z output")


@cocotb.test()
async def test_ram_reset_clears_output(dut):
    """RAM: reset clears Data output register (memory retained, cleared by bootloader)."""
    clock = Clock(dut.Clk, 1000, unit="ns")
    cocotb.start_soon(clock.start())
    await _ram_reset(dut)

    await _ram_write(dut, 0, 0x5A)
    actual = await _ram_read(dut, 0)
    assert actual == 0x5A, f"Pre-reset read failed: expected 0x5A, got {actual:#04x}"

    dut.Rst_n.value = 0
    for _ in range(3):
        await RisingEdge(dut.Clk)
    await Timer(1, unit='ns')
    assert int(dut.Out.value) == 0, (
        f"Data output not cleared during reset: got {int(dut.Out.value):#04x}"
    )
    dut.Rst_n.value = 1
    for _ in range(3):
        await RisingEdge(dut.Clk)
    log.info("RAM reset: Data output cleared")


@cocotb.test()
async def test_ram_we_zero_reads(dut):
    """RAM: WE=0 reads current address content without modifying."""
    clock = Clock(dut.Clk, 1000, unit="ns")
    cocotb.start_soon(clock.start())
    await _ram_reset(dut)

    await _ram_write(dut, 7, 0xAB)
    await _ram_write(dut, 8, 0xCD)

    # Read 7, then 8, then 7 again without writing
    v1 = await _ram_read(dut, 7)
    v2 = await _ram_read(dut, 8)
    v3 = await _ram_read(dut, 7)

    assert v1 == 0xAB, f"First read of addr 7: expected 0xAB, got {v1:#04x}"
    assert v2 == 0xCD, f"Read of addr 8: expected 0xCD, got {v2:#04x}"
    assert v3 == 0xAB, f"Second read of addr 7: expected 0xAB, got {v3:#04x}"
    log.info("RAM WE=0: consecutive reads return correct values")
