"""DPC test environment.

Wraps the full DekatronPC with clock generation, reset sequencing,
agent configuration, and scoreboard connections.
"""

from env.base_env import BaseEnv

import logging
log = logging.getLogger("cocotb.dpc_env")


class DPCEnv(BaseEnv):
    """Top-level environment for DekatronPC integration tests.

    Provides:
    - Dual clock generation (hsClk 10x + Clk)
    - DPC-specific reset sequence (matching C++ testbench)
    - Scoreboard connections for full-state comparison
    - Agent connections (DekatronCounter agents for IP/AP/Data/Loop)
    """

    def __init__(self, dut, hsclk_period_ns: int = 100):
        super().__init__(dut, hsclk_period_ns)
        self.scoreboard = None
        self.agents = {}

    async def start_clocks(self):
        """Start both hsClk and Clk with 10:1 phase relationship."""
        from cocotb.clock import Clock

        hsclk = Clock(self.dut.hsClk, self.hsclk_period_ns, units="ns")
        cocotb.start_soon(hsclk.start())

        clk = Clock(self.dut.Clk, self.clk_period_ns, units="ns")
        cocotb.start_soon(clk.start(start_high=False))

    async def dpc_reset(self):
        """DPC-specific reset with Run pulse, matching C++ testbench."""
        from cocotb.triggers import Timer, RisingEdge

        self.dut.Rst_n.value = 0
        self.dut.Run.value = 0
        self.dut.Step.value = 0
        if hasattr(self.dut, "EchoMode"):
            self.dut.EchoMode.value = 1

        # Hold reset
        for _ in range(200):
            await RisingEdge(self.dut.hsClk)

        self.dut.Rst_n.value = 1

        # Wait then pulse Run
        for _ in range(200):
            await RisingEdge(self.dut.hsClk)

        self.dut.Run.value = 1
        for _ in range(200):
            await RisingEdge(self.dut.hsClk)
        self.dut.Run.value = 0

        # Stabilize
        for _ in range(400):
            await RisingEdge(self.dut.hsClk)

    async def run_until_halted(self, max_cycles: int = 100000):
        """Run DPC until it reaches HALT state or max_cycles."""
        halted = False
        for _ in range(max_cycles):
            await RisingEdge(self.dut.Clk)
            state_val = self.dut.state.value.integer
            if state_val == 4:  # HALT
                halted = True
                break
        return halted

    async def step_one_instruction(self):
        """Pulse Step to advance one instruction in single-step mode."""
        self.dut.Step.value = 1
        await RisingEdge(self.dut.Clk)
        await RisingEdge(self.dut.Clk)
        self.dut.Step.value = 0
