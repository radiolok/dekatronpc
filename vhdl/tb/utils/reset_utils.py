"""Standard reset sequences for DPC modules.

Based on the timing in DekatronPC_tb.cpp stepVerilog() function (lines 101-151),
which sets the authoritative reset timing for all DPC tests.
"""

from cocotb.triggers import Timer, RisingEdge


async def standard_reset(dut, clk_signal, cycles: int = 10):
    """
    Simple async reset: assert Rst_n low, wait N clock cycles, deassert.

    Args:
        dut: Device under test
        clk_signal: Clock signal handle (e.g., dut.hsClk or dut.Clk)
        cycles: Number of clock cycles to hold reset low (after first edge)
    """
    # Assert async reset
    dut.Rst_n.value = 0

    # Wait for a few clock cycles
    for _ in range(cycles):
        await RisingEdge(clk_signal)

    # Deassert reset
    dut.Rst_n.value = 1

    # Wait for stabilization
    for _ in range(5):
        await RisingEdge(clk_signal)


async def dpc_reset_sequence(dut, hsclk_period_ns: int = 100):
    """
    DPC-specific full reset sequence matching DekatronPC_tb.cpp timing.

    This mirrors stepVerilog() in DekatronPC_tb.cpp lines 103-115:
      - PLL_CLK==1: Rst_n=0
      - PLL_CLK==SLOW_P*2: Rst_n=1
      - PLL_CLK==SLOW_P*4: Run=1
      - PLL_CLK==SLOW_P*6: Run=0

    After reset, the DPC will be in HALT state. Tests must pulse
    Run or Step to start execution.

    Args:
        dut: DPC top-level module (must have Rst_n, hsClk, Clk, Run, Step, Halt)
        hsclk_period_ns: hsClk period in ns (default 100 for 10 MHz)
    """
    # Initialize control signals
    dut.Rst_n.value = 0
    if hasattr(dut, "Run"):
        dut.Run.value = 0
    if hasattr(dut, "Step"):
        dut.Step.value = 0
    if hasattr(dut, "Halt"):
        dut.Halt.value = 0

    # PLL_CLK==1 timing: hold reset for 1 hsClk before starting
    await Timer(hsclk_period_ns, units="ns")

    # PLL_CLK up to SLOW_P*2: hold reset for ~20 slow cycles (20 us)
    await Timer(hsclk_period_ns * 200, units="ns")

    # Deassert reset (PLL_CLK == SLOW_P*2)
    dut.Rst_n.value = 1

    # PLL_CLK up to SLOW_P*4: wait 2 more slow cycles
    await Timer(hsclk_period_ns * 200, units="ns")

    # Pulse Run (PLL_CLK == SLOW_P*4 to SLOW_P*6)
    if hasattr(dut, "Run"):
        dut.Run.value = 1
    await Timer(hsclk_period_ns * 200, units="ns")

    if hasattr(dut, "Run"):
        dut.Run.value = 0

    # Wait for system to stabilize (up to SLOW_P*10)
    await Timer(hsclk_period_ns * 400, units="ns")


async def dekatron_reset_sequence(dut, clk, hsclk, cycles: int = 10):
    """
    Dekatron subsystem reset: assert Rst_n, wait for both clocks
    to stabilize, then deassert.

    Args:
        dut: Dekatron module
        clk: Slow clock signal (1 MHz)
        hsclk: Fast clock signal (10 MHz)
        cycles: Number of slow clock cycles to hold reset
    """
    dut.Rst_n.value = 0

    for _ in range(cycles):
        await RisingEdge(clk)

    dut.Rst_n.value = 1

    for _ in range(5):
        await RisingEdge(clk)
