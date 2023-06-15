import os
import sys
import argparse

def AsciiToBcd(dir):
    sv = open(f"{dir}/AsciiToBcd.sv", 'w')
    sv.write("function [11:0] AsciiToBcd(\n")
    sv.write("   input [7:0] ascii\n);\n")
    sv.write("  case(ascii)\n")
    for i in range(256):
        generatedCase = "    8'h%x: AsciiToBcd = 12'h%d; //%c \n" % (i, i, i if i > 32 else 0x20)
        sv.write(generatedCase)
    sv.write("    default: AsciiToBcd = {12'bx};\n")
    sv.write("  endcase\nendfunction\n")
    sv.close()
    return 0

def BcdToAscii(dir):
    sv = open(f"{dir}/BcdToAscii.sv", 'w')
    sv.write("function [7:0] BcdToAscii(\n")
    sv.write("   input [11:0] Bcd\n);\n")
    sv.write("  case(Bcd)\n")
    for i in range(256):
        generatedCase = "    12'h%d: BcdToAscii = 8'h%x; //%c \n" % (i, i, i if i > 32 else 0x20)
        sv.write(generatedCase)
    sv.write("    default: BcdToAscii = {8'bx};\n")
    sv.write("  endcase\nendfunction\n")
    sv.close()
    return 0

if __name__ == '__main__':    
    parser = argparse.ArgumentParser()
    parser.add_argument('-d', '--dir', required=True)
    args = parser.parse_args()
    AsciiToBcd(args.dir)
    BcdToAscii(args.dir)
