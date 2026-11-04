#!/usr/bin/env python3
"""Prepare program files for the web simulator.

Copies the Brainfuck-100 set (bfutils/programs/bf100, unchanged, with its
licenses) and the repo test programs (rtl/programs/*.bfk) next to the page
and writes web/programs/index.json with their metadata from metrics.json.

    python3 web/build_bf100.py          # from the repo root

Needs the bfutils submodule: git submodule update --init bfutils.
The output (web/programs/) is generated and not committed.
"""
import json
import os
import shutil
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BF100 = os.path.join(ROOT, 'bfutils', 'programs', 'bf100')
RTL_PROGS = os.path.join(ROOT, 'rtl', 'programs')
OUT = os.path.join(ROOT, 'web', 'programs')

# Repo programs shown first, in this order. Endless and input flags by hand.
REPO = [
    ('helloworld.bfk', 'Hello World', {}),
    ('program.bfk', 'program.bfk', {}),
    ('triangle.bfk', 'Sierpinski triangle', {}),
    ('pi.bfk', 'Pi', {}),
    ('fibonachi.bfk', 'Fibonacci', {'infinite': True}),
    ('rot13.bfk', 'ROT13', {'reads_input': True}),
    ('looptest.bfk', 'Loop test', {}),
    ('fractal.bfk', 'Mandelbrot fractal', {}),
]


def copy(src, rel):
    dst = os.path.join(OUT, rel)
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    shutil.copyfile(src, dst)
    return rel.replace(os.sep, '/')


def main():
    if os.path.isdir(OUT):
        shutil.rmtree(OUT)
    os.makedirs(OUT)

    repo = []
    for name, title, extra in REPO:
        src = os.path.join(RTL_PROGS, name)
        if not os.path.exists(src):
            continue
        item = {'name': name, 'title': title, 'file': copy(src, 'repo/' + name),
                'dialect': 'dpc', 'infinite': False, 'reads_input': False}
        item.update(extra)
        repo.append(item)

    bf100 = []
    metrics_path = os.path.join(BF100, 'metrics.json')
    if os.path.exists(metrics_path):
        with open(metrics_path, encoding='utf-8') as f:
            metrics = json.load(f)
        for m in metrics:
            item = {k: m.get(k) for k in (
                'n', 'category', 'name', 'description', 'source_repo', 'source_url',
                'license', 'commands', 'steps', 'reads_input', 'eof_mode', 'infinite',
                'fits_5_2_5_3', 'loop_max_scan', 'ap_max')}
            item['dialect'] = 'bf'
            item['file'] = copy(os.path.join(BF100, m['file']), 'bf100/' + m['file']) if m.get('file') else None
            item['input'] = copy(os.path.join(BF100, m['input']), 'bf100/' + m['input']) if m.get('input') else None
            bf100.append(item)
        lic = os.path.join(BF100, 'LICENSES')
        if os.path.isdir(lic):
            shutil.copytree(lic, os.path.join(OUT, 'bf100', 'LICENSES'))
    else:
        print('warning: %s not found, Brainfuck-100 skipped (git submodule update --init bfutils)'
              % metrics_path, file=sys.stderr)

    with open(os.path.join(OUT, 'index.json'), 'w', encoding='utf-8') as f:
        json.dump({'repo': repo, 'bf100': bf100}, f, ensure_ascii=False, separators=(',', ':'))
    print('web/programs: %d repo programs, %d Brainfuck-100 entries' % (len(repo), len(bf100)))


if __name__ == '__main__':
    main()
