# frozen_string_literal: true

module Oiml
  module OimlComplete
    # Finds terminology sections inside a LanguageHalf's text.
    #
    # Open/closed: adding a new pattern means appending to HEADER_PATTERNS,
    # never editing the matching algorithm itself.
    class TerminologyMatcher
      # Each entry: [regex, captures]
      # The regex must anchor to a `## N <title>` line (case-insensitive).
      # The title can be any text that contains a terminology keyword.
      # Patterns are checked in order; first hit wins. Add a new language
      # or phrasing by appending to this list — never edit an existing
      # regex.
      HEADER_PATTERNS = [
        # English / French / Spanish / German terminology section titles.
        # Allow any text around the keyword to absorb trailing page numbers
        # and parenthesised alternates like "(Terms and definitions)".
        /\A##\s+\d+(?:\.\d+)*\b[^\n]*\b(?:terms?\s+(?:and|et)\s+(?:definitions?|d[ée]finitions?|abbreviations?|symbols?|designations?|units?|references?))\b/iu,
        /\A##\s+\d+(?:\.\d+)*\b[^\n]*\bterminolog(?:y|ie|ía|ia)\b/iu,
        /\A##\s+\d+(?:\.\d+)*\b[^\n]*\b(?:definitions?|d[ée]finitions?|definitionen)\b/iu,
        /\A##\s+\d+(?:\.\d+)*\b[^\n]*\b(?:vocabular(?:y|ie|ire)|glossar(?:y|ie|ire))\b/iu,
        # "Basic and general terms in metrology" and the French equivalent.
        /\A##\s+\d+\s+(?:basic\s+(?:and\s+)?general\s+terms?\s+in\s+(?:legal\s+)?metrology)\b/iu,
        /\A##\s+\d+\s+termes?\s+(?:de\s+base|fondamentaux?(?:\s+en\s+(?:métrologie\s+légal))?)\b/iu,
      ].freeze

      # Markers that *introduce* a sub-section header like "## 3.1 Water meter
      # and its constituents" — used to know where term entries actually
      # begin inside a terminology section.
      SUB_HEADER_RE = /\A##\s+\d+\.\d+(?:\.\d+)*\s+[\p{L}]/.freeze

      def find_sections(half_text, language: "eng")
        lines = half_text.split(/\r?\n/, -1)
        sections = []
        i = 0
        while i < lines.size
          line = lines[i]
          if terminology_header?(line)
            section_number = parse_section_number(line)
            title = parse_section_title(line)
            start_i = i + 1
            end_i = find_section_end(lines, start_i, section_number)
            body = lines[start_i...end_i].join("\n")
            sections << TerminologySection.new(
              title: title,
              number: section_number,
              language: language,
              body: body,
            )
            i = end_i
          else
            i += 1
          end
        end
        sections
      end

      private

      def terminology_header?(line)
        return false unless line&.start_with?("#")

        HEADER_PATTERNS.any? { |re| line.match?(re) }
      end

      def parse_section_number(line)
        m = line.match(/\A##\s+(\d+(?:\.\d+)*)\b/)
        m && m[1]
      end

      def parse_section_title(line)
        line.sub(/\A##\s+\d+(?:\.\d+)*\s*/, "").strip
      end

      def find_section_end(lines, start_i, section_number)
        parent_depth = section_number.to_s.split(".").size
        start_i.upto(lines.size - 1) do |j|
          candidate = lines[j]
          next unless candidate.start_with?("#") || candidate.match?(/\A\s*\d+\.\s+\p{L}/)

          # End on the next sibling or parent header (## 4 after ## 3, etc.).
          header_m = candidate.match(/\A##\s+(\d+)(?:\.\d+)*\s/)
          if header_m
            sibling_num = header_m[1].to_i
            current_top = section_number.to_s.split(".").first.to_i
            return j if sibling_num > current_top
          end

          # Also stop on top-level heading with `#` (level-1).
          return j if candidate.start_with?("# ") && !candidate.start_with?("## ")
        end
        lines.size
      end
    end
  end
end
