"""Структурные схемы DekatronPC: сборка всех листов.

    python3 tools/schemes/build.py

Собирает HTML-страницу со всеми листами в tools/schemes/out/ и
экспортирует в корень репозитория SCHEMES.md и img/schemes/*.svg
(см. export_md.py). Сверка с RTL — константа RTL_REF ниже.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
OUT = os.path.join(HERE, 'out')

# Какой RTL отражают схемы: ветка и дата сверки. Обновлять при перерисовке.
RTL_REF = 'RTL ветки claude_nextGen, 07.10.2026'

import fallback
import sheet1, sheet2, sheet3, sheet4, sheet5, sheet6, sheet7

head = open(os.path.join(HERE, 'head.html')).read()
N = 7


def fig(svg, cap):
    return f'<figure><div class="scroll">{svg}</div><figcaption>{cap}</figcaption></figure>'


def stamp(n, code, name, src):
    return f'''<div class="stamp">
<div><span class="k">Обозначение</span><span class="v">{code}</span></div>
<div><span class="k">Наименование</span><span class="v">{name}</span></div>
<div><span class="k">Источник</span><span class="v">{src}</span></div>
<div><span class="k">Лист</span><span class="v">{n}</span></div>
<div><span class="k">Листов</span><span class="v">{N}</span></div>
</div>'''


def sheet(n, sid, title, body, name, src):
    code = f"ДПК-СХ-0{n}"
    return (f'<section class="sheet" id="{sid}"><div class="sheet-body">'
            f'<span class="num">ЛИСТ {n} · {code}</span><h2>{title}</h2>{body}</div>'
            f'{stamp(n, code, name, src)}</section>')


S = []

ring_rules = '''<div class="tbl"><table class="spec">
<thead><tr><th>Разряд</th><th>Воздействие</th><th>Результат</th></tr></thead>
<tbody>
<tr><td>K<sub>k</sub> (3k)</td><td>GuideA ≥ GUIDE_STEP_HS</td><td>на подкатод A (3k+1)</td></tr>
<tr><td>A (3k+1)</td><td>GuideB ≥ GUIDE_STEP_HS</td><td>на подкатод B (3k+2)</td></tr>
<tr><td>B (3k+2)</td><td>нет стимула FALL_STEP_HS</td><td class="acc">вперёд на K<sub>k+1</sub> (3k+3)</td></tr>
<tr><td>A (3k+1)</td><td>нет стимула FALL_STEP_HS</td><td>назад на K<sub>k</sub> (3k)</td></tr>
<tr><td>любой</td><td>write_en ≥ WRITE_MIN_HS</td><td>на катод write_pos</td></tr>
<tr><td>любой</td><td>reset0 / resetN ≥ RESET_MIN_HS</td><td>на K0 / K<sub>RESET_N_POS</sub></td></tr>
</tbody></table></div>
<p>Обратный шаг симметричен: GuideB уводит разряд с главного катода на B предыдущей тройки, GuideA — на A, падение доводит до K<sub>k−1</sub>. Держать разряд на подкатоде нельзя, поэтому у лампы нет ни busy, ни ready: <code>main_onehot_o</code> достоверен, только когда разряд стоит на главном катоде и стимулов нет.</p>'''

S.append(sheet(1, "tube", "Модель декатрона DekatronTubeV2",
    '<p>Модель повторяет физику А110: кольцо из 30 электродов, один горящий бит, переходы только по длительности импульсов на подкатодах. Логика вокруг лампы не может спросить её «готова ли» — она может лишь выдержать нужные интервалы.</p>'
    + '<div class="pair">' + fig(sheet1.fig_ring(),
        '<b>Кольцо.</b> Шаг +1 из K3 в K4 за три трети такта: A, B и падение на следующий главный катод. Без второй фазы разряд падает назад.')
    + '<div style="display:grid;gap:12px;min-width:0">' + ring_rules + '</div></div>'
    + fig(sheet1.fig_tube(), '<b>Внутреннее устройство модели.</b> Таймер перемещения считает такты hsClk на подкатоде; запись и сброс имеют приоритет над шагом; дешифратор выдаёт позиционный код только на главном катоде.')
    + fig(sheet1.fig_timing(), '<b>Временная диаграмма шага.</b> Такт Clk делится на трети: Phase1 [0,3), Phase2 [3,6), падение [6,10) тактов hsClk. Разряд ложится на главный катод с запасом в один такт hsClk до следующего фронта Clk, поэтому шаг гарантированно укладывается в такт. При прежней нарезке 3/4/3 он падал ровно на фронте. Счёт идёт на каждом такте 1 МГц.'),
    "Модель декатрона А110", "DekatronTubeV2.sv"))

S.append(sheet(2, "drive", "Работа с декатроном: фазы, импульсы, модуль",
    '<p>Генератор фаз один на счётчик; формирователь импульсов стоит в каждой декаде и только направляет фазы на подкатоды в нужном порядке. Схемы записи и чтения необязательны и включаются параметрами модуля.</p>'
    + fig(sheet2.fig_gates(), '<b>DekatronPhaseGen и DekatronPulseSender.</b> Две задержки OneShot формируют окна, Phase2 = Win12·¬Win1. Шаг вперёд: GuideA ← Phase1, GuideB ← Phase2; шаг назад — наоборот. Обозначения элементов — ГОСТ 2.743.')
    + fig(sheet2.fig_module(), '<b>DekatronModule.</b> Пунктиром — блоки, которые есть только при WRITE, READ и TOP_LIMIT_MODE. Каждый подблок остаётся отдельным экземпляром для размещения и трассировки. Признака Valid у модуля нет (TRS v0.10): он показывал только «разряд на главном катоде», а не «операция закончена». Готовность выводит <code>DekatronCounter</code> по известным длительностям.'),
    "Схемы управления декатроном", "DekatronPhaseGen.sv · DekatronPulseSender.sv · DekatronModule.sv"))

S.append(sheet(3, "counter", "Декатронный счётчик DekatronCounter",
    '<p>Счётчик превращает лампы без рукопожатия в блок с Valid/Ready. Готовность выводится из длительностей, а не из показаний ламп: шаг ±1 выполняется за такт без снятия ready; запись и подъём линии сброса запускают окно WR_WINDOW_HS, и ready снят до его конца. Линии soft_rst и hard_rst — физические: их длительность держит внешнее реле, счётчик только разводит их на SetZero и SetTop нужных декад.</p>'
    + fig(sheet3.fig_counter(), '<b>Структура на трёх декадах.</b> Перенос берётся из признаков nines_q и zeroes_q, защёлкнутых по clk, поэтому цепочка step_f не замыкается комбинационно. ready не зависит от writing — так разорвана найденная ранее петля.')
    + fig(sheet3.fig_counter_fsm(), '<b>Автомат счётчика.</b> TOP_LIMIT_MODE и HARD_RST_D_CNT взаимоисключающие (OPEN-012).'),
    "Декатронный счётчик", "DekatronCounter.sv"))

S.append(sheet(4, "ipline", "Линия выборки IpLine",
    '<p>IpLine владеет счётчиком инструкций, счётчиком вложенности и памятью программ. Промотку тела цикла линия делает сама и останавливается на парной скобке; MachineCtrl получает уже следующую исполняемую инструкцию. На этом уровне нет символов — только 4-битные опкоды.</p>'
    + fig(sheet4.fig_ipline(), '<b>Структура.</b> IP на пяти декадах: hard_rst ставит 99900 (старт загрузчика), soft_rst — 00000. Детектор скобок один, на выходе регистра инструкции.')
    + fig(sheet4.fig_ipline_fsm(), '<b>Автомат.</b> Оранжевым — ветвь промотки. Переполнение счётчика вложенности ловится до шага (своя скобка при 99), обрывает промотку и выдаёт loop_overflow. Стробы счётчикам и памяти дешифрируются из состояния; пар OP/WAIT нет (REQ-IPV2-007). Счётчик — 2 декады (0…99), <code>LOOP_DEKATRON_NUM = 2</code> (REQ-CNT-002).')
    + '<div class="note"><b>Дефект, отмечен пунктиром.</b> Если halt_rq приходит, когда IP уже сдвинут под инструкцию, IDLE делает IP+1 без промотки и уходит в HALT. В шаговом режиме это ломает каждую <code>[</code> при нулевой ячейке и каждую <code>]</code> при ненулевой; в режиме Run — останов сразу после такой скобки. Исправление ждёт решения: не трогать IP при останове или промотать при останове, если текущая инструкция — скобка.</div>',
    "Линия выборки инструкций", "IpLine.sv · IpMemory.sv · RAM.sv"))

flags = '''<div class="tbl"><table class="spec">
<thead><tr><th>Операция</th><th>Когда читает память</th><th>Когда пишет память</th><th>lock · dirty · mem_here после</th></tr></thead>
<tbody>
<tr><td><code>+ −</code></td><td>нет lock и нет mem_here</td><td>—</td><td>1 · 1 · —</td></tr>
<tr><td><code>&gt; &lt;</code>, CLRA</td><td>—</td><td>если dirty</td><td>0 · 0 · 0; в ветке при dirty = 0 lock остаётся (дефект)</td></tr>
<tr><td><code>.</code> COUT</td><td>нет lock и нет mem_here</td><td>—</td><td>— · — · 1 после чтения; без lock ячейка грузится в счётчик, lock не меняется</td></tr>
<tr><td>TEST</td><td>нет lock и нет mem_here</td><td>—</td><td>— · — · 1 после чтения</td></tr>
<tr><td><code>,</code> CIN, <code>[-]</code> CLRD</td><td>—</td><td>—</td><td>1 · 1 · —</td></tr>
<tr><td>LOAD</td><td>нет mem_here</td><td>—</td><td>lock не меняется</td></tr>
<tr><td>STORE</td><td>—</td><td>всегда</td><td>— · 0 · 1</td></tr>
<tr><td>CLRML</td><td>—</td><td>если dirty</td><td>0 · 0 · —</td></tr>
</tbody></table></div>'''

S.append(sheet(5, "apline", "Линия данных ApLine",
    '<p>Ленивое чтение: ячейка читается, только когда её значение действительно нужно, и выгружается, только если счётчик её изменил. Значение берётся из выходного регистра памяти напрямую — без копирования в счётчик данных. На программе Pi это 99 077 обращений против 155 625 при предвыборке (−36 %).</p>'
    + fig(sheet5.fig_apline(), '<b>Структура.</b> Оранжевым — путь значения ячейки из выходного регистра памяти: на мультиплексор входа счётчика и на выходные признаки. data_zero_valid = lock | mem_here.')
    + fig(sheet5.fig_apline_fsm(), '<b>Автомат.</b> Оранжевым — чтение по требованию.')
    + '<div class="note"><b>Дефект, отмечен пунктиром.</b> Шаг адреса без выгрузки (dirty = 0) оставляет lock = 1, если перед этим был STORE, — и следующие <code>.</code> или <code>+</code> работают со значением прежней ячейки. Правка (сброс lock при любой смене адреса) подготовлена, в ветку claude_nextGen не внесена.</div>'
    + '<h3>Флаги и обращения к памяти</h3>' + flags,
    "Линия данных", "ApLine.sv · RAM.sv"))

S.append(sheet(6, "mctrl", "Управление машиной MachineCtrl",
    '<p>MachineCtrl дешифрует инструкцию по паре {insn_mode, insn} и выдаёт ровно одну операцию на линию выборки, линию данных, терминал или реле сброса. В Brainfuck ISA перед скобкой, если признак нуля не достоверен, он просит ApLine выполнить AP_TEST — одно чтение на проверку, не на каждый шаг промотки.</p>'
    + fig(sheet6.fig_mctrl(), '<b>Структура.</b> loop_val_zero для IpLine: в Brainfuck ISA — нуль ячейки, в Debug ISA — нуль счётчика адреса.')
    + fig(sheet6.fig_mctrl_fsm(), '<b>Автомат.</b> Стробы дешифрируются из состояния, коды операций — из insn; пар OP/WAIT нет (REQ-CTLV2-010). Вывод: «.» сначала выдаёт AP_COUT, tx_vld — по его окончании (OPEN-017).'),
    "Управление машиной", "MachineCtrl.sv"))

S.append(sheet(7, "top", "Машина целиком DekatronPC",
    '<p>Арбитраж памяти не нужен: IpLine владеет IpMemory, ApLine — Ram. Сброс счётчиков любой природы — с пульта или инструкцией — проходит через реле времени, а MachineCtrl видит сами линии и сбрасывает общее состояние машины. Различие soft и hard — только в адресе, с которого стартует IP.</p>'
    + fig(sheet7.fig_top(), '<b>Верхний уровень.</b> Оранжевым — физические линии сброса и путь значения ячейки. Второй порт чтения памятей нужен только эмулятору.')
    + '<div class="note"><b>Проверить в TOP:</b> экземпляры Ram и IpMemory не передают BANK_DIGITS и CELLS, поэтому берутся значения по умолчанию: BANK_DIGITS = 4, память данных на 100 000 ячеек — 10 банков, около 100 блоков M10K вместо 30 при CELLS = 30 000.</div>',
    "Структурная схема машины", "DekatronPC.sv"))

toc = ''.join(f'<a href="#{i}"><span>0{n}</span>{t}</a>' for n, (i, t) in enumerate(
    [("tube", "Декатрон"), ("drive", "Фазы и модуль"), ("counter", "Счётчик"), ("ipline", "IpLine"),
     ("apline", "ApLine"), ("mctrl", "MachineCtrl"), ("top", "DekatronPC")], 1))

body = ('<div class="wrap"><header class="doc"><span class="eyebrow">DekatronPC · структурные схемы · ' + RTL_REF + '</span>'
        '<h1>Ламповая машина на декатронах А110</h1>'
        '<p class="lead">Семь листов снизу вверх: от модели лампы до верхнего уровня. Схемы сверены с RTL ветки claude_nextGen; оранжевым выделено то, о чём лист, пурпурным пунктиром — найденный дефект.</p></header>'
        f'<nav class="toc">{toc}</nav>' + ''.join(S) + '</div>')
body = fallback.apply(body)
os.makedirs(OUT, exist_ok=True)
page_path = os.path.join(OUT, 'DekatronPC_schemes.html')
# фрагмент без <html>/<head> — так его публикует артефакт
open(page_path, 'w').write(head + body)
# самостоятельная страница для просмотра в браузере
open(os.path.join(OUT, 'preview.html'), 'w').write(
    '<!doctype html><html><head><meta charset="utf-8">'
    '<meta name="viewport" content="width=device-width,initial-scale=1">'
    + head + '</head><body>' + body + '</body></html>')
print('page:', page_path)

import export_md
export_md.run(page_path, os.path.normpath(os.path.join(HERE, '..', '..')), RTL_REF)
