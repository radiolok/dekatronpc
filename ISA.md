# DekatronPC Instruction set

DekatronPC Instruction set if fully compatible with brainfuck programming language, but have some extentions for maintance purposes.

In-memory representation for each instruction is 4-bit width, 
but there are two Instruction Set Registers - ISAR0 and ISAR1, which extend number of instructions from 16 to 64.

## Brainfuck ISA (ISAR1=0, ISAR0=0)

| Symbol | Opcode | Brainfuck | Name | Description |
|------|--------|-----------|-|------------|
|  N |  0x0   |          |NOP | No instruction, can be used for alignment purposes|
|  H |  0x1   |          |HALT | Stop machine execution, Namual resume |
|  + |  0x2   |     +     |INC  | Increment of Current data cell|
|  - |  0x3   |     -     |DEC  | Decrement of current data cell|
|  > |  0x4   |     >     |AINC | Increment of address pointer|
|  < |  0x5   |     <     |ADEC | Decrement of address pointer|
|  [ |  0x6   |     [     |LBEG | If current data cell equal zero, skip the loop|
|  ] |  0x7   |     ]     |LEND| If current data cell not equal zero, repeat loop iteration|
|  . |  0x8   |     .     |COUT| Print current symbol to the terminal|
|  , |  0x9   |     ,     |CIN | Read symbol from the terminal (Blocked acces - Program halted while no symbol)|
|  R |  0xA   |          |RST | Hard reset|
|  0 |  0xB   |          |CLRD | Write zero to current Data Cell |
|  3 |  0xC   |          |ISA3| Set ISAR1 = 1 and ISAR0=1 - RESERVED ISA|
|  P |  0xD   |          |ISA2| Set ISAR1 = 1 and ISAR0=0 - PunchTape ISA|
|  M |  0xE   |          |ISA1| Set ISAR1 = 0 and ISAR0=1 - Maintaince ISA|
|  B |  0xF   |          |ISA0| Set ISAR1 = 0 and ISAR0=0 - Brainfuck ISA (Default value)|

## Maintance ISA (ISAR1=0, ISAR0=1)

| Symbol | Opcode | Brainfuck | Name | Description |
|------|--------|-----------|-|------------|
|  { |  0x0   |          |LABEG | If current address equal zero, skip the loop|
|  } |  0x1   |          |LAEND | If current address is not equal zero, repeat loop iteration  |
|   |  0x2   |          |  ||
|   |  0x3   |         |  ||
|  > |  0x4   |     >     | AINC | Increment of address pointer|
|  < |  0x5   |     <     | ADEC | Decrement of address pointer|
|   |  0x6   |          | | |
|   |  0x7   |          || |
|  S |  0x8   |          |SETI| Set instruction counter to start point|
|  I |  0x9   |          |CLRI |Clear instruction counter|
|  A |  0xA   |          |CLRA | Clear address counter|
|  0 |  0xB   |          | CLRD   | Clear Data |
|  3 |  0xC   |          |ISA3| Set ISAR1 = 1 and ISAR0=1 - RESERVED ISA|
|  P |  0xD   |          |ISA2| Set ISAR1 = 1 and ISAR0=0 - PunchTape ISA|
|  M |  0xE   |          |ISA1| Set ISAR1 = 0 and ISAR0=1 - Maintaince ISA|
|  B |  0xF   |          |ISA0| Set ISAR1 = 0 and ISAR0=0 - Brainfuck ISA (Default value)|



# Bootloader

Bootloder is the code, which is performed after reset vector. In placed on the instruction address 0x00000;

## Memory clearance routine

After Reset vector release we have zeroes in any counters, but memory can contain garbage. We need to do cleanup:

  ```
  for (i = 0; i < 30000; ++i)
  {
    Memory[i] = 0;
  }
  ```
  
With Dekatron PC ISA we will get next code:

```
  MA0> //Select maintance ISA, Clear Address counter, Clear data and select next data cell
  {   // While address counter is not zero
    0 >//Cleanup current data cell and go next
  }
  B //Set Default brainfuck ISA
  ```
