# Tubes

Reference data and SPICE models of the tubes used in the cells (`sch/logic/`). One folder per tube: `README.md` with the transcribed sheet, `scan/` with the source pages, `img/` with the figures. The models themselves stay in `sch/libs/` (the KiCad sheets reach them as `${KIPRJMOD}/../../libs/`).

| Tube | Kind | Model | Page | Used in |
|---|---|---|---|---|
| 6Kh7B (6Х7Б) | double diode | `sch/libs/6Kh7B.sub` (from the sheet's bounds) | [6Kh7B](6Kh7B/README.md) | DFFRN_J2N16X7, DFFSN_J2N16X7; planned: the `*_N16X7` diode cells |
| 6N16B (6Н16Б) | double triode | `sch/libs/6N16B.sub` | `doc/6n16b_datasheet.md` | NOR2_N16, NOT_N16, BUF_N16, OR2_N16, latches |
| 6Zh2B (6Ж2Б) | pentode with two control grids | `sch/libs/6Zh2B.sub` | `doc/6zh2b_datasheet.md` | NAND2_J2, latches, AOI cells |

6N16B and 6Zh2B still have their pages in `doc/`; they can move here.
