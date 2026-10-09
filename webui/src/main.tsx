import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import { App } from './components/App';
import { useProjectStore } from './store';
import { loadAutosave } from './services';

// Pick up where the last session left off
const autosaved = loadAutosave();
if (autosaved) useProjectStore.getState().loadProject(autosaved);

const root = document.getElementById('root');
if (!root) throw new Error('Root element not found');

createRoot(root).render(
  <StrictMode>
    <App />
  </StrictMode>,
);
