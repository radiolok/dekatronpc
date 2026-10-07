// DekatronPC Verilator testbench with step-by-step comparison against the
// C++ golden model (bfutils/dpcrun, REQ-GM-002).
//
// The program (dpc::assemble()) is loaded into the RTL over InsnIn after the
// InsnLoadingStart key, the bank-tree memory has no preload; the model gets
// it through loadCode(). Both start with Soft Reset + Run. With -s, after
// every instruction the RTL retires, the model steps once and IRET, IP, AP,
// tx_data_bcd, the loop counter and the terminal output are compared.
// Without -s only the final state is compared. Exit code 0 means PASS.
//
// Build: rtl/run/run_tests.sh (veremul). Needs -GEN_EMULATOR=1, otherwise
// IRET and LoopCount are not driven.

#include <stdlib.h>
#include <math.h>
#include <fstream>
#include <iostream>
#include <iterator>
#include <string>
#include <verilated.h>
#include <verilated_vcd_c.h>
#include <getopt.h>
#include "VDekatronPC.h"
#include "dpcrun.h"
#include <chrono>
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

// MachineCtrl states
enum {
    S_HALT     = 0,
    S_IDLE     = 1,
    S_DECODE   = 4,
    S_CIN_WAIT = 9
};

class VerilogMachine{
public:
    vluint64_t PLL_CLK;
    vluint64_t CPU_CLK_UNHALTED;
    VDekatronPC *dut;
    std::string output;
    int lastCin;
    // IRET also counts the opcodes accepted while loading and is not
    // cleared by Soft Reset; the program's count starts from this value
    uint32_t iretBase;

    uint32_t iret() const { return dut->IRET - iretBase; }

#ifdef SIM_TRACE
    VerilatedVcdC *trace;
#endif

    VerilogMachine(){
        PLL_CLK = 0;
        CPU_CLK_UNHALTED = 0;
        lastCin = -1;
        iretBase = 0;
        dut = new VDekatronPC;
#ifdef SIM_TRACE
        trace = new VerilatedVcdC;
#endif
        dut->rst_n = 1;
        dut->SoftRstKey = 0;
        dut->HardRstKey = 0;
        dut->hsClk = 0;
        dut->Clk = 0;
        dut->EchoMode = 1;
    }

    ~VerilogMachine(){
#ifdef SIM_TRACE
        trace->close();
        delete trace;
#endif
        delete dut;
    }
};

static int BcdToInt(int bcd, int groups)
{
    int result = 0;
    for (int i = 0; i < groups; ++i)
    {
        int digit = (bcd >> (4*i)) & 0xF;
        result += digit * pow(10, i);
    }
    return result;
}

static uint8_t Cout(VerilogMachine& state)
{
    static bool CoutOld = false;
    bool vld = state.dut->tx_vld;
    uint8_t update = 0;
    if (!CoutOld && vld){
        char symbol = static_cast<char>(BcdToInt(state.dut->tx_data_bcd, 3));
        state.output.push_back(symbol);
        putchar(symbol);
        fflush(stdout);
        update = 1;
    }
    CoutOld = vld;
    return update;
}

static uint8_t Cin(VerilogMachine& state)
{
    static bool CinOld = false;
    bool waiting = (state.dut->state == S_CIN_WAIT);
    uint8_t update = 0;
    if (!CinOld && waiting){
        int c = std::cin.get();
        if (c == EOF)
            c = 0;
        state.lastCin = c;
        uint8_t high = c / 100;
        uint8_t med = (c % 100) / 10;
        uint8_t low = c % 10;
        state.dut->rx_data_bcd = (high << 8) + (med << 4) + low;
        update = 1;
    }
    CinOld = waiting;
    return update;
}

static void tick(VerilogMachine &state)
{
    if ((state.PLL_CLK % HALF_HIGH_P) == 0){
        state.dut->hsClk ^= 1;
    }
    if ((state.PLL_CLK % HALF_SLOW_P) == 0){
        state.dut->Clk ^= 1;
        if (state.dut->Clk){
            state.CPU_CLK_UNHALTED++;
        }
    }
    Cout(state);
    state.dut->tx_rdy = 1;
    // rx_data_bcd is held until the rx_vld & rx_rdy handshake (REQ-UART-008)
    bool rx_done = state.dut->Clk && state.dut->rx_vld && state.dut->rx_rdy;
    state.dut->eval();
    if (Cin(state)){
        state.dut->rx_vld = 1;
    }
    else if (rx_done){
        state.dut->rx_vld = 0;
    }
#ifdef SIM_TRACE
    state.trace->dump(state.PLL_CLK*MUL);
#endif
    state.PLL_CLK++;
}

// Program memory is the bank tree and has no preload, so the program is
// loaded the way the panel does it. Power-on: rst_n pulse, the time relay
// gives a Hard Reset, the machine halts. Soft Reset (IP = 0, BF ISA), then
// the InsnLoadingStart key and the opcodes over InsnIn/InsnInValid/
// InsnInReady. The program ends with HALT, ISA0, EOT (generate_rom.py and
// dpc::assemble() both append them); with SoftRstOnEOT and RunOnSoftRst the
// EOT gives a Soft Reset and the program starts from 0, which is what the
// model does with softReset() + run().
static bool waitHalted(VerilogMachine &state)
{
    vluint64_t stable = 0;
    while (state.PLL_CLK < MAX_SIM_TIME){
        tick(state);
        stable = (state.dut->IsHalted && state.dut->state == S_HALT) ? stable + 1 : 0;
        if (stable >= SLOW_P*20)
            return true;
    }
    return false;
}

static void pressKey(VerilogMachine &state, CData &key)
{
    key = 1;
    for (vluint64_t t = 0; t < SLOW_P*4; ++t)
        tick(state);
    key = 0;
    for (vluint64_t t = 0; t < SLOW_P*4; ++t)
        tick(state);
}

static bool startVerilog(VerilogMachine &state, const std::vector<uint8_t> &code)
{
    state.dut->rst_n = 0;
    for (vluint64_t t = 0; t < SLOW_P*4; ++t)
        tick(state);
    state.dut->rst_n = 1;
    if (!waitHalted(state))
        return false;
    pressKey(state, state.dut->SoftRstKey);
    if (!waitHalted(state))
        return false;

    state.dut->SoftRstOnEOT = 1;
    state.dut->RunOnSoftRst = 1;
    pressKey(state, state.dut->InsnLoadingStart);
    size_t i = 0;
    bool seenLoading = false;
    while (state.PLL_CLK < MAX_SIM_TIME){
        state.dut->InsnIn = (i < code.size()) ? code[i] : 0;
        state.dut->InsnInValid = (i < code.size());
        bool fire = !state.dut->Clk && state.dut->InsnInReady && state.dut->InsnInValid;
        tick(state);
        if (fire && state.dut->Clk)
            ++i;
        seenLoading |= state.dut->InsnInLoading;
        // EOT accepted: loading drops, the Soft Reset starts the program
        if (seenLoading && !state.dut->InsnInLoading && i == code.size()){
            state.dut->InsnInValid = 0;
            state.iretBase = state.dut->IRET;
            return true;
        }
    }
    return false;
}

// Runs the RTL until one instruction retires: MachineCtrl passes S_DECODE
// and comes back to S_IDLE (or stops in S_HALT). Returns the final state.
static int stepVerilog(VerilogMachine &state)
{
    bool decoded = false;
    int prev = state.dut->state;
    while (state.PLL_CLK < MAX_SIM_TIME){
        tick(state);
        int cur = state.dut->state;
        if (cur == S_DECODE)
            decoded = true;
        if (decoded && cur != prev && (cur == S_IDLE || cur == S_HALT))
            return cur;
        if (!decoded && cur == S_HALT && prev != S_HALT)
            return cur;
        prev = cur;
    }
    return -1;
}

static int compareStates(const VerilogMachine& state, const dpc::Machine& cpp, bool halted)
{
    int err = 0;
    if (state.iret() != cpp.iret()){
        printf("FATAL: IRET %u != model %llu\n", state.iret(),
               static_cast<unsigned long long>(cpp.iret()));
        err = -1;
    }
    // After HALT IpLine steps IP once more a few cycles later; skip it
    if (!halted && static_cast<uint32_t>(BcdToInt(state.dut->IpAddress, 5)) != cpp.ip()){
        printf("FATAL: IpAddress %d != model %u\n", BcdToInt(state.dut->IpAddress, 5), cpp.ip());
        err = -1;
    }
    if (static_cast<uint32_t>(BcdToInt(state.dut->ApAddress, 5)) != cpp.ap()){
        printf("FATAL: ApAddress %d != model %u\n", BcdToInt(state.dut->ApAddress, 5), cpp.ap());
        err = -1;
    }
    if (BcdToInt(state.dut->tx_data_bcd, 3) != cpp.txData()){
        printf("FATAL: tx_data_bcd %d != model %u\n", BcdToInt(state.dut->tx_data_bcd, 3), cpp.txData());
        err = -1;
    }
    if (static_cast<uint32_t>(BcdToInt(state.dut->LoopCount, 3)) != cpp.loopCount()){
        printf("FATAL: LoopCount %d != model %u\n", BcdToInt(state.dut->LoopCount, 3), cpp.loopCount());
        err = -1;
    }
    if (state.output != cpp.output()){
        printf("FATAL: terminal output differs: RTL \"%s\" model \"%s\"\n",
               state.output.c_str(), cpp.output().c_str());
        err = -1;
    }
    return err;
}

int main(int argc, char** argv, char** env) {
    int c = 0;
    int stepMode = 0;
    char *filePath = NULL;
    while((c = getopt(argc, argv, "f:sth")) != -1){
        switch(c)
        {
        case 'h':
            std::cout << "VDekatronPC -f <file>" << std::endl;
            std::cout << "use -s to compare with the golden model after every instruction" << std::endl;
            std::cout << "use -h to show this menu" << std::endl;
            return 0;
        case 's':
            stepMode = 1;
            break;
        case 'f':
            filePath = optarg;
            break;
        }
    }
    std::ifstream file(filePath ? filePath : "", std::ios::binary);
    if (!file.is_open()){
        std::cerr << "Input file error, exiting"<< std::endl;
        return -1;
    }
    std::string source((std::istreambuf_iterator<char>(file)), std::istreambuf_iterator<char>());
    std::vector<uint8_t> code = dpc::assemble(source);
    if (code.empty())
    {
        std::cerr << "Input file " << filePath << " has no instructions, exiting" << std::endl;
        return -1;
    }

    VerilogMachine state;
    dpc::Machine cppMachine;
    cppMachine.loadCode(code);
    cppMachine.softReset();
    cppMachine.run();

#ifdef SIM_COV
    Verilated::mkdir("logs");
    VerilatedCov::write("logs/coverage_DPC.dat");
#endif
#ifdef SIM_TRACE
    Verilated::traceEverOn(true);
    state.dut->trace(state.trace, 5);
    state.trace->open("VDekatronPC.vcd");
#endif
    state.dut->EchoMode = 1;
    if (!startVerilog(state, code)){
        printf("FATAL: RTL did not start: power-on or program load failed\n");
        return -1;
    }

    auto start = high_resolution_clock::now();
    while (state.PLL_CLK < MAX_SIM_TIME) {
        // The program is over when the model reaches the first NOP past it
        if (cppMachine.ip() == code.size() || cppMachine.halted())
            break;

        int rtlState = stepVerilog(state);
        if (rtlState < 0)
            break;

        if (stepMode){
            if (state.lastCin >= 0){
                cppMachine.pushInput(static_cast<uint8_t>(state.lastCin));
                state.lastCin = -1;
            }
            dpc::Status s = cppMachine.step();
            fprintf(stderr, "IRET:%d(%llu) IP:%x(%u) LOOP:%x(%u) INSN:%s AP:%x(%u) DATA:%x(%u) %s\n",
                state.iret(),
                static_cast<unsigned long long>(cppMachine.iret()),
                state.dut->IpAddress,
                cppMachine.ip(),
                state.dut->LoopCount,
                cppMachine.loopCount(),
                dpc::mnemonic(state.dut->Insn, cppMachine.insnMode()),
                state.dut->ApAddress,
                cppMachine.ap(),
                state.dut->tx_data_bcd,
                cppMachine.txData(),
                dpc::statusName(s)
                );
            if (compareStates(state, cppMachine, rtlState == S_HALT))
            {
                return -1;
            }
        }
        if (rtlState == S_HALT)
            break;
        if ((state.iret() % 10000) == 0)
            printf("Time: %lluus, IRET: %u\n",
                   static_cast<unsigned long long>(state.CPU_CLK_UNHALTED), state.iret());
    }
    // Final verdict: both machines halted, same state and terminal output
    if (!stepMode)
        cppMachine.runUntilHalt(MAX_INSN_COUNT);
    int verdict = 0;
    if (!cppMachine.halted() || state.dut->state != S_HALT){
        printf("FATAL: not halted: RTL state %d, model %s\n", state.dut->state,
               cppMachine.halted() ? "halted" : "running");
        verdict = -1;
    }
    if (state.iret() == 0){
        printf("FATAL: RTL retired no instructions\n");
        verdict = -1;
    }
    if (compareStates(state, cppMachine, true))
        verdict = -1;
    auto stop = high_resolution_clock::now();
    auto duration = duration_cast<microseconds>(stop - start);
    printf("VDekatronPC Done. state.CPU_CLK_UNHALTED = %llu, IRET=%u\n",
                static_cast<unsigned long long>(state.CPU_CLK_UNHALTED),
                state.iret());
    std::cout << "Time taken by function: "
         << duration.count() << " microseconds" << std::endl;
    if (verdict){
        printf("FAIL: RTL and model differ\n");
        exit(EXIT_FAILURE);
    }
    printf("PASS: RTL matches the model, output \"%s\"\n", state.output.c_str());
    exit(EXIT_SUCCESS);
}
