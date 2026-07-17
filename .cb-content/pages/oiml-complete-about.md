---
title: "About"
type: "page"
---

<h2>OIML Complete Vocabulary</h2>
<p>The <strong>OIML Complete Vocabulary</strong> is a derived dataset that consolidates every terminology entry defined inside every OIML publication into a single browsable vocabulary.</p>
<h3>What's included</h3>
<p>Every term defined in the "Terms and definitions" / "Terminology" section of each OIML publication — Recommendations (R), Documents (D), Guides (G), Basic Publications (B), and Expert Reports (E) — is captured here as its own concept.</p>
<p>Many terms appear in multiple publications with different definitions, notes, or scope. <strong>Each appearance is preserved as a separate concept</strong> so readers can see how the same term is used differently across the OIML corpus.</p>
<h3>Structure</h3>
<p>Concepts are organized into <strong>sections by publication family</strong> — for example, all terms from OIML B 3 publications (B 3:2003, B 3:2011) appear in section "B 3", and all terms from OIML R 49 publications appear in section "R 49".</p>
<h3>Multilingual coverage</h3>
<p>Where a publication exists in both English and French editions, the terms are <strong>correlated into a single bilingual concept</strong> — each language retains its own designation, definition, and notes. Some publications also have Spanish, German, or Polish editions.</p>
<h3>Source provenance</h3>
<p>Each concept carries full bibliographic provenance:</p>
<ul><li>The <strong>publication</strong> where the term appears (authoritative or lineage source)</li><li>Where applicable, the <strong>upstream vocabulary</strong> (VIM or VIML) that the term</li></ul>
<p>  was originally defined in, with a lineage chain showing how it was   reproduced from the vocabulary into the publication</p>
<h3>How it's built</h3>
<p>This dataset is generated from the glossarist data produced by the <a href="https://github.com/oimlsmart/publications" target="_blank"><code>oimlsmart/publications</code></a> pipeline, which extracts terminology from OCR'd publication PDFs. The build script is at <code>scripts/build_oiml_complete_from_publications.rb</code>.</p>
