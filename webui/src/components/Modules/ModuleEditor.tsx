// ============================================================================
// ModuleEditor — "Modules" tab: module-type library (REQ-PR-006, manual entry)
//   list of types · properties · slots · per-copy pin map · 2×36 connector view
// ============================================================================

import { useCallback, useMemo, useState } from 'react';
import { useProjectStore } from '@/store';
import {
  CONTACT_IDS,
  CONTACTS_PER_SIDE,
  contactUsage,
  getAllCellTypes,
  getCellPins,
  moduleTubes,
  slotCount,
  type ContactUse,
  type ModuleKind,
  type ModuleType,
  type PinMapping,
} from '@/types';

const WIDTH_STEPS = [1, 2, 3, 4, 5, 6];

function nextTypeId(types: ModuleType[]): string {
  let n = 1;
  while (types.some(t => t.id === `T${n}`)) n++;
  return `T${n}`;
}

function formatTubes(tubes: Record<string, number>): string {
  const parts = Object.entries(tubes).map(([t, n]) => `${t}×${n}`);
  return parts.length ? parts.join(' ') : '—';
}

/** "NAND2_J2 #2.A" — copy numbers shown 1-based */
function contactLabel(type: ModuleType, u: ContactUse): string {
  return `${type.slots[u.slotDefIndex]?.cellType} #${u.copy + 1}.${u.cellPin}`;
}

export function ModuleEditor() {
  const moduleTypes = useProjectStore(s => s.moduleTypes);
  const liberty = useProjectStore(s => s.liberty);
  const externalElements = useProjectStore(s => s.externalElements);
  const blocks = useProjectStore(s => s.blocks);
  const addModuleType = useProjectStore(s => s.addModuleType);
  const updateModuleType = useProjectStore(s => s.updateModuleType);
  const removeModuleType = useProjectStore(s => s.removeModuleType);
  const addSlot = useProjectStore(s => s.addSlot);
  const updateSlot = useProjectStore(s => s.updateSlot);
  const removeSlot = useProjectStore(s => s.removeSlot);
  const setSlotPinMap = useProjectStore(s => s.setSlotPinMap);
  const autoAssignContacts = useProjectStore(s => s.autoAssignContacts);

  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [newName, setNewName] = useState('');
  const [newSlotType, setNewSlotType] = useState('');
  const [newSlotCount, setNewSlotCount] = useState(1);
  /** Slot copy whose pin map is being edited */
  const [copyRef, setCopyRef] = useState<{ slot: number; copy: number }>({ slot: 0, copy: 0 });

  const type = moduleTypes.find(t => t.id === selectedId) ?? null;
  const cellTypes = useMemo(
    () => getAllCellTypes({ liberty, externalElements }).map(c => c.name).sort(),
    [liberty, externalElements],
  );
  const usage = useMemo(() => (type ? contactUsage(type) : new Map<string, ContactUse[]>()), [type]);
  const clashes = [...usage.values()].filter(u => u.length > 1).length;

  // Verilog modules the netlists know as whole instances (kept boards, black boxes)
  const verilogModules = useMemo(() => {
    const names = new Set<string>();
    for (const b of Object.values(blocks)) {
      for (const k of b.netlist.keep ?? []) names.add(k);
      for (const i of b.netlist.instances) if (i.module) names.add(i.cellType);
    }
    return [...names].sort();
  }, [blocks]);

  const instancesOf = useCallback((typeId: string) =>
    Object.values(blocks).reduce((n, b) => n + b.placement.modules.filter(m => m.typeId === typeId).length, 0),
  [blocks]);

  const handleCreate = useCallback(() => {
    const id = nextTypeId(moduleTypes);
    addModuleType({ id, name: newName.trim() || id, kind: 'board', widthSteps: 2, slots: [] });
    setNewName('');
    setSelectedId(id);
    setCopyRef({ slot: 0, copy: 0 });
  }, [moduleTypes, newName, addModuleType]);

  const handleRemove = useCallback((t: ModuleType) => {
    const n = instancesOf(t.id);
    const placed = n ? ` It is placed ${n} time${n !== 1 ? 's' : ''}; those modules go too.` : '';
    if (!confirm(`Delete module type "${t.name}"?${placed}`)) return;
    removeModuleType(t.id);
    if (selectedId === t.id) setSelectedId(null);
  }, [instancesOf, removeModuleType, selectedId]);

  const handleWidth = useCallback((steps: number) => {
    if (!type) return;
    updateModuleType(type.id, { widthSteps: steps });
    if (useProjectStore.getState().moduleTypes.find(t => t.id === type.id)?.widthSteps !== steps) {
      alert('A placed module of this type would no longer fit its row at that width.');
    }
  }, [type, updateModuleType]);

  const handleAddSlot = useCallback(() => {
    if (!type || !newSlotType || newSlotCount < 1) return;
    addSlot(type.id, newSlotType, newSlotCount);
    setCopyRef({ slot: type.slots.length, copy: 0 });
  }, [type, newSlotType, newSlotCount, addSlot]);

  // Pin map of the copy being edited
  const slot = type?.slots[copyRef.slot];
  const copy = slot && copyRef.copy < slot.count ? copyRef.copy : 0;
  const pinMap: PinMapping[] = slot?.pinMaps[copy] ?? [];
  const cellPins = slot ? getCellPins({ liberty, externalElements }, slot.cellType) ?? [] : [];

  const setContact = useCallback((cellPin: string, contactId: string) => {
    if (!type || !slot) return;
    const next = pinMap.filter(m => m.cellPin !== cellPin);
    if (contactId) next.push({ cellPin, contactId });
    setSlotPinMap(type.id, copyRef.slot, copy, next);
  }, [type, slot, pinMap, copyRef.slot, copy, setSlotPinMap]);

  return (
    <div className="split-layout">
      {/* ---- Type list ---- */}
      <div>
        <div className="panel">
          <h2>Module Types</h2>
          {moduleTypes.length === 0 ? (
            <p style={{ fontSize: 12, fontStyle: 'italic', marginBottom: 8 }}>
              No module types yet. A module type is one PCB design: 140×140 mm with a 2×36
              edge connector, carrying a set of cells.
            </p>
          ) : (
            <ul className="item-list" style={{ marginBottom: 8 }}>
              {moduleTypes.map(t => (
                <li
                  key={t.id}
                  className={t.id === selectedId ? 'selected' : ''}
                  onClick={() => { setSelectedId(t.id); setCopyRef({ slot: 0, copy: 0 }); }}
                >
                  <span>
                    <span style={{ fontWeight: 600 }}>{t.name}</span>
                    <span style={{ fontSize: 11, color: 'var(--text-secondary)', marginLeft: 6 }}>
                      {t.id} · {t.widthSteps * 12} mm · {slotCount(t)} cells · {formatTubes(moduleTubes(t, liberty))}
                    </span>
                    {t.kind === 'interconnect' && <span className="badge badge-inout" style={{ marginLeft: 6 }}>interconnect</span>}
                  </span>
                  <button
                    className="btn btn-danger btn-small"
                    onClick={e => { e.stopPropagation(); handleRemove(t); }}
                    aria-label={`Delete ${t.name}`}
                  >
                    ×
                  </button>
                </li>
              ))}
            </ul>
          )}
          <div style={{ display: 'flex', gap: 6 }}>
            <input
              type="text"
              value={newName}
              onChange={e => setNewName(e.target.value)}
              onKeyDown={e => { if (e.key === 'Enter') handleCreate(); }}
              placeholder="New type name"
              style={{ flex: 1 }}
            />
            <button className="btn btn-primary btn-small" onClick={handleCreate}>+ Type</button>
          </div>
        </div>
      </div>

      {/* ---- Editor ---- */}
      <div>
        {!type ? (
          <div className="panel">
            <p style={{ color: 'var(--text-secondary)', fontStyle: 'italic' }}>Select or create a module type.</p>
          </div>
        ) : (
          <>
            <div className="panel">
              <h2>Properties — {type.id}</h2>
              <div className="form-row">
                <div className="form-group">
                  <label htmlFor="mt-name">Name</label>
                  <input
                    id="mt-name"
                    key={`${type.id}-name-${type.name}`}
                    type="text"
                    defaultValue={type.name}
                    onBlur={e => { if (e.target.value !== type.name) updateModuleType(type.id, { name: e.target.value }); }}
                  />
                </div>
                <div className="form-group">
                  <label htmlFor="mt-kind">Kind</label>
                  <select
                    id="mt-kind"
                    value={type.kind}
                    onChange={e => updateModuleType(type.id, { kind: e.target.value as ModuleKind })}
                    title="An interconnect board links neighbouring modules; its links are not routed"
                  >
                    <option value="board">board</option>
                    <option value="interconnect">interconnect</option>
                  </select>
                </div>
              </div>
              <div className="form-row">
                <div className="form-group">
                  <label htmlFor="mt-width">Width</label>
                  <select id="mt-width" value={type.widthSteps} onChange={e => handleWidth(Number(e.target.value))}>
                    {WIDTH_STEPS.map(w => <option key={w} value={w}>{w} × 12 = {w * 12} mm</option>)}
                  </select>
                </div>
                <div className="form-group">
                  <label htmlFor="mt-verilog">Verilog module</label>
                  <input
                    id="mt-verilog"
                    key={`${type.id}-vm-${type.verilogModule ?? ''}`}
                    type="text"
                    list="mt-verilog-modules"
                    defaultValue={type.verilogModule ?? ''}
                    placeholder="e.g. DekatronModule"
                    title="Netlist submodule this board replaces; it is kept whole when parsing"
                    onBlur={e => {
                      if (e.target.value.trim() !== (type.verilogModule ?? '')) {
                        updateModuleType(type.id, { verilogModule: e.target.value });
                      }
                    }}
                  />
                  <datalist id="mt-verilog-modules">
                    {verilogModules.map(m => <option key={m} value={m} />)}
                  </datalist>
                </div>
              </div>
              <div className="form-row">
                <div className="form-group">
                  <label htmlFor="mt-power">Power (W, for reference)</label>
                  <input
                    id="mt-power"
                    key={`${type.id}-pw-${type.powerW ?? ''}`}
                    type="number"
                    min={0}
                    defaultValue={type.powerW ?? ''}
                    onBlur={e => {
                      const v = e.target.value === '' ? undefined : Number(e.target.value);
                      if (v !== type.powerW && (v === undefined || v >= 0)) updateModuleType(type.id, { powerW: v });
                    }}
                  />
                </div>
                <div className="form-group">
                  <label>Tubes</label>
                  <input type="text" readOnly value={formatTubes(moduleTubes(type, liberty))} />
                </div>
              </div>
            </div>

            <div className="panel">
              <h2>Slots</h2>
              {type.slots.length > 0 && (
                <table className="data-table" style={{ marginBottom: 8 }}>
                  <thead>
                    <tr><th>Cell type</th><th>Count</th><th>Pins mapped</th><th /></tr>
                  </thead>
                  <tbody>
                    {type.slots.map((sl, i) => {
                      const pins = getCellPins({ liberty, externalElements }, sl.cellType);
                      const mapped = sl.pinMaps.reduce((n, m) => n + m.length, 0);
                      return (
                        <tr key={i}>
                          <td>
                            <select
                              value={sl.cellType}
                              onChange={e => updateSlot(type.id, i, { cellType: e.target.value })}
                              aria-label={`Cell type of slot ${i + 1}`}
                            >
                              {!cellTypes.includes(sl.cellType) && <option value={sl.cellType}>{sl.cellType} (unknown)</option>}
                              {cellTypes.map(c => <option key={c} value={c}>{c}</option>)}
                            </select>
                          </td>
                          <td>
                            <input
                              key={`${i}-${sl.count}`}
                              type="number"
                              min={1}
                              defaultValue={sl.count}
                              aria-label={`Count of slot ${i + 1}`}
                              style={{ width: 60 }}
                              onBlur={e => {
                                const n = Math.round(Number(e.target.value));
                                if (n >= 1 && n !== sl.count) updateSlot(type.id, i, { count: n });
                              }}
                            />
                          </td>
                          <td>{pins ? `${mapped} / ${pins.length * sl.count}` : '— (unknown cell)'}</td>
                          <td>
                            <button
                              className="btn btn-danger btn-small"
                              onClick={() => removeSlot(type.id, i)}
                              aria-label={`Remove slot ${i + 1}`}
                            >
                              ×
                            </button>
                          </td>
                        </tr>
                      );
                    })}
                  </tbody>
                </table>
              )}
              {cellTypes.length === 0 ? (
                <p style={{ fontSize: 12, fontStyle: 'italic' }}>Load a liberty file or add elements first.</p>
              ) : (
                <div style={{ display: 'flex', gap: 6, alignItems: 'center' }}>
                  <select value={newSlotType} onChange={e => setNewSlotType(e.target.value)} aria-label="New slot cell type">
                    <option value="">Cell type…</option>
                    {cellTypes.map(c => <option key={c} value={c}>{c}</option>)}
                  </select>
                  <input
                    type="number"
                    min={1}
                    value={newSlotCount}
                    onChange={e => setNewSlotCount(Math.max(1, Math.round(Number(e.target.value)) || 1))}
                    aria-label="New slot count"
                    style={{ width: 60 }}
                  />
                  <button className="btn btn-small" onClick={handleAddSlot} disabled={!newSlotType}>+ Slot</button>
                </div>
              )}
            </div>

            {type.slots.length > 0 && (
              <div className="split-layout equal">
                <div className="panel">
                  <h2>Pin Map</h2>
                  <div style={{ display: 'flex', gap: 4, flexWrap: 'wrap', marginBottom: 8 }}>
                    {type.slots.flatMap((sl, i) => Array.from({ length: sl.count }, (_, c) => (
                      <button
                        key={`${i}-${c}`}
                        className={`btn btn-small ${i === copyRef.slot && c === copy ? 'btn-primary' : ''}`}
                        onClick={() => setCopyRef({ slot: i, copy: c })}
                      >
                        {sl.cellType} #{c + 1}
                      </button>
                    )))}
                  </div>
                  {cellPins.length === 0 ? (
                    <p style={{ fontSize: 12, fontStyle: 'italic' }}>The cell type is unknown: no pins.</p>
                  ) : (
                    <table className="data-table">
                      <thead>
                        <tr><th>Pin</th><th>Dir</th><th>Contact</th></tr>
                      </thead>
                      <tbody>
                        {cellPins.map(p => {
                          const current = pinMap.find(m => m.cellPin === p.name)?.contactId ?? '';
                          return (
                            <tr key={p.name}>
                              <td style={{ fontFamily: 'var(--font-mono)' }}>{p.name}</td>
                              <td><span className={`badge badge-${p.type === 'signal' ? p.direction : p.type}`}>{p.type === 'signal' ? p.direction : p.type}</span></td>
                              <td>
                                <select
                                  value={current}
                                  onChange={e => setContact(p.name, e.target.value)}
                                  aria-label={`Contact of ${p.name}`}
                                  style={{ fontFamily: 'var(--font-mono)', fontSize: 12 }}
                                >
                                  <option value="">—</option>
                                  {CONTACT_IDS.map(c => {
                                    const others = (usage.get(c) ?? []).filter(u =>
                                      !(u.slotDefIndex === copyRef.slot && u.copy === copy && u.cellPin === p.name));
                                    return (
                                      <option key={c} value={c}>
                                        {c}{others.length ? ` · ${contactLabel(type, others[0])}` : ''}
                                      </option>
                                    );
                                  })}
                                </select>
                              </td>
                            </tr>
                          );
                        })}
                      </tbody>
                    </table>
                  )}
                  <button
                    className="btn btn-small"
                    style={{ marginTop: 8 }}
                    onClick={() => autoAssignContacts(type.id)}
                    title="Give every unmapped signal pin of every copy the next free contact"
                  >
                    Auto-assign free contacts
                  </button>
                </div>

                <div className="panel">
                  <h2>Connector 2×36</h2>
                  {clashes > 0 && (
                    <p style={{ fontSize: 12, color: 'var(--warning)', marginBottom: 6 }}>
                      {clashes} contact{clashes !== 1 ? 's' : ''} carry more than one pin.
                    </p>
                  )}
                  <table className="data-table" style={{ fontSize: 11 }}>
                    <thead>
                      <tr><th>#</th><th>A</th><th>B</th></tr>
                    </thead>
                    <tbody>
                      {Array.from({ length: CONTACTS_PER_SIDE }, (_, i) => (
                        <tr key={i}>
                          <td style={{ color: 'var(--text-secondary)' }}>{i + 1}</td>
                          {(['A', 'B'] as const).map(side => {
                            const uses = usage.get(`${side}${i + 1}`) ?? [];
                            return (
                              <td
                                key={side}
                                data-testid={`contact-${side}${i + 1}`}
                                onClick={() => uses[0] && setCopyRef({ slot: uses[0].slotDefIndex, copy: uses[0].copy })}
                                style={{
                                  fontFamily: 'var(--font-mono)',
                                  cursor: uses.length ? 'pointer' : 'default',
                                  background: uses.length > 1 ? 'rgba(255, 201, 71, 0.2)' : undefined,
                                }}
                              >
                                {uses.map(u => contactLabel(type, u)).join(', ')}
                              </td>
                            );
                          })}
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              </div>
            )}
          </>
        )}
      </div>
    </div>
  );
}
