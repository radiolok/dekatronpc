#!/usr/bin/env python3
"""Shared parts of the cell-sheet generators (gen_latch_j2n16.py, gen_aoi.py): embedded library symbols with
the SPICE models of the tubes, pin geometry, the Sheet writer (net labels at short pin stubs) and the HV -> LV divider.
Moved out of gen_latch_j2n16.py unchanged."""
import math, uuid, re, sys, os

SYSLIB = os.environ.get("KICAD_SYMBOL_DIR", "/usr/share/kicad/symbols")
REPO = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))

G = 2.54
def U(): return str(uuid.uuid4())
def q(s): return '"' + s.replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n') + '"'
def f(v): return ("%.4f" % v).rstrip("0").rstrip(".")
def pf(v): return ("%.2f" % v).rstrip("0").rstrip(".") + "p"


# ---------------------------------------------------------------- lib symbols (as gen_nand2_j2.py)
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
        b = b.replace('"%s' % name, '"%s' % rename)
        b = b.replace('"Value" "%s"' % rename, '"Value" "%s"' % (value or rename))
        b = re.sub(r'(Power symbol creates a global label with name \\")[^\\]*', r'\g<1>' + (value or rename), b)
        name = rename
    return b.replace('(symbol "%s"' % name, '(symbol "%s:%s"' % (libname, name), 1)

def fix_tube_pins(b):
    b = re.sub(r'\(pin output (line\s*\(at [^)]*\)\s*\(length [^)]*\)\s*\(name "A")', r'(pin open_collector \1', b)
    b = re.sub(r'\(pin bidirectional (line\s*\(at [^)]*\)\s*\(length [^)]*\)\s*\(name "K")', r'(pin passive \1', b)
    return b

J2, N16, X7 = "vacuum_tube:6Ж2Б", "vacuum_tube:6Н16Б", "vacuum_tube:6Х7Б"
SIM = {J2: {"Sim.Library": "${KIPRJMOD}/../../libs/6Zh2B.sub", "Sim.Name": "6Zh2B", "Sim.Device": "SUBCKT",
            "Sim.Pins": "1=A 2=G3 3=G2 6=K 7=G1"},
       N16: {"Sim.Library": "${KIPRJMOD}/../../libs/6N16B.sub", "Sim.Name": "6N16B", "Sim.Device": "SUBCKT",
             "Sim.Pins": "1=Pa 7=Ga 6=Ka 5=Pb 3=Gb 2=Kb"},
       X7: {"Sim.Library": "${KIPRJMOD}/../../libs/6Kh7B.sub", "Sim.Name": "6Kh7B2", "Sim.Device": "SUBCKT",
            "Sim.Pins": "1=A1 3=K1 7=A2 5=K2"}}

def tube_lib(name, key):
    b = embed(f"{REPO}/sch/libs/vacuum_tube.kicad_sym", name, "vacuum_tube")
    for k in ("Sim.Library", "Sim.Pins"):
        b = re.sub(r'\(property "%s" "[^"]*"' % re.escape(k), '(property "%s" %s' % (k, q(SIM[key][k])), b)
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
    "Simulation_SPICE:VPWL": embed(f"{SYSLIB}/Simulation_SPICE.kicad_sym", "VPWL", "Simulation_SPICE"),
    J2: tube_lib("6Ж2Б", J2),
    N16: tube_lib("6Н16Б", N16),
    # a diode anode shares the reset line with many others: every 6Kh7B pin but the heater is passive
    X7: re.sub(r'\(pin (output|bidirectional) ', '(pin passive ', embed(f"{REPO}/sch/libs/vacuum_tube.kicad_sym", "6Х7Б", "vacuum_tube")),
}

PINS = {  # lib-space pin coordinates (y up)
    "Device:R": {"1": (0, 3.81), "2": (0, -3.81)},
    "Device:C": {"1": (0, 3.81), "2": (0, -3.81)},
    "Simulation_SPICE:VDC": {"1": (0, 5.08), "2": (0, -5.08)},
    "Simulation_SPICE:VPWL": {"1": (0, 5.08), "2": (0, -5.08)},
    J2: {"1": (0, 10.16), "2": (-7.62, 1.27), "3": (7.62, 0), "4": (-1.27, -10.16), "5": (1.27, -10.16),
         "6": (-2.54, -10.16), "7": (-7.62, -1.27)},
    N16: {1: {"1": (0, 10.16), "7": (-7.62, 0), "6": (-2.54, -10.16), "4": (1.27, -10.16), "8": (-1.27, -10.16)},
          2: {"5": (0, 10.16), "3": (-7.62, 0), "2": (-2.54, -10.16)}},
    X7: {1: {"1": (0, 5.08), "3": (-2.54, -10.16), "2": (-1.27, -10.16), "6": (1.27, -10.16)},
         2: {"7": (0, 5.08), "5": (-2.54, -10.16)}},
}
# bottom pins of a tube are 1.27 mm apart: cathode straight down, heaters bent to the right at different heights
def heat(h1, h2, k="GND"):
    return {"k": (k, [(0, 5)]), "h1": (h1, [(0, 3), (5, 0)]), "h2": (h2, [(0, 1), (3, 0)])}
def j2_bottom(h1="H1", h2="H2"):
    b = heat(h1, h2); return {"6": b["k"], "4": b["h1"], "5": b["h2"]}
def n16_bottom(h1="H1", h2="H2"):
    b = heat(h1, h2); return {"6": b["k"], "8": b["h1"], "4": b["h2"]}
def x7_bottom(k, h1="H1", h2="H2"):
    """unit A of a 6Kh7B: cathode (lead 3) straight down to its net, heater 2 / 6 bent to the right"""
    b = heat(h1, h2, k); return {"3": b["k"], "2": b["h1"], "6": b["h2"]}
POWER = {"+150V": "power:+150V", "-50V": "power:-50V", "GND": "power:GND", "+6.3V": "power:+6.3V"}

def pins_of(lib, unit):
    p = PINS[lib]
    return p[unit] if isinstance(next(iter(p)), int) else p

def pin_xy(lib, pos, ang, pin, unit=1):
    """screen position of a pin and the outward unit direction (screen, y down)"""
    px, py = pins_of(lib, unit)[pin]
    a = math.radians(ang)
    rx, ry = px*math.cos(a) - py*math.sin(a), px*math.sin(a) + py*math.cos(a)
    d = (1 if rx > 0.1 else -1 if rx < -0.1 else 0, 0) if abs(rx) >= abs(ry) else (0, -1 if ry > 0 else 1)
    return (round(pos[0] + rx, 4), round(pos[1] - ry, 4)), d


# ---------------------------------------------------------------- sheet
class Sheet:
    """insts: [(project, path, n)] - every instance of this sheet file; references get the instance number n"""
    def __init__(self, insts, uid=None):
        self.items = []; self.used = set(); self.uuid = uid or U(); self.insts = insts; self.cnt = {}
    def ref(self, prefix):
        self.cnt[prefix] = self.cnt.get(prefix, 0) + 1
        return [(pr, pa, "%s%s%02d" % (prefix, n, self.cnt[prefix])) for pr, pa, n in self.insts]
    def wire(self, a, b):
        self.items.append('(wire (pts (xy %s %s) (xy %s %s)) (stroke (width 0) (type default)) (uuid "%s"))'
                          % (f(a[0]), f(a[1]), f(b[0]), f(b[1]), U()))
    def text(self, s, p, size=1.27):
        self.items.append('(text %s (exclude_from_sim no) (at %s %s 0) (effects (font (size %s %s)) (justify left top)) (uuid "%s"))'
                          % (q(s), f(p[0]), f(p[1]), size, size, U()))
    def _inst(self, refs, unit):
        by = {}
        for pr, pa, r in refs: by.setdefault(pr, []).append('(path "%s" (reference %s) (unit %d))' % (pa, q(r), unit))
        return ' '.join('(project %s %s)' % (q(pr), ' '.join(v)) for pr, v in by.items())
    def symbol(self, lib, pos, ang, refs, value, unit=1, props=None, ref_off=(2.54, -1.27), val_off=(2.54, 1.27),
               hide_ref=False, hide_val=False, pins=None):
        self.used.add(lib)
        pr = []
        def prop(k, v, off, hide, shown):
            fx = FONT % ((' (justify left)' if shown else '') + (' (hide yes)' if hide or not shown else ''))
            pr.append('(property %s %s (at %s %s 0) %s)' % (q(k), q(v), f(pos[0]+off[0]), f(pos[1]+off[1]), fx))
        prop("Reference", refs[0][2], ref_off, hide_ref, True)
        prop("Value", value, val_off, hide_val, True)
        prop("Footprint", "", (0, 0), True, False)
        prop("Datasheet", "~", (0, 0), True, False)
        for k, v in (props or {}).items(): prop(k, v, (0, 0), True, False)
        pins = pins or list(pins_of(lib, unit).keys()) if lib in PINS else (pins or ["1"])
        pl = ' '.join('(pin "%s" (uuid "%s"))' % (n, U()) for n in pins)
        self.items.append('(symbol (lib_id %s) (at %s %s %d) (unit %d) (exclude_from_sim no) (in_bom yes) (on_board yes) (dnp no) (uuid "%s") %s %s (instances %s))'
                          % (q(lib), f(pos[0]), f(pos[1]), ang, unit, U(), ' '.join(pr), pl, self._inst(refs, unit)))
    def power(self, net, p, d):
        lib = POWER[net]
        up = net in ("+150V", "+6.3V")
        ang = {(0, -1): 0, (0, 1): 180, (-1, 0): 90, (1, 0): 270}[d] if up else \
              {(0, 1): 0, (0, -1): 180, (-1, 0): 270, (1, 0): 90}[d]
        self.symbol(lib, p, ang, self.ref("#PWR"), net, ref_off=(0, 0), val_off=(1.27 * d[0], 1.27 * d[1] + (-2.54 if up else 2.54)),
                    hide_ref=True, pins=["1"])
    def label(self, net, p, d, hier=None):
        ang = {(1, 0): 0, (-1, 0): 180, (0, -1): 90, (0, 1): 270}[d]
        j = "left" if ang in (0, 90) else "right"
        if hier:
            self.items.append('(hierarchical_label %s (shape %s) (at %s %s %d) (effects (font (size 1.27 1.27)) (justify %s)) (uuid "%s"))'
                              % (q(net), hier, f(p[0]), f(p[1]), ang, j, U()))
        else:
            self.items.append('(label %s (at %s %s %d) (effects (font (size 1.27 1.27)) (justify %s bottom)) (uuid "%s"))'
                              % (q(net), f(p[0]), f(p[1]), ang, j, U()))
    def noconn(self, p):
        self.items.append('(no_connect (at %s %s) (uuid "%s"))' % (f(p[0]), f(p[1]), U()))
    def attach(self, p, d, net, hier=None, stub=G):
        """stub from a pin (or sheet pin) to a label / power symbol / no-connect"""
        if net == "NC": self.noconn(p); return
        e = (round(p[0] + d[0] * stub, 4), round(p[1] + d[1] * stub, 4))
        self.wire(p, e)
        if net in POWER: self.power(net, e, d)
        else: self.label(net, e, d, hier.get(net) if hier else None)
    def part(self, lib, pos, prefix, value, nets, ang=0, unit=1, props=None, hier=None, refs=None, ref_off=None, val_off=None):
        refs = refs or self.ref(prefix)
        ro = ref_off or ((3.81, -1.27) if lib.startswith("Device") else (5.08, -7.62))
        vo = val_off or ((3.81, 1.27) if lib.startswith("Device") else (5.08, 7.62))
        self.symbol(lib, pos, ang, refs, value, unit=unit, props=props, ref_off=ro, val_off=vo)
        for pin, net in nets.items():
            p, d = pin_xy(lib, pos, ang, pin, unit)
            if isinstance(net, tuple):            # (net, [(dx, dy), ...] in grid steps): a bent stub
                net, path = net
                for dx, dy in path[:-1]:
                    e = (round(p[0] + dx * G, 4), round(p[1] + dy * G, 4)); self.wire(p, e); p = e
                dx, dy = path[-1]
                d = (int(math.copysign(1, dx)) if dx else 0, int(math.copysign(1, dy)) if dy else 0)
                self.attach(p, d, net, hier, stub=G * abs(dx or dy))
            else:
                self.attach(p, d, net, hier)
        return refs
    def subsheet(self, name, file, pos, size, pins, nets, page_paths, uid, hier=None):
        """pins: [(name, type, side 'L'|'R', row)], nets: pin -> net in this sheet; page_paths: [(project, path, page)]"""
        x, y = pos; w, h = size
        ps = []
        for n, t, side, row in pins:
            p = (x if side == "L" else x + w, y + (row + 1) * G)
            d = (-1, 0) if side == "L" else (1, 0)
            ps.append('(pin %s %s (at %s %s %d) (uuid "%s") (effects (font (size 1.27 1.27)) (justify %s)))'
                      % (q(n), t, f(p[0]), f(p[1]), 180 if side == "L" else 0, U(), "left" if side == "L" else "right"))
            self.attach(p, d, nets[n], hier, stub=2 * G)
        by = {}
        for pr, pa, pg in page_paths: by.setdefault(pr, []).append('(path "%s" (page "%s"))' % (pa, pg))
        inst = ' '.join('(project %s %s)' % (q(pr), ' '.join(v)) for pr, v in by.items())
        self.items.append('(sheet (at %s %s) (size %s %s) (exclude_from_sim no) (in_bom yes) (on_board yes) (dnp no) (fields_autoplaced yes) '
                          '(stroke (width 0.1524) (type solid)) (fill (color 0 0 0 0.0000)) (uuid "%s") '
                          '(property "Sheetname" %s (at %s %s 0) (effects (font (size 1.27 1.27)) (justify left bottom))) '
                          '(property "Sheetfile" %s (at %s %s 0) (effects (font (size 1.27 1.27)) (justify left top))) %s (instances %s))'
                          % (f(x), f(y), f(w), f(h), uid, q(name), f(x), f(y - 0.7), q(file), f(x), f(y + h + 0.6), ' '.join(ps), inst))
        return uid
    def dump(self, path, title, root=False, comments=(), paper="A4"):
        libs = '\n'.join(LIBS[k] for k in sorted(self.used))
        tb = '(title_block (title %s) (company "DekatronPC") %s)' % (q(title), ' '.join('(comment %d %s)' % (i+1, q(c)) for i, c in enumerate(comments)))
        si = '(sheet_instances (path "/" (page "1")))' if root else ''
        open(path, "w").write('(kicad_sch (version 20260306) (generator "eeschema") (generator_version "10.0") (uuid "%s") (paper "%s") %s\n(lib_symbols\n%s)\n%s\n%s\n(embedded_fonts no))\n'
                              % (self.uuid, paper, tb, libs, '\n'.join(self.items), si))

FONT = '(effects (font (size 1.27 1.27))%s)'


def divider(sh, x, y, hv, lv, c1, hier=None):
    """HV -> LV divider: R1 470k || C1 from hv to lv, R2 200k from lv to -50 V, three vertical parts in a row"""
    sh.part("Device:R", (x, y), "R", "470k", {"1": hv, "2": lv}, hier=hier)
    sh.part("Device:C", (x + 5*G, y), "C", c1, {"1": hv, "2": lv}, hier=hier)
    sh.part("Device:R", (x + 10*G, y), "R", "200k", {"1": lv, "2": "-50V"}, hier=hier)
