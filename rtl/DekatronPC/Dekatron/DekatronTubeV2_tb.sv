//======================================================================
// DekatronTubeV2_tb — тестбенч кольцевой модели декатрона
//----------------------------------------------------------------------
// Покрывает тестовый план Dekatron_Model_TRS_v0_1.md §14 с поправками
// на кольцевую модель.
//
// Запуск:
//   Verilator:
//     verilator --binary --assert --timing -Wno-fatal \
//       DekatronTubeV2.sv DekatronTubeV2_assertions.sv DekatronTubeV2_tb.sv \
//       --top-module DekatronTubeV2_tb
//     ./obj_dir/VDekatronTubeV2_tb
//
//   Icarus:
//     iverilog -g2012 -o dek_tb DekatronTubeV2.sv \
//       DekatronTubeV2_assertions.sv DekatronTubeV2_tb.sv && vvp dek_tb
//
// ВАЖНО: часть тестов — негативные (UT-GUIDE-001, UT-WR-006/009,
// UT-RST0-006/007, UT-RSTN-005). В них СПЕЦИАЛЬНО подаются недопустимые
// комбинации входов, поэтому сообщения assertions в этих секциях
// ОЖИДАЕМЫ. Признак провала — только счётчик ошибок в итоговом отчёте.
//
// ОСОБЕННОСТЬ КОЛЬЦЕВОЙ МОДЕЛИ: пока подкатодная линия удерживается,
// разряд физически остаётся на подкатоде и main_onehot_o невалиден.
// Значение цифры проверяется ТОЛЬКО после снятия обеих линий и
// завершения падения на главный катод (FALL_STEP_HS).
//======================================================================

`default_nettype none
`timescale 1ns/1ps

module DekatronTubeV2_tb_core #(
    parameter unsigned GUIDE_STEP_HS = 2,
    parameter unsigned FALL_STEP_HS  = 3,
    parameter unsigned GUIDE_MAX_HS  = 20,
    parameter unsigned WRITE_MIN_HS  = 100,
    parameter unsigned RESET_MIN_HS  = 100,
    parameter bit          EN_RESETN     = 1'b1,
    parameter unsigned RESET_N_POS   = 9,
    parameter logic [3:0]  INIT_DIGIT    = 4'd0,
    parameter bit          INC_BY_A_THEN_B = 1'b1,
    parameter unsigned SUITE         = 0,  // 0=FULL 1=DIR 2=NO_RSTN 3=RSTN5
    parameter string       NAME          = "FULL"
)(
    output int err_count,
    output bit done
);

    localparam int HSCLK_PERIOD_NS = 100;   // 10 MHz
    localparam int SETTLE = FALL_STEP_HS + 4;

    logic hsClk;

    logic        guide_a, guide_b;
    logic        write_en;
    logic [9:0]  write_pos;
    logic        reset0, resetN;
    logic        sim_preset_en;
    logic [29:0] sim_preset_cathodes;

    logic [9:0]  main_onehot;
    logic [29:0] cathodes_dbg;
    logic        on_guide_dbg, moving_dbg;
    logic        in_write_reset_dbg, settled_dbg, invalid_dbg;

    DekatronTubeV2 #(
        .HS_PER_CLK       (10),
        .GUIDE_STEP_HS    (GUIDE_STEP_HS),
        .FALL_STEP_HS     (FALL_STEP_HS),
        .GUIDE_MAX_HS     (GUIDE_MAX_HS),
        .WRITE_MIN_HS     (WRITE_MIN_HS),
        .WRITE_MAX_HS     (200),
        .RESET_MIN_HS     (RESET_MIN_HS),
        .RESET_MAX_HS     (200),
        .EN_RESETN        (EN_RESETN),
        .RESET_N_POS      (RESET_N_POS),
        .INIT_DIGIT       (INIT_DIGIT),
        .INC_BY_A_THEN_B  (INC_BY_A_THEN_B),
        .EN_SIM_PRESET    (1'b1),
        .EN_ASSERTIONS    (1'b1),
        .EN_DEBUG_OUTPUTS (1'b1)
    ) dut (
        .hsClk                 (hsClk),
        .guide_a_i             (guide_a),
        .guide_b_i             (guide_b),
        .write_en_i            (write_en),
        .write_pos_i           (write_pos),
        .reset0_i              (reset0),
        .resetN_i              (resetN),
        .sim_preset_en_i       (sim_preset_en),
        .sim_preset_cathodes_i (sim_preset_cathodes),
        .main_onehot_o         (main_onehot),
        .cathodes_dbg_o        (cathodes_dbg),
        .on_guide_dbg_o        (on_guide_dbg),
        .moving_dbg_o          (moving_dbg),
        .in_write_reset_dbg_o  (in_write_reset_dbg),
        .settled_dbg_o         (settled_dbg),
        .invalid_dbg_o         (invalid_dbg)
    );

    initial begin
        hsClk = 0;
        forever #(HSCLK_PERIOD_NS/2) hsClk = ~hsClk;
    end

    //------------------------------------------------------------------
    // Мониторы
    //------------------------------------------------------------------
    bit saw_invalid, saw_settled, main_leaked, ring_broken, mon_arm;

    always @(posedge hsClk) begin
        if (mon_arm) begin
            if (invalid_dbg)                              saw_invalid <= 1'b1;
            if (settled_dbg)                              saw_settled <= 1'b1;
            if (in_write_reset_dbg && (main_onehot != 0)) main_leaked <= 1'b1;
            if ($countones(cathodes_dbg) != 1)            ring_broken <= 1'b1;
        end
    end

    task automatic mon_reset();
        saw_invalid = 0; saw_settled = 0; main_leaked = 0;
        ring_broken = 0; mon_arm = 1;
    endtask

    //------------------------------------------------------------------
    // Учёт результатов
    //------------------------------------------------------------------
    int errors, checks;

    function automatic int oh2digit(input logic [9:0] oh);
        oh2digit = -1;
        for (int i = 0; i < 10; i++)
            if (oh == (10'b1 << i)) oh2digit = i;
    endfunction

    task automatic chk(input bit cond, input string id);
        checks++;
        if (!cond) begin
            errors++;
            $display("  [%0s] FAIL: %0s (t=%0t)", NAME, id, $time);
        end else
            $display("  [%0s] ok  : %0s", NAME, id);
    endtask

    task automatic chk_digit(input int expected, input string id);
        int d;
        d = oh2digit(main_onehot);
        checks++;
        if (d != expected) begin
            errors++;
            $display("  [%0s] FAIL: %0s (ожидалось %0d, получено %0d, ring=%b, t=%0t)",
                     NAME, id, expected, d, cathodes_dbg, $time);
        end else
            $display("  [%0s] ok  : %0s (цифра=%0d)", NAME, id, d);
    endtask

    //------------------------------------------------------------------
    // Драйвер
    //------------------------------------------------------------------
    task automatic wait_hs(input int n);
        repeat (n) @(posedge hsClk);
    endtask

    task automatic idle_all(input int n = 20);
        @(negedge hsClk);
        guide_a = 0; guide_b = 0; write_en = 0; write_pos = '0;
        reset0 = 0; resetN = 0; sim_preset_en = 0;
        wait_hs(n);
    endtask

    task automatic pulse_guide_a(input int duration_hs);
        @(negedge hsClk); guide_a = 1;
        wait_hs(duration_hs);
        @(negedge hsClk); guide_a = 0;
    endtask

    task automatic pulse_guide_b(input int duration_hs);
        @(negedge hsClk); guide_b = 1;
        wait_hs(duration_hs);
        @(negedge hsClk); guide_b = 0;
    endtask

    task automatic do_write(input logic [9:0] pos, input int duration_hs);
        @(negedge hsClk); write_pos = pos; write_en = 1;
        wait_hs(duration_hs);
        @(negedge hsClk); write_en = 0;
        wait_hs(3);
        @(negedge hsClk); write_pos = '0;
        wait_hs(SETTLE);
    endtask

    task automatic do_reset0(input int duration_hs);
        @(negedge hsClk); reset0 = 1;
        wait_hs(duration_hs);
        @(negedge hsClk); reset0 = 0;
        wait_hs(SETTLE);
    endtask

    task automatic do_resetN(input int duration_hs);
        @(negedge hsClk); resetN = 1;
        wait_hs(duration_hs);
        @(negedge hsClk); resetN = 0;
        wait_hs(SETTLE);
    endtask

    task automatic set_digit(input int d);
        do_write(10'b1 << d, WRITE_MIN_HS);
    endtask

    // Один счётный шаг: две фазы подкатодов, затем падение на катод.
    // hold=1 — вторая линия остаётся поднятой (разряд стоит на подкатоде).
    task automatic do_step(input bit inc,
                           input int dur  = 0,
                           input int gap  = 0,
                           input bit hold = 0);
        int  d;
        bit  a_first;
        d       = (dur == 0) ? GUIDE_STEP_HS : dur;
        a_first = inc;   // порядок ролей задаётся параметром внутри DUT

        if (a_first) begin
            pulse_guide_a(d);
            if (gap > 0) wait_hs(gap);
            @(negedge hsClk); guide_b = 1;
            wait_hs(d);
            if (!hold) begin
                @(negedge hsClk); guide_b = 0;
                wait_hs(SETTLE);
            end
        end
        else begin
            pulse_guide_b(d);
            if (gap > 0) wait_hs(gap);
            @(negedge hsClk); guide_a = 1;
            wait_hs(d);
            if (!hold) begin
                @(negedge hsClk); guide_a = 0;
                wait_hs(SETTLE);
            end
        end
    endtask

    task automatic banner(input string s);
        $display("[%0s] --- %0s ---", NAME, s);
    endtask

    task automatic neg_banner(input string s);
        $display("[%0s] --- %0s (ОЖИДАЮТСЯ СООБЩЕНИЯ ASSERTIONS) ---", NAME, s);
    endtask

    //==================================================================
    // Наборы тестов
    //==================================================================

    task automatic suite_stable();
        banner("UT-STABLE: стабильное состояние");
        mon_reset(); wait_hs(5);
        chk_digit(int'(INIT_DIGIT), "UT-STABLE-001 начальная позиция");
        idle_all(50);
        chk_digit(int'(INIT_DIGIT), "UT-STABLE-002 без воздействий не меняется");
        chk(on_guide_dbg == 0, "UT-STABLE-004 on_guide_dbg_o == 0 на главном катоде");
        chk(in_write_reset_dbg == 0, "UT-STABLE-005 in_write_reset_dbg_o == 0");
        chk(moving_dbg == 0, "UT-STABLE-002 moving_dbg_o == 0 в покое");
        begin
            bit ok; ok = 1;
            for (int i = 0; i < 10; i++) begin
                set_digit(i);
                if (oh2digit(main_onehot) != i) ok = 0;
            end
            chk(ok, "UT-STABLE-003 запись всех позиций 0..9");
        end
    endtask

    task automatic suite_inc();
        banner("UT-INC: инкремент");

        set_digit(0); do_step(.inc(1)); chk_digit(1, "UT-INC-001 0 -> 1");
        set_digit(8); do_step(.inc(1)); chk_digit(9, "UT-INC-002 8 -> 9");
        set_digit(9); do_step(.inc(1)); chk_digit(0, "UT-INC-003 9 -> 0 перенос");

        set_digit(3);
        pulse_guide_a(GUIDE_STEP_HS-1); pulse_guide_b(GUIDE_STEP_HS);
        idle_all(SETTLE+10);
        chk_digit(3, "UT-INC-004 короткая первая фаза -> шага нет");

        set_digit(3);
        pulse_guide_a(GUIDE_STEP_HS); idle_all(SETTLE+10);
        chk_digit(3, "UT-INC-005 нет второй фазы -> падение назад на исходный катод");

        set_digit(3);
        pulse_guide_a(GUIDE_STEP_HS); pulse_guide_b(GUIDE_STEP_HS-1);
        idle_all(SETTLE+10);
        chk_digit(3, "UT-INC-006 короткая вторая фаза -> возврат");

        set_digit(3);
        pulse_guide_a(GUIDE_STEP_HS);
        wait_hs(FALL_STEP_HS + 6);
        pulse_guide_b(GUIDE_STEP_HS);
        idle_all(SETTLE+10);
        chk_digit(3, "UT-INC-007 вторая фаза поздно -> разряд уже свалился, шага нет");

        neg_banner("UT-INC-008 подкатодный импульс длиннее GUIDE_MAX_HS");
        set_digit(3); mon_reset();
        pulse_guide_a(GUIDE_MAX_HS+3); idle_all(SETTLE+10);
        chk(saw_invalid, "UT-INC-008 длинный импульс -> invalid_dbg_o == 1");

        // Удержание второй фазы: разряд остаётся на подкатоде
        set_digit(3);
        do_step(.inc(1), .hold(1));
        chk(main_onehot == 10'b0,
            "UT-INC-009 при удержании подкатода main_onehot_o невалиден");
        chk(on_guide_dbg == 1'b1, "UT-INC-009 on_guide_dbg_o == 1 на подкатоде");
        wait_hs(50);
        chk(main_onehot == 10'b0, "UT-INC-009 удержание не даёт самопроизвольного шага");
        idle_all(SETTLE+10);
        chk_digit(4, "UT-INC-009 после снятия линии -> ровно один шаг");
        wait_hs(60);
        chk_digit(4, "UT-INC-009 повторного шага нет");

        begin
            bit ok; ok = 1;
            set_digit(0);
            for (int i = 0; i < 10; i++) begin
                do_step(.inc(1));
                if (oh2digit(main_onehot) != (i+1) % 10) ok = 0;
            end
            chk(ok && (oh2digit(main_onehot) == 0),
                "UT-INC-010 десять инкрементов, цикл 0->9->0");
        end
    endtask

    task automatic suite_dec();
        banner("UT-DEC: декремент");

        set_digit(1); do_step(.inc(0)); chk_digit(0, "UT-DEC-001 1 -> 0");
        set_digit(0); do_step(.inc(0)); chk_digit(9, "UT-DEC-002 0 -> 9 перенос");

        set_digit(5);
        pulse_guide_b(GUIDE_STEP_HS-1); idle_all(SETTLE+10);
        chk_digit(5, "UT-DEC-003 короткая первая фаза -> шага нет");

        set_digit(5);
        pulse_guide_b(GUIDE_STEP_HS); idle_all(SETTLE+10);
        chk_digit(5, "UT-DEC-004 нет второй фазы -> падение вперёд на исходный катод");

        set_digit(5);
        pulse_guide_b(GUIDE_STEP_HS);
        wait_hs(FALL_STEP_HS + 6);
        pulse_guide_a(GUIDE_STEP_HS);
        idle_all(SETTLE+10);
        chk_digit(5, "UT-DEC-005 вторая фаза поздно -> шага нет");

        set_digit(5); do_step(.inc(0), .hold(1));
        chk(main_onehot == 10'b0, "UT-DEC-006 удержание -> разряд на подкатоде");
        idle_all(SETTLE+10);
        chk_digit(4, "UT-DEC-006 после снятия -> ровно один шаг");

        begin
            bit ok; ok = 1;
            set_digit(0);
            for (int i = 0; i < 10; i++) begin
                do_step(.inc(0));
                if (oh2digit(main_onehot) != (9 - i) % 10) ok = 0;
            end
            chk(ok && (oh2digit(main_onehot) == 0),
                "UT-DEC-007 десять декрементов, цикл 0->9->0");
        end
    endtask

    task automatic suite_direction();
        banner("UT-DIR: направление счёта по параметру INC_BY_A_THEN_B");

        set_digit(4);
        pulse_guide_a(GUIDE_STEP_HS); pulse_guide_b(GUIDE_STEP_HS);
        idle_all(SETTLE+5);
        if (INC_BY_A_THEN_B)
            chk_digit(5, "UT-DIR-001 INC_BY_A_THEN_B=1: A->B = инкремент");
        else
            chk_digit(3, "UT-DIR-003 INC_BY_A_THEN_B=0: A->B = декремент");

        set_digit(4);
        pulse_guide_b(GUIDE_STEP_HS); pulse_guide_a(GUIDE_STEP_HS);
        idle_all(SETTLE+5);
        if (INC_BY_A_THEN_B)
            chk_digit(3, "UT-DIR-002 INC_BY_A_THEN_B=1: B->A = декремент");
        else
            chk_digit(5, "UT-DIR-004 INC_BY_A_THEN_B=0: B->A = инкремент");
    endtask

    task automatic suite_guide_conflicts();
        neg_banner("UT-GUIDE: конфликты подкатодных линий");

        set_digit(3); mon_reset();
        @(negedge hsClk); guide_a = 1; guide_b = 1;
        wait_hs(10);
        @(negedge hsClk); guide_a = 0; guide_b = 0;
        idle_all(SETTLE+10);
        chk(saw_invalid, "UT-GUIDE-001 обе линии -> invalid_dbg_o == 1");
        chk_digit(3, "UT-GUIDE-001 разряд не перемещается");

        set_digit(3);
        pulse_guide_a(GUIDE_STEP_HS);
        mon_reset();
        @(negedge hsClk); guide_a = 1; guide_b = 1;
        wait_hs(4);
        @(negedge hsClk); guide_a = 0; guide_b = 0;
        idle_all(SETTLE+10);
        chk(saw_invalid, "UT-GUIDE-002 обе линии на подкатоде -> invalid_dbg_o == 1");
        chk_digit(3, "UT-GUIDE-002 некорректного перехода на главный катод нет");

        set_digit(3);
        for (int i = 0; i < 6; i++) begin
            pulse_guide_a(1);
            wait_hs(1);
        end
        idle_all(SETTLE+10);
        chk_digit(3, "UT-GUIDE-005 дребезг -> квалифицированного шага нет");
    endtask

    task automatic suite_write();
        banner("UT-WR: запись");

        set_digit(3); do_write(10'b1 << 0, WRITE_MIN_HS);
        chk_digit(0, "UT-WR-001 запись позиции 0 (ровно WRITE_MIN_HS)");
        set_digit(3); do_write(10'b1 << 5, WRITE_MIN_HS);
        chk_digit(5, "UT-WR-002 запись позиции 5");
        set_digit(3); do_write(10'b1 << 9, WRITE_MIN_HS);
        chk_digit(9, "UT-WR-003 запись позиции 9");

        set_digit(3); do_write(10'b1 << 7, WRITE_MIN_HS-1);
        chk_digit(3, "UT-WR-004 запись короче WRITE_MIN_HS -> не выполняется");

        set_digit(3); mon_reset();
        do_write(10'b1 << 6, 2*WRITE_MIN_HS);
        chk_digit(6, "UT-WR-005 длинная запись -> одна запись");
        chk(saw_settled, "UT-WR-005 settled_dbg_o поднимался внутри операции");

        neg_banner("UT-WR-006 write_pos_i не one-hot");
        set_digit(3); mon_reset();
        do_write(10'b0000000011, WRITE_MIN_HS);
        idle_all(SETTLE+10);
        chk(saw_invalid, "UT-WR-006 не-one-hot write_pos -> invalid_dbg_o == 1");
        chk_digit(3, "UT-WR-006 запись не выполняется");

        // Запись, когда разряд находится на подкатоде
        set_digit(3);
        pulse_guide_a(GUIDE_STEP_HS);
        do_write(10'b1 << 2, WRITE_MIN_HS);
        chk_digit(2, "UT-WR-008 запись с подкатода -> целевой катод установлен");

        neg_banner("UT-WR-009 / UT-ISO-001 подкатодный импульс во время записи");
        set_digit(3); mon_reset();
        @(negedge hsClk); write_pos = 10'b1 << 5; write_en = 1;
        wait_hs(5);
        @(negedge hsClk); guide_a = 1;
        wait_hs(3);
        @(negedge hsClk); guide_a = 0;
        wait_hs(WRITE_MIN_HS);
        @(negedge hsClk); write_en = 0; write_pos = '0;
        idle_all(SETTLE+10);
        chk(saw_invalid, "UT-WR-009 guide во время записи -> invalid_dbg_o == 1");
        chk_digit(5, "UT-ISO-001 запись завершилась в целевой катод");
        chk(!main_leaked, "UT-ISO-004 main_onehot_o невалиден в течение записи");
        chk(!ring_broken, "инвариант: кольцо остаётся one-hot");
    endtask

    task automatic suite_reset0();
        banner("UT-RST0: сброс в катод 0");

        set_digit(5); do_reset0(RESET_MIN_HS);
        chk_digit(0, "UT-RST0-001 сброс в 0 из позиции 5");
        set_digit(0); do_reset0(RESET_MIN_HS);
        chk_digit(0, "UT-RST0-002 сброс в 0 из позиции 0");

        set_digit(5);
        pulse_guide_a(GUIDE_STEP_HS);
        do_reset0(RESET_MIN_HS);
        chk_digit(0, "UT-RST0-003 сброс в 0 с подкатода");

        set_digit(5); do_reset0(RESET_MIN_HS-1);
        chk_digit(5, "UT-RST0-004 короткий сброс -> не выполняется");

        set_digit(5); do_reset0(2*RESET_MIN_HS);
        chk_digit(0, "UT-RST0-005 длинный сброс -> один сброс");

        neg_banner("UT-RST0-006 подкатодный импульс во время сброса");
        set_digit(5); mon_reset();
        @(negedge hsClk); reset0 = 1;
        wait_hs(5);
        @(negedge hsClk); guide_a = 1;
        wait_hs(3);
        @(negedge hsClk); guide_a = 0;
        wait_hs(RESET_MIN_HS);
        @(negedge hsClk); reset0 = 0;
        idle_all(SETTLE+10);
        chk(saw_invalid, "UT-RST0-006 guide во время сброса -> invalid_dbg_o == 1");
        chk_digit(0, "UT-ISO-002 сброс завершился в 0, утечки на катод 1 нет");
        chk(!main_leaked, "UT-ISO-002 main_onehot_o невалиден во время сброса");

        neg_banner("UT-RST0-007 одновременные reset0 и write_en");
        set_digit(5); mon_reset();
        @(negedge hsClk); reset0 = 1; write_en = 1; write_pos = 10'b1 << 2;
        wait_hs(RESET_MIN_HS + 10);
        @(negedge hsClk); reset0 = 0; write_en = 0; write_pos = '0;
        idle_all(SETTLE+10);
        chk(saw_invalid, "UT-RST0-007 конфликт reset0/write -> invalid_dbg_o == 1");
        chk_digit(5, "UT-RST0-007 операция не выполнена, позиция сохранена");
    endtask

    task automatic suite_resetN();
        banner($sformatf("UT-RSTN: сброс в катод %0d", RESET_N_POS));

        set_digit(0); do_resetN(RESET_MIN_HS);
        chk_digit(int'(RESET_N_POS), "UT-RSTN-001 сброс в целевой катод из 0");

        do_resetN(RESET_MIN_HS);
        chk_digit(int'(RESET_N_POS), "UT-RSTN-002 повторный сброс из той же позиции");

        set_digit(3);
        pulse_guide_a(GUIDE_STEP_HS);
        do_resetN(RESET_MIN_HS);
        chk_digit(int'(RESET_N_POS), "UT-RSTN-003 сброс с подкатода");

        set_digit(3); do_resetN(RESET_MIN_HS-1);
        chk_digit(3, "UT-RSTN-004 короткий сброс -> не выполняется");

        neg_banner("UT-RSTN-006 одновременные reset0 и resetN");
        set_digit(4); mon_reset();
        @(negedge hsClk); reset0 = 1; resetN = 1;
        wait_hs(RESET_MIN_HS + 10);
        @(negedge hsClk); reset0 = 0; resetN = 0;
        idle_all(SETTLE+10);
        chk(saw_invalid, "UT-RSTN-006 конфликт reset0/resetN -> invalid_dbg_o == 1");
        chk_digit(4, "UT-RSTN-006 позиция сохранена");
    endtask

    task automatic suite_resetN_disabled();
        neg_banner("UT-RSTN-005: активность resetN_i при EN_RESETN = 0");
        set_digit(3); mon_reset();
        do_resetN(RESET_MIN_HS);
        idle_all(SETTLE+10);
        chk(saw_invalid, "UT-RSTN-005 resetN при EN_RESETN=0 -> invalid_dbg_o == 1");
        chk_digit(3, "UT-RSTN-005 операция не выполняется");
    endtask

    task automatic suite_sim_preset();
        banner("SIM-PRESET: прямая установка кольца (не физический сигнал)");

        set_digit(0);
        @(negedge hsClk);
        sim_preset_en       = 1;
        sim_preset_cathodes = 30'b1 << (3*7);
        wait_hs(1);
        @(negedge hsClk); sim_preset_en = 0;
        wait_hs(SETTLE);
        chk_digit(7, "SIM-PRESET установка кольца в главный катод 7");

        // Установка на подкатод: разряд обязан свалиться на главный катод
        @(negedge hsClk);
        sim_preset_en       = 1;
        sim_preset_cathodes = 30'b1 << (3*7 + 2);   // подкатод B цифры 7
        wait_hs(1);
        @(negedge hsClk); sim_preset_en = 0;
        wait_hs(FALL_STEP_HS + 5);
        chk_digit(8, "SIM-PRESET с подкатода B разряд сваливается вперёд на 8");
    endtask

    task automatic suite_perf();
        banner("UT-PERF: производительность и back-to-back");

        begin
            bit ok; ok = 1;
            set_digit(0);
            for (int i = 0; i < 10; i++) begin
                do_step(.inc(1));
                if (oh2digit(main_onehot) != (i+1) % 10) ok = 0;
            end
            chk(ok, "UT-PERF-001 инкременты подряд");
        end
        begin
            bit ok; ok = 1;
            set_digit(0);
            for (int i = 0; i < 10; i++) begin
                do_step(.inc(0));
                if (oh2digit(main_onehot) != (10 - i - 1) % 10) ok = 0;
            end
            chk(ok, "UT-PERF-002 декременты подряд");
        end
        begin
            bit ok; ok = 1;
            for (int i = 0; i < 10; i++) begin
                do_write(10'b1 << i, WRITE_MIN_HS);
                if (oh2digit(main_onehot) != i) ok = 0;
            end
            chk(ok, "UT-PERF-003 серия из 10 записей");
        end

        set_digit(4); do_step(.inc(1));
        chk_digit(5, "UT-PERF-004 запись, затем сразу инкремент");

        do_reset0(RESET_MIN_HS); do_step(.inc(0));
        chk_digit(9, "UT-PERF-005 сброс, затем сразу декремент");

        // Проверка бюджета времени: полный шаг должен укладываться
        // в один такт процессорной частоты (HS_PER_CLK = 10)
        begin
            int cyc;
            set_digit(0);
            cyc = 0;
            @(negedge hsClk); guide_a = 1;
            fork
                begin
                    wait_hs(GUIDE_STEP_HS);
                    @(negedge hsClk); guide_a = 0; guide_b = 1;
                    wait_hs(GUIDE_STEP_HS);
                    @(negedge hsClk); guide_b = 0;
                end
                begin
                    while (oh2digit(main_onehot) != 1 && cyc < 100) begin
                        @(posedge hsClk); cyc++;
                    end
                end
            join
            while (oh2digit(main_onehot) != 1 && cyc < 100) begin
                @(posedge hsClk); cyc++;
            end
            $display("  [%0s] инфо: полный инкремент занял %0d тактов hsClk", NAME, cyc);
            chk(cyc <= 10, "UT-PERF инкремент укладывается в один такт 1 МГц");
        end
    endtask

    task automatic suite_debug();
        banner("UT-DBG: debug-сигналы");

        idle_all(SETTLE+10);
        chk(on_guide_dbg == 0 && in_write_reset_dbg == 0,
            "UT-DBG-001 на главном катоде: on_guide=0, in_write_reset=0");

        set_digit(2);
        @(negedge hsClk); guide_a = 1;
        wait_hs(GUIDE_STEP_HS + 1);
        chk(on_guide_dbg == 1, "UT-DBG-002 разряд на подкатоде: on_guide_dbg_o == 1");
        chk(main_onehot == 10'b0, "UT-DBG-002 main_onehot_o невалиден на подкатоде");
        @(negedge hsClk); guide_a = 0;
        idle_all(SETTLE+10);
        chk_digit(2, "UT-DBG-002 после снятия разряд вернулся на исходный катод");

        @(negedge hsClk); write_pos = 10'b1 << 6; write_en = 1;
        wait_hs(3);
        chk(in_write_reset_dbg == 1, "UT-DBG-003 запись активна: in_write_reset_dbg_o == 1");
        chk(settled_dbg == 0, "UT-DBG-004 до WRITE_MIN_HS: settled_dbg_o == 0");
        wait_hs(WRITE_MIN_HS);
        chk(settled_dbg == 1, "UT-DBG-004 после WRITE_MIN_HS: settled_dbg_o == 1");
        @(negedge hsClk); write_en = 0; write_pos = '0;
        idle_all(SETTLE+10);
        chk_digit(6, "UT-DBG-004 запись завершена корректно");

        neg_banner("UT-DBG-005 конфликт входов");
        mon_reset();
        @(negedge hsClk); guide_a = 1; guide_b = 1;
        wait_hs(4);
        chk(invalid_dbg == 1, "UT-DBG-005 конфликт -> invalid_dbg_o == 1");
        @(negedge hsClk); guide_a = 0; guide_b = 0;
        idle_all(SETTLE+10);
    endtask

    //==================================================================
    initial begin
        errors = 0; checks = 0; done = 0; mon_arm = 0;
        saw_invalid = 0; saw_settled = 0; main_leaked = 0; ring_broken = 0;
        guide_a = 0; guide_b = 0; write_en = 0; write_pos = '0;
        reset0 = 0; resetN = 0;
        sim_preset_en = 0; sim_preset_cathodes = '0;

        $display("");
        $display("==================================================");
        $display("[%0s] DekatronTubeV2 (кольцевая модель)", NAME);
        $display("[%0s]   GUIDE_STEP=%0d FALL_STEP=%0d GUIDE_MAX=%0d",
                 NAME, GUIDE_STEP_HS, FALL_STEP_HS, GUIDE_MAX_HS);
        $display("[%0s]   WRITE_MIN=%0d RESET_MIN=%0d", NAME, WRITE_MIN_HS, RESET_MIN_HS);
        $display("[%0s]   EN_RESETN=%0b RESET_N_POS=%0d INC_BY_A_THEN_B=%0b",
                 NAME, EN_RESETN, RESET_N_POS, INC_BY_A_THEN_B);
        $display("==================================================");

        mon_reset();
        wait_hs(5);

        case (SUITE)
            1: suite_direction();
            2: suite_resetN_disabled();
            3: begin
                   suite_resetN();
                   suite_sim_preset();
               end
            default: begin
                suite_stable();
                suite_inc();
                suite_dec();
                suite_direction();
                suite_guide_conflicts();
                suite_write();
                suite_reset0();
                if (EN_RESETN) suite_resetN();
                suite_sim_preset();
                suite_perf();
                suite_debug();
            end
        endcase

        idle_all(20);
        $display("[%0s] ИТОГ: проверок %0d, ошибок %0d", NAME, checks, errors);
        err_count = errors;
        done      = 1;
    end

endmodule


//----------------------------------------------------------------------
// Верхний уровень: несколько конфигураций (UT-REQ-008)
//----------------------------------------------------------------------
module DekatronTubeV2_tb;

    int err_full, err_fast, err_dir, err_norstn, err_rstn5;
    bit done_full, done_fast, done_dir, done_norstn, done_rstn5;

    // Полный набор, базовые параметры
    DekatronTubeV2_tb_core #(
        .GUIDE_STEP_HS (2), .FALL_STEP_HS (3), .GUIDE_MAX_HS (20),
        .WRITE_MIN_HS (100), .RESET_MIN_HS (100),
        .EN_RESETN (1'b1), .RESET_N_POS (9),
        .INC_BY_A_THEN_B (1'b1), .SUITE (0), .NAME ("FULL")
    ) u_full (.err_count(err_full), .done(done_full));

    // Тот же набор на других временных параметрах
    DekatronTubeV2_tb_core #(
        .GUIDE_STEP_HS (3), .FALL_STEP_HS (5), .GUIDE_MAX_HS (30),
        .WRITE_MIN_HS (20), .RESET_MIN_HS (20),
        .EN_RESETN (1'b1), .RESET_N_POS (9),
        .INC_BY_A_THEN_B (1'b1), .SUITE (0), .NAME ("FAST")
    ) u_fast (.err_count(err_fast), .done(done_fast));

    // Обратное направление подкатодов
    DekatronTubeV2_tb_core #(
        .EN_RESETN (1'b1), .INC_BY_A_THEN_B (1'b0),
        .SUITE (1), .NAME ("DIR_REV")
    ) u_dir (.err_count(err_dir), .done(done_dir));

    // resetN запрещён параметром
    DekatronTubeV2_tb_core #(
        .EN_RESETN (1'b0), .SUITE (2), .NAME ("NO_RSTN")
    ) u_norstn (.err_count(err_norstn), .done(done_norstn));

    // Линия сброса в катод 5 — для счётчика данных до 255
    DekatronTubeV2_tb_core #(
        .EN_RESETN (1'b1), .RESET_N_POS (5),
        .SUITE (3), .NAME ("RSTN_5")
    ) u_rstn5 (.err_count(err_rstn5), .done(done_rstn5));

    initial begin
        wait (done_full && done_fast && done_dir && done_norstn && done_rstn5);
        #1000;
        $display("");
        $display("==================================================");
        $display("  СВОДНЫЙ РЕЗУЛЬТАТ DekatronTubeV2");
        $display("--------------------------------------------------");
        $display("  FULL     : %0d ошибок", err_full);
        $display("  FAST     : %0d ошибок", err_fast);
        $display("  DIR_REV  : %0d ошибок", err_dir);
        $display("  NO_RSTN  : %0d ошибок", err_norstn);
        $display("  RSTN_5   : %0d ошибок", err_rstn5);
        $display("--------------------------------------------------");
        if ((err_full + err_fast + err_dir + err_norstn + err_rstn5) == 0)
            $display("  РЕЗУЛЬТАТ: ВСЕ ТЕСТЫ ПРОЙДЕНЫ");
        else
            $display("  РЕЗУЛЬТАТ: ЕСТЬ ОШИБКИ (%0d)",
                     err_full + err_fast + err_dir + err_norstn + err_rstn5);
        $display("==================================================");
        $finish;
    end

    initial begin
        #100_000_000;
        $display("ОШИБКА: таймаут тестбенча");
        $finish;
    end

endmodule

`default_nettype wire
