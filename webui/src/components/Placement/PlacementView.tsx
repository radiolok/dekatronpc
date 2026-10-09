// ============================================================================
// PlacementView — "Placement" tab: module instances on the block canvas
// (REQ-PR-007). Element-to-slot placement and auto-placement come later.
// ============================================================================

import { useCallback, useState } from 'react';
import { useProjectStore } from '@/store';
import { firstFreeSpot, planModuleMove } from '@/types';
import { BlockCanvas } from './BlockCanvas';

export function PlacementView() {
  const blocks = useProjectStore(s => s.blocks);
  const activeBlockId = useProjectStore(s => s.activeBlockId);
  const cfg = useProjectStore(s => s.block);
  const moduleTypes = useProjectStore(s => s.moduleTypes);
  const cables = useProjectStore(s => s.cables);
  const setActiveBlock = useProjectStore(s => s.setActiveBlock);
  const addModuleInstance = useProjectStore(s => s.addModuleInstance);
  const moveModuleInstance = useProjectStore(s => s.moveModuleInstance);
  const lockModuleInstance = useProjectStore(s => s.lockModuleInstance);
  const removeModuleInstance = useProjectStore(s => s.removeModuleInstance);
  const moveConnector = useProjectStore(s => s.moveConnector);

  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [armedTypeId, setArmedTypeId] = useState<string | null>(null);
  const [message, setMessage] = useState<string | null>(null);

  const block = activeBlockId ? blocks[activeBlockId] : undefined;
  const blockIds = Object.keys(blocks).sort();
  const selected = block?.placement.modules.find(m => m.id === selectedId);

  const placeAt = useCallback((typeId: string, row: number, col: number) => {
    const id = addModuleInstance(typeId, row, col);
    if (id) {
      setSelectedId(id);
      setMessage(null);
    } else {
      setMessage('No room there: the module would leave the row, cover the transformer or overlap another module.');
    }
  }, [addModuleInstance]);

  const placeFirstFree = useCallback((typeId: string) => {
    if (!block) return;
    const spot = firstFreeSpot({ block: cfg, moduleTypes }, block.rows, block.placement.modules, typeId);
    if (spot) placeAt(typeId, spot.row, spot.col);
    else setMessage('The block is full for this module width.');
  }, [block, cfg, moduleTypes, placeAt]);

  const handleMove = useCallback((id: string, row: number, col: number) => {
    if (!block) return;
    const m = block.placement.modules.find(x => x.id === id);
    if (!m) return;
    const plan = planModuleMove({ block: cfg, moduleTypes }, block.rows, block.placement.modules, { id, typeId: m.typeId }, row, col);
    if (!plan) {
      setMessage('Cannot move there: no room, or a locked module is in the way.');
      return;
    }
    moveModuleInstance(id, row, col, { push: true });
    setMessage(plan.size > 1 ? `Moved ${id}; shifted ${plan.size - 1} module${plan.size > 2 ? 's' : ''} aside.` : null);
  }, [block, cfg, moduleTypes, moveModuleInstance]);

  if (blockIds.length === 0) {
    return (
      <div className="panel">
        <p style={{ color: 'var(--text-secondary)', fontStyle: 'italic' }}>
          No blocks yet. Load a netlist on the Netlist tab, or add a block there.
        </p>
      </div>
    );
  }

  return (
    // Fixed height: the canvas must not resize when the sidebar grows (it would rescale mid-drag)
    <div style={{ display: 'grid', gridTemplateColumns: '280px 1fr', gap: 16, height: 'calc(100vh - 120px)', minHeight: 420 }}>
      <div style={{ overflowY: 'auto' }}>
        <div className="panel">
          <div className="form-group">
            <label htmlFor="pl-block">Block</label>
            <select
              id="pl-block"
              value={activeBlockId ?? ''}
              onChange={e => { setActiveBlock(e.target.value || null); setSelectedId(null); }}
            >
              <option value="">— none —</option>
              {blockIds.map(id => <option key={id} value={id}>{id} ({blocks[id].rows} rows)</option>)}
            </select>
          </div>
          <p style={{ fontSize: 11, color: 'var(--text-secondary)' }}>
            Drag a module to move it; others shift aside if there is room. Wheel zooms, dragging the
            background pans. Connectors above the baskets drag to reorder.
          </p>
        </div>

        {block && (
          <>
            <div className="panel">
              <h2>Module Types</h2>
              {moduleTypes.length === 0 ? (
                <p style={{ fontSize: 12, fontStyle: 'italic' }}>Define module types on the Modules tab.</p>
              ) : (
                <table className="data-table">
                  <tbody>
                    {moduleTypes.map(t => (
                      <tr key={t.id}>
                        <td>
                          {t.name}
                          <span style={{ fontSize: 11, color: 'var(--text-secondary)', marginLeft: 4 }}>{t.widthSteps * 12} mm</span>
                        </td>
                        <td style={{ whiteSpace: 'nowrap' }}>
                          <button className="btn btn-small" onClick={() => placeFirstFree(t.id)} title="Place at the first free position">
                            Place
                          </button>
                          <button
                            className={`btn btn-small ${armedTypeId === t.id ? 'btn-primary' : ''}`}
                            style={{ marginLeft: 4 }}
                            onClick={() => setArmedTypeId(armedTypeId === t.id ? null : t.id)}
                            title="Then click an empty cell on the canvas"
                            aria-pressed={armedTypeId === t.id}
                            aria-label={`Click to place ${t.name}`}
                          >
                            ✚
                          </button>
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              )}
            </div>

            {selected && (
              <div className="panel">
                <h2>Module {selected.id}</h2>
                <table className="data-table" style={{ marginBottom: 8 }}>
                  <tbody>
                    <tr><td>Type</td><td>{moduleTypes.find(t => t.id === selected.typeId)?.name ?? selected.typeId}</td></tr>
                    <tr><td>Row</td><td>{selected.row + 1}</td></tr>
                    <tr><td>Column</td><td>{selected.col} ({selected.col * cfg.gridStep} mm)</td></tr>
                  </tbody>
                </table>
                <div style={{ display: 'flex', gap: 6 }}>
                  <button className="btn btn-small" onClick={() => lockModuleInstance(selected.id, !selected.locked)}>
                    {selected.locked ? 'Unlock' : 'Lock'}
                  </button>
                  <button
                    className="btn btn-danger btn-small"
                    onClick={() => { removeModuleInstance(selected.id); setSelectedId(null); }}
                  >
                    Remove
                  </button>
                </div>
              </div>
            )}

            <div className="panel">
              <h2>Placed ({block.placement.modules.length})</h2>
              <ul className="item-list">
                {[...block.placement.modules].sort((a, b) => a.row - b.row || a.col - b.col).map(m => (
                  <li key={m.id} className={m.id === selectedId ? 'selected' : ''} onClick={() => setSelectedId(m.id)}>
                    <span>
                      {m.locked ? '🔒 ' : ''}{m.id}
                      <span style={{ fontSize: 11, color: 'var(--text-secondary)', marginLeft: 6 }}>
                        {moduleTypes.find(t => t.id === m.typeId)?.name} · row {m.row + 1}, col {m.col}
                      </span>
                    </span>
                  </li>
                ))}
              </ul>
            </div>
          </>
        )}
      </div>

      <div className="panel" style={{ padding: 0, overflow: 'hidden', display: 'flex', flexDirection: 'column' }}>
        {message && (
          <p role="status" style={{ fontSize: 12, padding: '6px 10px', color: 'var(--warning)' }}>{message}</p>
        )}
        {block ? (
          <div style={{ flex: 1 }}>
            <BlockCanvas
              block={block}
              cfg={cfg}
              moduleTypes={moduleTypes}
              cables={cables}
              selectedId={selectedId}
              armedTypeId={armedTypeId}
              onSelect={setSelectedId}
              onMove={handleMove}
              onPlace={placeAt}
              onMoveConnector={moveConnector}
            />
          </div>
        ) : (
          <p style={{ padding: 16, fontStyle: 'italic' }}>Select a block.</p>
        )}
      </div>
    </div>
  );
}
