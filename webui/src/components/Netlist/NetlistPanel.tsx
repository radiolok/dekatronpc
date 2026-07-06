// ============================================================================
// NetlistPanel — Load & view Verilog netlist + Liberty file
// ============================================================================

import { useCallback, useState, useMemo } from 'react';
import { useProjectStore } from '@/store';
import { parseVerilogNetlist, parseLiberty, validateCellTypes } from '@/services/parsers';
import { getAllCellTypes } from '@/types';

type SubTab = 'overview' | 'instances' | 'nets' | 'liberty';

export function NetlistPanel() {
  const [subTab, setSubTab] = useState<SubTab>('overview');
  const [verilogText, setVerilogText] = useState('');
  const [libertyText, setLibertyText] = useState('');
  const [parseError, setParseError] = useState<string | null>(null);

  const netlist = useProjectStore(s => s.netlist);
  const liberty = useProjectStore(s => s.liberty);
  const setNetlist = useProjectStore(s => s.setNetlist);
  const setLiberty = useProjectStore(s => s.setLiberty);

  const handleParseVerilog = useCallback(() => {
    try {
      setParseError(null);
      const parsed = parseVerilogNetlist(verilogText);
      setNetlist(parsed);
    } catch (err) {
      setParseError(`Verilog parse error: ${(err as Error).message}`);
    }
  }, [verilogText, setNetlist]);

  const handleParseLiberty = useCallback(() => {
    try {
      setParseError(null);
      const parsed = parseLiberty(libertyText);
      setLiberty(parsed);
    } catch (err) {
      setParseError(`Liberty parse error: ${(err as Error).message}`);
    }
  }, [libertyText, setLiberty]);

  // Validate cell types referenced in netlist
  const missingTypes = useMemo(() => {
    if (netlist.instances.length === 0) return [];
    const knownTypes = new Set(getAllCellTypes(useProjectStore.getState()).map(c => c.name));
    return validateCellTypes(netlist, knownTypes);
  }, [netlist]);

  const subTabs: { id: SubTab; label: string }[] = [
    { id: 'overview', label: 'Overview' },
    { id: 'instances', label: `Instances (${netlist.instances.length})` },
    { id: 'nets', label: `Nets (${netlist.nets.length})` },
    { id: 'liberty', label: `Liberty (${Object.keys(liberty).length})` },
  ];

  return (
    <div>
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
                <label>Paste structural Verilog</label>
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
            </div>

            <div className="panel">
              <h2>Liberty File</h2>
              <div className="form-group">
                <label>Paste Liberty (.lib) content</label>
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
                <tr><td>Instances</td><td>{netlist.instances.length}</td></tr>
                <tr><td>Nets</td><td>{netlist.nets.length}</td></tr>
                <tr><td>Liberty cells</td><td>{Object.keys(liberty).length}</td></tr>
              </tbody>
            </table>
          </div>
        </div>
      )}

      {/* Instances */}
      {subTab === 'instances' && (
        <div className="panel">
          <h2>Netlist Instances</h2>
          {netlist.instances.length === 0 ? (
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
                {netlist.instances.map(inst => (
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
          <h2>Nets</h2>
          {netlist.nets.length === 0 ? (
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
                {netlist.nets.map(net => (
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
