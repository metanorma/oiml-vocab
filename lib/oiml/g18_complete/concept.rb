# frozen_string_literal: true

module Oiml
  module G18Complete
    # A glossarist v3 outer concept: groups one or more LocalizedConcepts
    # under a stable identity for a single (publication, term-number).
    #
    # Identity rules:
    #   - One concept per (publication, term-number). If both EN and FR
    #     exist for the same number, both live in `localized_concepts`.
    #   - UUIDs are deterministic (UUID v5) so re-running the extractor
    #     produces byte-stable files.
    Concept = Data.define(
      :publication,             # PublicationCode
      :number,                  # String — the term number ("3.1.1")
      :localized_concepts,      # Array<LocalizedConcept>
      :date_accepted,           # ISO 8601 date string
    ) do
      def dataset_identifier
        "#{publication.dataset_id}-#{number}"
      end

      def file_basename
        "#{publication.dataset_id}-#{number}.yaml"
      end

      def outer_uuid
        UuidV5.generate(
          UuidNamespace::NAMESPACE_UUID,
          "#{UuidNamespace::DATASET_ID}|#{publication.dataset_id}|#{number}",
        )
      end

      def languages
        localized_concepts.map(&:language)
      end

      def sources_for_outer
        [{
          "ref" => publication.oiml_ref,
          "clause" => number,
          "version" => publication.year.to_s,
        }]
      end
    end
  end
end
