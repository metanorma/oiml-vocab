# frozen_string_literal: true

require "fileutils"
require "pathname"
require "set"

module Oiml
  module G18Complete
    # Orchestrates the V 0 extraction pipeline.
    #
    # Flow:
    #   for each publication dir in source_root:
    #     Publication = PublicationCode.parse(dir.name)
    #     OcrDoc = OcrDocument.from_path(dir/ocr.md)
    #     sections = OcrDoc.terminology_sections
    #     term_entries = sections.flat_map { |s| s.term_entries }
    #     concepts = group_entries_by_number(term_entries, publication)
    #   emit all concepts + register + bibliography via DatasetWriter
    class Extractor
      PerPublication = Data.define(:publication, :sections_found, :entries_found, :concepts, :errors)

      def initialize(source_root:, date_accepted: "2026-07-13T00:00:00+00:00")
        @source_root = Pathname.new(source_root)
        @date_accepted = date_accepted
      end

      def call(limit: nil, only: nil, &on_progress)
        pub_dirs = discover_publications(only: only)
        pub_dirs = pub_dirs.first(limit) if limit

        per_publication = pub_dirs.map { |dir| process_publication(dir) }

        concepts = per_publication.flat_map(&:concepts)
        concepts = concepts.sort_by { |c| [c.publication.dataset_id, c.number] }

        publications = per_publication
          .select { |r| r.concepts.any? }
          .map(&:publication)
          .uniq(&:dataset_id)
          .sort_by(&:dataset_id)

        languages = per_publication
          .flat_map { |r| r.concepts.flat_map(&:languages) }
          .uniq
          .sort

        per_publication.each { |r| on_progress&.call(r) }

        {
          concepts: concepts,
          publications: publications,
          languages: languages,
          per_publication: per_publication,
        }
      end

      private

      def process_publication(dir)
        publication = PublicationCode.parse(dir.basename.to_s)
        ocr_path = dir + "ocr.md"
        unless ocr_path.exist?
          return PerPublication.new(publication: publication, sections_found: 0, entries_found: [], concepts: [], errors: ["ocr.md missing"])
        end

        document = OcrDocument.from_path(ocr_path.to_s)
        sections = document.terminology_sections(default_language: publication.language)
        entries = sections.flat_map { |s| s.term_entries }
        concepts = build_concepts_for_publication(publication, entries)

        PerPublication.new(
          publication: publication,
          sections_found: sections.size,
          entries_found: entries,
          concepts: concepts,
          errors: [],
        )
      rescue => e
        PerPublication.new(
          publication: publication,
          sections_found: 0,
          entries_found: [],
          concepts: [],
          errors: ["#{e.class}: #{e.message}"],
        )
      end

      def build_concepts_for_publication(publication, entries)
        # Group by term number. Within a number, only one entry per
        # language is kept (the first occurrence) so that a multi-part
        # publication that repeats the same terminology section in each
        # part doesn't produce duplicate localized concepts for the same
        # language under one concept file.
        entries.group_by(&:number).map do |number, per_lang|
          localized = per_lang
            .uniq { |e| e.language }
            .map do |e|
              LocalizedConcept.from_term_entry(e, publication: publication, date_accepted: @date_accepted)
            end
          Concept.new(
            publication: publication,
            number: number,
            localized_concepts: localized,
            date_accepted: @date_accepted,
          )
        end
      end

      def discover_publications(only: nil)
        # Include every directory under source_root, even ones without
        # ocr.md. The per-publication result will record the missing-file
        # error so the operator can see which publications need OCR. This
        # also makes the count of `per_publication` equal to the number of
        # publication directories, which is what tests and reports expect.
        dirs = @source_root.children.select(&:directory?).sort_by(&:basename)
        return dirs unless only

        wanted = only.split(",").map(&:strip).to_set
        dirs.select { |d| wanted.include?(d.basename.to_s) }
      end
    end
  end
end
