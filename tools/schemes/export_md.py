"""Экспорт структурных схем в репозиторий: отдельные SVG + SCHEMES.md.

Вызывается из build.py. Берёт собранную HTML-страницу, вырезает каждую
схему в img/schemes/<имя>.svg и пишет SCHEMES.md с текстом листов.

SVG делаются самодостаточными: встроенный <style> со значениями светлой
темы, светлое поле листа, явные width/height — чтобы GitHub показывал их
через <img> одинаково в светлой и тёмной теме.

Порядок имён в NAMES совпадает с порядком схем на странице: новый рисунок
на листе — новое имя в списке на своём месте.
"""
import html
import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))
IMGDIR = 'img/schemes'
NAMES = ["01_1_decatron_ring", "01_2_decatron_model", "01_3_decatron_timing",
         "02_1_phasegen_pulsesender", "02_2_dekatron_module", "03_1_dekatron_counter",
         "03_2_dekatron_counter_fsm", "04_1_ipline", "04_2_ipline_fsm", "05_1_apline",
         "05_2_apline_fsm", "06_1_machinectrl", "06_2_machinectrl_fsm", "07_1_dekatronpc_top"]


def svg_style():
    """CSS схем со значениями светлой темы вместо переменных."""
    head = open(os.path.join(HERE, 'head.html')).read()
    root = re.search(r':root\s*\{(.*?)\}', head, re.S).group(1)
    v = dict(re.findall(r'--([\w-]+):\s*([^;]+);', root))
    v['display'] = '"PT Sans Narrow", "Arial Narrow", "Roboto Condensed", Arial, sans-serif'
    v['body'] = '"PT Sans", "Segoe UI", Roboto, Helvetica, Arial, sans-serif'
    v['mono'] = '"JetBrains Mono", "DejaVu Sans Mono", Consolas, "Liberation Mono", monospace'
    rules = '\n'.join(l for l in head.splitlines() if l.startswith('.dg'))
    rules = re.sub(r'var\(--([\w-]+)\)', lambda m: v[m.group(1)].strip(), rules)
    rules = rules.replace('.dg {', '.dg { color: %s;' % v['ink'].strip(), 1)
    return '<style>\n' + rules + '\n</style>', v['sheet'].strip()


def export_svgs(page, repo):
    """Каждая схема страницы → img/schemes/<имя>.svg. Возвращает {svg: (файл, alt)}."""
    style, sheet = svg_style()
    os.makedirs(os.path.join(repo, IMGDIR), exist_ok=True)
    svgs = re.findall(r'<svg[^>]*class="dg".*?</svg>', page, re.S)
    if len(svgs) != len(NAMES):
        raise SystemExit(f'на странице {len(svgs)} схем, а в NAMES {len(NAMES)} имён')
    files = {}
    for name, svg in zip(NAMES, svgs):
        w, h = re.search(r'viewBox="0 0 ([\d.]+) ([\d.]+)"', svg).groups()
        open_tag = re.match(r'<svg[^>]*>', svg).group(0)
        aria = re.search(r'aria-label="([^"]*)"', open_tag)
        new_open = (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w} {h}" '
                    f'width="{w}" height="{h}" class="dg" role="img"'
                    + (f' aria-label="{aria.group(1)}"' if aria else '') + '>')
        bg = f'<rect x="0" y="0" width="{w}" height="{h}" fill="{sheet}"/>'
        out = ('<?xml version="1.0" encoding="UTF-8"?>\n' + new_open + style + bg
               + svg[len(open_tag):])
        fn = f'{IMGDIR}/{name}.svg'
        open(os.path.join(repo, fn), 'w').write(out + '\n')
        files[svg] = (fn, aria.group(1) if aria else name)
    return files


def inline(t):
    """Строчная HTML-разметка → Markdown."""
    t = re.sub(r'<b>(.*?)</b>', r'**\1**', t, flags=re.S)
    t = re.sub(r'<code>(.*?)</code>', lambda m: '`' + html.unescape(m.group(1)) + '`', t, flags=re.S)
    sub = str.maketrans('k+−-1', 'ₖ₊₋₋₁')
    t = re.sub(r'<sub>(.*?)</sub>',
               lambda m: m.group(1).translate(sub) if set(m.group(1)) <= set('k+−-1')
               else '_' + m.group(1), t)
    t = re.sub(r'<a href="([^"]*)">(.*?)</a>', r'[\2](\1)', t)
    t = re.sub(r'<[^>]+>', '', t)
    return html.unescape(t).strip()


def table(t):
    rows = re.findall(r'<tr>(.*?)</tr>', t, re.S)
    out = []
    for i, r in enumerate(rows):
        cells = [inline(c).replace('|', '\\|')
                 for c in re.findall(r'<t[hd][^>]*>(.*?)</t[hd]>', r, re.S)]
        out.append('| ' + ' | '.join(cells) + ' |')
        if i == 0:
            out.append('|' + '---|' * len(cells))
    return '\n'.join(out)


def run(src, repo, rtl_ref):
    page = open(src).read()
    files = export_svgs(page, repo)

    md = ['# DekatronPC — структурные схемы\n',
          'Микроархитектура ядра DekatronPC в семи листах, снизу вверх: от модели лампы А110 '
          f'до верхнего уровня машины. Схемы сверены: {rtl_ref}. Требования — в [TRS.md](TRS.md).\n',
          '**Обозначения.** Оранжевым выделено то, о чём лист: путь разряда, цепочка переноса, '
          'ленивое чтение. Пурпурным пунктиром — найденный дефект RTL. Пунктирные блоки есть только '
          'при соответствующем параметре. Логические элементы — по ГОСТ 2.743.\n',
          '## Листы\n']
    secs = re.findall(r'<section class="sheet" id="(\w+)">(.*?)</section>', page, re.S)
    for n, (_, s) in enumerate(secs, 1):
        title = inline(re.search(r'<h2>(.*?)</h2>', s).group(1))
        slug = re.sub(r'[^\w\- ]', '', title.lower()).replace(' ', '-')
        md.append(f'{n}. [{title}](#{slug})')
    md.append('')

    for _, s in secs:
        num = re.search(r'<span class="num">(.*?)</span>', s).group(1)
        title = inline(re.search(r'<h2>(.*?)</h2>', s).group(1))
        srcf = inline(re.search(r'<span class="k">Источник</span><span class="v">(.*?)</span>', s).group(1))
        md.append(f'## {title}\n')
        md.append(f'*{num} · источник: {srcf}*\n')
        body = re.sub(r'<div class="stamp">.*?</div>\s*</div>', '', s, flags=re.S)
        body = re.sub(r'^.*?</h2>', '', body, flags=re.S)
        # блоки листа в порядке появления
        for m in re.finditer(r'<p>(.*?)</p>|<figure>(.*?)</figure>|<div class="note">(.*?)</div>'
                             r'|<h3>(.*?)</h3>|<table class="spec">(.*?)</table>', body, re.S):
            p, figb, note, h3, tbl = m.groups()
            if p is not None:
                md.append(inline(p) + '\n')
            elif figb is not None:
                svg = re.search(r'<svg.*?</svg>', figb, re.S).group(0)
                fn, alt = files[svg]
                cap = inline(re.search(r'<figcaption>(.*?)</figcaption>', figb, re.S).group(1))
                md.append(f'![{alt.replace("[", "(").replace("]", ")")}]({fn})\n')
                md.append(cap + '\n')
            elif note is not None:
                md.append('> ' + inline(note) + '\n')
            elif h3 is not None:
                md.append(f'### {inline(h3)}\n')
            else:
                md.append(table(tbl) + '\n')

    md.append('---\n')
    md.append('Конструктив, тепловой режим и внешний вид машины в этот документ не входят. '
              'Схемы и этот файл генерируются скриптом [`tools/schemes/build.py`](tools/schemes/README.md), '
              'править их вручную не нужно.\n')
    open(os.path.join(repo, 'SCHEMES.md'), 'w').write('\n'.join(md))
    print(f'SCHEMES.md и {len(files)} схем в {IMGDIR}/')
