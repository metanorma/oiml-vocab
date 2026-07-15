# frozen_string_literal: true

module Oiml
  module OimlComplete
    # Parses a TerminologySection body into an Array<TermEntry>.
    #
    # The parser is intentionally tolerant: OIML OCR varies wildly across
    # editions, languages, and decades of publishing conventions. The
    # algorithm is:
    #
    #   1. Walk the body line-by-line.
    #   2. Recognise a term-entry start: a header line whose entire payload
    #      is a sub-number of the section (e.g. `## 3.1.1`, `### 3.1.1`,
    #      bare `3.1.1`, or the OCR-flattened `3. 7` form).
    #   3. After the number header, the next non-empty, non-header line is
    #      the designation. (Some OCRs put a `##` in front of the
    #      designation too; treat a `## <word>` line after a number header
    #      as the designation, not a new sub-section.)
    #   4. Following lines until the next number header are the body.
    #      Classify them into definition / notes / examples / source citation
    #      based on textual cues.
    #   5. Sub-section titles like `## 3.1 Water meter and its constituents`
    #      do *not* start a term entry — they are group headings and are
    #      skipped.
    class TermEntryParser
      # A whole line that is just a sub-number (with optional markdown hashes).
      NUMBER_HEADER_RE = /\A[#]{0,6}\s*(\d+(?:\.\d+)+|\d+\.\s+\d+)\s*\z/.freeze

      # A sub-section group heading, e.g. `## 3.1 Water meter and its constituents`.
      GROUP_HEADER_RE = /\A[#]+\s+\d+(?:\.\d+)*\s+\p{L}/.freeze

      NOTE_RE    = /\A[#]*\s*(?:note(?:\s+\d+)?|n\.\s*b)\s*[:\-–]\s*/i.freeze
      EXAMPLE_RE = /\A[#]*\s*(?:example|exemple|beispiel|ejemplo)(?:\s+\d+)?\s*[:\-–]\s*/i.freeze

      SOURCE_BRACKET_RE = /\A\[\s*source\s*:/i.freeze
      SOURCE_PLAIN_RE   = /\A\s*\[?(?:source|VIM|VIML|ISO|IEC|JCGM)\b/i.freeze

      def parse(section)
        entries = []
        lines = section.body.split(/\r?\n/, -1)

        builder = nil

        lines.each do |line|
          stripped = line.to_s.strip

          if group_header?(stripped)
            flush(entries, builder)
            builder = nil
            next
          end

          number = number_header_match(stripped, section.number)
          if number
            flush(entries, builder)
            builder = Builder.new(number, section.language)
            next
          end

          next if builder.nil?
          next if stripped.empty?

          populate(builder, stripped)
        end

        flush(entries, builder)
        entries
      end

      # Mutable work object used while parsing one term entry. Frozen
      # immutable TermEntry values are emitted at the end. Keeping this
      # internal means callers never see a half-built entry.
      Builder = Struct.new(:number, :language, :designations, :preferred,
                           :definition, :notes, :examples, :source_citation,
                           :raw_text) do
        def initialize(number, language)
          super(number, language, [], nil, nil, [], [], nil, +"")
        end

        def term_entry
          TermEntry.new(
            number: number,
            language: language,
            designations: designations.dup,
            preferred: preferred,
            definition: definition,
            notes: notes.dup,
            examples: examples.dup,
            source_citation: source_citation,
            raw_text: raw_text.to_s,
          )
        end
      end
      private_constant :Builder

      private

      def group_header?(stripped)
        stripped.match?(GROUP_HEADER_RE)
      end

      def number_header_match(stripped, section_number)
        return nil unless stripped

        m = stripped.match(NUMBER_HEADER_RE)
        return nil unless m

        candidate = m[1].gsub(/\s+/, "")

        return nil if candidate == section_number.to_s

        depth = candidate.split(".").size
        section_depth = section_number.to_s.split(".").size
        return nil if depth < section_depth + 1
        return nil unless candidate.start_with?("#{section_number}.")

        candidate
      end

      def populate(builder, stripped)
        builder.raw_text << stripped << "\n"

        case stripped
        when SOURCE_BRACKET_RE
          builder.source_citation = strip_source(stripped)
        when SOURCE_PLAIN_RE
          builder.source_citation ||= strip_source(stripped)
        when NOTE_RE
          builder.notes << strip_label(stripped, NOTE_RE)
        when EXAMPLE_RE
          builder.examples << strip_label(stripped, EXAMPLE_RE)
        else
          if builder.preferred.nil? || builder.preferred.strip.empty?
            designation = stripped.sub(/\A[#]+\s+/, "").strip
            unless designation.empty?
              builder.designations << designation
              builder.preferred = designation
            end
          elsif builder.definition.nil? || builder.definition.empty?
            builder.definition = stripped
          else
            builder.definition = "#{builder.definition} #{stripped}"
          end
        end
      end

      def strip_label(stripped, re)
        stripped.sub(re, "").strip
      end

      def strip_source(stripped)
        stripped
          .sub(/\A\s*\[\s*/, "")
          .sub(/\]\s*\z/, "")
          .sub(/\Asource\s*:\s*/i, "")
          .strip
      end

      def flush(entries, builder)
        return if builder.nil?
        return if builder.preferred.nil? || builder.preferred.strip.empty?

        entries << builder.term_entry
      end
    end
  end
end
