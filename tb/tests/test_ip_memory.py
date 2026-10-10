"""
Tests for IpMemory — program memory: banked Ram with 4-bit opcodes and
the bootloader ROM overlaid on the top bank (TRS 5.1, 5.3).

Default parameters: D_NUM = 5, EN_BOOTLOADER = 1. Addresses 99900..99999
read the bootloader ROM (rtl/programs/bootloader/bootloader.sv); writes
there are refused with err.

Ports: clk, rst_n, valid, ready, wr, addr, wr_data, rd_data, rd_valid,
err, dbg_addr, dbg_data, is_bootloader.
"""

import os
import re
import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, ReadOnly

BOOT_SV = os.path.join(os.path.dirname(__file__), "..", "..", "rtl",
                       "programs", "bootloader", "bootloader.sv")


def boot_rom():
    """Opcodes of the regular (non-SIMPLEBOOT) bootloader, by low address byte."""
    text = open(BOOT_SV).read()
    body = text.split("`else", 1)[1]
    rom = {}
    for addr, data in re.findall(r"8'h([0-9a-fA-F]{2}):\s*Data\s*=\s*4'h([0-9a-fA-F])", body):
        rom[int(addr, 16)] = int(data, 16)
    return rom


def bcd(n, digits=5):
    v = 0
    for i in range(digits):
        v |= (n % 10) << (4 * i)
        n //= 10
    return v


async def setup(dut):
    cocotb.start_soon(Clock(dut.clk, 1000, unit="ns").start())
    dut.rst_n.value = 0
    dut.valid.value = 0
    dut.wr.value = 0
    dut.addr.value = 0
    dut.wr_data.value = 0
    dut.dbg_addr.value = 0
    for _ in range(3):
        await RisingEdge(dut.clk)
    await FallingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)


async def access(dut, addr, wr=0, data=0, timeout=50):
    """One Valid/Ready transfer. Returns (rd_data, rd_valid, err)."""
    await FallingEdge(dut.clk)
    dut.addr.value = addr
    dut.wr.value = wr
    dut.wr_data.value = data
    dut.valid.value = 1
    for _ in range(timeout):
        await RisingEdge(dut.clk)
        await ReadOnly()
        if int(dut.ready.value) == 0:
            break
    else:
        raise AssertionError("request was not accepted")
    await FallingEdge(dut.clk)
    dut.valid.value = 0
    for _ in range(timeout):
        await RisingEdge(dut.clk)
        await ReadOnly()
        if int(dut.ready.value) == 1:
            break
    else:
        raise AssertionError("ready did not return")
    return int(dut.rd_data.value), int(dut.rd_valid.value), int(dut.err.value)


@cocotb.test()
async def test_program_write_read(dut):
    """Opcodes written below the bootloader read back unchanged."""
    await setup(dut)
    rng = random.Random(4)
    addrs = [0, 1, 99, 100, 12345, 50000, 99899]
    addrs += [rng.randrange(99900) for _ in range(10)]
    addrs = list(dict.fromkeys(addrs))
    ref = {}
    for a in addrs:
        ref[a] = rng.randrange(16)
        _, rv, err = await access(dut, bcd(a), wr=1, data=ref[a])
        assert (rv, err) == (1, 0), f"write {a}: rd_valid={rv} err={err}"
    for a in addrs:
        data, rv, err = await access(dut, bcd(a))
        assert (rv, err) == (1, 0), f"read {a}: rd_valid={rv} err={err}"
        assert data == ref[a], f"addr {a}: expected {ref[a]:x}, got {data:x}"


@cocotb.test()
async def test_bootloader_read(dut):
    """99900..99999 read the bootloader ROM; is_bootloader marks the area."""
    await setup(dut)
    rom = boot_rom()
    assert rom, "could not parse bootloader.sv"
    for low in sorted(set(rom) | {0x13, 0x50}):
        addr = 0x99900 | low                     # low byte is two BCD tetrads
        await FallingEdge(dut.clk)
        dut.addr.value = addr
        await ReadOnly()
        assert int(dut.is_bootloader.value) == 1, f"{addr:05x} not marked as bootloader"
        data, rv, err = await access(dut, addr)
        assert (rv, err) == (1, 0), f"read {addr:05x}: rd_valid={rv} err={err}"
        assert data == rom.get(low, 0), \
            f"ROM {addr:05x}: expected {rom.get(low, 0):x}, got {data:x}"
    await FallingEdge(dut.clk)
    dut.addr.value = bcd(99899)
    await ReadOnly()
    assert int(dut.is_bootloader.value) == 0, "99899 marked as bootloader"


@cocotb.test()
async def test_bootloader_write_protected(dut):
    """A write into the bootloader area raises err and changes nothing."""
    await setup(dut)
    rom = boot_rom()
    addr = 0x99900
    _, rv, err = await access(dut, addr, wr=1, data=(rom.get(0, 0) ^ 0xF))
    assert (rv, err) == (0, 1), f"write to ROM: rd_valid={rv} err={err}"
    data, rv, err = await access(dut, addr)
    assert (rv, err) == (1, 0)
    assert data == rom.get(0, 0), f"ROM changed by a write: {data:x}"


@cocotb.test()
async def test_bad_bcd_address(dut):
    """A tetrad above 9 raises err."""
    await setup(dut)
    _, rv, err = await access(dut, 0x0000B)
    assert (rv, err) == (0, 1), f"read 0000B: rd_valid={rv} err={err}"
