import sys
import json
import argparse
import re
from liberty.parser import parse_liberty

vtube_cells = {}


known_modules = {
    'Dekatron' : 1,
    'DekatronCarrySignal' : 7.5,
    'DekatronPulseSender' : 1.5,
    '$_DLATCH_N_' : 2.5
}

statistics_modules = ['\\\\IpLine', '\\\\ApLine', '\\\\DekatronPC']


def getModuleName(modules, moduleName):
    mn = re.sub('\\\\','', moduleName)
    for item in modules:
        itemf = re.sub('\\\\', '', item)
        if mn == itemf:
            return item

dpc_modules = {}

def getModuleArea(modules, moduleName):
    area = 0
    found = getModuleName(modules,moduleName)
    if not found:
        print(f"Warning! {moduleName} not found!")
        return 0
    module = modules[found]
    dpc_modules[found] = {}
    dpc_modules[found]['cells'] = {}
    dpc_modules[found]['area'] = 0
    cells = module['num_cells_by_type']
    for cell in cells:
        count = cells[cell]
        cellArea = vtube_cells[cell] if cell in vtube_cells else known_modules[cell] if cell in known_modules else getModuleArea(modules, cell)
        area += count * cellArea
        dpc_modules[found]['cells'][cell] = count
        dpc_modules[found]['area'] += count * cellArea
    
    print(moduleName, area)
    return area

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--json", '-j', type=str, required=True, help="Yosys stats json file")
    parser.add_argument("--top", '-t', type=str, required=True, help="Top Module")
    parser.add_argument("--lib", '-l', type=str, required=True, help="Liberty file")
    args = parser.parse_args()



    top_module = ""

    with open(args.lib, "r") as f:
        library = parse_liberty(f.read())
        # Loop through all cells.
        for cell_group in library.get_groups('cell'):
#            print(cell_group)
            name = cell_group.args[0]
            area = cell_group.get_groups('ff')
            vtube_cells[name] = cell_group['area']

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
    area = getModuleArea(modules, top_module)
    

    cells_total = {}

    for module in dpc_modules:
        for cell in dpc_modules[module]['cells']:
            if cell not in cells_total:
                cells_total[cell] = 0
            cells_total[cell] += dpc_modules[module]['cells'][cell]

    print("Total cells usage")
    for cell in cells_total:
        if cell in vtube_cells:
            print(cell, cells_total[cell], vtube_cells[cell]*cells_total[cell])

    print("Total number of vacuum tubes:", area)