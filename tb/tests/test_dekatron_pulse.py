"""
Tests for DekatronPulseSender — the guide-cathode pulse former.

The module is pure combinational logic on top of DekatronPhaseGen
(EXT_PHASES = 0, the default: own phase generator). A count clock cycle
is split into thirds:

    first third   Phase1
    second third  Phase2
    last third    no pulse — the discharge falls onto the next cathode

    StepF (forward):  GuideA = Phase1, GuideB = Phase2
    StepR (backward): GuideA = Phase2, GuideB = Phase1

Ports: hsClk, Clk, Rst_n, StepF, StepR, Phase1_i, Phase2_i -> GuideA, GuideB.
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import Timer, RisingEdge, ReadOnly

HS_NS = 100        # hsClk period (10 MHz)
CLK_NS = 1000      # Clk period (1 MHz)
HS_PER_CLK = CLK_NS // HS_NS


async def clk_gen(dut):
    """Clk shifted by half an hsClk period so its edges never race hsClk."""
    dut.Clk.value = 0
    await Timer(HS_NS // 2, unit="ns")
    while True:
        dut.Clk.value = 1
        await Timer(CLK_NS // 2, unit="ns")
        dut.Clk.value = 0
        await Timer(CLK_NS // 2, unit="ns")


async def setup(dut):
    cocotb.start_soon(Clock(dut.hsClk, HS_NS, unit="ns").start())
    cocotb.start_soon(clk_gen(dut))
    dut.Rst_n.value = 0
    dut.StepF.value = 0
    dut.StepR.value = 0
    dut.Phase1_i.value = 0
    dut.Phase2_i.value = 0
    for _ in range(5):
        await RisingEdge(dut.hsClk)
    dut.Rst_n.value = 1
    # let the phase generator run a couple of count cycles
    for _ in range(2):
        await RisingEdge(dut.Clk)


async def sample_period(dut):
    """
    Sample GuideA/GuideB twice per hsClk period over one Clk period,
    starting right after a Clk rising edge. Returns two lists.
    """
    await RisingEdge(dut.Clk)
    a, b = [], []
    # samples at 1/4, 3/4, 5/4 ... hsClk after the Clk edge: never on an edge
    await Timer(HS_NS // 4, unit="ns")
    for i in range(2 * HS_PER_CLK):
        if i:
            await Timer(HS_NS // 2, unit="ns")
        await ReadOnly()
        a.append(int(dut.GuideA.value))
        b.append(int(dut.GuideB.value))
    return a, b


def first_high(seq):
    return next((i for i, v in enumerate(seq) if v), None)


async def set_step(dut, f, r):
    # change the request away from the Clk edge (mid count cycle is not
    # allowed either, so we change it right after a Clk falling edge and
    # discard the following period)
    await RisingEdge(dut.Clk)
    dut.StepF.value = f
    dut.StepR.value = r
    await RisingEdge(dut.Clk)


@cocotb.test()
async def test_idle_no_pulses(dut):
    """No step request: both guide lines stay low."""
    await setup(dut)
    for _ in range(3):
        a, b = await sample_period(dut)
        assert not any(a), f"GuideA pulsed without a step request: {a}"
        assert not any(b), f"GuideB pulsed without a step request: {b}"


async def check_step(dut, forward):
    lead, lag = ("A", "B") if forward else ("B", "A")
    for _ in range(3):
        a, b = await sample_period(dut)
        seq = {"A": a, "B": b}
        assert any(a) and any(b), f"both guides must pulse: A={a} B={b}"
        assert not any(x and y for x, y in zip(a, b)), \
            f"guides overlap: A={a} B={b}"
        assert first_high(seq[lead]) < first_high(seq[lag]), \
            f"Guide{lead} must come before Guide{lag}: A={a} B={b}"
        # last third: discharge falls onto the main cathode, no pulses
        tail = 2 * HS_PER_CLK // 3 - 1
        assert not any(a[-tail:]) and not any(b[-tail:]), \
            f"guides must be low in the last third: A={a} B={b}"
        # Phase1 is shorter than Phase2 (3 vs 4 hsClk by default)
        assert sum(seq[lead]) < sum(seq[lag]), \
            f"first pulse must be shorter than the second: A={a} B={b}"


@cocotb.test()
async def test_step_forward(dut):
    """StepF: GuideA (Phase1) then GuideB (Phase2), then a quiet third."""
    await setup(dut)
    await set_step(dut, 1, 0)
    await check_step(dut, forward=True)


@cocotb.test()
async def test_step_backward(dut):
    """StepR: GuideB (Phase1) then GuideA (Phase2), then a quiet third."""
    await setup(dut)
    await set_step(dut, 0, 1)
    await check_step(dut, forward=False)


@cocotb.test()
async def test_step_release(dut):
    """Dropping the request stops the pulses from the next count cycle."""
    await setup(dut)
    await set_step(dut, 1, 0)
    a, b = await sample_period(dut)
    assert any(a) and any(b)
    await set_step(dut, 0, 0)
    a, b = await sample_period(dut)
    assert not any(a) and not any(b), f"pulses after release: A={a} B={b}"
