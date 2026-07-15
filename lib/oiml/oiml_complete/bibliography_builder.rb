# frozen_string_literal: true

module Oiml
  module OimlComplete
    # Builds the dataset bibliography.yaml — one entry per unique OIML
    # publication that contributed at least one term to the dataset.
    #
    # Multiple directories can map to the same OIML reference (e.g.
    # `b18-2017-e` and `b18-2017-f` both → "OIML B 18:2017"). We dedupe
    # by `oiml_ref` and accumulate the per-language `dataset_id`s inside
    # each entry so provenance is preserved without duplicate bibliography
    # ids (which would fail the project validator's uniqueness check).
    #
    # Format: an Array of `{ "id" => ..., "ref" => ..., "urn" => ... }`
    # entries. Array form (not keyed-by-ref) per the project memory rule.
    class BibliographyBuilder
      def build(publications)
        publications
          .group_by(&:oiml_ref)
          .map { |ref, group| entry_for(ref, group) }
          .sort_by { |e| e["id"] }
      end

      private

      def entry_for(ref, group)
        first = group.first
        {
          "id" => ref,
          "urn" => first.urn,
          "type" => "OIML publication",
          "dataset_ids" => group.map(&:dataset_id).sort,
        }
      end
    end
  end
end
