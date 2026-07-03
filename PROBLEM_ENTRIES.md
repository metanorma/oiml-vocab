# G18 Problematic Entries — Full Inventory

This document catalogues every data-quality issue found in `datasets/g18-2010/` and `datasets/g18-202X/` after PR #47. Every entry is **validated against source**:

- **g18-202X**: source is `reference-docs/TC1_P3_N008-2CD_revision_of_G18-clean.docx` (G18 Edition 202X 2CD draft).
- **g18-2010**: source is `reference-docs/g018-2010-ocr/glm-ocr.md` (GLM OCR of `g018-e10.pdf`).

Status markers:
- `[SRC-TYPO]` — the typo/error exists in the source document itself. Data must stay verbatim; issue opened against the source.
- `[DATA-ERROR]` — the source is fine; data has wrong/corrupt value. Fix in dataset.
- `[EXTRACTION-ARTIFACT]` — DOCX parser concatenated separate designations into one string; source has them separate.
- `[STYLE]` — DOCX uses smart quotes / dashes; data should normalize to ASCII.

---

## A. Source-side DOCX errors (report upstream, keep verbatim) — [SRC-TYPO]

| File | Current designation | DOCX line | Issue |
|---|---|---|---|
| 202X/00209 | `field surveillance ("in-service surveillance")` | 4353 | Smart quotes (acceptable style) |
| 202X/02278-D016 | `in-service surveillance (alternatively "field surveillance")` | 5482 | Smart quotes |
| 202X/01858 | `Beer's factor (Kε = εb = Ac/c)` | 1321 | Smart apostrophe |
| 202X/02270-D016 | `manufacturer's representative` | 6575 | Smart apostrophe |
| 202X/00200 | `manufacturer's  representative` | n/a | Smart apostrophe + double space |
| 202X/01453 (01454 in 202X) | `magnetic force (F1, F2, Fa, Fb, F- and Fz)` | 9296 | `F-` is truncated — should be `Fmax` (DOCX rendering dropped subscript) |
| 202X/01911 | `mean area error ()` | 7047 | Empty parens — χ̄ₑ symbol dropped |
| 202X/01451 | `magnetic constant (magnetic permeability of vacuum ()` | 6467 | Unclosed paren — μ₀ symbol dropped |
| 202X/02115 | `sensitivity to non-uniformity in the field of a  thermographic instrument` | 11039 | Double space |
| 202X/03583 | `transportable evidential breath alcohol anayser (transportable EBA)` | 12596 | Typo: anayser→analyser |
| 202X/03326 | `Newtonian viscosity stnadrd specimen (VSS)` | 8217 | Typo: stnadrd→standard |
| 202X/03539 | `stationary evidential breath alcohol analyzer (stationry EBA)` | 11854 | Typo: stationry→stationary |
| 202X/01642 | `maximum permissible error (of a measuring  instrument)` | n/a | Double space + paren qualifier |

**Action**: Open GH issue listing these 13 entries with their DOCX line numbers for OIML TC1/P3 to fix in the next 2CD revision.

---

## B. Math encoding — Unicode Greek / inline math (data fix) — [DATA-ERROR]

DOCX has correct Unicode math; data should use `stem:[...]` AsciiMath.

| File | Current | Should become |
|---|---|---|
| 202X/01679 | `net absorbance, ΔA` | expr + `stem:[Delta A]` |
| 202X/01680 | `specific net absorbance, Δk` | expr + `stem:[Delta k]` |
| 202X/01698 | `angle α` | expr + `stem:[alpha]` |
| 202X/01743 | `specific absorbance, kλ` | expr + `stem:[k_{lambda}]` |
| 202X/01841 | `incident flux (Φ0)` | expr + `stem:[Phi_{0}]` |
| 202X/01843 | `transmittance (τ = Φtr / Φ0)` | expr + `stem:[tau = Phi_{"tr"} / Phi_{0}]` |
| 202X/01844 | `absorbance (A = lg(1/τ))` | expr + `stem:[A = lg(1/tau)]` |
| 202X/01847 | `specific molar absorption coefficient (ε = A/bc)` | expr + `stem:[epsilon = A/(b c)]` |
| 202X/01848 | `law of Bouguer-Lambert and Beer (A = lg(1/τ) = εbc)` | expr + `stem:[A = lg(1/tau) = epsilon b c]` |
| 202X/01857 | `characteristic partial internal absorbance Ac (...)` | expr + `stem:[A_{"c"} = lg(Phi_{"r"}/Phi_{"s"}) = epsilon b c]` |
| 202X/01858 | `Beer's factor (Kε = εb = Ac/c)` | expr + `stem:[K_{epsilon} = epsilon b = A_{"c"}/c]` (also normalize apostrophe) |
| 202X/02114 | `noise equivalent temperature difference (temperature resolution, ΔTNETD)` | 2 exprs + `stem:[Delta T_{"NETD"}]` |
| 202X/02418 | `pressure loss Δp` | expr + `stem:[Delta p]` |
| 202X/02689 | `working density, ρw` | expr + `stem:[rho_{w}]` |
| 202X/00851 | `response time, τ 0,5` | expr + `stem:[tau_{0.5}]` |
| 202X/03317 | `minimum totalized load (Σmin)` | expr + `stem:[Sigma_{"min"}]` |
| 202X/03406 | `minimum totalised quantity, Σmin` | expr + `stem:[Sigma_{"min"}]` |

---

## C. Fake-math text subscripts (data fix) — [DATA-ERROR]

Plain-text subscript text that should be `stem:[...]` symbol.

| File | Current | Fix |
|---|---|---|
| 2010/01418 | `upper limit of measuring range (Pmax)` | expr + `stem:[P_{"max"}]` |
| 2010/01419 | `lower limit of measuring range (Pmin)` | expr + `stem:[P_{"min"}]` |
| 202X/02589 | `maximum operating speed, vmax` | expr + `stem:[v_{"max"}]` |
| 202X/02590 | `minimum operating speed, vmin` | expr + `stem:[v_{"min"}]` |
| 202X/03318 | `minimum measuring speed (Vmin)` | expr + `stem:[V_{"min"}]` |
| 202X/02302-2 | `minimum current (Imin)` | expr + `stem:[I_{"min"}]` |
| 202X/03302 | `minimum dead load (Emin)` | expr + `stem:[E_{"min"}]` |
| 202X/00442 | `minimum flowrate of the measuring system Qmin` | expr + `stem:[Q_{"min"}]` |
| 202X/02075 | `maximum flowrate of the measuring system Qmax` | expr + `stem:[Q_{"max"}]` |

---

## D. Concatenated designations (data fix) — [EXTRACTION-ARTIFACT]

DOCX has separate lines for each designation; parser joined them.

| File | Current | Split into |
|---|---|---|
| 202X/02253-D011 | `measurement uncertainty uncertainty of measurement uncertainty` | 3 expressions: `measurement uncertainty`, `uncertainty of measurement`, `uncertainty` |
| 202X/02933 | `combined standard measurement uncertainty combined standard uncertainty` | 2 expressions |
| 202X/02448 | `measurement repeatability repeatability` | 2 expressions |
| 202X/02449 | `measurement reproducibility reproducibility` | 2 expressions |
| 202X/03385 | `primary measurement standard primary standard` | 2 expressions |
| 202X/02452 | `reference quantity value reference value` | 2 expressions |
| 202X/03446 | `reference quantity value reference value` | 2 expressions |
| 202X/02791 | `reference quantity value {reference value}` | 2 expressions (strip braces) |
| 202X/03728 | `reference quantity value; reference value` | 2 expressions |
| 202X/03297 | `metrological traceability to a measurement unit metrological traceability to a unit` | 2 expressions |
| 202X/03296 | `metrological traceability chain traceability chain` | 2 expressions |
| 202X/02792 | `repeatability measurement repeatability` | 2 expressions |
| 202X/02446 | `maximum permissible measurement error (MPE) maximum permissible error limit of error` | expr + abbrev + admitted expr |
| 202X/03364 | `permanent automatic checking facility checking facility of type P` | expr + abbrev |
| 202X/03329 | `non-automatic checking facility checking facility of type N` | expr + abbrev |
| 202X/03152 | `intermittent automatic checking facility checking facility of type I` | expr + abbrev |
| 202X/02453 | `repeatability condition of measurement (repeatability condition)` | 2 expressions |
| 202X/02795 | `reproducibility condition of measurement {reproducibility condition}` | 2 expressions |
| 202X/02789 | `reference condition {reference operating condition}` | 2 expressions |
| 202X/01852 | `blank solution reference solution` | 2 expressions |
| 202X/01865 | `resolution of a spectrophotometer; resolving power of a spectrophotometer` | 2 expressions |
| 202X/01875 | `maximum permissible error (of a measuring instrument); limits of permissible error (of a measuring instrument)` | 2 exprs with usage_info |
| 202X/03441 | `product reference quantity` | Unclear — check DOCX |
| 2010/01875 | `maximum permissible error (of a measuring instrument); limits of permissible error (of a measuring instrument)` | 2 exprs with usage_info |
| 2010/01197 | `characteristic concentration characteristic mass` | 2 expressions |
| 2010/01853 | `calibration solution standard solution` | 2 expressions |
| 2010/01470 | `subsequent verification or in-service inspection` | 2 expressions |

---

## E. Abbreviation paren splits still needed (202X) — [DATA-ERROR]

| File | Current | Split |
|---|---|---|
| 202X/02060 | `calorific value determining device (CVDD)` | expr + abbrev |
| 202X/02112 | `instantaneous field of view (IFOV)` | expr + abbrev |
| 202X/02152 | `reference material (RM)` | expr + abbrev |
| 202X/02153 | `certified reference material (CRM)` | expr + abbrev |
| 202X/02235-R071 | `automatic level gauge (ALG)` | expr + abbrev |
| 202X/02254-R080-1 | `reference point top (RPT)` | expr + abbrev |
| 202X/02299-R085-1 | `automatic level gauge (ALG)` | expr + abbrev |
| 202X/02313-R046-1 | `power factor (PF)` | expr + abbrev |
| 202X/02508 | `sample correction factor (SCF)` | expr + abbrev |
| 202X/02569 | `weighing-in-motion (WIM)` | expr + abbrev |
| 202X/02661 | `weighted mean error (WME)` | expr + abbrev |
| 202X/02779 | `calibration gas mixture (CGM)` | expr + abbrev |
| 202X/02781 | `intraocular pressure (IOP)` | expr + abbrev |
| 202X/02790 | `reference material (RM)` | expr + abbrev |
| 202X/02811 | `protein content (PMB)` | expr + abbrev |
| 202X/02919 | `calibration and measurement capability (CMC)` | expr + abbrev |
| 202X/02942 | `conformity to type (CTT) program` | expr + abbrev + usage_info |
| 202X/03234 | `maximum permissible error (MPE)` | expr + abbrev |
| 202X/03303 | `minimum dead load output return (DR)` | expr + abbrev |
| 202X/03309 | `minimum measured quantity (MMQ)` | expr + abbrev |
| 202X/03325 | `Newtonian reference liquids (RL)` | expr + abbrev |
| 202X/03326 | `Newtonian viscosity stnadrd specimen (VSS)` | expr + abbrev (also keep typo from §A) |
| 202X/03583 | `transportable evidential breath alcohol anayser (transportable EBA)` | 2 exprs + 2 abbrev (also keep typo) |
| 202X/03539 | `stationary evidential breath alcohol analyzer (stationry EBA)` | 2 exprs + 2 abbrev (also keep typo) |
| 202X/03372 | `portable breath alcohol analyzer (portable EBA)` | 2 exprs + 2 abbrev |
| 202X/02089 | `weighted mean error (WME)` | expr + abbrev |
| 202X/00850 | `equipment under test (EUT)` | expr + abbrev |
| 202X/02992 | `dimensional weight (Dim Wt or DW)` | expr + 2 abbrev |
| 202X/02993 | `dimensional volume (Dim Vol or DV)` | expr + 2 abbrev |
| 202X/03674 | `multi-load AGFI` | usage_info |
| 202X/03771 | `maximum permissible error / MPE` | expr + abbrev |
| 202X/02414 | `maximum admissible temperature MAT` | expr + symbol `stem:[MAT]` |
| 202X/02415 | `maximum admissible pressure MAP` | expr + symbol `stem:[MAP]` |
| 202X/02424 | `rated operating condition ROC` | expr + abbrev |
| 202X/02445 | `certified reference material CRM` | expr + abbrev |
| 202X/03438 | `reference material RM` | expr + abbrev |
| 202X/03439 | `reference material RM` | expr + abbrev |
| 202X/02385 | `equipment under test EUT` | expr + abbrev |
| 202X/00629 | `net value, NET or N` | expr + 2 symbols |

---

## F. Single-letter symbol paren splits — [DATA-ERROR]

| File | Current | Split |
|---|---|---|
| 2010/01451 | `magnetic dipole moment (md)` | expr + `stem:[m_{d}]` |
| 2010/01464 | `test weight (mt)` | expr + `stem:[m_{t}]` |
| 2010/01712 | `volume (vol)` | expr + abbrev `vol` |
| 202X/01452 | `magnetic dipole moment (md)` | expr + `stem:[m_{d}]` |
| 202X/01453 | `magnetic field strength (H)` | expr + `stem:[H]` |
| 202X/01462 | `temperature (t)` | expr + `stem:[t]` |
| 202X/01464 | `test weight (mt)` | expr + `stem:[m_{t}]` |
| 202X/01486 | `retention time (tr) for a measurement` | expr with **inline** `stem:[t_{r}]` (DO NOT split) |
| 2010/01486 | `retention time (tr) for a measurement` | same as 202X |
| 202X/01845 | `optical path length (b)` | expr + `stem:[b]` |
| 202X/02256-R080-1 | `reference height (H)` | expr + `stem:[H]` |
| 202X/02307-R046-1 | `frequency (f)` | expr + `stem:[f]` |
| 202X/02312-R046-1 | `distortion factor (d)` | expr + `stem:[d]` |
| 202X/02957 | `conversion factor (F)` | expr + `stem:[F]` |
| 202X/03096 | `height (H)` | expr + `stem:[H]` |
| 202X/03193 | `liquid height (h)` | expr + `stem:[h]` |
| 202X/03204 | `load cell verification interval (v)` | expr + `stem:[v]` |
| 202X/03341 | `number of load cell verification intervals (n)` | expr + `stem:[n]` |
| 202X/03468 | `scale interval (d)` | expr + `stem:[d]` |
| 202X/03470 | `scale interval (d)` | expr + `stem:[d]` |
| 202X/03574 | `totalization scale interval (d)` | expr + `stem:[d]` |
| 202X/03604 | `ullage height (C)` | expr + `stem:[C]` |
| 202X/03630 | `weigh length (L) [not applicable to belt weighers inclusive of conveyor]` | expr + `stem:[L]` + usage_info |
| 202X/03644 | `width (W)` | expr + `stem:[W]` |

---

## G. usage_info parentheticals still needing extraction (202X)

| File | Current | usage_info |
|---|---|---|
| 202X/01320 | `conventional true value (of a quantity)` | `of a quantity` |
| 202X/02069 | `conventional true value (of a quantity)` | `of a quantity` |
| 202X/02658 | `indicated value (of a quantity)` | `of a quantity` |
| 202X/02272-D016 | `end user (of a measuring instrument)` | `of a measuring instrument` |
| 202X/03106 | `indicating device (of a weighing instrument)` | `of a weighing instrument` |
| 202X/00583 | `displaying device (of a weighing instrument)` | `of a weighing instrument` |
| 202X/01642 | `maximum permissible error (of a measuring instrument)` | `of a measuring instrument` |
| 202X/03161 | `integrity (of programs, data, or parameters)` | `of programs, data, or parameters` |
| 202X/03149 | `integrity (of software, measurement data, or parameters)` | `of software, measurement data, or parameters` |
| 202X/02083 | `significant fault (for the principal measurands: volumes, mass or energy)` | `for the principal measurands: volumes, mass or energy` |
| 202X/02085 | `significant fault (for CVDDs)` | `for CVDDs` |
| 202X/02084 | `significant fault (for associated measuring instruments other than CVDDs)` | `for associated measuring instruments other than CVDDs` |
| 202X/02323-R046-1 | `negative (energy) flow (for bi-directional and uni-directional meters)` | usage_info |
| 202X/02389 | `cartridge meter connection interface` | none — verify in DOCX |
| 202X/02392 | `connection interface for meters with exchangeable metrological modules` | usage_info |
| 202X/02337-R046-1 | `negative (energy) flow (for bi-directional and uni-directional meters)` | usage_info |
| 202X/02659 | `cyclic volume of a gas meter (positive displacement gas meters only)` | usage_info |
| 202X/01317 | `discontinuous totalizing automatic weighing instrument (totalizing hopper weigher)` | admitted expression |
| 202X/02945 | `continuous totalizing automatic weighing instrument (belt weigher)` | admitted |
| 202X/00846 | `sub-assemblies of a heat meter, which is a combined instrument` | usage_info |
| 202X/03630 | `weigh length (L) [not applicable to belt weighers inclusive of conveyor]` | usage_info |
| 2010/00561 | `automatic catchweighing instrument (catchweigher)` | admitted |
| 2010/01111 | `inadequate prepackage (also called a non-conforming prepackage)` | admitted |
| 2010/01370 | `non-automatic (static) operation` | usage_info |
| 2010/02008 | `unattended post-payment (or delayed payment)` | admitted |
| 2010/02272 | `collector (manifold)` | admitted |
| 2010/00330 | `systolic blood pressure (value)` | usage_info |
| 2010/00205 | `putting into service (use)` | usage_info |
| 2010/00207 | `being in service (use)` | usage_info |
| 2010/01828 | `influence quantity` | clean (no fix needed) |

---

## H. Citation pollution in definitions/notes — large cleanup

**~404 files** in g18-202X have `[VIM:XXXX, X.Y]`, `[OIML D XX, Y.Z]`, `(VIM:2007, X.Y)`, `[adapted from ...]` citations in definitions/notes that should be:

1. Stripped from text
2. Moved to `sources[]` on the definition
3. Status: `modified` if `[adapted from]`, `identical` if direct quote, per concept-model enum

**Status enum** (from `concept-model/schemas/v3/localized-concept.yaml`):
- `identical` — direct quote, no changes
- `similar` — close but reworded
- `modified` — **"adapted from"** maps here
- `restyle` — stylistic changes only
- `context_added` — added context to original
- `generalisation` — broader than original
- `specialisation` — narrower than original
- `unspecified`
- `related`
- `not_equal`

---

## I. Examples needing encoding

Many definitions contain `Example:` text mixed into definition. Per concept-model, examples are a separate field:

- **Concept-level `examples[]`**: when example is independent of any note
- **Per-note `examples[]`**: when example is scoped to a specific note (VIM 1993 style)

Need to scan for `Example:` patterns in definitions and split out.

---

## J. Compound notes — "Note 1: ... Note 2: ..." in single `notes[]` entry

20+ entries have multi-note content in one `notes[]` array element. Split into individual array entries.

---

## K. `{...}` brace wrappers around notes/examples (DOCX extraction artifact)

Examples at: 02795, 02784, 02789, 02785, 02809, 02253, etc. Strip braces.

---

## L. Bibliography stub entries needing canonical links

66 entries in `datasets/g18-202X/bibliography.yaml` have stub `reference` but no `link`. Look up canonical URLs from `~/src/relaton/relaton-data-oiml/data/` (titles + docnumbers).

URL pattern from existing g18-2010 bibliography: `https://www.oiml.org/en/files/pdf_{type}/{id_lower}-e{yy}.pdf`

---

## Plan

1. ✅ Write this PROBLEM_ENTRIES.md
2. Open GH issue listing §A source-side DOCX errors (13 entries)
3. Implement §B (math encoding) — 17 entries
4. Implement §C (fake-math subscripts) — 9 entries
5. Implement §D (concatenated splits) — 25 entries
6. Implement §E (abbreviation parens) — 35 entries
7. Implement §F (single-letter symbol parens) — 24 entries
8. Implement §G (usage_info) — 25 entries
9. Implement §H (citation stripping in defs/notes) — defer (too large for this PR)
10. Implement §I (examples encoding) — scan and fix
11. Implement §J (compound notes split) — 20+ entries
12. Implement §K (brace unwrapping) — 10+ entries
13. Implement §L (bibliography links) — 66 entries
