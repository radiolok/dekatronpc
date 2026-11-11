//======================================================================
// DekatronTubeV2_assertions — проверки допустимости внешних воздействий
//----------------------------------------------------------------------
// По спецификации Dekatron_Model_TRS_v0_1.md §13, адаптировано под
// кольцевую модель (добавлен инвариант one-hot на 30-битном кольце).
//
// Проверки относятся к корректности работы ВЫШЕСТОЯЩЕГО блока
// (DekatronCounterV2): физический прибор не может отказаться принять
// недопустимую комбинацию, он лишь ведёт себя непредсказуемо.
//
//======================================================================

`default_nettype none

module DekatronTubeV2_assertions #(
    parameter logic [9:0] LINES = 10'h3FF
)(
    input wire         hsClk,
    input wire         guide_a_i,
    input wire         guide_b_i,
    input wire [9:0]   line_open_i,
    input wire [29:0]  cathodes_q
);
`ifdef ASSERTIONS
    // §13.1. Одновременные подкатодные импульсы допустимы только как
    // перекрытие фаз, когда разряд уже на подкатоде (doc/harwell_1951_review.md §2)
    localparam logic [29:0] MASK_MAIN = 30'b001001001001001001001001001001;

    property p_no_simultaneous_guides;
        @(posedge hsClk) !(guide_a_i && guide_b_i && |(cathodes_q & MASK_MAIN));
    endproperty
    a_no_simultaneous_guides: assert property (p_no_simultaneous_guides)
        else $error("DekatronTubeV2: guide_a_i and guide_b_i together on a main cathode");

    // §13.2–13.3. Запрет подкатодных импульсов, пока закрыта хоть одна
    // катодная линия (запись и сброс — одно событие, TRS v0.56)
    wire wr_any_active = |(~line_open_i & LINES);

    property p_no_guide_during_write;
        @(posedge hsClk) wr_any_active |-> !(guide_a_i || guide_b_i);
    endproperty
    a_no_guide_during_write: assert property (p_no_guide_during_write)
        else $error("DekatronTubeV2: guide activity during write");

    // §13.4–13.5. Горящий катод закрыт — открыта ровно одна линия
    logic [9:0] main_now;
    always_comb
        for (int i = 0; i < 10; i++) main_now[i] = cathodes_q[3*i];

    property p_one_open_line;
        @(posedge hsClk) |(main_now & ~line_open_i) |-> $onehot(line_open_i & LINES);
    endproperty
    a_one_open_line: assert property (p_one_open_line)
        else $error("DekatronTubeV2: burning cathode closed, lines %b", line_open_i);

    // Инвариант кольцевой модели: разряд ровно в одном месте
    property p_ring_onehot;
        @(posedge hsClk) $onehot(cathodes_q);
    endproperty
    a_ring_onehot: assert property (p_ring_onehot)
        else $error("DekatronTubeV2: cathode ring is not one-hot (%b)", cathodes_q);
`endif
endmodule

`default_nettype wire
