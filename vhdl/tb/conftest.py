"""
Shared test fixtures and utilities for DekatronPC cocotb tests.

Provides:
- Clock generation (hsClk 10x Clk with correct phase relationship)
- Standardized reset sequences
- cocotb-pytest integration hooks
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import Timer, RisingEdge, FallingEdge, ClockCycles

import logging

log = logging.getLogger("cocotb")


# ============================================================
# Clock Generation
# ============================================================

async def generate_hsclk(dut, period_ns: int = 100):
    """Generate hsClk (10 MHz) clock signal."""
    half_period_ns = period_ns // 2
    while True:
        await Timer(half_period_ns, units="ns")
        dut.hsClk.value ^= 1


async def generate_clk(dut, period_us: float = 1.0):
    """
    Generate Clk (1 MHz) from hsClk divider.
    Based on hsClk/10 relationship as defined in the DPC clocking scheme.
    hsClk period = 100ns, Clk period = 1us (10x ratio).
    """
    half_period_ns = int(period_us * 1000 / 2)
    while True:
        await Timer(half_period_ns, units="ns")
        dut.Clk.value ^= 1


async def dual_clock_generator(dut, hsclk_period_ns: int = 100):
    """
    Generate both hsClk and Clk with the correct 10:1 phase relationship
    as defined in DekatronPC_tb.cpp stepVerilog().

    hsClk toggles every HALF_HIGH_P (1 cycle = 100ns period at 1us/1ns timescale)
    Clk toggles every HALF_SLOW_P (10 cycles = 1us period)

    The authoritative clocking reference is:
        DekatronPC_tb.cpp lines 120-128
    """
    half = hsclk_period_ns // 2
    slow_half = half * 5  # 10:1 ratio

    while True:
        await Timer(half, units="ns")
        dut.hsClk.value ^= 1
        # Clk toggles at 1/10th the rate
        if hasattr(dut, "Clk"):
            tick = getattr(dut, "Clk")
            # Simple approach: use the hsClk positive edge count
            pass


async def start_dual_clocks(dut, hsclk_period_ns: int = 100):
    """
    Start both hsClk and Clk with correct phase.

    Clk is generated at 1/10 the hsClk rate by toggling every
    5 hsClk half-periods.
    """
    # Use cocotb Clock utility for hsClk
    hsclk = Clock(dut.hsClk, hsclk_period_ns, units="ns")
    cocotb.start_soon(hsclk.start())

    # Clk = hsClk / 10
    if hasattr(dut, "Clk"):
        clk = Clock(dut.Clk, hsclk_period_ns * 10, units="ns")
        # Align with first hsClk edge
        await RisingEdge(dut.hsClk)
        cocotb.start_soon(clk.start(start_high=False))


# ============================================================
# Reset Sequences
# ============================================================

async def reset_dut(dut, clk_signal, duration_ns: int = 1000):
    """
    Standard 3-phase reset:
    1. Assert Rst_n low (async)
    2. Wait for specified duration
    3. Deassert Rst_n high
    4. Wait for a few clock cycles

    Args:
        dut: Device under test
        clk_signal: The clock signal name (e.g., dut.Clk or dut.hsClk)
        duration_ns: How long to hold reset low
    """
    # Phase 1: Assert reset
    dut.Rst_n.value = 0
    await Timer(duration_ns, units="ns")

    # Phase 2: Deassert reset
    dut.Rst_n.value = 1

    # Phase 3: Wait for stabilization
    for _ in range(5):
        await RisingEdge(clk_signal)


async def dpc_reset_sequence(dut, pll_clock, hsclk_period_ns: int = 100):
    """
    DPC-specific reset sequence matching DekatronPC_tb.cpp timing:
    - Rst_n=0 at PLL_CLK==1 (1 hsClk cycle after start)
    - Rst_n=1 at PLL_CLK==SLOW_P*2 (2000 ns later at 1us timescale)
    - Run pulse at PLL_CLK==SLOW_P*4
    - Run release at PLL_CLK==SLOW_P*6

    This mirrors stepVerilog() in DekatronPC_tb.cpp lines 103-115.
    """
    # Start with reset asserted
    dut.Rst_n.value = 0
    dut.Run.value = 0
    dut.Step.value = 0
    if hasattr(dut, "Halt"):
        dut.Halt.value = 0

    await Timer(hsclk_period_ns, units="ns")

    # Hold reset for 20 slow clock cycles (~2000 ns)
    await Timer(hsclk_period_ns * 20, units="ns")

    # Deassert reset
    dut.Rst_n.value = 1

    # Wait 2 more slow cycles then pulse Run
    await Timer(hsclk_period_ns * 20, units="ns")
    dut.Run.value = 1

    await Timer(hsclk_period_ns * 20, units="ns")
    dut.Run.value = 0

    # Wait for system to stabilize
    await Timer(hsclk_period_ns * 40, units="ns")


# ============================================================
# BCD Helper Functions
# ============================================================

def bcd_to_int(bcd_value: int, num_digits: int) -> int:
    """Convert a BCD value to integer.

    Args:
        bcd_value: Packed BCD value (e.g., 0x255 for decimal 255 with 3 digits)
        num_digits: Number of BCD digits (4 bits each)

    Returns:
        Integer value
    """
    result = 0
    for i in range(num_digits):
        digit = (bcd_value >> (4 * i)) & 0xF
        result += digit * (10 ** i)
    return result


def int_to_bcd(value: int, num_digits: int) -> int:
    """Convert an integer to packed BCD.

    Args:
        value: Integer value
        num_digits: Number of BCD digits (4 bits each)

    Returns:
        Packed BCD value
    """
    result = 0
    for i in range(num_digits):
        digit = (value // (10 ** i)) % 10
        result |= (digit & 0xF) << (4 * i)
    return result


def bcd_increment(bcd_value: int, num_digits: int) -> int:
    """Increment a BCD value with proper digit rollover."""
    val = bcd_to_int(bcd_value, num_digits)
    val += 1
    max_val = (10 ** num_digits) - 1
    if val > max_val:
        val = 0
    return int_to_bcd(val, num_digits)


def bcd_decrement(bcd_value: int, num_digits: int) -> int:
    """Decrement a BCD value with proper digit rollover."""
    val = bcd_to_int(bcd_value, num_digits)
    val -= 1
    if val < 0:
        val = (10 ** num_digits) - 1
    return int_to_bcd(val, num_digits)


def oneshot_active(oneshot_value: int) -> bool:
    """Check if a one-hot encoded value has a single active bit."""
    # Count bits set
    return bin(oneshot_value).count("1") == 1


def bcd_digit_to_onehot(bcd_digit: int) -> int:
    """Convert a single BCD digit (0-9) to 10-bit one-hot."""
    if 0 <= bcd_digit <= 9:
        return 1 << bcd_digit
    return 0


def onehot_to_bcd_digit(onehot: int) -> int:
    """Convert 10-bit one-hot back to BCD digit (0-9)."""
    for i in range(10):
        if onehot & (1 << i):
            return i
    return 0


# ============================================================
# BF Program Helpers
# ============================================================

def bf_to_opcodes(bf_program: str) -> list:
    """Convert a Brainfuck program string to a list of opcodes.

    Opcode mapping (from generate_rom.py):
        N=0x00, H=0x01, +=0x02, -=0x03, >=0x04, <=0x05,
        [=0x06, ]=0x07, .=0x08, ,=0x09, 0=0x0A, M=0x0B,
        G=0x0C, P=0x0D, D=0x0E, B=0x0F
        (braces {}=0x06/0x07 for debug ISA)
    """
    symbol_to_opcode = {
        '+': 0x02, '-': 0x03, '>': 0x04, '<': 0x05,
        '[': 0x06, ']': 0x07, '.': 0x08, ',': 0x09,
        # DekatronPC extended:
        '{': 0x06, '}': 0x07,  # Debug ISA loop
        '0': 0x0A,  # Clear current cell
        'M': 0x0B,  # Clear memory lock
        'G': 0x0C,  # Reserved
        'P': 0x0D,  # Reserved
        'D': 0x0E,  # Enter debug ISA
        'B': 0x0F,  # Enter brainfuck ISA
        'N': 0x00, 'H': 0x01,  # NOP, HALT
    }

    opcodes = []
    for ch in bf_program:
        if ch in symbol_to_opcode:
            opcodes.append(symbol_to_opcode[ch])
        elif ch in ' \t\n\r':
            continue  # skip whitespace
        # Other unknown chars are ignored
    return opcodes


# ============================================================
# Register Model Helpers
# ============================================================

def bcd_register_model(num_digits: int, top_value: int = None):
    """Create a simple BCD register reference model.

    Args:
        num_digits: Number of BCD digits
        top_value: If set, limit for rollover (0 means wrap to 0, N-1 means wrap to 0)

    Returns:
        A dict with 'value', 'step_up', 'step_down', 'set' functions
    """
    state = {"value": 0}
    max_val = (10 ** num_digits) - 1
    limit = top_value if top_value else max_val + 1

    def step_up():
        state["value"] += 1
        if state["value"] >= limit:
            state["value"] = 0
        return state["value"]

    def step_down():
        state["value"] -= 1
        if state["value"] < 0:
            state["value"] = limit - 1
        return state["value"]

    def set_value(v):
        state["value"] = v
        return state["value"]

    return {
        "get": lambda: state["value"],
        "get_bcd": lambda: int_to_bcd(state["value"], num_digits),
        "inc": step_up,
        "dec": step_down,
        "set": set_value,
        "zero": lambda: set_value(0),
    }


# ============================================================
# Coverage Helpers
# ============================================================

try:
    from cocotb_coverage.coverage import (
        coverage_db,
        CoverPoint,
        CoverCross,
        CoverCheck,
    )
    HAS_COVERAGE = True
except ImportError:
    HAS_COVERAGE = False
    log.warning("cocotb-coverage not installed. Coverage collection disabled.")


def add_coverage_point(name: str, bins: dict, description: str = ""):
    """Add a cover point if cocotb-coverage is available."""
    if not HAS_COVERAGE:
        return None
    cp = CoverPoint(
        top=None,
        name=name,
        bins=list(bins.values()),
        bins_labels=list(bins.keys()),
        description=description,
    )
    return cp
