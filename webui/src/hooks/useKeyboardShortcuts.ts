// ============================================================================
// Keyboard shortcuts hook
// ============================================================================

import { useEffect } from 'react';
import { useProjectStore } from '@/store';

export function useKeyboardShortcuts() {
  useEffect(() => {
    function handleKeyDown(e: KeyboardEvent) {
      const mod = e.ctrlKey || e.metaKey;

      // Ctrl+Z — Undo
      if (mod && e.key === 'z' && !e.shiftKey) {
        e.preventDefault();
        const store = useProjectStore.getState();
        if (store.past.length > 0) store.undo();
      }

      // Ctrl+Y or Ctrl+Shift+Z — Redo
      if ((mod && e.key === 'y') || (mod && e.shiftKey && e.key === 'z')) {
        e.preventDefault();
        const store = useProjectStore.getState();
        if (store.future.length > 0) store.redo();
      }
    }

    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, []);
}
