"""
Tests for the InsnDecoder module.

InsnDecoder: 7-state FSM instruction decoder for the DekatronPC.
States: IDLE(1), FETCH(2), EXEC(3), HALT(4), CIN(5), COUT(6), CIO_ACQ(7)

Key parameters (from parameters.sv):
- INSN_WIDTH=4, DEBUG_ISA=0, BRAINFUCK_ISA=1

The decoder uses casez({InsnMode,Insn}) in FETCH state to decode instructions.
InsnMode is internal: 0=Debug ISA, 1=Brainfuck ISA (default after reset).

IMPORTANT: Inputs must be driven on FallingEdge to avoid race conditions
with the clock edge. A Timer(1) after RisingEdge ensures non-blocking
assignments settle before reading outputs.
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import Timer, RisingEdge, FallingEdge

import logging
log = logging.getLogger(__name__)

# State encoding (from InsnDecoder.sv)
IDLE = 1
FETCH = 2
EXEC = 3
HALT = 4
CIN = 5
COUT = 6
CIO_ACQ = 7

# ISA modes
DEBUG_ISA = 0
BRAINFUCK_ISA = 1

# Opcodes
OP_NOP = 0x0
OP_HALT = 0x1
OP_INC = 0x2
OP_DEC = 0x3
OP_RIGHT = 0x4
OP_LEFT = 0x5
OP_LOOP_OPEN = 0x6
OP_LOOP_CLOSE = 0x7
OP_COUT = 0x8
OP_CIN = 0x9
OP_CLRD = 0xA
OP_CLRA = 0xB
OP_DEBUG = 0xE
OP_BF = 0xF


# ============================================================
# Helper coroutines
# ============================================================

async def drive_and_edge(dut, signal, value):
    """Drive signal on falling edge and wait for rising edge + settle."""
    await FallingEdge(dut.Clk)
    signal.value = value
    await RisingEdge(dut.Clk)
    await Timer(1, unit="ns")


async def reset_dut(dut):
    """Apply reset sequence."""
    dut.Rst_n.value = 0
    await RisingEdge(dut.Clk)
    await Timer(1, unit="ns")
    await RisingEdge(dut.Clk)
    await Timer(1, unit="ns")
    dut.Rst_n.value = 1
    await RisingEdge(dut.Clk)
    await Timer(1, unit="ns")
    await RisingEdge(dut.Clk)
    await Timer(1, unit="ns")


async def initialize_dut(dut):
    """Set all inputs to default inactive values."""
    dut.Halt.value = 0
    dut.Step.value = 0
    dut.Run.value = 0
    dut.Insn.value = 0
    dut.IpLineReady.value = 0
    dut.ApLineReady.value = 0
    dut.DataZero.value = 0
    dut.ApZero.value = 0
    dut.tx_rdy.value = 0
    dut.rx_vld.value = 0
    dut.EchoMode.value = 0


async def pulse_step(dut):
    """Pulse Step=1 for one clock cycle. Sets OneStep flag."""
    await FallingEdge(dut.Clk)
    dut.Step.value = 1
    await RisingEdge(dut.Clk)
    await Timer(1, unit="ns")
    await FallingEdge(dut.Clk)
    dut.Step.value = 0


async def pulse_run(dut):
    """Pulse Run=1 for one clock cycle. Does NOT set OneStep flag."""
    await FallingEdge(dut.Clk)
    dut.Run.value = 1
    await RisingEdge(dut.Clk)
    await Timer(1, unit="ns")
    await FallingEdge(dut.Clk)
    dut.Run.value = 0


async def advance_to_fetch(dut, insn=0, use_step=False):
    """Drive the FSM from HALT through IDLE to FETCH, presenting an instruction.

    Uses Run by default (continuous execution). Use use_step=True for one-step tests.
    """
    dut.Insn.value = insn
    await FallingEdge(dut.Clk)
    dut.IpLineReady.value = 0
    dut.ApLineReady.value = 0
    if use_step:
        await pulse_step(dut)
    else:
        await pulse_run(dut)
    # Now in IDLE; wait one more edge for IDLE→FETCH
    await RisingEdge(dut.Clk)
    await Timer(1, unit="ns")


async def complete_fetch(dut):
    """Signal IpLineReady and wait one cycle to execute the instruction decode."""
    await FallingEdge(dut.Clk)
    dut.IpLineReady.value = 1
    await RisingEdge(dut.Clk)
    await Timer(1, unit="ns")
    await FallingEdge(dut.Clk)
    dut.IpLineReady.value = 0


async def complete_exec(dut, halt_after=False):
    """Complete EXEC phase by signaling ApLineReady."""
    await FallingEdge(dut.Clk)
    if halt_after:
        dut.Halt.value = 1
    dut.ApLineReady.value = 1
    await RisingEdge(dut.Clk)
    await Timer(1, unit="ns")
    await FallingEdge(dut.Clk)
    dut.ApLineReady.value = 0
    if halt_after:
        dut.Halt.value = 0


# ============================================================
# Reset and Initial State Tests
# ============================================================

@cocotb.test()
async def test_reset_state(dut):
    """After reset, state=HALT and IsHalted=1."""
    clock = Clock(dut.Clk, 100, unit="ns")
    cocotb.start_soon(clock.start())
    await initialize_dut(dut)
    await reset_dut(dut)

    assert int(dut.state.value) == HALT, (
        f"After reset, state should be HALT({HALT}), got {int(dut.state.value)}"
    )
    assert int(dut.IsHalted.value) == 1, "After reset, IsHalted should be 1"


@cocotb.test()
async def test_initial_flags_after_reset(dut):
    """After reset, all output requests should be deasserted."""
    clock = Clock(dut.Clk, 100, unit="ns")
    cocotb.start_soon(clock.start())
    await initialize_dut(dut)
    await reset_dut(dut)

    assert int(dut.IpRequest.value) == 0, "IpRequest should be 0 after reset"
    assert int(dut.ApRequest.value) == 0, "ApRequest should be 0 after reset"
    assert int(dut.DataRequest.value) == 0, "DataRequest should be 0 after reset"
    assert int(dut.tx_vld.value) == 0, "tx_vld should be 0 after reset"


# ============================================================
# State Transition Tests
# ============================================================

@cocotb.test()
async def test_step_exits_halt(dut):
    """A Step pulse exits HALT state and enters IDLE."""
    clock = Clock(dut.Clk, 100, unit="ns")
    cocotb.start_soon(clock.start())
    await initialize_dut(dut)
    await reset_dut(dut)

    assert int(dut.state.value) == HALT
    await pulse_step(dut)

    assert int(dut.state.value) == IDLE, (
        f"After Step pulse, state should be IDLE({IDLE}), got {int(dut.state.value)}"
    )


@cocotb.test()
async def test_run_exits_halt(dut):
    """A Run pulse exits HALT state and enters IDLE."""
    clock = Clock(dut.Clk, 100, unit="ns")
    cocotb.start_soon(clock.start())
    await initialize_dut(dut)
    await reset_dut(dut)

    assert int(dut.state.value) == HALT
    await pulse_run(dut)

    assert int(dut.state.value) == IDLE, (
        f"After Run pulse, state should be IDLE({IDLE}), got {int(dut.state.value)}"
    )


@cocotb.test()
async def test_idle_to_fetch(dut):
    """From IDLE, FSM transitions to FETCH on next cycle."""
    clock = Clock(dut.Clk, 100, unit="ns")
    cocotb.start_soon(clock.start())
    await initialize_dut(dut)
    await reset_dut(dut)

    await pulse_run(dut)
    assert int(dut.state.value) == IDLE

    await RisingEdge(dut.Clk)
    await Timer(1, unit="ns")
    assert int(dut.state.value) == FETCH, (
        f"After IDLE, state should be FETCH({FETCH}), got {int(dut.state.value)}"
    )


@cocotb.test()
async def test_halt_in_idle(dut):
    """Halt=1 in IDLE state forces transition to HALT."""
    clock = Clock(dut.Clk, 100, unit="ns")
    cocotb.start_soon(clock.start())
    await initialize_dut(dut)
    await reset_dut(dut)

    await pulse_run(dut)
    assert int(dut.state.value) == IDLE

    # Set Halt now (at falling edge after pulse_run) so next rising edge sees it
    dut.Halt.value = 1
    await RisingEdge(dut.Clk)
    await Timer(1, unit="ns")
    assert int(dut.state.value) == HALT, "Halt=1 in IDLE should transition to HALT"
    assert int(dut.IsHalted.value) == 1


# ============================================================
# Instruction Decode Tests - NOP and HALT
# ============================================================

@cocotb.test()
async def test_nop_instruction(dut):
    """NOP (Insn=0) returns to IDLE (with Run, no OneStep)."""
    clock = Clock(dut.Clk, 100, unit="ns")
    cocotb.start_soon(clock.start())
    await initialize_dut(dut)
    await reset_dut(dut)

    await advance_to_fetch(dut, insn=OP_NOP)
    assert int(dut.state.value) == FETCH

    await complete_fetch(dut)
    # NOP with Run (no OneStep): state → IDLE
    assert int(dut.state.value) == IDLE, (
        f"NOP should transition to IDLE({IDLE}), got {int(dut.state.value)}"
    )


@cocotb.test()
async def test_nop_one_step(dut):
    """NOP in one-step mode returns to HALT."""
    clock = Clock(dut.Clk, 100, unit="ns")
    cocotb.start_soon(clock.start())
    await initialize_dut(dut)
    await reset_dut(dut)

    await advance_to_fetch(dut, insn=OP_NOP, use_step=True)
    await complete_fetch(dut)
    # With OneStep=1, NOP goes to HALT instead of IDLE
    assert int(dut.state.value) == HALT, (
        f"NOP in one-step mode should go to HALT({HALT}), got {int(dut.state.value)}"
    )


@cocotb.test()
async def test_halt_instruction(dut):
    """HALT (Insn=1) sets state=HALT and IsHalted=1."""
    clock = Clock(dut.Clk, 100, unit="ns")
    cocotb.start_soon(clock.start())
    await initialize_dut(dut)
    await reset_dut(dut)

    await advance_to_fetch(dut, insn=OP_HALT)
    await complete_fetch(dut)

    assert int(dut.state.value) == HALT, (
        f"HALT instruction should set state=HALT({HALT}), got {int(dut.state.value)}"
    )
    assert int(dut.IsHalted.value) == 1


# ============================================================
# Instruction Decode Tests - BF ISA Arithmetic
# ============================================================

@cocotb.test()
async def test_bf_increment(dut):
    """+ (Insn=2) in BF ISA → DataRequest=1, ApLineDec=0, state→EXEC."""
    clock = Clock(dut.Clk, 100, unit="ns")
    cocotb.start_soon(clock.start())
    await initialize_dut(dut)
    await reset_dut(dut)

    await advance_to_fetch(dut, insn=OP_INC)
    await complete_fetch(dut)

    assert int(dut.state.value) == EXEC, (
        f"+ should transition to EXEC({EXEC}), got {int(dut.state.value)}"
    )
    assert int(dut.DataRequest.value) == 1, "+ should set DataRequest=1"
    assert int(dut.ApRequest.value) == 0, "+ should clear ApRequest"
    assert int(dut.ApLineDec.value) == 0, "+ should set ApLineDec=0"


@cocotb.test()
async def test_bf_decrement(dut):
    """- (Insn=3) in BF ISA → DataRequest=1, ApLineDec=1, state→EXEC."""
    clock = Clock(dut.Clk, 100, unit="ns")
    cocotb.start_soon(clock.start())
    await initialize_dut(dut)
    await reset_dut(dut)

    await advance_to_fetch(dut, insn=OP_DEC)
    await complete_fetch(dut)

    assert int(dut.state.value) == EXEC, (
        f"- should transition to EXEC({EXEC}), got {int(dut.state.value)}"
    )
    assert int(dut.DataRequest.value) == 1, "- should set DataRequest=1"
    assert int(dut.ApRequest.value) == 0, "- should clear ApRequest"
    assert int(dut.ApLineDec.value) == 1, "- should set ApLineDec=1"


@cocotb.test()
async def test_bf_right(dut):
    """> (Insn=4) in BF ISA → ApRequest=1, ApLineDec=0, state→EXEC."""
    clock = Clock(dut.Clk, 100, unit="ns")
    cocotb.start_soon(clock.start())
    await initialize_dut(dut)
    await reset_dut(dut)

    await advance_to_fetch(dut, insn=OP_RIGHT)
    await complete_fetch(dut)

    assert int(dut.state.value) == EXEC, (
        f"> should transition to EXEC({EXEC}), got {int(dut.state.value)}"
    )
    assert int(dut.ApRequest.value) == 1, "> should set ApRequest=1"
    assert int(dut.DataRequest.value) == 0, "> should clear DataRequest"
    assert int(dut.ApLineDec.value) == 0, "> should set ApLineDec=0"


@cocotb.test()
async def test_bf_left(dut):
    """< (Insn=5) in BF ISA → ApRequest=1, ApLineDec=1, state→EXEC."""
    clock = Clock(dut.Clk, 100, unit="ns")
    cocotb.start_soon(clock.start())
    await initialize_dut(dut)
    await reset_dut(dut)

    await advance_to_fetch(dut, insn=OP_LEFT)
    await complete_fetch(dut)

    assert int(dut.state.value) == EXEC, (
        f"< should transition to EXEC({EXEC}), got {int(dut.state.value)}"
    )
    assert int(dut.ApRequest.value) == 1, "< should set ApRequest=1"
    assert int(dut.DataRequest.value) == 0, "< should clear DataRequest"
    assert int(dut.ApLineDec.value) == 1, "< should set ApLineDec=1"


# ============================================================
# Instruction Decode Tests - Loop Instructions
# ============================================================

@cocotb.test()
async def test_loop_open_data_nonzero(dut):
    """[ (Insn=6) with DataZero=0 → state=EXEC (enter loop body)."""
    clock = Clock(dut.Clk, 100, unit="ns")
    cocotb.start_soon(clock.start())
    await initialize_dut(dut)
    await reset_dut(dut)

    dut.DataZero.value = 0
    await advance_to_fetch(dut, insn=OP_LOOP_OPEN)
    await complete_fetch(dut)

    assert int(dut.state.value) == EXEC, (
        f"[ with DataZero=0 should go to EXEC({EXEC}), got {int(dut.state.value)}"
    )


@cocotb.test()
async def test_loop_open_data_zero(dut):
    """[ (Insn=6) with DataZero=1 → IpRequest=1 (skip loop, stay in FETCH)."""
    clock = Clock(dut.Clk, 100, unit="ns")
    cocotb.start_soon(clock.start())
    await initialize_dut(dut)
    await reset_dut(dut)

    dut.DataZero.value = 1
    await advance_to_fetch(dut, insn=OP_LOOP_OPEN)
    await complete_fetch(dut)

    assert int(dut.state.value) != EXEC, (
        f"[ with DataZero=1 should NOT go to EXEC, got {int(dut.state.value)}"
    )
    assert int(dut.IpRequest.value) == 1, (
        "[ with DataZero=1 should re-assert IpRequest (skip loop)"
    )


@cocotb.test()
async def test_loop_close_data_zero(dut):
    """] (Insn=7) with DataZero=1 → state=EXEC (exit loop)."""
    clock = Clock(dut.Clk, 100, unit="ns")
    cocotb.start_soon(clock.start())
    await initialize_dut(dut)
    await reset_dut(dut)

    dut.DataZero.value = 1
    await advance_to_fetch(dut, insn=OP_LOOP_CLOSE)
    await complete_fetch(dut)

    assert int(dut.state.value) == EXEC, (
        f"] with DataZero=1 should go to EXEC({EXEC}), got {int(dut.state.value)}"
    )


@cocotb.test()
async def test_loop_close_data_nonzero(dut):
    """] (Insn=7) with DataZero=0 → IpRequest=1 (loop back, stay in FETCH)."""
    clock = Clock(dut.Clk, 100, unit="ns")
    cocotb.start_soon(clock.start())
    await initialize_dut(dut)
    await reset_dut(dut)

    dut.DataZero.value = 0
    await advance_to_fetch(dut, insn=OP_LOOP_CLOSE)
    await complete_fetch(dut)

    assert int(dut.state.value) != EXEC, (
        f"] with DataZero=0 should NOT go to EXEC, got {int(dut.state.value)}"
    )
    assert int(dut.IpRequest.value) == 1, (
        "] with DataZero=0 should re-assert IpRequest (loop back)"
    )


@cocotb.test()
async def test_loop_open_debug_isa_apzero(dut):
    """In Debug ISA, [ uses ApZero (not DataZero) for loop decision."""
    clock = Clock(dut.Clk, 100, unit="ns")
    cocotb.start_soon(clock.start())
    await initialize_dut(dut)
    await reset_dut(dut)

    # Switch to Debug ISA first
    await advance_to_fetch(dut, insn=OP_DEBUG)
    await complete_fetch(dut)
    assert int(dut.state.value) == EXEC
    await complete_exec(dut)
    assert int(dut.state.value) == FETCH

    # Now in Debug ISA. ApZero=1, DataZero=0 → [ should skip (uses ApZero)
    dut.ApZero.value = 1
    dut.DataZero.value = 0
    await advance_to_fetch(dut, insn=OP_LOOP_OPEN)
    await complete_fetch(dut)

    assert int(dut.state.value) != EXEC, (
        f"[ in Debug ISA with ApZero=1 should skip, got state={int(dut.state.value)}"
    )


# ============================================================
# Instruction Decode Tests - CLRD and CLRA
# ============================================================

@cocotb.test()
async def test_clrd_instruction(dut):
    """CLRD (Insn=0xA) → DataRequest=1, ApLineZero=1, ApRequest=0, state=EXEC."""
    clock = Clock(dut.Clk, 100, unit="ns")
    cocotb.start_soon(clock.start())
    await initialize_dut(dut)
    await reset_dut(dut)

    await advance_to_fetch(dut, insn=OP_CLRD)
    await complete_fetch(dut)

    assert int(dut.state.value) == EXEC, (
        f"CLRD should go to EXEC({EXEC}), got {int(dut.state.value)}"
    )
    assert int(dut.DataRequest.value) == 1, "CLRD should set DataRequest=1"
    assert int(dut.ApLineZero.value) == 1, "CLRD should set ApLineZero=1"
    assert int(dut.ApRequest.value) == 0, "CLRD should clear ApRequest"


@cocotb.test()
async def test_clra_instruction_debug_isa(dut):
    """CLRA (Insn=0xB) in Debug ISA → ApRequest=1, ApLineZero=1, DataRequest=0."""
    clock = Clock(dut.Clk, 100, unit="ns")
    cocotb.start_soon(clock.start())
    await initialize_dut(dut)
    await reset_dut(dut)

    # Switch to Debug ISA first
    await advance_to_fetch(dut, insn=OP_DEBUG)
    await complete_fetch(dut)
    await complete_exec(dut)
    assert int(dut.state.value) == FETCH

    # Now test CLRA in Debug ISA
    await advance_to_fetch(dut, insn=OP_CLRA)
    await complete_fetch(dut)

    assert int(dut.state.value) == EXEC, (
        f"CLRA in Debug ISA should go to EXEC({EXEC}), got {int(dut.state.value)}"
    )
    assert int(dut.ApRequest.value) == 1, "CLRA should set ApRequest=1"
    assert int(dut.ApLineZero.value) == 1, "CLRA should set ApLineZero=1"
    assert int(dut.DataRequest.value) == 0, "CLRA should clear DataRequest"


# ============================================================
# ISA Mode Switch Tests
# ============================================================

@cocotb.test()
async def test_debug_mode_switch(dut):
    """D (Insn=0xE) switches ISA mode to DEBUG."""
    clock = Clock(dut.Clk, 100, unit="ns")
    cocotb.start_soon(clock.start())
    await initialize_dut(dut)
    await reset_dut(dut)

    # Switch to Debug ISA
    await advance_to_fetch(dut, insn=OP_DEBUG)
    await complete_fetch(dut)
    assert int(dut.state.value) == EXEC
    await complete_exec(dut)
    assert int(dut.state.value) == FETCH

    # Now in Debug ISA. + (Insn=2) should go to default case → EXEC without DataRequest.
    await advance_to_fetch(dut, insn=OP_INC)
    await complete_fetch(dut)

    assert int(dut.state.value) == EXEC
    assert int(dut.DataRequest.value) == 0, (
        "Insn=2 in Debug ISA should NOT set DataRequest (not a BF +)"
    )


@cocotb.test()
async def test_bf_mode_switch(dut):
    """B (Insn=0xF) switches ISA mode to BRAINFUCK."""
    clock = Clock(dut.Clk, 100, unit="ns")
    cocotb.start_soon(clock.start())
    await initialize_dut(dut)
    await reset_dut(dut)

    # Switch to Debug first, then back to BF
    await advance_to_fetch(dut, insn=OP_DEBUG)
    await complete_fetch(dut)
    await complete_exec(dut)
    assert int(dut.state.value) == FETCH

    # In Debug ISA, switch back to BF
    await advance_to_fetch(dut, insn=OP_BF)
    await complete_fetch(dut)
    await complete_exec(dut)
    assert int(dut.state.value) == FETCH

    # Now back in BF ISA. + (Insn=2) should set DataRequest=1.
    await advance_to_fetch(dut, insn=OP_INC)
    await complete_fetch(dut)

    assert int(dut.state.value) == EXEC
    assert int(dut.DataRequest.value) == 1, (
        "Insn=2 in BF ISA should set DataRequest=1 (+ instruction)"
    )


# ============================================================
# EXEC Phase Tests
# ============================================================

@cocotb.test()
async def test_exec_to_fetch(dut):
    """After ApLineReady in EXEC, FSM returns to FETCH (continuous mode)."""
    clock = Clock(dut.Clk, 100, unit="ns")
    cocotb.start_soon(clock.start())
    await initialize_dut(dut)
    await reset_dut(dut)

    await advance_to_fetch(dut, insn=OP_INC)
    await complete_fetch(dut)
    assert int(dut.state.value) == EXEC

    await complete_exec(dut)
    assert int(dut.state.value) == FETCH, (
        f"After EXEC, state should be FETCH({FETCH}), got {int(dut.state.value)}"
    )


@cocotb.test()
async def test_exec_to_halt(dut):
    """Halt=1 during EXEC transitions to HALT."""
    clock = Clock(dut.Clk, 100, unit="ns")
    cocotb.start_soon(clock.start())
    await initialize_dut(dut)
    await reset_dut(dut)

    await advance_to_fetch(dut, insn=OP_INC)
    await complete_fetch(dut)
    assert int(dut.state.value) == EXEC

    await complete_exec(dut, halt_after=True)
    assert int(dut.state.value) == HALT, (
        f"Halt during EXEC should go to HALT({HALT}), got {int(dut.state.value)}"
    )


@cocotb.test()
async def test_exec_to_halt_one_step(dut):
    """OneStep=1 causes EXEC→HALT after instruction completes."""
    clock = Clock(dut.Clk, 100, unit="ns")
    cocotb.start_soon(clock.start())
    await initialize_dut(dut)
    await reset_dut(dut)

    # Use Step (which sets OneStep) instead of Run
    await advance_to_fetch(dut, insn=OP_INC, use_step=True)
    await complete_fetch(dut)
    assert int(dut.state.value) == EXEC

    await complete_exec(dut)
    assert int(dut.state.value) == HALT, (
        f"OneStep should cause EXEC→HALT({HALT}), got {int(dut.state.value)}"
    )


# ============================================================
# CIN/COUT Tests
# ============================================================

@cocotb.test()
async def test_cout_instruction(dut):
    """. (Insn=8) in BF ISA → tx_vld=1, state=COUT."""
    clock = Clock(dut.Clk, 100, unit="ns")
    cocotb.start_soon(clock.start())
    await initialize_dut(dut)
    await reset_dut(dut)

    await advance_to_fetch(dut, insn=OP_COUT)
    await complete_fetch(dut)

    assert int(dut.state.value) == COUT, (
        f". should go to COUT({COUT}), got {int(dut.state.value)}"
    )
    assert int(dut.tx_vld.value) == 1, ". should set tx_vld=1"


@cocotb.test()
async def test_cout_to_cio_acq(dut):
    """After tx_rdy in COUT, FSM goes to CIO_ACQ and clears tx_vld."""
    clock = Clock(dut.Clk, 100, unit="ns")
    cocotb.start_soon(clock.start())
    await initialize_dut(dut)
    await reset_dut(dut)

    await advance_to_fetch(dut, insn=OP_COUT)
    await complete_fetch(dut)
    assert int(dut.state.value) == COUT

    await FallingEdge(dut.Clk)
    dut.tx_rdy.value = 1
    await RisingEdge(dut.Clk)
    await Timer(1, unit="ns")
    await FallingEdge(dut.Clk)
    dut.tx_rdy.value = 0

    assert int(dut.state.value) == CIO_ACQ, (
        f"After tx_rdy, state should be CIO_ACQ({CIO_ACQ}), got {int(dut.state.value)}"
    )
    assert int(dut.tx_vld.value) == 0, "tx_vld should be cleared after tx_rdy"


@cocotb.test()
async def test_cin_instruction(dut):
    """, (Insn=9) in BF ISA → state=CIN."""
    clock = Clock(dut.Clk, 100, unit="ns")
    cocotb.start_soon(clock.start())
    await initialize_dut(dut)
    await reset_dut(dut)

    await advance_to_fetch(dut, insn=OP_CIN)
    await complete_fetch(dut)

    assert int(dut.state.value) == CIN, (
        f", should go to CIN({CIN}), got {int(dut.state.value)}"
    )


@cocotb.test()
async def test_cin_to_cio_acq(dut):
    """After rx_vld in CIN, FSM goes to CIO_ACQ with DataRequest and ApLineCin."""
    clock = Clock(dut.Clk, 100, unit="ns")
    cocotb.start_soon(clock.start())
    await initialize_dut(dut)
    await reset_dut(dut)

    await advance_to_fetch(dut, insn=OP_CIN)
    await complete_fetch(dut)
    assert int(dut.state.value) == CIN

    await FallingEdge(dut.Clk)
    dut.rx_vld.value = 1
    await RisingEdge(dut.Clk)
    await Timer(1, unit="ns")
    await FallingEdge(dut.Clk)
    dut.rx_vld.value = 0

    assert int(dut.state.value) == CIO_ACQ, (
        f"After rx_vld, state should be CIO_ACQ({CIO_ACQ}), got {int(dut.state.value)}"
    )
    assert int(dut.DataRequest.value) == 1, "CIN should set DataRequest=1"
    assert int(dut.ApLineCin.value) == 1, "CIN should set ApLineCin=1"


# ============================================================
# Echo Mode Tests
# ============================================================

@cocotb.test()
async def test_echo_mode_cin(dut):
    """EchoMode=1 during CIN sets Echo flag, causing COUT after CIO_ACQ."""
    clock = Clock(dut.Clk, 100, unit="ns")
    cocotb.start_soon(clock.start())
    await initialize_dut(dut)
    await reset_dut(dut)

    dut.EchoMode.value = 1

    # Start CIN instruction
    await advance_to_fetch(dut, insn=OP_CIN)
    await complete_fetch(dut)
    assert int(dut.state.value) == CIN

    # rx_vld triggers CIN → CIO_ACQ with Echo set
    await FallingEdge(dut.Clk)
    dut.rx_vld.value = 1
    await RisingEdge(dut.Clk)
    await Timer(1, unit="ns")
    await FallingEdge(dut.Clk)
    dut.rx_vld.value = 0
    assert int(dut.state.value) == CIO_ACQ

    # Complete CIO_ACQ: ApLineReady & tx_rdy
    # Echo flag is set, so next state should be COUT with tx_vld
    await FallingEdge(dut.Clk)
    dut.ApLineReady.value = 1
    dut.tx_rdy.value = 1
    await RisingEdge(dut.Clk)
    await Timer(1, unit="ns")
    await FallingEdge(dut.Clk)
    dut.ApLineReady.value = 0
    dut.tx_rdy.value = 0

    assert int(dut.state.value) == COUT, (
        f"With EchoMode, should go to COUT({COUT}) after CIO_ACQ, got {int(dut.state.value)}"
    )
    assert int(dut.tx_vld.value) == 1, "Echo should set tx_vld=1 for echo output"


@cocotb.test()
async def test_no_echo_without_echomode(dut):
    """Without EchoMode, CIN does not produce echo COUT."""
    clock = Clock(dut.Clk, 100, unit="ns")
    cocotb.start_soon(clock.start())
    await initialize_dut(dut)
    await reset_dut(dut)

    dut.EchoMode.value = 0

    await advance_to_fetch(dut, insn=OP_CIN)
    await complete_fetch(dut)

    await FallingEdge(dut.Clk)
    dut.rx_vld.value = 1
    await RisingEdge(dut.Clk)
    await Timer(1, unit="ns")
    await FallingEdge(dut.Clk)
    dut.rx_vld.value = 0
    assert int(dut.state.value) == CIO_ACQ

    # Complete CIO_ACQ without echo
    await FallingEdge(dut.Clk)
    dut.ApLineReady.value = 1
    dut.tx_rdy.value = 1
    await RisingEdge(dut.Clk)
    await Timer(1, unit="ns")
    await FallingEdge(dut.Clk)
    dut.ApLineReady.value = 0
    dut.tx_rdy.value = 0

    assert int(dut.state.value) == EXEC, (
        f"Without EchoMode, should go to EXEC({EXEC}) after CIN CIO_ACQ, got {int(dut.state.value)}"
    )


# ============================================================
# Multi-Instruction Sequence Tests
# ============================================================

@cocotb.test()
async def test_instruction_sequence(dut):
    """Run a sequence: +, >, +, < through the decoder."""
    clock = Clock(dut.Clk, 100, unit="ns")
    cocotb.start_soon(clock.start())
    await initialize_dut(dut)
    await reset_dut(dut)

    # Instruction 1: + (Insn=2)
    await advance_to_fetch(dut, insn=OP_INC)
    await complete_fetch(dut)
    assert int(dut.state.value) == EXEC
    assert int(dut.DataRequest.value) == 1
    assert int(dut.ApLineDec.value) == 0
    await complete_exec(dut)
    assert int(dut.state.value) == FETCH

    # Instruction 2: > (Insn=4)
    await advance_to_fetch(dut, insn=OP_RIGHT)
    await complete_fetch(dut)
    assert int(dut.state.value) == EXEC
    assert int(dut.ApRequest.value) == 1
    assert int(dut.ApLineDec.value) == 0
    await complete_exec(dut)
    assert int(dut.state.value) == FETCH

    # Instruction 3: + (Insn=2)
    await advance_to_fetch(dut, insn=OP_INC)
    await complete_fetch(dut)
    assert int(dut.state.value) == EXEC
    assert int(dut.DataRequest.value) == 1
    assert int(dut.ApLineDec.value) == 0
    await complete_exec(dut)
    assert int(dut.state.value) == FETCH

    # Instruction 4: < (Insn=5)
    await advance_to_fetch(dut, insn=OP_LEFT)
    await complete_fetch(dut)
    assert int(dut.state.value) == EXEC
    assert int(dut.ApRequest.value) == 1
    assert int(dut.ApLineDec.value) == 1
    await complete_exec(dut)
    assert int(dut.state.value) == FETCH


@cocotb.test()
async def test_halt_and_restart(dut):
    """HALT instruction stops the machine; Step restarts it."""
    clock = Clock(dut.Clk, 100, unit="ns")
    cocotb.start_soon(clock.start())
    await initialize_dut(dut)
    await reset_dut(dut)

    # Run one instruction
    await advance_to_fetch(dut, insn=OP_INC)
    await complete_fetch(dut)
    await complete_exec(dut)
    assert int(dut.state.value) == FETCH

    # Issue HALT
    await advance_to_fetch(dut, insn=OP_HALT)
    await complete_fetch(dut)
    assert int(dut.state.value) == HALT
    assert int(dut.IsHalted.value) == 1

    # Step to resume
    await pulse_step(dut)
    assert int(dut.state.value) == IDLE


# ============================================================
# LoopValZero Logic Tests
# ============================================================

@cocotb.test()
async def test_loop_val_zero_bf_isa(dut):
    """In BF ISA, LoopValZero mirrors DataZero."""
    clock = Clock(dut.Clk, 100, unit="ns")
    cocotb.start_soon(clock.start())
    await initialize_dut(dut)
    await reset_dut(dut)

    # Default after reset is BF ISA
    dut.DataZero.value = 1
    dut.ApZero.value = 0
    await Timer(2, unit="ns")

    assert int(dut.LoopValZero.value) == 1, (
        f"In BF ISA, LoopValZero should follow DataZero(1), got {int(dut.LoopValZero.value)}"
    )

    dut.DataZero.value = 0
    dut.ApZero.value = 1
    await Timer(2, unit="ns")

    assert int(dut.LoopValZero.value) == 0, (
        f"In BF ISA, LoopValZero should follow DataZero(0), got {int(dut.LoopValZero.value)}"
    )


@cocotb.test()
async def test_loop_val_zero_debug_isa(dut):
    """In Debug ISA, LoopValZero mirrors ApZero."""
    clock = Clock(dut.Clk, 100, unit="ns")
    cocotb.start_soon(clock.start())
    await initialize_dut(dut)
    await reset_dut(dut)

    # Switch to Debug ISA
    await advance_to_fetch(dut, insn=OP_DEBUG)
    await complete_fetch(dut)
    await complete_exec(dut)
    assert int(dut.state.value) == FETCH

    # Now in Debug ISA
    dut.ApZero.value = 1
    dut.DataZero.value = 0
    await Timer(2, unit="ns")

    assert int(dut.LoopValZero.value) == 1, (
        f"In Debug ISA, LoopValZero should follow ApZero(1), got {int(dut.LoopValZero.value)}"
    )

    dut.ApZero.value = 0
    dut.DataZero.value = 1
    await Timer(2, unit="ns")

    assert int(dut.LoopValZero.value) == 0, (
        f"In Debug ISA, LoopValZero should follow ApZero(0), got {int(dut.LoopValZero.value)}"
    )
