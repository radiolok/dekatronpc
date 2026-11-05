# usage: gen2.py <out.lib> <flags: f=followers allowed, a=AND2_J2 follower, o=wired AO followers<=6, i=wired AOI<=6>
import sys,string,re
sys.argv_=sys.argv
out,flags=sys.argv[1],sys.argv[2]
src=open('/home/radiolok/dekatronpc/sch/logic/vtube_cells.lib').read()
if 'f' in flags:
    src=re.sub(r'\n\s*dont_use : true;   // cathode follower[^\n]*','',src)
def cell(name,p,t,inv,fol):
    pins=iter(string.ascii_uppercase); terms=[]; pl=[]
    for i in range(p):
        a=next(pins);b=next(pins);terms.append(f"{a}*{b}")
        pl+= [(a,'follower' if fol else 'pentode_g1',0.69 if fol else .69),(b,'follower' if fol else 'pentode_g3',0.69 if fol else 1.74)]
    for i in range(t):
        a=next(pins);terms.append(a);pl.append((a,'follower' if fol else 'triode',0.69 if fol else 1.0))
    tubes=([f"      J2B: {p};"] if p else [])+([f"      N16B: {t*0.5};"] if t else [])
    f="+".join(terms); f=f"({f})'" if inv else f"({f})"
    c=f"  cell({name}) {{\n    area: {p+0.5*t};\n    current_unit : \"1mA\";\n    heat_current: {200*(p+t)};\n    tubes(names) {{\n"+"\n".join(tubes)+"\n    }\n"
    for n_,g,l in pl: c+=f"    pin({n_}) {{ vtube_grid : \"{g}\"; direction: input; fanout_load: {l}; }}\n"
    c+=f"    pin(Y) {{ vtube_level : \"{'LV' if fol else 'HV'}\"; direction: output; max_fanout : 10; driver_type : pull_up; function: \"{f}\"; }}\n  }}\n"
    return c
cells=[]
if 'a' in flags: cells.append(cell("AND2_J2K",1,0,False,True))
for p in range(4):
    for t in range(7):
        n=2*p+t
        if n<2 or n>6: continue
        if 'o' in flags and not (p==0 and t in(2,4)) : cells.append(cell(f"AO_P{p}T{t}",p,t,False,True))
        if 'i' in flags and (p,t) not in {(0,2),(0,3),(0,4),(1,0),(1,1),(1,2),(2,0)}: cells.append(cell(f"WIRED_P{p}T{t}",p,t,True,False))
i=src.rindex('}')
open(out,'w').write(src[:i]+"\n".join(cells)+"}\n")
