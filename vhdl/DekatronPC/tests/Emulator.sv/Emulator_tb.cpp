#include <stdlib.h>
#include <iostream>
#include <verilated.h>
#include <verilated_vcd_c.h>
#include "VEmulator.h"
#include "curses.h"

#define MAX_SIM_TIME 600000
vluint64_t sim_time = 0;

class UI{
public:
    UI() : KeyCurrentRows(0)
    {

    }

void keyboardClear()
{
    KeyCurrentRows = 0;
}

uint8_t keyboardUpdate(uint8_t data)
{
    KeyCurrentRows = data;
    if (KeyCurrentRows == 0)
        return 0;
    uint8_t tmp = KeyCurrentRows;
    uint8_t idx = 0;
    while (tmp)
    {
        idx++;
        tmp>>=1;
    }
    if (idx < 7)
        return KeypadRaw[7];
    return 0;
}

void in12Clear()
{
    in12CathodesNum = 0;
    in12AnodeNum = 0;
}
void in12CathodeUpdate(uint8_t data)
{
    in12CathodesNum = data;
}
void in12AnodeUpdate(uint8_t data)
{
    in12AnodeNum = data;
}

uint8_t ms6205UpdateAddr(uint8_t data, uint8_t marker){
    ms6205addr = data;
    ms6205marker = marker;
    return 1;
}

uint8_t ms6205UpdateData(uint8_t data, uint8_t marker){
    ms6205ram[ms6205addr] = data;
    ms6205marker = marker;
    return 1;
}

private:
    uint8_t KeyCurrentRows;
    uint8_t KeypadRaw[7];

    uint8_t in12AnodeNum;
    uint8_t in12CathodesNum;

    uint8_t ms6205ram[16*10];
    uint8_t ms6205addr;
    bool ms6205marker;
};


int main(int argc, char** argv, char** env) {
    VEmulator *dut = new VEmulator;
    UI *ui = new UI;
    Verilated::traceEverOn(true);
    Verilated::mkdir("logs");
    VerilatedCov::write("logs/Emulator.dat");
    VerilatedVcdC *m_trace = new VerilatedVcdC;
    dut->trace(m_trace, 5);
    m_trace->open("Emulator.vcd");
    while (sim_time < MAX_SIM_TIME) {
        dut->FPGA_CLK_50 ^= 1;
        if (sim_time == 1){
            dut->KEY = 0;
        }
        if (sim_time == 4){
            dut->KEY = 1;
        }
        dut->eval();
        m_trace->dump(sim_time);
        if (dut->keyboard_write == 1){
            dut->keyboard_data_in = ui->keyboardUpdate(dut->emulData);
        }
        if (dut->keyboard_clear == 1){
            ui->keyboardClear();
        }
        if (dut->in12_write_anode == 1){
            ui->in12AnodeUpdate(dut->emulData);
        }
        if (dut->in12_write_cathode == 1){
            ui->in12CathodeUpdate(dut->emulData);
        }
        if (dut->in12_clear == 1){
            ui->in12Clear();
        }
        if (dut->ms6205_write_addr_n == 0){
            dut->ms6205_ready = ui->ms6205UpdateAddr(dut->emulData, dut->ms6205_marker);
        }
        if (dut->ms6205_write_data_n == 0){
            dut->ms6205_ready = ui->ms6205UpdateData(dut->emulData, dut->ms6205_marker);
        }        
        sim_time++;
    }
    std::cout << "Emulator Done. sim_time = " << sim_time << "\n";
    m_trace->close();
    delete dut;
    delete ui;
    exit(EXIT_SUCCESS);
}