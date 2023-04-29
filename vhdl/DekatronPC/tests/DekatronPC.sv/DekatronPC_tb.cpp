#include <stdlib.h>
#include <iostream>
#include <verilated.h>
#include <verilated_vcd_c.h>
#include "VDekatronPC.h"

#define MAX_SIM_TIME 601000
vluint64_t sim_time = 0;

int main(int argc, char** argv, char** env) {
    VDekatronPC *dut = new VDekatronPC;

    Verilated::traceEverOn(true);
    Verilated::mkdir("logs");
    VerilatedCov::write("logs/coverage_DPC.dat");
    VerilatedVcdC *m_trace = new VerilatedVcdC;
    dut->trace(m_trace, 5);
    m_trace->open("VDekatronPC.vcd");
    dut->Rst_n = 1;
    int count = 0;
    while (sim_time < MAX_SIM_TIME) {
        if (sim_time == 1){
            dut->Rst_n = 0;
        }
        if (sim_time == 4){
            dut->Rst_n = 1;
        }
        if (sim_time == 40){
            dut->Run = 1;
        }
        if (sim_time == 100){
            dut->Run = 0;
        }
        if (sim_time > 1000){
            if (dut->CurrentState == 0x04)
                break;
        }
        dut->hsClk ^= 1;
        if (count==10)
        {
            dut->Clk = 1;
        }
        if (count == 20)
        {
            dut->Clk = 0;
            count = 0;
        }
        count++;
        dut->eval();
        m_trace->dump(sim_time);
        sim_time++;
    }
    printf("VDekatronPC Done. sim_time = %ld\n", sim_time);
    m_trace->close();
    delete dut;
    exit(EXIT_SUCCESS);
}