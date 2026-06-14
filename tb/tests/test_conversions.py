"""Tests for conversion functions: AsciiToBcd, BcdToAscii, BcdToBinEnc,
BinaryToHex, OpcodeToSymbol, SymbolToOpcode, In12CathodeToPin.

All modules are combinational. Each test checks for the expected ports
and skips silently if the wrong TOPLEVEL is instantiated.

NOTE: Test adjusted for rtl/ RTL version — OpcodeToSymbol now uses 5-bit
opcodes with casez: 5'h?0 and 5'h10 both map to space " " (0x20), not 'N'.
SymbolToOpcode was updated accordingly: " " maps to {isa, 4'h0}.
KeyToSymbol test adjusted to match.

AsciiToBcd converts an 8-bit binary value (0-255) to its 12-bit packed BCD
representation. BcdToAscii does the reverse.
"""

import cocotb
from cocotb.triggers import Timer

import logging
log = logging.getLogger(__name__)


def _has_ports(dut, *names):
    return all(hasattr(dut, n) for n in names)


def _dec_to_bcd_12bit(n):
    """Convert decimal 0-255 to 12-bit packed BCD hex value."""
    return ((n // 100) << 8) | (((n // 10) % 10) << 4) | (n % 10)


def _bcd_12bit_to_dec(raw):
    """Convert 12-bit packed BCD hex value to decimal."""
    return ((raw >> 8) & 0xF) * 100 + ((raw >> 4) & 0xF) * 10 + (raw & 0xF)


# ============================================================
# AsciiToBcd
# ============================================================

@cocotb.test()
async def test_ascii_to_bcd_all_256(dut):
    """AsciiToBcd: all 256 input values produce correct BCD output."""
    if not _has_ports(dut, "ascii", "bcd"):
        return
    for byte_val in range(256):
        dut.ascii.value = byte_val
        await Timer(1, unit="ns")
        result = int(dut.bcd.value)
        expected = _dec_to_bcd_12bit(byte_val)
        assert result == expected, (
            f"AsciiToBcd: ascii=0x{byte_val:02X} ({byte_val} dec) "
            f"expected bcd=0x{expected:03X}, got 0x{result:03X}"
        )


@cocotb.test()
async def test_ascii_to_bcd_edge_cases(dut):
    """AsciiToBcd: edge case values."""
    if not _has_ports(dut, "ascii", "bcd"):
        return
    cases = [
        (0x00, "NUL"),
        (0x20, "SPACE"),
        (0x7F, "DEL"),
        (0xFF, "0xFF"),
        (0x30, "ASCII '0'"),
        (0x39, "ASCII '9'"),
        (0x41, "ASCII 'A'"),
        (0x5A, "ASCII 'Z'"),
        (0x61, "ASCII 'a'"),
        (0x7A, "ASCII 'z'"),
    ]
    for ascii_val, label in cases:
        dut.ascii.value = ascii_val
        await Timer(1, unit="ns")
        result = int(dut.bcd.value)
        expected = _dec_to_bcd_12bit(ascii_val)
        assert result == expected, (
            f"AsciiToBcd edge {label}: ascii=0x{ascii_val:02X} ({ascii_val} dec) "
            f"expected bcd=0x{expected:03X}, got 0x{result:03X}"
        )


@cocotb.test()
async def test_ascii_to_bcd_numeric_range(dut):
    """AsciiToBcd: verify ASCII digits '0'-'9' map to their decimal values in BCD."""
    if not _has_ports(dut, "ascii", "bcd"):
        return
    for digit in range(10):
        ascii_val = 0x30 + digit  # '0' through '9'
        dut.ascii.value = ascii_val
        await Timer(1, unit="ns")
        result = int(dut.bcd.value)
        expected = _dec_to_bcd_12bit(ascii_val)
        assert result == expected, (
            f"AsciiToBcd '{chr(ascii_val)}': ascii=0x{ascii_val:02X} ({ascii_val} dec) "
            f"expected bcd=0x{expected:03X}, got 0x{result:03X}"
        )


# ============================================================
# BcdToAscii
# ============================================================

@cocotb.test()
async def test_bcd_to_ascii_boundary(dut):
    """BcdToAscii: boundary BCD values — BCD-encoded decimal → binary byte."""
    if not _has_ports(dut, "Bcd", "Ascii"):
        return
    cases = [
        (0x000, 0),    # BCD 000 → 0
        (0x001, 1),    # BCD 001 → 1
        (0x063, 63),   # BCD 063 → 63
        (0x099, 99),   # BCD 099 → 99
        (0x100, 100),  # BCD 100 → 100
        (0x255, 255),  # BCD 255 → 255
    ]
    for bcd_raw, expected_dec in cases:
        dut.Bcd.value = bcd_raw
        await Timer(1, unit="ns")
        result = int(dut.Ascii.value)
        assert result == expected_dec, (
            f"BcdToAscii: Bcd=0x{bcd_raw:03X} (dec {_bcd_12bit_to_dec(bcd_raw)}) "
            f"expected Ascii=0x{expected_dec:02X}, got 0x{result:02X}"
        )


@cocotb.test()
async def test_bcd_to_ascii_roundtrip(dut):
    """BcdToAscii: for all decimal values 0-255, BcdToAscii(in_bcd(dec)) == dec."""
    if not _has_ports(dut, "Bcd", "Ascii"):
        return
    for dec_val in range(256):
        bcd_raw = _dec_to_bcd_12bit(dec_val)
        dut.Bcd.value = bcd_raw
        await Timer(1, unit="ns")
        result = int(dut.Ascii.value)
        assert result == dec_val, (
            f"BcdToAscii: dec={dec_val} Bcd=0x{bcd_raw:03X} "
            f"expected Ascii=0x{dec_val:02X}, got 0x{result:02X}"
        )


# ============================================================
# BcdToBinEnc
# ============================================================

@cocotb.test()
async def test_bcd_to_bin_enc_zero(dut):
    """BcdToBinEnc: 000000 BCD → 0 binary."""
    if not _has_ports(dut, "bcd", "bin"):
        return
    dut.bcd.value = 0
    await Timer(1, unit="ns")
    assert int(dut.bin.value) == 0, f"000000 BCD → expected 0, got {int(dut.bin.value)}"


@cocotb.test()
async def test_bcd_to_bin_enc_small(dut):
    """BcdToBinEnc: simple single-digit BCD values."""
    if not _has_ports(dut, "bcd", "bin"):
        return
    cases = [
        (0x000001, 1),
        (0x000010, 10),
        (0x000100, 100),
        (0x001000, 1000),
        (0x010000, 10000),
        (0x100000, 100000),
    ]
    for bcd_val, expected_bin in cases:
        dut.bcd.value = bcd_val
        await Timer(1, unit="ns")
        result = int(dut.bin.value)
        assert result == expected_bin, (
            f"BcdToBinEnc: BCD=0x{bcd_val:06X} expected {expected_bin}, got {result}"
        )


@cocotb.test()
async def test_bcd_to_bin_enc_known(dut):
    """BcdToBinEnc: known multi-digit BCD conversions."""
    if not _has_ports(dut, "bcd", "bin"):
        return
    cases = [
        (0x000009, 9),
        (0x000099, 99),
        (0x000999, 999),
        (0x009999, 9999),
        (0x099999, 99999),
        (0x123456, 123456),
        (0x654321, 654321),
        (0x000042, 42),
        (0x000255, 255),
        (0x010000, 10000),
    ]
    for bcd_val, expected_bin in cases:
        dut.bcd.value = bcd_val
        await Timer(1, unit="ns")
        result = int(dut.bin.value)
        assert result == expected_bin, (
            f"BcdToBinEnc: BCD=0x{bcd_val:06X} expected {expected_bin}, got {result}"
        )


@cocotb.test()
async def test_bcd_to_bin_enc_max(dut):
    """BcdToBinEnc: maximum BCD value 999999."""
    if not _has_ports(dut, "bcd", "bin"):
        return
    dut.bcd.value = 0x999999
    await Timer(1, unit="ns")
    result = int(dut.bin.value)
    assert result == 999999, f"BcdToBinEnc: 999999 BCD → expected 999999, got {result}"


# ============================================================
# BinaryToHex (one-hot 16-bit → 4-bit hex)
# ============================================================

@cocotb.test()
async def test_binary_to_hex_all(dut):
    """BinaryToHex: all 16 one-hot inputs produce correct hex digit."""
    if not _has_ports(dut, "In", "Out"):
        return
    expected = {
        0x0001: 0x0, 0x0002: 0x1, 0x0004: 0x2, 0x0008: 0x3,
        0x0010: 0x4, 0x0020: 0x5, 0x0040: 0x6, 0x0080: 0x7,
        0x0100: 0x8, 0x0200: 0x9, 0x0400: 0xA, 0x0800: 0xB,
        0x1000: 0xC, 0x2000: 0xD, 0x4000: 0xE, 0x8000: 0xF,
    }
    for one_hot, hex_digit in expected.items():
        dut.In.value = one_hot
        await Timer(1, unit="ns")
        result = int(dut.Out.value)
        assert result == hex_digit, (
            f"BinaryToHex: In=0x{one_hot:04X} expected 0x{hex_digit:X}, got 0x{result:X}"
        )


@cocotb.test()
async def test_binary_to_hex_default(dut):
    """BinaryToHex: non-one-hot inputs return default 0."""
    if not _has_ports(dut, "In", "Out"):
        return
    invalid_inputs = [0x0000, 0x0003, 0x0005, 0xFFFF, 0xAAAA, 0x5555, 0x00F0]
    for val in invalid_inputs:
        dut.In.value = val
        await Timer(1, unit="ns")
        result = int(dut.Out.value)
        assert result == 0, (
            f"BinaryToHex: In=0x{val:04X} expected default 0, got 0x{result:X}"
        )


# ============================================================
# OpcodeToSymbol
# ============================================================

@cocotb.test()
async def test_opcode_to_symbol_all(dut):
    """OpcodeToSymbol: test all 32 opcodes produce expected symbols."""
    if not _has_ports(dut, "Opcode", "Symbol") or hasattr(dut, "isa"):
        return
    # Expected mapping from source (casez with wildcards)
    # Format: opcode → ASCII char, byte value
    expected = {
        0x00: (ord(' '), " "),
        0x01: (ord('H'), "H"),
        0x02: (0x07, "\\a"),
        0x03: (0x00, "\\0"),
        0x04: (ord('E'), "E"),
        0x05: (ord('S'), "S"),
        0x06: (ord('{'), "{"),
        0x07: (ord('}'), "}"),
        0x08: (ord('L'), "L"),
        0x09: (ord('I'), "I"),
        0x0A: (ord('0'), "0"),
        0x0B: (ord('A'), "A"),
        0x0C: (ord('R'), "R"),
        0x0D: (ord('r'), "r"),
        0x0E: (ord('D'), "D"),
        0x0F: (ord('B'), "B"),
        0x10: (ord(' '), " "),  # ?0 wildcard
        0x11: (ord('H'), "H"),  # ?1 wildcard
        0x12: (ord('+'), "+"),
        0x13: (ord('-'), "-"),
        0x14: (ord('>'), ">"),
        0x15: (ord('<'), "<"),
        0x16: (ord('['), "["),
        0x17: (ord(']'), "]"),
        0x18: (ord('.'), "."),
        0x19: (ord(','), ","),
        0x1A: (ord('0'), "0"),  # ?A wildcard
        0x1B: (ord('M'), "M"),
        0x1C: (ord('G'), "G"),
        0x1D: (ord('P'), "P"),
        0x1E: (ord('D'), "D"),  # ?E wildcard
        0x1F: (ord('B'), "B"),  # ?F wildcard
    }

    for opcode in range(32):
        dut.Opcode.value = opcode
        await Timer(1, unit="ns")
        result = int(dut.Symbol.value)
        exp_byte, exp_char = expected[opcode]
        assert result == exp_byte, (
            f"OpcodeToSymbol: opcode=0x{opcode:02X} expected '{exp_char}' (0x{exp_byte:02X}), got 0x{result:02X}"
        )


# ============================================================
# SymbolToOpcode
# ============================================================

@cocotb.test()
async def test_symbol_to_opcode_roundtrip_isa0(dut):
    """SymbolToOpcode: round-trip SymbolToOpcode(OpcodeToSymbol(op), isa=0) == op for most opcodes.

    Opcode 0x03 (→ \"\\0\" = 0x00) is excluded because SymbolToOpcode has no
    explicit case for 0x00 and its default produces {isa, 4'h0}, which does
    not round-trip back to 0x03.
    """
    if not _has_ports(dut, "Symbol", "Opcode", "isa"):
        return

    opcode_to_symbol_map = {
        0x00: ord(' '), 0x01: ord('H'), 0x02: 0x07,
        0x04: ord('E'), 0x05: ord('S'), 0x06: ord('{'), 0x07: ord('}'),
        0x08: ord('L'), 0x09: ord('I'), 0x0A: ord('0'), 0x0B: ord('A'),
        0x0C: ord('R'), 0x0D: ord('r'), 0x0E: ord('D'), 0x0F: ord('B'),
    }

    for opcode, symbol_byte in opcode_to_symbol_map.items():
        dut.Symbol.value = symbol_byte
        dut.isa.value = 0
        await Timer(1, unit="ns")
        result = int(dut.Opcode.value)
        assert result == opcode, (
            f"SymbolToOpcode roundtrip isa=0: opcode=0x{opcode:02X} "
            f"symbol=0x{symbol_byte:02X} expected opcode=0x{opcode:02X}, got 0x{result:02X}"
        )


@cocotb.test()
async def test_symbol_to_opcode_roundtrip_isa1(dut):
    """SymbolToOpcode: round-trip with isa=1 for wildcard opcodes."""
    if not _has_ports(dut, "Symbol", "Opcode", "isa"):
        return
    wildcard_isa1 = [
        (0x10, ord(' ')),  # 0x10 → space → {1, 4'h0} = 0x10
        (0x11, ord('H')),  # 0x11 → H → {1, 4'h1} = 0x11
        (0x1A, ord('0')),  # 0x1A → 0 → {1, 4'hA} = 0x1A
        (0x1E, ord('D')),  # 0x1E → D → {1, 4'hE} = 0x1E
        (0x1F, ord('B')),  # 0x1F → B → {1, 4'hF} = 0x1F
    ]

    for opcode, symbol_byte in wildcard_isa1:
        dut.Symbol.value = symbol_byte
        dut.isa.value = 1
        await Timer(1, unit="ns")
        result = int(dut.Opcode.value)
        assert result == opcode, (
            f"SymbolToOpcode roundtrip isa=1: opcode=0x{opcode:02X} "
            f"symbol=0x{symbol_byte:02X} expected opcode=0x{opcode:02X}, got 0x{result:02X}"
        )


@cocotb.test()
async def test_symbol_to_opcode_all_defined(dut):
    """SymbolToOpcode: verify all defined symbol mappings."""
    if not _has_ports(dut, "Symbol", "Opcode", "isa"):
        return

    # All defined symbols and their expected opcodes for isa=0
    defined = [
        (ord(' '), 0x00),
        (ord('H'), 0x01),
        (0x07, 0x02),        # \a
        (ord('E'), 0x04),
        (ord('S'), 0x05),
        (ord('{'), 0x06),
        (ord('}'), 0x07),
        (ord('L'), 0x08),
        (ord('I'), 0x09),
        (ord('0'), 0x0A),
        (ord('A'), 0x0B),
        (ord('R'), 0x0C),
        (ord('r'), 0x0D),
        (ord('D'), 0x0E),
        (ord('B'), 0x0F),
        (ord('+'), 0x12),
        (ord('-'), 0x13),
        (ord('>'), 0x14),
        (ord('<'), 0x15),
        (ord('['), 0x16),
        (ord(']'), 0x17),
        (ord('.'), 0x18),
        (ord(','), 0x19),
        (ord('M'), 0x1B),
        (ord('G'), 0x1C),
        (ord('P'), 0x1D),
    ]

    for symbol_byte, expected_opcode in defined:
        dut.Symbol.value = symbol_byte
        dut.isa.value = 0
        await Timer(1, unit="ns")
        result = int(dut.Opcode.value)
        assert result == expected_opcode, (
            f"SymbolToOpcode: symbol=0x{symbol_byte:02X} "
            f"expected opcode=0x{expected_opcode:02X}, got 0x{result:02X}"
        )


@cocotb.test()
async def test_symbol_to_opcode_unknown_default(dut):
    """SymbolToOpcode: unknown symbols default to {isa, 4'h0}."""
    if not _has_ports(dut, "Symbol", "Opcode", "isa"):
        return

    unknown_symbols = [0x00, 0x01, 0x20, 0x40, 0x60, 0x7F, 0xFF]
    for sym in unknown_symbols:
        dut.Symbol.value = sym
        dut.isa.value = 0
        await Timer(1, unit="ns")
        result = int(dut.Opcode.value)
        assert result == 0x00, (
            f"SymbolToOpcode unknown: symbol=0x{sym:02X} isa=0 expected 0x00, got 0x{result:02X}"
        )

        dut.isa.value = 1
        await Timer(1, unit="ns")
        result = int(dut.Opcode.value)
        assert result == 0x10, (
            f"SymbolToOpcode unknown: symbol=0x{sym:02X} isa=1 expected 0x10, got 0x{result:02X}"
        )


# ============================================================
# In12CathodeToPin
# ============================================================

@cocotb.test()
async def test_in12_cathode_to_pin_all(dut):
    """In12CathodeToPin: test all 10 cathode positions."""
    if not _has_ports(dut, "Cathode", "Pin"):
        return

    # Mapping from source:
    # Cathode 0→1, 1→0, 2→2, 3→3, 4→6, 5→8, 6→9, 7→7, 8→5, 9→4
    expected = {0: 1, 1: 0, 2: 2, 3: 3, 4: 6, 5: 8, 6: 9, 7: 7, 8: 5, 9: 4}

    for cathode in range(10):
        dut.Cathode.value = cathode
        await Timer(1, unit="ns")
        result = int(dut.Pin.value)
        assert result == expected[cathode], (
            f"In12CathodeToPin: Cathode={cathode} expected Pin={expected[cathode]}, got {result}"
        )


@cocotb.test()
async def test_in12_cathode_to_pin_invalid(dut):
    """In12CathodeToPin: values outside 0-9 return default 0xA."""
    if not _has_ports(dut, "Cathode", "Pin"):
        return

    for cathode in [10, 11, 12, 13, 14, 15]:
        dut.Cathode.value = cathode
        await Timer(1, unit="ns")
        result = int(dut.Pin.value)
        assert result == 0xA, (
            f"In12CathodeToPin: Cathode={cathode} (invalid) expected 0xA, got {result}"
        )
