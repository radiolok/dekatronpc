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
    ' ' : "0000",
    '+' : "0001",
    '-' : "0010",
    '>' : "0011",
    '<' : "0100",
    '[' : "0101",
    ']' : "0110",
    '.' : "0111",
    ',' : "1000",
    'H' : "1111",
}

def encodeSymbol(symbol):
    opcode = "0000"
    try:
        opcode = symbolToOpcode[symbol]
    except KeyError:
        return opcode
    return opcode



def Generate(filePath, resultPath):
    fileIn = open(filePath,'r')
    fileOut = open(resultPath, 'w')
    fileSize = os.path.getsize(filePath)
    fileName = os.path.splitext(os.path.basename(resultPath))[0]
    if fileSize == 0:
        return -1
    if GenerateHeader(fileIn, fileName, fileSize, fileOut) != 0:
        return -1
    if GenerateBody(fileIn, fileOut) != 0:
        return -1
    if GenerateFooter(fileIn, fileOut) != 0:
        return -1
    fileIn.close()
    fileOut.close()
    return 0



def GenerateHeader(fileIn, fileName, fileSize, fileOut):
    fileOut.write("module %s(Address, Data);\n\n" %(fileName))
    fileOut.write("")
    portSize = 4
    codeSize = fileSize/4
    if fileSize % 4:
        codeSize += 1

    if codeSize > 10:
        portSize = 8
    if codeSize > 100:
        portSize = 12
    if codeSize > 1000:
        portSize = 16
    if codeSize > 10000:
        portSize = 20
    if codeSize > 100000:
        portSize = 24
    fileOut.write("parameter portSize = %d\n" % (portSize))
    fileOut.write("parameter dataSize = 16\n\n")
    fileOut.write("input [portSize-1:0] Address\n")
    fileOut.write("input [dataSize-1:0] Data\n\n")
    fileOut.write("always_comb\n")
    fileOut.write("  case(Address)\n")
    return 0

def GenerateFooter(fileIn, fileOut):
    fileOut.write("    default: Data = {dataSize{1'b0}}\n")
    fileOut.write("  endcase\n\n")
    fileOut.write("endmodule\n")
    return 0

def GenerateBody(fileIn, fileOut):
    caseNumber = 0
    while 1:
        count = 0
        symbols = [' ', ' ', ' ', ' ']
        symbols_enc = ["0000", "0000", "0000", "0000"]
        while count < 4:
            symbol = fileIn.read(1)
            if not symbol:  
                break
            if checkSymbol(symbol):
                symbols[count] = symbol
                symbols_enc[count] = encodeSymbol(symbol)
                count += 1
        generatedCase = "    %d: Data = dataSize{4'b%s, 4'b%s, 4'b%s, 4'b%s};\n" % (caseNumber, symbols_enc[3], symbols_enc[2], symbols_enc[1], symbols_enc[0])
        sys.stdout.write(generatedCase)
        fileOut.write(generatedCase)
        if count < 4:
            break
        caseNumber += 1
    return 0


if __name__ == '__main__':    
    parser = argparse.ArgumentParser()
    parser.add_argument('-f', '--file', nargs='+')

    args = parser.parse_args()

    if args.file == None:
        print("No input files, exiting")
        exit()
    
    for file in args.file:
        filePath = os.path.abspath(file)
        print("Generate rom from: %s" %(filePath))        
        resultPath = os.path.splitext(filePath)[0] + ".sv"
        print("Generate file: %s" % (resultPath))
        Generate(filePath, resultPath)