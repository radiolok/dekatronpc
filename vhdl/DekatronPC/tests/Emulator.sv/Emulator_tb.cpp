#include <stdlib.h>
#include <iostream>
#include <stdio.h>
#include <ctype.h>
#include <mutex>
#include <thread>
#include <chrono>
#include <curses.h>
#include <verilated.h>
#include "verilated_vpi.h"
#include <verilated_vcd_c.h>
#include "VEmulator.h"


#define MAX_SIM_TIME 600000000
#define DIGITS 9

#define SIM_TRACE

std::atomic<bool> toExit(false);
std::atomic<bool> toUpdate(false);

std::atomic<bool> cinReq(false);
std::atomic<bool> cioAcq(false);
std::atomic<char> cinSymbol(0);

std::mutex keyUpdateMutex;
vluint64_t sim_time = 0;

uint8_t In12CathodeToPin[] = {1,0,2,3,6,8,9,7,5,4};

const char* dpcStatus[] = {"NONE", "IDLE", "RUN", "RUN", "HALT", "CIN", "COUT", "CIO_ACQ"};

#define EXIT 0xFF

class Consul{
public:
    Consul() : symbols_on_line(0), set_kb_block(0),
        set_tab(0), need_nl(0), block_print(0),
        is_moving(0), high_reg(0), coAcq(0), red_print(0),
        top_symbol_correction(0), cin_ready(0),
        ecc(0), inchar(0), sync(0), outchar(0)
    {
    }

    ~Consul(){

    }
    
    bool ioConnect(vluint64_t time, uint8_t Rout, uint8_t Lout, uint8_t& Rin, uint8_t& Lin){
        bool update = false;
        outchar = Lout & 0x7F;

        sync = (Lout >> 7) & 0x01;

        set_tab = (Rout & 0x01);
        set_kb_block = (Rout >> 1) & 0x01;
        ctime = time;

        Lin = (ecc << 7) | inchar & 0x07F;
        Rin = (cin_ready << 7) |
            (top_symbol_correction << 6)|
            (red_print << 5) |
            (coAcq << 4) |
            (high_reg << 3) |
            (is_moving << 2) |
            (block_print << 1) |
            need_nl;
        return update;
    }

    void waitMs(uint8_t ms){
        vluint64_t waittime = ctime + 100*ms;
        while (ctime < waittime)
        {
            std::this_thread::sleep_for(std::chrono::milliseconds(10));
        }
    }

    void printChar(){
        while(true){
            if (sync){
                char char_to_print = outchar;
                switch(char_to_print){
                    case 0x0e:
                        high_reg = 1;
                        waitMs(6);
                        break;
                    case 0x0f:
                        high_reg = 0;
                        waitMs(6);
                        break;
                    case 0x11:
                        red_print = 1;
                        waitMs(6);
                        break;
                    case 0x12:
                        red_print = 0;
                        waitMs(6);
                        break;
                    default:
                        waitMs(1);
                        block_print = 1;
                        waitMs(6);                        
                        mvprintw(20,0, "%c", char_to_print);
                        coAcq = 1;
                        break;
                }               
            }
            else{
                waitMs(6);
                block_print = 0;
                coAcq = 0;
            }
        }
    }

    uint8_t getChar(){
        uint8_t symbol;

        return symbol;
    }
private:
    volatile uint8_t outchar;
    volatile uint8_t sync;
    volatile uint8_t inchar;
    volatile uint8_t ecc;
    volatile uint8_t cin_ready;
    volatile uint8_t top_symbol_correction;
    volatile uint8_t red_print;
    volatile uint8_t coAcq;
    volatile uint8_t high_reg;
    volatile uint8_t is_moving;
    volatile uint8_t block_print;
    volatile uint8_t need_nl;
    volatile uint8_t set_tab;
    volatile uint8_t set_kb_block;
    volatile uint8_t symbols_on_line;

    volatile vluint64_t ctime;
};

class ioRegs{
public:
    ioRegs(){
        memset(inputRegs, 0, sizeof(inputRegs));
        memset(outputRegs, 0, sizeof(outputRegs));
    }

    ~ioRegs(){

    }
    //return true if dataOut is updated
    bool update(uint8_t en_n, uint8_t addr, uint8_t data, uint8_t& dataOut){
        en_n = (~en_n) & 0x03;
        uint8_t reg = (en_n - 1) * 8 + (addr & 0x07);
        
        if(reg < 16){
            if ((addr >> 3) & 0x01){//write
                outputRegs[reg] = data;
                return false;
            } else {//read
                dataOut = inputRegs[reg];
                return true;
            }
        }
        return false;

    }

    uint8_t read(uint8_t addr){
        return (addr < 16) ? outputRegs[addr] : (addr < 32) ? inputRegs[addr] : 0;
    }
    
    void write(uint8_t addr, const uint8_t& data){
        if (addr < 16 ){
            inputRegs[addr] = data;
        }
    }
private:
    uint8_t inputRegs[16];
    uint8_t outputRegs[16];
};

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
        for (uint8_t i = 0; i < 8; i++)
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
            if (idx < 8)
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
            in12Low[in12AnodeNum]  = In12CathodeToPin[(data & 0x0F)] + 0x30;
            in12High[in12AnodeNum] = In12CathodeToPin[((data >> 4) & 0x0F)] + 0x30;
        }
        in12cathodeWrOld = state;
        
    }
    uint8_t in12AnodeUpdate(bool state, uint8_t data)
    {
        uint8_t status = 0;
        if (state & !in12anodeWrOld)
        {
            in12AnodeNum = data & 0x0F;
            //if (!in12AnodeNum)
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
            ms6205ram[ms6205addr] = (0xFF - data) & 0x7F;
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
        toUpdate = true;
    }
    void keyControl()
    {
        static int ch_old;
        while(true){
            
            int ch = getch();
            if (ch == KEY_END)
            {
                toExit = true;
                break;
            }
            switch(ch){
                case KEY_F(1)://step
                    keyPressed(26);//KEYBOARD_HALT_KEY =  26,
                break;
                case KEY_F(2)://KEYBOARD_STEP_KEY =  33,
                    keyPressed(33);
                break;
                case KEY_F(3)://KEYBOARD_RUN_KEY =  28,
                    keyPressed(28);
                break;
                case KEY_F(5):
                    keyPressed(15);// KEYBOARD_IRAM_KEY =  15,
                break;
                case KEY_F(6):
                    keyPressed(10);//KEYBOARD_DRAM_KEY =  10,
                break;
                case KEY_F(7):
                    keyPressed(0);//KEYBOARD_CIO_KEY =  0,
                break;
                case KEY_F(9)://KEYBOARD_SOFT_RST_KEY  = 38,
                    keyPressed(38);
                break;
                case KEY_F(10)://KEYBOARD_HARD_RST =   37,
                    keyPressed(37);
                break;
                case KEY_NPAGE: keyPressed(36); break;//KEYBOARD_INC_KEY
                case KEY_PPAGE: keyPressed(31); break;//KEYBOARD_DEC_KEY
                default:
                break;
            }
            if (ch < 256 & cinReq){
                cioAcq = true;
                cinSymbol = ch;
            }
            ch_old = ch;
        }
    }

    void printHeader(const VEmulator *dut)
    {
        mvprintw(0,0, "DekatronPC Virtual HDL Emulator");
        mvprintw(1,0, "Status: %s      ", dpcStatus[dut->DPC_currentState]);
    }

    void printFooter(const VEmulator *dut)
    {
        std::string status = "RUN";
        if (dut->DPC_currentState == 0x04)
            status = "HALT";
        mvprintw(LINES-1,0, "Quit(END), F1: HALT, F2: STEP, F3: RUN, F5: IRAM, F6: DRAM, F7: CIO, F9: Soft RST, F10: Hard Rst");
        mvprintw(LINES-2,0, "IpAddr: %x  Loop: %x ApAddr: %x  Data: %x", dut->IpAddress, dut->LoopCount, dut->ApAddress, dut->DPC_DataOut);
    }

    void rectangle(int y1, int x1, int y2, int x2)
    {
        mvhline(y1, x1, 0, x2-x1);
        mvhline(y2, x1, 0, x2-x1);
        mvvline(y1, x1, 0, y2-y1);
        mvvline(y1, x2, 0, y2-y1);
        mvaddch(y1, x1, ACS_ULCORNER);
        mvaddch(y2, x1, ACS_LLCORNER);
        mvaddch(y1, x2, ACS_URCORNER);
        mvaddch(y2, x2, ACS_LRCORNER);
    }

    void printMs6205()
    {
        for (uint8_t r = 0; r < 10; r++)
        {
            move(LINES/4-5+r, COLS/4-8);
            for(uint8_t c = 0; c< 16; c++)
            {
                mvprintw(LINES/4-5+r, COLS/4-8+c,"%c", ms6205ram[r*16+c]);
            }
        }
        rectangle(LINES/4-6, COLS/4-9, LINES/4+6, COLS/4+9);
    }

    void printIn12()
    {
        int row = LINES/4-1;
        int col = COLS/2;
        mvprintw(row,col+2, "IP: ");
        for (uint8_t i = 7; i > 1; i--)
            printw("%c", in12High[i]);
        mvprintw(row+1,col+2, "AP: ");
        for (uint8_t i = 8; i > 3; i--)
            printw("%c", in12Low[i]);
        mvprintw(row,col+16, "Loop: ");
        for (uint8_t i = 1; i < 10; i--)
            printw("%c", in12High[i]);
        mvprintw(row+1,col+15, "Data: ");
        for (uint8_t i = 2; i < 10; i--)
            printw("%c", in12Low[i]);
    }
    void updateScreen(const VEmulator *dut)
    {
	    printHeader(dut);
        printMs6205();
        printIn12();

        printFooter(dut);
        refresh();
    }

private:
    uint8_t KeyCurrentRows;
    uint8_t KeypadRaw[8];

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
};

uint8_t Cin(bool state, uint8_t& symbol)
{
    static bool CinOld = false;
    uint8_t update = 0;
    if (!CinOld & state){
        cinReq = true;
    }
    if (cioAcq){
        cinReq = false;
        cioAcq = false;
        update = 1;
        symbol = cinSymbol;
    }
    CinOld = state;
    return update;
}

int main(int argc, char** argv, char** env) {
    VEmulator *dut = new VEmulator;
    UI *ui = new UI;
    ioRegs *ioregs = new ioRegs;
    Consul *consul = new Consul;
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
    keypad(stdscr, TRUE);
    start_color();
    std::thread keyControl(&UI::keyControl, ui);
    std::thread ConsulPrint(&Consul::printChar, consul);
    std::thread ConsulGet(&Consul::getChar, consul);
    uint8_t io_regs_out = 0;
    uint8_t consulLin, consulRin;

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
        if (sim_time < MAX_SIM_TIME)
            m_trace->dump(sim_time);
    #endif

        if(ioregs->update(dut->io_enable_n, dut->io_address, dut->io_data, io_regs_out))
        {
            dut->io_data = io_regs_out;
        }
        
        for(uint8_t c = 0; c< 16; c++)
        {
            mvprintw(3+c, 0,"%x", ioregs->read(c));
            mvprintw(3+c, 5,"%x", ioregs->read(c+16));
        }
        consul->ioConnect(sim_time, ioregs->read(1),ioregs->read(0), consulRin, consulLin);
        ioregs->write(1, consulRin);
        ioregs->write(0, consulLin);
        uint8_t needUpdate = 0;
        ui->keyboardUpdate(dut->keyboard_write, dut->emulData, dut->keyboard_data_in);
        needUpdate += ui->in12AnodeUpdate(dut->in12_write_anode, dut->emulData);
        ui->in12CathodeUpdate(dut->in12_write_cathode, dut->emulData);
        if (needUpdate | toUpdate)
        {
            ui->updateScreen(dut);
            if (toUpdate){
                toUpdate = false;
            }
        }
        dut->ms6205_ready = ui->ms6205UpdateAddr(dut->ms6205_write_addr_n, dut->emulData, dut->ms6205_marker);
        dut->ms6205_ready = ui->ms6205UpdateData(dut->ms6205_write_data_n, dut->emulData, dut->ms6205_marker);

        sim_time++;
    }
    mvprintw(20,0, "Emulator Done. sim_time = %ld\n", sim_time);
#ifdef SIM_TRACE
    m_trace->close();
#endif
    keyControl.join();
    endwin();
    delete dut;
    delete ui;
    delete ioregs;
    delete consul;
    exit(EXIT_SUCCESS);
}