# OIML G 18 dynamic datasets

This directory holds two derived glossarist v3 datasets built from the
OIML publication corpus. Both are regenerated from the source OCR
manually (no automated extraction) — see
[`TODO.consolidate/01-g18-complete-extraction-spec.md`](../../TODO.consolidate/01-g18-complete-extraction-spec.md)
for the contract every extracting agent follows.

## Datasets

### `datasets/g18-complete/`

The **comprehensive** terminology index: every terminology entry that
appears inside every OIML publication, observed via the OCR pipeline at
[`publications/reference-docs/ocr-output/`](../../../publications/reference-docs/ocr-output/).
One concept YAML file per `(publication, term_number)` pair. Many
designations repeat across publications with different definitions,
notes, or scope — every appearance is its own concept.

- **Status**: derived/observational.
- **Concept identity**: `(publication_directory, term_number)`. Two
  language editions of the same source PDF are SEPARATE concepts (per
  spec §8.12) — duplicated terminology is the data, not a bug.
- **Size**: ~11,000 concepts across ~370 publications; 5 languages
  (eng, fra, spa, deu, pol).
- **Build**: extract agents read each OCR end-to-end and write YAML by
  hand. Re-extraction is idempotent (deterministic UUIDs).

### `datasets/g18-current/`

The **tip-filtered** view of `g18-complete`: one concept per
`(family, term_number)`, where `family = (kind, base_number)` and only
the newest edition ("tip") per family is kept. All language editions at
tip collapse into a single multi-language concept.

- **Status**: derived/observational.
- **Concept identity**: `(family, term_number)`. Multiple language
  editions at the tip year are merged into ONE concept file with
  multi-language `localized_concepts`.
- **Size**: ~3,000 unique tip concepts.
- **Build**: derived mechanically from `g18-complete` by
  `scripts/g18_current_vs_g18.rb --build`. No manual work.

## Generating `g18-current` from `g18-complete`

Pre-reqs: `g18-complete` is up-to-date and validates.

```sh
cd /Users/mulgogi/src/oimlsmart/vocab

# 1. Re-aggregate g18-complete's register + bibliography from on-disk concepts
ruby scripts/aggregate_g18_complete_register.rb

# 2. Re-gen UUIDs in g18-complete (deterministic; idempotent)
ruby scripts/g18_complete_fix_uuids.rb
ruby scripts/g18_complete_check_uuids.rb   # verifies all UUIDs match

# 3. Build g18-current (correlates languages, filters to tip editions)
ruby scripts/g18_current_vs_g18.rb --build

# 4. Validate both datasets
ruby scripts/validate_datasets.rb --datasets g18-complete,g18-current
```

The build is fully deterministic — re-running on the same `g18-complete`
produces byte-identical `g18-current` output (UUID v5 with a fixed
namespace + name input).

## Cross-reference report

The `g18_current_vs_g18.rb` script also writes per-category reports at
[`reference-docs/g18-current-vs-g18/`](../../reference-docs/g18-current-vs-g18/)
that compare the tip concepts to `datasets/g18-202X/` (the draft new
edition of OIML G 18):

- `01-at-tip.txt` — G 18:202X entries citing current tip editions ✓
- `02-below-tip-has-clause.txt` — G 18 stale, term still exists at tip
- `03-below-tip-no-clause.txt` — G 18 stale, term removed/renamed
- `04-no-family-citation-missing.txt` — G 18 entries with no/invalid citation
- `05-no-family-pub-in-corpus.txt` — G 18 cites a pub whose family is in OCR corpus but has no extracted concepts
- `06-no-family-pub-missing-from-corpus.txt` — G 18 cites pubs we don't have OCR for
- `06b-no-family-withdrawn.txt` — G 18 entries to **REMOVE** (citing withdrawn pubs)
- `07-tip-editions-missing-from-g18.txt` — tip concepts G 18 should add
- `08-summary.txt` — top-line numbers + publications needing OCR acquisition

## Source data

OCR output is at
[/Users/mulgogi/src/oimlsmart/publications/reference-docs/ocr-output/](file:///Users/mulgogi/src/oimlsmart/publications/reference-docs/ocr-output/).
The corpus covers ~817 OIML publications. Publications whose terminology
sections were not extracted (brochures, governance docs, test report
formats, citation-only sections) are documented in agent reports per
round.
