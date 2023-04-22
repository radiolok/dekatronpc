#include <stdlib.h>
#include <iostream>
#include <verilated.h>
#include "verilated_vpi.h"
#include <verilated_vcd_c.h>
#include "VEmulator.h"
#include "curses.h"
#include "iostream"

#define MAX_SIM_TIME 60000000
#define DIGITS 9

vluint64_t sim_time = 0;

uint8_t In12CathodeToPin[] = {1,0,2,3,6,8,9,7,5,4};

class UI{
public:
    UI() : KeyCurrentRows(0)
    {
        in12High[DIGITS] = 0;
        in12Low[DIGITS] = 0;
        in12anodeWrOld = 0;
        in12cathodeWrOld = 0;
        ms6205addrOld = 0;
        ms6205dataOld = 0;
        in12AnodeNumOld = 0;
        keyboardWrOld = 0;
        for (uint8_t i = 0; i < 7; i++)
        {
            KeypadRaw[i] = 0x00;
        }
    }

    ~UI()
    {

    }

    void Cout(bool state, uint16_t data)
    {
        if (!CoutOld & state){
            uint16_t symbol = (data&0x0F) + ((data>>4) &0x0F)*10 + ((data>>8) &0x0F)*100;
            printw("%x %x %x - %c\n", (data>>8)&0xf, (data>>4)&0xf, (data)&0xf, symbol);
        }
        CoutOld = state;
    }

    void keyboardUpdate(bool state, uint8_t data, uint8_t& dataOut)
    {
        if (!keyboardWrOld & state){
            KeyCurrentRows = data;
            if (KeyCurrentRows == 0)
                return;
            if (KeyCurrentRows & (KeyCurrentRows-1))
                return;
            uint8_t tmp = KeyCurrentRows;
            uint8_t idx = 0;
            while (tmp>>=1)
            {
                idx++;
            }
            if (idx < 7)
                dataOut = KeypadRaw[idx];
        }
        keyboardWrOld = state;
    }

    void in12CathodeUpdate(bool state, uint8_t data)
    {
        if (state & !in12cathodeWrOld)
        {
            in12Low[DIGITS-in12AnodeNum-1]  = In12CathodeToPin[(data & 0x0F)] + 0x30;
            in12High[DIGITS-in12AnodeNum-1] = In12CathodeToPin[((data >> 4) & 0x0F)] + 0x30;
        }
        in12cathodeWrOld = state;
        
    }
    void in12AnodeUpdate(bool state, uint8_t data)
    {
        if (state & !in12anodeWrOld)
        {
            in12AnodeNum = data & 0x0F;
            if (in12AnodeNumOld != in12AnodeNum)
            {
                if (in12AnodeNum == 0)
                {
                    printw("HIGH: ");
                    for (uint8_t i = 0; i < DIGITS; i++)
                        printw("%c", in12High[i]);
                    printw("  LOW: ");
                    for (uint8_t i = 0; i < DIGITS; i++)
                        printw("%c", in12Low[i]);
                    printw("\n");
                }
            }
        }
        in12anodeWrOld = state;
        in12AnodeNumOld = in12AnodeNum;
    }

    uint8_t ms6205UpdateAddr(bool state, uint8_t data, uint8_t marker){
        if (!state & ms6205addrOld)
        {
            ms6205addr = data;
            ms6205marker = marker;
        }
        ms6205addrOld = state;
        return 1;
    }

    uint8_t ms6205UpdateData(bool state, uint8_t data, uint8_t marker){
        if (ms6205dataOld & !state)
        {
            ms6205ram[ms6205addr] = data;
            ms6205marker = marker;
            }
        ms6205dataOld = state;
        return 1;
    }

private:
    uint8_t KeyCurrentRows;
    uint8_t KeypadRaw[7];

    uint8_t in12AnodeNum;
    char in12High[DIGITS+1];
    char in12Low[DIGITS+1];
    bool in12anodeWrOld;
    bool in12cathodeWrOld;

    uint8_t ms6205ram[16*10];
    uint8_t ms6205addr;
    bool ms6205marker;
    bool ms6205addrOld;
    bool ms6205dataOld;
    bool keyboardWrOld;
    bool CoutOld;
    uint8_t in12AnodeNumOld;
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
    dut->KEY = 1;
    dut->FPGA_CLK_50 = 0;
    initscr();                   // Переход в curses-режим
    printw("Hello world!\n");  // Отображение приветствия в буфер
    refresh();                   // Вывод приветствия на настоящий экран
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

        if (dut->DPC_currentState == 0x04)
            break;//DPC HALTED


        ui->Cout(dut->Cout, dut->Data);
        ui->keyboardUpdate(dut->keyboard_write, dut->emulData, dut->keyboard_data_in);
        ui->in12AnodeUpdate(dut->in12_write_anode, dut->emulData);
        ui->in12CathodeUpdate(dut->in12_write_cathode, dut->emulData);
    
        dut->ms6205_ready = ui->ms6205UpdateAddr(dut->ms6205_write_addr_n, dut->emulData, dut->ms6205_marker);
        dut->ms6205_ready = ui->ms6205UpdateData(dut->ms6205_write_data_n, dut->emulData, dut->ms6205_marker);

        sim_time++;
    }
    printw("Emulator Done. sim_time = %d\n", sim_time);
    m_trace->close();
    getch();
    endwin();                    // Выход из curses-режима. Обязательная команда.
    delete dut;
    delete ui;
    exit(EXIT_SUCCESS);
}