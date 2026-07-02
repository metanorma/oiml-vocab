# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project overview

This is a deployment repository for the **VIML** (International Vocabulary of Legal Metrology, OIML V 1) concept browser and the **VIM** (International Vocabulary of Metrology, OIML V 2-200) concept dataset. It uses the `@glossarist/concept-browser` npm package — a statically deployable Vue 3 SPA — to serve an interactive terminology browser on GitHub Pages.

This is NOT a software project. It is a deployment configuration: site config, datasets, content pages, and CI.

## Build commands

```sh
# Install concept-browser
npm install --ignore-scripts @glossarist/concept-browser
npm install --prefix node_modules/@glossarist/concept-browser sharp 2>/dev/null || true

# Build the static site
npx concept-browser build

# Preview locally
npx vite preview
```

Output goes to `dist/`. All configuration is read from `site-config.yml` — no environment variables needed.

## Key files

- `site-config.yml` — All site configuration (branding, features, dataset source, base path, languages). Hand-edited, committed to the repo.
- `datasets/viml-2022/` — Glossarist v3 dataset for VIML 2022 (135 concept YAML files + `register.yaml`)
- `datasets/viml-2013/` — Glossarist v3 dataset for VIML 2013 (135 concepts, includes section A)
- `datasets/viml-2000/` — Glossarist v3 dataset for VIML 2000 (44 concepts)
- `datasets/viml-1968/` — Glossarist v3 dataset for VIML 1968 (OCR, needs manual review)
- `datasets/vim-2012/` — Glossarist v3 dataset for VIM 2012 (144 concepts, current)
- `datasets/vim-2010/` — Glossarist v3 dataset for VIM 2010 (143 concepts)
- `datasets/vim-2007/` — Glossarist v3 dataset for VIM 2007 (143 concepts)
- `datasets/vim-1993/` — Glossarist v3 dataset for VIM 1993 (120 concepts, OCR)
- `about-eng.md` / `about-fra.md` — Site-level about page content (English and French, covers both VIML and VIM)
- `logos/` — OIML logo SVGs (main, light variant, dark variant)
- `scripts/validate_datasets.rb` — CI gate, dataset invariant validation (read-only)
- `scripts/compare_viml_1968_index.rb` — Read-only comparator (viml-1968 index vs concepts)
- `scripts/match_supersedes.rb` — Find supersedes relationships across editions (default `--dry-run`)
- `scripts/ocr_pdf_glm.rb` — GLM-OCR driver for any source PDF (auto-splits >100p)
- `scripts/ocr_vim_1993_zai.py` — Z.AI GLM-OCR API client (legacy, writes to `/tmp/`)
- `scripts/historical/` — One-shot generation scripts that seeded each edition (incl. the retired `audit_vim.rb` / `audit_viml.rb` which compared against stale cached HTML). **Do not re-run** — datasets are authoritative. See `scripts/historical/README.md`.
- `reference-docs/{vim,viml}-*-ocr/glm-ocr.md` — Clean GLM OCR output for all 7 source PDFs (VIM 1993/2007/2010/2012, VIML 1968/2000/2013)

## Configuration conventions

- `basePath: /vocab/` — GitHub Pages subpath deployment. No `BASE_PATH` env var.
- `localPath: datasets/viml-2022` — Dataset source directory. No `DATASET_SOURCE_*` env var.
- `ref: "OIML V 1:2022"` — Publication reference shown in sidebar provenance.
- All config is in `site-config.yml`. The CI uses only `GITHUB_TOKEN`.

### i18n in site-config.yml

Localized text uses **language maps** — a `translations` field keyed by ISO 639-2 language codes. The top-level `title`, `subtitle`, and `description` fields hold the default-language value; `translations` holds the non-default languages:

```yaml
title: OIML Vocabularies
subtitle: International Vocabularies of Metrology
description: Terminology from the International Vocabularies of Metrology published by OIML
translations:
  fra:
    subtitle: Vocabulaires internationaux de métrologie
    description: Terminologie des Vocabulaires internationaux de métrologie publiés par l'OIML
```

Do NOT use language suffixes like `title_fra` or `description_fra`. Always use nested language maps. This pattern applies to all localized text: site-level translations, dataset translations, group translations, and page translations.

## CI

Push to `main` triggers `.github/workflows/build_deploy.yml`:
1. Install `@glossarist/concept-browser` from npm (always released version, never git)
2. Run `npx concept-browser build`
3. Deploy `dist/` to GitHub Pages

Note: Edition scrapers in `scripts/historical/` are one-shots that have already run. They are not part of routine workflow. See `scripts/historical/README.md`.

## Datasets

### VIML (multi-edition)

Four VIML editions are available as separate datasets:

| Edition | Path | Concepts | Notes |
|---------|------|----------|-------|
| 2022 (current) | `datasets/viml-2022/` | 135 | Bilingual EN/FR, scraped from viml.oiml.info |
| 2013 | `datasets/viml-2013/` | 135 | Bilingual EN/FR, scraped from Word HTML (includes section A) |
| 2000 | `datasets/viml-2000/` | 44 | Bilingual EN/FR, scraped from PDF HTML |
| 1968 | `datasets/viml-1968/` | 276 | French only, OCR-derived — 302 index entries map to 276 unique concepts |

Cross-edition `supersedes` relations are encoded declaratively in each concept's `related` array — only the newer concept declares what it supersedes. `superseded_by` is derived at render time by concept-browser from incoming `supersedes` graph edges.

### VIM (multi-edition)

Five VIM editions are tracked (four are exposed in the concept-browser; VIM 1984 is a stub pending source OCR):

| Edition | Path | Concepts | Notes |
|---------|------|----------|-------|
| 2012 (current) | `datasets/vim-2012/` | 144 | Bilingual EN/FR, scraped from jcgm.bipm.org/vim |
| 2010 | `datasets/vim-2010/` | 144 | Bilingual EN/FR, scraped from pdftotext; mirrors 2007 + adds 2.53 |
| 2007 | `datasets/vim-2007/` | 144 | Bilingual EN/FR, authoritative (issue #27) + 2.53 added |
| 1993 | `datasets/vim-1993/` | 120 | Bilingual EN/FR, OCR HTML (6 chapters, 5.29-5.33 do not exist) |
| 1984 (stub) | `datasets/vim-1984/` | 70 stubs | Not exposed in concept-browser; minimal concept files for URN resolution |

VIM 2007/2010 share the same concept numbering (5 chapters, 144 concepts each). VIM 1993 has 6 chapters with 120 concepts (1.1-1.22, 2.1-2.9, 3.1-3.16, 4.1-4.31, 5.1-5.28, 6.1-6.14). VIM 1984 uses zero-padded numbering (1.02, 2.05, 6.14) matching its source.

**VIM 2007 and VIM 1993 are the fully editor-validated authoritative editions** (issue #27). Editors have manually checked every concept against GLM OCR output for the source PDFs (`reference-docs/{vim-1993,vim-2007}-ocr/glm-ocr.md` — and likewise for VIM 2010/2012). Cross-edition supersession:

- `supersedes` source `urn:oiml:pub:v:2:1984` → VIM 1984 (1st edition; stub only — 70 minimal concept files referenced by VIM 1993)
- `supersedes` source `urn:oiml:pub:v:2:1993` → VIM 1993 (VIM 2007 and VIM 2010 both link here, since VIM 2010 is the corrected print of the same edition as VIM 2007)
- `supersedes` source `urn:oiml:pub:v:2:2007` → VIM 2007 (VIM 2012 supersedes 2007 directly)

The validator (`scripts/validate_datasets.rb`) verifies that every URN-prefixed supersedes ref points to an actual concept file when the target edition is present in `datasets/`.

Datasets are authoritative — hand-curated by editors. To fix data, edit the YAML directly. Do not regenerate from source (the original scrapers are in `scripts/historical/` for provenance only).

### G18 (OIML G 18:2010 — term-usage registry)

`datasets/g18-2010/` is **preserved as canonical source data** (2132 entries, 1207 unique terms, 287 with multiple publication instances, 101 cross-refs to VIM/VIML). It is **disabled in the concept-browser** (not in `site-config.yml`; see PR #41) because G 18 is structurally a *term-usage registry*, not a vocabulary — VIM/VIML are *authoritative concept definitions*; G 18 is *observations of where terms are used across OIML publications*.

`datasets/g18-202X/` is the **new draft edition** (Edition 202X, 2CD — TC1/P3/N008). 2689 entries extracted from `reference-docs/TC1_P3_N008-2CD_revision_of_G18-clean.docx`. Status: `draft`. Year placeholder "202X" to be updated upon publication.

The dedicated UI for G 18 lives in a separate repo: [`oimlsmart/g18-registry`](https://github.com/oimlsmart/g18-registry) — deployed at https://oimlsmart.github.io/g18-registry/ and tracks implementation steps 2–6 (per-term model migration, TC/SC attribution, browsing UI, AI consistency checks). See issue [#42](https://github.com/oimlsmart/vocab/issues/42) for the full direction.

**Do not delete `datasets/g18-2010/` or `datasets/g18-202X/`** from this repo. They are the source-of-truth consumed by the g18-registry migration.
