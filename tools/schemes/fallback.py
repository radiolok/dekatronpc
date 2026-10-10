"""Запасные атрибуты оформления для SVG.

Если просмотрщик не применяет CSS страницы к SVG, фигуры без атрибутов fill
заливаются чёрным (поведение по умолчанию). Здесь каждой фигуре добавляются
атрибуты fill/stroke со значениями светлой темы. Любое CSS-правило главнее
атрибутов оформления, поэтому в нормальном браузере ничего не меняется.
"""
import re

INK, MUTED, GLOW, WARN, PANEL = "#172024", "#56636a", "#c8431a", "#a4126e", "#ffffff"
GLOW_SOFT, HATCH, RULE, SHEET = "#f5ddd3", "#e3e9e8", "#c6cfcd", "#fbfcfb"

# класс (или пара классов) → атрибуты
SHAPE = {
    "blk": (PANEL, INK, 1.2), "blk-opt": (PANEL, INK, 1.2), "st": (PANEL, INK, 1.3),
    "inv": (PANEL, INK, 1.2), "seg": (PANEL, INK, 1.1), "kmain": (PANEL, INK, 1.4),
    "kga": (PANEL, INK, 1.2), "blk-acc": (GLOW_SOFT, GLOW, 1.6), "st-acc": (GLOW_SOFT, GLOW, 1.9),
    "seg-acc": (GLOW_SOFT, GLOW, 1.4), "frame": ("none", MUTED, 1), "st-dim": (HATCH, MUTED, 1.1),
    "seg-off": (HATCH, MUTED, 1), "anode": (HATCH, MUTED, 1), "kgb": (MUTED, "none", 0),
    "lit": (GLOW, GLOW, 1), "halo": (GLOW_SOFT, "none", 0), "tgt": ("none", GLOW, 1.3),
    "dot": (INK, "none", 0), "dot-acc": (GLOW, "none", 0), "ah": (INK, "none", 0),
    "ahg": (GLOW, "none", 0), "ahw": (WARN, "none", 0), "arh": (GLOW, "none", 0),
    # конструктив
    "pcb fx": ("#b9d2c0", "#3f6a4f", 0.6), "pcb fy": ("#9fbfa9", "#3f6a4f", 0.6),
    "pcb fz": ("#d4e5d8", "#3f6a4f", 0.6), "metal fx": ("#d5dadc", "#59656b", 0.6),
    "metal fy": ("#bcc3c6", "#59656b", 0.6), "metal fz": ("#e6eaeb", "#59656b", 0.6),
    "conn": ("#2f3538", "#2f3538", 0.4), "finger": ("#c9963c", "none", 0),
    "glass body": ("#c8dee6", "#4b6a76", 0.7), "glass cap": ("#e2f0f4", "#4b6a76", 0.6),
    "anode body": ("#6d7478", "none", 0), "core body": ("#8a5a3c", INK, 0.6),
    "core cap": ("#a8714d", INK, 0.6), "hole body": ("none", "none", 0),
    "hole cap": (SHEET, INK, 0.6), "winhole": (SHEET, "#59656b", 1),
    "wallghost": ("none", "#59656b", 1.2), "window": ("none", "#59656b", 1),
    "planbase": (HATCH, "#59656b", 1), "pthin": ("#d4e5d8", "#3f6a4f", 0.8),
    "pthick": (GLOW_SOFT, GLOW, 0.8), "ptrafo": ("#d9b9a3", INK, 0.8),
}
LINE = {
    "w": INK, "wd": INK, "wbus": INK, "wv": INK, "wacc": GLOW, "wvacc": GLOW, "wwarn": WARN,
    "wthin": MUTED, "grid": RULE, "lead": MUTED, "lead2": INK, "ln": INK, "dim": GLOW,
    "pboard": "#3f6a4f",
}
WIDTH = {"wbus": 3.2, "wv": 1.6, "wacc": 1.9, "wvacc": 2.1, "wwarn": 1.8, "pboard": 3}
TEXT = {"tl": MUTED, "tn": MUTED, "tpi": MUTED, "tf": MUTED, "ti": MUTED, "tick": MUTED,
        "note": MUTED, "tacc": GLOW, "tnum": GLOW, "dimt": GLOW, "twarn": WARN}
TSIZE = {"tt": 14, "tk": 14, "tg": 13, "dimt": 14, "ti": 8.5, "tick": 11, "tpi": 10, "tn": 10.5}

TAG = re.compile(r'<(rect|polygon|polyline|path|line|circle|text)\b([^>]*?)class="([^"]*)"')


def _attrs(tag, cls):
    if tag == "text":
        c = TEXT.get(cls.split()[0], INK)
        return f' fill="{c}" font-size="{TSIZE.get(cls.split()[0], 11)}" font-family="sans-serif"'
    if tag in ("polyline", "line") or (tag == "path" and cls.split()[0] in LINE):
        k = cls.split()[0]
        sw = WIDTH.get(k, 1.2)
        dash = ' stroke-dasharray="5 3"' if k in ("wd", "wwarn") else ""
        return f' fill="none" stroke="{LINE.get(k, INK)}" stroke-width="{sw}"{dash}'
    f, s, w = SHAPE.get(cls, SHAPE.get(cls.split()[0], (PANEL, INK, 1)))
    extra = ' fill-opacity="0.55"' if cls == "glass body" else ""
    return f' fill="{f}" stroke="{s}" stroke-width="{w}"{extra}'


def apply(svg_html):
    return TAG.sub(lambda m: f'<{m.group(1)}{m.group(2)}{_attrs(m.group(1), m.group(3))} class="{m.group(3)}"', svg_html)
