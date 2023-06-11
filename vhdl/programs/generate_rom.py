import os
import sys

import argparse


def checkSymbol(symbol):
    if (symbol == '+' or \
        symbol == '-' or \
        symbol == '<' or \
        symbol == '>' or \
        symbol == '.' or \
        symbol == ',' or \
        symbol == '[' or \
        symbol == ']' or \
        symbol == 'H' or \
        symbol == ' ' ):
        return True
    return False 

symbolToOpcode = {
    ' ' : "0000",#NOP
    'H' : "0001", #HALT
    '+' : "0010",
    '-' : "0011",
    '>' : "0100",
    '<' : "0101",
    '[' : "0110",
    ']' : "0111",
    '.' : "1000",
    ',' : "1001",
    'R' : "1010" # HARD Reset
}

decToBin = {
    0 : "0000",
    1 : "0001",
    2 : "0010",
    3 : "0011",
    4 : "0100",
    5 : "0101",
    6 : "0110",
    7 : "0111",
    8 : "1000",
    9 : "1001",
    0xA: "1010",
    0xB: "1011",
    0xC: "1100",
    0xD: "1101",
    0xE: "1110",
    0xF: "1111"
}

def encodeSymbol(symbol):
    opcode = "0000"
    try:
        opcode = symbolToOpcode[symbol]
    except KeyError:
        return opcode
    return opcode

def encodeAddress(address, radix = 10):
    addressStr = ""
    if address == 0:
        return decToBin[0]
    while address > 0:
        addressStr = decToBin[int(address % radix)] + addressStr
        address  = address//radix
    return addressStr

def Generate(filePath, resultPath, args):
    fileIn = open(filePath,'r')
    fileOut = open(resultPath, 'w')
    fileSize = os.path.getsize(filePath)
    if fileSize == 0:
        return -1
    portSize = GenerateHeader(fileIn, fileSize, fileOut, args)
    if portSize == 0:
        return -1        
    if GenerateBody(fileIn, fileOut, portSize, args) != 0:
        return -1
    if GenerateFooter(fileOut) != 0:
        return -1
    fileIn.close()
    fileOut.close()
    return 0



def GenerateHeader(fileIn, fileSize, fileOut, args):
    fileOut.write("module firmware #(\n")
    fileOut.write(f"//{fileIn.name}\n")
    portSize = 0
    codeSize = fileSize
    width = args.width
    if fileSize % int(width):
        codeSize += 1
    if codeSize > 0:
        portSize = 4 - int(width /2)
    if codeSize > 10:
        portSize = 8 -  int(width /2)
    if codeSize > 100:
        portSize = 12 - int(width /2)
    if codeSize > 1000:
        portSize = 16 - int(width /2)
    if codeSize > 10000:
        portSize = 20 - int(width /2)
    if codeSize > 100000:
        portSize = 24 - int(width /2)
    fileOut.write("parameter portSize = %d,\n" % (portSize))
    fileOut.write("parameter dataSize = %d)(\n" % (width * 4))
    fileOut.write("/* verilator lint_off UNUSEDSIGNAL */\n")
    fileOut.write("input wire [portSize-1:0] Address,\n")
    fileOut.write("/* verilator lint_on UNUSEDSIGNAL */\n")
    fileOut.write("output reg [dataSize-1:0] Data\n);\n")
    fileOut.write("always_comb\n")
    fileOut.write("/* verilator lint_off WIDTHEXPAND */\n")
    fileOut.write("  case(Address)\n")
    return portSize

def GenerateFooter(fileOut):
    fileOut.write("    default: Data = {dataSize{1'bx}};\n")
    fileOut.write("  endcase\n\n")
    fileOut.write("/* verilator lint_on WIDTHEXPAND */\n")
    fileOut.write("endmodule\n")
    return 0

def GenerateBody(fileIn, fileOut, portSize, args):
    caseNumber = 0
    while 1:
        count = 0
        symbols = [' ', ' ', ' ', ' ']
        symbols_enc = ["0000", "0000", "0000", "0000"]
        addressStr = ""
        addressStrCut = ""
        widthBits = args.width
        radix = args.radix
        while count < widthBits:
            symbol = fileIn.read(1)
            if not symbol:  
                break
            if checkSymbol(symbol):
                symbols[count] = symbol
                symbols_enc[count] = encodeSymbol(symbol)
                count += 1
        addressStr = encodeAddress(caseNumber, radix)
        addressStrCut = addressStr[0: len(addressStr)- int(widthBits / 2)]
        if widthBits == 4:
            generatedCase = "    %d'b%s: Data = {4'b%s, 4'b%s, 4'b%s, 4'b%s}; //%s %s %s %s\n" % (portSize, addressStrCut, 
                symbols_enc[3], symbols_enc[2], symbols_enc[1], symbols_enc[0],
                symbols[3], symbols[2], symbols[1], symbols[0])
        elif widthBits == 2:
            generatedCase = "    %d'b%s: Data = {4'b%s, 4'b%s}; //%s %s \n" % (portSize, addressStrCut, 
            symbols_enc[1], symbols_enc[0], symbols[1], symbols[0]) 
        elif widthBits == 1:
            generatedCase = "    %d'b%s: Data = {4'b%s}; //%s\n" % (portSize, addressStrCut, symbols_enc[0], symbols[0])
        else:
            print("Sorry, only width 1, 2 and 4 is supported")
        sys.stdout.write(generatedCase)
        fileOut.write(generatedCase)
        caseNumber += widthBits
        if count < widthBits:
            break
    return 0


if __name__ == '__main__':    
    parser = argparse.ArgumentParser()
    parser.add_argument('-f', '--file', nargs='+')
    parser.add_argument('-o', '--outfile')
    parser.add_argument('-w', '--width', type=int, default=1)
    parser.add_argument('-r', '--radix', type=int, default=10)

    args = parser.parse_args()

    if args.file == None:
        print("No input files, exiting")
        exit()
    
    for file in args.file:
        filePath = os.path.abspath(file)
        print("Generate rom from: %s" %(filePath))
        resultPath = args.outfile if args.outfile else os.path.splitext(filePath)[0] + ".sv"
        print("Generate file: %s" % (resultPath))
        Generate(filePath, resultPath, args)
