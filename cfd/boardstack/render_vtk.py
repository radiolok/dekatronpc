#!/usr/bin/env python3
# Render 3D isometric airflow "bundles" (tube streamlines) with raw VTK.
import vtk, os, math

CASE = "/home/radiolok/dekatronpc/cfd/boardstack"
OUT = CASE + "/images"
os.makedirs(OUT, exist_ok=True)

# --- read internal volume ---
mb = vtk.vtkXMLMultiBlockDataReader()
mb.SetFileName(CASE + "/VTK/boardstack_1500.vtm")
mb.Update()
internal = mb.GetOutput().GetBlock(0)

# --- compute velocity magnitude ---
calc = vtk.vtkArrayCalculator()
calc.SetInputData(internal)
calc.AddVectorArrayName("U")
calc.SetResultArrayName("Umag")
calc.SetFunction("mag(U)")
calc.SetAttributeTypeToPointData()
calc.Update()
internal = calc.GetOutput()

mag = internal.GetPointData().GetArray("Umag")
urange = list(mag.GetRange())
print("mag(U) range:", urange)

def make_lut(lo, hi, hue_hi=0.667, hue_lo=0.0):
    lut = vtk.vtkLookupTable()
    lut.SetHueRange(hue_hi, hue_lo)
    lut.SetSaturationRange(1.0, 1.0)
    lut.SetValueRange(0.9, 0.9)
    lut.SetRange(lo, hi)
    lut.Build()
    return lut

ulut = make_lut(urange[0], urange[1])

# --- boards (semi-transparent grey) ---
bactors = []
for i in range(3):
    r = vtk.vtkXMLPolyDataReader()
    r.SetFileName("%s/VTK/boardstack_1500/boundary/board%d.vtp" % (CASE, i))
    r.Update()
    m = vtk.vtkPolyDataMapper()
    m.SetInputData(r.GetOutput())
    a = vtk.vtkActor()
    a.SetMapper(m)
    a.GetProperty().SetColor(0.66, 0.66, 0.66)
    a.GetProperty().SetAmbient(0.35)
    a.GetProperty().SetDiffuse(0.7)
    a.GetProperty().SetOpacity(0.5)
    bactors.append(a)

# --- streamlines as thick tubes ("жгуты") ---
seed = vtk.vtkPlaneSource()
seed.SetOrigin(-0.12, 0.048, -0.003)
seed.SetPoint1(-0.12, 0.078, -0.003)   # 30 mm sector in Y (width)
seed.SetPoint2(-0.12, 0.048, 0.063)    # full Z height
seed.SetXResolution(10)
seed.SetYResolution(18)
seed.Update()

tracer = vtk.vtkStreamTracer()
tracer.SetInputData(internal)
tracer.SetSourceData(seed.GetOutput())
tracer.SetInputArrayToProcess(0, 0, 0,
    vtk.vtkDataObject.FIELD_ASSOCIATION_POINTS, "U")
tracer.SetIntegrationDirectionToForward()
tracer.SetIntegratorTypeToRungeKutta4()
tracer.SetMaximumNumberOfSteps(20000)
tracer.SetMaximumPropagation(0.6)
tracer.SetInitialIntegrationStep(0.5)
tracer.SetTerminalSpeed(1e-12)
tracer.SetComputeVorticity(False)
tracer.Update()

# cut the tails 10 mm past the board downstream edge (X = 68.58 + 10 mm)
clipPlane = vtk.vtkPlane()
clipPlane.SetOrigin(0.07858, 0.0, 0.0)
clipPlane.SetNormal(-1.0, 0.0, 0.0)
clip = vtk.vtkClipPolyData()
clip.SetInputConnection(tracer.GetOutputPort())
clip.SetClipFunction(clipPlane)
clip.Update()
ob = clip.GetOutput().GetBounds()
print("streamline bounds X: %.3f .. %.3f  points=%d" % (
    ob[0], ob[1], clip.GetOutput().GetNumberOfPoints()))

tube = vtk.vtkTubeFilter()
tube.SetInputConnection(clip.GetOutputPort())
tube.SetRadius(0.0011)
tube.SetNumberOfSides(8)
tube.CappingOn()

smapper = vtk.vtkPolyDataMapper()
smapper.SetInputConnection(tube.GetOutputPort())
smapper.SetScalarModeToUsePointFieldData()
smapper.SelectColorArray("Umag")
smapper.SetLookupTable(ulut)
smapper.SetScalarRange(urange)
sactor = vtk.vtkActor()
sactor.SetMapper(smapper)
sactor.GetProperty().SetAmbient(0.3)
sactor.GetProperty().SetDiffuse(0.8)
sactor.GetProperty().SetSpecular(0.45)
sactor.GetProperty().SetSpecularPower(40)

# --- boards coloured by temperature in Celsius, fixed 20..100 C ---
from vtk.util.numpy_support import vtk_to_numpy, numpy_to_vtk
import numpy as np

TLUT_LO, TLUT_HI = 20.0, 100.0
trange_c = [1e9, -1e9]
for i in range(3):
    r = vtk.vtkXMLPolyDataReader()
    r.SetFileName("%s/VTK/boardstack_1500/boundary/board%d.vtp" % (CASE, i))
    r.Update()
    tr = r.GetOutput().GetPointData().GetArray("T").GetRange()
    trange_c[0] = min(trange_c[0], tr[0] - 273.15)
    trange_c[1] = max(trange_c[1], tr[1] - 273.15)
print("T range boards (degC):", trange_c)
tlut = make_lut(TLUT_LO, TLUT_HI)  # cold=blue, hot=red, clamped 20..100

tactors = []
for i in range(3):
    r = vtk.vtkXMLPolyDataReader()
    r.SetFileName("%s/VTK/boardstack_1500/boundary/board%d.vtp" % (CASE, i))
    r.Update()
    o = r.GetOutput()
    T = vtk_to_numpy(o.GetPointData().GetArray("T"))
    arr = numpy_to_vtk(T - 273.15, deep=True)
    arr.SetName("Tc")
    o.GetPointData().AddArray(arr)
    m = vtk.vtkPolyDataMapper()
    m.SetInputData(o)
    m.SetScalarModeToUsePointFieldData()
    m.SelectColorArray("Tc")
    m.SetLookupTable(tlut)
    m.SetScalarRange(TLUT_LO, TLUT_HI)
    a = vtk.vtkActor()
    a.SetMapper(m)
    a.GetProperty().SetAmbient(0.3)
    a.GetProperty().SetDiffuse(0.7)
    a.GetProperty().SetSpecular(0.4)
    a.GetProperty().SetSpecularPower(30)
    tactors.append(a)

# --- scalar bars ---
def make_bar(lut, title, n=6):
    bar = vtk.vtkScalarBarActor()
    bar.SetLookupTable(lut)
    bar.SetTitle(title)
    bar.SetNumberOfLabels(n)
    bar.GetLabelTextProperty().SetFontSize(44)
    bar.GetTitleTextProperty().SetFontSize(50)
    bar.GetLabelTextProperty().SetColor(0, 0, 0)
    bar.GetTitleTextProperty().SetColor(0, 0, 0)
    bar.SetWidth(0.09)
    bar.SetHeight(0.55)
    bar.SetPosition(0.88, 0.22)
    return bar

ubar = make_bar(ulut, "|U|  m/s")
tbar = make_bar(tlut, "T, C")

# --- render window ---
ren = vtk.vtkRenderer()
ren.SetBackground(1, 1, 1)
ren.SetUseDepthPeeling(1)
ren.SetMaximumNumberOfPeels(50)

light = vtk.vtkLight()
light.SetLightTypeToCameraLight()
light.SetIntensity(0.9)
ren.AddLight(light)

rw = vtk.vtkRenderWindow()
rw.SetSize(2400, 1500)
rw.SetOffScreenRendering(1)
rw.SetMultiSamples(8)
rw.AddRenderer(ren)

CAM_FOCAL  = (0.0, 0.063, 0.028)
CAM_RADIUS = 0.55
CAM_ELEV   = 10.0    # degrees above the board plane
CAM_AZIM   = -55.0   # degrees about vertical; + = counterclockwise (from above)

# original isometric view, its own camera for the temperature image
ISO_POS    = (0.44, -0.40, 0.36)
ISO_FOCAL  = (0.02, 0.06, 0.028)

def set_cam(pos, focal):
    c = ren.GetActiveCamera()
    c.SetPosition(*pos)
    c.SetFocalPoint(*focal)
    c.SetViewUp(0, 0, 1)
    c.SetClippingRange(0.05, 2.5)

def low_angle_pos():
    el = math.radians(CAM_ELEV)
    az = math.radians(CAM_AZIM)
    dx = CAM_RADIUS * math.cos(el) * math.cos(az)
    dy = CAM_RADIUS * math.cos(el) * math.sin(az)
    dz = CAM_RADIUS * math.sin(el)
    return (CAM_FOCAL[0] + dx, CAM_FOCAL[1] + dy, CAM_FOCAL[2] + dz)

def save(name):
    w2i = vtk.vtkWindowToImageFilter()
    w2i.SetInput(rw)
    w2i.SetInputBufferTypeToRGB()
    w2i.ReadFrontBufferOff()
    w2i.Update()
    wr = vtk.vtkPNGWriter()
    wr.SetFileName(OUT + "/" + name)
    wr.SetInputConnection(w2i.GetOutputPort())
    wr.Write()
    print("wrote", OUT + "/" + name)

set_cam(low_angle_pos(), CAM_FOCAL)

# image 1: 3D tube streamlines + grey boards
for a in bactors:
    ren.AddActor(a)
ren.AddActor(sactor)
ren.AddActor2D(ubar)
rw.Render()
save("airflow_streamlines.png")

# image 2: temperature boards (original isometric view)
ren.RemoveActor(sactor)
for a in bactors:
    ren.RemoveActor(a)
for a in tactors:
    ren.AddActor(a)
ren.RemoveActor2D(ubar)
ren.AddActor2D(tbar)
set_cam(ISO_POS, ISO_FOCAL)
rw.Render()
save("board_temperature.png")

print("done")
