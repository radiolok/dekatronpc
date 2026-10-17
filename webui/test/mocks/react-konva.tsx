// ============================================================================
// DOM stand-in for react-konva in jsdom tests (Konva needs the native `canvas`
// package under Node). Each shape renders a <div data-konva="Rect" data-name=…>.
// A drag ends with a `konva-dragend` CustomEvent whose detail is {x, y}: the
// shape's onDragEnd gets a fake node at that position.
// ============================================================================

import { createElement, useEffect, useRef, type ReactNode } from 'react';

type Props = Record<string, unknown> & { children?: ReactNode };

function fakeNode(x: number, y: number) {
  const node = {
    x: () => x,
    y: () => y,
    position: (p?: { x: number; y: number }) => { if (p) { x = p.x; y = p.y; } return { x, y }; },
    getStage: () => null,
    absolutePosition: () => ({ x, y }),
  };
  return node;
}

function shape(kind: string) {
  return function Shape(props: Props) {
    const ref = useRef<HTMLDivElement>(null);
    const onDragEnd = props.onDragEnd as ((e: unknown) => void) | undefined;
    useEffect(() => {
      const el = ref.current;
      if (!el || !onDragEnd) return;
      const handler = (ev: Event) => {
        ev.stopPropagation();
        const { x, y } = (ev as CustomEvent<{ x: number; y: number }>).detail;
        onDragEnd({ target: fakeNode(x, y) });
      };
      el.addEventListener('konva-dragend', handler);
      return () => el.removeEventListener('konva-dragend', handler);
    }, [onDragEnd]);
    const onClick = props.onClick as ((e: unknown) => void) | undefined;
    return createElement(
      'div',
      {
        ref,
        'data-konva': kind,
        'data-name': props.name as string | undefined,
        onClick: onClick
          ? (ev: { stopPropagation: () => void }) => {
            ev.stopPropagation();
            onClick({ cancelBubble: false, target: { getStage: () => null }, evt: ev });
          }
          : undefined,
      },
      typeof props.text === 'string' ? props.text : null,
      props.children,
    );
  };
}

export const Stage = shape('Stage');
export const Layer = shape('Layer');
export const Group = shape('Group');
export const Rect = shape('Rect');
export const Line = shape('Line');
export const Text = shape('Text');
