#!/usr/bin/env node
// Tests of web/dpc.js.
//
//  node web/test/test_dpc.js [path/to/dpcrun]
//
// 1. Step-by-step trace compare with the C++ golden model dpcrun (-s trace)
//    on the repo programs. Skipped when no dpcrun binary is given.
// 2. Assembler: dialects and comments.
// 3. Loading through the SIMPLEBOOT ROM over SOT/EOT.
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
  return `IRET:${m.iret} IP:${p(m.ip, 5)} ${DPC.mnemonic(m.insn, m.mode).padEnd(5)} ` +
    `LOOP:${p(m.loop, 2)} AP:${p(m.ap, 5)} DATA:${String(m.txData()).padStart(3)} ` +
    `ML:${m.lock ? 1 : 0} ${s}`;
}

// The same run as dpcrun -f: program at 0, HALT after it, Soft Reset, Run,
// bootloader ROM all NOPs (dpcrun has none without -b).
function jsTrace(src) {
  const m = new DPC.Machine({ apTop: 99999 });
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
    const r = spawnSync(dpcrun, ['-f', file, '-s', '-a', '99999', '-n', String(MAX)],
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
  check('dpc dialect: full table', DPC.assemble('NH0MGPDBESLIARr', 'dpc').join(',') ===
    '0,1,10,11,12,13,14,15,4,5,8,9,11,12,13');
}

function testBootLoad() {
  const src = fs.readFileSync(path.join(PROGS, 'helloworld.bfk'), 'latin1');
  const m = new DPC.Machine();
  m.insnIn = DPC.loadStream(DPC.assemble(src, 'dpc'));
  m.hardReset();
  m.run();
  let s, n = 0;
  while ((s = m.step()) === DPC.OK && n < 1e6) n++;
  check('SOT/EOT load ends in Soft Reset, halted at IP 0 in BF ISA',
    s === DPC.HALTED && m.ip === 0 && m.mode === DPC.ISA_BF && !m.loading,
    `status ${s} ip ${m.ip} mode ${m.mode} loading ${m.loading}`);
  m.run();
  while ((s = m.step()) === DPC.OK);
  check('helloworld after SOT/EOT load prints Hello World!', m.tx === 'Hello World!\n', JSON.stringify(m.tx));

  // A pure Brainfuck program without HALT/ISA0/EOT gets them appended.
  const m2 = new DPC.Machine();
  m2.insnIn = DPC.loadStream(DPC.assemble('++++++++[>++++++++<-]>+.', 'bf'));
  m2.hardReset(); m2.run();
  while ((s = m2.step()) === DPC.OK);
  m2.run();
  while ((s = m2.step()) === DPC.OK);
  check('appended HALT ISA0 EOT, prints A', m2.tx === 'A', JSON.stringify(m2.tx));
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
