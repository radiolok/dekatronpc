"""
Tests for Ram — the banked BCD memory with a Valid/Ready interface
(rtl/DekatronPC/RAM.sv, TRS 5 and 12.5).

Default parameters: D_NUM = 5 (address 00000..99999 in BCD tetrads),
DATA_WIDTH = 10, BANK_DIGITS = 4, READ_CYCLES = WRITE_CYCLES = 1,
INIT_ZERO = 1, no overlay, no debug port.

Behaviour checked:
- ready does not depend on valid; it drops for the access and returns
  when rd_valid/err are set;
- read after write returns the written value in every bank;
- write-through: after a write rd_data already holds the written value;
- cells start at zero;
- an address tetrad above 9 raises err, gives no rd_valid and does not
  touch the memory.
"""

import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, ReadOnly

DATA_MASK = (1 << 10) - 1


def bcd(n, digits=5):
    """Decimal number -> packed BCD address."""
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
    dut.ovl_hit.value = 0
    dut.ovl_data.value = 0
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
    # accept: valid & ready on a rising edge, then the memory is busy
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
async def test_ready_after_reset(dut):
    """Idle memory is ready with and without valid (ready does not depend on valid)."""
    await setup(dut)
    await ReadOnly()
    assert int(dut.ready.value) == 1
    await FallingEdge(dut.clk)
    dut.valid.value = 1
    dut.addr.value = bcd(0)
    await ReadOnly()
    assert int(dut.ready.value) == 1, "ready must not depend on valid"


@cocotb.test()
async def test_init_zero(dut):
    """Untouched cells read as zero."""
    await setup(dut)
    for a in (0, 1, 9999, 10000, 54321, 99999):
        data, rv, err = await access(dut, bcd(a))
        assert (rv, err) == (1, 0), f"addr {a}: rd_valid={rv} err={err}"
        assert data == 0, f"addr {a}: expected 0, got {data}"


@cocotb.test()
async def test_write_read_banks(dut):
    """Write then read back across all ten banks and bank boundaries."""
    await setup(dut)
    rng = random.Random(110)
    addrs = [0, 9, 10, 99, 100, 9999, 10000, 29999, 30000, 50505, 89999, 99998, 99999]
    addrs += [rng.randrange(100000) for _ in range(20)]
    addrs = list(dict.fromkeys(addrs))
    ref = {}
    for a in addrs:
        v = rng.randrange(DATA_MASK + 1)
        ref[a] = v
        data, rv, err = await access(dut, bcd(a), wr=1, data=v)
        assert err == 0 and rv == 1, f"write {a}: rd_valid={rv} err={err}"
        assert data == v, f"write-through at {a}: expected {v}, got {data}"
    for a in reversed(addrs):
        data, rv, err = await access(dut, bcd(a))
        assert (rv, err) == (1, 0), f"read {a}: rd_valid={rv} err={err}"
        assert data == ref[a], f"addr {a}: expected {ref[a]}, got {data}"


@cocotb.test()
async def test_register_holds_last_cell(dut):
    """rd_data holds the last accessed cell until the next access."""
    await setup(dut)
    await access(dut, bcd(123), wr=1, data=0x155)
    await access(dut, bcd(456), wr=1, data=0x2AA)
    data, _, _ = await access(dut, bcd(123))
    assert data == 0x155
    for _ in range(5):
        await RisingEdge(dut.clk)
    await ReadOnly()
    assert int(dut.rd_data.value) == 0x155, "rd_data changed without an access"


@cocotb.test()
async def test_bad_bcd_address(dut):
    """A tetrad above 9 raises err and leaves the memory untouched."""
    await setup(dut)
    await access(dut, bcd(1230), wr=1, data=0x77)
    bad = bcd(1230) | 0xA          # 0123A
    _, rv, err = await access(dut, bad, wr=1, data=0x3FF)
    assert (rv, err) == (0, 1), f"write to {bad:05x}: rd_valid={rv} err={err}"
    _, rv, err = await access(dut, 0xF0000)
    assert (rv, err) == (0, 1), f"read from F0000: rd_valid={rv} err={err}"
    data, rv, err = await access(dut, bcd(1230))
    assert (rv, err) == (1, 0)
    assert data == 0x77, f"bad write disturbed cell 01230: {data:#x}"
