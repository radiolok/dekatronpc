//======================================================================
// DekatronPC — верхний уровень машины
//----------------------------------------------------------------------
// Соединяет:
//
//   MachineCtrl   верхний автомат, декодер инструкций
//   IpLine        выборка инструкций, промотка циклов   -> IpMemory (APB)
//   ApLine        работа с данными, MemLock             -> Ram      (APB)
//   RstTimeRelay  выдержка физических импульсов сброса
//
//----------------------------------------------------------------------
// ЧТО ИЗМЕНИЛОСЬ ОТНОСИТЕЛЬНО ПРЕЖНЕГО ВЕРХНЕГО УРОВНЯ
//
// 1. Исчез узел формирования Rst_n:
//        assign Rst_n = RstExtern_n & ~RstReqLong;
//    Прежде инструкция сброса дёргала общий асинхронный Rst_n всей
//    машины через OneShot. Декатрон цифровых сбросов не имеет: установка
//    позиции разряда — импульс по катоду длительностью около сотни
//    тактов hs_clk. Поэтому сброс счётчиков стал физической линией с
//    выдержкой, а rst_n остался сбросом одной лишь логики.
//
//    Сам сброс при этом остаётся общемашинным: линии soft_rst/hard_rst
//    приводят в исходное состояние и счётчики, и обе линии, и верхний
//    автомат. Не затрагивается только периферия индикации, которая
//    живёт в слое эмулятора и от кнопок сброса машины не зависит.
//
// 2. Исчезли оба преобразователя BcdToBinEnc вместе с умножителями:
//    банковая память адресуется BCD-тетрадами напрямую.
//
// 3. Память подключена по тому же Valid/Ready, что и остальной тракт,
//    и имеет регистровый выход, который держит значение последней
//    затронутой ячейки до следующего обращения. Благодаря этому линиям
//    не нужна собственная копия ячейки, а чтение стало ленивым: шаги
//    указателя память не трогают. У каждой памяти единственный мастер,
//    поэтому арбитраж не нужен: IpLine владеет IpMemory, ApLine — Ram.
//
// 4. Ширина шины состояния выросла с 3 до 4 бит: у верхнего автомата
//    стало больше состояний. Для слоя эмулятора это несовместимое
//    изменение и требует правки индикации.
//======================================================================

`default_nettype none

//----------------------------------------------------------------------
// RstTimeRelay — реле времени в цепи сброса
//
// Разряд декатрона сдвигается только импульсом полной длительности,
// поэтому короткий сигнал с пульта или от инструкции надо удержать.
// В машине это физическое реле; здесь его поведенческая модель.
//
// Пока реле держит линию, счётчики заняты, а верхний автомат ждёт
// снятия busy.
//----------------------------------------------------------------------
module RstTimeRelay #(
    parameter unsigned HOLD_HS         = 104,   // тактов hs_clk
    parameter bit          RST_ON_POWERUP  = 1'b1   // аппаратный сброс при включении
)(
    input  wire  hs_clk,
    input  wire  rst_n,

    input  wire  soft_key,      // пульт
    input  wire  hard_key,
    input  wire  soft_req,      // инструкции SRST / SoftRstOnEOT
    input  wire  hard_req,      // инструкция HRST

    output wire  soft_rst,      // физические линии на счётчики
    output wire  hard_rst,
    output wire  busy
);

    localparam int unsigned CNT_W = 16;

    logic [CNT_W-1:0] cnt;
    logic             active;
    logic             is_hard;
    logic             powerup_done;

    wire trig_hard = hard_key | hard_req |
                     (RST_ON_POWERUP & ~powerup_done);
    wire trig_soft = soft_key | soft_req;
    wire trig      = trig_hard | trig_soft;

    always_ff @(posedge hs_clk, negedge rst_n) begin
        if (~rst_n) begin
            cnt          <= '0;
            active       <= 1'b0;
            is_hard      <= 1'b0;
            powerup_done <= 1'b0;
        end
        else if (~active) begin
            if (trig) begin
                // Аппаратный сброс имеет приоритет над программным
                active  <= 1'b1;
                is_hard <= trig_hard;
                cnt     <= CNT_W'(1);
            end
        end
        else begin
            if (cnt >= CNT_W'(HOLD_HS)) begin
                active       <= 1'b0;
                cnt          <= '0;
                powerup_done <= 1'b1;
            end
            else begin
                cnt <= cnt + CNT_W'(1);
            end
        end
    end

    assign hard_rst = active &  is_hard;
    assign soft_rst = active & ~is_hard;
    assign busy     = active;

endmodule


//----------------------------------------------------------------------
// DekatronPC
//----------------------------------------------------------------------
module DekatronPC #(
    // Ячейка памяти данных: {hundreds[1:0], tens[3:0], ones[3:0]}
    parameter unsigned MEM_DATA_WIDTH    = 10,

    // Верхние пределы счётчиков
    parameter [AP_DEKATRON_NUM*DEKATRON_WIDTH-1:0]
              AP_TOP_VALUE   = {4'd2, 4'd9, 4'd9, 4'd9, 4'd9},   // 29999
    parameter [DATA_DEKATRON_NUM*DEKATRON_WIDTH-1:0]
              DATA_TOP_VALUE = {4'd2, 4'd5, 4'd5},               // 255

    // Тайминги памяти, тактов фазы ACCESS
    parameter unsigned MEM_READ_CYCLES  = 1,
    parameter unsigned MEM_WRITE_CYCLES = 1,

    // Выдержка реле времени в цепи сброса
    parameter unsigned RST_HOLD_HS      = 104,

    // Второй порт чтения памяти и счётчик инструкций — только эмулятор
    parameter bit          EN_EMULATOR      = 1'b0
)(
    input  wire hsClk,
    input  wire Clk,
    input  wire rst_n,          // сброс логики; разряд декатронов не двигает

    //------------------------------------------------------------------
    // Пульт управления
    //------------------------------------------------------------------
    input  wire SoftRstKey,
    input  wire HardRstKey,
    input  wire Halt,
    input  wire Step,
    input  wire Run,
    input  wire InsnLoadingStart,
    input  wire InsnLoadingStop,
    input  wire keyNextIp,
    input  wire keyPrevIp,

/* verilator lint_off UNUSEDSIGNAL */
    // Переключение предзагруженных программ выполняет слой эмулятора
    input  wire key_next_app_i,
/* verilator lint_on UNUSEDSIGNAL */

    // Тумблеры
    input  wire EchoMode,
    input  wire RunOnHardRst,
    input  wire RunOnSoftRst,
    input  wire SoftRstOnEOT,
    input  wire BellOnCIN,
    input  wire BellOnHALT,
    input  wire BellOnError,

    //------------------------------------------------------------------
    // Терминал
    //------------------------------------------------------------------
    output wire [DATA_DEKATRON_NUM*DEKATRON_WIDTH-1:0] tx_data_bcd,
    output wire                                        tx_vld,
    input  wire                                        tx_rdy,
    input  wire [DATA_DEKATRON_NUM*DEKATRON_WIDTH-1:0] rx_data_bcd,
    input  wire                                        rx_vld,

    //------------------------------------------------------------------
    // Загрузка программы
    //------------------------------------------------------------------
    input  wire [INSN_WIDTH-1:0] InsnIn,
    input  wire                  InsnInValid,
    output wire                  InsnInReady,
    output wire                  InsnInLoading,

    //------------------------------------------------------------------
    // Состояние машины
    //------------------------------------------------------------------
    output wire [IP_DEKATRON_NUM*DEKATRON_WIDTH-1:0]   IpAddress,
    output wire [AP_DEKATRON_NUM*DEKATRON_WIDTH-1:0]   ApAddress,
    output wire [LOOP_DEKATRON_NUM*DEKATRON_WIDTH-1:0] LoopCount,
    output wire [INSN_WIDTH-1:0]                       Insn,
    output wire [3:0]                                  state,
    output wire                                        IsHalted,
    output wire                                        Bell,
    output wire                                        LoopOverflow,

    //------------------------------------------------------------------
    // Индикация эмулятора: второй порт чтения обеих памятей
    //------------------------------------------------------------------
/* verilator lint_off UNUSEDSIGNAL */
    input  wire [IP_DEKATRON_NUM*DEKATRON_WIDTH-1:0]   IpAddress1,
    input  wire [AP_DEKATRON_NUM*DEKATRON_WIDTH-1:0]   ApAddress1,
/* verilator lint_on UNUSEDSIGNAL */
    output wire [INSN_WIDTH-1:0]                       RomData1,
    output wire [DATA_DEKATRON_NUM*DEKATRON_WIDTH-1:0] ApData1,
    output wire [31:0]                                 IRET
);

    localparam int unsigned IP_W   = IP_DEKATRON_NUM   * DEKATRON_WIDTH;
    localparam int unsigned AP_W   = AP_DEKATRON_NUM   * DEKATRON_WIDTH;
    localparam int unsigned DATA_W = DATA_DEKATRON_NUM * DEKATRON_WIDTH;

    //------------------------------------------------------------------
    // Реле времени в цепи сброса
    //------------------------------------------------------------------
    wire soft_rst_req, hard_rst_req;
    wire soft_rst, hard_rst, rst_busy;

    RstTimeRelay #(
        .HOLD_HS        (RST_HOLD_HS),
        .RST_ON_POWERUP (1'b1)
    ) rstRelay (
        .hs_clk   (hsClk),
        .rst_n    (rst_n),
        .soft_key (SoftRstKey),
        .hard_key (HardRstKey),
        .soft_req (soft_rst_req),
        .hard_req (hard_rst_req),
        .soft_rst (soft_rst),
        .hard_rst (hard_rst),
        .busy     (rst_busy)
    );

    //------------------------------------------------------------------
    // Линия выборки инструкций и память программ
    //------------------------------------------------------------------
    wire                  ip_valid, ip_ready;
    wire [1:0]            ip_op;
    wire                  loop_val_zero;
    wire                  insn_loading;
    wire                  insn_valid;
    wire                  insn_mode;      // 0 = Debug ISA, 1 = Brainfuck ISA

    wire [IP_W-1:0]       ip_mem_addr;
    wire [INSN_WIDTH-1:0] ip_mem_wr_data, ip_mem_rd_data;
    wire                  ip_mem_valid, ip_mem_ready, ip_mem_wr;
    wire                  ip_mem_rd_valid, ip_mem_err;

    IpLine #(
        .HARD_RST_D_CNT    (IP_DEKATRON_NUM - 2),
        .LOOP_READ         (EN_EMULATOR)
    ) ipLine (
        .rst_n         (rst_n),
        .clk           (Clk),
        .hs_clk        (hsClk),
        .soft_rst      (soft_rst),
        .hard_rst      (hard_rst),

        .valid         (ip_valid),
        .ready         (ip_ready),
        .op            (ip_op),
        .loop_val_zero (loop_val_zero),

        .insn          (Insn),
        .insn_valid    (insn_valid),

        .halt_rq       (IsHalted),
        .key_prev_ip   (keyPrevIp),
        .key_next_ip   (keyNextIp),

        .insn_loading  (insn_loading),
        .insn_mode     (insn_mode),
        .insn_in       (InsnIn),
        .insn_in_valid (InsnInValid),
        .insn_in_ready (InsnInReady),

        .ip_addr       (IpAddress),
        .loop_count    (LoopCount),
        .loop_overflow (LoopOverflow),

        .mem_addr      (ip_mem_addr),
        .mem_wr_data   (ip_mem_wr_data),
        .mem_rd_data   (ip_mem_rd_data),
        .mem_valid     (ip_mem_valid),
        .mem_ready     (ip_mem_ready),
        .mem_wr        (ip_mem_wr),
        .mem_rd_valid  (ip_mem_rd_valid),
        .mem_err       (ip_mem_err)
    );

    IpMemory #(
        .D_NUM         (IP_DEKATRON_NUM),
        .READ_CYCLES   (MEM_READ_CYCLES),
        .WRITE_CYCLES  (MEM_WRITE_CYCLES),
        .EN_BOOTLOADER (1'b1),
        .EN_DBG_PORT   (EN_EMULATOR)
    ) ipMemory (
        .clk           (Clk),
        .rst_n         (rst_n),
        .valid         (ip_mem_valid),
        .ready         (ip_mem_ready),
        .wr            (ip_mem_wr),
        .addr          (ip_mem_addr),
        .wr_data       (ip_mem_wr_data),
        .rd_data       (ip_mem_rd_data),
        .rd_valid      (ip_mem_rd_valid),
        .err           (ip_mem_err),
        .dbg_addr      (IpAddress1),
        .dbg_data      (RomData1),
        .is_bootloader ()
    );

    //------------------------------------------------------------------
    // Линия работы с данными и память данных
    //------------------------------------------------------------------
    wire                       ap_valid, ap_ready;
    wire [3:0]                 ap_op;
    wire                       ap_dec;
    wire                       data_zero, ap_zero, mem_lock;

    wire [AP_W-1:0]            ap_mem_addr;
    wire [MEM_DATA_WIDTH-1:0]  ap_mem_wr_data, ap_mem_rd_data;
    wire                       ap_mem_valid, ap_mem_ready, ap_mem_wr;
    wire                       ap_mem_rd_valid, ap_mem_err;
    wire                       data_zero_valid;

    ApLine #(
        .MEM_DATA_WIDTH    (MEM_DATA_WIDTH),
        .AP_TOP_VALUE      (AP_TOP_VALUE),
        .DATA_TOP_VALUE    (DATA_TOP_VALUE)
    ) apLine (
        .rst_n       (rst_n),
        .clk         (Clk),
        .hs_clk      (hsClk),
        .soft_rst    (soft_rst),
        .hard_rst    (hard_rst),

        .valid       (ap_valid),
        .ready       (ap_ready),
        .op          (ap_op),
        .dec         (ap_dec),

        .data_zero       (data_zero),
        .data_zero_valid (data_zero_valid),
        .ap_zero         (ap_zero),
        .mem_lock        (mem_lock),

        .rx_data_bcd (rx_data_bcd),
        .tx_data_bcd (tx_data_bcd),

        .mem_addr     (ap_mem_addr),
        .mem_wr_data  (ap_mem_wr_data),
        .mem_rd_data  (ap_mem_rd_data),
        .mem_valid    (ap_mem_valid),
        .mem_ready    (ap_mem_ready),
        .mem_wr       (ap_mem_wr),
        .mem_rd_valid (ap_mem_rd_valid),
        .mem_err      (ap_mem_err)
    );

    assign ApAddress = ap_mem_addr;

    wire [MEM_DATA_WIDTH-1:0] ap_dbg_data;

    Ram #(
        .D_NUM         (AP_DEKATRON_NUM),
        .DATA_WIDTH    (MEM_DATA_WIDTH),
        .READ_CYCLES   (MEM_READ_CYCLES),
        .WRITE_CYCLES  (MEM_WRITE_CYCLES),
        .EN_DBG_PORT   (EN_EMULATOR)
    ) ram (
        .clk      (Clk),
        .rst_n    (rst_n),
        .valid    (ap_mem_valid),
        .ready    (ap_mem_ready),
        .wr       (ap_mem_wr),
        .addr     (ap_mem_addr),
        .wr_data  (ap_mem_wr_data),
        .rd_data  (ap_mem_rd_data),
        .rd_valid (ap_mem_rd_valid),
        .err      (ap_mem_err),
        .ovl_hit  (1'b0),
        .ovl_data ({MEM_DATA_WIDTH{1'b0}}),
        .dbg_addr (ApAddress1),
        .dbg_data (ap_dbg_data)
    );

    // Ячейка памяти уже 10 бит, счётчик данных 12: старшие два бита
    // сотен восстанавливаются нулями, диапазон значений 0..255
    assign ApData1 = {{(DATA_W-MEM_DATA_WIDTH){1'b0}}, ap_dbg_data};

    //------------------------------------------------------------------
    // Верхний автомат
    //------------------------------------------------------------------
    MachineCtrl #(
        .EN_EMULATOR   (EN_EMULATOR)
    ) machineCtrl (
        .clk                    (Clk),
        .rst_n                  (rst_n),

        .halt_key               (Halt),
        .step_key               (Step),
        .run_key                (Run),
        .key_insn_loading_start (InsnLoadingStart),
        .key_insn_loading_stop  (InsnLoadingStop),

        .echo_mode              (EchoMode),
        .run_on_hard_rst        (RunOnHardRst),
        .run_on_soft_rst        (RunOnSoftRst),
        .soft_rst_on_eot        (SoftRstOnEOT),
        .bell_on_cin            (BellOnCIN),
        .bell_on_halt           (BellOnHALT),
        .bell_on_error          (BellOnError),

        .ip_valid               (ip_valid),
        .ip_ready               (ip_ready),
        .ip_op                  (ip_op),
        .loop_val_zero          (loop_val_zero),
        .insn_loading           (insn_loading),
        .insn                   (Insn),
        .insn_valid             (insn_valid),
        .loop_overflow          (LoopOverflow),

        .ap_valid               (ap_valid),
        .ap_ready               (ap_ready),
        .ap_op                  (ap_op),
        .ap_dec                 (ap_dec),
        .data_zero              (data_zero),
        .data_zero_valid        (data_zero_valid),
        .ap_zero                (ap_zero),
        .mem_lock               (mem_lock),

        .tx_vld                 (tx_vld),
        .tx_rdy                 (tx_rdy),
        .rx_vld                 (rx_vld),

        .soft_rst_req           (soft_rst_req),
        .hard_rst_req           (hard_rst_req),
        .rst_busy               (rst_busy),
        .soft_rst               (soft_rst),
        .hard_rst               (hard_rst),

        .insn_mode              (insn_mode),
        .is_halted              (IsHalted),
        .bell                   (Bell),
        .state                  (state),
        .iret                   (IRET)
    );

    assign InsnInLoading = insn_loading;

`ifndef SYNTH
    initial begin
        if (AP_DEKATRON_NUM < 2 || IP_DEKATRON_NUM < 3)
            $error("DekatronPC: слишком мало декатронов для банковой памяти");
    end

`ifdef ASSERTIONS
    always @(posedge Clk) begin
        // Каждая память имеет единственного мастера, поэтому
        // одновременных транзакций от разных источников быть не может
        if (rst_n && ip_mem_err)
            $error("DekatronPC: ошибка обращения к памяти программ");
        if (rst_n && ap_mem_err)
            $error("DekatronPC: ошибка обращения к памяти данных");
        if (rst_n && soft_rst && hard_rst)
            $error("DekatronPC: обе линии сброса активны одновременно");
    end
`endif
`endif

endmodule

`default_nettype wire
