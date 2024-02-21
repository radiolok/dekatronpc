import sys
import json
import argparse
import re
import math
from liberty.parser import parse_liberty

vtube_cells = {}


known_modules = {
    'Dekatron' : (1, 0),
    'DekatronCarrySignal' : (7.5, 2400),
    'DekatronPulseSender' : (1.5, 400),
    'OneShot': (1, 400)
}

statistics_modules = ['\\\\IpLine', '\\\\ApLine', '\\\\DekatronPC']


def getModuleName(modules, moduleName):
    mn = re.sub('\\\\','', moduleName)
    for item in modules:
        itemf = re.sub('\\\\', '', item)
        if mn == itemf:
            return item

dpc_modules = {}

def getModuleArea(modules, moduleName, args):
    area = 0
    heat_current = 0
    found = getModuleName(modules,moduleName)
    if not found:
        print(f"Warning! {moduleName} not found!")
        return 0
    module = modules[found]
    dpc_modules[found] = {}
    dpc_modules[found]['cells'] = {}
    dpc_modules[found]['area'] = 0
    dpc_modules[found]['heat_current'] = 0
    cells = module['num_cells_by_type']
    for cell in cells:
        count = cells[cell]
        cellAP = vtube_cells[cell] if cell in vtube_cells else known_modules[cell] if cell in known_modules else getModuleArea(modules, cell, args)
        area += count * cellAP[0]
        heat_current += count * cellAP[1]
        dpc_modules[found]['cells'][cell] = count
        dpc_modules[found]['area'] += count * cellAP[0]
        dpc_modules[found]['heat_current'] += count * cellAP[1]
    if args.full:
        print(f"{moduleName} Tubes: {area} Heat current: {heat_current/1000}A")
    return (area, heat_current)

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--json", '-j', type=str, required=True, help="Yosys stats json file")
    parser.add_argument("--top", '-t', type=str, required=True, help="Top Module")
    parser.add_argument("--lib", '-l', type=str, required=True, help="Liberty file")
    parser.add_argument("--full", action="store_true")
    args = parser.parse_args()



    top_module = ""

    with open(args.lib, "r") as f:
        library = parse_liberty(f.read())
        # Loop through all cells.
        for cell_group in library.get_groups('cell'):
#            print(cell_group)
            name = cell_group.args[0]
            area = cell_group.get_groups('ff')
            vtube_cells[name] = (cell_group['area'], cell_group['heat_current'])

    with open(args.json, "r") as f:
        data = json.load(f)
        for item in data:
            if 'modules' in item:
                modules = data[item]
                for module in modules:
                    moduleName = re.sub('^.*?\\\\', '', module)
                    moduleName = re.sub('\\\\.*$', '', moduleName)
                    if args.top in module:
                        top_module = module
    area,heat_current = getModuleArea(modules, top_module, args)
    

    cells_total = {}

    for module in dpc_modules:
        for cell in dpc_modules[module]['cells']:
            if cell not in cells_total:
                cells_total[cell] = 0
            cells_total[cell] += dpc_modules[module]['cells'][cell]

    print("Total cells usage")
    print(f"Cell\tCount\tTubes\tHeatCurrent")
    for cell in cells_total:
        if cell in vtube_cells:
            print(f"{cell}\t{cells_total[cell]}\t{vtube_cells[cell][0]*cells_total[cell]}\t{vtube_cells[cell][1]*cells_total[cell]/1000}A")
    current = heat_current/1000
    power = current * 6.3 /1000
    print(f"{args.json}:\nTotal\t\t{area} - {math.ceil(area/16)} modules, Heat: {current}A ({power:.02f}kW)")