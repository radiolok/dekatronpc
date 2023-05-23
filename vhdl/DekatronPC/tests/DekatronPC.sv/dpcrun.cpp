/* Copyright (c) 2016-2023, Artem Kashkanov
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

* Redistributions of source code must retain the above copyright notice, this
  list of conditions and the following disclaimer.

* Redistributions in binary form must reproduce the above copyright notice,
  this list of conditions and the following disclaimer in the documentation
  and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.*/



#include "dpcrun.h"

using namespace std;

int LoopLookup(CppMachine& machine, bool reverse = false)
{
	++(machine.loopCounter);
	while (machine.loopCounter.pos())
	{
		if (reverse)
		{
			--(machine.codeRAM);
			if (*(machine.codeRAM) == ']')
			{
				++(machine.loopCounter);
			}
			else if (*(machine.codeRAM) == '[')
			{
				--(machine.loopCounter);
			}
		}
		else
		{
			++(machine.codeRAM);
			if (*(machine.codeRAM) == ']')
			{
				--(machine.loopCounter);
			}
			else if (*(machine.codeRAM) == '[')
			{
				++(machine.loopCounter);
			}
		}
		machine.CLK_UNHALTED++;
	}
	return 0;
}

int stepCpp(CppMachine& machine){
	if (machine.codeRAM.Ready())
	{
		++(machine.codeRAM);
	}
	switch (*(machine.codeRAM))
		{
		case '>':
			++(machine.dataRAM);
			break;
		case '<':
			--(machine.dataRAM);
			break;
		case '+':
			++(*(machine.dataRAM));
			break;
		case '-':
			--(*(machine.dataRAM));
			break;
		case '.':
			std::cerr << *(machine.dataRAM) << std::endl;
			break;
		case ',':
			std::cin >> *(machine.dataRAM);
			break;
		case '[':
			if (!(*(machine.dataRAM)))
			{
				LoopLookup(machine);
			}
			break;
		case ']':
			if (*(machine.dataRAM))
			{
				LoopLookup(machine, true);
			}
			break;
		default:
			//NOP
			break;
		}
	machine.CLK_UNHALTED++;
	machine.IRET++;
	return 0;
}


int ExecCode(char* code, size_t size, int stepMode)
{
	Memory<char, size_t> codeRAM(0, size + 1, code);
	Memory<char, size_t> dataRAM(0, 30000);
	Counter<size_t> loopCounter(0,999);
	CppMachine machine(codeRAM, dataRAM, loopCounter);
    while(machine.codeRAM.pos() != size)
    {
		stepCpp(machine);
    }
    std::cout << "IRET:" << machine.IRET << std::endl;
    return 0;
}

std::ifstream::pos_type filesize(const char* filename)
{
	std::ifstream in(filename, std::ifstream::ate | std::ifstream::binary);
	return in.tellg();
}

#ifdef EXEC
int main(int argc, char **argv)
{
	int status = -1;
	int c = 0;
  int stepMode = 0;
	char *filePath = NULL;
	while((c = getopt(argc, argv, "f:sh")) != -1){
		switch(c)
		{
		case 'h':
      cout << "dpcrun -f <file>" << endl;
      cout << "use -s to step mode" << endl;
      cout << "use -h to show this menu" << endl;
        return 0;
			break;
		case 's':
      stepMode = 1;
			break;
		case 'f':
			filePath = optarg;
			break;
		}
	}

	std::ifstream file(filePath, std::ifstream::ate | std::ifstream::binary);
	if (!file.is_open()){
		cerr << "Input file error, exiting"<<endl;
		return -1;
	}

	  std::streamsize size = filesize(filePath);
	  if (size == 0)
	  {
		  cerr << "Input file " << filePath << " empty, exiting" << endl;
		  return -1;
	  }

	  file.seekg(0, std::ios::beg);

	  std::vector<char> buffer(size);
	  file.read(buffer.data(), size);

	  status = ExecCode(&buffer.front(), size, stepMode);
	  if (status) {
		  cerr << "Code Execution Error, Status =" << status << endl;
		  return -1;
	  }
	return 0;
}
#endif
