# frozen_string_literal: true

module Oiml
  module G18Complete
    # Per-language payload for one Concept, in glossarist v3 shape.
    #
    # This is a value object — *not* a serialization layer. There is no
    # `to_h` here. The ConceptSerializer is responsible for translating
    # this into a Hash suitable for YAML emission.
    LocalizedConcept = Data.define(
      :language,         # ISO 639-2 ("eng", "fra", ...)
      :identifier,       # human-readable id, e.g. "r49-1-2013-e-3.1.1-eng"
      :designation,      # preferred term
      :definition,       # String | nil
      :notes,            # Array<String>
      :examples,         # Array<String>
      :sources,          # Array<Hash{ref,clause,version}> — citation provenance
      :date_accepted,    # ISO 8601 date string
      :entry_status,     # "valid"
    ) do
      def self.from_term_entry(entry, publication:, date_accepted:)
        new(
          language: entry.language,
          identifier: "#{publication.dataset_id}-#{entry.number}-#{entry.language}",
          designation: entry.preferred,
          definition: entry.definition,
          notes: Array(entry.notes),
          examples: Array(entry.examples),
          sources: build_sources(entry, publication),
          date_accepted: date_accepted,
          entry_status: "valid",
        )
      end

      def self.build_sources(entry, publication)
        sources = [{
          "ref" => publication.oiml_ref,
          "clause" => entry.number,
          "version" => publication.year.to_s,
        }]
        if entry.source_citation
          sources << { "raw" => entry.source_citation }
        end
        sources
      end
      private_class_method :build_sources
    end
  end
end
