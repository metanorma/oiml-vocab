---
title: "About"
type: "page"
---

<h2>Vocabulaire complet de l'OIML</h2>
<p>Le <strong>Vocabulaire complet de l'OIML</strong> est un jeu de données dérivé qui consolide chaque entrée terminologique définie dans chaque publication OIML en un seul vocabulaire navigable.</p>
<h3>Ce qui est inclus</h3>
<p>Chaque terme défini dans la section « Termes et définitions » / « Terminologie » de chaque publication OIML — Recommandations (R), Documents (D), Guides (G), Publications fondamentales (B) et Rapports d'experts (E) — est capturé ici comme son propre concept.</p>
<p>De nombreux termes apparaissent dans plusieurs publications avec des définitions, notes ou portées différentes. <strong>Chaque occurrence est conservée comme un concept distinct</strong> afin que les lecteurs puissent voir comment le même terme est utilisé différemment dans le corpus OIML.</p>
<h3>Structure</h3>
<p>Les concepts sont organisés en <strong>sections par famille de publications</strong> — par exemple, tous les termes des publications OIML B 3 (B 3:2003, B 3:2011) apparaissent dans la section « B 3 », et tous les termes des publications OIML R 49 dans la section « R 49 ».</p>
<h3>Couverture multilingue</h3>
<p>Lorsqu'une publication existe en versions anglaise et française, les termes sont <strong>corrélés en un seul concept bilingue</strong> — chaque langue conserve sa propre désignation, définition et notes. Certaines publications ont également des éditions en espagnol, allemand ou polonais.</p>
<h3>Provenance des sources</h3>
<p>Chaque concept conserve la provenance bibliographique complète :</p>
<ul><li>La <strong>publication</strong> où le terme apparaît (source autoritaire ou de lignée)</li><li>Le cas échéant, le <strong>vocabulaire amont</strong> (VIM ou VIML) dans lequel le terme</li></ul>
<p>  a été initialement défini, avec une chaîne de provenance montrant comment il   a été reproduit du vocabulaire vers la publication</p>
<h3>Construction</h3>
<p>Ce jeu de données est généré à partir des données glossarist produites par le pipeline <a href="https://github.com/oimlsmart/publications" target="_blank"><code>oimlsmart/publications</code></a>, qui extrait la terminologie des PDF de publications OCRisés. Le script de construction se trouve dans <code>scripts/build_oiml_complete_from_publications.rb</code>.</p>
