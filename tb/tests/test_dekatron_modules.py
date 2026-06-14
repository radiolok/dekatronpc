"""
Tests for combinatorial Dekatron modules: BcdToBin, BinToBcd, DekatronWriteAmp.

Each test guards against the current TOPLEVEL via signal introspection
so that the module can be shared across multiple Makefile targets.
"""

import cocotb
from cocotb.triggers import Timer

import random
import logging
log = logging.getLogger(__name__)


def _is_bcd_to_bin(dut):
    return hasattr(dut, "Out") and not hasattr(dut, "En") and len(dut.In) == 4

def _is_bin_to_bcd(dut):
    return hasattr(dut, "Out") and not hasattr(dut, "En") and len(dut.In) == 10

def _is_write_amp(dut):
    return hasattr(dut, "En")


# ============================================================
# BcdToBin Tests
# ============================================================

@cocotb.test()
async def test_bcd_to_bin_all_valid(dut):
    """BcdToBin: all 10 valid BCD values (0-9) → correct one-hot output."""
    if not _is_bcd_to_bin(dut):
        return

    for digit in range(10):
        dut.In.value = digit
        await Timer(1, unit="ns")
        expected = 1 << digit
        actual = int(dut.Out.value)
        assert actual == expected, (
            f"BcdToBin: In={digit}, expected Out=0b{expected:010b}, got 0b{actual:010b}"
        )


@cocotb.test()
async def test_bcd_to_bin_invalid_inputs(dut):
    """BcdToBin: invalid BCD values (10-15) → Out=0."""
    if not _is_bcd_to_bin(dut):
        return

    for digit in range(10, 16):
        dut.In.value = digit
        await Timer(1, unit="ns")
        actual = int(dut.Out.value)
        assert actual == 0, (
            f"BcdToBin: In={digit} (invalid), expected Out=0, got 0b{actual:010b}"
        )


# ============================================================
# BinToBcd Tests
# ============================================================

@cocotb.test()
async def test_bin_to_bcd_all_positions(dut):
    """BinToBcd: all 10 one-hot positions → correct BCD digit."""
    if not _is_bin_to_bcd(dut):
        return

    for pos in range(10):
        onehot = 1 << pos
        dut.In.value = onehot
        await Timer(1, unit="ns")
        actual = int(dut.Out.value)
        assert actual == pos, (
            f"BinToBcd: In=0b{onehot:010b}, expected Out={pos}, got {actual}"
        )


@cocotb.test()
async def test_bin_to_bcd_zero_input(dut):
    """BinToBcd: In=0 → Out=0 (no position active)."""
    if not _is_bin_to_bcd(dut):
        return

    dut.In.value = 0
    await Timer(1, unit="ns")
    actual = int(dut.Out.value)
    assert actual == 0, f"BinToBcd: In=0, expected Out=0, got {actual}"


@cocotb.test()
async def test_bin_to_bcd_multi_bit_input(dut):
    """BinToBcd: multiple bits set in In → OR-based BCD output."""
    if not _is_bin_to_bcd(dut):
        return

    # Test a few multi-bit combinations to verify OR-gate logic
    test_cases = [
        # (In value as int, expected Out)
        (0b0000000011, 1),  # In[0]=1, In[1]=1 → Out[0]=1 (from In[1]), Out[3:1]=0
        (0b0000000101, 1),  # In[0]=1, In[2]=1 → Out[1]=1 (from In[2])
        (0b0000001010, 2),  # In[1]=1, In[3]=1 → Out[0]=1, Out[1]=1 → 0b0011 = 3? No...
        # Let me compute: In[1]→Out[0], In[3]→Out[0]+Out[1]
        # So Out[0]=In[1]|In[3]=1, Out[1]=In[2]|In[3]=1, Out[2]=0, Out[3]=0 → 0b0011 = 3
        (0b0010000010, 3),  # In[1]=1 → Out[0], In[5]=1 → Out[0]+Out[2] → Out=0b0101=5
        # In[1]→Out[0], In[5]→Out[0]|Out[2]|... → Out[0]=1, Out[2]=1 → 5
        (0b0100001000, 4),  # In[3]→Out[0]+Out[1]=3, In[6]→Out[1]+Out[2]=6 → Out=0b0111=7
        # Actually In[3]→Out[0]=1,Out[1]=1; In[6]→Out[1]=1,Out[2]=1 → Out=0b0111=7
    ]

    # Let me recompute more carefully:
    # Out[0] = In[1] | In[3] | In[5] | In[7] | In[9]
    # Out[1] = In[2] | In[3] | In[6] | In[7]
    # Out[2] = In[4] | In[5] | In[6] | In[7]
    # Out[3] = In[8] | In[9]

    recomputed = [
        (0b0000000011, 0b0001),  # In[0]+In[1]: Out[0]=In[1]=1 → 1
        (0b0000000101, 0b0010),  # In[0]+In[2]: Out[1]=In[2]=1 → 2
        (0b0000001010, 0b0011),  # In[1]+In[3]: Out[0]=In[1]|In[3]=1, Out[1]=In[3]=1 → 3
        (0b0000100010, 0b0101),  # In[1]+In[5]: Out[0]=In[1]|In[5]=1, Out[2]=In[5]=1 → 5
        (0b1100000000, 0b1001),  # In[8]+In[9]: Out[3]=In[8]|In[9]=1, Out[0]=In[9]=1 → 9
    ]

    for in_val, expected in recomputed:
        dut.In.value = in_val
        await Timer(1, unit="ns")
        actual = int(dut.Out.value)
        assert actual == expected, (
            f"BinToBcd multi-bit: In=0b{in_val:010b}, expected Out={expected}, got {actual}"
        )


# ============================================================
# DekatronWriteAmp Tests
# ============================================================

@cocotb.test()
async def test_write_amp_disabled(dut):
    """DekatronWriteAmp: En=0 → Out_n = ~10'b0 = all 1's."""
    if not _is_write_amp(dut):
        return

    dut.En.value = 0
    dut.In.value = 0
    await Timer(1, unit="ns")
    assert int(dut.Out_n.value) == 0x3FF, (
        f"WriteAmp En=0: expected Out_n=0x3FF, got {int(dut.Out_n.value):#x}"
    )

    # Output should be all 1's regardless of In when En=0
    for val in (0x155, 0x2AA, 0x3FF, 0x000):
        dut.In.value = val
        await Timer(1, unit="ns")
        assert int(dut.Out_n.value) == 0x3FF, (
            f"WriteAmp En=0 In={val:#x}: expected Out_n=0x3FF, got {int(dut.Out_n.value):#x}"
        )


@cocotb.test()
async def test_write_amp_enabled(dut):
    """DekatronWriteAmp: En=1 → Out_n = ~In."""
    if not _is_write_amp(dut):
        return

    dut.En.value = 1

    for val in range(0, 1024, 73):
        dut.In.value = val
        await Timer(1, unit="ns")
        expected = (~val) & 0x3FF
        actual = int(dut.Out_n.value)
        assert actual == expected, (
            f"WriteAmp En=1 In={val:#x}: expected Out_n={expected:#x}, got {actual:#x}"
        )


@cocotb.test()
async def test_write_amp_random(dut):
    """DekatronWriteAmp: random 10-bit values, both En states."""
    if not _is_write_amp(dut):
        return

    random.seed(123)
    for _ in range(100):
        val = random.randint(0, 1023)
        en = random.choice([0, 1])

        dut.In.value = val
        dut.En.value = en
        await Timer(1, unit="ns")

        expected = (~val if en else 0) & 0x3FF
        actual = int(dut.Out_n.value)
        assert actual == expected, (
            f"WriteAmp En={en} In={val:#x}: expected Out_n={expected:#x}, got {actual:#x}"
        )


@cocotb.test()
async def test_write_amp_toggle(dut):
    """DekatronWriteAmp: toggle En while holding In constant."""
    if not _is_write_amp(dut):
        return

    dut.In.value = 0x2AA  # alternating pattern
    dut.En.value = 0
    await Timer(1, unit="ns")
    assert int(dut.Out_n.value) == 0x3FF

    dut.En.value = 1
    await Timer(1, unit="ns")
    assert int(dut.Out_n.value) == (~0x2AA) & 0x3FF

    dut.En.value = 0
    await Timer(1, unit="ns")
    assert int(dut.Out_n.value) == 0x3FF
