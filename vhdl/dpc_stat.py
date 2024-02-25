"""Utility for DekatronPC tubes usage calculation"""

import json
import argparse
import re
import math
from liberty.parser import parse_liberty

VTUBE_CELLS = {}
DPC_MODULES = {}
STATS_MODULES = ['\\\\IpLine', '\\\\ApLine', '\\\\DekatronPC']

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
    found = get_module_name(_modules, _module_name)
    if not found:
        print(f"Warning! {_module_name} not found!")
        return 0
    _module = _modules[found]
    DPC_MODULES[found] = {}
    DPC_MODULES[found]['cells'] = {}
    DPC_MODULES[found]['area'] = 0
    DPC_MODULES[found]['heat_current'] = 0
    _cells = _module['num_cells_by_type']
    for _cell in _cells:
        _count = _cells[_cell]
        _cell_ap = VTUBE_CELLS[_cell] if _cell in VTUBE_CELLS else KNOWN_MODULES[_cell] \
            if _cell in KNOWN_MODULES else get_module_area(_modules, _cell, args)
        _area += _count * _cell_ap[0]
        _heat_current += _count * _cell_ap[1]
        DPC_MODULES[found]['cells'][_cell] = _count
        DPC_MODULES[found]['area'] += _count * _cell_ap[0]
        DPC_MODULES[found]['heat_current'] += _count * _cell_ap[1]
    if args.full:
        print(f"{_module_name} Tubes: {_area} Heat current: {_heat_current/1000}A")
    return (_area, _heat_current)

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
            area = cell_group.get_groups('ff')
            VTUBE_CELLS[name] = (cell_group['area'], cell_group['heat_current'])

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

    for module in DPC_MODULES:
        for cell in DPC_MODULES[module]['cells']:
            if cell not in CELLS_TOTAL:
                CELLS_TOTAL[cell] = 0
            CELLS_TOTAL[cell] += DPC_MODULES[module]['cells'][cell]

    print(f"=======================================================================")
    print(f"Cell\t\tCount\tTubes\tHeatCurrent")
    for cell in CELLS_TOTAL:
        if cell in VTUBE_CELLS:
            suffix = "\t" if len(cell) < 8 else ""
            print(f"{cell}{suffix}\t"\
                  f"{CELLS_TOTAL[cell]}\t"\
                  f"{VTUBE_CELLS[cell][0]*CELLS_TOTAL[cell]}\t"\
                  f"{VTUBE_CELLS[cell][1]*CELLS_TOTAL[cell]/1000}A")

    print(f"=======================================================================")
    print(f"Design\t\t\tTubes\t\tPCB\tHeatCurrent(HeatPower)")
    AREA = 0
    HEAT_CURRENT = 0
    for _item in BLOCKS:
        _area = BLOCKS[_item][0]
        AREA += _area
        _heat = BLOCKS[_item][1]/1000
        HEAT_CURRENT += _heat
        _power = _heat * 6.3
        if len(_item) < 10:
            _item += "\t"
        print(f"{_item}\t\t{_area}\
          {math.ceil(_area/16)}\t{_heat}A ({_power/1000:.02f}kW)")

    print(f"=======================================================================")
    print(f"Total\t\t\t{AREA}\
          {math.ceil(AREA/16)}\t{HEAT_CURRENT:.02f}A ({(HEAT_CURRENT*6.3/1000):.02f}kW)")
    