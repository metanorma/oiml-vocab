# frozen_string_literal: true

module Oiml
  module G18Complete
    # Wraps an OCR markdown document for one publication.
    #
    # The OCR pipeline writes both `ocr.md` (single concatenated file) and
    # `ocr.json` (per-chunk structured payload with layout details). For V 0
    # we only consume the markdown — it already contains the full text in
    # reading order, which is all we need for terminology extraction.
    OcrDocument = Data.define(:path, :text) do
      def self.from_path(path)
        new(path: path, text: File.read(path))
      end

      def language_halves(splitter: LanguageSplitter.new, default_language: "eng")
        splitter.split(text, default_language: default_language)
      end

      def terminology_sections(matcher: TerminologyMatcher.new, default_language: "eng")
        halves = language_halves(default_language: default_language)
        halves.flat_map do |half|
          matcher.find_sections(half.text, language: half.language)
        end
      end
    end
  end
end
