"""BCD conversion and arithmetic utilities.

These mirror the BcdToInt function in DekatronPC_tb.cpp (lines 153-162)
and the BCD arithmetic in the hardware modules.
"""


def bcd_to_int(bcd_value: int, num_digits: int) -> int:
    """Convert a packed BCD value to integer.

    Each group of 4 bits represents a decimal digit (0-9).

    Args:
        bcd_value: Packed BCD value (e.g., 0x255 for decimal 255 with 3 digits)
        num_digits: Number of BCD digits (4 bits each)

    Returns:
        Integer value

    Example:
        bcd_to_int(0x123, 3) -> 123
        bcd_to_int(0xFF, 2) -> 165 (0x0F=15, 0x0F=15, not valid BCD but handled)
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

    Example:
        int_to_bcd(123, 3) -> 0x123
        int_to_bcd(255, 3) -> 0x255
    """
    result = 0
    for i in range(num_digits):
        digit = (value // (10 ** i)) % 10
        result |= (digit & 0xF) << (4 * i)
    return result


def bcd_increment(bcd_value: int, num_digits: int) -> int:
    """Increment a BCD value with proper digit rollover.

    Args:
        bcd_value: Packed BCD value
        num_digits: Number of BCD digits

    Returns:
        Incremented BCD value, wrapping to 0 at max
    """
    val = bcd_to_int(bcd_value, num_digits)
    val += 1
    max_val = (10 ** num_digits) - 1
    if val > max_val:
        val = 0
    return int_to_bcd(val, num_digits)


def bcd_decrement(bcd_value: int, num_digits: int) -> int:
    """Decrement a BCD value with proper digit rollover.

    Args:
        bcd_value: Packed BCD value
        num_digits: Number of BCD digits

    Returns:
        Decremented BCD value, wrapping to max at -1
    """
    val = bcd_to_int(bcd_value, num_digits)
    if val == 0:
        val = (10 ** num_digits) - 1
    else:
        val -= 1
    return int_to_bcd(val, num_digits)


def bcd_increment_limit(bcd_value: int, num_digits: int, limit: int) -> int:
    """Increment a BCD value with a custom rollover limit.

    Args:
        bcd_value: Packed BCD value
        num_digits: Number of BCD digits
        limit: Rollover limit (wraps to 0 at this value)

    Returns:
        Incremented BCD value
    """
    val = bcd_to_int(bcd_value, num_digits)
    val += 1
    if val >= limit:
        val = 0
    return int_to_bcd(val, num_digits)


def bcd_decrement_limit(bcd_value: int, num_digits: int, limit: int) -> int:
    """Decrement a BCD value with a custom rollover limit.

    Args:
        bcd_value: Packed BCD value
        num_digits: Number of BCD digits
        limit: Rollover limit (wraps to limit-1 at -1)

    Returns:
        Decremented BCD value
    """
    val = bcd_to_int(bcd_value, num_digits)
    if val == 0:
        val = limit - 1
    else:
        val -= 1
    return int_to_bcd(val, num_digits)


def bcd_digit_to_onehot(bcd_digit: int) -> int:
    """Convert a single BCD digit (0-9) to 10-bit one-hot.

    Args:
        bcd_digit: BCD digit value (0-9)

    Returns:
        10-bit one-hot value, or 0 for invalid inputs
    """
    if 0 <= bcd_digit <= 9:
        return 1 << bcd_digit
    return 0


def onehot_to_bcd_digit(onehot: int) -> int:
    """Convert 10-bit one-hot back to BCD digit (0-9).

    Args:
        onehot: 10-bit one-hot value

    Returns:
        BCD digit (0-9), or 0 if no bits set
    """
    for i in range(10):
        if onehot & (1 << i):
            return i
    return 0


def oneshot_active(onehot: int) -> bool:
    """Check if a one-hot encoded value has exactly one active bit.

    Args:
        onehot: One-hot encoded integer

    Returns:
        True if exactly one bit is set
    """
    return onehot > 0 and (onehot & (onehot - 1)) == 0


def split_bcd_digits(bcd_value: int, num_digits: int) -> list:
    """Split a packed BCD value into individual digit values (0-9).

    Args:
        bcd_value: Packed BCD value
        num_digits: Number of BCD digits

    Returns:
        List of digit values, least significant first
    """
    return [(bcd_value >> (4 * i)) & 0xF for i in range(num_digits)]
