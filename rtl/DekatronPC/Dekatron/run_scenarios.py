from dek_model import Dek, NAMES

fails = []


def chk(cond, msg):
    if not cond:
        fails.append(msg)
        print("  FAIL:", msg)
    else:
        print("  ok  :", msg)


class Drv:
    """Драйвер, повторяющий задачи тестбенча."""

    def __init__(self, d):
        self.d = d
        self.ga = self.gb = self.we = self.r0 = self.r9 = 0
        self.wpos = 0
        self.saw_invalid = False
        self.main_nonzero_during_wr = False

    def t(self, n=1):
        for _ in range(n):
            if self.d.in_wr() and self.d.main_onehot() != 0:
                self.main_nonzero_during_wr = True
            self.d.tick(self.ga, self.gb, self.we, self.wpos, self.r0, self.r9)
            if self.d.invalid(self.ga, self.gb, self.we, self.r0, self.r9):
                self.saw_invalid = True

    def idle(self, n=20):
        self.ga = self.gb = self.we = self.r0 = self.r9 = 0
        self.wpos = 0
        self.t(n)

    def pulse_a(self, dur):
        self.ga = 1; self.t(dur); self.ga = 0

    def pulse_b(self, dur):
        self.gb = 1; self.t(dur); self.gb = 0

    def step(self, inc, dur=None, gap=0, hold=False):
        P = self.d.P
        dur = dur if dur is not None else P["GUIDE_MIN_HS"]
        a_first = (inc == P["INC_BY_A_THEN_B"])
        if a_first:
            self.pulse_a(dur)
            if gap: self.t(gap)
            self.gb = 1; self.t(dur)
            if not hold: self.gb = 0
        else:
            self.pulse_b(dur)
            if gap: self.t(gap)
            self.ga = 1; self.t(dur)
            if not hold: self.ga = 0
        self.t(2)

    def write(self, digit, dur=None, wpos=None):
        P = self.d.P
        dur = dur if dur is not None else P["WRITE_MIN_HS"]
        self.wpos = wpos if wpos is not None else (1 << digit)
        self.we = 1; self.t(dur); self.we = 0
        self.t(3)
        self.wpos = 0

    def reset0(self, dur=None):
        dur = dur if dur is not None else self.d.P["RESET_MIN_HS"]
        self.r0 = 1; self.t(dur); self.r0 = 0; self.t(3)

    def reset9(self, dur=None):
        dur = dur if dur is not None else self.d.P["RESET_MIN_HS"]
        self.r9 = 1; self.t(dur); self.r9 = 0; self.t(3)

    def set_digit(self, d):
        self.write(d)


def new(**kw):
    d = Dek(**kw)
    return d, Drv(d)


print("=== UT-STABLE ===")
d, v = new()
chk(v.d.digit() == 0, "UT-STABLE-001 init digit = INIT_DIGIT")
v.idle(50)
chk(v.d.digit() == 0, "UT-STABLE-002 no stimulus -> unchanged")
chk(v.d.on_guide(0, 0) is False, "UT-STABLE-004 on_guide=0")
chk(v.d.in_wr() is False, "UT-STABLE-005 in_write_reset=0")
ok = True
for i in range(10):
    v.write(i)
    if v.d.digit() != i:
        ok = False
chk(ok, "UT-STABLE-003 write all digits 0..9")

print("=== UT-INC ===")
d, v = new()
v.set_digit(0); v.step(inc=True)
chk(v.d.digit() == 1, "UT-INC-001 0 -> 1")
v.set_digit(8); v.step(inc=True)
chk(v.d.digit() == 9, "UT-INC-002 8 -> 9")
v.set_digit(9); v.step(inc=True)
chk(v.d.digit() == 0, "UT-INC-003 9 -> 0 wrap")

d, v = new()
v.set_digit(3)
v.pulse_a(d.P["GUIDE_MIN_HS"] - 1); v.pulse_b(d.P["GUIDE_MIN_HS"]); v.idle(30)
chk(v.d.digit() == 3, "UT-INC-004 short first pulse -> no step")

d, v = new()
v.set_digit(3); v.pulse_a(d.P["GUIDE_MIN_HS"] + 1); v.idle(40)
chk(v.d.digit() == 3, "UT-INC-005 no second pulse -> return to prev")

d, v = new()
v.set_digit(3); v.pulse_a(d.P["GUIDE_MIN_HS"])
v.pulse_b(d.P["GUIDE_MIN_HS"] - 1); v.idle(40)
chk(v.d.digit() == 3, "UT-INC-006 short second pulse -> return")

d, v = new()
v.set_digit(3); v.pulse_a(d.P["GUIDE_MIN_HS"]); v.t(25)
v.pulse_b(d.P["GUIDE_MIN_HS"]); v.idle(40)
chk(v.d.digit() == 3, "UT-INC-007 second pulse outside window -> net unchanged")

d, v = new()
v.set_digit(3); v.saw_invalid = False
v.pulse_a(d.P["GUIDE_MAX_HS"] + 3); v.idle(40)
chk(v.saw_invalid, "UT-INC-008 first pulse > GUIDE_MAX -> invalid flagged")

d, v = new()
v.set_digit(3); v.step(inc=True, hold=True)
after = v.d.digit()
v.t(60)
chk(after == 4 and v.d.digit() == 4, "UT-INC-009 held guide -> exactly one step")
v.gb = 0; v.idle(20)
chk(v.d.digit() == 4, "UT-INC-009b release after hold -> still one step")

d, v = new()
v.set_digit(0); seq_ok = True
for i in range(10):
    v.step(inc=True)
    if v.d.digit() != (i + 1) % 10:
        seq_ok = False
chk(seq_ok and v.d.digit() == 0, "UT-INC-010 ten increments cycle 0->9->0")

print("=== UT-DEC ===")
d, v = new()
v.set_digit(1); v.step(inc=False)
chk(v.d.digit() == 0, "UT-DEC-001 1 -> 0")
v.set_digit(0); v.step(inc=False)
chk(v.d.digit() == 9, "UT-DEC-002 0 -> 9 wrap")
d, v = new()
v.set_digit(5); v.pulse_b(d.P["GUIDE_MIN_HS"] - 1); v.idle(30)
chk(v.d.digit() == 5, "UT-DEC-003 short first -> no step")
d, v = new()
v.set_digit(5); v.pulse_b(d.P["GUIDE_MIN_HS"]); v.idle(40)
chk(v.d.digit() == 5, "UT-DEC-004 no second -> return")
d, v = new()
v.set_digit(0); ok = True
for i in range(10):
    v.step(inc=False)
    if v.d.digit() != (10 - i - 1) % 10:
        ok = False
chk(ok and v.d.digit() == 0, "UT-DEC-007 ten decrements cycle")

print("=== UT-DIR (INC_BY_A_THEN_B=0) ===")
d, v = new(INC_BY_A_THEN_B=False)
v.set_digit(4); v.pulse_a(2); v.pulse_b(2); v.t(3)
chk(v.d.digit() == 3, "UT-DIR-003 IABTB=0, A->B = decrement")
v.set_digit(4); v.pulse_b(2); v.pulse_a(2); v.t(3)
chk(v.d.digit() == 5, "UT-DIR-004 IABTB=0, B->A = increment")

print("=== UT-WR ===")
d, v = new()
for tgt in (0, 5, 9):
    v.set_digit(3); v.write(tgt)
    chk(v.d.digit() == tgt, f"UT-WR-00x write digit {tgt} at exactly WRITE_MIN_HS")
d, v = new()
v.set_digit(3); v.write(7, dur=d.P["WRITE_MIN_HS"] - 1)
chk(v.d.digit() == 3, "UT-WR-004 short write -> no change")
d, v = new()
v.set_digit(3); v.write(6, dur=2 * d.P["WRITE_MIN_HS"])
chk(v.d.digit() == 6, "UT-WR-005 long write -> single write")
d, v = new()
v.set_digit(3); v.saw_invalid = False
v.write(0, wpos=0b0000000011)
chk(v.d.digit() == 3 and v.saw_invalid,
    "UT-WR-006 non-onehot write_pos -> invalid, no write")
d, v = new()
v.set_digit(3); v.saw_invalid = False
v.wpos = 1 << 4; v.we = 1; v.t(10); v.wpos = 1 << 7
v.t(d.P["WRITE_MIN_HS"]); v.we = 0; v.t(3); v.wpos = 0
chk(v.saw_invalid, "UT-WR-007 write_pos changed mid-pulse -> invalid flagged")
d, v = new()
v.set_digit(3); v.pulse_a(2); v.t(1); v.write(2)
chk(v.d.digit() == 2, "UT-WR-008 write during ST_GUIDE -> target set")
d, v = new()
v.set_digit(3); v.saw_invalid = False; v.main_nonzero_during_wr = False
v.wpos = 1 << 5; v.we = 1; v.t(5); v.ga = 1; v.t(4); v.ga = 0
v.t(d.P["WRITE_MIN_HS"]); v.we = 0; v.t(3); v.wpos = 0
chk(v.saw_invalid, "UT-WR-009 guide during write -> invalid flagged")
chk(v.d.digit() == 5, "UT-WR-010/ISO-001 write completes to target despite guides")
chk(not v.main_nonzero_during_wr, "UT-ISO-004 main_onehot invalid during write")

print("=== UT-RST0 ===")
d, v = new()
v.set_digit(5); v.reset0()
chk(v.d.digit() == 0, "UT-RST0-001 reset0 from 5 -> 0")
v.set_digit(0); v.reset0()
chk(v.d.digit() == 0, "UT-RST0-002 reset0 from 0 -> 0")
d, v = new()
v.set_digit(5); v.pulse_a(2); v.t(1); v.reset0()
chk(v.d.digit() == 0, "UT-RST0-003 reset0 from ST_GUIDE -> 0")
d, v = new()
v.set_digit(5); v.reset0(dur=d.P["RESET_MIN_HS"] - 1)
chk(v.d.digit() == 5, "UT-RST0-004 short reset0 -> unchanged")
d, v = new()
v.set_digit(5); v.reset0(dur=2 * d.P["RESET_MIN_HS"])
chk(v.d.digit() == 0, "UT-RST0-005 long reset0 -> single reset")
d, v = new()
v.set_digit(5); v.saw_invalid = False
v.r0 = 1; v.we = 1; v.wpos = 1 << 2; v.t(20); v.r0 = 0; v.we = 0; v.wpos = 0; v.idle(20)
chk(v.saw_invalid and v.d.digit() == 5,
    "UT-RST0-007 reset0+write conflict -> invalid, no change")

print("=== UT-RST9 ===")
d, v = new(EN_RESET9=True)
v.set_digit(0); v.reset9()
chk(v.d.digit() == 9, "UT-RST9-001 reset9 from 0 -> 9")
v.set_digit(9); v.reset9()
chk(v.d.digit() == 9, "UT-RST9-002 reset9 from 9 -> 9")
d, v = new(EN_RESET9=True)
v.set_digit(3); v.pulse_a(2); v.t(1); v.reset9()
chk(v.d.digit() == 9, "UT-RST9-003 reset9 from ST_GUIDE -> 9")
d, v = new(EN_RESET9=True)
v.set_digit(3); v.reset9(dur=d.P["RESET_MIN_HS"] - 1)
chk(v.d.digit() == 3, "UT-RST9-004 short reset9 -> unchanged")
d, v = new(EN_RESET9=False)
v.set_digit(3); v.saw_invalid = False
v.reset9(dur=d.P["RESET_MIN_HS"])
chk(v.saw_invalid and v.d.digit() == 3,
    "UT-RST9-005 EN_RESET9=0 -> invalid, no operation")
d, v = new(EN_RESET9=True)
v.set_digit(4); v.saw_invalid = False
v.r0 = 1; v.r9 = 1; v.t(20); v.r0 = 0; v.r9 = 0; v.idle(20)
chk(v.saw_invalid and v.d.digit() == 4, "UT-RST9-006 reset0+reset9 -> invalid")

print("=== UT-ISO ===")
d, v = new()
v.set_digit(5); v.main_nonzero_during_wr = False
v.r0 = 1; v.t(5); v.ga = 1; v.t(3); v.ga = 0
v.t(d.P["RESET_MIN_HS"]); v.r0 = 0; v.t(3)
chk(v.d.digit() == 0 and not v.main_nonzero_during_wr,
    "UT-ISO-002 reset0 with guides -> 0, no leak to cathode 1")

print("=== UT-GUIDE ===")
d, v = new()
v.set_digit(3); v.saw_invalid = False
v.ga = 1; v.gb = 1; v.t(10); v.ga = 0; v.gb = 0; v.idle(20)
chk(v.saw_invalid and v.d.digit() == 3,
    "UT-GUIDE-001 both guides in stable -> invalid, no move")
d, v = new()
v.set_digit(3); v.pulse_a(2); v.saw_invalid = False
v.ga = 1; v.gb = 1; v.t(4); v.ga = 0; v.gb = 0; v.idle(30)
chk(v.saw_invalid and v.d.digit() == 3,
    "UT-GUIDE-002 both guides in ST_GUIDE -> invalid, return to prev")
d, v = new()
v.set_digit(3)
for _ in range(6):
    v.pulse_a(1); v.t(1)
v.idle(30)
chk(v.d.digit() == 3, "UT-GUIDE-005 guide debounce -> no qualified step")

print("=== UT-PERF ===")
d, v = new()
v.set_digit(0); ok = True
for i in range(10):
    v.step(inc=True); v.t(4)          # шаг + пауза, укладывается в 10 hsClk
    if v.d.digit() != (i + 1) % 10:
        ok = False
chk(ok, "UT-PERF-001 back-to-back increments")
d, v = new()
ok = True
for i in range(10):
    v.write(i)
    if v.d.digit() != i:
        ok = False
chk(ok, "UT-PERF-003 ten writes back-to-back")
d, v = new()
v.write(4); v.step(inc=True)
chk(v.d.digit() == 5, "UT-PERF-004 write then immediate increment")
d, v = new()
v.reset0(); v.step(inc=False)
chk(v.d.digit() == 9, "UT-PERF-005 reset then immediate decrement")

print("=== параметрический прогон (UT-REQ-008) ===")
d, v = new(GUIDE_MIN_HS=3, GUIDE_MAX_HS=30, PHASE_WINDOW_HS=14,
           RETURN_TIMEOUT_HS=8, WRITE_MIN_HS=20, RESET_MIN_HS=20)
v.set_digit(7); v.step(inc=True)
chk(v.d.digit() == 8, "params: increment with GUIDE_MIN=3, WRITE_MIN=20")
v.write(2, dur=20)
chk(v.d.digit() == 2, "params: write exactly WRITE_MIN_HS=20")
v.write(5, dur=19)
chk(v.d.digit() == 2, "params: write WRITE_MIN-1 -> no change")

print()
print("=" * 60)
if fails:
    print(f"ИТОГО: {len(fails)} FAIL")
    for f in fails:
        print("  -", f)
else:
    print("ИТОГО: все сценарии прошли")
