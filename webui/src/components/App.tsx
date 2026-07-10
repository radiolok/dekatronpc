// ============================================================================
// Main application shell with tab navigation
// ============================================================================

import { useState, useCallback, useEffect } from 'react';
import { useProjectStore } from '@/store';
import { loadProjectFromFile, saveProjectToFile, startAutosave } from '@/services';
import { useKeyboardShortcuts } from '@/hooks/useKeyboardShortcuts';
import { ProjectManager } from './ProjectManager/ProjectManager';
import { NetlistPanel } from './Netlist/NetlistPanel';
import { ElementEditor } from './Elements/ElementEditor';
import './App.css';

type TabId = 'project' | 'netlist' | 'elements' | 'modules' | 'placement' | 'routing' | 'assembly';

interface TabInfo {
  id: TabId;
  label: string;
}

const TABS: TabInfo[] = [
  { id: 'project', label: 'Project' },
  { id: 'netlist', label: 'Netlist' },
  { id: 'elements', label: 'Elements' },
  { id: 'modules', label: 'Modules' },
  { id: 'placement', label: 'Placement' },
  { id: 'routing', label: 'Routing' },
  { id: 'assembly', label: 'Assembly' },
];

export function App() {
  const [activeTab, setActiveTab] = useState<TabId>('project');

  const { meta, undo, redo, past, future, pushHistory } = useProjectStore();
  const canUndo = past.length > 0;
  const canRedo = future.length > 0;

  // Keyboard shortcuts
  useKeyboardShortcuts();

  // Autosave
  useEffect(() => {
    const stop = startAutosave(() => useProjectStore.getState());
    return stop;
  }, []);

  const handleNew = useCallback(() => {
    useProjectStore.getState().newProject('New Project');
  }, []);

  const handleOpen = useCallback(async () => {
    try {
      const state = await loadProjectFromFile();
      useProjectStore.getState().loadProject(state);
    } catch (err) {
      alert((err as Error).message);
    }
  }, []);

  const handleSave = useCallback(() => {
    saveProjectToFile(useProjectStore.getState());
  }, []);

  const handleUndo = useCallback(() => {
    if (canUndo) undo();
  }, [canUndo, undo]);

  const handleRedo = useCallback(() => {
    if (canRedo) redo();
  }, [canRedo, redo]);

  function renderTabContent() {
    switch (activeTab) {
      case 'project':
        return <ProjectManager />;
      case 'netlist':
        return <NetlistPanel />;
      case 'elements':
        return <ElementEditor />;
      case 'modules':
        return <PlaceholderTab label="Modules" />;
      case 'placement':
        return <PlaceholderTab label="Placement" />;
      case 'routing':
        return <PlaceholderTab label="Routing" />;
      case 'assembly':
        return <PlaceholderTab label="Assembly" />;
    }
  }

  return (
    <div className="app">
      <header className="app-header">
        <div className="app-title">
          <h1>DekatronPC</h1>
          <span className="app-subtitle">Block Place &amp; Route</span>
          <span className="app-project-name">{meta.projectName}</span>
        </div>

        <div className="app-toolbar">
          <button onClick={handleNew} title="New project">New</button>
          <button onClick={handleOpen} title="Open project">Open</button>
          <button onClick={handleSave} title="Save project">Save</button>
          <span className="toolbar-separator" />
          <button onClick={handleUndo} disabled={!canUndo} title="Undo (Ctrl+Z)">Undo</button>
          <button onClick={handleRedo} disabled={!canRedo} title="Redo (Ctrl+Y)">Redo</button>
        </div>
      </header>

      <nav className="app-tabs">
        {TABS.map(tab => (
          <button
            key={tab.id}
            className={`tab-button ${activeTab === tab.id ? 'active' : ''}`}
            onClick={() => setActiveTab(tab.id)}
          >
            {tab.label}
          </button>
        ))}
      </nav>

      <main className="app-content">
        {renderTabContent()}
      </main>
    </div>
  );
}

function PlaceholderTab({ label }: { label: string }) {
  return (
    <div className="placeholder-tab">
      <p>{label} — in development.</p>
    </div>
  );
}
