# DekatronCounter — логика работы машины состояний и план перевода на Valid/Ready

Модуль: `rtl/DekatronPC/Dekatron/DekatronCounter.sv`

## 1. Назначение

`DekatronCounter` — многодекадный BCD-счётчик на «декатронах». Каждая декада — это
экземпляр `DekatronModule`, который является поведенческой моделью холодно-катодной
счётной лампы (сдвиг тлеющего разряда по катодам). Счётчик используется в четырёх
местах машины:

| Инстанс | Файл | Параметры | Роль |
|---|---|---|---|
| `IP_counter` | `IpLine.sv` | `WRITE=0`, `HARD_RST_D_CNT=IP-2` | указатель команды |
| `Loop_counter` | `IpLine.sv` | `READ=EMU`, `WRITE=0` | счётчик цикла brainfuck |
| `AP_counter` | `ApLine.sv` | `WRITE=0`, `TOP_LIMIT_MODE=1` | адресный указатель |
| `Data_counter` | `ApLine.sv` | `WRITE=1`, `TOP_LIMIT_MODE=1` | ячейка данных |

Физическая особенность декатрона — «бесплатный» перенос/заём разряда: лампа сама
передаёт разряд соседней декаде, когда переходит через 9→0 (инкремент) или 0→9
(декремент). Вся цепочка переноса в этом модуле построена именно на этом эффекте.

## 2. Тактирование

Два домена:

- `Clk` — основная логика (FSM, регистры). Это `hsClk / 10` (см. `ClockDivider` в
  тестбенчах; в реальной системе `HSCLK_DIV=10`).
- `hsClk` — быстрый клок, эмулирующий физические задержки переноса разряда в лампе.

Ключевой факт: полный физический перенос одного разряда внутри `DekatronPulseSender`
занимает **менее 10 тактов `hsClk`** (OneShot'ы с `DELAY` до 9), то есть **укладывается
в один такт `Clk`**. Это и есть физическая основа для «однотактного» инкремента.

## 3. Интерфейс

### 3.1 Параметры

| Параметр | По умолч. | Описание |
|---|---|---|
| `D_NUM` | `3` | число декад |
| `WIDTH` | `D_NUM * DEKATRON_WIDTH` | ширина шины `In`/`Out` |
| `READ` | `1` | выдача BCD-значения (`BinToBcd` в `DekatronModule`) |
| `WRITE` | `1` | поддержка записи значения |
| `HARD_RST_D_CNT` | `0` | с какой декады разрешён `HardRst_n` (`EN_HARD_RST`) |
| `TOP_LIMIT_MODE` | `0` | режим «верхнего предела» — перенос на `TOP_VALUE` |
| `TOP_VALUE` | `{5,5,5}` | верхнее значение (для `TOP_LIMIT_MODE`) |

### 3.2 Порты

| Порт | Направление | Описание |
|---|---|---|
| `Rst_n`, `HardRst_n` | in | сбросы (мягкий / аппаратный по декадам) |
| `Clk`, `hsClk` | in | клоки |
| `Request` | in | импульс запуска операции (текущий протокол) |
| `Dec` | in | направление: `1` = декремент, `0` = инкремент |
| `Set` | in | записать `In` в счётчик |
| `SetZero` | in | сбросить счётчик в ноль |
| `In[WIDTH-1:0]` | in | данные для `Set` |
| `Ready` | out | готовность принять новую операцию |
| `Zero` | out | признак «счётчик равен нулю» |
| `Out[WIDTH-1:0]` | out | текущее значение (BCD) |

## 4. Машина состояний

### 4.1 Кодирование состояний

```systemverilog
localparam [2:0]
    IDLE     = 3'b000,
    INC      = 3'b010,
    DEC      = 3'b011,
    SET_ZERO = 3'b101,
    SET_TOP  = 3'b110,
    SET      = 3'b111;
```

Кодирование битовое (не one-hot):

- `state[2]` — признак SET-класса операций (`SET`, `SET_TOP`, `SET_ZERO`);
- `state[1]` — признак INC/DEC (активно только когда `state[2]==0`);
- `state[0]` — направление: `0` = инкремент, `1` = декремент.

Это позволяет:
- `PulseF = (state == INC)`, `PulseR = (state == DEC)`;
- `write_set = Impulse(state[2])` — импульс запуска таймера записи по фронту бита `state[2]`.

### 4.2 Комбинационные сигналы-признаки операции

```systemverilog
// TOP_LIMIT_MODE: нижний/верхний предел (автопереход через край)
assign SetTop      = Zero & Dec;          // 0 → TOP_VALUE  при декременте
assign SetZeroInt  = (&TopOut & ~Dec);    // TOP → 0        при инкременте

// признак «операция SET-класса»
assign SetAny = Set | SetTop | SetZeroInt | SetZero;
```

`TopOut[d]` = `OutPos[TOP_PIN_OUT]` — горит ли в декаде катод верхнего предела.

### 4.3 Логика переходов

```systemverilog
always_comb begin
    next = IDLE;                       // по умолчанию — назад в IDLE
    case (state)
        IDLE: begin
            if (_Request) begin
                if (~SetAny) begin     // быстрый путь
                    if (Dec) next = DEC; else next = INC;
                end
                else if (Set)          next = SET;
                else if (SetZero)      next = SET_ZERO;
                else if (TOP_LIMIT_MODE) begin
                    if (SetTop)        next = SET_TOP;
                    else if (SetZeroInt) next = SET_ZERO;
                    else               next = IDLE;
                end
                else                   next = IDLE;
            end
        end
        SET_TOP, SET_ZERO, SET: begin
            if (writed_n)              next = state;   // ждём конца таймера
        end                            // иначе next остаётся IDLE (default)
        default:                       next = IDLE;
    endcase
end
```

Замечания:

- Состояния `INC` и `DEC` **не имеют явных веток** и попадают в `default: next = IDLE`.
  То есть каждое из них живёт ровно один такт `Clk`.
- SET-состояния «залипают» на всё время, пока `writed_n == 1`, и выходят в `IDLE`,
  когда таймер досчитал.
- Приоритет при `SetAny==1`: `Set` > `SetZero` > (автопереходы `SetTop`/`SetZeroInt`).

### 4.4 Генерация импульсов шагов и таймер записи

```systemverilog
wire PulseR = (state == DEC);
wire PulseF = (state == INC);

// одиночные Clk-импульсы шага для декады 0
Impulse pulsesImpDec(.En(PulseR), .Impulse(Pulses[1]));
Impulse pulsesImpInc(.En(PulseF), .Impulse(Pulses[0]));

// импульс запуска записи по фронту state[2]
wire write_set;
Impulse writeimpulse(.En(state[2]), .Impulse(write_set));

// таймер записи: 100 тактов hsClk
wire writed_n;
OneShot #(.DELAY(100)) writeOneShot(.Clk(hsClk), .En(write_set), .Impulse(writed_n));

// сигналы записи в декады на время таймера
wire [2:0] SetTopZero;
assign SetTopZero[0] = ((state == SET_ZERO) & writed_n);
assign SetTopZero[1] = ((state == SET_TOP)  & writed_n);
assign SetTopZero[2] = ((state == SET)      & writed_n);
```

Замечание по именам: `writed_n` — на самом деле **активный-высокий** сигнал «идёт
запись» (выход `Impulse` у `OneShot` = `|count | En`). Суффикс `_n` сбивает с толку.

### 4.5 Логика Ready

```systemverilog
assign Ready = ~Request & ~(|DekatronBusy) & (state == IDLE);
```

`DekatronBusy[d] = |pulses | |SetTopZero` — признак, что декада получает импульс шага
или находится в окне записи.

## 5. Два класса операций

### 5.1 Быстрые операции: INC / DEC

Путь: `IDLE → INC|DEC → IDLE`. Состояние `INC`/`DEC` держится ровно один такт `Clk`,
за который `PulseF`/`PulseR` выдают одиночный импульс в декаду 0. Сам перенос разряда
досчитывается внутри `hsClk`-домена ещё в течение этого же такта `Clk`.

Итоговая латентность (от фронта `Request`):

| Такт Clk | `Request` | `_Request` | `state` | `PulseF` | `Busy` | `Ready` |
|---|---|---|---|---|---|---|
| 0 | 0 | 0 | IDLE | 0 | 0 | 1 |
| 1 | 1 | 1 | IDLE | 0 | 0 | 0 |
| 2 | 0 | 0 | INC | 1 | 1 | 0 |
| 3 | 0 | 0 | IDLE | 0 | 0 | 1 |

`Ready` низкий **2 такта Clk** (такт регистрации запроса + такт импульса), затем снова
высокий. Физически значение `Out` стабилизируется уже к концу такта 2.

### 5.2 Медленные операции: SET / SET_ZERO / SET_TOP

Путь: `IDLE → SET|SET_ZERO|SET_TOP → (writed_n) → IDLE`.

- По фронту `state[2]` вырабатывается `write_set` (один такт `Clk`).
- `writeOneShot` (`DELAY=100` на `hsClk`) держит `writed_n == 1` **≈ 100 тактов hsClk
  = 10 тактов Clk**.
- Пока `writed_n == 1`, модуль держит состояние SET и подаёт в декады
  `SetTopZero[2:0]` — декатрон каждый такт `hsClk` переписывает своё значение из `In`
  (или в ноль / в `TOP_VALUE`).
- Когда таймер досчитал, `writed_n` падает → `next = IDLE`.

| Такт Clk | `state` | `write_set` | `writed_n` | `SetTopZero` | `Ready` |
|---|---|---|---|---|---|
| 1 | IDLE | 0 | 0 | 0 | 0 |
| 2 | SET | 1 | 1 | 1 | 0 |
| 3..11 | SET | 0 | 1 | 1 | 0 |
| 12 | SET | 0 | 0 | 0 | 0 |
| 13 | IDLE | 0 | 0 | 0 | 1 |

`Ready` низкий ≈ **12 тактов Clk** (≈ 100+ тактов `hsClk`).

## 6. Цепочка переноса (carry chain)

```systemverilog
assign npulses = ((Nines[d] & (state == INC)) |
                  (Zeroes[d] & (state == DEC))) ? pulses : 2'b0;
```

- `Zeroes[d]` / `Nines[d]` — регистры (`Clk`), захватывают `Zero`/`Nine` декады **до**
  выполнения текущего шага.
- `pulses` декады 0 — это `Pulses` (импульсы шага); `pulses` декады `d` — это
  `dek[d-1].npulses` (перенос от младшей декады).
- Импульс пробрасывается в следующую декаду, если младшая декада была на 9 (инкремент)
  или на 0 (декремент) — классический заём/перенос.

То есть перенос распространяется комбинационно по всей цепочке декад **в течение того
же такта Clk**, в котором активен `state == INC/DEC`.

## 7. Запись/сброс внутри DekatronModule

`SetTopZero[2:0]` маппируется в `DekatronModule.Set[2:0] = {Set, SetTop, SetZero}`.
Внутри (`WRITE==1`):

```systemverilog
// idx == 0:
InPosDek_n[0] = ~((Set[2] & ~InPos[0]) | Set[0]);          // SetZero → позиция 0
// idx == TOP_PIN_OUT (TOP_LIMIT_MODE):
InPosDek_n[idx] = ~((Set[2] & ~InPos[idx]) | Set[1]);       // SetTop → TOP_PIN_OUT
// остальные:
InPosDek_n[idx] = ~(Set[2] & ~InPos[idx]);                  // Set → из In
```

Приоритет: `Set[0]` (ноль) и `Set[1]` (верхний предел) сильнее `Set[2]` (запись `In`).
В `Dekatron.sv` запись выполняется через `InLong` при `toWrite = |In`.

## 8. Нюансы и потенциальные проблемы текущей реализации

1. **Протокол не Valid/Ready.** `Request` — это импульс (фронт ловится `Impulse`-ом
   `reqPulse`), а `Ready` зависит от `~Request`. Мастер обязан **сначала снять
   `Request`**, и только потом ждать `Ready`. Это квази-двухфазный handshake, а не
   классический ST-протокол.
2. **Опкод и данные не защёлкиваются.** `Dec`, `Set`, `SetZero`, `In` читаются напрямую;
   подразумевается, что мастер держит их всё время операции. Для медленного пути
   (10 тактов) это неявное требование «держать `In` стабильным», которое легко нарушить.
3. **Лишний такт на INC/DEC.** Состояния `INC`/`DEC` существуют только чтобы
   сформировать одиночный импульс; при этом физический перенос и так укладывается в один
   такт `Clk`. Можно выжать «однотактный» инкремент (п. 9).
4. **Имя `writed_n`** обманчиво (активный-высокий).
5. **Сброс декатрона.** При `Rst_n` `Cathodes <= 30'b1` (все катоды «горят»), то есть
   после мягкого сброса позиция не определена, пока не выполнен `SetZero`/`Set`/`HardRst`.
   На старте системы счётчики должны быть явно сброшены/инициализированы.
6. **`Ready` зависит от `DekatronBusy`**, но `Busy` для INC/DEC — это лишь одиночный
   Clk-импульс входных `pulses`, а не полная длительность переноса в `hsClk`. Это
   корректно только потому, что перенос < 1 такта `Clk`.

## 9. План перевода на Valid/Ready

### 9.1 Целевой контракт

Классический ST-handshake (как уже сделано для `InsnInValid`/`InsnInReady` в
`IpLine.sv` и `FirmwareLoader`):

```systemverilog
input  wire            Valid;   // запрос операции (держится до handshake)
output wire            Ready;   // счётчик готов принять операцию
input  wire            Dec;     // квалифицируется Valid
input  wire            Set;
input  wire            SetZero;
input  wire [WIDTH-1:0] In;
output wire            Zero;
output wire [WIDTH-1:0] Out;
```

Правила:

- `Accept = Valid & Ready` — передача происходит на фронте `Clk`, когда оба сигнала
  высокие.
- `Ready` **не зависит от `Valid`** (в отличие от текущего `~Request`).
- `Ready = 1` в `IDLE` (и таймер записи не активен).
- Результат операции стабилен:
  - INC/DEC — к следующему такту `Clk` после `Accept`;
  - SET/SET_ZERO/SET_TOP — к моменту, когда `Ready` снова поднимается.

### 9.2 Ключевые изменения

1. **Убрать фронт-детектор `reqPulse`.** Handshake ловится комбинационно: `Accept`.
2. **Быстрый путь сделать однотактным.** Импульс `PulseF`/`PulseR` формируется
   комбинационно из `Accept`, без промежуточных состояний `INC`/`DEC`. Это даёт
   пропускную способность 1 операция/такт и ровно то поведение, которое описано в
   постановке: «в простом случае счётчик отрабатывает сразу же в этом такте».
3. **Медленный путь оставить на таймере.** На `Accept` с SET-операцией модуль
   защёлкивает `In` и входит в SET-состояние, запускает `OneShot #(.DELAY(100))` на
   `hsClk`; `Ready` снимается на ~100 тактов `hsClk`, пока декатроны «делают своё
   грязное дело».
4. **Защёлкнуть операнды на `Accept`.** Как минимум `In_l` (для SET); `Dec`/`Set`/
   `SetZero` используются комбинационно в такте `Accept` и дальше не нужны (решение
   закодировано в состоянии/импульсе). Для единообразия защёлкиваются все.
5. **Ready перестать привязывать к `Busy`.** Для однотактного INC/DEC `Ready` обязан
   оставаться высоким в такт `Accept`. Достаточно `Ready = (state == IDLE)`
   (опционально `& ~writed_n`).

### 9.3 Эскиз рефакторенной FSM

```systemverilog
wire Accept = Valid & Ready;

// защёлкиваем данные (минимум — In для SET)
reg Dec_l, Set_l, SetZero_l;
reg [WIDTH-1:0] In_l;
always @(posedge Clk or negedge Rst_n)
  if (~Rst_n) begin Dec_l<=0; Set_l<=0; SetZero_l<=0; In_l<=0; end
  else if (Accept) begin
    Dec_l <= Dec; Set_l <= Set; SetZero_l <= SetZero; In_l <= In;
  end

// комбинационные признаки в такте Accept
wire SetTop     = TOP_LIMIT_MODE ? (Zero & Dec)   : 1'b0;
wire SetZeroInt = TOP_LIMIT_MODE ? (&TopOut & ~Dec) : 1'b0;
wire SetAny     = Set | SetTop | SetZeroInt | SetZero;

// быстрый путь: однотактные импульсы
wire PulseF = Accept & ~SetAny & ~Dec;
wire PulseR = Accept & ~SetAny &  Dec;

// запуск таймера записи
wire write_set = Accept & SetAny;
OneShot #(.DELAY(100)) writeOneShot(.Clk(hsClk), .En(write_set), .Impulse(writed_n));

localparam [1:0] IDLE=2'b00, SET_ZERO=2'b01, SET_TOP=2'b10, SET=2'b11;
reg [1:0] state, next;
always_comb begin
    next = IDLE;
    case (state)
        IDLE: begin
            if (Accept) begin
                if (Set)            next = SET;
                else if (SetZero)   next = SET_ZERO;
                else if (SetTop)    next = SET_TOP;
                else if (SetZeroInt)next = SET_ZERO;
                else                next = IDLE;      // INC/DEC — без состояния
            end
        end
        SET, SET_TOP, SET_ZERO:
            if (writed_n) next = state;                // ждём таймер
    endcase
end

assign Ready = (state == IDLE);

// окно записи — из защёлкнутого состояния + In_l
wire [2:0] SetTopZero;
assign SetTopZero[0] = ((state == SET_ZERO) & writed_n);
assign SetTopZero[1] = ((state == SET_TOP)  & writed_n);
assign SetTopZero[2] = ((state == SET)      & writed_n);

// цепочка переноса: гейтим по импульсам, а не по state
assign npulses = ((Nines[d] & PulseF) | (Zeroes[d] & PulseR)) ? pulses : 2'b0;
```

`DekatronModule.In` подключается к `In_l` (стабильные данные на всё окно записи).

### 9.4 Совместимость и потребители

Потребители, которые нужно перевести с импульсного `Request` на `Valid`-handshake:

- `IpLine.sv` — `IP_counter`, `Loop_counter` (регистры `IP_Request`, `Loop_Request`);
- `ApLine.sv` — `AP_counter`, `Data_counter` (регистры `AP_Request`, `Data_Request`).

Паттерн замены одинаковый. Было (упрощённо, `ApLine`/`IpLine`):

```systemverilog
// текущий: поднять Request, перейти в состояние, снять Request, ждать Ready
XX_Request <= 1'b1;            state <= COUNT;
XX_Request <= 1'b0;
if (XX_Ready) state <= IDLE;
```

Стало:

```systemverilog
// Valid/Ready: держим Valid, пока не случится Accept = Valid & Ready
XX_Valid <= 1'b1;              state <= COUNT;
if (XX_Valid & XX_Ready) begin
    XX_Valid <= 1'b0;          state <= IDLE;
end
```

Внешние `Ready` линий (`ApLine.Ready`, `IpLine.Ready`), вычисляемые как
`~ApRequest & ~DataRequest & ...`, заменяются на условие «все внутренние операции
завершены и линия в `IDLE`», без членов `~Request`.

### 9.5 Тесты

- `tb/tests/test_dekatron_counter.py` — переписать хелперы `handshake_increment`/
  `handshake_decrement` под `Valid`-протокол; добавить тест **back-to-back инкрементов**
  (проверка однотактного пути) и тест **стабильности `In`** при записи (после `Accept`
  мастер снимает `Valid` и меняет `In`, значение должно остаться защёлкнутым).
- `rtl/tests/Counter.sv/Counter_tb.sv` (legacy) — обновить драйвер `Request` на `Valid`.
- `ApLine_tb.sv` / `IpLine_tb.sv` / `DekatronPC_tb.sv` — обновить стимулы.

Запуск регрессии: `make -C tb test_dek_counter SIM=icarus`, затем `make -C tb regression`.

### 9.6 Порядок работ

1. Доработать `DekatronCounter.sv` (интерфейс + FSM) по п. 9.3.
2. Обновить `tb/tests/test_dekatron_counter.py`, прогнать `test_dek_counter` — убедиться
   в однотактном инкременте и корректном тайминге записи.
3. Перевести `IpLine.sv` и `ApLine.sv` на `Valid`-handshake.
4. Обновить интеграционные тесты (`test_ip_line`, `test_ap_line`, `test_dpc`) и legacy
   SystemVerilog-тестбенчи.
5. Прогнать `make -C tb regression`.

### 9.7 Ожидаемый результат

- INC/DEC: **1 операция за такт Clk** (Ready не снимается), физический перенос
  по-прежнему внутри одного такта `Clk`.
- SET/SET_ZERO/SET_TOP: `Ready` снимается на **N = 100 тактов hsClk** (≈ 10 тактов
  `Clk`), после чего снова поднимается — ровно та семантика, что описана в постановке.
- Устранены неявные требования «держать `Request`/`In`» — операнды защёлкиваются по
  handshake.
