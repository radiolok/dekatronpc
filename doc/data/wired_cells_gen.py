import sys,string
src=open('/home/radiolok/dekatronpc/sch/logic/vtube_cells.lib').read()
maxin=int(sys.argv[1]); out=sys.argv[2]
existing={(0,2),(0,3),(0,4),(1,0),(1,1),(1,2),(2,0),(0,1)}
cells=[]
for p in range(0,4):
  for t in range(0,7):
    n=2*p+t
    if n<2 or n>maxin or (p,t) in existing: continue
    pins=iter(string.ascii_uppercase)
    terms=[]; pl=[]
    for i in range(p):
      a=next(pins);b=next(pins);terms.append(f"{a}*{b}");pl.append((a,'pentode_g1',0.69));pl.append((b,'pentode_g3',1.74))
    for i in range(t):
      a=next(pins);terms.append(a);pl.append((a,'triode',1.0))
    tubes=[]
    if p: tubes.append(f"      J2B: {p};")
    if t: tubes.append(f"      N16B: {t*0.5};")
    c=f"  // WIRED experiment: {p} pentode terms + {t} triode terms on one plate\n  cell(WIRED_P{p}T{t}) {{\n    area: {p+0.5*t};\n    current_unit : \"1mA\";\n    heat_current: {200*p+200*t};\n    tubes(names) {{\n"+"\n".join(tubes)+"\n    }\n"
    for n_,g,l in pl: c+=f"    pin({n_}) {{ vtube_grid : \"{g}\"; direction: input; fanout_load: {l}; }}\n"
    c+=f"    pin(Y) {{ vtube_level : \"HV\"; direction: output; max_fanout : 10; driver_type : pull_up; function: \"({'+'.join(terms)})'\"; }}\n  }}\n"
    cells.append(c)
i=src.rindex('}')
open(out,'w').write(src[:i]+"\n".join(cells)+"}\n")
print(len(cells),"cells")
