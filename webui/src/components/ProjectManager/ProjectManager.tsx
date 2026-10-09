// ============================================================================
// ProjectManager — Project creation, settings, file operations
// ============================================================================

import { useCallback, useState } from 'react';
import { useProjectStore } from '@/store';
import { saveProjectToFile, loadProjectFromFile, clearAutosave } from '@/services';
import { blockHeight, columnsPerRow, type Block } from '@/types';

export function ProjectManager() {
  const { meta, block, liberty, externalElements, moduleTypes, blocks } = useProjectStore();
  const setProjectName = useProjectStore(s => s.setProjectName);
  const [isSaving, setIsSaving] = useState(false);

  const blockList = Object.values(blocks);
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
          <h2>Block Configuration</h2>

          <div className="form-row">
            <div className="form-group">
              <label>Rows</label>
              <input type="number" readOnly value={block.rows} />
            </div>
            <div className="form-group">
              <label>Columns per Row</label>
              <input type="number" readOnly value={columnsPerRow(block)} />
            </div>
          </div>

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
              <label>Transformer Width (mm)</label>
              <input type="number" readOnly value={block.transformerWidth} />
            </div>
          </div>

          <div className="form-row">
            <div className="form-group">
              <label>Chassis Height (mm)</label>
              <input type="number" readOnly value={blockHeight(block)} />
            </div>
            <div className="form-group">
              <label>Obstructions</label>
              <input type="text" readOnly value={`${block.obstructions.length} zones defined`} />
            </div>
          </div>
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
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
}
