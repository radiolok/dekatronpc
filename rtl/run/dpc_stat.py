"""Utility for DekatronPC tubes usage calculation"""

import json
import argparse
import re
import math
from liberty.parser import parse_liberty

VTUBE_CELLS = {}
VTUBE_CELLS_DATA = {}
DPC_MODULES = {}
STATS_MODULES = ['\\\\IpLine', '\\\\ApLine', '\\\\DekatronPC']

KNOWN_TUBES = ('N16B', 'J2B', 'X7B')
# Relays are not tubes: area 0, counted separately (rtl/Logic/Relay.sv)
KNOWN_RELAYS = ('RELAY_2CO',)
VTUBE_RELAYS = {}

KNOWN_MODULES = {
    'Dekatron' : (1, 0),
    'DekatronCarrySignal' : (7.5, 2400),
    'DekatronPulseSender' : (1.5, 400),
    'OneShot': (1, 300),
    'Impulse': (1, 300)
}

def get_module_name(_modules, _module_name):
    """Remove excess symbols and return module"""
    _mn = re.sub('\\\\', '', _module_name)
    for _item in _modules:
        _itemf = re.sub('\\\\', '', _item)
        if _mn == _itemf:
            return _item
    return None


def get_module_area(_modules, _module_name, args):
    """Calculate Area usage"""
    _area = 0
    _heat_current = 0
    _relays = 0
    found = get_module_name(_modules, _module_name)
    if not found:
        print(f"Warning! {_module_name} not found!")
        return (0, 0, 0)
    _module = _modules[found]
    DPC_MODULES[found] = {}
    DPC_MODULES[found]['cells'] = {}
    DPC_MODULES[found]['area'] = 0
    DPC_MODULES[found]['heat_current'] = 0
    DPC_MODULES[found]['relays'] = 0
    _cells = _module['num_cells_by_type']
    for _cell in _cells:
        _count = _cells[_cell]
        _cell_ap = VTUBE_CELLS[_cell] if _cell in VTUBE_CELLS else KNOWN_MODULES[_cell] \
            if _cell in KNOWN_MODULES else get_module_area(_modules, _cell, args)
        _area += _count * _cell_ap[0]
        _heat_current += _count * _cell_ap[1]
        _cell_relays = VTUBE_RELAYS.get(_cell, 0) if _cell in VTUBE_CELLS else \
            _cell_ap[2] if len(_cell_ap) > 2 else 0
        _relays += _count * _cell_relays
        DPC_MODULES[found]['relays'] += _count * _cell_relays
        DPC_MODULES[found]['cells'][_cell] = _count
        DPC_MODULES[found]['area'] += _count * _cell_ap[0]
        DPC_MODULES[found]['heat_current'] += _count * _cell_ap[1]
    if args.full:
        print(f"{_module_name} Tubes: {_area} Relays: {_relays} Heat current: {_heat_current/1000}A")
    return (_area, _heat_current, _relays)

def get_flat_cells(_modules, _module_name, _acc, _mult=1):
    """Library cells of a module with its submodules, times instance count"""
    found = get_module_name(_modules, _module_name)
    if not found:
        return _acc
    for _cell, _count in _modules[found]['num_cells_by_type'].items():
        if _cell in VTUBE_CELLS:
            _acc[_cell] = _acc.get(_cell, 0) + _mult * _count
        elif _cell not in KNOWN_MODULES:
            get_flat_cells(_modules, _cell, _acc, _mult * _count)
    return _acc

if __name__ == "__main__":
    PARSER = argparse.ArgumentParser()
    PARSER.add_argument("--json", '-j', type=str, required=True, help="Yosys stats json file")
    PARSER.add_argument("--top", '-t', type=str, help="Top Module")
    PARSER.add_argument("--lib", '-l', type=str, required=True, help="Liberty file")
    PARSER.add_argument("--full", action="store_true")
    CMDARGS = PARSER.parse_args()

    with open(CMDARGS.lib, "r") as f:
        LIBRARY = parse_liberty(f.read())
        # Loop through all cells.
        for cell_group in LIBRARY.get_groups('cell'):
#            print(cell_group)
            name = cell_group.args[0]
            tubes = cell_group.get_group('tubes')['N16B']
            VTUBE_CELLS[name] = (cell_group['area'], cell_group['heat_current'])
            VTUBE_CELLS_DATA[name] = {}
            VTUBE_CELLS_DATA[name]['area'] = cell_group['area']
            for _tube in KNOWN_TUBES:
                 VTUBE_CELLS_DATA[name][_tube] = cell_group.get_group('tubes')[_tube] or 0.0
            _rel = cell_group.get_groups('relays')
            VTUBE_RELAYS[name] = sum((_rel[0][_r] or 0) for _r in KNOWN_RELAYS) if _rel else 0

    CELLS_TOTAL = {}

    CMDARGS.json = list(CMDARGS.json.split(','))

    BLOCKS = {}
    for _file in CMDARGS.json:
        print(_file)
        top_module = _file.replace('.json', '')
        with open(_file, "r") as f:
            _data = json.load(f)
            for _item in _data:
                if 'modules' in _item:
                    modules = _data[_item]
                    for module in modules:
                        moduleName = re.sub('^.*?\\\\', '', module)
                        moduleName = re.sub('\\\\.*$', '', moduleName)
                        if CMDARGS.top and CMDARGS.top in module:
                            top_module = module
        BLOCKS[top_module] = get_module_area(modules, top_module, CMDARGS)
        get_flat_cells(modules, top_module, CELLS_TOTAL)

    TUBES_TOTAL = {}
    for tube in KNOWN_TUBES:
        TUBES_TOTAL[tube] = 0.0

    print(f"=======================================================================")
    # Counts include every instance of every submodule
    print(f"Cell\t\tCount\tTubes\tHeatCurrent")
    for cell in CELLS_TOTAL:
        if cell in VTUBE_CELLS:
            suffix = "\t" if len(cell) < 8 else ""
            print(f"{cell}{suffix}\t"\
                  f"{CELLS_TOTAL[cell]}\t"\
                  f"{VTUBE_CELLS[cell][0]*CELLS_TOTAL[cell]}\t"\
                  f"{VTUBE_CELLS[cell][1]*CELLS_TOTAL[cell]/1000}A")
            for tube in KNOWN_TUBES:
                TUBES_TOTAL[tube] += VTUBE_CELLS_DATA[cell][tube] * CELLS_TOTAL[cell]
    
    print(f"=======================================================================")
    for tube in KNOWN_TUBES:
        print(f"{tube}: {TUBES_TOTAL[tube]} - TBD")

    print(f"=======================================================================")
    print(f"Design\t\t\tTubes\tRelays\tPCB\tHeatCurrent(HeatPower)")
    AREA = 0
    HEAT_CURRENT = 0
    RELAYS = 0
    for _item in BLOCKS:
        _area = BLOCKS[_item][0]
        AREA += _area
        _relays = BLOCKS[_item][2]
        RELAYS += _relays
        _heat = BLOCKS[_item][1]/1000
        HEAT_CURRENT += _heat
        _power = _heat * 6.3
        if len(_item) < 10:
            _item += "\t"
        print(f"{_item}\t\t{_area}\t{_relays}\t"\
              f"{math.ceil(_area/16)}\t{_heat}A ({_power/1000:.02f}kW)")

    print(f"=======================================================================")
    print(f"Total\t\t\t{AREA}\t{RELAYS}\t"\
          f"{math.ceil(AREA/16)}\t{HEAT_CURRENT:.02f}A ({(HEAT_CURRENT*6.3/1000):.02f}kW)")
    print(f"Relays are {', '.join(KNOWN_RELAYS)} (2 changeover contacts), not counted as tubes")
