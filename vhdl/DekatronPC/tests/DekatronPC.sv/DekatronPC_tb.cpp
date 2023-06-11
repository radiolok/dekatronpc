#include <stdlib.h>
#include <iostream>
#include <verilated.h>
#include <verilated_vcd_c.h>
#include "VDekatronPC.h"
#include "dpcrun.h"
#include <chrono>
#include <curses.h>
using namespace std::chrono;

#define MUL (50)
#define HALF_HIGH_P (1)
#define HIGH_P (HALF_HIGH_P*2)
#define HALF_SLOW_P (HIGH_P*5)
#define SLOW_P (HALF_SLOW_P*2)
#define MAX_INSN_COUNT 2500000
#define INSN_EXEC_TIME (SLOW_P*20)
#define MAX_SIM_TIME (INSN_EXEC_TIME*MAX_INSN_COUNT)

#define SIM_TRACE 1

class VerilogMachine{
public:
    vluint64_t PLL_CLK;
    vluint64_t CPU_CLK_UNHALTED;
    VDekatronPC *dut;

#ifdef SIM_TRACE
    VerilatedVcdC *trace;
#endif

    VerilogMachine(){
        PLL_CLK = 0;
        CPU_CLK_UNHALTED = 0;
        dut = new VDekatronPC;
#ifdef SIM_TRACE
        trace = new VerilatedVcdC;
#endif
        dut->Rst_n = 1;
        dut->hsClk = 0;
        dut->Clk = 0;
    }

    ~VerilogMachine(){
#ifdef SIM_TRACE      
        trace->close();
        delete trace;
#endif
        delete dut;
    }
};

uint8_t Cout(bool state, uint16_t data)
{
    static bool CoutOld = false;
    uint8_t update = 0;
    if (!CoutOld & state){
        uint16_t symbol = (data&0x0F) + ((data>>4) &0x0F)*10 + ((data>>8) &0x0F)*100;
        printf("COUT: %c\n", symbol);
        update = 1;
    }
    CoutOld = state;
    return update;
}

uint8_t Cin(bool state, uint16_t& symbol)
{
    static bool CinOld = false;
    uint8_t update = 0;
    if (!CinOld & state){
        char c;
        std::cin >> c;
        uint8_t high = c / 100;
        uint8_t med = (c % 100) / 10;
        uint8_t low = c % 10;
        symbol = (high << 8) + (med << 4) + low;
        printf("CIN: %c %x\n", c, symbol);
        update = 1;
    }
    CinOld = state;
    return update;
}

uint8_t InsnToSymbol(int Insn){
    switch(Insn){
        case 0: return 'N';
        case 1: return 'H';
        case 2: return '+';
        case 3: return '-';
        case 4: return '>';
        case 5: return '<';
        case 6: return '[';
        case 7: return ']';
        case 8: return '.';
        case 9: return ',';
        case 10: return 'R';
    }
    return 'x';
}

int stepVerilog(VerilogMachine &state){
    while(true){
        static int prev_state = state.dut->state;
        if (state.PLL_CLK == 1){
            state.dut->Rst_n = 0;
        }
        if (state.PLL_CLK == SLOW_P*2){
            state.dut->Rst_n = 1;
        }
        if (state.PLL_CLK == SLOW_P*4){
            state.dut->Run = 1;
        }
        if (state.PLL_CLK == SLOW_P*6){
        state.dut->Run = 0;
        }
        if (state.PLL_CLK > SLOW_P*10){
            if (state.dut->state == 0x04)
                return state.dut->state;
        }
        if ((state.PLL_CLK % HALF_HIGH_P) == 0){
            state.dut->hsClk ^= 1;
        }
        if ((state.PLL_CLK % HALF_SLOW_P) == 0){
            state.dut->Clk ^= 1;
            if (state.dut->Clk){
                state.CPU_CLK_UNHALTED++;
            }
        }
        if (Cout(state.dut->Cout, state.dut->Data))
        {
            state.dut->CioAcq = 1;
        }
        if (!(state.dut->Cout | state.dut->CinReq)){
            state.dut->CioAcq = 0;
        }
        if (Cin(state.dut->CinReq, state.dut->DataCin)){
            state.dut->CioAcq = 1;
        }
        state.dut->eval();
#ifdef SIM_TRACE
        state.trace->dump(state.PLL_CLK*MUL);
#endif
        state.PLL_CLK++;
        if ((state.dut->state == 0x02) & (prev_state == 0x03))
        {
            prev_state = state.dut->state;
            return 0;
        }
        prev_state = state.dut->state;
    }
}

int BcdToInt(int bcd, int groups)
{
    int result = 0;
    for (int i = 0; i < groups; ++i)
    {
        int digit = (bcd >> (4*i)) & 0xF;
        result += digit * pow(10, i);
    }
    return result;
}

int compareStates(const VerilogMachine& state, const CppMachine& cppMachine)
{
    if (state.dut->IRET != cppMachine.IRET){
        printf("FATAL: state.IRET(%d) != cppMachine.IRET(%ld)\n",
                state.dut->IRET, cppMachine.IRET);
        return -1;
    }
    if (BcdToInt(state.dut->IpAddress, 6) != cppMachine.codeRAM.pos())
    {
        printf("FATAL: state.dut->IpAddress(%d) != CppMachine.codeRAM.pos(%ld)\n",
        BcdToInt(state.dut->IpAddress, 6), cppMachine.codeRAM.pos());
        return -1;
    }
    if (BcdToInt(state.dut->ApAddress, 5) != cppMachine.dataRAM.pos())
    {
        printf("FATAL: state.dut->ApAddress(%d) != CppMachine.dataRAM.pos(%ld)\n",
        BcdToInt(state.dut->ApAddress, 5), cppMachine.dataRAM.pos());
        return -1;
    }
    if (BcdToInt(state.dut->Data, 3) != static_cast<uint8_t>(*cppMachine.dataRAM))
    {
        printf("FATAL: state.dut->Data(%d) != *CppMachine.dataRAM(%d)\n",
        BcdToInt(state.dut->Data, 3), *cppMachine.dataRAM);
        return -1;
    }
    if (BcdToInt(state.dut->LoopCount, 3) != cppMachine.loopCounter.pos())
    {
        printf("FATAL: state.dut->LoopCount(%d) != cppMachine.loopCounter.pos(%ld)\n",
        BcdToInt(state.dut->LoopCount, 3), cppMachine.loopCounter.pos());
        return -1;
    }
    return 0;
}

int main(int argc, char** argv, char** env) {
	int status = -1;
	int c = 0;
    int stepMode = 0;
	char *filePath = NULL;
	while((c = getopt(argc, argv, "f:sth")) != -1){
		switch(c)
		{
		case 'h':
      std::cout << "dpcrun -f <file>" << std::endl;
      std::cout << "use -s to step mode" << std::endl;
      std::cout << "use -h to show this menu" << std::endl;
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
		std::cerr << "Input file error, exiting"<< std::endl;
		return -1;
	}

    std::streamsize size = filesize(filePath);
    if (size == 0)
    {
        std::cerr << "Input file " << filePath << " empty, exiting" << std::endl;
        return -1;
    }

    file.seekg(0, std::ios::beg);

    std::vector<char> buffer(size);
    file.read(buffer.data(), size);

    VerilogMachine state;
    Memory<char, size_t> codeRAM(0, size + 1, &buffer.front());
	Memory<char, size_t> dataRAM(0, 100000 - 1);
	Counter<size_t> loopCounter(0,999);
	CppMachine cppMachine(codeRAM, dataRAM, loopCounter);
#ifdef SIM_COV
    Verilated::mkdir("logs");
    VerilatedCov::write("logs/coverage_DPC.dat");
#endif
#ifdef SIM_TRACE
    Verilated::traceEverOn(true);
    state.dut->trace(state.trace, 5);
    state.trace->open("VDekatronPC.vcd");
#endif
      
    auto start = high_resolution_clock::now();
    while (state.PLL_CLK < MAX_SIM_TIME) {
        if (cppMachine.codeRAM.pos() == size)
        {
            break;
        }
        if (stepMode){
            stepCpp(cppMachine);
        }
        if (stepVerilog(state) == 0x04){
            break;
        }
        if (stepMode){
            fprintf(stderr,"IRET:%d(%ld) IP: %x(%ld) LOOP:%x(%ld) - INSN: %c(%c) AP: %x(%ld) DATA: %x(%d)\n",
                state.dut->IRET,
                cppMachine.IRET,
                state.dut->IpAddress,
                cppMachine.codeRAM.pos(),
                state.dut->LoopCount,
                cppMachine.loopCounter.pos(),
                InsnToSymbol(state.dut->Insn),
                *(cppMachine.codeRAM),
                state.dut->ApAddress,
                cppMachine.dataRAM.pos(),
                state.dut->Data,
                static_cast<uint8_t>(*(cppMachine.dataRAM))
                );
            if (compareStates(state, cppMachine))
            {
                return -1;
            }
        }
        if ((state.dut->IRET % 10000) == 0)
            printf("Time: %ldus, IRET: %d\n", state.CPU_CLK_UNHALTED, state.dut->IRET);
    }
    auto stop = high_resolution_clock::now();
    auto duration = duration_cast<microseconds>(stop - start);
    printf("VDekatronPC Done. state.CPU_CLK_UNHALTED = %ld, state.IRET=%d\n", 
                state.CPU_CLK_UNHALTED,
                state.dut->IRET);
    std::cout << "Time taken by function: "
         << duration.count() << " microseconds" << std::endl;
    exit(EXIT_SUCCESS);
}