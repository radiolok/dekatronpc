#include <stdlib.h>
#include <iostream>
#include <stdio.h>
#include <ctype.h>
#include <mutex>
#include <thread>
#include <curses.h>
#include <verilated.h>
#include "verilated_vpi.h"
#include <verilated_vcd_c.h>
#include "VEmulator.h"


#define MAX_SIM_TIME 60000000
#define DIGITS 9

#define SIM_TRACE

std::atomic<bool> toExit(false);
std::atomic<bool> toUpdate(false);
std::mutex keyUpdateMutex;
vluint64_t sim_time = 0;

uint8_t In12CathodeToPin[] = {1,0,2,3,6,8,9,7,5,4};

#define EXIT 0xFF

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
        keyboardWrOld = 0;
        for (uint8_t i = 0; i < 7; i++)
        {
            KeypadRaw[i] = 0x00;
        }
        for (uint8_t i = 0; i < 160; i++)
        {
            ms6205ram[i] = ' ';
        }
        printInit();
    }

    ~UI()
    {
    }

    uint8_t Cout(bool state, uint16_t data)
    {
        uint8_t update = 0;
        if (!CoutOld & state){
            uint16_t symbol = (data&0x0F) + ((data>>4) &0x0F)*10 + ((data>>8) &0x0F)*100;
            coutSymbols.push_back(symbol);
            update = 1;
        }
        CoutOld = state;
        return update;
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
            {
                std::lock_guard<std::mutex> lk(keyUpdateMutex);
                dataOut = KeypadRaw[idx];
                KeypadRaw[idx] = 0;
            }
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
    uint8_t in12AnodeUpdate(bool state, uint8_t data)
    {
        uint8_t status = 0;
        if (state & !in12anodeWrOld)
        {
            in12AnodeNum = data & 0x0F;
            if (!in12AnodeNum)
                status = 1;
        }
        in12anodeWrOld = state;
        return status;
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

    void printInit()
    {
        init_color(COLOR_WHITE, 190,190,190);
        init_pair(1, COLOR_RED, COLOR_WHITE);
        init_pair(2, COLOR_GREEN, COLOR_WHITE);
        init_pair(3, COLOR_RED, COLOR_WHITE);
    }

    void keyPressed(uint8_t keyCode)
    {
        std::lock_guard<std::mutex> lk(keyUpdateMutex);
        uint8_t keyRow = 1<<(keyCode % 5);
        KeypadRaw[keyCode / 5] = keyRow;
    }

    void keyControl()
    {
        while(true){
            int ch = getch();
            toUpdate = true;
            if (ch == 'q')
            {
                toExit = true;
                break;
            }
            switch(ch){
                case 'h'://step
                    keyPressed(26);//KEYBOARD_HALT_KEY =  26,
                break;
                case 's'://KEYBOARD_STEP_KEY =  33,
                    keyPressed(33);
                break;
                case 'r'://KEYBOARD_RUN_KEY =  28,
                    keyPressed(28);
                break;
                case KEY_NPAGE: keyPressed(36); break;//KEYBOARD_INC_KEY
                case KEY_PPAGE: keyPressed(31); break;//KEYBOARD_DEC_KEY
                default:
                break;
            }
            std::this_thread::sleep_for(std::chrono::milliseconds(10));
        }
    }

    void printHeader()
    {
        mvprintw(0,0, "DekatronPC Virtual HDL Emulator");
    }

    void printFooter(const VEmulator *dut)
    {
        std::string status = "RUN";
        if (dut->DPC_currentState == 0x04)
            status = "HALT";
        mvprintw(LINES-1,0, "Quit, Halt, Run, Step. Status: %s", status.c_str());
        mvprintw(LINES-2,0, "IpAddr: %x  ApAddr: %x", dut->IpAddress, dut->ApAddress);
    }

    void printMs6205()
    {
        for (uint8_t r = 0; r < 10; r++)
        {
            move(LINES/4-5+r, COLS/4-8);
            for(uint8_t c = 0; c< 16; c++)
            {
                printw("%c", ms6205ram[r*16+c]);
            }
        }
    }

    void printIn12()
    {
        int row = LINES/4-1;
        int col = COLS/2;
        mvprintw(row,col+2, "IP: ");
        for (uint8_t i = 8; i > 2; i--)
            printw("%c", in12High[i]);
        mvprintw(row+1,col+2, "AP: ");
        for (uint8_t i = 8; i > 3; i--)
            printw("%c", in12Low[i]);
        mvprintw(row,col+15, "Loop: ");
        for (uint8_t i = 2; i < 10; i--)
            printw("%c", in12High[i]);
        mvprintw(row+1,col+15, "Data: ");
        for (uint8_t i = 2; i < 10; i--)
            printw("%c", in12Low[i]);
    }
    void updateScreen(const VEmulator *dut)
    {
	    printHeader();
        printMs6205();
        printIn12();

        mvprintw(LINES/2,2, "COUT: ");
        for (char c: coutSymbols)
        {
            printw("%c", c);
        }
        printFooter(dut);
        refresh();
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

    std::vector<char> coutSymbols;
};

int main(int argc, char** argv, char** env) {
    VEmulator *dut = new VEmulator;
    UI *ui = new UI;
    Verilated::traceEverOn(true);
#ifdef SIM_COV
    Verilated::mkdir("logs");
    VerilatedCov::write("logs/Emulator.dat");
#endif
#ifdef SIM_TRACE
    VerilatedVcdC *m_trace = new VerilatedVcdC;
    dut->trace(m_trace, 5);
    m_trace->open("Emulator.vcd");
#endif
    dut->KEY = 1;
    dut->FPGA_CLK_50 = 0;
    initscr();
    start_color();   

    std::thread keyControl(&UI::keyControl, ui);
    
    while (true) {
        if (toExit)
            break;
        dut->FPGA_CLK_50 ^= 1;
        if (sim_time == 1){
            dut->KEY = 0;
        }
        if (sim_time == 4){
            dut->KEY = 1;
        }
        dut->eval();
    #ifdef SIM_TRACE
        m_trace->dump(sim_time);
    #endif

        uint8_t needUpdate = 0;
        needUpdate += ui->Cout(dut->Cout, dut->Data);
        if (needUpdate)
        {
            dut->CioAcq = 1;
        }
        if (!dut->Cout){
            dut->CioAcq = 0;
        }
        ui->keyboardUpdate(dut->keyboard_write, dut->emulData, dut->keyboard_data_in);
        needUpdate += ui->in12AnodeUpdate(dut->in12_write_anode, dut->emulData);
        ui->in12CathodeUpdate(dut->in12_write_cathode, dut->emulData);
        if (needUpdate | toUpdate)
        {
            ui->updateScreen(dut);
            toUpdate = false;
        }
        dut->ms6205_ready = ui->ms6205UpdateAddr(dut->ms6205_write_addr_n, dut->emulData, dut->ms6205_marker);
        dut->ms6205_ready = ui->ms6205UpdateData(dut->ms6205_write_data_n, dut->emulData, dut->ms6205_marker);

        sim_time++;
    }
    mvprintw(20,0, "Emulator Done. sim_time = %d\n", sim_time);
#ifdef SIM_TRACE
    m_trace->close();
#endif
    keyControl.join();
    endwin();
    delete dut;
    delete ui;
    exit(EXIT_SUCCESS);
}