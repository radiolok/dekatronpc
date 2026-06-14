"""Base environment for all UVM-inspired DPC tests.

Provides common infrastructure shared across all test environments:
- Clock generation
- Reset sequences  
- Standard BCD utilities
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import Timer, RisingEdge, FallingEdge, ClockCycles

import logging
log = logging.getLogger("cocotb.env")


class BaseEnv:
    """Base test environment providing clock and reset infrastructure."""

    def __init__(self, dut, hsclk_period_ns: int = 100):
        self.dut = dut
        self.hsclk_period_ns = hsclk_period_ns
        self.clk_period_ns = hsclk_period_ns * 10  # 10:1 ratio

    async def start_clocks(self):
        """Start hsClk with correct frequency."""
        if hasattr(self.dut, "hsClk"):
            hsclk = Clock(self.dut.hsClk, self.hsclk_period_ns, units="ns")
            cocotb.start_soon(hsclk.start())

        if hasattr(self.dut, "Clk"):
            clk = Clock(self.dut.Clk, self.clk_period_ns, units="ns")
            cocotb.start_soon(clk.start(start_high=False))

    async def reset(self, cycles: int = 10):
        """Standard async reset using hsClk if available, else Clk."""
        clk = getattr(self.dut, "hsClk", None) or getattr(self.dut, "Clk", None)
        if clk is None:
            raise RuntimeError("No clock signal found on DUT")

        self.dut.Rst_n.value = 0
        for _ in range(cycles):
            await RisingEdge(clk)
        self.dut.Rst_n.value = 1
        for _ in range(5):
            await RisingEdge(clk)

    async def wait_cycles(self, n: int, clk_name: str = "Clk"):
        """Wait for N cycles of the named clock signal."""
        clk = getattr(self.dut, clk_name, None)
        if clk is None:
            clk = getattr(self.dut, "hsClk", None)
        for _ in range(n):
            await RisingEdge(clk)
