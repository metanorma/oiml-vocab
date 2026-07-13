# frozen_string_literal: true

module Oiml
  module G18Complete
    # Builds the dataset register.yaml in glossarist v3 shape.
    class RegisterBuilder
      attr_reader :dataset_id, :urn, :ref, :year

      def initialize(dataset_id: UuidNamespace::DATASET_ID,
                     urn: "urn:oiml:dataset:g18-complete",
                     ref: "OIML G 18 complete",
                     year: Time.now.utc.year,
                     owner: "OIML",
                     source_repo: "https://github.com/oimlsmart/vocab")
        @dataset_id = dataset_id
        @urn = urn
        @ref = ref
        @year = year
        @owner = owner
        @source_repo = source_repo
      end

      def build(concept_count:, languages:)
        {
          "schema_type" => "glossarist",
          "schema_version" => "3",
          "id" => dataset_id,
          "ref" => ref,
          "ref_aliases" => [ref],
          "year" => year,
          "urn" => urn,
          "urn_aliases" => ["#{urn}*"],
          "status" => "valid",
          "owner" => @owner,
          "source_repo" => @source_repo,
          "tags" => %w[metrology oiml vocabulary derived],
          "languages" => languages,
          "language_order" => language_order(languages),
          "derived" => true,
          "derived_from" => "cross-publication terminology extraction",
          "concept_count" => concept_count,
        }
      end

      private

      def language_order(languages)
        canonical = %w[eng fra spa deu ara fas zho rus ita por nld]
        ordered = canonical & languages
        ordered + (languages - ordered).sort
      end
    end
  end
end
