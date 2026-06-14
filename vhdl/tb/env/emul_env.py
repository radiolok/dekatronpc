"""Emulator test environment.

Wraps the full Emulator top-level module with display and keyboard agents.
"""

from env.base_env import BaseEnv

import logging
log = logging.getLogger("cocotb.emul_env")


class EmulEnv(BaseEnv):
    """Top-level environment for Emulator integration tests."""

    def __init__(self, dut, hsclk_period_ns: int = 100):
        super().__init__(dut, hsclk_period_ns)

    async def start_clocks(self):
        """Emulator uses FPGA_CLK_50 (50 MHz)."""
        from cocotb.clock import Clock
        clk = Clock(getattr(self.dut, "FPGA_CLK_50", self.dut.hsClk),
                     self.hsclk_period_ns, units="ns")
        cocotb.start_soon(clk.start())
