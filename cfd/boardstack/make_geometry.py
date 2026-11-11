#!/usr/bin/env python3
"""Read the legacy board STL, clean it, and write 3 translated copies.

The source STL is OpenCASCADE binary STL (80-byte header, uint32 count,
50 bytes per triangle).  surfaceCheck reports 1370 duplicate triangles
and 2 regions; this script drops exact-duplicate and degenerate triangles
and writes a clean binary STL per board, translated along Z so the boards
are stacked with a given pitch.
"""
import struct
import sys
from pathlib import Path

SRC = Path("/home/radiolok/dekatronpc/sch/logic/legacy/Board_4NOR_2NOR_NOT.stl")
OUT_DIR = Path("/home/radiolok/dekatronpc/cfd/boardstack/geometry")

PITCH_MM = 24.0          # board pitch (centre-to-centre) in Z
N_BOARDS = 3
SCALE = 1e-3             # STL coordinates are mm -> write in metres (SI)

def read_stl(path):
    with open(path, "rb") as f:
        hdr = f.read(80)
        (n,) = struct.unpack("<I", f.read(4))
        tris = []
        for _ in range(n):
            d = f.read(50)
            if len(d) < 50:
                break
            vals = struct.unpack("<12fH", d)
            tris.append(tuple(tuple(vals[3 + 3 * i + k] for k in range(3))
                              for i in range(3)))
    return tris

def tri_area(t):
    a, b, c = t
    ax, ay, az = a
    bx, by, bz = b
    cx, cy, cz = c
    ux, uy, uz = bx - ax, by - ay, bz - az
    vx, vy, vz = cx - ax, cy - ay, cz - az
    nx = uy * vz - uz * vy
    ny = uz * vx - ux * vz
    nz = ux * vy - uy * vx
    return 0.5 * (nx * nx + ny * ny + nz * nz) ** 0.5

def write_stl(path, tris, scale=1.0):
    with open(path, "wb") as f:
        f.write(b"clean board STL".ljust(80, b" "))
        f.write(struct.pack("<I", len(tris)))
        for t in tris:
            a, b, c = t
            ax, ay, az = a
            bx, by, bz = b
            cx, cy, cz = c
            ux, uy, uz = bx - ax, by - ay, bz - az
            vx, vy, vz = cx - ax, cy - ay, cz - az
            nx, ny, nz = uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx
            f.write(struct.pack("<12fH",
                                nx * scale, ny * scale, nz * scale,
                                ax * scale, ay * scale, az * scale,
                                bx * scale, by * scale, bz * scale,
                                cx * scale, cy * scale, cz * scale, 0))

def main():
    tris = read_stl(SRC)
    print(f"read {len(tris)} triangles")

    # Dedup by canonical key (sorted rounded vertex coords), drop degenerates.
    seen = set()
    clean = []
    deg = 0
    dup = 0
    for t in tris:
        key = tuple(sorted(tuple(round(v, 4) for v in p) for p in t))
        if key in seen:
            dup += 1
            continue
        seen.add(key)
        if tri_area(t) < 1e-12:
            deg += 1
            continue
        clean.append(t)
    print(f"duplicates dropped: {dup}, degenerate dropped: {deg}, "
          f"kept: {len(clean)}")

    area = sum(tri_area(t) for t in clean)
    mn = [min(p[k] for t in clean for p in t) for k in range(3)]
    mx = [max(p[k] for t in clean for p in t) for k in range(3)]
    print(f"surface area: {area:.4f} mm^2 = {area * 1e-6:.6f} m^2")
    print(f"bbox min: {['%.3f' % v for v in mn]}")
    print(f"bbox max: {['%.3f' % v for v in mx]}")
    print(f"size   : {['%.3f' % (mx[k] - mn[k]) for k in range(3)]}")

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    z0 = -mn[2]
    for i in range(N_BOARDS):
        shift = z0 + i * PITCH_MM
        tris_i = [tuple((x, y, z + shift) for (x, y, z) in t) for t in clean]
        write_stl(OUT_DIR / f"board{i}.stl", tris_i, scale=SCALE)
        print(f"wrote board{i}.stl  (Z shift +{shift:.4f} mm)")

    # Per-board power and flux estimate.
    heater = 16 * 2.52   # 16 x 6N16B, 6.3 V * 0.4 A
    anode = 16 * 1.0     # estimate ~1 W/tube at +150 V
    total = heater + anode
    flux = total / (area * 1e-6)
    print(f"\nper board: heater {heater:.2f} W + anode {anode:.2f} W = "
          f"{total:.2f} W,  flux {flux:.1f} W/m^2")

if __name__ == "__main__":
    main()
