#!/usr/bin/env python3
"""Generate the NOT_N16 cell sheet and its testbench (doc/cell_design_method.md, sch/logic/NOT_N16/README.md).

usage: gen_not_n16.py OUT_DIR      -> OUT_DIR/NOT_N16/NOT_N16.kicad_sch, OUT_DIR/NOT_N16/NOT_N16_tb.kicad_sch
One sheet = one 6N16B = two independent inverters (liberty NOT_N16 is half a tube): A1 -> Y1, A2 -> Y2.
Copied from gen_nor2_n16.py; the cell and testbench sections are new, the .meas lines come from
tools/spice/not_sweep.py so the KiCad run and the plain-SPICE sweep measure the same things.
Every run makes new UUIDs: regenerate only to start over, not to edit a drawn cell (edit that in KiCad).
"""
import math, uuid, re, sys, os

OUT = sys.argv[1]
os.makedirs(os.path.join(OUT, "NOT_N16"), exist_ok=True)
SYSLIB = os.environ.get("KICAD_SYMBOL_DIR", "/usr/share/kicad/symbols")
REPO = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
PROJ = "NOT_N16_tb"

SIMLIB = "${KIPRJMOD}/../../libs/6N16B.sub"
TUBE_PINS = "1=Pa 7=Ga 6=Ka 5=Pb 3=Gb 2=Kb"

def U(): return str(uuid.uuid4())
def q(s): return '"' + s.replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n') + '"'
def f(v): return ("%.4f" % v).rstrip("0").rstrip(".")

# ---------------------------------------------------------------- lib symbols
def lib_block(path, name):
    t = open(path).read()
    i = t.find('(symbol "%s"' % name)
    assert i >= 0, (path, name)
    depth = 0
    for j in range(i, len(t)):
        if t[j] == '(': depth += 1
        elif t[j] == ')':
            depth -= 1
            if depth == 0: return t[i:j+1]

def embed(path, name, libname, rename=None, value=None):
    b = lib_block(path, name)
    if rename:
        b = b.replace('"%s' % name, '"%s' % rename)   # symbol + sub-symbol names
        b = b.replace('"Value" "%s"' % rename, '"Value" "%s"' % (value or rename))
        b = re.sub(r'(Power symbol creates a global label with name \\")[^\\]*', r'\g<1>' + (value or rename), b)
        name = rename
    return b.replace('(symbol "%s"' % name, '(symbol "%s:%s"' % (libname, name), 1)

def fix_tube_pins(b):
    # plate = open_collector (wired-OR of plates is legal), cathode = passive
    b = re.sub(r'\(pin output (line\s*\(at [^)]*\)\s*\(length [^)]*\)\s*\(name "A")', r'(pin open_collector \1', b)
    b = re.sub(r'\(pin bidirectional (line\s*\(at [^)]*\)\s*\(length [^)]*\)\s*\(name "K")', r'(pin passive \1', b)
    return b

def tube_lib():
    b = embed(f"{REPO}/sch/libs/vacuum_tube.kicad_sym", "6Н16Б", "vacuum_tube")
    b = re.sub(r'\(property "Sim\.Library" "[^"]*"', '(property "Sim.Library" %s' % q(SIMLIB), b)
    b = re.sub(r'\(property "Sim\.Pins" "[^"]*"', '(property "Sim.Pins" %s' % q(TUBE_PINS), b)
    return fix_tube_pins(b)

LIBS = {
    "Device:R": embed(f"{SYSLIB}/Device.kicad_sym", "R", "Device"),
    "Device:C": embed(f"{SYSLIB}/Device.kicad_sym", "C", "Device"),
    "power:GND": embed(f"{SYSLIB}/power.kicad_sym", "GND", "power"),
    "power:PWR_FLAG": embed(f"{SYSLIB}/power.kicad_sym", "PWR_FLAG", "power"),
    "power:+150V": embed(f"{SYSLIB}/power.kicad_sym", "+12V", "power", "+150V"),
    "power:-50V": embed(f"{SYSLIB}/power.kicad_sym", "-12V", "power", "-50V"),
    "power:+6.3V": embed(f"{SYSLIB}/power.kicad_sym", "+12V", "power", "+6.3V"),
    "Simulation_SPICE:VDC": embed(f"{SYSLIB}/Simulation_SPICE.kicad_sym", "VDC", "Simulation_SPICE"),
    "Simulation_SPICE:VPULSE": embed(f"{SYSLIB}/Simulation_SPICE.kicad_sym", "VPULSE", "Simulation_SPICE"),
    "vacuum_tube:6Н16Б": tube_lib(),
}

PINS = {  # lib-space pin coordinates
    "Device:R": {"1": (0, 3.81), "2": (0, -3.81)},
    "Device:C": {"1": (0, 3.81), "2": (0, -3.81)},
    "Simulation_SPICE:VDC": {"1": (0, 5.08), "2": (0, -5.08)},
    "Simulation_SPICE:VPULSE": {"1": (0, 5.08), "2": (0, -5.08)},
    "vacuum_tube:6Н16Б": {1: {"1": (0, 10.16), "7": (-7.62, 0), "6": (-2.54, -10.16), "4": (1.27, -10.16), "8": (-1.27, -10.16)},
                          2: {"5": (0, 10.16), "3": (-7.62, 0), "2": (-2.54, -10.16)}},
}

def pin_at(lib, pos, ang, pin, unit=1):
    p = PINS[lib]
    if isinstance(next(iter(p)), int): p = p[unit]
    px, py = p[pin]
    a = math.radians(ang)
    rx, ry = px*math.cos(a) - py*math.sin(a), px*math.sin(a) + py*math.cos(a)
    return (round(pos[0] + rx, 4), round(pos[1] - ry, 4))

FONT = '(effects (font (size 1.27 1.27))%s)'

class Sheet:
    def __init__(self):
        self.items = []; self.used = set(); self.uuid = U()
    def wire(self, *pts):
        for a, b in zip(pts, pts[1:]):
            self.items.append('(wire (pts (xy %s %s) (xy %s %s)) (stroke (width 0) (type default)) (uuid "%s"))'
                              % (f(a[0]), f(a[1]), f(b[0]), f(b[1]), U()))
    def junction(self, p):
        self.items.append('(junction (at %s %s) (diameter 0) (color 0 0 0 0) (uuid "%s"))' % (f(p[0]), f(p[1]), U()))
    def noconn(self, p):
        self.items.append('(no_connect (at %s %s) (uuid "%s"))' % (f(p[0]), f(p[1]), U()))
    def text(self, s, p, size=1.27):
        self.items.append('(text %s (exclude_from_sim no) (at %s %s 0) (effects (font (size %s %s)) (justify left top)) (uuid "%s"))'
                          % (q(s), f(p[0]), f(p[1]), size, size, U()))
    def label(self, name, p, ang=0):
        j = {0: "left bottom", 180: "right bottom", 90: "left bottom", 270: "right bottom"}[ang]
        self.items.append('(label %s (at %s %s %d) (effects (font (size 1.27 1.27)) (justify %s)) (uuid "%s"))'
                          % (q(name), f(p[0]), f(p[1]), ang, j, U()))
    def hlabel(self, name, shape, p, ang):
        j = {0: "left", 180: "right", 90: "left", 270: "right"}[ang]
        self.items.append('(hierarchical_label %s (shape %s) (at %s %s %d) (effects (font (size 1.27 1.27)) (justify %s)) (uuid "%s"))'
                          % (q(name), shape, f(p[0]), f(p[1]), ang, j, U()))
    def symbol(self, lib, pos, ang, refs, value, unit=1, props=None, ref_off=(2.54, -1.27), val_off=(2.54, 1.27),
               hide_ref=False, hide_val=False, pins=None, fang=0):
        """refs: list of (path, reference) instances."""
        self.used.add(lib)
        props = props or {}
        ref0 = refs[0][1]
        pr = []
        def prop(k, v, off, hide):
            pr.append('(property %s %s (at %s %s %d) %s)' % (q(k), q(v), f(pos[0]+off[0]), f(pos[1]+off[1]), fang if k in ("Reference", "Value") else 0,
                      FONT % (' (justify left)' + (' (hide yes)' if hide else '')) if k in ("Reference", "Value") else FONT % ' (hide yes)'))
        prop("Reference", ref0, ref_off, hide_ref)
        prop("Value", value, val_off, hide_val)
        prop("Footprint", "", (0, 0), True)
        prop("Datasheet", "~", (0, 0), True)
        for k, v in props.items(): prop(k, v, (0, 0), True)
        if pins is None:
            p = PINS.get(lib, {"1": None})
            pins = list((p[unit] if isinstance(next(iter(p)), int) else p).keys())
        pl = ' '.join('(pin "%s" (uuid "%s"))' % (n, U()) for n in pins)
        inst = ' '.join('(path "%s" (reference %s) (unit %d))' % (path, q(r), unit) for path, r in refs)
        self.items.append('(symbol (lib_id %s) (at %s %s %d) (unit %d) (exclude_from_sim no) (in_bom yes) (on_board yes) (dnp no) (uuid "%s") %s %s (instances (project %s %s)))'
                          % (q(lib), f(pos[0]), f(pos[1]), ang, unit, U(), ' '.join(pr), pl, q(PROJ), inst))
    def raw(self, s): self.items.append(s)
    def dump(self, path, title, root=False, comments=(), paper="A4"):
        libs = '\n'.join(LIBS[k] for k in sorted(self.used))
        tb = '(title_block (title %s) (company "DekatronPC") %s)' % (q(title), ' '.join('(comment %d %s)' % (i+1, q(c)) for i, c in enumerate(comments)))
        si = '(sheet_instances (path "/" (page "1")))' if root else ''
        open(path, "w").write('(kicad_sch (version 20260306) (generator "eeschema") (generator_version "10.0") (uuid "%s") (paper "%s") %s\n(lib_symbols\n%s)\n%s\n%s\n(embedded_fonts no))\n'
                              % (self.uuid, paper, tb, libs, '\n'.join(self.items), si))



# ================================================================ cell: two inverters on one 6N16B
# Levels (owner, 2026-10-23): HV (plate) 1 = +150 V, 0 = +50 V; LV (grid) 1 = +10 V, 0 = -20 V.
# HV -> LV: divider R1 || C1 / R2 to -50 V (ratio 0.3); LV -> HV: the gate itself.
sys.path.insert(0, os.path.join(REPO, "tools", "spice"))
import not_sweep as sw
RA, R1, R2, C1G = "10k", "470k", "200k", 3.9      # C1 = 3.9 pF per grid on the LV net
cell = Sheet()
tb = Sheet()
INST = ["DUT", "DRV"] + ["LOAD_A%d" % i for i in range(1, 6)] + ["LOAD_B%d" % i for i in range(1, 6)]
sheet_uuid = {n: U() for n in INST}
paths = {n: "/%s/%s" % (tb.uuid, sheet_uuid[n]) for n in INST}
def refs(fmt):
    return [(paths[n], fmt.format(k=k+1)) for k, n in enumerate(INST)]
pwr_n = [0]
def pwr_refs():
    pwr_n[0] += 1
    return [(paths[n], "#PWR%d%02d" % (k+1, pwr_n[0])) for k, n in enumerate(INST)]

G = 2.54
Y0 = 40*G
tube_props = {"Sim.Library": SIMLIB, "Sim.Name": "6N16B", "Sim.Device": "SUBCKT", "Sim.Pins": TUBE_PINS}
T = "vacuum_tube:6Н16Б"
for xt, unit, n, ppin, gpin, kpin in ((36*G, 1, 1, "1", "7", "6"), (66*G, 2, 2, "5", "3", "2")):
    cell.symbol(T, (xt, Y0), 0, refs("Л{k}"), "6Н16Б", unit=unit, props=tube_props, ref_off=(3.81, -6.35), val_off=(3.81, 6.35))
    yp = Y0 - 8*G
    cell.wire(pin_at(T, (xt, Y0), 0, ppin, unit), (xt, yp))
    ra = (xt, yp - 3*G)
    cell.symbol("Device:R", ra, 0, refs("R{k}%d" % n), RA)
    cell.wire(pin_at("Device:R", ra, 0, "2"), (xt, yp))
    top = (xt, ra[1] - 3*G)
    cell.wire(pin_at("Device:R", ra, 0, "1"), top)
    cell.symbol("power:+150V", top, 0, pwr_refs(), "+150V", ref_off=(0, 3.81), val_off=(-2.54, -3.81), hide_ref=True, pins=["1"])
    cell.wire((xt, yp), (xt + 8*G, yp)); cell.junction((xt, yp))
    cell.hlabel("Y%d" % n, "output", (xt + 8*G, yp), 0)
    g = pin_at(T, (xt, Y0), 0, gpin, unit)
    xin = g[0] - 5*G
    cell.wire((xin, Y0), g)
    cell.hlabel("A%d" % n, "input", (xin, Y0), 180)
    k = pin_at(T, (xt, Y0), 0, kpin, unit)
    kg = (k[0] - 2*G, k[1] + 2*G)
    cell.wire(k, (k[0], k[1] + G), (kg[0], k[1] + G), kg)
    cell.symbol("power:GND", kg, 0, pwr_refs(), "GND", ref_off=(0, 6.35), val_off=(-1.27, 5.08), hide_ref=True, pins=["1"])
for pin, name in (("8", "H1"), ("4", "H2")):
    p = pin_at(T, (36*G, Y0), 0, pin, 1)
    e = (p[0], p[1] + 4*G)
    cell.wire(p, e)
    cell.hlabel(name, "passive", e, 270)
cell.text("NOT_N16: Y1 = ~A1, Y2 = ~A2. One 6N16B (6Н16Б): two independent inverters, each triode with its own Ra.\n"
          "Inputs A1, A2: LV level, straight to the grids (1 = +10 V, 0 = -20 V).\n"
          "Outputs Y1, Y2: HV level on the plates (1 = +150 V, 0 = +50 V).\n"
          "Simulated: Y = 147 / 55 V; fanout 2/10: tpHL 61/83 ns, tpLH 64/211 ns; crosstalk between the halves -2 / +5 V.\n"
          "Each HV net that drives grids needs a divider HV -> LV: 470k || C1 from Y to the LV net,\n"
          "200k from the LV net to -50 V, C1 = 3.9 pF per grid on that net (see NOT_N16_tb).\n"
          "LV inputs must come from such a divider (grid current is limited by it), never from a stiff source.\n"
          "Unused half: tie its input to a used LV net or to the other input. Supplies: +150 V, -50 V (dividers only),\n"
          "heater 6.3 V 0.4 A on H1/H2. Page: sch/logic/NOT_N16/README.md", (20*G, 58*G))
cell.dump(os.path.join(OUT, "NOT_N16", "NOT_N16.kicad_sch"), "NOT_N16 - 2 x NOT on 6N16B",
          comments=["Y1 = ~A1, Y2 = ~A2; A: LV (+10/-20 V); Y: HV (+150/+50 V)", "Ra 10k to +150 V per triode"])

# ---------------------------------------------------------------- testbench
ROOT = "/%s" % tb.uuid
def r1(ref): return [(ROOT, ref)]
SW, SH = 12*G, 10*G
def sheet(name, pos, page):
    x, y = pos
    pins = [("A1", "input", (x, y + 2*G), 180), ("A2", "input", (x, y + 4*G), 180),
            ("Y1", "output", (x + SW, y + 2*G), 0), ("Y2", "output", (x + SW, y + 4*G), 0),
            ("H1", "passive", (x, y + 7*G), 180), ("H2", "passive", (x, y + 8*G), 180)]
    ps = ' '.join('(pin %s %s (at %s %s %d) (uuid "%s") (effects (font (size 1.27 1.27)) (justify %s)))'
                  % (q(n), t, f(p[0]), f(p[1]), a, U(), "left" if a == 180 else "right") for n, t, p, a in pins)
    tb.raw('(sheet (at %s %s) (size %s %s) (exclude_from_sim no) (in_bom yes) (on_board yes) (dnp no) (fields_autoplaced yes) '
           '(stroke (width 0.1524) (type solid)) (fill (color 0 0 0 0.0000)) (uuid "%s") '
           '(property "Sheetname" %s (at %s %s 0) (effects (font (size 1.27 1.27)) (justify left bottom))) '
           '(property "Sheetfile" "NOT_N16.kicad_sch" (at %s %s 0) (effects (font (size 1.27 1.27)) (justify left top))) '
           '%s (instances (project %s (path "%s" (page "%d")))))'
           % (f(x), f(y), f(SW), f(SH), sheet_uuid[name], q(name), f(x), f(y - 0.7), f(x), f(y + SH + 0.6), ps, q(PROJ), ROOT, page))
    return {n: p for n, _, p, _ in pins}

pn = [0]
def tpwr(lib, p, ang=0):
    pn[0] += 1
    off = {"power:GND": ((0, 6.35), (-1.27, 5.08)), "power:-50V": ((0, -3.81), (-2.54, 3.81))}.get(lib, ((0, 3.81), (-2.54, -3.81)))
    tb.symbol(lib, p, ang, r1("#PWR%02d" % pn[0]), lib.split(":")[1], ref_off=off[0], val_off=off[1], hide_ref=True, pins=["1"])

def heat(s):
    a, b = s["H1"], s["H2"]
    x = a[0] - 2*G
    tb.wire(a, (x, a[1])); tpwr("power:+6.3V", (x, a[1]))
    tb.wire(b, (x - G, b[1]), (x - G, b[1] + 2*G)); tpwr("power:GND", (x - G, b[1] + 2*G))

def tie(s):
    """tie A1 and A2 of a sheet (a load tube: both inverters on one net), return the tie point"""
    a, b = s["A1"], s["A2"]
    x = a[0] - 3*G
    tb.wire(a, (x, a[1])); tb.wire(b, (x, b[1])); tb.wire((x, a[1]), (x, b[1])); tb.junction((x, a[1]))
    return (x, a[1])

dn = [0]
def divider(hv, c1):
    """HV->LV divider: R1 || C1 horizontal from hv to the LV node, R2 from the LV node down to -50 V. Returns the LV node."""
    dn[0] += 1
    n = dn[0]
    x, y = hv
    rs, cs = (x + 4*G, y), (x + 4*G, y - 3*G)
    tb.symbol("Device:R", rs, 90, r1("R5%02d" % (2*n - 1)), R1, ref_off=(-3.81, 3.81), val_off=(-3.81, 6.35), fang=90)
    tb.symbol("Device:C", cs, 90, r1("C5%02d" % n), c1, ref_off=(-3.81, -5.08), val_off=(-3.81, -2.54), fang=90)
    l, r = pin_at("Device:R", rs, 90, "1"), pin_at("Device:R", rs, 90, "2")
    cl, cr = pin_at("Device:C", cs, 90, "1"), pin_at("Device:C", cs, 90, "2")
    tb.wire(hv, l); tb.wire(cl, l); tb.wire(cr, r); tb.junction(l); tb.junction(r)
    lv = (r[0] + 2*G, y)
    tb.wire(r, lv); tb.junction(lv)
    rb = (lv[0], y + 3*G)
    tb.symbol("Device:R", rb, 0, r1("R5%02d" % (2*n)), R2)
    tb.wire(lv, pin_at("Device:R", rb, 0, "1"))
    neg = (rb[0], rb[1] + 3*G)
    tb.wire(pin_at("Device:R", rb, 0, "2"), neg)
    tpwr("power:-50V", neg, 180)
    return lv

def vsrc(lib, p, ref, value, params):
    props = {"Sim.Device": "V", "Sim.Type": "DC" if lib.endswith("VDC") else "PULSE", "Sim.Pins": "1=+ 2=-", "Sim.Params": params}
    tb.symbol(lib, p, 0, r1(ref), value, props=props, ref_off=(3.81, -1.27), val_off=(3.81, 1.27))
    t, b = pin_at(lib, p, 0, "1"), pin_at(lib, p, 0, "2")
    tb.wire(t, (t[0], t[1] - G)); tb.wire(b, (b[0], b[1] + G))
    return (t[0], t[1] - G), (b[0], b[1] + G)

def flag(pt, n):
    p = (pt[0] + 3*G, pt[1])
    tb.wire(pt, p); tb.junction(pt)
    tb.symbol("power:PWR_FLAG", p, 0, r1("#FLG%02d" % n), "PWR_FLAG", ref_off=(0, -1.905), val_off=(1.27, -3.81), hide_ref=True, pins=["1"])

# supplies
x0 = 8*G
t, b = vsrc("Simulation_SPICE:VDC", (x0, 16*G), "V1", "150", "dc=150")
tpwr("power:+150V", t); tpwr("power:GND", b); flag(t, 1); flag(b, 2)
t, b = vsrc("Simulation_SPICE:VDC", (x0, 30*G), "V2", "50", "dc=50")
g = (x0 - 3*G, t[1]); tb.wire(t, g); tpwr("power:GND", g)
tpwr("power:-50V", b, 180); flag(b, 3)
t, b = vsrc("Simulation_SPICE:VDC", (x0, 44*G), "V3", "6.3", "dc=6.3")
tpwr("power:+6.3V", t); tpwr("power:GND", b); flag(t, 4)

# stimulus (HV levels) -> divider -> driver tube (one inverter per input) -> divider -> DUT input
# 2 us per state, DUT (A,B) = 00 10 11 01 00 (not_sweep.SEQ_A/B): the DUT input is 1 while STIM is 0 (+50 V)
drv = sheet("DRV", (44*G, 30*G), 3)
dut = sheet("DUT", (76*G, 30*G), 2)
loads_a = [sheet("LOAD_A%d" % i, (112*G, (6 + 13*(i-1))*G), 3 + i) for i in range(1, 6)]
loads_b = [sheet("LOAD_B%d" % i, (140*G, (6 + 13*(i-1))*G), 8 + i) for i in range(1, 6)]
for s in [drv, dut] + loads_a + loads_b: heat(s)
# STIM_A: high, low from 2 to 6 us; STIM_B: high, low from 4 to 8 us
for name, ref, params, y, pin in (("STIM_A", "V4", "y1=150 y2=50 td=2u tr=20n tf=20n tw=4u per=20u", drv["A1"][1], "A1"),
                                  ("STIM_B", "V5", "y1=150 y2=50 td=4u tr=20n tf=20n tw=4u per=20u", 48*G, "A2")):
    t, b = vsrc("Simulation_SPICE:VPULSE", (20*G, y + 4*G), ref, "VPULSE", params)
    tpwr("power:GND", b)
    hv = (t[0], y)
    tb.wire(t, hv); tb.wire(hv, (t[0] + 2*G, y))
    tb.label(name, (t[0] + G, y), 0)
    lv = divider((t[0] + 2*G, y), "%gp" % C1G)
    d = drv[pin]
    if lv[1] == d[1]:
        tb.wire(lv, d)
    else:
        xm = lv[0] + 2*G
        tb.wire(lv, (xm, lv[1]), (xm, d[1]), d)
# driver outputs -> dividers (one grid each) -> DUT inputs
y1 = drv["Y1"]
tb.wire(y1, (y1[0] + 2*G, y1[1]))
lv = divider((y1[0] + 2*G, y1[1]), "%gp" % C1G)
tb.wire(lv, dut["A1"])
tb.label("IN_A", (lv[0] + 2*G, lv[1]), 0)
y2 = drv["Y2"]
yb = 46*G
tb.wire(y2, (y2[0] + G, y2[1]), (y2[0] + G, yb), (y2[0] + 2*G, yb))
lv = divider((y2[0] + 2*G, yb), "%gp" % C1G)
xm = lv[0] + 4*G
tb.wire(lv, (xm, yb), (xm, dut["A2"][1]), dut["A2"])
tb.label("IN_B", (xm + G, dut["A2"][1]), 0)
# DUT outputs: each HV net -> one divider for 10 grids -> LV net -> 5 load tubes, both inverters of each on the net
o1 = dut["Y1"]
tb.wire(o1, (o1[0] + 3*G, o1[1]))
tb.label("OUT_A", (o1[0] + G, o1[1]), 0)
lva = divider((o1[0] + 3*G, o1[1]), "%gp" % (10 * C1G))
o2 = dut["Y2"]
yo = 50*G
tb.wire(o2, (o2[0] + G, o2[1]), (o2[0] + G, yo), (o2[0] + 5*G, yo))
tb.label("OUT_B", (o2[0] + 1.5*G, yo), 0)
lvb = divider((o2[0] + 5*G, yo), "%gp" % (10 * C1G))
tb.wire(lvb, (lvb[0] + 2*G, yo))
tb.label("OUT_B_LV", (lvb[0] + 2*G, yo), 0)

def load_bus(loads, xo, start=None, label=None):
    ys = []
    for s in loads:
        tp = tie(s)
        tb.wire(tp, (xo, tp[1])); ys.append(tp[1])
        tb.noconn(s["Y1"]); tb.noconn(s["Y2"])
    if start is not None:
        tb.wire(start, (xo, start[1])); ys.append(start[1])
    if label:
        top = min(ys) - 2*G
        tb.wire((xo, top), (xo - 6*G, top)); tb.label(label, (xo - 6*G, top), 0); ys.append(top)
    ys = sorted(ys)
    for a, b in zip(ys, ys[1:]): tb.wire((xo, a), (xo, b))
    for y in ys:
        if y not in (ys[0], ys[-1]): tb.junction((xo, y))
load_bus(loads_a, 106*G, start=lva)
tb.label("OUT_A_LV", (lva[0] + 0.5*G, lva[1]), 0)
load_bus(loads_b, 134*G, label="OUT_B_LV")

STOP = 2 * len(sw.SEQ_A)
tb.text(".tran 5n %du" % STOP, (20*G, 62*G), 1.5)
tb.text("\n".join("." + l for l in sw.meas_lines("/IN_A", "/IN_B", "/OUT_A", "/OUT_B", "/OUT_A_LV", STOP)), (20*G, 65*G))
tb.text("NOT_N16 testbench. 2 us per input state, DUT (A,B) = 00 10 11 01 00: each half switches while the other is static.\n"
        "STIM_x (HV, ideal) -> divider -> driver inverter (DRV) -> divider -> IN_x (LV): real edges and levels on the DUT grids.\n"
        "OUT_x (HV) -> one divider (C1 = 3.9 pF x 10 grids) -> OUT_x_LV -> 5 load tubes, both inverters on the net = fanout 10.\n"
        "Plot V(/IN_A) V(/IN_B) V(/OUT_A) V(/OUT_B) V(/OUT_A_LV); .meas: ya0..4 / yb0..4 = OUT_A / OUT_B at the end of each state,\n"
        "xlo_min / xlo_max / xhi_min = the static output while the other half switches (plate-to-plate capacitance).",
        (20*G, 98*G))
tb.dump(os.path.join(OUT, "NOT_N16", "NOT_N16_tb.kicad_sch"), "NOT_N16 testbench", root=True,
        comments=["HV +150/+50 V, LV +10/-20 V, fanout 10 on each output, 2 us per input state"], paper="A3")
print("ok")
