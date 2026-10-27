#!/usr/bin/env python3
"""Generate the RSLATCH_J2N16, DLATCH2_J2N16 and DFF_J2N16 sheets and their testbenches
(doc/cell_design_method.md, doc/latch_j2n16.md).

usage: gen_latch_j2n16.py OUT_DIR
  OUT_DIR/RSLATCH_J2N16.kicad_sch   cell: gated RS latch, 2 x 6Zh2B + 1 x 6N16B (sub-sheet of the two below)
  OUT_DIR/DLATCH2_J2N16.kicad_sch   two D latches: 2 x RSLATCH + one 6N16B for both D inverters (7 tubes)
  OUT_DIR/DFF_J2N16.kicad_sch       master-slave D flip-flop, falling edge: 2 x RSLATCH + one 6N16B (D and C) (7 tubes)
  OUT_DIR/<cell>_tb.kicad_sch/.kicad_pro   testbenches; stimulus, loads and .meas from tools/spice/latch_tb.py

Unlike gen_nand2_j2.py the parts are connected by net labels at short pin stubs, not by drawn wires: the cells have
many internal nets, and the labels carry the same names as the plain-SPICE reference (latch_tb.py).
Every run makes new UUIDs: regenerate to start over, edit drawn sheets in KiCad. RSLATCH_J2N16.kicad_sch carries
the instances of all three testbench projects.
"""
import math, uuid, re, sys, os

OUT = sys.argv[1]
SYSLIB = os.environ.get("KICAD_SYMBOL_DIR", "/usr/share/kicad/symbols")
REPO = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, os.path.join(REPO, "tools", "spice"))
import latch_tb as TB

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

J2, N16 = "vacuum_tube:6Ж2Б", "vacuum_tube:6Н16Б"
SIM = {J2: {"Sim.Library": "${KIPRJMOD}/../libs/6Zh2B.sub", "Sim.Name": "6Zh2B", "Sim.Device": "SUBCKT",
            "Sim.Pins": "1=A 2=G3 3=G2 6=K 7=G1"},
       N16: {"Sim.Library": "${KIPRJMOD}/../libs/6N16B.sub", "Sim.Name": "6N16B", "Sim.Device": "SUBCKT",
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
    J2: tube_lib("6Ж2Б", J2),
    N16: tube_lib("6Н16Б", N16),
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
}
# bottom pins of a tube are 1.27 mm apart: cathode straight down, heaters bent to the right at different heights
def heat(h1, h2, k="GND"):
    return {"k": (k, [(0, 5)]), "h1": (h1, [(0, 3), (5, 0)]), "h2": (h2, [(0, 1), (3, 0)])}
def j2_bottom(h1="H1", h2="H2"):
    b = heat(h1, h2); return {"6": b["k"], "4": b["h1"], "5": b["h2"]}
def n16_bottom(h1="H1", h2="H2"):
    b = heat(h1, h2); return {"6": b["k"], "8": b["h1"], "4": b["h2"]}
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


# ================================================================ the cells
P = TB.P
RA, RG2, CB = "10k", "15k", "%dp" % P['Cb']
C1F, C1P, C1G3 = pf(P['C1f']), pf(P['C1p']), P['C1g3']

# sheet uuids of the testbench roots and of every sheet instance, fixed before any file is written
R = {k: U() for k in ("rs", "dl", "df")}
S = {k: U() for k in ("rs_dut", "dl_dut", "df_dut", "dl_l1", "dl_l2", "df_m", "df_s")}
PROJ = {"rs": "RSLATCH_J2N16_tb", "dl": "DLATCH2_J2N16_tb", "df": "DFF_J2N16_tb"}

# ---------------------------------------------------------------- RSLATCH_J2N16
rs_insts = [(PROJ["rs"], f"/{R['rs']}/{S['rs_dut']}", 1),
            (PROJ["dl"], f"/{R['dl']}/{S['dl_dut']}/{S['dl_l1']}", 1), (PROJ["dl"], f"/{R['dl']}/{S['dl_dut']}/{S['dl_l2']}", 2),
            (PROJ["df"], f"/{R['df']}/{S['df_dut']}/{S['df_m']}", 1), (PROJ["df"], f"/{R['df']}/{S['df_dut']}/{S['df_s']}", 2)]
rs = Sheet(rs_insts)
H = {"S": "input", "R": "input", "E": "input", "Q": "output", "QN": "output", "H1": "passive", "H2": "passive"}
x0, y0 = 30*G, 30*G
# QN half: pentode (S on g1, E on g3) and triode A (grid from Q) on the plate QN; Q half mirrored
rs.part(J2, (x0, y0), "Л", "6Ж2Б", {"1": "QN", "2": "E", "3": "SG1", "7": "S", **j2_bottom()}, props=SIM[J2], hier=H)
rs.part(J2, (x0, y0 + 30*G), "Л", "6Ж2Б", {"1": "Q", "2": "E", "3": "SG2", "7": "R", **j2_bottom()}, props=SIM[J2], hier=H)
tref = rs.ref("Л")
rs.part(N16, (x0 + 25*G, y0), None, "6Н16Б", {"1": "QN", "7": "FQ", **n16_bottom()}, unit=1, props=SIM[N16], hier=H, refs=tref)
rs.part(N16, (x0 + 25*G, y0 + 30*G), None, "6Н16Б", {"5": "Q", "3": "FQN", "2": "GND"}, unit=2, props=SIM[N16], hier=H, refs=tref)
# plate and screen resistors, Cb on each g3 (to -50 V, as in latch_sweep.py)
rs.part("Device:R", (x0 + 40*G, y0 - 6*G), "R", RA, {"1": "+150V", "2": "QN"}, hier=H)
rs.part("Device:R", (x0 + 40*G, y0 + 24*G), "R", RA, {"1": "+150V", "2": "Q"}, hier=H)
rs.part("Device:R", (x0 + 12*G, y0 - 6*G), "R", RG2, {"1": "+150V", "2": "SG1"}, hier=H)
rs.part("Device:R", (x0 + 12*G, y0 + 24*G), "R", RG2, {"1": "+150V", "2": "SG2"}, hier=H)
rs.part("Device:C", (x0 - 12*G, y0 + 10*G), "C", CB, {"1": "E", "2": "-50V"}, hier=H)
rs.part("Device:C", (x0 - 12*G, y0 + 40*G), "C", CB, {"1": "E", "2": "-50V"}, hier=H)
# cross-coupling dividers: Q -> FQ (grid of triode A), QN -> FQN (grid of triode B)
divider(rs, x0 + 50*G, y0 + 2*G, "Q", "FQ", C1F, hier=H)
divider(rs, x0 + 50*G, y0 + 32*G, "QN", "FQN", C1F, hier=H)
rs.text("RSLATCH_J2N16: gated RS latch. QN = ~((S & E) | Q), Q = ~((R & E) | QN).\n"
        "Two AND-OR-INVERT halves: 6Zh2B (S or R on g1, E on g3) and one triode of the 6N16B on a common plate, Ra 10k.\n"
        "Each plate drives the other half's triode through a divider in the cell (470k || 3.9 pF / 200k to -50 V).\n"
        "S, R, E: LV (1 = +10 V, 0 = -20 V). Q, QN: HV (1 = +150 V, 0 = +50 V). S = R = 1 with E = 1 is forbidden (Q = QN = 0).\n"
        "Screens Rg2 15k from +150 V; Cb 15 pF on each g3 holds E against the plate swing (g3 Miller, doc/nand2_j2_6zh2b.md).\n"
        "Input divider C1 per grid: S, R (pentode g1) 2.7 pF; E (two g3) 2 x 6.8 pF. Outputs: one divider per net, 3.9 pF per triode grid.\n"
        "Simulated, fanout 2/10: E -> Q 172/368 ns, S -> QN 138/337 ns; E pulse >= 216/454 ns; setup 182/432 ns, hold <= 0.\n"
        "Heater 6.3 V: 2 x 0.2 A + 0.4 A on H1/H2. Page: doc/latch_j2n16.md", (20*G, 85*G))
rs.dump(os.path.join(OUT, "RSLATCH_J2N16.kicad_sch"), "RSLATCH_J2N16 - gated RS latch",
        comments=["QN = ~((S&E)|Q), Q = ~((R&E)|QN); S, R, E: LV; Q, QN: HV", "2 x 6Zh2B + 6N16B; Ra 10k, Rg2 15k, Cb 15p"], paper="A3")

RS_PINS = [("S", "input", "L", 1), ("R", "input", "L", 3), ("E", "input", "L", 5), ("H1", "passive", "L", 8),
           ("H2", "passive", "L", 9), ("Q", "output", "R", 1), ("QN", "output", "R", 3)]
RS_SIZE = (14*G, 11*G)


def inverter_tube(sh, nets1, nets2, hier, x, y):
    """one 6N16B as two inverters with Ra 10k: nets = (grid, plate)"""
    t = sh.ref("Л")
    sh.part(N16, (x, y), None, "6Н16Б", {"1": nets1[1], "7": nets1[0], **n16_bottom()}, unit=1, props=SIM[N16], hier=hier, refs=t)
    sh.part(N16, (x, y + 25*G), None, "6Н16Б", {"5": nets2[1], "3": nets2[0], "2": "GND"}, unit=2, props=SIM[N16], hier=hier, refs=t)
    sh.part("Device:R", (x + 12*G, y - 6*G), "R", "10k", {"1": "+150V", "2": nets1[1]}, hier=hier)
    sh.part("Device:R", (x + 12*G, y + 19*G), "R", "10k", {"1": "+150V", "2": nets2[1]}, hier=hier)


# ---------------------------------------------------------------- DLATCH2_J2N16
dl = Sheet([(PROJ["dl"], f"/{R['dl']}/{S['dl_dut']}", 9)])
HD = {"D1": "input", "D2": "input", "E": "input", "Q1": "output", "QN1": "output", "Q2": "output", "QN2": "output",
      "H1": "passive", "H2": "passive"}
inverter_tube(dl, ("D1", "DN1"), ("D2", "DN2"), HD, 25*G, 25*G)
divider(dl, 45*G, 27*G, "DN1", "R1", C1P, hier=HD)
divider(dl, 45*G, 52*G, "DN2", "R2", C1P, hier=HD)
for i, (uid, yy) in enumerate(((S['dl_l1'], 20*G), (S['dl_l2'], 45*G)), 1):
    nets = {"S": f"D{i}", "R": f"R{i}", "E": "E", "Q": f"Q{i}", "QN": f"QN{i}", "H1": "H1", "H2": "H2"}
    dl.subsheet(f"L{i}", "RSLATCH_J2N16.kicad_sch", (90*G, yy), RS_SIZE, RS_PINS, nets,
                [(PROJ["dl"], f"/{R['dl']}/{S['dl_dut']}", str(2 + i))], uid, hier=HD)
dl.text("DLATCH2_J2N16: two D latches, Qi = Di while E = 1, held while E = 0. 7 tubes: 2 x RSLATCH_J2N16 + one 6N16B.\n"
        "The 6N16B inverts D1 and D2 (Ra 10k), each through a divider (2.7 pF, one pentode g1) to R of its latch.\n"
        "D pins: one pentode g1 + one triode grid (divider C1 2.7 + 3.9 pF). E: four g3 (4 x 6.8 pF). Outputs HV.\n"
        "A 16-tube board holds two of these (four latches) or two DFF_J2N16. Page: doc/latch_j2n16.md", (20*G, 80*G))
dl.dump(os.path.join(OUT, "DLATCH2_J2N16.kicad_sch"), "DLATCH2_J2N16 - two D latches",
        comments=["Qi = Di while E = 1; D, E: LV; Q, QN: HV", "2 x RSLATCH_J2N16 + 6N16B (D inverters)"], paper="A3")

# ---------------------------------------------------------------- DFF_J2N16
df = Sheet([(PROJ["df"], f"/{R['df']}/{S['df_dut']}", 9)])
HF = {"D": "input", "C": "input", "Q": "output", "QN": "output", "H1": "passive", "H2": "passive"}
inverter_tube(df, ("D", "DN"), ("C", "CN"), HF, 25*G, 25*G)
divider(df, 45*G, 27*G, "DN", "RM", C1P, hier=HF)
divider(df, 45*G, 52*G, "CN", "ES", pf(2 * C1G3), hier=HF)
divider(df, 125*G, 22*G, "QM", "SS", C1P, hier=HF)
divider(df, 125*G, 32*G, "QNM", "RS", C1P, hier=HF)
df.subsheet("M", "RSLATCH_J2N16.kicad_sch", (90*G, 20*G), RS_SIZE,
            RS_PINS, {"S": "D", "R": "RM", "E": "C", "Q": "QM", "QN": "QNM", "H1": "H1", "H2": "H2"},
            [(PROJ["df"], f"/{R['df']}/{S['df_dut']}", "3")], S['df_m'], hier=HF)
df.subsheet("S", "RSLATCH_J2N16.kicad_sch", (90*G, 50*G), RS_SIZE,
            RS_PINS, {"S": "SS", "R": "RS", "E": "ES", "Q": "Q", "QN": "QN", "H1": "H1", "H2": "H2"},
            [(PROJ["df"], f"/{R['df']}/{S['df_dut']}", "4")], S['df_s'], hier=HF)
df.text("DFF_J2N16: master-slave D flip-flop, Q takes D at the FALLING edge of C (owner's drawing, 2026-10-27).\n"
        "Master M = RSLATCH (S = D, R = ~D, E = C): transparent while C = 1. Slave S = RSLATCH (S = QM, R = QNM, E = ~C).\n"
        "One 6N16B: D -> DN (divider 2.7 pF -> RM), C -> CN (divider 2 x 6.8 pF -> ES). QM, QNM -> SS, RS through 2.7 pF dividers.\n"
        "The C inverter must stay in the cell: the master opens before the slave closes by its delay, race margin ~90 ns.\n"
        "Simulated: register to register 1.11 / 1.05 / 0.93 MHz at fanout 2 / 6 / 10; C -> Q 340/539 ns (fanout 2/10); hold <= 0.\n"
        "D: one pentode g1 + one triode grid (C1 2.7 + 3.9 pF). C: two g3 + one triode grid (2 x 6.8 + 3.9 pF). 7 tubes, heater 2.0 A.\n"
        "Page: doc/latch_j2n16.md", (20*G, 80*G))
df.dump(os.path.join(OUT, "DFF_J2N16.kicad_sch"), "DFF_J2N16 - D flip-flop, falling edge",
        comments=["Q <= D at the falling edge of C; D, C: LV; Q, QN: HV", "2 x RSLATCH_J2N16 + 6N16B (D and C inverters)"], paper="A3")


# ================================================================ testbenches
def testbench(key, tb, cell_file, cell_pins, size):
    proj = PROJ[key]
    sh = Sheet([(proj, f"/{R[key]}", "")], uid=R[key])
    # supplies
    x = 10*G
    for i, (v, top, bot, y) in enumerate((("150", "+150V", "GND", 15*G), ("50", "GND", "-50V", 35*G), ("6.3", "+6.3V", "GND", 55*G))):
        props = {"Sim.Device": "V", "Sim.Type": "DC", "Sim.Pins": "1=+ 2=-", "Sim.Params": f"dc={v}"}
        rf = sh.ref("V")
        sh.symbol("Simulation_SPICE:VDC", (x, y), 0, rf, v, props=props, ref_off=(3.81, -1.27), val_off=(3.81, 1.27))
        for pin, net in (("1", top), ("2", bot)):
            p, d = pin_xy("Simulation_SPICE:VDC", (x, y), 0, pin)
            e = (p[0], p[1] + d[1] * G)
            sh.wire(p, e); sh.power(net, e, d)
            if net != "GND" or v == "150":
                fp = (e[0] + 3*G, e[1]); sh.wire(e, fp)
                sh.symbol("power:PWR_FLAG", fp, 0, sh.ref("#FLG"), "PWR_FLAG", ref_off=(0, -1.905), val_off=(1.27, -3.81), hide_ref=True, pins=["1"])
    # drivers: PWL source -> divider -> 6N16B triode (Ra 10k; second triode cut off, grid at -50 V) -> divider -> input
    y = 12*G
    for k, (times, bits) in tb['src'].items():
        pts = " ".join(f"{t:.4f}u {v}" for t, v in TB.pwl_pts(times, bits))
        props = {"Sim.Device": "V", "Sim.Type": "PWL", "Sim.Pins": "1=+ 2=-", "Sim.Params": f'pwl="{pts}"'}
        sh.part("Simulation_SPICE:VPWL", (30*G, y + 4*G), "V", "VPWL", {"1": f"STIM_{k}", "2": "GND"}, props=props)
        divider(sh, 38*G, y + 4*G, f"STIM_{k}", f"IS_{k}", pf(P['C1g']))
        t = sh.ref("Л")
        sh.part(N16, (75*G, y + 6*G), None, "6Н16Б", {"1": f"PD_{k}", "7": f"IS_{k}", **n16_bottom("+6.3V", "GND")},
                unit=1, props=SIM[N16], refs=t)
        sh.part(N16, (88*G, y + 6*G), None, "6Н16Б", {"5": f"PDX_{k}", "3": "-50V", "2": "GND"}, unit=2, props=SIM[N16], refs=t)
        sh.part("Device:R", (65*G, y + 2*G), "R", "10k", {"1": "+150V", "2": f"PD_{k}"})
        sh.part("Device:R", (98*G, y + 2*G), "R", "10k", {"1": "+150V", "2": f"PDX_{k}"})
        divider(sh, 104*G, y + 4*G, f"PD_{k}", k, pf(tb['inputs'][k]))
        y += 26*G
    # DUT
    nets = {n: n for n, *_ in cell_pins}; nets.update(H1="+6.3V", H2="GND")
    sh.subsheet("DUT", cell_file, (150*G, 20*G), size, cell_pins, nets, [(proj, f"/{R[key]}", "2")], S[key + "_dut"])
    # outputs: one divider each -> load tubes (both grids on the LV net, plates through 10k)
    y = 12*G
    for o, ng in tb['outputs'].items():
        divider(sh, 185*G, y + 4*G, o, f"{o}_LV", pf(P['C1g'] * ng))
        for i in range(ng // 2):
            t = sh.ref("Л"); xx = 220*G + i * 26*G
            sh.part(N16, (xx, y + 6*G), None, "6Н16Б", {"1": f"PL_{o}{i}a", "7": f"{o}_LV", **n16_bottom("+6.3V", "GND")},
                    unit=1, props=SIM[N16], refs=t)
            sh.part(N16, (xx + 12*G, y + 6*G), None, "6Н16Б", {"5": f"PL_{o}{i}b", "3": f"{o}_LV", "2": "GND"}, unit=2, props=SIM[N16], refs=t)
            sh.part("Device:R", (xx - 5*G, y - 2*G), "R", "10k", {"1": "+150V", "2": f"PL_{o}{i}a"})
            sh.part("Device:R", (xx + 18*G, y - 2*G), "R", "10k", {"1": "+150V", "2": f"PL_{o}{i}b"})
        y += 26*G
    yt = max(y, 12*G + 26*G * len(tb['src'])) + 4*G
    sh.text(".tran 5n %gu" % round(tb['stop'], 3), (20*G, yt), 1.5)
    sh.text(f"{tb['name']} testbench (tools/kicad/gen_latch_j2n16.py, stimulus and .meas from tools/spice/latch_tb.py).\n"
            "STIM_x (HV PWL, ideal) -> divider -> driver triode (Ra 10k) -> divider -> x (LV DUT input): real edges and levels.\n"
            "Each output -> one divider (C1 3.9 pF per grid) -> x_LV -> load tubes, both grids on the net.\n"
            + tb['note'] + "\nThe plain-SPICE run of the same bench: python3 tools/spice/latch_tb.py", (20*G, yt + 3*G))
    sh.text("\n".join("." + l for l in tb['meas']), (20*G, yt + 12*G), 1.0)
    sh.dump(os.path.join(OUT, f"{tb['name']}_tb.kicad_sch"), f"{tb['name']} testbench", root=True,
            comments=["HV +150/+50 V, LV +10/-20 V", tb["note"][:120]], paper="A1")
    open(os.path.join(OUT, f"{tb['name']}_tb.kicad_pro"), "w").write(
        '{\n  "meta": {\n    "filename": "%s_tb.kicad_pro",\n    "version": 3\n  }\n}\n' % tb['name'])

testbench("rs", TB.rslatch_tb(), "RSLATCH_J2N16.kicad_sch", RS_PINS, RS_SIZE)
testbench("dl", TB.dlatch2_tb(), "DLATCH2_J2N16.kicad_sch",
          [("D1", "input", "L", 1), ("D2", "input", "L", 3), ("E", "input", "L", 5), ("H1", "passive", "L", 8),
           ("H2", "passive", "L", 9), ("Q1", "output", "R", 1), ("QN1", "output", "R", 3), ("Q2", "output", "R", 5),
           ("QN2", "output", "R", 7)], (14*G, 11*G))
testbench("df", TB.dff_tb(), "DFF_J2N16.kicad_sch",
          [("D", "input", "L", 1), ("C", "input", "L", 3), ("H1", "passive", "L", 8), ("H2", "passive", "L", 9),
           ("Q", "output", "R", 1), ("QN", "output", "R", 3)], (14*G, 11*G))
print("ok")
