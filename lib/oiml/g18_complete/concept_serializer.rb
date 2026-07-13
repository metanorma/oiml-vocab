# frozen_string_literal: true

module Oiml
  module G18Complete
    # Translates a Concept into the Array<Hash> form expected by glossarist v3.
    #
    # This is the ONLY place that knows about glossarist's wire shape.
    # Models stay free of `to_h` / serialization concerns.
    #
    # Output: an Array of one outer-document Hash plus one Hash per
    # localized concept. Pass the result to MultiDocYaml to get the
    # final multi-doc YAML string.
    class ConceptSerializer
      SCHEMA_VERSION = "3".freeze
      STATUS = "valid".freeze
      ENTRY_STATUS = "valid".freeze
      DEFAULT_DOMAIN = "section-terms".freeze

      def serialize(concept)
        localized_concept_uuids = concept.localized_concepts.map do |lc|
          [lc.language, localized_uuid(concept, lc)]
        end

        outer = {
          "data" => {
            "identifier" => concept.dataset_identifier,
            "localized_concepts" => localized_concept_uuids.to_h,
            "domains" => [{
              "concept_id" => DEFAULT_DOMAIN,
              "source" => concept.publication.urn,
              "ref_type" => "section",
            }],
            "sources" => concept.sources_for_outer,
          },
          "status" => STATUS,
          "id" => concept.outer_uuid,
          "schema_version" => SCHEMA_VERSION,
        }

        localized_docs = concept.localized_concepts.map do |lc|
          localized_doc(lc, localized_uuid(concept, lc))
        end

        [outer, *localized_docs]
      end

      private

      def localized_uuid(concept, localized)
        UuidV5.generate(
          UuidNamespace::NAMESPACE_UUID,
          "#{UuidNamespace::DATASET_ID}|#{concept.publication.dataset_id}|#{concept.number}|#{localized.language}",
        )
      end

      def localized_doc(lc, uuid)
        {
          "data" => {
            "dates" => [
              { "date" => lc.date_accepted, "type" => "accepted" },
            ],
            "definition" => definition_array(lc.definition),
            "examples" => lc.examples.map { |e| { "content" => e } },
            "id" => lc.identifier,
            "notes" => lc.notes.map { |n| { "content" => n } },
            "sources" => lc.sources,
            "terms" => terms_array(lc),
            "language_code" => lc.language,
            "entry_status" => lc.entry_status,
          },
          "date_accepted" => lc.date_accepted,
          "id" => uuid,
        }
      end

      def definition_array(definition)
        return [] if definition.nil? || definition.strip.empty?

        [{ "content" => definition }]
      end

      def terms_array(localized)
        return [] if localized.designation.nil? || localized.designation.strip.empty?

        [{
          "type" => "expression",
          "normative_status" => "preferred",
          "designation" => localized.designation,
        }]
      end
    end
  end
end
