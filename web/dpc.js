/* DekatronPC web simulator: machine model.
 *
 * Instruction-level model of DekatronPC, a line-by-line JavaScript port of the
 * golden model bfutils/dpcrun (dpcrun.h, dpcrun.cpp): one 4-bit instruction
 * set (ISA16, doc/isa16.md) without modes, IP 4 dekatrons (0..9999), AP 3
 * dekatrons (0..999, wraps 0 <-> 999), Loop 2, Data 3 (0..255). Like dpcrun
 * it mirrors the RTL as it is (doc/dpcrun_golden_model.md §4).
 *
 * Differences from dpcrun, all outside the instruction semantics:
 *  - The bootloader ROM holds rtl/programs/bootloader.bfk (0<{0<}NNNS) from
 *    power-on: it clears the data memory and loads from address 0. dpcrun
 *    has an empty ROM unless -b.
 *  - Panel keys that dpcrun has no API for: haltKey(), loadingStop(),
 *    nextIp()/prevIp() (manual IP move while halted), and manualStep(),
 *    the page's INC/DEC keys on a counter picked by the counter selector
 *    (a simulator extension: the RTL has keys for IP only).
 *  - assemble() knows two dialects and comments, see below.
 *
 * Copyright (c) 2016-2026, Artem Kashkanov. BSD-2-Clause, see dpcrun.cpp.
 */
(function (root) {
  'use strict';

  const IP_SIZE = 10000, BOOT_BASE = 9990, BOOT_SIZE = 10;
  const AP_SIZE = 1000, LOOP_SIZE = 100, DATA_TOP = 255;
  const PH_FETCH = 0, PH_INSN = 1, PH_CIN = 2;
  const OK = 'Ok', HALTED = 'Halted', WAIT = 'WaitInput';

  // ISA16 opcodes (never renumber, AGENTS.md §3)
  const OP = {
    NOP: 0x0, HALT: 0x1, INC: 0x2, DEC: 0x3, AINC: 0x4, ADEC: 0x5, LBEG: 0x6, LEND: 0x7,
    COUT: 0x8, CIN: 0x9, CLRD: 0xA, LD: 0xB, CLRA: 0xC, MEMLOCK: 0xD, LABEG: 0xE, LAEND: 0xF
  };
  const isLoopOpen = (op) => (op & 0x7) === 0x6;
  const isLoopClose = (op) => (op & 0x7) === 0x7;

  //--------------------------------------------------------------------
  // Loader: text -> opcodes. Same table as rtl/run/generate_rom.py and
  // dpc::symbolToOpcode(). S and E are both LD: SOT in a program, EOT in
  // the load stream.
  //--------------------------------------------------------------------
  const SYMBOLS = {
    'N': 0x0, 'H': 0x1, '+': 0x2, '-': 0x3, '>': 0x4, '<': 0x5, '[': 0x6, ']': 0x7,
    '.': 0x8, ',': 0x9, '0': 0xA, 'S': 0xB, 'E': 0xB, 'A': 0xC, 'P': 0xD, '{': 0xE, '}': 0xF
  };
  const BF_ONLY = { '+': 0x2, '-': 0x3, '>': 0x4, '<': 0x5, '[': 0x6, ']': 0x7, '.': 0x8, ',': 0x9 };

  // rtl/programs/bootloader.bfk
  const BOOTLOADER = '0<{0<}NNNS';

  // Removes comments of the DekatronPC dialect: "// ...", "; ...", "# ..."
  // to the end of the line and "/* ... */" blocks.
  function stripComments(src) {
    let out = '';
    for (let i = 0; i < src.length; i++) {
      const c = src[i], n = src[i + 1];
      if (c === '/' && n === '*') {
        const end = src.indexOf('*/', i + 2);
        if (end < 0) break;
        i = end + 1;
      } else if ((c === '/' && n === '/') || c === ';' || c === '#') {
        const end = src.indexOf('\n', i);
        if (end < 0) break;
        i = end - 1;
      } else {
        out += c;
      }
    }
    return out;
  }

  // dialect 'bf': only the eight Brainfuck commands, everything else is a
  // comment. dialect 'dpc': the full DekatronPC table with comments.
  function assemble(src, dialect) {
    const out = [];
    if (dialect === 'dpc') {
      for (const c of stripComments(src)) {
        const op = SYMBOLS[c];
        if (op !== undefined) out.push(op);
      }
    } else {
      for (const c of src) {
        const op = BF_ONLY[c];
        if (op !== undefined) out.push(op);
      }
    }
    return out;
  }

  // dpc::opcodeToSymbol() and dpc::mnemonic()
  const SYM = 'NH+-><[].,0SAP{}';
  const MN = ['NOP', 'HALT', 'INC', 'DEC', 'AINC', 'ADEC', 'LBEG', 'LEND',
    'COUT', 'CIN', 'CLRD', 'LD', 'CLRA', 'MEMLOCK', 'LABEG', 'LAEND'];
  const symbol = (op) => SYM[op & 15];
  const mnemonic = (op) => MN[op & 15];

  // Opcodes sent over InsnIn for a program: the program, then HALT and LD
  // (EOT) unless it already ends with LD. EOT is not stored.
  function loadStream(code) {
    const s = code.slice();
    if (!s.length || s[s.length - 1] !== OP.LD) s.push(OP.HALT, OP.LD);
    return s;
  }

  //--------------------------------------------------------------------
  // Machine
  //--------------------------------------------------------------------
  class Machine {
    constructor(cfg) {
      this.cfg = Object.assign({
        apTop: AP_SIZE - 1, runOnHardRst: false, runOnSoftRst: false, softRstOnEot: true,
        echoMode: true, bellOnCin: false, bellOnHalt: false, bellOnError: false
      }, cfg || {});
      if (!(this.cfg.apTop >= 1 && this.cfg.apTop < AP_SIZE)) throw new RangeError('apTop must be 1..999');
      this.onCout = null;
      this.onBell = null;
      this.onCin = null;     // optional: () => code or -1 when no input
      this.powerOn();
    }

    powerOn() {
      this.codeRam = new Uint8Array(IP_SIZE);
      this.bootRom = new Uint8Array(BOOT_SIZE);
      this.setBootRom(assemble(BOOTLOADER, 'dpc'));
      this.dataMem = new Uint8Array(this.cfg.apTop + 1);
      this.memReg = 0;
      this.ip = 0; this.ap = 0; this.loop = 0; this.data = 0;
      this.lock = false; this.memHere = false;
      this.ipCounted = false; this.insn = OP.NOP; this.overflow = false;
      this.loading = false; this.halted = true; this.phase = PH_FETCH;
      this.iret = 0; this.bells = 0; this.memReads = 0; this.memWrites = 0;
      this.rx = []; this.insnIn = []; this.tx = '';
    }

    clearData() { this.dataMem.fill(0); this.memReg = 0; }
    clearCode() { this.codeRam.fill(0); }
    setBootRom(ops) { this.bootRom.fill(0); ops.slice(0, BOOT_SIZE).forEach((op, i) => { this.bootRom[i] = op & 15; }); }

    //--- Resets and panel keys ------------------------------------------
    // soft_rst/hard_rst lines: counters to their reset positions, memories
    // keep their contents, a locked Data counter is not written back.
    resetCounters(hard) {
      this.ip = hard ? BOOT_BASE : 0;   // HARD_RST_D_CNT = 3 -> 9990
      this.ap = 0; this.loop = 0; this.data = 0;
      this.lock = this.memHere = false;
      this.ipCounted = false; this.overflow = false; this.loading = false;
      this.phase = PH_FETCH;
      this.halted = !(hard ? this.cfg.runOnHardRst : this.cfg.runOnSoftRst);
    }
    hardReset() { this.resetCounters(true); }
    softReset() { this.resetCounters(false); }
    run() { this.halted = false; }
    startLoading() { this.loading = true; this.run(); }

    // Halt key: MachineCtrl goes to S_HALT at the instruction boundary and
    // IpLine takes its halt step (RTL: a pending loop scan is ignored).
    haltKey() { if (!this.halted) this.enterHalt(); }

    // InsnLoadingStop: loading ends and the machine halts.
    loadingStop() {
      if (!this.loading) return;
      this.loading = false;
      this.phase = PH_FETCH;
      this.enterHalt();
    }

    // keyNextIp / keyPrevIp in IpLine S_HALT: step IP, re-read on resume.
    nextIp() { if (this.halted) { this.ip = (this.ip + 1) % IP_SIZE; this.ipCounted = false; } }
    prevIp() { if (this.halted) { this.ip = (this.ip + IP_SIZE - 1) % IP_SIZE; this.ipCounted = false; } }

    // Manual INC/DEC of one counter between instructions.
    //  ip   - as keyNextIp/keyPrevIp: the instruction is re-read on resume
    //  loop - 0..99 with wrap, the overflow flag is not touched
    //  ap   - as > / <: a locked Data counter is flushed first, lazy read after
    //  data - as + / -: the cell is read if needed, MemLock is set
    manualStep(counter, dec) {
      switch (counter) {
        case 'ip':
          this.ip = dec ? (this.ip + IP_SIZE - 1) % IP_SIZE : (this.ip + 1) % IP_SIZE;
          this.ipCounted = false;
          break;
        case 'loop': this.loop = dec ? (this.loop + LOOP_SIZE - 1) % LOOP_SIZE : (this.loop + 1) % LOOP_SIZE; break;
        case 'ap': this.apMove(false, dec); break;
        case 'data': this.dataStep(dec); break;
      }
    }

    enterHalt() {
      this.halted = true;
      this.phase = PH_FETCH;
      if (this.ipCounted) {
        this.ip = (this.ip + 1) % IP_SIZE;
        this.ipCounted = false;
      }
    }

    bell() { this.bells++; if (this.onBell) this.onBell(); }
    cout(c) { this.tx += String.fromCharCode(c); if (this.onCout) this.onCout(c); }

    //--- Memories --------------------------------------------------------
    readCode(a) { return a >= BOOT_BASE ? this.bootRom[a - BOOT_BASE] : this.codeRam[a]; }
    writeCode(a, op) { if (a < BOOT_BASE) this.codeRam[a] = op & 15; }   // ROM decade is write-protected
    code(a) { return this.readCode(((a % IP_SIZE) + IP_SIZE) % IP_SIZE); }
    loadCode(ops, base) { base = base || 0; ops.forEach((op, i) => this.writeCode((base + i) % IP_SIZE, op)); }
    cell(a) { return this.dataMem[a]; }
    cellValue() { return this.lock ? this.data : this.dataMem[this.ap]; }
    txData() { return this.data; }

    //--- ApLine ----------------------------------------------------------
    memRead() { this.memReads++; this.memReg = this.dataMem[this.ap]; this.memHere = true; }
    // Write-through: the output register takes the written value.
    flush() {
      this.memWrites++;
      this.dataMem[this.ap] = this.data;
      this.memReg = this.data;
      this.memHere = true;
    }
    // > < and CLRA. MemLock is the only flag: a locked counter is flushed
    // before the address moves, which releases the lock (REQ-ML-005/007).
    // After MemLock this writes the counter into the cell MemLock took over.
    apMove(zero, dec) {
      if (this.lock) { this.flush(); this.lock = false; }
      const n = this.cfg.apTop + 1;
      if (zero) this.ap = 0;
      else if (dec) this.ap = (this.ap + n - 1) % n;
      else this.ap = (this.ap + 1) % n;
      this.memHere = false;   // lazy read: the new cell is not read now
    }
    // + -: MemLock is taken before the first step.
    dataStep(dec) {
      if (!this.lock) { if (!this.memHere) this.memRead(); this.data = this.memReg; }
      this.data = dec ? (this.data + DATA_TOP) % (DATA_TOP + 1) : (this.data + 1) % (DATA_TOP + 1);
      this.lock = true;
    }

    //--- IpLine ----------------------------------------------------------
    // MachineCtrl: loop_val_zero = op_q[3] ? ap_zero : data_zero
    loopValZero() {
      if (this.insn & 0x8) return this.ap === 0;                   // { }
      return (this.lock ? this.data : this.memReg) === 0;          // [ ]
    }
    fetch() {
      if (!this.ipCounted) {
        // First fetch after reset or halt: read at the current IP
        this.ipCounted = true;
        if (this.loading) this.phase = PH_INSN;
        else this.insn = this.readCode(this.ip);
        return OK;
      }
      if (this.loading) {
        this.ip = (this.ip + 1) % IP_SIZE;
        this.phase = PH_INSN;
        return OK;
      }
      const zero = this.loopValZero();
      if (isLoopOpen(this.insn) && zero) return this.scan(false);
      if (isLoopClose(this.insn) && !zero) return this.scan(true);
      this.ip = (this.ip + 1) % IP_SIZE;
      this.insn = this.readCode(this.ip);
      return OK;
    }
    // Loop scan: +1 for the starting bracket and every bracket of the same
    // direction, -1 for every matching one; [ ] and { } are counted together.
    // Stops ON the matching bracket. Past 99 is the hardware error of
    // REQ-CNT-007: the machine stands still until a reset (TC-N2, no halt).
    scan(back) {
      const TOP = LOOP_SIZE - 1;
      if (this.loop !== TOP) {
        this.loop++;
        for (;;) {
          this.ip = back ? (this.ip + IP_SIZE - 1) % IP_SIZE : (this.ip + 1) % IP_SIZE;
          this.insn = this.readCode(this.ip);
          if (back ? isLoopClose(this.insn) : isLoopOpen(this.insn)) {
            if (this.loop === TOP) break;   // overflow, stand on this bracket
            this.loop++;
          } else if (isLoopOpen(this.insn) || isLoopClose(this.insn)) {
            this.loop--;
            if (this.loop === 0) return OK;   // matching bracket, stand on it
          }
        }
      }
      this.overflow = true;
      this.phase = PH_FETCH;
      if (this.cfg.bellOnError) this.bell();
      return HALTED;
    }

    //--- MachineCtrl -----------------------------------------------------
    // S_INSN_IN: one opcode from InsnIn is written at IP; LD (EOT) is not.
    takeInsn() {
      if (!this.insnIn.length) return false;
      const op = this.insnIn.shift() & 15;
      this.insn = op;
      if (op !== OP.LD) this.writeCode(this.ip, op);
      return true;
    }
    // Load mode: only LD (EOT) acts; everything else is just stored.
    decodeLoading() {
      if (this.insn === OP.LD) {
        this.loading = false;
        if (this.cfg.softRstOnEot) this.resetCounters(false);
        else this.enterHalt();
      }
    }
    decode() {
      this.iret++;
      if (this.loading) { this.decodeLoading(); return; }
      switch (this.insn) {
        case OP.HALT: if (this.cfg.bellOnHalt) this.bell(); this.enterHalt(); break;
        // Brackets: IpLine decides at the next fetch. Before [ ] the zero
        // flag is made valid (AP_TEST); { } test AP.
        case OP.LBEG: case OP.LEND: if (!this.lock && !this.memHere) this.memRead(); break;
        case OP.LABEG: case OP.LAEND: break;
        case OP.CLRD: this.data = 0; this.lock = true; break;     // [-] (REQ-ML-009)
        case OP.LD: this.loading = true; break;                  // SOT
        case OP.CLRA: this.apMove(true, false); break;
        case OP.MEMLOCK: this.lock = true; break;                // flag without a load
        case OP.INC: case OP.DEC: this.dataStep(this.insn & 1); break;
        case OP.AINC: case OP.ADEC: this.apMove(false, this.insn & 1); break;
        case OP.COUT:
          // Output is always the Data counter: without MemLock the cell is
          // loaded into it first. MemLock is unchanged (OPEN-017).
          if (!this.lock) { if (!this.memHere) this.memRead(); this.data = this.memReg; }
          this.cout(this.data);
          break;
        case OP.CIN: if (this.cfg.bellOnCin) this.bell(); this.phase = PH_CIN; break;
        default: break;                                          // NOP
      }
    }
    // S_CIN_WAIT -> AP_CIN -> optional echo
    finishCin() {
      let c = -1;
      if (this.onCin) c = this.onCin();
      else if (this.rx.length) c = this.rx.shift();
      if (c < 0) return WAIT;
      this.phase = PH_FETCH;
      this.data = c % (DATA_TOP + 1);
      this.lock = true;
      if (this.cfg.echoMode) this.cout(this.data);
      return OK;
    }

    // One instruction: one pass through S_DECODE.
    step() {
      if (this.halted || this.overflow) return HALTED;   // halted, or stopped by an overflow
      if (this.phase === PH_CIN) return this.finishCin();
      if (this.phase === PH_FETCH) {
        const s = this.fetch();
        if (s !== OK) return s;
      }
      if (this.phase === PH_INSN) {
        if (!this.takeInsn()) return WAIT;
        this.phase = PH_FETCH;
      }
      this.decode();
      if (this.phase === PH_CIN) return this.finishCin();
      return this.halted ? HALTED : OK;
    }

    get waitingCin() { return this.phase === PH_CIN; }
    get waitingInsn() { return this.phase === PH_INSN; }
  }

  const DPC = {
    Machine, OP, assemble, stripComments, loadStream, symbol, mnemonic, BOOTLOADER,
    IP_SIZE, BOOT_BASE, AP_SIZE, LOOP_SIZE, DATA_TOP, OK, HALTED, WAIT
  };
  if (typeof module !== 'undefined' && module.exports) module.exports = DPC;
  else root.DPC = DPC;
})(typeof self !== 'undefined' ? self : this);
