import os
import sys
import argparse

def AsciiToBcd(dir):
    sv = open(f"{dir}/AsciiToBcd.sv", 'w')
    sv.write("module AsciiToBcd(\n")
    sv.write("   input wire [7:0] ascii,\n")
    sv.write("   output reg [11:0] bcd\n);\n")
    sv.write("always_comb\n")
    sv.write("  case(ascii)\n")
    for i in range(256):
        generatedCase = "    8'h%x: bcd = 12'h%d; //%c \n" % (i, i, i if i > 32 else 0x20)
        sv.write(generatedCase)
    sv.write("    default: bcd = {12'bx};\n")
    sv.write("  endcase\nendmodule\n")
    sv.close()
    return 0

def BcdToAscii(dir):
    sv = open(f"{dir}/BcdToAscii.sv", 'w')
    sv.write("module BcdToAscii(\n")
    sv.write("   input wire [11:0] Bcd,\n")
    sv.write("   output reg [7:0] Ascii\n);\n")
    sv.write("always_comb\n")
    sv.write("  case(Bcd)\n")
    for i in range(256):
        generatedCase = "    12'h%d: Ascii = 8'h%x; //%c \n" % (i, i, i if i > 32 else 0x20)
        sv.write(generatedCase)
    sv.write("    default: Ascii = {8'bx};\n")
    sv.write("  endcase\nendmodule\n")
    sv.close()
    return 0

if __name__ == '__main__':    
    parser = argparse.ArgumentParser()
    parser.add_argument('-d', '--dir', required=True)
    args = parser.parse_args()
    AsciiToBcd(args.dir)
    BcdToAscii(args.dir)
