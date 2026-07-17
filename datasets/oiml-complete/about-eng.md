# OIML Complete Vocabulary

The **OIML Complete Vocabulary** is a derived dataset that consolidates every
terminology entry defined inside every OIML publication into a single
browsable vocabulary.

## What's included

Every term defined in the "Terms and definitions" / "Terminology" section of
each OIML publication — Recommendations (R), Documents (D), Guides (G), Basic
Publications (B), and Expert Reports (E) — is captured here as its own
concept.

Many terms appear in multiple publications with different definitions,
notes, or scope. **Each appearance is preserved as a separate concept** so
readers can see how the same term is used differently across the OIML corpus.

## Structure

Concepts are organized into **sections by publication family** — for example,
all terms from OIML B 3 publications (B 3:2003, B 3:2011) appear in section
"B 3", and all terms from OIML R 49 publications appear in section "R 49".

## Multilingual coverage

Where a publication exists in both English and French editions, the terms are
**correlated into a single bilingual concept** — each language retains its own
designation, definition, and notes. Some publications also have Spanish,
German, or Polish editions.

## Source provenance

Each concept carries full bibliographic provenance:

- The **publication** where the term appears (authoritative or lineage source)
- Where applicable, the **upstream vocabulary** (VIM or VIML) that the term
  was originally defined in, with a lineage chain showing how it was
  reproduced from the vocabulary into the publication

## How it's built

This dataset is generated from the glossarist data produced by the
[`oimlsmart/publications`](https://github.com/oimlsmart/publications) pipeline,
which extracts terminology from OCR'd publication PDFs. The build script is at
`scripts/build_oiml_complete_from_publications.rb`.
