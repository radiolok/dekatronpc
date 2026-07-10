// ============================================================================
// NetlistPanel — Load & view Verilog netlists + Liberty file, multi-block
// ============================================================================

import { useCallback, useState, useMemo, useRef } from 'react';
import { useProjectStore } from '@/store';
import { parseVerilogNetlist, parseLiberty, validateCellTypes } from '@/services/parsers';
import { getAllCellTypes } from '@/types';

type SubTab = 'overview' | 'instances' | 'nets' | 'liberty';

/** Read a file from a file input and call setText with its contents */
function loadFileContent(file: File, setText: (s: string) => void) {
  const reader = new FileReader();
  reader.onload = () => setText(reader.result as string);
  reader.onerror = () => alert(`Failed to read file: ${file.name}`);
  reader.readAsText(file);
}

/** Derive block name from filename: "IpLine_synth.v" → "IpLine" */
function deriveBlockName(filename: string): string {
  return filename.replace(/\.[^.]+$/, '').replace(/_synth$/, '');
}

export function NetlistPanel() {
  const [subTab, setSubTab] = useState<SubTab>('overview');
  const [verilogText, setVerilogText] = useState('');
  const [libertyText, setLibertyText] = useState('');
  const [parseError, setParseError] = useState<string | null>(null);
  const [newBlockName, setNewBlockName] = useState('');

  const verilogInputRef = useRef<HTMLInputElement>(null);
  const libertyInputRef = useRef<HTMLInputElement>(null);

  const blocks = useProjectStore(s => s.blocks);
  const activeBlockId = useProjectStore(s => s.activeBlockId);
  const liberty = useProjectStore(s => s.liberty);
  const setLiberty = useProjectStore(s => s.setLiberty);
  const setBlockNetlist = useProjectStore(s => s.setBlockNetlist);
  const addBlock = useProjectStore(s => s.addBlock);
  const setActiveBlock = useProjectStore(s => s.setActiveBlock);
  const removeBlock = useProjectStore(s => s.removeBlock);

  // Derive active block data for display
  const activeBlock = activeBlockId ? blocks[activeBlockId] : null;
  const activeNetlist = activeBlock?.netlist ?? { instances: [], nets: [] };

  const blockIds = Object.keys(blocks).sort();

  // Store the filename for block naming
  const [lastVerilogFilename, setLastVerilogFilename] = useState('');

  const handleOpenVerilog = useCallback(() => verilogInputRef.current?.click(), []);
  const handleOpenLiberty = useCallback(() => libertyInputRef.current?.click(), []);

  const handleVerilogFile = useCallback((e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (file) {
      setLastVerilogFilename(file.name);
      loadFileContent(file, setVerilogText);
    }
    e.target.value = '';
  }, []);

  const handleLibertyFile = useCallback((e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (file) loadFileContent(file, setLibertyText);
    e.target.value = '';
  }, []);

  const handleParseVerilog = useCallback(() => {
    try {
      setParseError(null);
      const parsed = parseVerilogNetlist(verilogText);
      const blockName = deriveBlockName(lastVerilogFilename) || 'Block_' + Date.now();
      setBlockNetlist(blockName, parsed);
    } catch (err) {
      setParseError(`Verilog parse error: ${(err as Error).message}`);
    }
  }, [verilogText, lastVerilogFilename, setBlockNetlist]);

  const handleParseLiberty = useCallback(() => {
    try {
      setParseError(null);
      const parsed = parseLiberty(libertyText);
      setLiberty(parsed);
    } catch (err) {
      setParseError(`Liberty parse error: ${(err as Error).message}`);
    }
  }, [libertyText, setLiberty]);

  const handleAddBlock = useCallback(() => {
    const name = newBlockName.trim();
    if (name) {
      addBlock(name);
      setNewBlockName('');
    }
  }, [newBlockName, addBlock]);

  // Validate cell types against ALL blocks (shared liberty)
  const missingTypes = useMemo(() => {
    if (activeNetlist.instances.length === 0) return [];
    const knownTypes = new Set(getAllCellTypes(useProjectStore.getState()).map(c => c.name));
    return validateCellTypes(activeNetlist, knownTypes);
  }, [activeNetlist]);

  const subTabs: { id: SubTab; label: string }[] = [
    { id: 'overview', label: 'Overview' },
    { id: 'instances', label: `Instances (${activeNetlist.instances.length})` },
    { id: 'nets', label: `Nets (${activeNetlist.nets.length})` },
    { id: 'liberty', label: `Liberty (${Object.keys(liberty).length})` },
  ];

  return (
    <div>
      {/* Block selector */}
      <div className="panel" style={{ marginBottom: 16, padding: '8px 16px', display: 'flex', alignItems: 'center', gap: 12, flexWrap: 'wrap' }}>
        <span style={{ fontWeight: 600, fontSize: 13, whiteSpace: 'nowrap' }}>Block:</span>
        <select
          value={activeBlockId ?? ''}
          onChange={e => setActiveBlock(e.target.value || null)}
          style={{ minWidth: 140, fontFamily: 'var(--font-mono)', fontSize: 12 }}
        >
          <option value="">— none —</option>
          {blockIds.map(id => (
            <option key={id} value={id}>{id} ({blocks[id].netlist.instances.length} inst)</option>
          ))}
        </select>

        <div style={{ display: 'flex', gap: 4, alignItems: 'center' }}>
          <input
            type="text"
            value={newBlockName}
            onChange={e => setNewBlockName(e.target.value)}
            placeholder="Block name"
            style={{ width: 120, padding: '3px 6px', fontSize: 12 }}
            onKeyDown={e => { if (e.key === 'Enter') handleAddBlock(); }}
          />
          <button className="btn btn-small" onClick={handleAddBlock}>+ New</button>
        </div>

        {blockIds.length > 0 && activeBlockId && (
          <span style={{ fontSize: 11, color: 'var(--text-secondary)', marginLeft: 'auto' }}>
            {blockIds.length} block{blockIds.length !== 1 ? 's' : ''}
          </span>
        )}
      </div>

      {/* Sub-tabs */}
      <div className="app-tabs" style={{ marginBottom: 16 }}>
        {subTabs.map(t => (
          <button
            key={t.id}
            className={`tab-button ${subTab === t.id ? 'active' : ''}`}
            onClick={() => setSubTab(t.id)}
          >
            {t.label}
          </button>
        ))}
      </div>

      {parseError && (
        <div className="panel" style={{ borderColor: 'var(--accent)', background: 'rgba(233,69,96,0.1)' }}>
          <p style={{ color: 'var(--accent)', fontSize: 13 }}>{parseError}</p>
        </div>
      )}

      {missingTypes.length > 0 && (
        <div className="panel" style={{ borderColor: 'var(--warning)' }}>
          <h2>Missing Cell Types</h2>
          <p style={{ fontSize: 13 }}>
            The netlist references cell types not found in liberty or external elements:
          </p>
          <ul style={{ marginLeft: 20, marginTop: 8 }}>
            {missingTypes.map(t => <li key={t} style={{ fontFamily: 'var(--font-mono)', fontSize: 12 }}>{t}</li>)}
          </ul>
        </div>
      )}

      {/* Overview */}
      {subTab === 'overview' && (
        <div className="split-layout equal">
          <div>
            <div className="panel">
              <h2>Verilog Netlist</h2>
              <div className="form-group">
                <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 6 }}>
                  <label style={{ margin: 0 }}>Paste structural Verilog or open a file</label>
                  <button className="btn btn-small" onClick={handleOpenVerilog}>Open File...</button>
                </div>
                <input
                  ref={verilogInputRef}
                  type="file"
                  accept=".v,.sv,.txt"
                  onChange={handleVerilogFile}
                  style={{ display: 'none' }}
                />
                <textarea
                  value={verilogText}
                  onChange={e => setVerilogText(e.target.value)}
                  placeholder={`AND2 U1 (.A(net1), .B(net2), .Y(net3));\nOR2 U2 (.A(net1), .B(net4), .Y(net5));`}
                  style={{ minHeight: 200 }}
                />
              </div>
              <button className="btn btn-primary" onClick={handleParseVerilog}>
                Parse Verilog
              </button>
              {lastVerilogFilename && (
                <span style={{ marginLeft: 8, fontSize: 11, color: 'var(--text-secondary)' }}>
                  Block: <span style={{ fontFamily: 'var(--font-mono)' }}>{deriveBlockName(lastVerilogFilename)}</span>
                </span>
              )}
            </div>

            <div className="panel">
              <h2>Liberty File</h2>
              <div className="form-group">
                <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 6 }}>
                  <label style={{ margin: 0 }}>Paste Liberty (.lib) content or open a file</label>
                  <button className="btn btn-small" onClick={handleOpenLiberty}>Open File...</button>
                </div>
                <input
                  ref={libertyInputRef}
                  type="file"
                  accept=".lib,.txt"
                  onChange={handleLibertyFile}
                  style={{ display: 'none' }}
                />
                <textarea
                  value={libertyText}
                  onChange={e => setLibertyText(e.target.value)}
                  placeholder={`library (DekatronPC) {\n  cell (AND2) {\n    pin (A) { direction : "input"; }\n    pin (B) { direction : "input"; }\n    pin (Y) { direction : "output"; }\n  }\n}`}
                  style={{ minHeight: 200 }}
                />
              </div>
              <button className="btn btn-primary" onClick={handleParseLiberty}>
                Parse Liberty
              </button>
            </div>
          </div>

          <div className="panel">
            <h2>Parse Summary</h2>
            <table className="data-table">
              <tbody>
                <tr><td>Blocks</td><td>{blockIds.length}</td></tr>
                <tr><td>Instances</td><td>{activeNetlist.instances.length}</td></tr>
                <tr><td>Nets</td><td>{activeNetlist.nets.length}</td></tr>
                <tr><td>Liberty cells</td><td>{Object.keys(liberty).length}</td></tr>
              </tbody>
            </table>
            {blockIds.length > 1 && (
              <div style={{ marginTop: 12 }}>
                <h3 style={{ fontSize: 13, marginBottom: 6 }}>All Blocks</h3>
                <table className="data-table">
                  <thead>
                    <tr><th>Block</th><th>Instances</th><th>Nets</th></tr>
                  </thead>
                  <tbody>
                    {blockIds.map(id => (
                      <tr key={id} style={id === activeBlockId ? { background: 'var(--bg-active)' } : {}}>
                        <td style={{ fontFamily: 'var(--font-mono)' }}>{id}</td>
                        <td>{blocks[id].netlist.instances.length}</td>
                        <td>{blocks[id].netlist.nets.length}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
          </div>
        </div>
      )}

      {/* Instances — only shown when block is active */}
      {subTab === 'instances' && (
        <div className="panel">
          <h2>Netlist Instances {activeBlockId ? `— ${activeBlockId}` : ''}</h2>
          {!activeBlockId ? (
            <p style={{ color: 'var(--text-secondary)', fontStyle: 'italic' }}>
              Select or create a block first.
            </p>
          ) : activeNetlist.instances.length === 0 ? (
            <p style={{ color: 'var(--text-secondary)', fontStyle: 'italic' }}>No instances parsed.</p>
          ) : (
            <table className="data-table">
              <thead>
                <tr>
                  <th>Instance</th>
                  <th>Cell Type</th>
                  <th>Connections</th>
                </tr>
              </thead>
              <tbody>
                {activeNetlist.instances.map(inst => (
                  <tr key={inst.name}>
                    <td style={{ fontFamily: 'var(--font-mono)' }}>{inst.name}</td>
                    <td>
                      <span className={`badge badge-input`}>{inst.cellType}</span>
                    </td>
                    <td style={{ fontFamily: 'var(--font-mono)', fontSize: 11 }}>
                      {Object.entries(inst.connections).map(([port, net]) => (
                        <span key={port} style={{ marginRight: 8 }}>
                          .{port}(<span style={{ color: 'var(--success)' }}>{net}</span>)
                        </span>
                      ))}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </div>
      )}

      {/* Nets */}
      {subTab === 'nets' && (
        <div className="panel">
          <h2>Nets {activeBlockId ? `— ${activeBlockId}` : ''}</h2>
          {!activeBlockId ? (
            <p style={{ color: 'var(--text-secondary)', fontStyle: 'italic' }}>
              Select or create a block first.
            </p>
          ) : activeNetlist.nets.length === 0 ? (
            <p style={{ color: 'var(--text-secondary)', fontStyle: 'italic' }}>No nets parsed.</p>
          ) : (
            <table className="data-table">
              <thead>
                <tr>
                  <th>Net Name</th>
                  <th>Terminals</th>
                  <th>Fanout</th>
                </tr>
              </thead>
              <tbody>
                {activeNetlist.nets.map(net => (
                  <tr key={net.name}>
                    <td style={{ fontFamily: 'var(--font-mono)', color: 'var(--success)' }}>{net.name}</td>
                    <td style={{ fontFamily: 'var(--font-mono)', fontSize: 11 }}>
                      {net.terminals.map(t => `${t.instance}.${t.port}`).join(', ')}
                    </td>
                    <td>{net.terminals.length}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </div>
      )}

      {/* Liberty */}
      {subTab === 'liberty' && (
        <div className="panel">
          <h2>Liberty Cells</h2>
          {Object.keys(liberty).length === 0 ? (
            <p style={{ color: 'var(--text-secondary)', fontStyle: 'italic' }}>No liberty cells loaded.</p>
          ) : (
            <table className="data-table">
              <thead>
                <tr>
                  <th>Cell</th>
                  <th>Pins</th>
                </tr>
              </thead>
              <tbody>
                {Object.entries(liberty).map(([name, cell]) => (
                  <tr key={name}>
                    <td style={{ fontFamily: 'var(--font-mono)' }}>{name}</td>
                    <td>
                      {cell.pins.map(pin => (
                        <span key={pin.name} className={`badge badge-${pin.direction}`} style={{ marginRight: 4 }}>
                          {pin.name} ({pin.direction})
                        </span>
                      ))}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </div>
      )}
    </div>
  );
}
