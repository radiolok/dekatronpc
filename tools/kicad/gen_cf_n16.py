#!/usr/bin/env python3
"""Generate the BUF_N16 and OR2_N16 cell sheets and their testbenches (doc/cell_design_method.md,
sch/logic/BUF_N16/README.md).

usage: gen_cf_n16.py OUT_DIR
  OUT_DIR/BUF_N16/BUF_N16.kicad_sch     two cathode followers on one 6N16B: Y1 = A1, Y2 = A2 (liberty BUF_N16 = half a tube)
  OUT_DIR/OR2_N16/OR2_N16.kicad_sch    one 6N16B, cathodes tied: Y = A | B
  OUT_DIR/<cell>/<cell>_tb.kicad_sch/.kicad_pro   testbenches; netlist, stimulus and .meas as tools/spice/cf_sweep.py
Each follower: plate -> +150 V, cathode -> Rs 2.2k || Cs 100p -> Y -> Rk 12k -> -50 V. Y is LV and goes straight
onto the load grids (no divider); each input grid needs its own divider (C1 2.7 pF per follower grid).
Helpers and the label-at-pin-stub style are copied from gen_latch_j2n16.py. Every run makes new UUIDs:
regenerate to start over, edit drawn sheets in KiCad.
"""
import math, uuid, re, sys, os

OUT = sys.argv[1]
for _c in ("BUF_N16", "OR2_N16"): os.makedirs(os.path.join(OUT, _c), exist_ok=True)
SYSLIB = os.environ.get("KICAD_SYMBOL_DIR", "/usr/share/kicad/symbols")
REPO = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, os.path.join(REPO, "tools", "spice"))
import cf_sweep as SW

G = 2.54
def U(): return str(uuid.uuid4())
def q(s): return '"' + s.replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n') + '"'
def f(v): return ("%.4f" % v).rstrip("0").rstrip(".")
def pf(v): return ("%.2f" % v).rstrip("0").rstrip(".") + "p"


# ---------------------------------------------------------------- lib symbols (as gen_latch_j2n16.py)
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

N16 = "vacuum_tube:6Н16Б"
SIM = {N16: {"Sim.Library": "${KIPRJMOD}/../../libs/6N16B.sub", "Sim.Name": "6N16B", "Sim.Device": "SUBCKT",
             "Sim.Pins": "1=Pa 7=Ga 6=Ka 5=Pb 3=Gb 2=Kb"}}

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
    N16: tube_lib("6Н16Б", N16),
}

PINS = {  # lib-space pin coordinates (y up)
    "Device:R": {"1": (0, 3.81), "2": (0, -3.81)},
    "Device:C": {"1": (0, 3.81), "2": (0, -3.81)},
    "Simulation_SPICE:VDC": {"1": (0, 5.08), "2": (0, -5.08)},
    "Simulation_SPICE:VPWL": {"1": (0, 5.08), "2": (0, -5.08)},
    N16: {1: {"1": (0, 10.16), "7": (-7.62, 0), "6": (-2.54, -10.16), "4": (1.27, -10.16), "8": (-1.27, -10.16)},
          2: {"5": (0, 10.16), "3": (-7.62, 0), "2": (-2.54, -10.16)}},
}
# bottom pins of a tube are 1.27 mm apart: cathode straight down, heaters bent to the right at different heights
def n16_bottom(h1="H1", h2="H2", k="GND"):
    return {"6": (k, [(0, 5)]), "8": (h1, [(0, 3), (5, 0)]), "4": (h2, [(0, 1), (3, 0)])}
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

FONT = '(effects (font (size 1.27 1.27))%s)'


# ---------------------------------------------------------------- sheet (as gen_latch_j2n16.py)
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
    def dump(self, path, title, root=False, comments=(), paper="A4", passive_plates=False):
        libs = '\n'.join(LIBS[k] for k in sorted(self.used))
        if passive_plates:      # a follower plate sits on +150 V: passive, not open collector, so ERC accepts it
            libs = libs.replace('(pin open_collector', '(pin passive')
        tb = '(title_block (title %s) (company "DekatronPC") %s)' % (q(title), ' '.join('(comment %d %s)' % (i+1, q(c)) for i, c in enumerate(comments)))
        si = '(sheet_instances (path "/" (page "1")))' if root else ''
        open(path, "w").write('(kicad_sch (version 20260306) (generator "eeschema") (generator_version "10.0") (uuid "%s") (paper "%s") %s\n(lib_symbols\n%s)\n%s\n%s\n(embedded_fonts no))\n'
                              % (self.uuid, paper, tb, libs, '\n'.join(self.items), si))


def divider(sh, x, y, hv, lv, c1, hier=None):
    """HV -> LV divider: R1 470k || C1 from hv to lv, R2 200k from lv to -50 V, three vertical parts in a row"""
    sh.part("Device:R", (x, y), "R", SW.DEFAULT["R1"], {"1": hv, "2": lv}, hier=hier)
    sh.part("Device:C", (x + 5*G, y), "C", c1, {"1": hv, "2": lv}, hier=hier)
    sh.part("Device:R", (x + 10*G, y), "R", SW.DEFAULT["R2"], {"1": lv, "2": "-50V"}, hier=hier)


def follower(sh, x, y, k, out, hier):
    """the level-shifting cathode load: Rs || Cs from the cathode k to out, Rk from out to -50 V"""
    sh.part("Device:R", (x, y), "R", P["Rs"], {"1": k, "2": out}, hier=hier)
    sh.part("Device:C", (x + 5*G, y), "C", P["Cs"], {"1": k, "2": out}, hier=hier)
    sh.part("Device:R", (x + 10*G, y), "R", P["Rk"], {"1": out, "2": "-50V"}, hier=hier)


# ================================================================ the cells
P = SW.DEFAULT
C1 = pf(P["C1g"])
R = {k: U() for k in ("BUF", "OR2")}          # testbench root sheets
S = {k: U() for k in ("BUF", "OR2")}          # DUT sheet instances
PROJ = {k: f"{k}_N16_tb" for k in ("BUF", "OR2")}
x0, y0 = 30*G, 30*G
NOTE_DIV = ("Input: LV (1 = +10 V, 0 = -20 V), from its OWN divider on the driving HV net: 470k || C1 / 200k to -50 V,\n"
            "C1 = 2.7 pF per follower grid. Never share that divider with gate grids (NOT/NOR/NAND): they clamp a '1' at\n"
            "+0.4 V and Y then stays near -5 V. Output Y: LV, straight onto gate grids (no divider); fanout 10 grids.\n"
            "Y must not drive another BUF_N16/OR2_N16 input or any HV input. Supplies: +150 V, -50 V, heater 6.3 V 0.4 A.")

# ---------------------------------------------------------------- BUF_N16
buf = Sheet([(PROJ["BUF"], f"/{R['BUF']}/{S['BUF']}", 1)])
HB = {"A1": "input", "A2": "input", "Y1": "output", "Y2": "output", "H1": "passive", "H2": "passive"}
t = buf.ref("Л")
buf.part(N16, (x0, y0), None, "6Н16Б", {"1": "+150V", "7": "A1", **n16_bottom(k="K1")}, unit=1, props=SIM[N16], hier=HB, refs=t)
buf.part(N16, (x0, y0 + 25*G), None, "6Н16Б", {"5": "+150V", "3": "A2", "2": "K2"}, unit=2, props=SIM[N16], hier=HB, refs=t)
follower(buf, x0 + 20*G, y0, "K1", "Y1", HB)
follower(buf, x0 + 20*G, y0 + 25*G, "K2", "Y2", HB)
buf.text("BUF_N16: Y1 = A1, Y2 = A2. One 6N16B (6Н16Б): two independent cathode followers (owner, 2026-10-28).\n"
         "Each: plate to +150 V; cathode -> Rs 2.2k || Cs 100p -> Y -> Rk 12k -> -50 V. Rs puts Y ~5 V below the cathode,\n"
         "so '0' is about -19 V although the cathode sits 5 V above its grid, and it limits the load grid current on a '1'.\n"
         + NOTE_DIV + "\n"
         "Simulated, fanout 2/10 (input grid -5 V -> load plate 100 V): Y up 24/69 ns, Y down 32/224 ns. Ik 5.4 mA, Pa 0.74 W.\n"
         "Page: sch/logic/BUF_N16/README.md", (15*G, 70*G))
buf.dump(os.path.join(OUT, "BUF_N16", "BUF_N16.kicad_sch"), "BUF_N16 - 2 x BUF (cathode follower) on 6N16B",
         comments=["Y1 = A1, Y2 = A2; A: LV via own divider (C1 2.7p); Y: LV, straight to gate grids",
                   "plate +150 V; Rs 2.2k || Cs 100p, Rk 12k to -50 V per triode"], passive_plates=True)
BUF_PINS = [("A1", "input", "L", 1), ("A2", "input", "L", 3), ("H1", "passive", "L", 6), ("H2", "passive", "L", 7),
            ("Y1", "output", "R", 1), ("Y2", "output", "R", 3)]

# ---------------------------------------------------------------- OR2_N16
orc = Sheet([(PROJ["OR2"], f"/{R['OR2']}/{S['OR2']}", 1)])
HO = {"A": "input", "B": "input", "Y": "output", "H1": "passive", "H2": "passive"}
t = orc.ref("Л")
orc.part(N16, (x0, y0), None, "6Н16Б", {"1": "+150V", "7": "A", **n16_bottom(k="K")}, unit=1, props=SIM[N16], hier=HO, refs=t)
orc.part(N16, (x0, y0 + 25*G), None, "6Н16Б", {"5": "+150V", "3": "B", "2": "K"}, unit=2, props=SIM[N16], hier=HO, refs=t)
follower(orc, x0 + 20*G, y0 + 12*G, "K", "Y", HO)
orc.text("OR2_N16: Y = A | B. One 6N16B (6Н16Б): two cathode followers with the cathodes tied (owner, 2026-10-28).\n"
         "Plates to +150 V; common cathode K -> Rs 2.2k || Cs 100p -> Y -> Rk 12k -> -50 V. The higher grid carries the current.\n"
         + NOTE_DIV + "\n"
         "Simulated, fanout 2/10 (input grid -5 V -> load plate 100 V): Y up 26/85 ns, Y down 41/241 ns. Ik 5.7 mA, Pa 0.74 W.\n"
         "Hazard: A down with B up together dips Y; the load plate reaches 119 V at fanout 2 for < 0.2 us (73 V at fanout 10).\n"
         "Page: sch/logic/BUF_N16/README.md", (15*G, 70*G))
orc.dump(os.path.join(OUT, "OR2_N16", "OR2_N16.kicad_sch"), "OR2_N16 - OR2 (cathode followers) on 6N16B",
         comments=["Y = A | B; A, B: LV via own divider (C1 2.7p); Y: LV, straight to gate grids",
                   "plates +150 V; common Rs 2.2k || Cs 100p, Rk 12k to -50 V"], passive_plates=True)
OR2_PINS = [("A", "input", "L", 1), ("B", "input", "L", 3), ("H1", "passive", "L", 6), ("H2", "passive", "L", 7),
            ("Y", "output", "R", 2)]


# ================================================================ testbenches (same netlist as cf_sweep.deck)
def pwl_param(bits):
    """cf_sweep.pwl of the inverted bits (the driver inverts), as a KiCad VPWL parameter in microseconds"""
    s = SW.pwl([1 - b for b in bits], 50, 150)[4:-1].split()
    return " ".join((f"{float(a)*1e6:.4f}u" if i % 2 == 0 else a) for i, a in enumerate(s))


def testbench(cell, cell_file, cell_pins, size, outs):
    proj = PROJ[cell]
    sa, sb = SW.SEQ[cell]
    sh = Sheet([(proj, f"/{R[cell]}", "")], uid=R[cell])
    # supplies
    x = 10*G
    for v, top, bot, y in (("150", "+150V", "GND", 15*G), ("50", "GND", "-50V", 35*G), ("6.3", "+6.3V", "GND", 55*G)):
        props = {"Sim.Device": "V", "Sim.Type": "DC", "Sim.Pins": "1=+ 2=-", "Sim.Params": f"dc={v}"}
        sh.symbol("Simulation_SPICE:VDC", (x, y), 0, sh.ref("V"), v, props=props, ref_off=(3.81, -1.27), val_off=(3.81, 1.27))
        for pin, net in (("1", top), ("2", bot)):
            p, d = pin_xy("Simulation_SPICE:VDC", (x, y), 0, pin)
            e = (p[0], p[1] + d[1] * G)
            sh.wire(p, e); sh.power(net, e, d)
            if net != "GND" or v == "150":
                fp = (e[0] + 3*G, e[1]); sh.wire(e, fp)
                sh.symbol("power:PWR_FLAG", fp, 0, sh.ref("#FLG"), "PWR_FLAG", ref_off=(0, -1.905), val_off=(1.27, -3.81), hide_ref=True, pins=["1"])
    # drivers: PWL (HV, ideal) -> divider 3.9 pF -> one 6N16B, a NOT per input (Ra 10k) -> divider C1 -> DUT input
    t = sh.ref("Л")
    for i, (k, bits) in enumerate((("A", sa), ("B", sb))):
        y = 12*G + i * 26*G
        props = {"Sim.Device": "V", "Sim.Type": "PWL", "Sim.Pins": "1=+ 2=-", "Sim.Params": f'pwl="{pwl_param(bits)}"'}
        sh.part("Simulation_SPICE:VPWL", (30*G, y + 4*G), "V", "VPWL", {"1": f"STIM_{k}", "2": "GND"}, props=props)
        divider(sh, 38*G, y + 4*G, f"STIM_{k}", f"IS_{k}", "3.9p")
        if i == 0:
            sh.part(N16, (75*G, y + 6*G), None, "6Н16Б", {"1": "PDA", "7": "IS_A", **n16_bottom("+6.3V", "GND")},
                    unit=1, props=SIM[N16], refs=t)
        else:
            sh.part(N16, (75*G, y + 6*G), None, "6Н16Б", {"5": "PDB", "3": "IS_B", "2": "GND"}, unit=2, props=SIM[N16], refs=t)
        sh.part("Device:R", (65*G, y + 2*G), "R", "10k", {"1": "+150V", "2": f"PD{k}"})
        divider(sh, 90*G, y + 4*G, f"PD{k}", k, C1)
    # DUT
    nets = {n: n for n, *_ in cell_pins}; nets.update(H1="+6.3V", H2="GND")
    nets.update({p: o for p, o in outs.items()})
    if cell == "BUF": nets.update(A1="A", A2="B")
    sh.subsheet("DUT", cell_file, (130*G, 20*G), size, cell_pins, nets, [(proj, f"/{R[cell]}", "2")], S[cell])
    # outputs: 10 grids each, straight on the LV net (no divider): 5 load tubes, both grids on the net, plates 10k
    for j, o in enumerate(outs.values()):
        y = 12*G + j * 26*G
        for i in range(5):
            tl = sh.ref("Л"); xx = 165*G + i * 30*G
            pa = f"PL{o[-1]}" if i == 0 else f"PL{o[-1]}{i}a"
            sh.part(N16, (xx, y + 6*G), None, "6Н16Б", {"1": pa, "7": o, **n16_bottom("+6.3V", "GND")},
                    unit=1, props=SIM[N16], refs=tl)
            sh.part(N16, (xx + 12*G, y + 6*G), None, "6Н16Б", {"5": f"PL{o[-1]}{i}b", "3": o, "2": "GND"}, unit=2, props=SIM[N16], refs=tl)
            sh.part("Device:R", (xx - 5*G, y - 2*G), "R", "10k", {"1": "+150V", "2": pa})
            sh.part("Device:R", (xx + 18*G, y - 2*G), "R", "10k", {"1": "+150V", "2": f"PL{o[-1]}{i}b"})
    stop = 2 * len(sa)
    yt = 12*G + 26*G * 2 + 4*G
    sh.text(".tran 5n %du" % stop, (20*G, yt), 1.5)
    seq = " ".join(f"{a}{b}" for a, b in zip(sa, sb))
    sh.text(f"{cell}_N16 testbench (tools/kicad/gen_cf_n16.py; the same netlist and .meas as tools/spice/cf_sweep.py).\n"
            f"2 us per input state, (A,B) = {seq}.\n"
            "STIM_x (HV PWL, ideal) -> divider -> driver inverter (one 6N16B, Ra 10k) -> divider (C1 2.7 pF) -> x (LV DUT input).\n"
            "Each DUT output goes straight onto 5 load tubes (both grids on the net) = 10 grids; PLA / PLB = a load plate.\n"
            "Plot V(/A) V(/B) V(/YA)" + (" V(/YB)" if cell == "BUF" else "") + " V(/PLA). .meas: ya*/pa* = Y and the load plate at the end of each state,\n"
            "tplh_*/tphl_* = DUT grid (-5 V) -> Y (-5 V), tqlh_*/tqhl_* = DUT grid (-5 V) -> load plate (100 V)"
            + (", hz_* = the A-down/B-up hazard." if cell == "OR2" else "."), (20*G, yt + 3*G))
    sh.text("\n".join("." + l for l in SW.meas_lines(cell, "/A", "/B", "/YA", "/YB", "/PLA", "/PLB", stop, pda="/PDA", ik=False)),
            (20*G, yt + 14*G), 1.0)
    sh.dump(os.path.join(OUT, f"{cell}_N16", f"{cell}_N16_tb.kicad_sch"), f"{cell}_N16 testbench", root=True,
            comments=["HV +150/+50 V, LV +10/-20 V; DUT output LV straight onto 10 grids", f"(A,B) = {seq}, 2 us per state"], paper="A1")
    open(os.path.join(OUT, f"{cell}_N16", f"{cell}_N16_tb.kicad_pro"), "w").write(
        '{\n  "meta": {\n    "filename": "%s_N16_tb.kicad_pro",\n    "version": 3\n  }\n}\n' % cell)


testbench("BUF", "BUF_N16.kicad_sch", BUF_PINS, (12*G, 9*G), {"Y1": "YA", "Y2": "YB"})
testbench("OR2", "OR2_N16.kicad_sch", OR2_PINS, (12*G, 9*G), {"Y": "YA"})
print("ok")
