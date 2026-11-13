# Ревью RTL: гонки, неопределённое поведение, резервы по лампам (2026-11-13)

Задача владельца: пройти RTL проекта и выявить (1) потенциальные гонки, (2) неопределённое
поведение, (3) возможности сократить число ламп. Просмотрено ядро целиком
(`DekatronPC`, `MachineCtrl`, `IpLine`, `ApLine`, `IpMemory`/`RAM`, `ClkTree`,
`DekatronCounter`, `DekatronModule`, `DekatronPhaseGen`, `DekatronPulseSender`,
`WriteLineDec`, обе модели декатрона, ячейки `rtl/Logic`) и слой эмулятора
(`Emulator.sv`, `io_key_display_block`, `MS6205`, `Sequencer`, `uart_*`, `RstTimeRelay`).
Инструменты: чтение кода, `verilator --lint-only -Wall`, Quartus `quartus_map`
(по просьбе владельца), целевые Icarus-тесты на `DekatronPC_tb` (сценарии ниже),
`synth_seeds.sh -s "0 1 2 3"` для оценок по лампам, в конце — полная регрессия (§6).

Состояние на входе: ветка `release-width-ip4-ap3`, TRS v0.63, `run_tests.sh -s`:
IpLine 313.0, ApLine 368.0, MachineCtrl 224.0, всего **905.0** (917.0 с 12 А110).

## 0. Сводка

| № | Что | Класс | Тяжесть | Подтверждение |
|---|---|---|---|---|
| F1 | Останов на скобке теряет промотку: в пошаговом режиме (и по клавише Halt в `S_IDLE`) `[` при нулевой ячейке не перепрыгивает цикл, `]` при ненулевой не возвращается | неопределённое/неверное поведение | **высокая** | Icarus, §1.1 |
| F2 | Клавиша `InsnLoadingStart` сразу после Hard Reset (IP = 9990) пишет в защищённую декаду загрузчика: 10 опкодов молча теряются, `mem_err` никуда не идёт | неверное поведение | средняя | Icarus, §1.2 |
| F3 | Остановить зависшую загрузку клавишами Halt/InsnLoadingStop нельзя: проверка стоит под `go`, а `go` ждёт опкод | поведение | средняя | чтение кода, §1.3 |
| F4 | Линии сброса асинхронны и входят в D всех триггеров автоматов через `rst_line`/`go`: по фронту реле один такт автомат может быть в смешанном коде | гонка (известная частично) | низкая, безвредная | анализ, §1.4 |
| F5 | В прошивке ПЛИС `DekatronPC` стоит без `EN_EMULATOR=1`: второй порт памятей и `IRET` отключены, экраны IRAM/DRAM на МС6205 читают нули | эмулятор | низкая | Quartus-отчёт, §4 |
| F6–F8 | Косметика эмулятора: двоичный `ms6205Pos` в BCD-адресе, недовыведенный `inIPHigh[9]`, защёлки в `consul.sv` | эмулятор | низкая | Quartus/lint, §4 |
| T1–T3 | Измеренные резервы: мёртвая ветка переполнения в `IpLine` (−2), `halt_pending_q` → `halt_rq` (−10), `hard_rst_req` не нужен (−3) | лампы | ≈ −15 суммарно | синтез, §2 |
| T4–T8 | Неизмеренные идеи: EOT хранить в памяти (−4), признак нуля ячейки от памяти (−5), клавиша Stop = Halt (−4) и др. | лампы | ≈ −13 | оценка, §2.3 |

Ничего в дереве не правлено: все варианты измерены на копиях файлов вне дерева, тестовые
сценарии лежат в этом отчёте (§5). Решения — за владельцем (§7).

## 1. Гонки и неопределённое поведение

### 1.1. F1: останов на скобке теряет промотку (высокая)

**Где.** `MachineCtrl.sv` S_DECODE для `[`/`]`: `state_d = ~data_zero_valid ? S_EXEC : one_step ? S_HALT : S_IDLE`;
для `{ }`/NOP — `default: one_step ? S_HALT : S_IDLE`; после TEST — `s_next = (halt_key_s | one_step) ? S_HALT …`;
в S_IDLE — `if (halt_key_s) state_d = S_HALT` раньше выдачи `ip_valid`.
`IpLine.sv` S_IDLE при `halt_rq`: `(ip_counted_q & ~ip_ahead) ? S_IP : S_HALT` — только шаг IP, решение о промотке
(`scan_req`) принимается лишь в ветке `accept`, а `ready` снят при `halt_rq`.

**Что происходит.** Скобка «исполнена» только тогда, когда IpLine принял следующий запрос выборки и по
`loop_val_zero` решил: промотать или шагнуть. Если между декодом скобки и этим запросом машина уходит в
останов (пошаговый режим — всегда; клавиша Halt — если успела к S_IDLE), IpLine делает обычный шаг останова
на IP + 1, и после пуска исполняется тело цикла.

**Проверка** (Icarus, `DekatronPC_tb` + сценарий §5.1, программа `[+.]HE`, ячейка 0, загрузчик ставит NOP по адресу 0):

```
  loaded, halted: IP=0000 Insn=1
  step 1: IP=0001 Insn=0   (NOP)
  step 2: IP=0002 Insn=6   <- после [ ожидался IP=0004 (парная ]), получен 0002
  step 3: IP=0003 Insn=8 data=001
  TX: (1)                  <- тело цикла исполнено, символ напечатан
  FAIL: step mode executed the body of [ ] although the cell was 0
```

В режиме Run та же программа ничего не печатает (`run_tests.sh -t/-d` это и проверяют). Веб-симулятор
(`web/dpc.js:155`) про клавишу Halt пишет «RTL: a pending loop scan is ignored», то есть расхождение с
RTL в нём воспроизведено, но как особенность, а не как ошибка; для пошагового режима оно нигде не описано.
Ни один тест пошаговый режим на скобках не покрывает (`MachineCtrl_tb.check_step_halt` — программа `+ .`).

**Предложение.** Исправлять в IpLine, не в MachineCtrl: в ветке `halt_rq` состояния S_IDLE при
`ip_counted_q & ~ip_ahead & ~insn_loading & scan_req` начинать промотку (`S_LOOP`, `scanning_d`, `dir_d`),
как в ветке `accept`, вместо шага S_IP. Промотка кончается в S_IP при `scan_done` → S_IDLE, там
`halt_rq` ещё поднят, `ip_counted_q` уже снят при входе в останов, значит дальше S_HALT без шага, и после
пуска парная скобка читается заново и декодируется как обычно. Признак `loop_val_zero` в этот момент
достоверен: по `[`/`]` машина приходит в останов либо после TEST, либо при `data_zero_valid`; по `{ }`
он комбинационный с AP. Случай `ip_ahead = 1` (упреждающая выборка) не затронут: там IP уже стоит на
следующей, не декодированной инструкции. Цена: условие `~insn_loading & scan_req` уже есть, добавляется
мультиплексор перехода; оценка +2…+5 ламп (не измерено). Тест: добавить скобку в `check_step_halt`
и сценарий §5.1 в `DekatronPC_tb` (с ожиданием IP = 4 после второго шага).

### 1.2. F2: загрузка с пульта сразу после Hard Reset пишет в декаду загрузчика (средняя)

**Где.** После Hard Reset IP = 9990, машина в S_HALT. Клавиша `InsnLoadingStart` → `insn_loading = 1`,
S_IDLE, запрос выборки; IpLine с `ip_counted_q = 0` идёт прямо в S_INSN_IN и пишет первый опкод по текущему
адресу (REQ-LOAD-001/004). `IpMemory` поднимает `err` на запись в область загрузчика (`wr & ovl_active`),
запись не выполняется, но `insn_in_ready` рукопожатие отдаёт, и IP шагает дальше. `mem_err` у IpLine
в `lint_off UNUSEDSIGNAL`, на пульт не выведен (REQ-RST-005: флагов ошибок пока нет).

**Проверка** (сценарий §5.2, та же программа из 7 опкодов):

```
  halted: IP=9990
  opcode 0 accepted at IP=9990  mem_err=0   (err приходит тактом позже)
  opcode 6 accepted at IP=9991  mem_err=1
  …
  opcode b accepted at IP=9996  mem_err=1
  handshakes=7, final IP=9997
```

Вся программа потеряна, машина остановилась, ошибки никто не видел. Штатный путь (загрузчик `0<{0<}`
с LD на 9999 → загрузка с 0) этого не задевает, но пульт позволяет нажать клавишу в любом состоянии.

**Варианты.** (а) Вывести `mem_err` обеих памятей на лампочку пульта, как `loop_overflow` (TC-N2), и
при ошибке держать её до сброса; (б) запретить `InsnLoadingStart` при `is_bootloader` (IpMemory уже
считает признак) — но это требование к пульту; (в) описать в TRS, что ручная загрузка допустима только
после Soft Reset. Рекомендую (а) + (в); (б) — решение владельца.

### 1.3. F3: зависшую загрузку нельзя остановить с пульта (средняя)

`MachineCtrl` S_FETCH_W: `if (go) begin if (insn_loading & (key_insn_loading_stop_s | halt_key_s)) … S_HALT`.
Пока источник не выдал опкод, IpLine стоит в S_INSN_IN, `ip_ready = 0`, `go = 0`, и клавиши не читаются.
С клавиатурной загрузкой это значит: нажал Stop — ничего; набрал ещё один опкод — он записан в память, и
только тогда машина остановилась. Выход только через сброс. В TRS требования на момент действия клавиши нет.

**Предложение.** Вынести проверку клавиш из-под `go`: `else if (insn_loading & (stop | halt)) → S_HALT, insn_loading_d = 0`.
IpLine в S_INSN_IN по `~insn_loading` уходит в S_IDLE, дальше обычный шаг останова. Рукопожатие с
источником в том же такте не ломается: `insn_in_ready` снимается только со следующего фронта. Цена ≈ 0
(условие то же, меняется только приоритет). Побочный эффект: клавиша действует до записи текущего
опкода, а не после — это и есть ожидаемое поведение.

### 1.4. F4: асинхронные линии сброса в логике переходов (низкая, безвредная)

`soft_rst`/`hard_rst` держит реле времени и поднимает их в любой момент такта. В `MachineCtrl`
они входят в `go` (`~rst_line`), в `if (rst_line)` ветку всех `*_d`, в `tx_vld`; в `DekatronCounter`
`ready = ~rst_active` → `go` IpLine/ApLine. На фронте линии, попавшем в окно установки, часть триггеров
защёлкнет «S_RST_WAIT», часть — обычное следующее состояние: один такт автомат в произвольном коде.
Почему безвредно: линия держится ≥ 100 тактов, и на следующем фронте все триггеры в S_RST_WAIT;
`tx_vld` замаскирован `~rst_line`; случайное S_RST_REQ даёт импульс `rst_rq_q` в уже сработавшее реле;
`ip_valid`/`ap_valid` обрываются посреди такта — шаг декатрона недоделан, но линия сброса всё равно
переписывает разряд по катоду (модель: запись с подкатода идёт на цель). Спад линии безопасен: в
S_RST_WAIT D автомата не зависит от `rst_line`, выход — по синхронизированному `rst_busy_s`
(doc/external_inputs_falling_edge.md §5, TRS v0.49).

Рекомендация: зафиксировать это рассуждение в `MachineCtrl.sv` рядом с синхронизаторами (сейчас там
описан только спад). Синхронизировать сам `rst_line` (один DFFP, 3,5 лампы) не нужно.

### 1.5. Что проверено и замечаний не вызвало

- Valid/Ready: ни один `ready` не зависит от `valid` (`DekatronCounter.ready = ~rst_active`,
  `IpLine.ready = S_IDLE & ~halt_rq & go & ~overflow_q`, `ApLine.ready = S_IDLE & go`, `Ram.ready = ~busy`);
  `valid`, зависящие от `ready` (`mem_valid = … & go`), допустимы.
- Упреждающая выборка: скобки и CIN не выбирают заранее; `op_q` держится до `ready` ApLine; при останове
  с `pf_q = 1` IpLine не шагает (`ip_ahead`), после пуска та же инструкция читается заново
  (`MachineCtrl_tb.check_step_halt`, `IpLine_tb` 5a).
- CIN: `rx_rdy = in_wait & is_cin & go` поднимается на такт позже записи счётчика; источник держит
  `rx_data_bcd` до рукопожатия (REQ-UART-008), буфер эмулятора это соблюдает.
- COUT/эхо: `tx_vld`/`tx_rdy` через регистр по спаду в эмуляторе; двойной выдачи нет, занятый UART
  задерживает автомат в S_COUT.
- Промотка: направление в `dir_q` ставится в такте `accept` и читается с S_LOOP; счётчик вложенности
  самоочищается; переполнение ловится до шага (REQ-CNT-007) и снимает `ready` до сброса (TC-N2).
- MemLock: единственный флаг владения, выгрузка перед сменой адреса, `rd_data` памяти как копия ячейки
  (doc/memlock_single_flag.md) — переходы ApLine соответствуют.
- DekatronCounter: `set` приоритетнее автопереходов; `zero_q`/`at_top_q` защёлкнуты по фронту, живые
  катоды внутри такта не читаются; защёлки разрешений переноса берут `dec` в конце окна команды
  (TRS v0.60); `rst_to_zero`/`rst_to_nine` взаимоисключающи по построению `RstTimeRelay`.
- Модели декатрона: инерционные задержки отсекают иголки; запись с подкатода идёт на цель;
  `DEKATRON_RANDOM_INIT` выбирает только катоды с линией (TC-N1).
- `RamGroup.digit_q` инициализирован нулём, `rd_data` = 0 до первого обращения — иначе `data_zero` X
  доходил бы до IpLine (doc/synth_sim.md §4.1); сквозная запись через `wr_q`/`byp_q`.
- Lint `verilator -Wall` с `rules.vlt` по DekatronPC и Emulator: чисто (без `rules.vlt` — только
  `PINCONNECTEMPTY` на пустых `QN` и `DECLFILENAME` для `KEYDB_N16` в `IpLine.sv`).
- `IpLine.S_IDLE`: ветка `scan_req & loop_at_top` (повторное переполнение) недостижима — см. T1.

## 2. Резервы по лампам

### 2.1. Измерено (`synth_seeds.sh -s "0 1 2 3"`, среднее четырёх зёрен; варианты — копии файлов вне дерева)

| ID | Изменение | Блок | База | Вариант | Δ |
|---|---|---|---|---|---|
| T1 | Убрать мёртвую ветку S_IDLE `scan_req & loop_at_top → overflow` | IpLine | 313.3 | 311.0 | **−2.3** |
| T2 | `halt_pending_q` (DFF_J2N16, 7 ламп) заменить на `halt_rq` в S_IP | IpLine | 313.3 | 303.3 | **−10.0** |
| T1+T2 | вместе | IpLine | 313.3 | 300.5 | **−12.8** |
| T3 | `soft_rst_req = rst_rq_q`, `hard_rst_req = 0`, убрать `rst_soft_d = 1` в S_DECODE | MachineCtrl | 219.1 | 216.2 | **−2.9** |
| — | S_CIN_WAIT слить с S_EXEC (10 состояний → 9) | MachineCtrl | 219.1 | 218.5 | −0.6, шум |

По зёрнам: база IpLine 313/314/313/313, T1+T2 301.5/300.5/300/300; база MachineCtrl 224/219/220.5/213,
T3 217.5/215/215.5/217.

Почему корректно:

- **T1.** После переполнения `overflow_q` снимает `ready` до сброса, а сброс обнуляет счётчик вложенности;
  промотку нельзя прервать (S_IDLE не достигается до `scan_done`), поэтому вне промотки счётчик всегда 0
  и `loop_at_top` в S_IDLE не бывает. Поведение не меняется.
- **T2.** S_IP достигается из S_IDLE по `accept` (тогда MachineCtrl в S_FETCH_W/S_WAIT, `halt_rq = 0`),
  из промотки (`halt_rq = 0`, S_FETCH_W не уходит в останов без `go`) или из ветки останова
  (`halt_rq = 1`). Единственное отличие: если Run нажат в тот же такт, что и вход IpLine в S_IP по
  останову (MachineCtrl покинул S_HALT через один такт после входа), IpLine сделает шаг и чтение, а затем
  по `ip_counted_q = 0` прочитает ту же инструкцию ещё раз — лишнее обращение к памяти, результат тот же.
- **T3.** Машина сама никогда не запрашивает аппаратный сброс: S_RST_REQ достигается только из EOT с
  `rst_soft_d = 1`; `hard_rst_req` тождественно 0, `rst_soft` нужен лишь в S_RST_WAIT для `run_on_rst`,
  где его ставит ветка `rst_line` (`~hard_rst`). Порт `hard_rst_req` DekatronPC → RstTimeRelay остаётся
  (константа), Приложение B не затронуто.

Проверки вариантов: `IpLine_tb` на T1+T2 — PASS (400 выборок, 131 промотка, останов и ручные шаги);
`MachineCtrl_tb` на T3 — PASS (ISA, CIN, загрузка, сбросы, переполнение, пошаговый останов);
`DekatronPC_tb` helloworld (загрузчик → EOT → Soft Reset → `Hello World!`, `check_ip_moving`) на
T1+T2+T3 — PASS. Полная регрессия на вариантах не гонялась — они не в дереве.

### 2.2. Исправление F1 стоит ламп

Промотка из ветки останова (§1.1) добавляет мультиплексор перехода в S_IDLE: оценка +2…+5. С T1+T2+T3
чистый выигрыш остаётся ≈ −10…−13.

### 2.3. Не измерено (оценки, нужны решения владельца)

| ID | Идея | Δ (оценка) | Что задевает |
|---|---|---|---|
| T4 | EOT (LD в потоке загрузки) **писать** в память как обычный опкод и убрать `eot_q` + гейт `~end_of_transmission` на `mem_valid`; MachineCtrl в режиме загрузки считает концом `insn == 0xB` | −4…−5 | TRS §6.2 «в память не пишется», AGENTS §3. После программы в памяти остаётся LD — файлы и так кончаются `HE`, HALT стоит раньше. Риск: программа ровно до 9989 запишет LD в 9990 → `err` |
| T5 | Признак нуля ячейки отдавать с платы памяти: диодное ИЛИ 10 выходов усилителей считывания (германий в обвязке ферритовой памяти разрешён REQ-AUTH) вместо 10-входового И на инверсной шине в ApLine | −5 | Интерфейс `Ram` (новый выход `rd_zero`), REQ-PR-019 (провод в разъёме) |
| T6 | Клавиша `InsnLoadingStop` = Halt: убрать синхронизатор `syncLdStp` и ИЛИ в S_FETCH_W | −4 | Приложение B (`InsnLoadingStop`), пульт |
| T7 | `key_mode` без `& halt_rq` и `& insn_loading`: ручной шаг IP в такт пуска просто исполняется | −1…−2 | Поведение клавиш в граничном такте |
| T8 | `rx_vld` терминала сразу в `ap_valid` (сейчас так и есть) — проверено, резерва нет | 0 | — |

Старые списки (`doc/tube_count_below_1000.md` §8, `doc/tube_count_1000.md` §6–7) перепроверены: TC-N4
(«шаг, потом выборка», −34), TC-N6 (матрица записи совпадением), TC-O4 (CIN через шину памяти), TC-O6
(без клавиш ±IP), TC-O8 (без упреждающей выборки) по-прежнему самые крупные и по-прежнему требуют
решений владельца; новых структурных резервов того же масштаба в текущем RTL не видно: автоматы уже
минимальны по состояниям, триггеры — DFFP где позволяет fanout, счётчики — одна защёлка на декаду.

## 3. Что не является ошибкой, но стоит знать

- `MachineCtrl` S_HALT: пока `one_step` поднят (клавиша Step ещё нажата), Run и InsnLoadingStart
  переводят только флаги, но не состояние; после отпускания Step их надо нажать снова. Особенность пульта,
  не баг.
- `IpLine.mem_err`, `ApLine.mem_err`, `mem_rd_valid` не используются (`lint_off`): в ламповой машине
  ошибка памяти никак не проявляется (см. F2).
- `DekatronCounter` при `WRITE = 0` и `set = 1` — пустая операция, ловится только ассертом; все три
  такие счётчика (`IP`, `Loop`, `AP`) подают `set = 0` константой.
- `io_key_display_block.inIPHigh` объявлен `[0:9]`, заполняется `[0:8]`, читается до `[5]` — недовыведенный
  элемент не читается (F7).
- `MS6205` подставляет `ms6205Pos` (двоичный 0…159) в младшие тетрады `ipAddress1`/`apAddress1`:
  тетрады A…F банк считает недопустимыми и отдаёт 0 (F6). Косметика отладочного экрана.

## 4. Quartus (`build_fpga.sh syn`, quartus_map, Cyclone V)

Синтез прошёл (ALM ≈ 3375, регистров 3993, памяти 51 280 бит). Предупреждения, относящиеся к RTL:

| Сообщение | Где | Оценка |
|---|---|---|
| 10240 inferring latch(es) for `iret` | `MachineCtrl.sv` always_ff `iret` | Не защёлка: `EN_EMULATOR = 0` делает инкремент мёртвым, Quartus видит регистр, который только держится. Исчезнет с `EN_EMULATOR = 1` или под `generate`. Связано с F5 |
| 10240 latches `kb_data_o`, `kb_data_vld`, `set_kb_block`, `set_tab` | `Emulator/consul.sv:98` | Настоящие защёлки в `always_comb` без значений по умолчанию; legacy-консул, только эмулятор |
| 10030 Net `Mem.data_a`/`waddr_a`/`we_a` has no driver | `Emulator/FirmwareLoader.sv:19` | ПЗУ выведено как ОЗУ с неподключённым портом записи; безвредно |
| 127005 Memory depth differs from MIF (256 vs 160, 1024 vs 650) | `MS6205`, `FirmwareLoader` | Массивы не кратны 2ⁿ; хвост нулями, безвредно |
| 14320 Synthesized away RAM nodes | `AsciiToBcd` | Таблица ASCII→BCD выведена в блок памяти и частично вырезана; безвредно |
| 10335 Unrecognized attribute `keep_hierarchy` | `DekatronModule.sv:134` | Атрибут Yosys; безвредно |
| 21074 10 input pins do not drive logic | `FPGA_CLK2/3_50`, `KEY[1]`, `SW[3:0]`, `keyboard_data_in[6:5]`, `ms6205_ready` | Невостребованные входы платы; `ms6205_ready` объявлен, но дисплей его не ждёт |
| 13024 Output pins stuck | `LED[7]` (нет драйвера), `io_address[2:1]`, `io_enable_n[0]`, `pwr_selector` | Константы по конструкции |
| 10036 assigned but never read | `DekatronCounter.sv:297-298` (`hard_*`/`base_*`), `WriteLineDec.sv:92` (`xb`), `RAM.sv:490`, `DekatronTubeV2.sv:156` | Зависят от параметров; уже помечены `lint_off` |
| 10230 truncated 32 → N | `uart_*`, `consul`, `UpCounter`, `MS6205` | Неразмерные литералы в арифметике; косметика |

Гонок и неопределённости по тракту DekatronPC Quartus не показал. Полный компиляционный прогон
(fit/sta) не запускался: он просился отдельно, а последний результат (коммит 3052186) — положительный slack.

**F5.** `Emulator.sv` инстанцирует `DekatronPC` без `#(.EN_EMULATOR(1'b1))` (Verilator-тест ставит
`-GEN_EMULATOR=1'b1`, qsf — нет). В прошивке `EN_DBG_PORT = 0`: `RomData1`/`ApData1` = 0, `IRET` = 0, и
экраны IRAM/DRAM на МС6205 показывают нули. Если это сделано ради блоков памяти (второй порт удваивает
их), стоит записать как решение; иначе — добавить параметр в инстанс и пересобрать.

## 5. Тестовые сценарии (вне дерева, `scratchpad/steptest/`)

Оба — копия `tests/DekatronPC.sv/DekatronPC_tb.sv` с заменой `check_ip_moving()` на свой сценарий,
сборка как в `run/emul` (`iverilog -g2012 -DIPMEMFILE -DSIMPLEBOOT -DNO_VCD -DPROGRAM_PATH=…`,
плюс `Functions/BcdToAscii.sv`). Программа `[+.]HE` → `step.hex` = `6 2 8 7 1 b`.

### 5.1. Пошаговый режим на скобке (F1)

```systemverilog
task automatic press_step();
    @(negedge Clk); Step <= 1'b1; repeat (4) @(negedge Clk); Step <= 1'b0; repeat (4) @(posedge Clk);
endtask

task automatic check_step_bracket();
    RunOnHardRst <= 1'b0; RunOnSoftRst <= 1'b0; SoftRstOnEOT <= 1'b1;
    hard_rst_key(); press_run();
    @(posedge InsnInLoading); @(negedge InsnInLoading);
    wait_relay(); wait_halted();                       // загружено, Soft Reset, IP = 0
    for (int i = 0; i < 4; i++) begin
        press_step(); wait_halted(); repeat (30) @(posedge Clk);
        $display("  step %0d: IP=%h Insn=%h data=%h tx_count=%0d", i+1, ~IpAddress, Insn, ~tx_data_bcd, tx_q.size());
    end
    if (tx_q.size() != 0) begin errors++; $display("FAIL: step mode executed the body of [ ]"); end
endtask
```

Ожидание после исправления: шаг 2 → `IP=0004 Insn=7`, шаг 3 → `IP=0005 Insn=1` (HALT), `tx_count=0`.

### 5.2. Загрузка с пульта после Hard Reset (F2)

```systemverilog
task automatic check_load_after_hard_rst();
    int hs = 0;
    RunOnHardRst <= 1'b0; RunOnSoftRst <= 1'b0; SoftRstOnEOT <= 1'b0;
    hard_rst_key();                                    // IP = 9990
    @(negedge Clk); InsnLoadingStart <= 1'b1; repeat (4) @(negedge Clk); InsnLoadingStart <= 1'b0;
    fork
        begin : watch
            forever begin @(posedge Clk);
                if (InsnInReady & InsnInValid) begin hs++;
                    $display("  opcode %h accepted at IP=%h  mem_err=%b", InsnIn, ~IpAddress, dekatronPC.ip_mem_err); end
            end
        end
        begin @(negedge InsnInLoading); repeat (10) @(posedge Clk); disable watch; end
    join
    $display("  handshakes=%0d, final IP=%h", hs, ~IpAddress);
endtask
```

## 6. Регрессия (конец сессии, по требованию владельца)

Дерево не менялось (варианты §2 — вне дерева), прогон подтверждает исходное состояние ветки:

| Прогон | Результат |
|---|---|
| `run_tests.sh -t` | Icarus Dekatron/Counter/IpLine/ApLine/MachineCtrl/DekatronPC PASS; Verilator шаг в шаг с dpcrun: helloworld, program, pi.bfk (221 386 инструкций, вывод `3.141`) PASS |
| `run_tests.sh -d` (delay-модель) | все PASS, pi.bfk 27,45 мс модельного времени |
| `cd tb && make regression SIM=icarus` | 34/34 PASS |
| `synth_sim.sh` | 7/7 PASS |
| `synth_sim.sh -t` | 4/4 PASS, 0 setup / 0 hold / 0 masked |
| `run_tests.sh -s` | IpLine 313.0, ApLine 368.0, MachineCtrl 224.0; **905.0** ламп (6Н16Б 544.5, 6Ж2Б 312.0, 6Х7Б 48.5), с 12 А110 — **917.0**; накал 294.75 А (1.86 кВт) |
| `synth_sim.sh -p` (helloworld, program) | PASS; program.bfk: 2502 Вт ср. (накал 1827 Вт / 290 А, +150 В анод 545 Вт + экранные 113 Вт, −50 В 15 Вт, +350 В декатроны 3 Вт), пик ≤ 2564 Вт |
| `synth_sim.sh -p -n Pi` | PASS; pi.bfk 27,45 с модельного времени: 2505 Вт ср. (анод 549 Вт, экранные 112 Вт), пик ≤ 2564 Вт; по блокам ApLine 1022, IpLine 865, MachineCtrl 615 Вт |
| `synth_seeds.sh -s "0 1 2 3" IpLine MachineCtrl` | база: 532.3 среднее (IpLine 313.3, MachineCtrl 219.1) |
| Quartus `build_fpga.sh syn` | прошёл, предупреждения в §4; полный compile не запускался |

Отчёты потребления: `rtl/run/synth_sim_power/DekatronPC/DekatronPC_{hello,program,pi}_power.md`.

## 7. Вопросы владельцу

1. F1: исправлять промотку из ветки останова IpLine (предложение §1.1)? Это меняет поведение клавиши
   Halt тоже: останов на скобке будет стоять на парной скобке, а не на следующей инструкции — веб-симулятор
   (`dpc.js haltKey`) и `dpcrun` потребуют того же.
2. F2: лампочка ошибки памяти на пульте (а) и/или запрет загрузки в декаду загрузчика (б)?
3. F3: клавиши Stop/Halt действуют во время ожидания опкода (перенос проверки из-под `go`)?
4. T1–T3 вносить? T2 меняет поведение только в граничном такте Run-после-Halt (лишнее чтение).
5. T4 (EOT в памяти) и T5 (признак нуля с платы памяти) — требуют правки TRS/интерфейсов; интересны ли?
6. F5: `EN_EMULATOR` в прошивке — намеренно выключен?
