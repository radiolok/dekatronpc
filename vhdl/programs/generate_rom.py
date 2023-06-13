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
    '0' : 0x0A # Clear data cell
}

def encodeSymbol(symbol):
    if symbol in symbolToOpcode:
        return symbolToOpcode[symbol]
    return None

def Generate(filePath, resultPath):
    bfk = open(filePath,'r')
    sv = open(resultPath, 'w')
    fileSize = os.path.getsize(filePath)
    if fileSize == 0:
        return -1
    sv.write("module firmware #(\n")
    sv.write(f"//{bfk.name}\n")
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
        generatedCase = "    %d'h%d: Data = 4'h%x; //%c \n" % (portSize, address, encoded, symbol)
        sys.stdout.write(generatedCase)
        sv.write(generatedCase)
        address += 1 
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
    parser.add_argument('-o', '--outfile')

    args = parser.parse_args()

    if args.file == None:
        print("No input files, exiting")
        exit()
    
    for file in args.file:
        filePath = os.path.abspath(file)
        print("Generate rom from: %s" %(filePath))
        resultPath = args.outfile if args.outfile else os.path.splitext(filePath)[0] + ".sv"
        print("Generate file: %s" % (resultPath))
        Generate(filePath, resultPath)
