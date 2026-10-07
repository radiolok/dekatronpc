// Simulation speed report for the Verilator testbenches: how many hsClk and
// Clk cycles were simulated, how long it took in wall time, and the
// resulting simulated clock rate against the real machine (hsClk = 10 MHz,
// Clk = 1 MHz).
//
// Call hsClkEdge()/clkEdge() on every rising edge the testbench drives (or
// sees), then report() once at the end of the run.

#ifndef SIM_CLOCK_STATS_H
#define SIM_CLOCK_STATS_H

#include <chrono>
#include <cstdint>
#include <cstdio>

class SimClockStats {
public:
    static constexpr double HS_CLK_REAL_HZ = 10e6;
    static constexpr double CLK_REAL_HZ = 1e6;

    SimClockStats() : hsClkCycles(0), clkCycles(0), started(false) {}

    void start() {
        t0 = std::chrono::steady_clock::now();
        started = true;
    }

    void hsClkEdge() { hsClkCycles++; }
    void clkEdge() { clkCycles++; }

    uint64_t hsClk() const { return hsClkCycles; }
    uint64_t clk() const { return clkCycles; }

    double elapsed() const {
        if (!started)
            return 0.0;
        return std::chrono::duration<double>(std::chrono::steady_clock::now() - t0).count();
    }

    // iret: retired instructions, or 0 to skip that line
    void report(FILE* out, uint64_t iret = 0) const {
        double s = elapsed();
        fprintf(out, "Sim speed: wall %.3f s\n", s);
        line(out, "hsClk", hsClkCycles, s, HS_CLK_REAL_HZ);
        line(out, "Clk", clkCycles, s, CLK_REAL_HZ);
        if (iret && s > 0)
            fprintf(out, "  IRET  %12llu insns, %10.1f insn/s\n",
                    static_cast<unsigned long long>(iret), iret / s);
    }

private:
    static void line(FILE* out, const char* name, uint64_t cycles, double s, double realHz) {
        double hz = s > 0 ? cycles / s : 0.0;
        fprintf(out, "  %-5s %12llu cycles, %10.3f kHz simulated (%.4f%% of real %.0f MHz, slowdown %.1fx)\n",
                name, static_cast<unsigned long long>(cycles), hz / 1e3,
                100.0 * hz / realHz, realHz / 1e6, hz > 0 ? realHz / hz : 0.0);
    }

    uint64_t hsClkCycles;
    uint64_t clkCycles;
    bool started;
    std::chrono::steady_clock::time_point t0;
};

#endif
