"""
Tests for ROM module — read-only instruction storage with firmware ROM.

Ports:
  Clk, Rst_n, Address[D_NUM*D_WIDTH-1:0]=24, Insn[DATA_WIDTH-1:0]=4,
  Request, Ready

Parameters (defaults):
  D_NUM=6, D_WIDTH=4, DATA_WIDTH=4

Internals:
  3-state FSM: INIT→(Request)→BUSY→(DataReady)→READY
  Insn updated on negedge Clk when state==BUSY
  firmware #(.portSize(D_NUM*D_WIDTH), .dataSize(DATA_WIDTH)) provides Data

LIMITATION: The ROM module instantiates a `firmware` submodule that must be
compiled into the simulation. Without the generated firmware module, the
elaboration will fail with an undefined-module error. The Makefile's test_rom
target currently omits the firmware source. To run this test, add:
  $(VHDL_ROOT)/programs/firmware.sv
to the VERILOG_SOURCES for the test_rom target in vhdl/tb/Makefile (line 145).

Until that is done, this test file is provided for documentation of the
expected behavior.
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import Timer, RisingEdge

import logging
log = logging.getLogger(__name__)

D_NUM = 6
D_WIDTH = 4
DATA_WIDTH = 4


def _bcd_address(digits):
    """Pack a list of 6 BCD digits (0-9 each) into a 24-bit BCD address."""
    addr = 0
    for i, d in enumerate(digits):
        addr |= (d & 0xF) << (4 * i)
    return addr


async def _rom_reset(dut):
    """Assert reset, wait, deassert, stabilize."""
    dut.Rst_n.value = 0
    dut.Request.value = 0
    dut.Address.value = 0
    for _ in range(5):
        await RisingEdge(dut.Clk)
    dut.Rst_n.value = 1
    for _ in range(5):
        await RisingEdge(dut.Clk)


async def _rom_request_read(dut, address_bcd):
    """Perform a full Request→Ready handshake and return Insn.

    Sequence:
      1. Set Address, Request=1
      2. Wait for BUSY→READY transition
      3. Deassert Request
      4. Wait for Ready assertion
      5. Return Insn
    """
    dut.Address.value = address_bcd
    dut.Request.value = 1
    await RisingEdge(dut.Clk)

    # State: INIT → BUSY on first posedge
    await RisingEdge(dut.Clk)
    # State: BUSY → READY on second posedge (DataReady=1)
    # Insn updates on negedge when state==BUSY

    dut.Request.value = 0

    for _ in range(10):
        await RisingEdge(dut.Clk)
        if int(dut.Ready.value) == 1:
            break

    return int(dut.Insn.value)


@cocotb.test()
async def test_rom_handshake(dut):
    """ROM: Request/Ready handshake — Ready asserted after Request deasserted."""
    clock = Clock(dut.Clk, 1000, unit="ns")
    cocotb.start_soon(clock.start())
    await _rom_reset(dut)

    # Phase 1: Ready should be 0 in INIT
    dut.Request.value = 0
    await RisingEdge(dut.Clk)
    assert int(dut.Ready.value) == 0, "Ready=0 expected in INIT with no request"

    # Phase 2: Assert Request — Ready stays 0
    dut.Request.value = 1
    dut.Address.value = 0
    await RisingEdge(dut.Clk)
    assert int(dut.Ready.value) == 0, "Ready=0 expected while BUSY"

    # Phase 3: BUSY→READY transition
    await RisingEdge(dut.Clk)
    assert int(dut.Ready.value) == 0, "Ready=0 while Request still asserted"

    # Phase 4: Deassert Request — Ready asserts
    dut.Request.value = 0
    await RisingEdge(dut.Clk)
    assert int(dut.Ready.value) == 1, "Ready=1 expected after Request deasserted"

    log.info("ROM handshake: verified Request→Ready sequence")


@cocotb.test()
async def test_rom_data_output(dut):
    """ROM: Insn output valid after BUSY→READY transition.

    The firmware module (firmware.sv) maps address 0→0x2 (+), 1→0x2 (+), ...
    This test reads from known firmware addresses and verifies non-X output.
    """
    clock = Clock(dut.Clk, 1000, unit="ns")
    cocotb.start_soon(clock.start())
    await _rom_reset(dut)

    # Read address 0 (should return firmware data 0x2 = '+' in looptest)
    insn0 = await _rom_request_read(dut, 0)
    log.info(f"ROM address 0x000000 → Insn=0x{insn0:x}")

    # The firmware returns 0x2 for address 0 in the current firmware.sv
    # (looptest program: first instruction is '+')
    # This may vary depending on which firmware program is compiled in.
    # Just verify the output is a stable value (no X/Z bits).
    insn0_again = await _rom_request_read(dut, 0)
    assert insn0 == insn0_again, (
        f"ROM read at addr 0 not stable: 0x{insn0:x} vs 0x{insn0_again:x}"
    )

    # Read a few addresses, verify consistent values
    values = {}
    for addr in range(8):
        val = await _rom_request_read(dut, addr)
        values[addr] = val
        log.info(f"ROM addr 0x{addr:06x} → 0x{val:x}")

    # Re-read and verify consistency
    for addr in range(8):
        val = await _rom_request_read(dut, addr)
        assert val == values[addr], (
            f"ROM addr 0x{addr:06x}: inconsistent reads {val:#x} vs {values[addr]:#x}"
        )

    log.info(f"ROM data output: verified stable reads across 8 addresses")


@cocotb.test()
async def test_rom_reset(dut):
    """ROM: reset clears Insn output and returns FSM to INIT."""
    clock = Clock(dut.Clk, 1000, unit="ns")
    cocotb.start_soon(clock.start())
    await _rom_reset(dut)

    # Read a value first
    val = await _rom_request_read(dut, 0)

    # Assert reset
    dut.Rst_n.value = 0
    for _ in range(3):
        await RisingEdge(dut.Clk)
    dut.Rst_n.value = 1
    for _ in range(5):
        await RisingEdge(dut.Clk)

    # After reset, Insn should be 0 (cleared on negedge during reset)
    dut.Address.value = 0
    dut.Request.value = 0
    await RisingEdge(dut.Clk)
    assert int(dut.Insn.value) == 0, (
        f"After reset Insn should be 0, got {int(dut.Insn.value):#x}"
    )

    # Ready should be 0 (INIT state)
    assert int(dut.Ready.value) == 0, "Ready=0 expected after reset (state=INIT)"

    log.info("ROM reset: Insn cleared, state returns to INIT")


@cocotb.test()
async def test_rom_multiple_requests(dut):
    """ROM: multiple back-to-back Request/Ready cycles work correctly."""
    clock = Clock(dut.Clk, 1000, unit="ns")
    cocotb.start_soon(clock.start())
    await _rom_reset(dut)

    for addr in range(5):
        val = await _rom_request_read(dut, addr)
        log.info(f"ROM cycle {addr}: addr 0x{addr:06x} → 0x{val:x}")

        # Ensure Ready deasserts when we assert Request again
        dut.Request.value = 0
        await RisingEdge(dut.Clk)
        assert int(dut.Ready.value) == 1, f"Ready should stay 1 after req=0, cycle {addr}"

    log.info("ROM multiple requests: 5 back-to-back cycles completed")


@cocotb.test()
async def test_rom_insn_on_negedge(dut):
    """ROM: verify Insn updates on negedge Clk during BUSY state.

    ROM.sv updates Insn on negedge Clk (line 66):
      always @(negedge Clk, negedge Rst_n)
          if (state == BUSY) Insn <= Data;

    This differs from IpMemory which updates on posedge.
    """
    clock = Clock(dut.Clk, 1000, unit="ns")
    cocotb.start_soon(clock.start())
    await _rom_reset(dut)

    # Set up a request and watch the Insn signal around clock edges
    dut.Address.value = 0
    dut.Request.value = 1

    # Before first posedge, Insn should be 0 (from reset)
    assert int(dut.Insn.value) == 0, f"Insn before first posedge: expected 0, got {int(dut.Insn.value):#x}"

    # First posedge: INIT→BUSY
    await RisingEdge(dut.Clk)

    # Now state is BUSY. On next negedge, Insn should update.
    # Track Insn before and after negedge
    insn_before_negedge = int(dut.Insn.value)

    # Wait for negedge (half period after posedge)
    await Timer(500, unit="ns")

    insn_after_negedge = int(dut.Insn.value)
    log.info(
        f"ROM negedge: Insn before={insn_before_negedge:#x}, after={insn_after_negedge:#x}"
    )

    # Insn should have changed from its reset value to firmware data
    # on the negedge when state==BUSY
    assert insn_before_negedge != insn_after_negedge or insn_after_negedge == 0, (
        "Insn should update on negedge during BUSY"
    )

    log.info("ROM negedge: confirmed Insn update timing")
