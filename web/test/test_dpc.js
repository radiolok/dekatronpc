#!/usr/bin/env node
// Tests of web/dpc.js.
//
//  node web/test/test_dpc.js [path/to/dpcrun]
//
// 1. Step-by-step trace compare with the C++ golden model dpcrun (-s trace)
//    on the repo programs. Skipped when no dpcrun binary is given.
// 2. Assembler: dialects and comments.
// 3. Loading through the bootloader ROM (0<{0<}NNNS) over SOT/EOT.
'use strict';
const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');
const DPC = require('../dpc.js');

const ROOT = path.resolve(__dirname, '..', '..');
const PROGS = path.join(ROOT, 'rtl', 'programs');
const MAX = 400000;
let failed = 0, passed = 0;

function check(name, cond, info) {
  if (cond) { passed++; console.log('ok   ' + name); }
  else { failed++; console.log('FAIL ' + name + (info ? '\n     ' + info : '')); }
}

// dpcrun -s line format (dpcrun.cpp main)
function traceLine(m, s) {
  const p = (v, n) => String(v).padStart(n, '0');
  return `IRET:${m.iret} IP:${p(m.ip, 4)} ${DPC.mnemonic(m.insn).padEnd(5)} ` +
    `LOOP:${p(m.loop, 2)} AP:${p(m.ap, 3)} DATA:${String(m.txData()).padStart(3)} ` +
    `ML:${m.lock ? 1 : 0} ${s}`;
}

// The same run as dpcrun -f: program at 0, HALT after it, Soft Reset, Run,
// bootloader ROM all NOPs (dpcrun has none without -b).
function jsTrace(src) {
  const m = new DPC.Machine();
  m.setBootRom([]);
  const code = DPC.assemble(src, 'dpc');
  code.push(0x1);
  m.loadCode(code);
  m.softReset();
  m.run();
  const out = [];
  for (let i = 0; i < MAX; i++) {
    const s = m.step();
    out.push(traceLine(m, s));
    if (s !== DPC.OK) break;
  }
  return out;
}

function compareWithDpcrun(dpcrun) {
  for (const name of ['helloworld', 'looptest', 'program', 'triangle', 'pi', 'fibonachi']) {
    const file = path.join(PROGS, name + '.bfk');
    const r = spawnSync(dpcrun, ['-f', file, '-s', '-n', String(MAX)],
      { input: '', maxBuffer: 1 << 30 });
    const a = (r.stderr || '').toString().split('\n').filter(l => l.startsWith('IRET:'));
    const b = jsTrace(fs.readFileSync(file, 'latin1'));
    let diff = -1;
    for (let i = 0; i < Math.max(a.length, b.length); i++) if (a[i] !== b[i]) { diff = i; break; }
    check(`trace ${name} (${b.length} steps)`, diff < 0,
      diff >= 0 ? `step ${diff}: dpcrun "${a[diff]}" js "${b[diff]}"` : '');
  }
}

function testAssembler() {
  check('bf dialect keeps only + - < > [ ] . ,',
    DPC.assemble('ab+c-<>[].,xyz0H', 'bf').join(',') === '2,3,5,4,6,7,8,9');
  check('bf dialect ignores letters', DPC.assemble('Hello World', 'bf').length === 0);
  check('dpc dialect: line comments //, ;, #',
    DPC.assemble('+ // H\n- ; H\n> # H\n<', 'dpc').join(',') === '2,3,4,5');
  check('dpc dialect: block comment',
    DPC.assemble('+/* H E\nS */-', 'dpc').join(',') === '2,3');
  check('dpc dialect: full ISA16 table', DPC.assemble('NH+-><[].,0SAP{}E', 'dpc').join(',') ===
    '0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,11');
  check('symbols and mnemonics round-trip', [...Array(16).keys()].every(op =>
    DPC.assemble(DPC.symbol(op), 'dpc')[0] === op) && DPC.mnemonic(0xD) === 'MEMLOCK');
}

function testBootLoad() {
  const src = fs.readFileSync(path.join(PROGS, 'helloworld.bfk'), 'latin1');
  const m = new DPC.Machine();
  m.dataMem.fill(7);                       // ferrite keeps old contents
  m.insnIn = DPC.loadStream(DPC.assemble(src, 'dpc'));
  m.hardReset();
  check('hard reset: IP at the bootloader decade 9990', m.ip === 9990 && DPC.BOOT_BASE === 9990);
  m.run();
  let s, n = 0;
  while ((s = m.step()) === DPC.OK && n < 1e6) n++;
  check('SOT/EOT load ends in Soft Reset, halted at IP 0',
    s === DPC.HALTED && m.ip === 0 && !m.loading, `status ${s} ip ${m.ip} loading ${m.loading}`);
  check('bootloader cleared all 1000 data cells', m.dataMem.length === 1000 && m.dataMem.every(v => v === 0));
  check('ROM decade not overwritten', m.code(9990) === 0xA && m.code(9999) === 0xB);
  m.run();
  while ((s = m.step()) === DPC.OK);
  check('helloworld after SOT/EOT load prints Hello World!', m.tx === 'Hello World!\n', JSON.stringify(m.tx));

  // A pure Brainfuck program without HALT/EOT gets them appended.
  const m2 = new DPC.Machine();
  m2.insnIn = DPC.loadStream(DPC.assemble('++++++++[>++++++++<-]>+.', 'bf'));
  m2.hardReset(); m2.run();
  while ((s = m2.step()) === DPC.OK);
  m2.run();
  while ((s = m2.step()) === DPC.OK);
  check('appended HALT EOT, prints A', m2.tx === 'A', JSON.stringify(m2.tx));

  // AP wraps 0 <-> 999 (3 dekatrons)
  const m3 = new DPC.Machine();
  m3.loadCode(DPC.assemble('<.>H', 'dpc'));
  m3.softReset(); m3.run(); m3.step(); const top = m3.ap;
  m3.step(); m3.step();
  check('AP wraps 0 -> 999 -> 0', top === 999 && m3.ap === 0, `ap ${top} then ${m3.ap}`);

  // { } test AP, [ ] the cell; a loop overflow stops without halt (TC-N2)
  const m4 = new DPC.Machine();
  m4.loadCode(DPC.assemble('['.repeat(101), 'dpc'));
  m4.softReset(); m4.run();
  while ((s = m4.step()) === DPC.OK);
  check('loop overflow stops the machine, not a halt', s === DPC.HALTED && m4.overflow && !m4.halted);
}

function testCin() {
  const m = new DPC.Machine({ echoMode: false });
  m.loadCode(DPC.assemble(fs.readFileSync(path.join(PROGS, 'rot13.bfk'), 'latin1'), 'dpc'));
  m.softReset(); m.run();
  for (const c of 'Hello\n') m.rx.push(c.charCodeAt(0));
  let s;
  while ((s = m.step()) === DPC.OK);
  check('rot13 waits for input after a line', s === DPC.WAIT && m.tx === 'Uryyb\n', JSON.stringify(m.tx));
}

const dpcrun = process.argv[2];
if (dpcrun && fs.existsSync(dpcrun)) compareWithDpcrun(dpcrun);
else console.log('skip trace compare: no dpcrun binary given');
testAssembler();
testBootLoad();
testCin();
console.log(`\n${passed} passed, ${failed} failed`);
process.exit(failed ? 1 : 0);
