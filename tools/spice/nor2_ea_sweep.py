#!/usr/bin/env python3
"""NOR2_N16 at a lower plate supply Ea. For each (Ea, Ra): static VOL1 (one triode, grid clamped),
then a divider R1||C1/R2 to Vn chosen so HV "1"/"0" map to LV +10/-20 (LV kept), R1+R2 = 670k.
C1 per grid scaled so R1*C1 = const*R2 (same compensation as 470k/200k/3.9p). Transient: nor2_sweep chain."""
import subprocess, re, sys, os, tempfile
from multiprocessing import Pool
REPO=os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
NGRUN=f"{REPO}/tools/spice/ngrun.py"; MODEL=f"{REPO}/sch/libs/6N16B.sub"
def ng(deck):
    fd, fn = tempfile.mkstemp(suffix=".cir"); os.write(fd, deck.encode()); os.close(fd)
    o = subprocess.run(["timeout","120","python3",NGRUN,fn],capture_output=True,text=True).stdout
    os.unlink(fn)
    return {k: float(v) for k, v in re.findall(r"^(\w+)\s+=\s+([-\d.e+]+)", o, re.M)}
def static(Ea, Ra):
    d=f"""* st
.include {MODEL}
VCC vcc 0 {Ea}
VG g 0 0.3
X1 p g 0 p2 off 0 6N16B
VOFF off 0 -30
RA vcc p {Ra}
RL p nb 670k
VNB nb 0 -50
.control
op
let vol=v(p)
let ia=i(VCC)
print vol ia
.endc
.end
"""
    fd, fn = tempfile.mkstemp(suffix=".cir"); os.write(fd, d.encode()); os.close(fd)
    o = subprocess.run(["timeout","60","python3",NGRUN,fn],capture_output=True,text=True).stdout; os.unlink(fn)
    m=dict(re.findall(r"^(\w+)\s+=\s+([-\d.e+]+)", o, re.M)); return float(m['vol']), -float(m['ia'])
def nor(t,a,b,p):
    return (f"X{t} p{t} {a} 0 p{t} {b} 0 6N16B\nRA{t} vcc pl{t} {p['Ra']}\nLA{t} pl{t} p{t} 680u\nRD{t} pl{t} p{t} 10k\n")
def div(t,hv,lv,p,n):
    return f"R1{t} {hv} {lv} {p['R1']}\nC1{t} {hv} {lv} {p['C1g']*n}p\nR2{t} {lv} nb {p['R2']}\n"
def pwl(bits,lo,hi):
    pts=[];t=0
    for b in bits:
        v=hi if b else lo; pts+=[f"{t+20e-9:.3e} {v}",f"{t+2e-6:.3e} {v}"]; t+=2e-6
    return "PWL(0 %s %s)"%(lo," ".join(pts))
def tran(p,n):
    VH,VL,th=p['VH'],p['VL'],p['TH']
    s=f"""* tr
.include {MODEL}
VCC vcc 0 {p['Ea']}
VNB nb 0 {p['Vn']}
VSA sa 0 {pwl([1,0,1,0,1],VL,VH)}
VSB sb 0 {pwl([1,1,0,0,1],VL,VH)}
"""
    s+=div('sa','sa','ia',p,2)+div('sb','sb','ib',p,2)
    s+=nor('da','ia','ia',p)+div('da','pda','a',p,1)+nor('db','ib','ib',p)+div('db','pdb','b',p,1)
    s+=nor('d','a','b',p)+div('d','pd','yl',p,n)
    for i in range(n//2): s+=nor(f'l{i}','yl','yl',p)
    s+=f""".tran 5n 10u
.control
run
meas tran voh find v(pd) at=1.95u
meas tran vol1 find v(pd) at=3.95u
meas tran lvl find v(a) at=1.95u
meas tran gmin min v(a) from=0.5u to=10u
meas tran tphl trig v(a) val=-5 rise=1 targ v(pd) val={th} fall=1
meas tran tplh trig v(a) val=-5 fall=1 td=7.9u targ v(pd) val={th} rise=1 td=7.9u
meas tran lvd_hl trig v(a) val=-5 rise=1 targ v(yl) val=-5 fall=1
meas tran lvd_lh trig v(a) val=-5 fall=1 td=7.9u targ v(yl) val=-5 rise=1 td=7.9u
meas tran icc avg i(VCC) from=0 to=10u
.endc
.end
"""
    return ng(s)
def case(arg):
    Ea,Ra,n=arg
    VL,ia=static(Ea,Ra); VH=Ea-3
    r=30/(VH-VL); Vn=10-(VH-10)*r/(1-r)   # V_lv = Vn + (Vhv-Vn)*r ; Vlv(VH)=+10
    Vn=(10-r*VH)/(1-r)
    R2=670e3*r; R1=670e3-R2
    C1g=3.9*(470/200)*(R2/R1)   # keep R1*C1/R2 as in the reference divider
    p=dict(Ea=Ea,Ra=Ra,VH=VH,VL=VL,Vn=Vn,R1=f"{R1:.0f}",R2=f"{R2:.0f}",C1g=C1g,TH=(VH+VL)/2)
    m=tran(p,n)
    return Ea,Ra,n,VL,ia,r,Vn,C1g,m
if __name__=="__main__":
    jobs=[(Ea,Ra,n) for Ea,Ra in [(150,"10k"),(120,"10k"),(120,"6.8k"),(100,"10k"),(100,"6.8k"),(100,"4.7k")] for n in (2,10)]
    with Pool(6) as pl:
        for Ea,Ra,n,VL,ia,r,Vn,C1g,m in pl.map(case,jobs):
            g=lambda k,s=1:m.get(k,float('nan'))*s
            P=Ea*ia
            print(f"Ea={Ea:3d} Ra={Ra:>4s} N={n:2d} | VOL1={VL:5.1f} Ion={ia*1e3:4.1f}mA P_on={P:4.2f}W | div r={r:.3f} Vn={Vn:6.1f} C1g={C1g:3.1f}p | "
                  f"HV {g('voh'):5.1f}/{g('vol1'):4.1f} LV0 {g('lvl'):5.1f} gmin {g('gmin'):5.1f} | tpHL {g('tphl',1e9):4.0f} tpLH {g('tplh',1e9):4.0f} LV->LV {g('lvd_hl',1e9):4.0f}/{g('lvd_lh',1e9):4.0f} ns | Iavg {g('icc',-1e3):4.1f}mA")
