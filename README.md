# DekatronPC
A vacuum tube and cold-cathode tube based computer

## Dekatrons
Сan do +1 and -1 operations by desing, so they are best devices for brainfuck instruction set.

As a next generation of BrainfuckPC, DekatronPC should have next characteristics:

* 8 instructions - pure brainfuck only without RLE;
* 1M Instruction Pointer counter;
* 30K Address Pointer Counter;
* 256 data counter;
* Harvard architecture;
* Up to 50kHz clock;
* RAM size - 30 000 bytes;
* RAM device - ferrite core memory;

![DekatronPC arch](https://github.com/radiolok/dekatronpc/blob/master/img/DPC_Arch.jpg)

Architecture of the machine

```
$ git clone https://github.com/radiolok/dekatronpc.git
$ cd dekatronpc/vhdl
$ sudo docker build -t emulator .
$ sudo docker run --rm -it --entrypoint bash dpc_emul
# ./run_emul.sh
```
