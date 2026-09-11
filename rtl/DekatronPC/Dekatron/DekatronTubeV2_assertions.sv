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
    parameter bit EN_RESETN = 1'b0
)(
    input wire         hsClk,
    input wire         guide_a_i,
    input wire         guide_b_i,
    input wire         write_en_i,
    input wire [9:0]   write_pos_i,
    input wire         reset0_i,
    input wire         resetN_i,
    input wire [29:0]  cathodes_q
);
`ifdef ASSERTIONS
    // §13.1. Запрет одновременных подкатодных импульсов
    property p_no_simultaneous_guides;
        @(posedge hsClk) !(guide_a_i && guide_b_i);
    endproperty
    a_no_simultaneous_guides: assert property (p_no_simultaneous_guides)
        else $error("DekatronTubeV2: simultaneous guide_a_i and guide_b_i");

    // §13.2. Запрет подкатодных импульсов во время записи
    property p_no_guide_during_write;
        @(posedge hsClk) write_en_i |-> !(guide_a_i || guide_b_i);
    endproperty
    a_no_guide_during_write: assert property (p_no_guide_during_write)
        else $error("DekatronTubeV2: guide activity during write");

    // §13.3. Запрет подкатодных импульсов во время сброса в 0
    property p_no_guide_during_reset0;
        @(posedge hsClk) reset0_i |-> !(guide_a_i || guide_b_i);
    endproperty
    a_no_guide_during_reset0: assert property (p_no_guide_during_reset0)
        else $error("DekatronTubeV2: guide activity during reset0");

    // §13.3 (доп.). То же для сброса в катод RESET_N_POS
    property p_no_guide_during_resetN;
        @(posedge hsClk) (resetN_i && EN_RESETN) |-> !(guide_a_i || guide_b_i);
    endproperty
    a_no_guide_during_resetN: assert property (p_no_guide_during_resetN)
        else $error("DekatronTubeV2: guide activity during resetN");

    // §13.4. Запрет конфликта записи и сброса
    property p_no_write_reset_conflict;
        @(posedge hsClk)
        !((write_en_i && reset0_i) ||
          (write_en_i && resetN_i) ||
          (reset0_i   && resetN_i));
    endproperty
    a_no_write_reset_conflict: assert property (p_no_write_reset_conflict)
        else $error("DekatronTubeV2: write/reset conflict");

    // §13.5. Проверка one-hot write_pos
    property p_write_pos_onehot;
        @(posedge hsClk) write_en_i |-> $onehot(write_pos_i);
    endproperty
    a_write_pos_onehot: assert property (p_write_pos_onehot)
        else $error("DekatronTubeV2: write_pos_i is not one-hot");

    // §13.6. Запрет resetN при EN_RESETN = 0
    generate
        if (!EN_RESETN) begin : g_no_resetN
            property p_resetN_disabled;
                @(posedge hsClk) !resetN_i;
            endproperty
            a_resetN_disabled: assert property (p_resetN_disabled)
                else $error("DekatronTubeV2: resetN_i active while EN_RESETN = 0");
        end
    endgenerate

    // Инвариант кольцевой модели: разряд ровно в одном месте
    property p_ring_onehot;
        @(posedge hsClk) $onehot(cathodes_q);
    endproperty
    a_ring_onehot: assert property (p_ring_onehot)
        else $error("DekatronTubeV2: cathode ring is not one-hot (%b)", cathodes_q);

    // Доп. проверка: write_pos_i не меняется внутри импульса записи.
    // Процедурно — для переносимости между Verilator и Icarus.
    logic       write_en_d;
    logic [9:0] write_pos_d;

    initial begin
        write_en_d  = 1'b0;
        write_pos_d = 10'b0;
    end

    always_ff @(posedge hsClk) begin
        if (write_en_i && write_en_d && (write_pos_i != write_pos_d))
            $error("DekatronTubeV2: write_pos_i changed during active write pulse");
        write_en_d  <= write_en_i;
        write_pos_d <= write_pos_i;
    end
`endif
endmodule

`default_nettype wire
