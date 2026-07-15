# frozen_string_literal: true

module Oiml
  module OimlComplete
    # A single terminology entry extracted from a publication.
    #
    # One TermEntry corresponds to one numbered item like
    #   ## 3.1.1
    #   water meter
    #   instrument intended to measure continuously...
    #   Note 1: ...
    #
    # It is the per-language unit. Multiple TermEntries with the same
    # `number` across languages of the same publication are grouped into
    # one Concept by the Extractor.
    TermEntry = Data.define(
      :number,             # "3.1.1" — the source's term numbering
      :language,           # ISO 639-2 (eng, fra, ...)
      :designations,       # Array<String> of preferred + alternative designations
      :preferred,          # String (first designation) — convenience accessor
      :definition,         # String (may be nil if OCR cut off)
      :notes,              # Array<String>
      :examples,           # Array<String>
      :source_citation,    # String | nil — e.g. "OIML V 2-200:2012 (VIM) 3.8"
      :raw_text,           # String — original body for debugging
    ) do
      def has_designation?
        preferred.to_s.strip.length.positive?
      end
    end
  end
end
