import os
import sys
import argparse

symbolToOpcode = {
    'N' : 0x00,#NOP
    'H' : 0x01, #HALT
    '+' : 0x02,
    '-' : 0x03,
    '>' : 0x04,
    '<' : 0x05,
    '[' : 0x06,
    ']' : 0x07,
    '.' : 0x08,
    ',' : 0x09,
    '0' : 0x0A, # Clear data cell
    'M' : 0x0B, # Clear memory Lock
    'G' : 0x0C,
    'P' : 0x0D,
    'D' : 0x0E,
    'B' : 0x0F,
    # Debug ISA:
    '\a' : 0x02, #Ring the bell
    #'-' : 0x03,
    'E' : 0x04, #EOT
    'S' : 0x05, #SOT
    '{' : 0x06,
    '}' : 0x07,
    'L' : 0x08,
    'I' : 0x09,
    '0' : 0x0A, # Clear data cell
    'A' : 0x0B,
    'R' : 0x0C,
    'r' : 0x0D
}

def encodeSymbol(symbol):
    if symbol in symbolToOpcode:
        return symbolToOpcode[symbol]
    return None

def Generate(filePath, resultPath, args):
    bfk = open(filePath,'r')
    sv = open(resultPath, 'w')
    fileSize = os.path.getsize(filePath)
    if fileSize == 0:
        return -1
    if not args.hex:
        sv.write("module firmware #(\n")
        sv.write("//%s\n" % (bfk.name))
        codeSize = int(str(int(fileSize)), base=16)
        portSize = codeSize.bit_length()
        sv.write("parameter portSize = %d,\n" % (portSize))
        sv.write("parameter dataSize = 4)(\n")
        sv.write("/* verilator lint_off UNUSEDSIGNAL */\n")
        sv.write("input wire [portSize-1:0] Address,\n")
        sv.write("/* verilator lint_on UNUSEDSIGNAL */\n")
        sv.write("output reg [dataSize-1:0] Data\n);\n")
        sv.write("always_comb\n")
        sv.write("/* verilator lint_off WIDTHEXPAND */\n")
        sv.write("  case(Address)\n")
    address = 0
    while 1:
        symbol = bfk.read(1)
        if not symbol:
            break
        encoded = encodeSymbol(symbol)
        if not encoded:
            continue
        if args.hex:
            suffix = "0 0 0 0 0 0\n" if (address and (address % 10 == 0)) else ""
            generatedCase = f"{suffix}{encoded:01x} "
        else:
            generatedCase = "    %d'h%d: Data = 4'h%x; //%c \n" % (portSize, address, encoded, symbol)
        if (args.verbose):
            sys.stdout.write(generatedCase)
        sv.write(generatedCase)
        address += 1 
    if not args.hex:
        sv.write("    default: Data = {dataSize{1'bx}};\n")
        sv.write("  endcase\n\n")
        sv.write("/* verilator lint_on WIDTHEXPAND */\n")
        sv.write("endmodule\n")
    bfk.close()
    sv.close()
    return 0

if __name__ == '__main__':    
    parser = argparse.ArgumentParser()
    parser.add_argument('-f', '--file', nargs='+')
    parser.add_argument('--hex', action='store_true', default=False)
    parser.add_argument('-o', '--outfile')
    parser.add_argument('-v', '--verbose', action='store_true')

    args = parser.parse_args()

    if args.file == None:
        print("No input files, exiting")
        exit()
    
    for file in args.file:
        filePath = os.path.abspath(file)
        print("Generate rom from: %s" %(filePath))
        suffix = ".hex" if args.hex else ".sv"
        resultPath = args.outfile if args.outfile else os.path.splitext(filePath)[0] + suffix
        print("Generate file: %s" % (resultPath))
        Generate(filePath, resultPath, args)
