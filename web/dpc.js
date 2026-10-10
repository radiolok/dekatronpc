/* DekatronPC web simulator: machine model.
 *
 * Instruction-level model of DekatronPC, a line-by-line JavaScript port of the
 * golden model bfutils/dpcrun (dpcrun.h, dpcrun.cpp). Like dpcrun it mirrors
 * the RTL as it is, including the places marked "RTL:" in dpcrun.cpp where
 * the RTL and TRS disagree (doc/dpcrun_golden_model.md §4).
 *
 * Differences from dpcrun, all outside the instruction semantics:
 *  - The bootloader ROM is the SIMPLEBOOT variant of
 *    rtl/programs/bootloader/bootloader.sv: NOPs, then ISA0 at 99998 and SOT
 *    at 99999. Data memory is cleared by the page (clearData()), not by a
 *    clear-memory routine in the ROM.
 *  - AP limit defaults to 99999, as in the current RTL (ApLine has no top
 *    limit, OPEN-001) and as DekatronPC_tb.cpp builds dpcrun.
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

  const IP_SIZE = 100000, BOOT_BASE = 99900, BOOT_SIZE = 100, LOOP_SIZE = 100, DATA_TOP = 255;
  const ISA_DEBUG = 0, ISA_BF = 1;
  const PH_FETCH = 0, PH_INSN = 1, PH_CIN = 2;
  const OK = 'Ok', HALTED = 'Halted', WAIT = 'WaitInput';

  //--------------------------------------------------------------------
  // Loader: text -> opcodes. Same table as rtl/run/generate_rom.py and
  // dpc::symbolToOpcode().
  //--------------------------------------------------------------------
  const SYMBOLS = {
    'N': 0x0, 'H': 0x1, '+': 0x2, '-': 0x3, '>': 0x4, '<': 0x5, '[': 0x6, ']': 0x7,
    '.': 0x8, ',': 0x9, '0': 0xA, 'M': 0xB, 'G': 0xC, 'P': 0xD, 'D': 0xE, 'B': 0xF,
    '\x07': 0x2, 'E': 0x4, 'S': 0x5, '{': 0x6, '}': 0x7, 'L': 0x8, 'I': 0x9,
    'A': 0xB, 'R': 0xC, 'r': 0xD
  };
  const BF_ONLY = { '+': 0x2, '-': 0x3, '>': 0x4, '<': 0x5, '[': 0x6, ']': 0x7, '.': 0x8, ',': 0x9 };

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

  const BF_SYM = 'NH+-><[].,0MGPDB';
  const DBG_SYM = 'NH⍾-ES{}LI0ARrDB';
  const BF_MN = ['NOP', 'HALT', 'INC', 'DEC', 'AINC', 'ADEC', 'LBEG', 'LEND',
    'COUT', 'CIN', 'CLRD', 'CLRML', 'LOAD', 'STORE', 'ISA0', 'ISA1'];
  const DBG_MN = ['NOP', 'HALT', 'BELL', 'RSVD', 'EOT', 'SOT', 'LABEG', 'LAEND',
    'CLRL', 'CLRI', 'CLRD', 'CLRA', 'HRST', 'SRST', 'ISA0', 'ISA1'];
  const symbol = (op, mode) => (mode === ISA_BF ? BF_SYM : DBG_SYM)[op & 15];
  const mnemonic = (op, mode) => (mode === ISA_BF ? BF_MN : DBG_MN)[op & 15];

  // Opcodes sent over InsnIn for a program: ISA1 first (loading starts in
  // Debug ISA, where '>' = 0x4 is EOT; same as DekatronPC_tb), then the
  // program, HALT, ISA0, EOT.
  function loadStream(code) {
    const s = [0xF].concat(code);
    const n = code.length;
    const endsWithEot = n >= 2 && code[n - 2] === 0xE && code[n - 1] === 0x4;
    if (!endsWithEot) s.push(0x1, 0xE, 0x4);
    return s;
  }

  //--------------------------------------------------------------------
  // Machine
  //--------------------------------------------------------------------
  class Machine {
    constructor(cfg) {
      this.cfg = Object.assign({
        apTop: 99999, runOnHardRst: false, runOnSoftRst: false, softRstOnEot: true,
        echoMode: true, bellOnCin: false, bellOnHalt: false, bellOnError: false
      }, cfg || {});
      this.onCout = null;
      this.onBell = null;
      this.onCin = null;     // optional: () => code or -1 when no input
      this.powerOn();
    }

    powerOn() {
      this.codeRam = new Uint8Array(IP_SIZE);
      this.bootRom = new Uint8Array(BOOT_SIZE);
      this.bootRom[98] = 0xE;   // ISA0 (SIMPLEBOOT)
      this.bootRom[99] = 0x5;   // SOT
      this.dataMem = new Uint8Array(this.cfg.apTop + 1);
      this.memReg = 0;
      this.ip = 0; this.ap = 0; this.loop = 0; this.data = 0;
      this.lock = false; this.memHere = false;
      this.ipCounted = false; this.insn = 0; this.overflow = false;
      this.mode = ISA_DEBUG; this.loading = false; this.halted = true; this.phase = PH_FETCH;
      this.iret = 0; this.bells = 0; this.memReads = 0; this.memWrites = 0;
      this.rx = []; this.insnIn = []; this.tx = '';
      this.lastScan = 0;
    }

    clearData() { this.dataMem.fill(0); this.memReg = 0; }
    clearCode() { this.codeRam.fill(0); }
    setBootRom(ops) { this.bootRom.fill(0); ops.slice(0, BOOT_SIZE).forEach((op, i) => { this.bootRom[i] = op & 15; }); }

    //--- Resets and panel keys ------------------------------------------
    resetCounters(hard) {
      this.ip = hard ? BOOT_BASE : 0;
      this.ap = 0; this.loop = 0; this.data = 0;
      this.lock = this.memHere = false;
      this.ipCounted = false; this.overflow = false; this.loading = false;
      this.phase = PH_FETCH;
      this.mode = hard ? ISA_DEBUG : ISA_BF;
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
    writeCode(a, op) { if (a < BOOT_BASE) this.codeRam[a] = op & 15; }
    code(a) { return this.readCode(((a % IP_SIZE) + IP_SIZE) % IP_SIZE); }
    loadCode(ops, base) { base = base || 0; ops.forEach((op, i) => this.writeCode((base + i) % IP_SIZE, op)); }
    cell(a) { return this.dataMem[a]; }
    cellValue() { return this.lock ? this.data : this.dataMem[this.ap]; }
    txData() { return this.data; }

    //--- ApLine ----------------------------------------------------------
    memRead() { this.memReads++; this.memReg = this.dataMem[this.ap]; this.memHere = true; }
    flush() {
      this.memWrites++;
      this.dataMem[this.ap] = this.data;
      this.memReg = this.data;
      this.memHere = true;
    }
    // MemLock is the only flag: a locked counter is flushed before the address
    // moves, which releases the lock (REQ-ML-005/007). After STORE this writes
    // the same value again.
    apMove(zero, dec) {
      if (this.lock) { this.flush(); this.lock = false; }
      const n = this.cfg.apTop + 1;
      if (zero) this.ap = 0;
      else if (dec) this.ap = (this.ap + n - 1) % n;
      else this.ap = (this.ap + 1) % n;
      this.memHere = false;
    }
    dataStep(dec) {
      if (!this.lock) { if (!this.memHere) this.memRead(); this.data = this.memReg; }
      this.data = dec ? (this.data + DATA_TOP) % (DATA_TOP + 1) : (this.data + 1) % (DATA_TOP + 1);
      this.lock = true;
    }

    //--- IpLine ----------------------------------------------------------
    loopValZero() {
      if (this.mode === ISA_BF) return (this.lock ? this.data : this.memReg) === 0;
      return this.ap === 0;
    }
    fetch() {
      if (!this.ipCounted) {
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
      if (this.insn === 0x6 && zero) return this.scan(false);
      if (this.insn === 0x7 && !zero) return this.scan(true);
      this.ip = (this.ip + 1) % IP_SIZE;
      this.insn = this.readCode(this.ip);
      return OK;
    }
    scan(back) {
      const own = back ? 0x7 : 0x6, TOP = LOOP_SIZE - 1;
      if (this.loop !== TOP) {
        this.loop++;
        for (;;) {
          this.ip = back ? (this.ip + IP_SIZE - 1) % IP_SIZE : (this.ip + 1) % IP_SIZE;
          this.insn = this.readCode(this.ip);
          this.lastScan++;
          if (this.insn === own) {
            if (this.loop === TOP) break;
            this.loop++;
          } else if (this.insn === 0x6 || this.insn === 0x7) {
            this.loop--;
            if (this.loop === 0) return OK;
          }
        }
      }
      this.overflow = true;
      if (this.cfg.bellOnError) this.bell();
      this.enterHalt();
      return HALTED;
    }

    //--- MachineCtrl -----------------------------------------------------
    takeInsn() {
      if (!this.insnIn.length) return false;
      const op = this.insnIn.shift() & 15;
      this.insn = op;
      if (!(this.mode === ISA_DEBUG && op === 0x4)) this.writeCode(this.ip, op);
      return true;
    }
    decodeLoading() {
      const f = (this.mode << 4) | this.insn;
      if (f === 0x04) {
        this.loading = false;
        if (this.cfg.softRstOnEot) this.resetCounters(false);
        else this.enterHalt();
      } else if (f === 0x0E || f === 0x1E) this.mode = ISA_DEBUG;
      else if (f === 0x0F || f === 0x1F) this.mode = ISA_BF;
    }
    decode() {
      this.iret++;
      if (this.loading) { this.decodeLoading(); return; }
      const f = (this.mode << 4) | this.insn;
      switch (f) {
        case 0x01: case 0x11: if (this.cfg.bellOnHalt) this.bell(); this.enterHalt(); break;
        case 0x0E: case 0x1E: this.mode = ISA_DEBUG; break;
        case 0x0F: case 0x1F: this.mode = ISA_BF; break;
        case 0x06: case 0x07: break;
        case 0x16: case 0x17: if (!this.lock && !this.memHere) this.memRead(); break;
        case 0x0A: case 0x1A: this.data = 0; this.lock = true; break;
        case 0x02: this.bell(); break;
        case 0x05: this.loading = true; break;
        case 0x08: this.loop = 0; this.overflow = false; break;
        case 0x09: this.ip = 0; this.ipCounted = false; break;
        case 0x0B: this.apMove(true, false); break;
        case 0x0C: this.resetCounters(true); break;
        case 0x0D: this.resetCounters(false); break;
        case 0x12: case 0x13: this.dataStep(this.insn & 1); break;
        case 0x14: case 0x15: this.apMove(false, this.insn & 1); break;
        case 0x18:
          if (!this.lock) { if (!this.memHere) this.memRead(); this.data = this.memReg; }
          this.cout(this.data);
          break;
        case 0x19: if (this.cfg.bellOnCin) this.bell(); this.phase = PH_CIN; break;
        case 0x1B: if (this.lock) this.flush(); this.lock = false; break;
        case 0x1C: if (!this.memHere) this.memRead(); this.data = this.memReg; break;
        case 0x1D: this.flush(); break;
        default: break;
      }
    }
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
      if (this.halted) return HALTED;
      this.lastScan = 0;
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
    Machine, assemble, stripComments, loadStream, symbol, mnemonic,
    IP_SIZE, BOOT_BASE, LOOP_SIZE, DATA_TOP, ISA_BF, ISA_DEBUG, OK, HALTED, WAIT
  };
  if (typeof module !== 'undefined' && module.exports) module.exports = DPC;
  else root.DPC = DPC;
})(typeof self !== 'undefined' ? self : this);
