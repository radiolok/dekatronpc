// Fix: import getAllCellTypes properly instead of require()
import { useCallback, useState, useEffect } from 'react';
import { useProjectStore } from '@/store';
import { getAllCellTypes } from '@/types';
import type { ExternalElement, ElementPin, PinDirection, ElementPinType, CellType } from '@/types';

const EMPTY_PIN: ElementPin = { name: '', direction: 'input', type: 'signal' };

export function ElementEditor() {
  const externalElements = useProjectStore(s => s.externalElements);
  const liberty = useProjectStore(s => s.liberty);
  const addExternalElement = useProjectStore(s => s.addExternalElement);
  const removeExternalElement = useProjectStore(s => s.removeExternalElement);

  const [editName, setEditName] = useState('');
  const [editDesc, setEditDesc] = useState('');
  const [editPins, setEditPins] = useState<ElementPin[]>([{ ...EMPTY_PIN }]);
  const [selected, setSelected] = useState<string | null>(null);
  const [allCells, setAllCells] = useState<CellType[]>([]);

  // Refresh combined cell registry when liberty or externalElements change
  useEffect(() => {
    setAllCells(getAllCellTypes(useProjectStore.getState()));
  }, [externalElements, liberty]);

  const resetForm = useCallback(() => {
    setEditName('');
    setEditDesc('');
    setEditPins([{ ...EMPTY_PIN }]);
    setSelected(null);
  }, []);

  const handleSelect = useCallback((name: string) => {
    setSelected(name);
    const el = externalElements[name];
    if (el) {
      setEditName(el.name);
      setEditDesc(el.description ?? '');
      setEditPins(el.pins.length > 0 ? el.pins.map(p => ({ ...p })) : [{ ...EMPTY_PIN }]);
    }
  }, [externalElements]);

  const handleAdd = useCallback(() => {
    if (!editName.trim()) {
      alert('Element name is required');
      return;
    }
    const validPins = editPins.filter(p => p.name.trim());
    if (validPins.length === 0) {
      alert('At least one pin is required');
      return;
    }
    addExternalElement({
      name: editName.trim(),
      description: editDesc.trim() || undefined,
      pins: validPins.map(p => ({ ...p, name: p.name.trim() })),
    });
    resetForm();
  }, [editName, editDesc, editPins, addExternalElement, resetForm]);

  const handleRemove = useCallback((name: string) => {
    if (confirm(`Delete element "${name}"?`)) {
      removeExternalElement(name);
      if (selected === name) resetForm();
    }
  }, [removeExternalElement, selected, resetForm]);

  const updatePin = useCallback((index: number, field: keyof ElementPin, value: string) => {
    setEditPins(prev => {
      const next = [...prev];
      if (field === 'name') {
        next[index] = { ...next[index], name: value };
      } else if (field === 'direction') {
        next[index] = { ...next[index], direction: value as PinDirection };
      } else if (field === 'type') {
        next[index] = { ...next[index], type: value as ElementPinType };
      }
      return next;
    });
  }, []);

  const addPinRow = useCallback(() => {
    setEditPins(prev => [...prev, { ...EMPTY_PIN }]);
  }, []);

  const removePinRow = useCallback((index: number) => {
    setEditPins(prev => prev.filter((_, i) => i !== index));
  }, []);

  const elementList = Object.keys(externalElements).sort();

  return (
    <div className="split-layout">
      {/* Left: list */}
      <div>
        <div className="panel">
          <h2>External Elements ({elementList.length})</h2>
          {elementList.length === 0 ? (
            <p style={{ color: 'var(--text-secondary)', fontStyle: 'italic', fontSize: 13 }}>
              No external elements defined. Create one on the right.
            </p>
          ) : (
            <ul className="item-list">
              {elementList.map(name => (
                <li
                  key={name}
                  className={selected === name ? 'selected' : ''}
                  onClick={() => handleSelect(name)}
                >
                  <span>
                    <span style={{ fontFamily: 'var(--font-mono)' }}>{name}</span>
                    {externalElements[name].description && (
                      <span style={{ color: 'var(--text-secondary)', marginLeft: 8, fontSize: 11 }}>
                        — {externalElements[name].description}
                      </span>
                    )}
                  </span>
                  <span style={{ display: 'flex', gap: 4, alignItems: 'center' }}>
                    <span style={{ fontSize: 11, color: 'var(--text-secondary)' }}>
                      {externalElements[name].pins.length} pins
                    </span>
                    <button
                      className="btn btn-danger btn-small"
                      onClick={e => { e.stopPropagation(); handleRemove(name); }}
                    >
                      Del
                    </button>
                  </span>
                </li>
              ))}
            </ul>
          )}
        </div>
      </div>

      {/* Right: editor */}
      <div>
        <div className="panel">
          <h2>{selected ? `Edit: ${selected}` : 'New Element'}</h2>

          <div className="form-group">
            <label>Name</label>
            <input
              type="text"
              value={editName}
              onChange={e => setEditName(e.target.value)}
              placeholder="e.g. DECATRON_CELL, PWR_MODULE"
            />
          </div>

          <div className="form-group">
            <label>Description (optional)</label>
            <input
              type="text"
              value={editDesc}
              onChange={e => setEditDesc(e.target.value)}
              placeholder="Brief description..."
            />
          </div>

          <div className="form-group">
            <label>Pins</label>
            <div style={{ border: '1px solid var(--border)', borderRadius: 4, overflow: 'hidden' }}>
              <table className="data-table" style={{ margin: 0 }}>
                <thead>
                  <tr>
                    <th style={{ width: '35%' }}>Name</th>
                    <th style={{ width: '25%' }}>Direction</th>
                    <th style={{ width: '25%' }}>Type</th>
                    <th style={{ width: '15%' }}></th>
                  </tr>
                </thead>
                <tbody>
                  {editPins.map((pin, i) => (
                    <tr key={i}>
                      <td>
                        <input
                          type="text"
                          value={pin.name}
                          onChange={e => updatePin(i, 'name', e.target.value)}
                          placeholder="pin name"
                          style={{ width: '100%', padding: '2px 4px', background: 'var(--bg-primary)', color: 'var(--text-primary)', border: '1px solid var(--border)', borderRadius: 3, fontSize: 12 }}
                        />
                      </td>
                      <td>
                        <select
                          value={pin.direction}
                          onChange={e => updatePin(i, 'direction', e.target.value)}
                          style={{ width: '100%', padding: '2px 4px', background: 'var(--bg-primary)', color: 'var(--text-primary)', border: '1px solid var(--border)', borderRadius: 3, fontSize: 12 }}
                        >
                          <option value="input">input</option>
                          <option value="output">output</option>
                          <option value="inout">inout</option>
                          <option value="internal">internal</option>
                        </select>
                      </td>
                      <td>
                        <select
                          value={pin.type}
                          onChange={e => updatePin(i, 'type', e.target.value)}
                          style={{ width: '100%', padding: '2px 4px', background: 'var(--bg-primary)', color: 'var(--text-primary)', border: '1px solid var(--border)', borderRadius: 3, fontSize: 12 }}
                        >
                          <option value="signal">signal</option>
                          <option value="power">power</option>
                          <option value="ground">ground</option>
                          <option value="clock">clock</option>
                        </select>
                      </td>
                      <td>
                        <button
                          className="btn btn-danger btn-small"
                          onClick={() => removePinRow(i)}
                          disabled={editPins.length <= 1}
                          style={{ fontSize: 10 }}
                        >
                          X
                        </button>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
            <button className="btn btn-small" onClick={addPinRow} style={{ marginTop: 8 }}>
              + Add Pin
            </button>
          </div>

          <div style={{ display: 'flex', gap: 8, marginTop: 12 }}>
            <button className="btn btn-primary" onClick={handleAdd}>
              {selected ? 'Update Element' : 'Create Element'}
            </button>
            <button className="btn" onClick={resetForm}>Clear</button>
          </div>
        </div>

        {/* Preview of registered element types */}
        <div className="panel">
          <h2>All Registered Cell Types ({allCells.length})</h2>
          <table className="data-table">
            <thead>
              <tr>
                <th>Name</th>
                <th>Source</th>
                <th>Pins</th>
              </tr>
            </thead>
            <tbody>
              {allCells.map(cell => (
                <tr key={cell.name}>
                  <td style={{ fontFamily: 'var(--font-mono)' }}>{cell.name}</td>
                  <td>
                    <span className={`badge ${cell.source === 'liberty' ? 'badge-input' : 'badge-output'}`}>
                      {cell.source}
                    </span>
                  </td>
                  <td>
                    {cell.pins.map(pin => (
                      <span key={pin.name} className={`badge badge-${pin.type}`} style={{ marginRight: 4 }}>
                        {pin.name}
                      </span>
                    ))}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
}
