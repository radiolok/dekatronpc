# Digitizing tube reference sheets

Instructions for an agent that turns scanned tube reference sheets (PDF) into data files: tables as text, curves as numbers. The output is used by a tube tester project, so values must be exact where the sheet is exact, and never invented.

The method was worked out on the 6N16B sheet; the result is `doc/6n16b_datasheet.md` with data in `doc/data/6n16b_datasheet.json`. Use those two files as the reference for what finished work looks like. The second example is the 6Zh2B (`doc/6zh2b_datasheet.md`, `doc/data/6zh2b_datasheet.json`). It is a pentode from a skewed low-resolution GIF scan, with solid and dashed families on one plot and two sheets that disagree.

Tool: `tools/digitize/digitize.py`. Copy it, together with this file, into the project that does the work.

## Rules that are never broken

1. **Never invent a value.** If a number cannot be read, write `null` and say why in a `"note"`.
2. **Never extrapolate a curve** past the end of the drawn line. Curves start and stop where the ink starts and stops.
3. **Never trust a curve until its points are drawn over the scan** (`overlay`) and you have looked at the picture. A value read "by eye" without an overlay was 10 V off on the first try.
4. **Copy tables exactly:** the same numbers, tolerances (±), units, conditions and footnotes. Do not convert units in tables. Do not round.
5. **One tube at a time, one plot at a time.** Finish, check and save a plot before starting the next.
6. **Stop and report** instead of guessing when a stop condition (section 7) is met.

## 1. Setup

```
python3 -m venv ~/.venvs/digitize
~/.venvs/digitize/bin/pip install pymupdf numpy pillow matplotlib
alias D='~/.venvs/digitize/bin/python /path/to/digitize.py'
```

Use `pymupdf` for rendering. Pillow alone cannot decode the fax-compressed (CCITT) scans that these PDFs usually contain; it returns blank pages without an error.

Work in one folder per tube, for example `work/6N16B/`.

## 2. Render and look

```
D render sheet.pdf --out page{n}.png        # all pages at 300 dpi
```

If the sheet comes as images (GIF, PNG, JPEG) rather than a PDF, convert each to a greyscale PNG with Pillow, for example `Image.open("p1.gif").convert("L").save("page1.png")`. Keep a copy of the original images next to the JSON, because without a URL they are the only source.

Open every page image and make a list of what is on it:
- text blocks;
- tables;
- the pinout drawing;
- the dimension drawing;
- each plot, with its title, axes, units and conditions (for example "Uh = 6.3 V, Ua = 100 V").

## 3. Tables and text

Transcribe into the JSON (schema in section 6):

- **Description:** purpose, construction, environment, weight, service life. Translate to English, and keep the original Russian name of the tube.
- **Electrical characteristics:** every row with value, tolerance, unit and condition. Footnote marks become `"note"` texts.
- **Interelectrode capacitances.**
- **Maximum and minimum ratings:** keep separate max and min columns, with every footnote (for example "350 V with the tube cut off, Ia ≤ 5 µA").
- **Pinout:** pin number → electrode, with the system number (T1/T2) as printed, and the key mark position.
- **Dimensions** as printed, in mm, with min/max.

Read small text on a zoomed crop (`D crop … --box` around the table) if the full page is unclear.

Tube names:
- Keep the original, e.g. `6Н16Б`.
- Add a Latin name using this table:

| Cyrillic | Н | Ж | П | Х | С | Б | Г | Э | К | Ц | Д | И | Ф |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Latin | N | Zh | P | Kh | S | B | G | E | K | Ts | D | I | F |

  So 6Н16Б → 6N16B and 6Ж2Б → 6Zh2B.

## 4. Each plot, step by step

The worked example is the 6N16B plot Ia = f(Ug): four curves for Ua = 150, 120, 100, 80 V.

### 4.1 Crop

```
D crop page2.png --box 0.57 0.32 0.86 0.63 --out iaug.png
```

`--box` takes x0 y0 x1 y1 as fractions of the page (or pixels). Include the axis labels but not the neighbouring plot. Open the crop and check that nothing is cut off.

**Skew.** Check whether the grid lines are straight. For example, find the lines separately in the left and right thirds of the crop and compare their positions. A tilt of more than about 1 px across the plot must be removed, because the two-point calibration cannot absorb it:

```
D deskew iaug.png --out iaug_d.png      # prints the tilt of horizontal and vertical lines, then shears them straight
```

Run `deskew` before `grid`, and work on the deskewed crop from then on, overlays included.

**Low resolution** (GIF or JPEG scans with about 20 px per grid step, where curves are 2 px and grid lines 1–2 px): upscale the deskewed crop 3× with bicubic resampling before `grid`, for example with Pillow `im.resize((3*W, 3*H), Image.BICUBIC)`. Then the run-length thresholds have room: grid lines become about 1–5 px and curves 5–7 px. Upscaling adds no detail, so the accuracy stays one line width of the original.

### 4.2 Find the grid

```
D grid iaug.png
```

The output gives:
- vertical and horizontal grid line positions in pixels;
- a "gaps filled" list for each direction; copy these lists into the calibration;
- a run-length histogram.

If too few lines are found, lower `--thr` (for example 0.35). If labels or curves are taken for lines, raise it.

The run-length histogram, for example `2:812 3:1593 4:458 5:212 6:319 …`, shows dark run lengths. Grid lines make the peak at 2–3 px; curves make the longer tail. Choose `--minlen` just above the grid peak: 5 for solid curves at 300 dpi. Thin dashed curves are as thin as the grid; section 4.4 covers them.

### 4.3 Calibrate

Pick two vertical grid lines that have printed axis values, as far apart as possible, and two horizontal ones. Write `cal.json`:

```json
{"x": {"px": [21.5, 673.0], "val": [-8, 0]},
 "y": {"px": [1006.0, 45.5], "val": [0, 12]},
 "grid_x_px": [21.5, 64.5, 105.5, ...],
 "grid_y_px": [45.5, 85.5, 126.0, ...]}
```

- Use the "gaps filled" lists from `grid` for `grid_x_px` and `grid_y_px`.
- Pixel y grows downwards; that is fine, the calibration handles it.
- A logarithmic axis gets `"log": true` inside `"x"` or `"y"`, with `"val"` as the real values (for example `[1, 100]`).
- A plot with several y scales (for example S, μ and Ri on one plot) gets one calibration file per scale. They share `"x"`.

Check the calibration before going on: run `scan`, and see that a curve you can read on the scan, for example "the 100 V curve meets −4.7 V at 0 mA", comes out at that value.

### 4.4 Get the points

Choose the method by what the curves look like.

| Situation | Method |
|---|---|
| Curves never cross, every row cuts each of them once (families like Ia = f(Ug), Ia = f(Ua)) | `order` |
| Curves cross, are dashed, or share the plot with labels and other lines | `band` |
| A few points where lines merge (bundles near the origin, labels on top of a curve) | read by hand from a zoomed crop, see 4.7 |

**order**: give the curves in left-to-right order. For curves that exist only for part of the y range, give that range:

```
echo '[{"name":"Ua 150 V"},{"name":"Ua 120 V"},{"name":"Ua 100 V"},{"name":"Ua 80 V"}]' > curves.json
D order iaug.png --cal cal.json --curves curves.json --start 0.05 --stop 11.95 --step 0.05 --out iaug_raw.json
```

- A row is used only if the number of crossings equals the number of curves expected there. Rows with labels, crossings or gaps are skipped automatically.
- If more than about 70 % of rows are skipped, the curve list or the y ranges are wrong.
- Use `"ymin"`/`"ymax"` per curve to stop the row search just below the curve labels. Labels sit at the curve ends and add crossings.

**band**: write rough guides, 5–10 points per curve read off the scan in data units, then collect the pixels inside a band around each guide:

```
echo '{"S": [[1,1.3],[2,2.3],[3,3.1],[4,3.8],[6,4.85],[8,5.47],[9,5.7]]}' > g_S.json
D band smu.png --cal cal_S.json --guides g_S.json --width 20 --minlen 5 --maxlen 14 --out raw_S.json
```

Choosing the band options:
- **Solid curves:** `--minlen 5`. That rejects the grid and thin dashed lines.
- **Dashed or dash-dot curves:** `--minlen 1 --maxlen 4`, a narrower band (`--width 14`), and guides that keep away from the other curves.
- **Where two curves come close:** narrow the band there (10 px). If the curves still mix, add guide points.
- **Curves lying on a grid line.** `--skip` drops every crossing near a grid line, so a curve that runs along a grid line loses all its points there. Run a second pass with `--skip 0` and `--minlen` above the thickest bare grid line, so that only the merged curve-plus-grid run is accepted. Then merge the two point sets. The merged run's centre is biased towards the grid line by at most half the offset. Where the curve lies exactly on the line, the merged run is no thicker than the curve and is lost too. In that case read the value by hand as the grid value ± half a line width (4.7).
- **Solid and dashed families on one plot** (for example Ia solid and Ig2 dashed): run `band` once per family with its own guides. Where a solid and a dashed line become one line on the sheet, both curves keep the points of that line; write the range in the note.

Scan direction (`--mode`): `cols` (the default) suits curves that run mostly left to right; `rows` suits steep curves.

### 4.5 Smooth and resample (when the points are scattered)

Families read with `order` can be stored as raw points. Curves from `band`, dashed curves, and curves you want on a regular grid get a robust fit:

```
D fit raw_S.json --basis sqrt --deg 3 --step 0.25 --lo 1 --hi 9 --out S.json
```

- **Basis:** use `sqrt` for curves that rise fast and then flatten (currents), `log` for slow saturation (μ), `inv` for 1/x shapes (Ri), `x` otherwise.
- **`median` (no shape):** the median of the raw points in each bin of width `--step`, for bins with at least 3 points. Use it when the band points are dense and clean and a polynomial lags at a steep start or drifts at an end. On the 6Zh2B, deg 3–4 fits missed the steep starts of the Ig2 curves by several line widths, and the medians did not. A bin that contains a crossing takes points from both curves; check crossings in the overlay.
- **Range:** set `--lo` and `--hi` to the drawn ends of the curve, never wider.
- **Fit quality:** the command prints the kept points and the largest residual; the residual should be about one line width. If it keeps less than 60 % of the points, the band was wrong.

### 4.6 Overlay and inspect, always

```
D overlay iaug.png --cal cal.json --points iaug_raw.json --r 2 --out iaug_ov.png
```

Open the picture. Accept the plot only if all of these hold:

- [ ] every point lies on the black line it belongs to;
- [ ] no curve "jumps" to its neighbour anywhere along its length;
- [ ] no points sit on labels, grid lines, arrows or the Pa max hyperbola;
- [ ] each curve starts and ends where its line does, especially after `fit`: fits drift at the ends, so trim `--lo`/`--hi`;
- [ ] the number of curves equals the number on the sheet.

If one check fails, fix the guides, band width, `--minlen` or the y ranges, and repeat 4.4–4.6. Do not edit points by hand to make a picture look right.

### 4.7 Hand reading (only where the tools cannot work)

Make a 3× zoom of the area with the grid lines labelled in data units, read the crossings of each curve with the grid lines, add them as points, and run `overlay` again.

Use this only for small regions:
- curves running together near the origin;
- the first and last few points under labels.

Write in the JSON note which ranges were read by hand.

## 5. Cross-checks for each tube

Run these after all plots of a tube are done. Each one either passes, or is reported with the numbers.

| Check | How | Expected |
|---|---|---|
| Nominal point | from Ia = f(Ug) at the nominal Ua, the Ug that gives the nominal Ia; compare with Ia × Rk if the sheet gives Rk for self-bias | within ~0.1 V. 6N16B: −1.97 V vs 6.3 mA × 325 Ω = 2.05 V |
| Table vs curves | S, μ, Ri at the nominal Ia from the curves | inside the table tolerance |
| S·Ri = μ | product at the same Ia | within ~5 %. 6N16B: 4.95 × 4.87 = 24.1 vs μ 24.7 |
| Two families agree | Ia from Ia = f(Ua) at a (Ug, Ua) point vs Ia = f(Ug) at the same point, at 4–5 points | within ~10 % or 0.5 mA. The sheets themselves disagree this much: 6N16B up to 0.46 mA (7 %). A larger gap usually means a swapped curve or a wrong calibration |
| Monotonic | plate current grows with Ua and with Ug | no reversals larger than the reading accuracy |
| Ratings | the Pa max line on the sheet equals Pa max in the ratings table | same value |

For a **pentode** the table usually gives no μ or Ri, so S·Ri = μ is dropped. Self-bias then uses the cathode current: Ug1 = −(Ia + Ig2)·Rk. On the 6Zh2B this gives Ug1 = −1.85 V, Ia = 6.0 mA against the table's 5.5 ± 2 mA. "Two families agree" compares the plots at the point they share, for example Ia = f(Ug3) at Ug3 = 0 against Ia = f(Ua) at the nominal Ua. If the curves run past the ratings (Pa, Pg2, Ik, Ua), say so in the checks with the numbers; that is not a failure.

**Two sheets for one tube** (a handbook page and a ТУ label sheet, or a tube and its "-В" version): transcribe both and keep them apart in the JSON (for example `variant_6Zh2B_V`). List every value that differs. Pin numbering in particular can differ between the sheets. Never merge two pinouts. Put both in the report, and say which one the KiCad symbol follows.

## 6. Output format

One JSON file per tube, `<latin name>.json`, for example `6N16B.json`:

```json
{
 "tube": "6N16B", "name_ru": "6Н16Б", "type": "double triode",
 "source": "file name or URL, pages",
 "description": "…",
 "electrical": [ {"name": "S", "value": 5.0, "tol": 1.25, "unit": "mA/V", "cond": "each triode", "note": null}, … ],
 "capacitances": [ {"name": "Cg1k", "value": 2.7, "tol": 0.7, "unit": "pF"}, … ],
 "ratings": [ {"name": "Ua", "max": 200, "min": null, "unit": "V", "note": null},
              {"name": "Ua", "max": 350, "min": null, "unit": "V", "note": "tube cut off, Ia <= 5 uA"}, … ],
 "pinout": [ {"pin": 1, "electrode": "anode", "system": "T2"}, … ],
 "dimensions": [ {"name": "bulb diameter", "max": 10.2, "unit": "mm"}, … ],
 "plots": {
   "ia_ua": {"title": "Ia = f(Ua)", "x": "Ua, V", "y": "Ia, mA", "param": "Ug, V",
             "cond": "Uh = 6.3 V, each triode",
             "curves": {"0": [[6.2, 0.25], [11.7, 0.5], …], "-1": […]},
             "method": "order", "hand_read": null,
             "accuracy": "+-0.5 V, +-0.03 mA"},
   …
 },
 "checks": [ {"name": "S*Ri = mu at 6.3 mA", "result": "24.1 vs 24.7", "pass": true}, … ],
 "notes": "anything unclear, with the page number"
}
```

Rules for the file:
- Curve points are `[x, y]` in the plot's own units, sorted by x (or by y for curves that are steep in x).
- `"param"` names what distinguishes the curves; the curve keys are its values as text, without units.
- Keep each plot's overlay PNG next to the JSON (`<tube>_<plot>_overlay.png`). The reviewer checks them.

## 7. Stop conditions: report, do not guess

Stop working on a plot and write a note when:
- the axis values cannot be read, or fewer than two labelled grid lines exist on an axis;
- the axis is not linear and not logarithmic;
- curves cross many times so that neither `order` nor `band` separates them after two attempts;
- the overlay still shows points off the lines after three attempts;
- the curve labels cannot be matched to the curves;
- a cross-check in section 5 fails by more than twice the expected tolerance.

Leave that plot's `"curves"` as `null` with the reason, and continue with the next plot.

## 8. Known traps

| Trap | What happens | Remedy |
|---|---|---|
| Pillow on CCITT scans | blank or garbage pages, no error | render with `pymupdf` (`D render`) |
| Grid skew | grid lines drift 1–3 px across the scan and leave "phantom curves" at fixed x | use the "gaps filled" grid list, `--skip 3`; drop crossings that stay at one x on every row |
| Missed grid lines | some lines are not detected (a curve crosses them) | the "gaps filled" list adds them |
| Labels at curve ends | extra crossings near the tops | `ymax` per curve in `order`, or stop the guide before the label |
| Pa max hyperbola, arrows, leader lines | extra points | `band` with a narrow width, or drop rows that cross them |
| Curves merging near the origin | `order` sees fewer crossings | let those rows be skipped; read the bundle by hand (4.7) |
| Dashed curves as thin as the grid | lost with `--minlen 5` | `--minlen 1 --maxlen 4` in `band` with careful guides |
| Several y scales on one plot | wrong values | one calibration file per scale |
| Fit end effects | the first and last fitted points drift | trim `--lo`/`--hi` to the drawn ends; check the ends in the overlay |
| Reading values without overlay | silent errors of several volts | never skip `overlay` |
| Two curves swapped | values look plausible but belong to the neighbour | check the left-to-right order against the labels on the sheet |
| Skewed scan | horizontal grid lines drift by several px from left to right; calibration is right at one end and wrong at the other | `deskew` before `grid` |
| Low-resolution GIF/JPEG | curves and grid are both 1–2 px, `--minlen` cannot separate them | upscale the deskewed crop 3× before `grid` |
| Curve along a grid line | `--skip` drops the whole stretch, and the curve ends early | second `band` pass with `--skip 0` and a high `--minlen`; hand reading where the curve lies exactly on the line |
| Polynomial fit at a steep start | the fit lags the line by several line widths | `fit --basis median` |
| Saving overlays with a small palette | the coloured points disappear | save as RGB PNG |

## 9. Report for each tube

Write a short text next to the JSON:
- which plots were digitized and by which method;
- the ranges read by hand;
- the result of each cross-check;
- anything left `null`, and why.
