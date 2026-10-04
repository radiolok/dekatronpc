0. Working rules (from the project owner)
Record every investigation as Markdown. Put new reports in doc/, or extend the existing report next to the RTL it covers (e.g. rtl/DekatronPC/emulator_inspection.md, rtl/DekatronPC/Dekatron/DekatronCounter.md). Don't leave results only in chat.
Append to history.md every session. Add one bullet of 1–2 sentences saying what the session did. Example: - Ran DekatronCounter in Verilator, fixed the UNOPTFLAT loop, saved doc/DekatronCounter_sim_report.md.
Keep this file and the TRS current. When the user brings new data (measurements, schematics, documents, tools) or a finding changes a fact, update the relevant section here. Record requirement status changes in TRS.md (repo root; the version lives in its header and §1, not in the file name), and list any new report in the §6 repo map.
Ask when unsure. If you are not sure about an idea, interpretation or direction, ask the user instead of deciding on your own. This especially applies to the OPEN-* items in §8.
Take care of machine resources. The project may run on small nodes. Prefer light tools (single cocotb targets on Icarus, Python models, Verilator --lint-only) over heavy ones (full DekatronPC/Emulator Verilator builds, make regression, Quartus or Yosys synthesis). Ask the user before starting any long-running heavy job.

1. Source of truth
The requirements spec is TRS.md in the repo root (Russian, v0.9, draft, 2026-10-04; earlier editions are in git history). Microarchitecture block diagrams are in SCHEMES.md (images in img/schemes/, generated, not hand-edited). Every requirement has a stable ID (REQ-*, OPEN-*) and a status: TODO / In Progress / In Review / Assumption / Done / Rejected. Cite IDs in commits, reports and code comments. When work changes a requirement's status, update the TRS (new version tag like [v0.10]) rather than only this file. Sections 19 (checklist), 21 (Definition of Done) and 22 (next actions) are the live to-do list.
Names in the TRS don't always match the tree: the TRS says Ram.sv, the file is rtl/DekatronPC/RAM.sv. Check the tree before trusting a path.

2. What the project is
A Brainfuck computer built from A110 dekatrons and vacuum tubes, plus an FPGA emulator (DE0-Nano-SoC, Cyclone V) that stands in for tube blocks that aren't built yet.
- Authenticity (REQ-AUTH-*): no silicon semiconductors in the real machine's compute path; germanium diodes allowed in power, ferrite-memory support and BCD/HEX codecs. FPGA is a temporary dev tool only. UART/terminals/loaders are external and may be non-tube.
- Priorities (REQ-SCOPE-003): RTL, then test stand, then tube modules, then measurements/liberty. The P&R tool is a separate project that takes netlist/liberty/connector requirements from the TRS (section 17).

3. Architecture facts (don't break these)
- Four reversible BCD dekatron counters, Harvard architecture. Widths come from rtl/parameters.sv:
  - IP: 5 dekatrons, 0–99999 (100k instructions). The old PDF's 6 dekatrons / 1M is obsolete (REQ-ARCH-009).
  - Loop: 2 dekatrons, 0–99 by TRS v0.9 (REQ-CNT-002, chosen on the Brainfuck-100 set: max nesting during scan is 67). rtl/parameters.sv still says 3; changing it is pending. Overflow is a hardware error: it must abort the loop scan and halt the machine, or the machine hangs (REQ-CNT-007).
  - AP: 5 dekatrons physically, BF limit 0–29999. The choice between 29999 and 99999 stays a parameter until RTL freeze (OPEN-001).
  - Data: 3 dekatrons, 0–255, 12-bit BCD out.
- Program memory: 100k × 4-bit opcodes. Data memory: 30k × 10-bit cells encoded {hundreds[1:0], tens[3:0], ones[3:0]}; on read, the top 2 hundreds bits come back as 2'b00.
- Memory is a recursive bank tree (bank of 10×10 = 2 dekatrons, then groups of 10, and so on). Addresses are raw BCD tetrads compared directly, with no BCD-to-binary arithmetic; tetrads A..F raise err. The bootloader is the top 10×10 bank, 99900–99999, write-protected, overlaid with ovl_hit/ovl_data inputs.
- OPEN-015: the bank tree doesn't fit Cyclone V (about 1000 banks against about 550 M10K blocks). A flat memory with the same interface is needed for the FPGA build.
- Clocks: Clk = 1 MHz CPU clock; hsClk = 10 MHz models dekatron pulse timing (emulator only, not in the real machine). Everything else is emulator/peripheral.

4. ISA (opcodes are near-final: never renumber existing codes)
Decode on the pair {insn_mode, insn}. All 32 combinations must be covered. Undefined or reserved opcodes act as NOP and never raise an error.
| Op | Debug ISA (mode 0) | Brainfuck ISA (mode 1) |
|---|---|---|
| 0x0 | NOP | NOP |
| 0x1 | HALT | HALT |
| 0x2 | BELL | INC + |
| 0x3 | reserved (NOP) | DEC - |
| 0x4 | EOT (end of load; NOP outside load mode) | AINC > |
| 0x5 | SOT (start of load) | ADEC < |
| 0x6 | LABEG { (skip if AP==0) | LBEG [ (skip if data==0) |
| 0x7 | LAEND } (repeat if AP!=0) | LEND ] (repeat if data!=0) |
| 0x8 | CLRL | COUT . |
| 0x9 | CLRI (IP and MemLock) | CIN , |
| 0xA | CLRD | CLRD [-] (sets MemLock) |
| 0xB | CLRA (AP and MemLock) | CLRML (flush and clear MemLock) |
| 0xC | HRST | LOAD |
| 0xD | SRST | STORE |
| 0xE | ISA0 (to Debug) | ISA0 |
| 0xF | ISA1 (to BF) | ISA1 |
- The table above matches MachineCtrl.sv, which decodes literal {mode, opcode} values. rtl/DekatronPC/insnValues.sv is stale: it has no BELL and no 0x0C, and it names 0x0D INSN_RST. Only the old InsnDecoder uses it.
- Debug loops test AP; BF loops test Data. Bracket opcodes 0x6/0x7 are the same in both ISAs, so a single detector is enough.
- Hard Reset: IP=99900, AP/Data/Loop=0, MemLock cleared, Debug ISA; runs the bootloader if RunOnHardRst is set. Soft Reset: all counters 0, MemLock cleared, BF ISA; runs from 0 if RunOnSoftRst is set.
- SOT/EOT: after SOT the machine accepts opcodes via InsnIn/InsnInValid/InsnInReady and auto-increments IP. With SoftRstOnEOT set, EOT triggers a Soft Reset.
- IpLine only ever sees opcodes, never ASCII symbols. Conversion belongs to the loader, and any verification model must follow the same rule (REQ-IPV2-005).

5. RTL design rules
- Handshake: Valid/Ready everywhere above the dekatron, and ready must not depend on valid. APB was tried and rejected in v0.7. Don't reintroduce single-cycle pulse Request/Ready.
- Dekatron physics (REQ-DEK-012/015/016): the tube has no valid/ready/busy. It reacts to pulses of a given length regardless of its state. A discharge can't rest on a guide cathode: it falls back from guide A and forward from guide B. A reading is valid only on a main cathode with no stimulus (Valid: OR10_X7 tube cell under SYNTH, |MainOneHot in simulation; OneHotValid is gone). All discipline lives in DekatronCounter.
- Dekatron stack under rtl/DekatronPC/Dekatron/:
  - DekatronTubeV2: a 30-bit one-hot ring model, not an FSM.
  - DekatronModule wraps it with gate-level codecs. Codecs are placed only for WRITE/READ, and sub-blocks stay separate instances so P&R can swap them for tube cells.
  - DekatronCounter is the first Valid/Ready level.
  - DekatronPhaseGen splits the clock into thirds (guide A, guide B, fall) so the tube can count every cycle at 1 MHz.
  - DekatronPulseSender is pure combinational logic, with one phase generator per counter.
- Timing parameters must be explicit: GUIDE_STEP_HS, FALL_STEP_HS, GUIDE_MAX_HS, WRITE_MIN_HS, RESET_MIN_HS. The current values are estimates until they're calibrated on hardware (OPEN-013/014). The write window must be longer than one count cycle; this is checked at compile time.
- soft_rst/hard_rst are physical lines. An external time relay holds them, so don't add stretch logic in RTL. rst_n resets logic only and never moves a discharge. MachineCtrl must react to reset lines from the panel, not only to its own HRST/SRST requests.
- ApLine uses lazy reads (about 36% fewer memory accesses on pi.bfk). The memory's rd_data register holds the last touched cell (write-through), so ApLine keeps only lock/dirty/mem_here and never stores a copy of the cell. It writes back only when dirty. Before [ or ] in BF mode MachineCtrl issues TEST; in Debug mode it doesn't.
- MemLock:
  - Set before the first +/-.
  - Flushed on >/< before the AP step.
  - LOAD/STORE don't touch it.
  - CLRD sets it; without that, [-] doesn't clear the cell.
  - CLRML flushes the counter to memory, then clears MemLock.
- Loop scan runs entirely inside IpLine and stops on the matching bracket, not after it.
- Synthesizable constructs only. No X-masking tricks. FPGA-specific primitives go only in the Emulator layer, above DekatronPC. The code style is SystemVerilog; BcdToBin.v/BinToBcd.v are legacy Verilog-95.
- Combinational loops: treat Verilator UNOPTFLAT as an error and fix it structurally, never with lint_off. A ripple written bit-by-bit into a vector that is also read counts as a false loop: use locals inside always_comb. A model check isn't a simulator check: Python cycle models can't see zero-delay loops (REQ-VER-029/031/032).
- Emulator to DekatronPC interface: frozen by TRS Appendix B (instantiated in rtl/Emulator/Emulator.sv). Any change is a breaking change: update the TRS and io_key_display_block/MS6205/Sequencer together.

6. Repo map
- rtl/DekatronPC/: core. DekatronPC.sv, MachineCtrl.sv, IpLine.sv, ApLine.sv, IpMemory.sv, RAM.sv, insnValues.sv, De0Nano.sv (FPGA top).
- rtl/DekatronPC/Dekatron/: the dekatron subsystem (see §5).
- rtl/Emulator/: FPGA-only layer: keyboard, MS6205, IN-12 Sequencer, consul (legacy, to be dropped), FirmwareLoader, io_register_block (temporary until LVDS boards exist).
- rtl/Logic/, rtl/Functions/: primitives and codecs.
- rtl/uart/: 110 baud, 7N1, hardcoded.
- rtl/[DEPRECATED]/: don't touch.
- rtl/programs/: *.bfk test programs (helloworld, pi, rot13, …) and the bootloader.
- rtl/quartus/: Quartus project.
- rtl/run/: run_tests.sh, synthesis and emulator scripts.
- tb/: cocotb + pyuvm testbench, see tb/README.md.
- bfutils/programs/bf100/: the Brainfuck-100 set (100 real programs by category, inputs, metrics, sources and licenses). Any counter width change is checked against it (REQ-ARCH-011).
- bfutils/: git submodule (github.com/radiolok/bfutils), the C++ model of BrainfuckPC, built with CMake: bfpp compiler, bfrun emulator, and dpcrun, the DekatronPC golden model (REQ-GM-*). bfutils/dpcrun/dpcrun.h + dpcrun.cpp (dpc::Machine, full ISA; mirrors the RTL as-is by owner decision) is the only copy; unit tests in bfutils/dpcrun/test run in bfutils' own GitHub Actions (cmake + ctest). rtl/run/run_tests.sh builds it into libdpcrun.a and links it into the Verilator testbench rtl/tests/DekatronPC.sv/DekatronPC_tb.cpp for step-by-step comparison. Change the model in the submodule, not in this repo. After cloning, run git submodule update --init.
- TRS.md, SCHEMES.md, README.md: requirements, block diagrams, project overview (repo root).
- doc/: reference literature (PDF/djvu) and new investigation reports.
- Reports: rtl/DekatronPC/emulator_inspection.md (Emulator layer), rtl/DekatronPC/Dekatron/DekatronCounter.md (counter design), doc/dpcrun_golden_model.md (golden model semantics, RTL-vs-TRS divergences, RTL findings).
- Old blocks still in the tree and due for removal (TRS 19.4): Dekatron.sv, DekatronPulseAllow, DekatronCarrySignal, RsLatch uses, InsnDecoder, BcdToBinEnc in the memory path. Several tb/Makefile targets still build against them.

7. Build and test (CI: .github/workflows/docker-image.yml, all inside the Docker image from ./Dockerfile)
- cocotb regression: cd tb && make regression (or a single target: make test_compare SIM=icarus). Module tests run on Icarus; DPC/Emulator integration runs on Verilator.
- RTL simulation: cd rtl/run && ./run_tests.sh -t
- Synthesis: cd rtl/run && ./run_tests.sh -s (Yosys with -define SYNTH=1 and rtl/vtube/vtube_cells.lib; Ram is stubbed under SYNTH because the recursive RamGroup loops hierarchy -check, so the tube count excludes memory)
- Resource note (§0): full-design Verilator builds and Quartus runs are heavy. Ask before starting them on small nodes and prefer single tb targets.

8. Open decisions (ask the user; don't decide these yourself)
- OPEN-001: AP limit, 29999 or 99999.
- OPEN-003: does SOT switch ISA? The current RTL behaviour is only an assumption.
- OPEN-004: how the bootloader ends.
- OPEN-007: BELL behaviour.
- OPEN-009: HRST/SRST opcode cross-check.
- OPEN-011: hardcoded panel switches (RunOnHardRst=0, RunOnSoftRst=0, SoftRstOnEOT=1, EchoMode=1).
- OPEN-012: TOP_LIMIT_MODE vs HARD_RST_D_CNT.
- OPEN-013/014: dekatron timing calibration and whether 1 MHz is achievable.
- OPEN-015: flat FPGA memory.
- OPEN-018: single-master memory invariant.

9. Current priorities (TRS §22)
1. Run all new RTL in Verilator and Icarus. Most blocks so far are verified only on Python models.
2. Write testbenches for RAM/IpMemory, ApLine (MemLock, lazy read, dirty), IpLine (scan, overflow), MachineCtrl (full ISA table, TEST before brackets), plus DekatronModule/DekatronCounter and back-to-back write/reset ops (REQ-VER-028/030).
3. Flat memory for the FPGA build (OPEN-015).
4. Remove the old modules so there's one datapath.
5. Use the C++ golden model (bfutils/dpcrun, full ISA since TRS v0.8) for step-by-step comparison with the RTL: first fix the COUT defect (OPEN-017 reopened, MachineCtrl never issues AP_COUT), then build DekatronPC_tb.cpp and run it with -s.
6. Bring the RTL in line with TRS v0.9: LOOP_DEKATRON_NUM = 2, reset lock in ApLine on any address step (also when not dirty, after STORE), cout_pending in MachineCtrl. The ApLine and MachineCtrl fixes are prepared but not merged; ask the owner before applying.
