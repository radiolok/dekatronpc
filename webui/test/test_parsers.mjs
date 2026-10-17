// ============================================================================
// DekatronPC Stage 1 Parser Tests
// Usage: node test_parsers.mjs <liberty.lib> <netlist.v>
// ============================================================================

import { readFileSync } from 'fs';

const [,, libPath, vlogPath] = process.argv;

if (!libPath || !vlogPath) {
  console.error('Usage: node test_parsers.mjs <liberty.lib> <netlist.v>');
  process.exit(1);
}

const libSource = readFileSync(libPath, 'utf-8');
const vlogSource = readFileSync(vlogPath, 'utf-8');

// ============================================================================
// Liberty parser (inline — matches production parser logic)
// ============================================================================

function findMatchingBrace(source, openBraceIndex) {
  let depth = 0;
  for (let i = openBraceIndex; i < source.length; i++) {
    if (source[i] === '{') depth++;
    else if (source[i] === '}') { depth--; if (depth === 0) return i; }
  }
  return -1;
}

function parseLiberty(source) {
  const cells = {};
  const clean = source.replace(/\/\*[\s\S]*?\*\//g, '').replace(/\/\/.*$/gm, '');

  let errors = 0;
  const cellRegex = /\bcell\s*\(\s*(\w+)\s*\)\s*\{/g;
  let cellMatch;
  while ((cellMatch = cellRegex.exec(clean)) !== null) {
    const cellName = cellMatch[1];
    const openIdx = cellMatch.index + cellMatch[0].length - 1;
    const closeIdx = findMatchingBrace(clean, openIdx);
    if (closeIdx === -1) { errors++; continue; }
    const cellBody = clean.slice(openIdx + 1, closeIdx);

    const pins = [];
    const pinRegex = /\bpin\s*\(\s*(\w+)\s*\)\s*\{/g;
    let pinMatch;
    while ((pinMatch = pinRegex.exec(cellBody)) !== null) {
      const pinName = pinMatch[1];
      const pinOpenIdx = pinMatch.index + pinMatch[0].length - 1;
      const pinCloseIdx = findMatchingBrace(cellBody, pinOpenIdx);
      if (pinCloseIdx === -1) { errors++; continue; }
      const pinBody = cellBody.slice(pinOpenIdx + 1, pinCloseIdx);

      const dirMatch = pinBody.match(/\bdirection\s*:\s*"?(input|output|inout|internal)"?\s*;/);
      const funcMatch = pinBody.match(/\bfunction\s*:\s*"([^"]*)"/);
      const clockMatch = pinBody.match(/\bclock\s*:\s*(true|false)/);

      pins.push({
        name: pinName,
        direction: dirMatch ? dirMatch[1] : '?',
        function: funcMatch ? funcMatch[1] : undefined,
        isClock: clockMatch ? clockMatch[1] === 'true' : undefined,
      });
    }

    const areaMatch = cellBody.match(/\barea\s*:\s*([\d.]+)\s*;/);
    const heatMatch = cellBody.match(/\bheat_current\s*:\s*([\d.]+)\s*;/);
    const isFF = /\bff\s*\(/.test(cellBody);
    const isLatch = /\blatch\s*\(/.test(cellBody);

    // Parse tubes
    const tubesMatch = cellBody.match(/\btubes\s*\(\s*\w+\s*\)\s*\{([^}]*)\}/);
    const tubes = {};
    if (tubesMatch) {
      const kvRegex = /(\w+)\s*:\s*([\d.]+)\s*;/g;
      let kv;
      while ((kv = kvRegex.exec(tubesMatch[1])) !== null) tubes[kv[1]] = parseFloat(kv[2]);
    }

    cells[cellName] = {
      name: cellName, pins,
      area: areaMatch ? parseFloat(areaMatch[1]) : undefined,
      heatCurrent: heatMatch ? parseFloat(heatMatch[1]) : undefined,
      tubes: Object.keys(tubes).length > 0 ? tubes : undefined,
      isFlipFlop: isFF || undefined,
      isLatch: isLatch || undefined,
    };
  }

  return { cells, errors };
}

// ============================================================================
// Verilog parser (inline — matches production parser logic)
// ============================================================================

function isConstant(expr) { return /^\d+'[bhod]\w+$/i.test(expr); }

function extractBaseNet(expr) {
  const m = expr.match(/^(\w+)(?:\s*\[[^\]]*\])?\s*$/);
  return m ? m[1] : expr;
}

function parseVerilog(source) {
  const clean = source.replace(/\/\*[\s\S]*?\*\//g, '').replace(/\/\/.*$/gm, '');

  const keywords = new Set([
    'module', 'endmodule', 'input', 'output', 'inout', 'wire',
    'reg', 'assign', 'always', 'if', 'else', 'for', 'while',
    'begin', 'end', 'case', 'endcase', 'parameter', 'localparam',
    'function', 'endfunction', 'task', 'endtask',
  ]);

  // Collect wires
  const wireNames = new Set();
  const wireRegex = /\bwire\s+(?:\[[^\]]*\]\s*)?((?:\s*(?:\w+)\s*,?\s*)+)\s*;/g;
  let wm;
  while ((wm = wireRegex.exec(clean)) !== null) {
    for (const n of wm[1].split(',').map(s => s.trim()).filter(Boolean)) wireNames.add(n);
  }

  // Gather instance starts: escaped + regular
  const starts = [];

  // Escaped: \escaped\name  inst_name (
  const escRegex = /\\([^\s\\]+(?:\s*\\[^\s\\]+)*)\s+(\w+)\s*\(/g;
  let em;
  while ((em = escRegex.exec(clean)) !== null) {
    const fullEscaped = em[0].slice(0, em[0].lastIndexOf(em[2])).trim();
    starts.push({ index: em.index, cellType: fullEscaped, instName: em[2] });
  }

  // Regular: CELL_TYPE INST_NAME (
  const regRegex = /(\w+)\s+(\w+)\s*\(/g;
  let rm;
  while ((rm = regRegex.exec(clean)) !== null) {
    const type = rm[1];
    if (keywords.has(type)) continue;
    // Check if inside escaped identifier
    const before = clean.slice(Math.max(0, rm.index - 200), rm.index);
    const lastNewline = before.lastIndexOf('\n');
    const chunk = before.slice(lastNewline + 1);
    const openEsc = chunk.lastIndexOf('\\');
    if (openEsc !== -1 && /^\S+$/.test(chunk.slice(openEsc + 1))) continue;
    starts.push({ index: rm.index, cellType: type, instName: rm[2] });
  }

  // Deduplicate by index
  starts.sort((a, b) => a.index - b.index);
  const seen = new Set();
  const uniq = starts.filter(s => { if (seen.has(s.index)) return false; seen.add(s.index); return true; });

  const instances = [];
  const nets = new Map();
  let errors = 0;

  for (const s of uniq) {
    const parenIdx = clean.indexOf('(', s.index);
    if (parenIdx === -1) continue;

    let depth = 0, closeIdx = -1;
    for (let i = parenIdx; i < clean.length; i++) {
      if (clean[i] === '(') depth++;
      else if (clean[i] === ')') { depth--; if (depth === 0) { closeIdx = i; break; } }
    }
    if (closeIdx === -1) { errors++; continue; }
    const after = clean.slice(closeIdx + 1).search(/[^\s]/);
    if (after === -1 || clean[closeIdx + 1 + after] !== ';') continue;

    const portStr = clean.slice(parenIdx + 1, closeIdx);
    const conns = {};
    const connRegex = /\.(\w+)\s*\(\s*([^)]+?)\s*\)/g;
    let cm;
    while ((cm = connRegex.exec(portStr)) !== null) {
      conns[cm[1]] = cm[2].trim();
    }

    // Track nets
    for (const [, expr] of Object.entries(conns)) {
      if (!isConstant(expr)) {
        const base = extractBaseNet(expr);
        if (!nets.has(base)) nets.set(base, []);
        nets.get(base).push(`${s.instName}.${Object.keys(conns).find(k => conns[k] === expr) || '?'}`);
      }
    }

    instances.push({ cellType: s.cellType, name: s.instName, connections: conns });
  }

  return { instances, nets: Array.from(nets.entries()), wireCount: wireNames.size, errors };
}

// ============================================================
// Run tests
// ============================================================

let allPassed = true;

// --- Liberty test ---
console.log('=== LIBERTY PARSER ===');
const lib = parseLiberty(libSource);
const libNames = Object.keys(lib.cells);
console.log(`  Cells: ${libNames.length} (errors: ${lib.errors})`);

// Show cells with pin details
for (const [name, cell] of Object.entries(lib.cells)) {
  const pinStr = cell.pins.map(p => {
    let extra = '';
    if (p.function) extra += ` func="${p.function}"`;
    if (p.isClock) extra += ' CLOCK';
    return `${p.name}:${p.direction}${extra}`;
  }).join(', ');
  let cellExtra = '';
  if (cell.area) cellExtra += ` area=${cell.area}`;
  if (cell.heatCurrent) cellExtra += ` heat=${cell.heatCurrent}`;
  if (cell.tubes) cellExtra += ` tubes=[${Object.entries(cell.tubes).map(([k, v]) => `${k}:${v}`).join(', ')}]`;
  if (cell.isFlipFlop) cellExtra += ' FF';
  if (cell.isLatch) cellExtra += ' LATCH';
  console.log(`  ${name}: [${pinStr}]${cellExtra}`);
}

if (lib.errors > 0 || libNames.length < 10) {
  console.log('  FAIL: expected >=10 cells with no errors');
  allPassed = false;
} else {
  console.log('  PASS');
}

// --- Verilog test ---
console.log('\n=== VERILOG PARSER ===');
const vlog = parseVerilog(vlogSource);
console.log(`  Instances: ${vlog.instances.length}`);
console.log(`  Nets:      ${vlog.nets.length}`);
console.log(`  Wires:     ${vlog.wireCount}`);
console.log(`  Errors:    ${vlog.errors}`);

// Unique cell types
const types = new Set(vlog.instances.map(i => i.cellType));
console.log(`  Cell types: ${types.size}`);

// Show gate types (ones in liberty)
console.log('\n  --- Gate instances ---');
const libNamesSet = new Set(libNames);
const gateTypes = [...types].filter(t => libNamesSet.has(t)).sort();
for (const t of gateTypes) {
  const count = vlog.instances.filter(i => i.cellType === t).length;
  console.log(`    ${t}: ${count}`);
}

// Show submodules (not in liberty)
console.log('\n  --- Submodule instances ---');
const subTypes = [...types].filter(t => !libNamesSet.has(t)).sort();
if (subTypes.length > 0) {
  for (const t of subTypes) {
    const count = vlog.instances.filter(i => i.cellType === t).length;
    console.log(`    ${t}: ${count}`);
  }
  console.log(`  (${subTypes.length} types need external element definitions)`);
}

// Net fanout stats
if (vlog.nets.length > 0) {
  const fanouts = vlog.nets.map(([, terms]) => terms.length);
  const maxFanout = Math.max(...fanouts);
  const totalTerms = fanouts.reduce((a, b) => a + b, 0);
  console.log(`\n  --- Net stats ---`);
  console.log(`    Total terminals: ${totalTerms}`);
  console.log(`    Max fanout:      ${maxFanout}`);
}

// Show first 5 instances as sample
console.log('\n  --- Samples (first 5 instances) ---');
for (const inst of vlog.instances.slice(0, 5)) {
  const ports = Object.entries(inst.connections).map(([p, v]) => `.${p}(${v})`).join(', ');
  console.log(`    ${inst.cellType} ${inst.name} (${ports});`);
}

const gateTotal = gateTypes.reduce((sum, t) => sum + vlog.instances.filter(i => i.cellType === t).length, 0);
const subTotal = vlog.instances.length - gateTotal;

if (vlog.errors > 0 || vlog.instances.length < 50) {
  console.log('\n  FAIL: expected >=50 instances with no errors');
  allPassed = false;
} else {
  console.log('\n  PASS');
}

// --- Summary ---
console.log('\n============================================');
console.log(`  Liberty: ${libNames.length} cells (${lib.errors} errors)`);
console.log(`  Verilog: ${vlog.instances.length} instances, ${vlog.nets.length} nets`);
console.log(`           ${gateTotal} gates (${gateTypes.length} types)`);
console.log(`           ${subTotal} submodules (${subTypes.length} types)`);
console.log(`  RESULT:  ${allPassed ? 'ALL TESTS PASSED' : 'SOME TESTS FAILED'}`);
console.log('============================================');

process.exit(allPassed ? 0 : 1);
