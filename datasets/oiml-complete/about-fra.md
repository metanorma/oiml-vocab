# Vocabulaire complet de l'OIML

Le **Vocabulaire complet de l'OIML** est un jeu de données dérivé qui
consolide chaque entrée terminologique définie dans chaque publication OIML
en un seul vocabulaire navigable.

## Ce qui est inclus

Chaque terme défini dans la section « Termes et définitions » /
« Terminologie » de chaque publication OIML — Recommandations (R), Documents
(D), Guides (G), Publications fondamentales (B) et Rapports d'experts (E) —
est capturé ici comme son propre concept.

De nombreux termes apparaissent dans plusieurs publications avec des
définitions, notes ou portées différentes. **Chaque occurrence est conservée
comme un concept distinct** afin que les lecteurs puissent voir comment le
même terme est utilisé différemment dans le corpus OIML.

## Structure

Les concepts sont organisés en **sections par famille de publications** — par
exemple, tous les termes des publications OIML B 3 (B 3:2003, B 3:2011)
apparaissent dans la section « B 3 », et tous les termes des publications
OIML R 49 dans la section « R 49 ».

## Couverture multilingue

Lorsqu'une publication existe en versions anglaise et française, les termes
sont **corrélés en un seul concept bilingue** — chaque langue conserve sa
propre désignation, définition et notes. Certaines publications ont également
des éditions en espagnol, allemand ou polonais.

## Provenance des sources

Chaque concept conserve la provenance bibliographique complète :

- La **publication** où le terme apparaît (source autoritaire ou de lignée)
- Le cas échéant, le **vocabulaire amont** (VIM ou VIML) dans lequel le terme
  a été initialement défini, avec une chaîne de provenance montrant comment il
  a été reproduit du vocabulaire vers la publication

## Construction

Ce jeu de données est généré à partir des données glossarist produites par le
pipeline [`oimlsmart/publications`](https://github.com/oimlsmart/publications),
qui extrait la terminologie des PDF de publications OCRisés. Le script de
construction se trouve dans `scripts/build_oiml_complete_from_publications.rb`.
