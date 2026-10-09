// ============================================================================
// ProjectManager — Project creation, settings, file operations
// ============================================================================

import { useCallback, useMemo, useState } from 'react';
import { useProjectStore } from '@/store';
import { saveProjectToFile, loadProjectFromFile, clearAutosave } from '@/services';
import { cableLinks, unassignedPorts } from '@/services/interconnect';
import {
  blockHeight,
  columnsPerRow,
  ROWS_MIN,
  ROWS_MAX,
  TRANSFORMER_WIDTH_MIN,
  TRANSFORMER_WIDTH_MAX,
  type Block,
  type CableEnd,
} from '@/types';

const endKey = (e: CableEnd) => `${e.block}\u0000${e.connector}`;
const parseEnd = (k: string): CableEnd => {
  const [block, connector] = k.split('\u0000');
  return { block, connector };
};

export function ProjectManager() {
  const { meta, block, liberty, externalElements, moduleTypes, blocks, cables } = useProjectStore();
  const setProjectName = useProjectStore(s => s.setProjectName);
  const setBlockConfig = useProjectStore(s => s.setBlockConfig);
  const setBlockRows = useProjectStore(s => s.setBlockRows);
  const addCable = useProjectStore(s => s.addCable);
  const removeCable = useProjectStore(s => s.removeCable);
  const [isSaving, setIsSaving] = useState(false);
  const [cableFrom, setCableFrom] = useState('');
  const [cableTo, setCableTo] = useState('');

  const blockList = Object.values(blocks).sort((a, b) => a.name.localeCompare(b.name));
  const transformerWidths: number[] = [];
  for (let w = TRANSFORMER_WIDTH_MIN; w <= TRANSFORMER_WIDTH_MAX; w += block.gridStep) transformerWidths.push(w);

  // Connectors not yet on a cable can take one
  const freeEnds = blockList.flatMap(b => b.connectors
    .filter(c => !cables.some(k => [k.from, k.to].some(e => e.block === b.name && e.connector === c.id)))
    .map(c => ({ block: b.name, connector: c.id })));
  const links = useMemo(() => cableLinks({ meta, liberty, externalElements, moduleTypes, block, blocks, cables }),
    [meta, liberty, externalElements, moduleTypes, block, blocks, cables]);
  const badLinks = links.filter(l => l.problems.length > 0).length;

  const handleAddCable = useCallback(() => {
    if (!cableFrom || !cableTo) return;
    if (addCable(parseEnd(cableFrom), parseEnd(cableTo))) {
      setCableFrom('');
      setCableTo('');
    } else {
      alert('A cable joins connectors of two different blocks, and each connector takes one cable.');
    }
  }, [cableFrom, cableTo, addCable]);

  const total = (f: (b: Block) => number) => blockList.reduce((sum, b) => sum + f(b), 0);

  const handleOpen = useCallback(async () => {
    try {
      const state = await loadProjectFromFile();
      useProjectStore.getState().loadProject(state);
    } catch (err) {
      alert((err as Error).message);
    }
  }, []);

  const handleSave = useCallback(() => {
    setIsSaving(true);
    try {
      saveProjectToFile(useProjectStore.getState());
    } finally {
      setIsSaving(false);
    }
  }, []);

  const handleNew = useCallback(() => {
    if (confirm('Create a new project? Unsaved changes will be lost.')) {
      useProjectStore.getState().newProject('New Project');
      clearAutosave();
    }
  }, []);

  return (
    <div className="split-layout">
      <div>
        <div className="panel">
          <h2>Project Info</h2>

          <div className="form-group">
            <label>Project Name</label>
            <input
              type="text"
              value={meta.projectName}
              onChange={e => setProjectName(e.target.value)}
            />
          </div>

          <div className="form-row">
            <div className="form-group">
              <label>Created</label>
              <input type="text" readOnly value={new Date(meta.createdAt).toLocaleString()} />
            </div>
            <div className="form-group">
              <label>Updated</label>
              <input type="text" readOnly value={new Date(meta.updatedAt).toLocaleString()} />
            </div>
          </div>

          <div className="form-group">
            <label>Format Version</label>
            <input type="text" readOnly value={meta.version} />
          </div>
        </div>

        <div className="panel">
          <h2>File Operations</h2>
          <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap' }}>
            <button className="btn" onClick={handleNew}>New Project</button>
            <button className="btn" onClick={handleOpen}>Open File...</button>
            <button className="btn btn-primary" onClick={handleSave} disabled={isSaving}>
              {isSaving ? 'Saving...' : 'Save As...'}
            </button>
          </div>
        </div>
      </div>

      <div>
        <div className="panel">
          <h2>Basket Geometry</h2>
          <p style={{ fontSize: 12, color: 'var(--text-secondary)', marginBottom: 8 }}>
            Shared by all blocks. A row is one basket; the backplane carries power only.
          </p>

          <div className="form-row">
            <div className="form-group">
              <label>Row Width (mm)</label>
              <input type="number" readOnly value={block.rowWidth} />
            </div>
            <div className="form-group">
              <label>Row Height (mm)</label>
              <input type="number" readOnly value={block.rowHeight} />
            </div>
          </div>

          <div className="form-row">
            <div className="form-group">
              <label>Grid Step (mm)</label>
              <input type="number" readOnly value={block.gridStep} />
            </div>
            <div className="form-group">
              <label>Columns per Row</label>
              <input type="number" readOnly value={columnsPerRow(block)} />
            </div>
          </div>

          <div className="form-row">
            <div className="form-group">
              <label>Transformer Width (mm)</label>
              <select
                value={block.transformerWidth}
                onChange={e => setBlockConfig({ transformerWidth: Number(e.target.value) })}
                title="72 + 12·K mm. A width that would overlap a placed module is refused."
              >
                {transformerWidths.map(w => <option key={w} value={w}>{w}</option>)}
              </select>
            </div>
            <div className="form-group">
              <label>Obstructions</label>
              <input type="text" readOnly value={`${block.obstructions.length} zones defined`} />
            </div>
          </div>
        </div>

        <div className="panel">
          <h2>Blocks</h2>
          {blockList.length === 0 ? (
            <p style={{ fontSize: 12, fontStyle: 'italic' }}>No blocks yet: load a netlist on the Netlist tab.</p>
          ) : (
            <table className="data-table">
              <thead>
                <tr><th>Block</th><th>Rows</th><th>Height</th><th>Connectors</th><th>Ports not on a pin</th></tr>
              </thead>
              <tbody>
                {blockList.map(b => (
                  <tr key={b.name}>
                    <td style={{ fontFamily: 'var(--font-mono)' }}>{b.name}</td>
                    <td>
                      <select
                        value={b.rows}
                        onChange={e => setBlockRows(b.name, Number(e.target.value))}
                        aria-label={`Rows of ${b.name}`}
                      >
                        {Array.from({ length: ROWS_MAX - ROWS_MIN + 1 }, (_, i) => ROWS_MIN + i)
                          .map(r => <option key={r} value={r}>{r}</option>)}
                      </select>
                    </td>
                    <td>{blockHeight(block, b.rows)} mm</td>
                    <td>{b.connectors.map(c => c.id).join(', ') || '—'}</td>
                    <td>{unassignedPorts(b).length}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </div>

        <div className="panel">
          <h2>Cables</h2>
          <p style={{ fontSize: 12, color: 'var(--text-secondary)', marginBottom: 8 }}>
            HD-68 cables between blocks, pin to pin. Add connectors on the Netlist tab (Ports).
          </p>
          {cables.length > 0 && (
            <table className="data-table" style={{ marginBottom: 8 }}>
              <tbody>
                {cables.map(c => (
                  <tr key={c.id}>
                    <td style={{ fontFamily: 'var(--font-mono)' }}>{c.id}</td>
                    <td style={{ fontFamily: 'var(--font-mono)' }}>
                      {c.from.block}·{c.from.connector} ↔ {c.to.block}·{c.to.connector}
                    </td>
                    <td>{links.filter(l => l.cable === c.id).length} signals</td>
                    <td><button className="btn btn-small" onClick={() => removeCable(c.id)}>Remove</button></td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
          {badLinks > 0 && (
            <p style={{ fontSize: 12, color: 'var(--warning)', marginBottom: 8 }}>
              {badLinks} cable pin{badLinks !== 1 ? 's' : ''} with a problem (one end only, unknown port, or driver mismatch).
            </p>
          )}
          {freeEnds.length >= 2 ? (
            <div style={{ display: 'flex', gap: 6, alignItems: 'center', flexWrap: 'wrap' }}>
              {[[cableFrom, setCableFrom, 'From'], [cableTo, setCableTo, 'To']].map(([value, set, label]) => (
                <select
                  key={label as string}
                  value={value as string}
                  onChange={e => (set as (v: string) => void)(e.target.value)}
                  aria-label={`Cable ${label}`}
                >
                  <option value="">{label as string}…</option>
                  {freeEnds.map(e => <option key={endKey(e)} value={endKey(e)}>{e.block}·{e.connector}</option>)}
                </select>
              ))}
              <button className="btn btn-small" onClick={handleAddCable} disabled={!cableFrom || !cableTo}>
                + Cable
              </button>
            </div>
          ) : (
            <p style={{ fontSize: 12, fontStyle: 'italic' }}>Two free connectors in different blocks are needed for a cable.</p>
          )}
        </div>

        <div className="panel">
          <h2>Project Summary</h2>
          <table className="data-table">
            <tbody>
              <tr><td>Liberty cells loaded</td><td>{Object.keys(liberty).length}</td></tr>
              <tr><td>External elements</td><td>{Object.keys(externalElements).length}</td></tr>
              <tr><td>Module types defined</td><td>{moduleTypes.length}</td></tr>
              <tr><td>Blocks</td><td>{blockList.length}</td></tr>
              <tr><td>Netlist instances (total)</td><td>{total(b => b.netlist.instances.length)}</td></tr>
              <tr><td>Nets (total)</td><td>{total(b => b.netlist.nets.length)}</td></tr>
              <tr><td>Modules placed (total)</td><td>{total(b => b.placement.modules.length)}</td></tr>
              <tr><td>Elements placed (total)</td><td>{total(b => b.placement.elements.length)}</td></tr>
              <tr><td>Routed nets (total)</td><td>{total(b => b.routing.nets.length)}</td></tr>
              <tr><td>Power nets (total)</td><td>{total(b => b.powerNets.length)}</td></tr>
              <tr><td>Cables</td><td>{cables.length}</td></tr>
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
}
