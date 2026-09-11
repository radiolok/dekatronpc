"""
Поведенческая копия DekatronTubeV2.sv (такт-в-такт) для валидации логики
до запуска в Verilator. Семантика скопирована с RTL буквально.
"""

ST_STABLE, ST_GUIDE, ST_WRITE_RESET, ST_INVALID = 0, 1, 2, 3
NAMES = {0: "STABLE", 1: "GUIDE", 2: "WRITE_RESET", 3: "INVALID"}


class Dek:
    def __init__(self, GUIDE_MIN_HS=2, GUIDE_MAX_HS=20, PHASE_WINDOW_HS=10,
                 RETURN_TIMEOUT_HS=5, WRITE_MIN_HS=100, RESET_MIN_HS=100,
                 EN_RESET9=True, INIT_DIGIT=0, INC_BY_A_THEN_B=True):
        self.P = dict(GUIDE_MIN_HS=GUIDE_MIN_HS, GUIDE_MAX_HS=GUIDE_MAX_HS,
                      PHASE_WINDOW_HS=PHASE_WINDOW_HS,
                      RETURN_TIMEOUT_HS=RETURN_TIMEOUT_HS,
                      WRITE_MIN_HS=WRITE_MIN_HS, RESET_MIN_HS=RESET_MIN_HS,
                      EN_RESET9=EN_RESET9, INC_BY_A_THEN_B=INC_BY_A_THEN_B)
        self.state = ST_STABLE
        self.stable_digit = INIT_DIGIT
        self.prev_digit = INIT_DIGIT
        self.target_digit = INIT_DIGIT
        self.guide_dir_inc = False
        self.guide_first_a = False
        self.guide_armed = True
        self.first_released = False
        self.ga_high = 0
        self.gb_high = 0
        self.phase_timer = 0
        self.ret_timer = 0
        self.wr_timer = 0
        self.wr_is_write = False
        self.wr_is_reset0 = False
        self.wr_is_reset9 = False
        self.wr_settled = False
        self.wr_pos_latched = 0
        self.illegal = False
        # input delay regs
        self.ga_q = 0
        self.gb_q = 0
        self.we_q = 0
        self.r0_q = 0
        self.r9_q = 0

    # ---- combinational views of current inputs -----------------------
    def main_onehot(self):
        return (1 << self.stable_digit) if self.state == ST_STABLE else 0

    def digit(self):
        oh = self.main_onehot()
        if oh == 0:
            return None
        return oh.bit_length() - 1

    def invalid(self, ga, gb, we, r0, r9):
        P = self.P
        r9en = P["EN_RESET9"] and r9
        conflict = (we and r0) or (we and r9en) or (r0 and r9en)
        r9bad = (not P["EN_RESET9"]) and r9
        return self.illegal or conflict or (ga and gb) or r9bad

    def on_guide(self, ga, gb):
        return self.state == ST_GUIDE or (self.state == ST_WRITE_RESET and (ga or gb))

    def in_wr(self):
        return self.state == ST_WRITE_RESET

    def settled(self):
        return self.state == ST_WRITE_RESET and self.wr_settled

    # ---- one rising edge of hsClk ------------------------------------
    def tick(self, ga=0, gb=0, we=0, wpos=0, r0=0, r9=0):
        P = self.P
        ga, gb, we, r0, r9 = int(ga), int(gb), int(we), int(r0), int(r9)

        ga_rise = ga and not self.ga_q
        gb_rise = gb and not self.gb_q
        we_rise = we and not self.we_q
        r0_rise = r0 and not self.r0_q
        r9_rise = r9 and not self.r9_q

        r9en = P["EN_RESET9"] and r9
        wr_any = bool(we or r0 or r9en)
        conflict = bool((we and r0) or (we and r9en) or (r0 and r9en))
        r9bad = (not P["EN_RESET9"]) and r9
        both_guides = bool(ga and gb)

        ga_len = self.ga_high + 1
        gb_len = self.gb_high + 1
        ga_min = bool(ga and ga_len >= P["GUIDE_MIN_HS"])
        gb_min = bool(gb and gb_len >= P["GUIDE_MIN_HS"])
        ga_max = bool(ga and ga_len > P["GUIDE_MAX_HS"])
        gb_max = bool(gb and gb_len > P["GUIDE_MAX_HS"])

        onehot = (wpos != 0) and (wpos & (wpos - 1)) == 0

        start_a = (self.state == ST_STABLE and self.guide_armed and
                   ga_min and not gb and not wr_any)
        start_b = (self.state == ST_STABLE and self.guide_armed and
                   gb_min and not ga and not wr_any)

        first_low = (not ga) if self.guide_first_a else (not gb)
        second_ok = gb_min if self.guide_first_a else ga_min

        wpos_changed = (self.state == ST_WRITE_RESET and self.wr_is_write
                        and we and wpos != self.wr_pos_latched)

        # ---- next-state (all assignments computed from current regs) --
        nxt = {}

        def s(k, v):
            nxt[k] = v

        # input regs / counters
        s("ga_q", ga); s("gb_q", gb); s("we_q", we); s("r0_q", r0); s("r9_q", r9)
        s("ga_high", self.ga_high + 1 if ga else 0)
        s("gb_high", self.gb_high + 1 if gb else 0)

        st = self.state
        if st == ST_STABLE:
            s("illegal", False)
            if not ga and not gb:
                s("guide_armed", True)

            if conflict or r9bad:
                s("state", ST_INVALID); s("illegal", True)
                s("prev_digit", self.stable_digit)
            elif we_rise:
                if not onehot:
                    s("state", ST_INVALID); s("illegal", True)
                    s("prev_digit", self.stable_digit)
                else:
                    s("state", ST_WRITE_RESET)
                    s("prev_digit", self.stable_digit)
                    s("target_digit", wpos.bit_length() - 1)
                    s("wr_pos_latched", wpos)
                    s("wr_is_write", True); s("wr_is_reset0", False)
                    s("wr_is_reset9", False)
                    s("wr_timer", 1); s("wr_settled", False)
            elif r0_rise:
                s("state", ST_WRITE_RESET); s("prev_digit", self.stable_digit)
                s("target_digit", 0)
                s("wr_is_write", False); s("wr_is_reset0", True)
                s("wr_is_reset9", False)
                s("wr_timer", 1); s("wr_settled", False)
            elif r9_rise and P["EN_RESET9"]:
                s("state", ST_WRITE_RESET); s("prev_digit", self.stable_digit)
                s("target_digit", 9)
                s("wr_is_write", False); s("wr_is_reset0", False)
                s("wr_is_reset9", True)
                s("wr_timer", 1); s("wr_settled", False)
            elif start_a:
                s("state", ST_GUIDE); s("prev_digit", self.stable_digit)
                inc = P["INC_BY_A_THEN_B"]
                s("target_digit", (self.stable_digit + 1) % 10 if inc
                  else (self.stable_digit - 1) % 10)
                s("guide_dir_inc", inc); s("guide_first_a", True)
                s("guide_armed", False); s("first_released", False)
                s("phase_timer", 0); s("ret_timer", 0)
            elif start_b:
                s("state", ST_GUIDE); s("prev_digit", self.stable_digit)
                inc = not P["INC_BY_A_THEN_B"]
                s("target_digit", (self.stable_digit + 1) % 10 if inc
                  else (self.stable_digit - 1) % 10)
                s("guide_dir_inc", inc); s("guide_first_a", False)
                s("guide_armed", False); s("first_released", False)
                s("phase_timer", 0); s("ret_timer", 0)

        elif st == ST_GUIDE:
            s("phase_timer", self.phase_timer + 1)
            if self.first_released:
                s("ret_timer", self.ret_timer + 1)
            elif first_low:
                s("first_released", True)

            if conflict or r9bad:
                s("state", ST_INVALID); s("illegal", True)
            elif we_rise or r0_rise or (r9_rise and P["EN_RESET9"]):
                if we_rise and not onehot:
                    s("state", ST_INVALID); s("illegal", True)
                else:
                    s("state", ST_WRITE_RESET)
                    s("wr_timer", 1); s("wr_settled", False)
                    if we_rise:
                        s("target_digit", wpos.bit_length() - 1)
                        s("wr_pos_latched", wpos)
                        s("wr_is_write", True); s("wr_is_reset0", False)
                        s("wr_is_reset9", False)
                    elif r0_rise:
                        s("target_digit", 0)
                        s("wr_is_write", False); s("wr_is_reset0", True)
                        s("wr_is_reset9", False)
                    else:
                        s("target_digit", 9)
                        s("wr_is_write", False); s("wr_is_reset0", False)
                        s("wr_is_reset9", True)
            elif both_guides:
                s("illegal", True)
            elif second_ok:
                s("state", ST_STABLE); s("stable_digit", self.target_digit)
                s("phase_timer", 0); s("ret_timer", 0)
                s("first_released", False)
            elif (self.phase_timer >= P["PHASE_WINDOW_HS"] or
                  (self.first_released and self.ret_timer >= P["RETURN_TIMEOUT_HS"])):
                s("state", ST_STABLE); s("stable_digit", self.prev_digit)
                s("phase_timer", 0); s("ret_timer", 0)
                s("first_released", False)

        elif st == ST_WRITE_RESET:
            if conflict or r9bad:
                s("illegal", True)
            if ga or gb:
                s("illegal", True)

            if not wr_any:
                s("state", ST_STABLE)
                s("stable_digit", self.target_digit if self.wr_settled
                  else self.prev_digit)
                s("wr_timer", 0); s("wr_settled", False)
                s("wr_is_write", False); s("wr_is_reset0", False)
                s("wr_is_reset9", False)
            elif not self.wr_settled:
                s("wr_timer", self.wr_timer + 1)
                if self.wr_is_write and (self.wr_timer + 1) >= P["WRITE_MIN_HS"]:
                    s("wr_settled", True); s("stable_digit", self.target_digit)
                elif ((self.wr_is_reset0 or self.wr_is_reset9) and
                      (self.wr_timer + 1) >= P["RESET_MIN_HS"]):
                    s("wr_settled", True); s("stable_digit", self.target_digit)

        elif st == ST_INVALID:
            if not wr_any and not ga and not gb:
                s("state", ST_STABLE); s("stable_digit", self.prev_digit)
                s("illegal", False); s("guide_armed", True)
                s("wr_timer", 0); s("wr_settled", False)
                s("wr_is_write", False); s("wr_is_reset0", False)
                s("wr_is_reset9", False)

        # global violation overrides
        if ga_max or gb_max:
            s("illegal", True)
        if wpos_changed:
            s("illegal", True)

        for k, v in nxt.items():
            setattr(self, k, v)
