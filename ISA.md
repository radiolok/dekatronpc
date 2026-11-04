# DekatronPC instruction set (ISA16)

One 4-bit instruction set, no modes (TRS v0.42, [doc/isa16.md](doc/isa16.md)).
Codes 0x0–0xA are Brainfuck; the rest serve loading and the bootloader.
The symbols are those of `rtl/run/generate_rom.py` and `bfutils/dpcrun`.

| Symbol | Opcode | Brainfuck | Name | Description |
|---|---|---|---|---|
| `N` | 0x0 | | NOP | No operation |
| `H` | 0x1 | | HALT | Stop; Run resumes at the next instruction |
| `+` | 0x2 | `+` | INC | Increment the current cell |
| `-` | 0x3 | `-` | DEC | Decrement the current cell |
| `>` | 0x4 | `>` | AINC | Increment the address pointer |
| `<` | 0x5 | `<` | ADEC | Decrement the address pointer |
| `[` | 0x6 | `[` | LBEG | If the cell is zero, skip the loop |
| `]` | 0x7 | `]` | LEND | If the cell is not zero, repeat the loop |
| `.` | 0x8 | `.` | COUT | Print the cell |
| `,` | 0x9 | `,` | CIN | Read a character into the cell (waits) |
| `0` | 0xA | `[-]` | CLRD | Clear the cell (sets MemLock) |
| `S` `E` | 0xB | | LD | Start loading at the next address; in the load stream it ends loading (EOT) and is not stored |
| `A` | 0xC | | CLRA | Clear the address pointer (a locked cell is written back first) |
| `P` | 0xD | | MemLock | Set the MemLock flag without a load: the cell takes the data counter's value; `>P<` copies a cell to its neighbour |
| `{` | 0xE | | LABEG | If the address pointer is zero, skip the loop |
| `}` | 0xF | | LAEND | If the address pointer is not zero, repeat the loop |

The loop scan counts `[ ]` and `{ }` together: the two kinds must nest
properly with each other. `{ }` exist for the bootloader.

## Bootloader

Hard Reset sets IP = 99990 (the ROM decade 99990–99999), AP = Data = 0:

```
99990: 0 < { 0 < }     clear the data memory: the first < wraps AP to the top
99996: N N N
99999: S               LD: load the program from address 0 (IP wraps)
```

The program stream ends with `E`; with SoftRstOnEOT the machine soft-resets
and runs the program from 0.
