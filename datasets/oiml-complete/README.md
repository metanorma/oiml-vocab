# OIML Complete Vocabulary (`datasets/oiml-complete/`)

Comprehensive terminology index derived from all OIML publications. Every
terminology entry from every OIML publication — with full provenance back to
the source publication.

## What's in here

- **~5,900 concepts** across **~300 publications**
- **~2,300 bilingual** (eng+fra) concept files; the rest are monolingual
- **5 languages**: eng, fra, spa, deu, pol
- **120 sections** organized by publication family (e.g., `b-3` for OIML B 3,
  `r-49` for OIML R 49)
- Glossarist v3 multi-document YAML format

## How it's built

The dataset is **rebuilt from the sibling publications repo** at
`/Users/mulgogi/src/oimlsmart/publications/`. That repo contains a glossarist
dataset per publication under `sources/<slug>/glossarist/`, each with its own
`register.yaml`, `concepts/*.yaml`, and `bibliography.yaml`.

### Build script

```sh
ruby scripts/build_oiml_complete_from_publications.rb
```

The script:
1. **Scans** all `sources/*/glossarist/concepts/*.yaml` in the publications repo
2. **Groups** concept files by `(base_publication_slug, identifier)` — e.g.,
   `b3-2011-e/0003-001` and `b3-2011-f/0003-001` group together because they
   share base slug `b3-2011` and identifier `0003-001`
3. **Merges** multilingual concepts — each group with 2+ languages produces one
   bilingual (or multilingual) concept file with `localized_concepts` for each
   language
4. **Converts** v2 format → v3 (definition arrays, source shapes)
5. **Filters** sources to OIML-prefixed refs only (non-OIML cross-references
   like ISO/IEC, ASME are dropped from `sources[]`)
6. **Sets** `domains.concept_id` to the publication family (e.g., `b-3`)
7. **Computes** deterministic UUIDs (v5 with fixed namespace)
8. **Writes** to `datasets/oiml-complete/concepts/<pub-slug>-<seq>.yaml`
9. **Builds** `register.yaml` (sections, languages, metadata) and
   `bibliography.yaml` (all cited OIML publications)

### Multilingual correlation

The publications repo **already solved** multilingual correlation by using
**consistent identifiers** across language editions. Both the English
(`b3-2011-e`) and French (`b3-2011-f`) directories of OIML B 3:2011 use the
same identifier `0003-001` for the same concept ("measuring instrument" /
"instrument de mesure"). The build script simply merges files that share the
same `(base_slug, identifier)` key.

### v2 → v3 format conversion

The publications repo uses mixed v2/v3 glossarist format:
- `definition: ["text"]` (v2 string array) → `definition: [{content: "text"}]` (v3)
- `sources: [{ref: "VIM 3.1"}]` (v2 flat) → filtered (non-OIML cross-ref)
- The localized concept metadata (`language_code`, `entry_status`) is split
  across two YAML documents in the source; the build script merges them into
  one localized doc

### Post-build steps

After the build script runs, fix the bibliography for any source refs not yet
listed, then validate:

```sh
ruby scripts/validate_datasets.rb --datasets oiml-complete
```

## File naming convention

Each concept file: `<pub-slug>-<seq>.yaml`

| Source file | Base slug | Identifier | Seq | Output file |
|---|---|---|---|---|
| `b3-2011-e/0003-001.yaml` | `b3-2011` | `0003-001` | `1` | `b3-2011-1.yaml` |
| `d11-2013-e/0011-001.yaml` | `d11-2013` | `0011-001` | `1` | `d11-2013-1.yaml` |
| `r49-1-2013-eng/0049-001.yaml` | `r49-1-2013` | `0049-001` | `1` | `r49-1-2013-1.yaml` |

The language suffix is stripped from the publication slug for merged files.

## UUIDs

All UUIDs are deterministic (v5 with namespace `6b1d8e3a-8f9c-4c2b-bf5e-1a4d2c7b9e05`):
- Outer concept: `oiml-complete|<pub-slug>|<seq>`
- Localized concept: `oiml-complete|<pub-slug>|<seq>|<lang>`

## Concept browser wiring

In `site-config.yml`:
```yaml
- id: oiml-complete
  local_path: datasets/oiml-complete
  color: { light: '#166534', dark: '#22C55E' }
```
