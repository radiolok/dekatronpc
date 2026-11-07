# 3 платы / 24 мм / 65,6 м³/ч — первый OpenFOAM-кейс

Пробный сопряжённый тепловой расчёт «продувки» стопки плат. Служит для проверки
двух вещей: (1) равномерно ли обдуваются платы, (2) уносится ли тепло и хватает
ли вентиляторов.

## Что моделируется

- **Геометрия**: 3 копии платы `sch/logic/legacy/Board_4NOR_2NOR_NOT.stl`
  (134,6 × 143,5 × 11,6 мм), шаг **24 мм** по Z (зазор 12,4 мм), обдув вдоль X.
  Бокс 340 × 160 × 66 мм (вход/выход + 4 адиабатные стенки).
- **Солвер**: `buoyantSimpleFoam` (стационарный, вынужденная конвекция +
  плавучесть), `kOmegaSST`, воздух — perfectGas.
- **Тепло**: на каждую плату 16 ламп 6Н16Б — накал 16 × 2,52 Вт = 40,3 Вт +
  анод ~16 Вт = **56,3 Вт** на плату (`externalWallHeatFluxTemperature`, mode power).
- **Поток**: 350 м³/ч — расход на ряд из 16 плат, значит на 3 платы **65,6 м³/ч**
  (0,01823 м³/с, 1,73 м/с на входе), T_входа 20 °C.

## Как запустить

```bash
source ./activate.sh                       # OpenFOAM v2206 + Intel runtime + Intel MPI
python3 make_geometry.py                   # board0..2.stl в geometry/ (в метрах)
mkdir -p constant/triSurface
cp geometry/board*.stl constant/triSurface/ # копии для snappyHexMesh
blockMesh
snappyHexMesh -overwrite
checkMesh
decomposePar -force
mpirun -np 16 buoyantSimpleFoam -parallel > log.buoyantSimpleFoam 2>&1
reconstructPar -latestTime
foamToVTK -latestTime
python3 render_vtk.py                      # картинки в images/
```

Сетка: 334 775 ячеек (база 3 мм, уровень 1 у плат ≈ 1,5 мм). Счёт на 16 P-ядрах
(E-ядра не задействуем), ≈ 3,5 мин на 1500 итераций.

## Файлы

- `make_geometry.py` — читает legacy STL, чистит дубли, пишет 3 копии в метрах.
- `render_vtk.py` — картинки (raw VTK): 3D-жгуты линий тока и температура плат.
- `activate.sh` — окружение (v2206 собран Intel-компилятором; нужны
  `/opt/intel/oneapi/compiler/2025.3/lib` и `/opt/intel/oneapi/mpi/2021.17/lib`).
- `system/`, `constant/`, `0/` — сетка, свойства, граничные условия.
- `geometry/`, `constant/triSurface/`, `constant/polyMesh/`, `VTK/`, `1500/` —
  генерируется (в git не входит, см. `../.gitignore`).
- `images/` — готовые картинки изометрии.
