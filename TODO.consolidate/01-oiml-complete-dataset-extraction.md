# 01 — Build the OIML G 18 complete cross-publication terminology dataset

## Goal

Create a new dataset `datasets/g18-complete/` in glossarist v3 format that consolidates
the terminology defined inside every OIML publication. Unlike VIM (V 2-200) and
VIML (V 1), which are authoritative *concept definitions*, **V 0 is a derived
observational dataset**: every terminology entry that appears inside any OIML
publication is recorded here, with full provenance back to the publication it
came from.

The OIML publication codebase uses the prefix `V` for vocabularies
(V 1 = VIML, V 2-200 = VIM). This dataset is the cross-publication vocabulary
*derived from* the corpus, so it occupies the otherwise-unused `V 0` slot.

## Why this is needed

Today the only way to find how OIML documents use a term like "indicating
device" or "equipment under test" is to read each Recommendation/Document
individually. Many designations appear in dozens of publications with
**different definitions, notes, or scope**. There is no single index.

V 0 fills that gap: one concept-browser where every terminology appearance is
visible alongside its source publication, so a reader can see both the
variation and the consensus at a glance.

## Why extraction must be manual

OIML publications span six decades and many OCR pipelines. Terminology
sections vary wildly:

- Section titles: "Terms and definitions", "Terminology", "Termes et
  définitions", "Terminología", "0 TERMES DE BASE", "1.1. Definitions", ...
- Term headers: `## 3.1.1`, `### 3.1.1`, `3.1.1`, `3. 7`, `[VIML 5.14]`
- Some bilingual source PDFs interleave EN and FR in the same OCR file
- Older documents use prose definitions; modern ones use numbered entries
- OCR errors drop `#` characters, merge words ("Términosy" instead of
  "Términos y"), insert stray punctuation, etc.

Automated parsing cannot reliably recover the term/definition/notes/source
structure from this variety. **Every OCR document must be read end-to-end
by a reader who understands the content**, then converted to glossarist v3
YAML by hand. Regex-only extraction misses terms, misclassifies prose as
definitions, and silently drops source citations.

## Inputs

- **817 publications** at `/Users/mulgogi/src/oimlsmart/publications/reference-docs/ocr-output/<pub-code>/`
  - Each directory contains `ocr.md` (concatenated chunks) and `ocr.json`
    (structured chunks with `md_results`, `layout_visualization`, etc.).
  - `<pub-code>` is lowercase, e.g. `r49-1-2013-eng`, `d11-2013-e`,
    `v2-200-2012-e`, `b18-2017-f`.
- ~462 of 817 publications contain a terminology section (greppable as
  `## N <Term/Terminology/Definitions/...>` headers across multiple
  languages). The other ~355 have no terminology section and contribute
  nothing — that is expected.

## Output

- `datasets/g18-complete/`
  - `register.yaml` — glossarist v3 register with `urn: urn:oiml:dataset:g18-complete`,
    `ref: "OIML G 18 complete"`, `status: valid`, language list, `derived: true`.
  - `concepts/<pub-code>-<term-number>.yaml` — one glossarist v3 file per
    *(publication, term-number)* pair. Multi-document YAML:
    1. outer concept doc (`identifier`, `localized_concepts`, `sources`,
       `related`, `status`, `id`, `schema_version`)
    2. one localized concept doc per language extracted for that term
       (`eng`, `fra`, etc. — both live in the same file when the source
       publication provides both languages for the same term number).
  - `bibliography.yaml` — array form, one entry per unique OIML
    publication cited.

### Concept identity

Each *(publication, term-number)* pair is its own concept — the user
requirement is "many designations are duplicated but can have different
definitions and details, and we must show all of them". We do **not** merge
across publications. The OIML publication is recorded in:

- `data.sources[]` on the outer concept doc (`{ref: "OIML R 49-1:2013",
  clause: "3.1.1", version: "2013"}` style, matching glossarist v3),
- `bibliography.yaml` of the dataset.

### Language handling

- The OCR text of a single publication frequently contains both English and
  French halves (the source PDF is bilingual, separated by
  `Edition YYYY (E)` / `Edition YYYY (F)` markers).
- For each *(publication, term-number)*, if both halves have a parsed entry
  for that number, both go into the **same** concept file as
  `localized_concepts: {eng: ..., fra: ...}` (mirroring
  `datasets/vim-2012/concepts/1.1.yaml`).
- If only one language is present for a number, the concept is monolingual.
- Non-EN/FR languages (spa, deu, ara, fas, zho, etc.) are also captured as
  localized concepts under their ISO 639-2 code when present.

### Deterministic IDs

- All UUIDs are **UUID v5** with namespace `6b1d8e3a-8f9c-4c2b-bf5e-1a4d2c7b9e05`.
  This keeps output byte-stable across re-extractions.
- Name input for each UUID:
  - localized concept:
    `v0|<pub-code>|<term-number>|<language-code>`
  - outer concept: `v0|<pub-code>|<term-number>`

A reference Ruby implementation is at `lib/oiml/g18_complete/uuid_v5.rb` and can be
invoked as:

```ruby
$LOAD_PATH.unshift("lib"); require "oiml/g18_complete"
puts Oiml::G18Dynamic::UuidV5.generate(
  Oiml::G18Dynamic::UuidNamespace::NAMESPACE_UUID,
  "g18-complete|r49-1-2013-eng|3.1.1|eng",
)
# => cdb6f5ae-4b74-5939-b6c8-172f443823a0
```

## Manual extraction process

This dataset is produced by **5 parallel agents**, each handling ~163
publications from a partitioned list. Each agent:

1. Opens every `ocr.md` for its assigned publications.
2. Reads the entire document to find terminology section(s). A terminology
   section is any of:
   - `## N Terms and definitions` / `## N Termes et définitions` /
     `## N Términos y definiciones` / `## N Terminology` /
     `## N Terminologie` / `## N Definitions` / etc.
   - Includes parenthesised variants like `## 3 Terminology (Terms and
     definitions)` and trailing page numbers like `## 3 Terms and
     definitions ... 5`.
   - Section number can be 0, 1, 2, 3, 4, etc.
3. For each numbered term entry inside the section, captures:
   - the term number (e.g. `3.1.1`)
   - the preferred designation (the term itself)
   - the definition (verbatim)
   - all notes (verbatim, including `Note 1:`, `Note 2:` labels stripped)
   - all examples (verbatim)
   - any source citation (e.g. `[Source: OIML V 2-200:2012 (VIM) 3.8]`,
     `[VIML 5.14]`, `[VIM2.16]`)
   - the language code (eng, fra, spa, deu, ...)
4. Writes one glossarist v3 YAML file per *(publication, term-number)*
   pair to `datasets/g18-complete/concepts/<pub-code>-<term-number>.yaml`.
5. Skips publications with no terminology section (no file written).

The exact YAML shape, file naming, and edge cases are specified in
[`01-v0-extraction-spec.md`](./01-v0-extraction-spec.md). Every agent
follows that spec verbatim so output is consistent across buckets.

## Validation gate

After all 5 agents finish:

1. Generate `datasets/g18-complete/register.yaml` and `datasets/g18-complete/bibliography.yaml`
   from the concept files on disk.
2. Run the existing CI gate against the new dataset:

   ```sh
   ruby scripts/validate_datasets.rb --datasets g18-dynamic
   ```

3. Fix every error before declaring the task done.

The validator already supports a permissive i18n mode for derived datasets
(V 0 sets `derived: true`), so monolingual concepts don't fail the i18n
check.

## Acceptance criteria

1. `datasets/g18-complete/register.yaml` exists with `urn: urn:oiml:dataset:g18-complete` and
   `derived: true`.
2. `datasets/g18-complete/concepts/*.yaml` contains one file per *(publication,
   term-number)* pair found by manual reading of every OCR document.
3. Every concept file:
   - loads as multi-doc YAML with `schema_version: '3'`,
   - has at least one localized concept (`eng`, `fra`, or other),
   - has `data.sources[]` pointing to the publication it was extracted
     from,
   - has deterministic UUID v5 IDs (re-running produces byte-identical
     files).
4. `datasets/g18-complete/bibliography.yaml` lists every publication that
   contributed at least one term.
5. `ruby scripts/validate_datasets.rb --datasets g18-dynamic` returns 0 errors.

## Out of scope

- Cross-publication concept merging / aliasing — every appearance is its
  own concept. Future work can add `related: [{type: same-as, ref: ...}]`
  edges.
- Hand-curated editorial overrides — V 0 is purely machine-extracted.
  Editorial fixes belong in VIM/VIML, not here.
- Re-extraction of GLM-OCR corrections — agents use `ocr.md` as-is.
- Web UI for V 0 — wiring `datasets/g18-complete/` into `site-config.yml` is a
  separate task.
