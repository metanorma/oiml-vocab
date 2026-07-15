# frozen_string_literal: true

module Oiml
  module OimlComplete
    # Splits an OCR markdown document into per-language halves.
    #
    # Many OIML source PDFs are bilingual (English + French in the same
    # document, separated by an "Edition (E) ... Edition (F)" boundary or
    # a parallel-text title block). The splitter produces one LanguageHalf
    # per detected language so that downstream parsing treats each language
    # as its own stream.
    LanguageHalf = Data.define(:language, :text)

    class LanguageSplitter
      # Markers that introduce a new language half in the OCR text.
      # These appear at chunk boundaries in the source PDF: the title page
      # is repeated per language, prefixed by an "Edition YYYY (L)" marker.
      EDITION_MARKER_RE = /Edition\s+\d{4}\s*\(([A-Za-z]+)\)/.freeze

      # Map the single-letter / short language codes used inside the document
      # text to ISO 639-2 (which is what glossarist uses).
      INNER_LANG_MAP = {
        "E" => "eng", "EN" => "eng",
        "F" => "fra", "FR" => "fra",
        "S" => "spa", "ES" => "spa",
        "D" => "deu", "DE" => "deu", "GER" => "deu",
        "A" => "ara", "AR" => "ara",
        "P" => "fas", "FA" => "fas", "PS" => "fas",
        "C" => "zho", "ZH" => "zho",
        "R" => "rus", "RU" => "rus",
      }.freeze

      def split(ocr_text, default_language: "eng")
        markers = scan_edition_markers(ocr_text)
        return [LanguageHalf.new(language: default_language, text: ocr_text)] if markers.empty?

        # Each half runs from the END of its marker to the START of the
        # next marker. This keeps the marker line itself out of the body
        # text so downstream parsing sees only the content of one
        # language half at a time.
        markers.each_with_index.map do |(lang, _full_match, start_pos, end_pos), i|
          body_end = markers[i + 1] ? markers[i + 1][2] : ocr_text.length
          LanguageHalf.new(
            language: INNER_LANG_MAP.fetch(lang.upcase, lang.downcase),
            text: ocr_text[end_pos...body_end],
          )
        end
      end

      private

      def scan_edition_markers(text)
        matches = []
        text.to_s.scan(EDITION_MARKER_RE) do |(lang)|
          m = Regexp.last_match
          matches << [lang, m.to_s, m.offset(0)[0], m.offset(0)[1]]
        end
        # Deduplicate by start position (the title block can repeat the
        # same marker line at the same offset).
        matches.uniq { |(l, _s, start_pos, _end_pos)| start_pos }
               .sort_by { |(_, _, start_pos, _)| start_pos }
      end
    end
  end
end
