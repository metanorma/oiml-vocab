# V 0 extraction spec — manual, per-document, agent guide

You are one of 5 parallel agents building the **OIML G 18 complete** dataset by
**manually reading** every OIML publication's OCR markdown and emitting
glossarist v3 YAML for every terminology entry you find. Automated code
cannot do this — the corpus spans six decades of layout conventions and
OCR quality. You are the parser.

This spec is the contract. Follow it verbatim so output is byte-identical
to what the other 4 agents produce.

---

## 1. Inputs

You are assigned a list of publication directory names (e.g.
`r49-1-2013-eng`, `d11-2013-e`). For each one:

- Open the OCR markdown at:
  `/Users/mulgogi/src/oimlsmart/publications/reference-docs/ocr-output/<pub-code>/ocr.md`
- Read the **entire** document. Do not grep for keywords and assume what
  you found is the only terminology section — there are bilingual halves,
  multiple parts in the same file, and annexes that re-define terms.

If `ocr.md` does not exist for a directory, skip it (record it in your
report).

---

## 2. What counts as a terminology section

Any section that lists term/definition pairs. Match any of these header
forms (case-insensitive, allowing trailing page numbers, parenthesised
alternates, and any leading number of `#`):

- `Terms and definitions` / `Terms, definitions, symbols, and abbreviated terms`
- `Termes et définitions` / `Termes et définitions (Terminologie)` / `Termes et désignations`
- `Términos y definiciones` / `Terminología` / `Términos de base`
- `Terminology` / `Terminologie` / `TERMINOLOGY` / `TERMINOLOGIE`
- `Definitions` / `Définitions` / `Definitionen` / `DEFINITIONS`
- `Vocabulary` / `Vocabulaire` / `Glossary` / `Glossaire`
- `Basic and general terms in metrology`
- `0 Terms and definitions` / `0 Termes et définitions`
- `1.1 Definitions` (when it's a sub-clause that lists multiple definitions)

If the section is a prose paragraph that defines a term inline (older
documents often do this for one or two key terms), still extract it as a
concept — the section number is the term number.

If a document has **no terminology section at all** (it's a brochure, a
certificate, a meeting minutes, a constitution, etc.), skip it.

---

## 3. What to extract per term entry

For each numbered term entry inside a terminology section, capture:

| Field | Required? | Notes |
|---|---|---|
| `number` | yes | The entry's source numbering, e.g. `3.1.1`, `0.02`, `1.1`, `3.7`. Strip spaces from forms like `3. 7` → `3.7`. |
| `designation` | yes | The preferred term verbatim (the line right after the number header). |
| `definition` | yes if present | Verbatim definition text. Skip if the source only says "see VIM X.Y" (then put the citation in `source_citation` and leave `definition` null). |
| `notes` | optional | All `Note 1:`, `Note 2:`, `Note:`, `Remarque :` lines, label stripped, text verbatim. |
| `examples` | optional | All `Example:`, `EXAMPLE:`, `Exemple :` lines, label stripped, text verbatim. |
| `source_citation` | optional | Verbatim citation, e.g. `OIML V 2-200:2012 (VIM) 3.8`, `VIML 5.14`, `VIM2.16`. Strip the wrapping `[ ... ]` brackets. |
| `language` | yes | ISO 639-2 code: `eng`, `fra`, `spa`, `deu`, `ara`, `fas`, `zho`, `rus`, `por`, `ita`, `nld`. |

If a term has no designation (just a number followed by a definition),
skip it — there's nothing to surface in a vocabulary browser.

---

## 4. Detecting language

The directory name suffix is a hint (`-e`/`-eng` → eng, `-f`/`-fra` →
fra, `-spa` → spa, `-deu` → deu, etc.) but is unreliable because many
source PDFs are bilingual (English + French bundled in the same OCR).

The authoritative signal is the **content** of the OCR text. Look for
`Edition YYYY (E)` / `Edition YYYY (F)` markers — they split the document
into language halves. Each half's terminology section produces localized
concepts for that language only.

When a single OCR file has both an English and a French terminology
section for the same term number (e.g. `3.1.1 water meter` in the EN half
and `3.1.1 compteur d'eau` in the FR half), **emit ONE concept file** with
both localized_concepts entries. See §5 for the file shape.

---

## 5. Output file shape

Every concept is written to:

```
/Users/mulgogi/src/oimlsmart/vocab/datasets/g18-complete/concepts/<pub-code>-<term-number>.yaml
```

Where `<term-number>` keeps its dotted form (e.g. `3.1.1`, `0.02`). The
filename must sort correctly within the directory; do not zero-pad.

### 5.1 Monolingual concept (English only)

```yaml
---
data:
  identifier: r49-1-2013-eng-3.1.1
  localized_concepts:
    eng: cdb6f5ae-4b74-5939-b6c8-172f443823a0
  domains:
  - concept_id: section-terms
    source: urn:oiml:pub:r:49-1:2013
    ref_type: section
  sources:
  - origin:
      ref:
        source: OIML R 49-1:2013
        version: '2013'
    locality:
      type: clause
      reference_from: '3.1.1'
    type: authoritative
status: valid
id: d6289843-9b43-53b5-9094-a971cf9258de
schema_version: '3'
---
data:
  dates:
  - date: '2026-07-13T00:00:00+00:00'
    type: accepted
  definition:
  - content: instrument intended to measure continuously, memorize, and display the
      volume of water passing through the measurement transducer at metering conditions
  examples: []
  id: r49-1-2013-eng-3.1.1-eng
  notes:
  - content: A water meter includes at least a measurement transducer, a calculator
      and an indicating device.
  - content: A water meter may be a combination meter (see 3.1.16).
  sources:
  - origin:
      ref:
        source: OIML R 49-1:2013
        version: '2013'
    locality:
      type: clause
      reference_from: '3.1.1'
    type: authoritative
  terms:
  - type: expression
    normative_status: preferred
    designation: water meter
  language_code: eng
  entry_status: valid
date_accepted: '2026-07-13T00:00:00+00:00'
id: cdb6f5ae-4b74-5939-b6c8-172f443823a0
```

### 5.2 Bilingual concept (English + French)

```yaml
---
data:
  identifier: r49-2013-e-3.1.1
  localized_concepts:
    eng: 761e18c2-3e32-54bd-aa65-e44761c7ff02
    fra: 1aaf90ee-ce4e-571c-9e3b-52ee934548c3
  domains:
  - concept_id: section-terms
    source: urn:oiml:pub:r:49:2013
    ref_type: section
  sources:
  - origin:
      ref:
        source: OIML R 49:2013
        version: '2013'
    locality:
      type: clause
      reference_from: '3.1.1'
    type: authoritative
status: valid
id: e740a1ac-0058-5c0f-ab9b-617503e3cbf2
schema_version: '3'
---
data:
  dates:
  - date: '2026-07-13T00:00:00+00:00'
    type: accepted
  definition:
  - content: instrument intended to measure continuously the volume of water...
  examples: []
  id: r49-2013-e-3.1.1-eng
  notes: []
  sources:
  - origin:
      ref:
        source: OIML R 49:2013
        version: '2013'
    locality:
      type: clause
      reference_from: '3.1.1'
    type: authoritative
  terms:
  - type: expression
    normative_status: preferred
    designation: water meter
  language_code: eng
  entry_status: valid
date_accepted: '2026-07-13T00:00:00+00:00'
id: 761e18c2-3e32-54bd-aa65-e44761c7ff02
---
data:
  dates:
  - date: '2026-07-13T00:00:00+00:00'
    type: accepted
  definition:
  - content: instrument destiné à mesurer en continu le volume d'eau...
  examples: []
  id: r49-2013-e-3.1.1-fra
  notes: []
  sources:
  - origin:
      ref:
        source: OIML R 49:2013
        version: '2013'
    locality:
      type: clause
      reference_from: '3.1.1'
    type: authoritative
  terms:
  - type: expression
    normative_status: preferred
    designation: compteur d'eau
  language_code: fra
  entry_status: valid
date_accepted: '2026-07-13T00:00:00+00:00'
id: 1aaf90ee-ce4e-571c-9e3b-52ee934548c3
```

### 5.3 Source array shape (canonical glossarist v3)

The validator requires every `sources[].origin.ref.source` to resolve to a
URN, register ref, or bibliography id. **Use this canonical shape:**

```yaml
sources:
- origin:
    ref:
      source: OIML R 49-1:2013
      version: '2013'
  locality:
    type: clause
    reference_from: '3.1.1'
  type: authoritative
```

Field rules:
- `origin.ref.source` — the OIML publication ref (e.g. `OIML R 49-1:2013`),
  always matches the publication's `oiml_ref` from the helper.
- `origin.ref.version` — the publication year as a string.
- `locality.type` — `clause` for term entries, `section` for whole-section refs.
- `locality.reference_from` — the term number as a string.
- `type` — `authoritative` for the publication where the term appears.

### 5.4 Cross-references (VIM X.Y, VIML X.Y, ISO/IEC ..., etc.)

If the OCR'd entry has a citation like `[Source: OIML V 2-200:2012 (VIM)
3.8]` or `[VIML 5.14]` or `adapted from VIM 5.20`, **do NOT add it as a
second `sources[]` entry** — the validator will reject it because the
citation string doesn't resolve to a bibliography id.

Instead, **append the citation to the localized concept's `notes`**:

```yaml
notes:
- content: 'A water meter includes a transducer.'
- content: 'Source citation: OIML V 2-200:2012 (VIM) 3.8, modified — "meter" replaces "measuring system"'
```

This preserves the information without breaking validation. A future pass
can structure these into proper `related[]` cross-references.

**Only one `sources[]` entry per localized concept** — the OIML publication
where the term appears.

---

## 6. UUIDs (must be deterministic)

Use **UUID v5** with namespace `6b1d8e3a-8f9c-4c2b-bf5e-1a4d2c7b9e05`:

- **Outer concept id** → name = `v0|<pub-code>|<term-number>`
- **Localized concept id** → name = `v0|<pub-code>|<term-number>|<language-code>`

A Ruby helper is checked into the repo. Generate UUIDs with:

```sh
cd /Users/mulgogi/src/oimlsmart/vocab
ruby -Ilib -roiml/v0 -e 'puts Oiml::G18Dynamic::UuidV5.generate(Oiml::G18Dynamic::UuidNamespace::NAMESPACE_UUID, ARGV[0])' "g18-complete|r49-1-2013-eng|3.1.1"
# => d6289843-9b43-53b5-9094-a971cf9258de
```

**Always pass the exact name string** to the helper. Never invent UUIDs by
hand or use random UUIDs — re-extraction must produce byte-identical
files. If you write a concept and need its UUIDs, generate them with the
helper for the exact `v0|<pub>|<num>` and `v0|<pub>|<num>|<lang>` strings.

For batch efficiency, you can compute UUIDs for many names at once:

```sh
ruby -Ilib -roiml/v0 -e '
names = ARGV
names.each do |n|
  puts "#{n}\t#{Oiml::G18Dynamic::UuidV5.generate(Oiml::G18Dynamic::UuidNamespace::NAMESPACE_UUID, n)}"
end
' "g18-complete|r49-1-2013-eng|3.1.1" "g18-complete|r49-1-2013-eng|3.1.1|eng" "g18-complete|r49-1-2013-eng|3.1.1|fra"
```

---

## 7. Deriving `ref`, `urn`, `version` from the pub code

The pub code (directory name) parses as:
`<kind><number>-<year>[-suffixes]-<lang>`, e.g.:

| pub-code | ref | urn | version |
|---|---|---|---|
| `r49-1-2013-eng` | `OIML R 49-1:2013` | `urn:oiml:pub:r:49-1:2013` | `2013` |
| `d11-2013-e` | `OIML D 11:2013` | `urn:oiml:pub:d:11:2013` | `2013` |
| `v2-200-2012-e` | `OIML V 2-200:2012` | `urn:oiml:pub:v:2-200:2012` | `2013` |
| `b10-1-2004amendment-2006-eng` | `OIML B 10-1:2004 (amendment-2006)` | `urn:oiml:pub:b:10-1:2004` | `2004` |
| `r87-2008errata-eng` | `OIML R 87:2008 (errata)` | `urn:oiml:pub:r:87:2008` | `2008` |
| `r49-1-2013-fra` | `OIML R 49-1:2013` | `urn:oiml:pub:r:49-1:2013` | `2013` |
| `r137-1-2-2012-fra` | `OIML R 137-1-2:2012` | `urn:oiml:pub:r:137-1-2:2012` | `2012` |

Rules:
- **kind**: uppercase first letter (r→R, d→D, v→V, b→B, g→G, e→E, s→S).
- **number**: everything between kind and the trailing 4-digit year,
  including internal dashes (`49-1`, `2-200`, `137-1-2`).
- **year**: the last 4-digit run before the language suffix.
- **urn kind**: lowercase (`r`, `d`, `v`, `b`, `g`, `e`, `s`).
- **urn shape**: `urn:oiml:pub:<kind>:<number>:<year>` — no other suffix.
- **ref shape**: `OIML <KIND> <NUMBER>:<YEAR>` — append ` (<suffix>)` only
  when the directory has `amendment-YYYY`, `errata[-YYYY]`, `annexes`, or
  `sup` markers.

A Ruby helper is available:

```sh
ruby -Ilib -roiml/v0 -e '
ARGV.each do |code|
  pub = Oiml::G18Dynamic::PublicationCode.parse(code)
  puts [code, pub.oiml_ref, pub.urn, pub.year].join("\t")
end
' r49-1-2013-eng d11-2013-e v2-200-2012-e
```

Use it whenever you're unsure — don't guess.

---

## 8. Edge cases

1. **OCR merged two words** ("Términosy" for "Términos y"): preserve the
   term designation verbatim from the OCR — do not silently fix OCR
   errors. If the OCR is unreadable for the designation, skip the entry
   and note it in your report.

2. **Term with no definition, only a citation** ("see VIM 3.8"):
   - Leave `definition: []`.
   - Put the citation in `notes` as `{content: "Source citation: <text>"}`.
   - Keep the single `sources[]` entry pointing at THIS publication.

3. **Term with multiple designations** (synonyms listed on separate
   lines): use the first as the preferred designation; record the rest as
   additional `terms` entries with `normative_status: admitted`.

   ```yaml
   terms:
   - type: expression
     normative_status: preferred
     designation: equipment under test
   - type: expression
     normative_status: admitted
     designation: EUT
   ```

4. **Abbreviations** ("Abbreviation: EUT"): if the abbreviation appears
   in the body, add it as an admitted term (as above). Don't lose it.

5. **Same term number in two parts of the same publication** (Part 1 and
   Part 2 both define `3.1.1`): merge into one concept, taking the first
   occurrence per language. Do not emit two files with the same name.

6. **Math expressions** (`$Q_{1}$`, `$E_{0}$`): preserve verbatim in the
   designation/definition. Do not render.

7. **`## 3.1 Water meter and its constituents` group headers**: these are
   NOT term entries — they introduce a sub-group. Skip them.

8. **Bare `3. 7` style numbering** (OCR dropped the `##`): treat as a
   term entry number `3.7` if the line is *only* that number and is
   followed by a designation on the next non-empty line.

9. **PDF page artefacts** (running headers/footers that OCR embedded mid-
   text, page numbers like `... 5` appended to titles): strip them from
   the section title when matching, but do not let them otherwise affect
   extraction.

10. **Spanish / German / Arabic / Farsi / Chinese terminology sections**:
    extract them with the appropriate ISO 639-2 language code. The header
    keywords to look for are in §2.

11. **VIM / VIML source documents** (`v1-*`, `v2-200-*`, `v2-1993`):
    skip. VIM and VIML have their own authoritative datasets in this
    repo (`datasets/vim-*/`, `datasets/viml-*/`); including them in V 0
    would duplicate concepts and confuse the browse experience.

12. **Bilingual same-OCR duplicates across `-e`/`-f` directories**
    (e.g. `r35-2007-e` and `r35-2007-f` both bundle EN+FR): emit each
    pub-code's concepts per the standard rule. The directory name is the
    unit of provenance; even if the source PDF content is identical, the
    concepts get separate files with separate UUIDs because their
    `dataset_id` differs.

13. **Translation variants** (`-f`, `-spa`, `-fas`, `-ara`, `-deu`, etc.
    of an English document): **emit**, do not skip. V 0 is observational
    — each language edition is a separate observation of how the term is
    rendered in that language. Skipping translations would lose the
    non-English designations, which are first-class data.

14. **Boilerplate terminology** (terms repeated verbatim from D 11 / VIM
    / VIML): emit. V 0 records every appearance — repetition IS the data.

15. **Mirror documents** that reproduce VIM/VIML definitions verbatim
    with a `[Source: VIM ...]` citation: emit, with the citation captured
    in `sources[].raw`. V 0 sees them.

16. **Multi-part bundles across separate directories** (e.g. `r134-1`,
    `r134-2`, `r144-1`, `r144-2`, `r144-3`): treat each directory as
    its own publication. Emit `<pub-code>-<term-number>.yaml` per
    directory. Do not merge across directories even when they share a
    root publication number — the directories are distinct OIML
    publications with distinct URNs.

17. **Annex-style numbering** (`Annex 1`, `A.1`, `A1.2`, etc.): use the
    prefix as-is in the filename and identifier. Example: a term defined
    in `Annex 1, section 1` becomes `<pub-code>-A1-1.yaml` with
    `clause: 'A1-1'`.

18. **Legal-regulation style "definitions"** (e.g. `"X" means ...`):
    skip unless they have explicit numeric term-entry numbers. The V 0
    concept-browser needs a stable number to address concepts; prose
    definitions without numbers don't have one.

19. **Math expressions** ($Q_{1}$, $\Delta m$, $\tau_{0.5}$): preserve
    the OCR text verbatim — do not convert LaTeX to ASCII or vice versa.
    If the OCR rendered the math as plain text (e.g. `Q1`, `∆m`), keep
    that. Do not invent LaTeX.

20. **Math symbol terms** (e.g. the symbol `Q` defined as a quantity):
    use `type: symbol` in the `terms` array. The full allowed `type`
    values are: `expression`, `symbol`, `abbreviation`, `letter-symbol`.

21. **Multi-line note sub-items** (`Note 1: ... a) sub ... b) sub ...`):
    keep as a single note with the sub-items inline. Do not split into
    multiple notes — the sub-items belong to the parent note.

22. **Publications that only cite VIM/VIML/JCGM without restating
    definitions** (the terminology clause is just `For terminology, see
    OIML V 2-200`): skip. No own terms to extract.

23. **Year=0 publications** (`r76-zho`, `v1-srp`, etc. — directories
    without a year): process normally; the helper handles year=0.

24. **OCR-reordered headers** (very common in older side-by-side
    bilingual PDFs): match each definition to the correct header by
    reading the content. Do not blindly pair sequential (header,
    definition) — verify by content.

25. **Multiple terminology sections in the same document** (Section 3 +
    Section 4 + Annex): extract all of them. Use the original numbering
    (`3.1.1`, `4.1`, `A1-1`) — do not re-number.

26. **Unnumbered glossaries** (terms listed by name only, no numbers):
    skip. The concept-browser needs a stable addressable identifier;
    prose glossaries without numbers don't have one.

27. **Hybrid sections** (`Abbreviations and Terminology`, mixing an
    abbreviation table with numbered definitions): extract only the
    numbered term entries. Skip the abbreviation list unless each
    abbreviation has its own number.

28. **Large multi-dimensional terminology sections** (e.g. 100+ entries
    in `r76-1`): extract ALL of them, not just a sample. The V 0 dataset
    is comprehensive — partial extraction defeats its purpose. If you
    are running low on budget, extract as many as you can in numerical
    order and clearly report where you stopped.

---

## 9. File writing rules

- Use the **Write** tool to create each YAML file. Do not append.
- Each file must end with a trailing newline.
- Use straight ASCII quotes (`'` and `"`) — never curly quotes.
- Indent with **2 spaces**, never tabs.
- Strings with `:`, leading dashes, or special chars must be
  single-quoted in YAML (e.g. `reference_from: '3.1.1'`, `version: '2013'`).
- **Watch for ` : ` (space-colon-space) inside definition strings** —
  it breaks YAML parsing. Always double-quote any definition/note string
  that contains ` : ` (e.g. `content: "Definition: includes (in the text :
  conductivity) all..."`).
- **French apostrophes (`d'influence`, `l'eau`)** inside single-quoted
  YAML strings break parsing. Use double-quotes for any string containing
  `'` (apostrophe).
- **Double-quotes inside strings** must be escaped as `\"` when the YAML
  value is double-quoted.
- Empty arrays are `[]` on one line, not omitted.

After writing each batch, spot-check by reading one of your files back
and confirming it has:
- a leading `---` separator
- exactly 1 outer doc + 1 doc per language
- all UUIDs match what the helper produces
- no YAML syntax errors (load with `ruby -ryaml -e 'YAML.load_stream(File.read(ARGV[0]))' <file>` — no output means OK)

---

## 10. When to skip a publication

Skip (do not emit any concept files) when:
- The directory has no `ocr.md`.
- The document is a non-technical publication (B 1 constitution, meeting
  minutes, brochure, bulletin, certificate, errata slip with no terms,
  amendment slip with no terms).
- The document has only normative references / scope / foreword but no
  terminology section.
- The OCR is so garbled that you cannot reliably identify term entries
  (note this in your report).

Record every skipped publication in your final report with the reason.

---

## 11. Report format

When you finish, send a brief plain-text report listing:
- Count of publications processed
- Count of concepts emitted
- Count of publications skipped (with reasons)
- Any publications where OCR quality made extraction unreliable
- Any patterns you noticed that should feed back into this spec

Keep the report under 300 words. The team lead will compile a summary.

---

## 12. Reference: vim-2012 concept files

For shape reference, look at any file in
`/Users/mulgogi/src/oimlsmart/vocab/datasets/vim-2012/concepts/` — they
follow the same multi-doc glossarist v3 format. The only differences for
V 0:

- `data.domains` uses `concept_id: section-terms` (not `section-N`) and
  `source: urn:oiml:pub:<kind>:<num>:<year>` (pointing at the OIML
  publication the term came from, not a VIM/VIML URN).
- `data.sources` includes the OIML publication ref + clause + version.
- `data.related` is empty (no supersedes chain — V 0 is observational).

That's it. The rest of the shape (dates, definition, examples, notes,
terms, language_code, entry_status) is identical.
