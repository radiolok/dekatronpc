// ============================================================================
// BlockCanvas — Konva drawing of one block from the top: connector strip,
// baskets with the 12 mm grid and the transformer keep-out, module instances.
// Modules and connectors drag with grid snapping; wheel zooms, background pans.
// ============================================================================

import { useCallback, useEffect, useRef, useState } from 'react';
import { Stage, Layer, Rect, Line, Text, Group } from 'react-konva';
import type Konva from 'konva';
import type { Block, BlockConfig, Cable, ModuleType } from '@/types';
import { planModuleMove, transformerSpan } from '@/types';
import { stringToColor } from '@/utils/helpers';
import {
  CONNECTOR_WIDTH,
  MARGIN,
  STRIP_HEIGHT,
  canvasSize,
  cellAt,
  connectorPitch,
  rowTop,
  snapConnector,
  snapToCell,
} from './layout';

export interface BlockCanvasProps {
  block: Block;
  cfg: BlockConfig;
  moduleTypes: ModuleType[];
  cables: Cable[];
  selectedId: string | null;
  /** Module type placed by clicking an empty cell, if any */
  armedTypeId: string | null;
  onSelect: (id: string | null) => void;
  onMove: (id: string, row: number, col: number) => void;
  onPlace: (typeId: string, row: number, col: number) => void;
  onMoveConnector: (id: string, position: number) => void;
}

const MIN_SCALE = 0.3;
const MAX_SCALE = 12;

export function BlockCanvas(props: BlockCanvasProps) {
  const { block, cfg, moduleTypes, cables, selectedId, armedTypeId } = props;
  const containerRef = useRef<HTMLDivElement>(null);
  const [size, setSize] = useState({ width: 800, height: 500 });
  const drawing = canvasSize(cfg, block.rows, block.connectors.length);
  const fitScale = Math.min(size.width / drawing.width, size.height / drawing.height);
  const [view, setView] = useState<{ scale: number; x: number; y: number } | null>(null);
  const scale = view?.scale ?? fitScale;
  /** Drag feedback: where the dragged module would land and whether it can */
  const [ghost, setGhost] = useState<{ id: string; row: number; col: number; ok: boolean } | null>(null);

  useEffect(() => {
    const el = containerRef.current;
    if (!el || typeof ResizeObserver === 'undefined') return;
    const ro = new ResizeObserver(([e]) => {
      const { width, height } = e.contentRect;
      if (width > 0 && height > 0) setSize({ width, height });
    });
    ro.observe(el);
    return () => ro.disconnect();
  }, []);

  // A different block or geometry: fit again
  useEffect(() => setView(null), [block.name, block.rows, cfg]);

  const typeOf = (id: string) => moduleTypes.find(t => t.id === id);

  const handleWheel = useCallback((e: Konva.KonvaEventObject<WheelEvent>) => {
    e.evt.preventDefault();
    const stage = e.target.getStage();
    const pointer = stage?.getPointerPosition();
    if (!stage || !pointer) return;
    const old = stage.scaleX();
    const next = Math.min(MAX_SCALE, Math.max(MIN_SCALE, old * (e.evt.deltaY > 0 ? 1 / 1.1 : 1.1)));
    const at = { x: (pointer.x - stage.x()) / old, y: (pointer.y - stage.y()) / old };
    setView({ scale: next, x: pointer.x - at.x * next, y: pointer.y - at.y * next });
  }, []);

  /** Pointer in drawing mm (origin at the rows' left edge) */
  const pointerMm = (stage: Konva.Stage | null) => {
    const p = stage?.getRelativePointerPosition?.();
    return p ? { x: p.x - MARGIN, y: p.y - MARGIN } : null;
  };

  const handleRowClick = useCallback((e: Konva.KonvaEventObject<MouseEvent>) => {
    const p = pointerMm(e.target.getStage());
    if (!p) return;
    const cell = cellAt(p.x, p.y, cfg, block.rows);
    if (armedTypeId && cell) props.onPlace(armedTypeId, cell.row, cell.col);
    else props.onSelect(null);
  }, [armedTypeId, cfg, block.rows, props]);

  const dragCell = (node: Konva.Node, typeId: string) =>
    snapToCell(node.x(), node.y(), cfg, block.rows, typeOf(typeId)?.widthSteps ?? 1);

  const [t0, t1] = transformerSpan(cfg);
  const cols = Math.floor(cfg.rowWidth / cfg.gridStep);
  const sortedConnectors = [...block.connectors].sort((a, b) => a.position - b.position);

  return (
    <div ref={containerRef} style={{ width: '100%', height: '100%', minHeight: 400, background: 'var(--bg-primary)' }}>
      <Stage
        width={size.width}
        height={size.height}
        scaleX={scale}
        scaleY={scale}
        x={view?.x ?? 0}
        y={view?.y ?? 0}
        draggable
        onWheel={handleWheel}
        onDragEnd={e => {
          if (e.target === e.target.getStage()) setView({ scale, x: e.target.x(), y: e.target.y() });
        }}
      >
        <Layer x={MARGIN} y={MARGIN}>
          {/* Connector strip */}
          <Rect x={0} y={0} width={Math.max(cfg.rowWidth, sortedConnectors.length * connectorPitch)} height={STRIP_HEIGHT}
            fill="#141a33" stroke="#2a2a4a" strokeWidth={0.5} />
          {sortedConnectors.length === 0 && (
            <Text x={4} y={STRIP_HEIGHT / 2 - 4} text="No connectors: add them on Netlist › Ports" fontSize={7} fill="#a0a0b0" />
          )}
          {sortedConnectors.map(c => {
            const cable = cables.find(k => [k.from, k.to].some(e => e.block === block.name && e.connector === c.id));
            const far = cable && (cable.from.block === block.name && cable.from.connector === c.id ? cable.to : cable.from);
            return (
              <Group
                key={c.id}
                name={`connector-${c.id}`}
                x={c.position * connectorPitch}
                y={4}
                draggable
                dragBoundFunc={function (this: Konva.Node, pos) { return { x: pos.x, y: this.absolutePosition().y }; }}
                onDragEnd={e => {
                  const to = snapConnector(e.target.x(), block.connectors.length);
                  e.target.position({ x: c.position * connectorPitch, y: 4 });
                  if (to !== c.position) props.onMoveConnector(c.id, to);
                }}
              >
                <Rect width={CONNECTOR_WIDTH} height={STRIP_HEIGHT - 8} fill="#3a4a7a" stroke="#8fa3ff" strokeWidth={0.6} cornerRadius={2} />
                <Text x={3} y={3} text={`${c.id} HD-68`} fontSize={7} fill="#e8e8e8" />
                <Text x={3} y={13} text={`${c.ports.length}/${c.pins} pins`} fontSize={6} fill="#a0a0b0" />
                <Text x={3} y={21} text={far ? `→ ${far.block}·${far.connector}` : 'no cable'} fontSize={6}
                  fill={far ? '#4ecca3' : '#a0a0b0'} />
              </Group>
            );
          })}

          {/* Baskets */}
          {Array.from({ length: block.rows }, (_, r) => {
            const y = rowTop(r, cfg);
            return (
              <Group key={`row-${r}`}>
                <Rect name={`row-${r}`} x={0} y={y} width={cfg.rowWidth} height={cfg.rowHeight}
                  fill="#16213e" stroke="#2a2a4a" strokeWidth={0.6} onClick={handleRowClick} onTap={handleRowClick as never} />
                {Array.from({ length: cols - 1 }, (_, i) => (
                  <Line key={i} points={[(i + 1) * cfg.gridStep, y, (i + 1) * cfg.gridStep, y + cfg.rowHeight]}
                    stroke="#22305a" strokeWidth={0.3} listening={false} />
                ))}
                <Rect x={t0} y={y} width={t1 - t0} height={cfg.rowHeight} fill="#2b2b3d" stroke="#555" strokeWidth={0.5}
                  listening={false} />
                <Text x={t0} y={y + cfg.rowHeight / 2 - 4} width={t1 - t0} align="center" text={`TRAFO ${t1 - t0} mm`}
                  fontSize={7} fill="#888" listening={false} />
                <Text x={-MARGIN + 2} y={y + cfg.rowHeight / 2 + 8} text={`Row ${r + 1}`} fontSize={7} fill="#a0a0b0"
                  rotation={-90} listening={false} />
              </Group>
            );
          })}

          {/* Modules */}
          {block.placement.modules.map(m => {
            const type = typeOf(m.typeId);
            const w = (type?.widthSteps ?? 1) * cfg.gridStep;
            const elements = block.placement.elements.filter(e => e.moduleInstanceId === m.id).length;
            const slots = type?.slots.reduce((n, s) => n + s.count, 0) ?? 0;
            const selected = m.id === selectedId;
            return (
              <Group
                key={m.id}
                name={`module-${m.id}`}
                x={m.col * cfg.gridStep}
                y={rowTop(m.row, cfg)}
                draggable={!m.locked}
                onClick={e => { e.cancelBubble = true; props.onSelect(m.id); }}
                onTap={e => { e.cancelBubble = true; props.onSelect(m.id); }}
                onDragStart={() => props.onSelect(m.id)}
                onDragMove={e => {
                  const cell = dragCell(e.target, m.typeId);
                  e.target.position({ x: cell.col * cfg.gridStep, y: rowTop(cell.row, cfg) });
                  const ok = !!planModuleMove({ block: cfg, moduleTypes }, block.rows, block.placement.modules,
                    { id: m.id, typeId: m.typeId }, cell.row, cell.col);
                  setGhost({ id: m.id, ...cell, ok });
                }}
                onDragEnd={e => {
                  const cell = dragCell(e.target, m.typeId);
                  setGhost(null);
                  // Snap back; the store moves the module if the drop is valid
                  e.target.position({ x: m.col * cfg.gridStep, y: rowTop(m.row, cfg) });
                  if (cell.row !== m.row || cell.col !== m.col) props.onMove(m.id, cell.row, cell.col);
                }}
              >
                <Rect width={w} height={cfg.rowHeight} cornerRadius={1.5}
                  fill={type?.kind === 'interconnect' ? '#3d3d1f' : stringToColor(m.typeId)} opacity={0.85}
                  stroke={selected ? '#ffffff' : '#0b0b18'} strokeWidth={selected ? 1.4 : 0.6} />
                {/* Edge connector at the bottom */}
                <Rect x={1} y={cfg.rowHeight - 5} width={w - 2} height={4} fill="#c9a227" opacity={0.7} listening={false} />
                <Text x={3} y={4} text={m.id} fontSize={7} fontStyle="bold" fill="#0b0b18" listening={false} />
                {m.locked && <Text x={w - 10} y={4} text="🔒" fontSize={7} listening={false} />}
                <Text x={w / 2 - 4} y={cfg.rowHeight - 10} text={type?.name ?? `? ${m.typeId}`} fontSize={7}
                  fill="#0b0b18" rotation={-90} width={cfg.rowHeight - 24} listening={false} />
                {slots > 0 && (
                  <Text x={3} y={14} text={`${elements}/${slots}`} fontSize={6} fill="#0b0b18" listening={false} />
                )}
              </Group>
            );
          })}
          {/* Drop preview, above the modules */}
          {ghost && (
            <Rect x={ghost.col * cfg.gridStep} y={rowTop(ghost.row, cfg)}
              width={(typeOf(block.placement.modules.find(m => m.id === ghost.id)?.typeId ?? '')?.widthSteps ?? 1) * cfg.gridStep}
              height={cfg.rowHeight} stroke={ghost.ok ? '#4ecca3' : '#e94560'} strokeWidth={1.2} dash={[3, 2]}
              listening={false} />
          )}

        </Layer>
      </Stage>
    </div>
  );
}
