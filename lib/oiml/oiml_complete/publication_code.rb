# frozen_string_literal: true

module Oiml
  module OimlComplete
    # Parsed identity of an OIML publication directory name.
    #
    # Examples of inputs (the directory names under ocr-output/):
    #   r49-1-2013-e            → R 49-1, 2013, eng
    #   d11-2013-e              → D 11,   2013, eng
    #   v2-200-2012-e           → V 2-200, 2012, eng
    #   r49-1-2013-spa          → R 49-1, 2013, spa
    #   b10-1-2004amendment-2006-eng
    #                          → B 10-1, 2004 (amended 2006), eng
    #   r87-2008errata-eng      → R 87, 2008 (errata), eng
    #   r60-2017annexes-eng     → R 60, 2017 (annexes), eng
    #   r137-1-2-2012-fra       → R 137-1-2, 2012, fra
    #
    # The PublicationCode is the source of truth for:
    #   - `oiml_ref`   → "OIML R 49-1:2013" (used in concept sources + bib)
    #   - `urn`        → "urn:oiml:pub:r:49-1:2013"
    #   - `dataset_id` → "r49-1-2013-e" (the raw directory slug; stable key)
    PublicationCode = Data.define(:raw, :kind, :number, :year, :language, :suffix) do
      LANGUAGE_SUFFIX_MAP = {
        "e" => "eng", "eng" => "eng",
        "f" => "fra", "fra" => "fra",
        "spa" => "spa",
        "deu" => "deu",
        "ara" => "ara",
        "fas" => "fas",
        "zho" => "zho",
        "ukr" => "ukr",
        "pol" => "pol",
        "srp" => "srp",
      }.freeze

      AMENDMENT_RE = /amendment-(\d{4})/.freeze
      ERRATA_RE = /errata(?:-(\d{4}))?/.freeze
      ANNEXES_RE = /annexes/.freeze
      SUP_RE = /sup/.freeze

      def self.parse(slug)
        normalized = slug.to_s.downcase
        suffix_match = normalized.match(/-(#{LANGUAGE_SUFFIX_MAP.keys.join('|')})\z/)
        lang_suffix = suffix_match && suffix_match[1]
        stem = suffix_match ? normalized[0...suffix_match.offset(0)[0]] : normalized

        amendment = stem.match(AMENDMENT_RE)
        errata = stem.match(ERRATA_RE)
        annexes = stem.match(ANNEXES_RE)
        sup = stem.match(SUP_RE)

        annotations = []
        annotations << "amendment-#{amendment[1]}" if amendment
        annotations << (errata[1] ? "errata-#{errata[1]}" : "errata") if errata
        annotations << "annexes" if annexes
        annotations << "sup" if sup

        body = stem
        body = body.sub(AMENDMENT_RE, "")
        body = body.sub(ERRATA_RE, "")
        body = body.sub(ANNEXES_RE, "")
        body = body.sub(SUP_RE, "")
        body = body.sub(/-+\z/, "")

        kind_letter, number_part, year = split_kind_number_year(body)
        language = LANGUAGE_SUFFIX_MAP.fetch(lang_suffix, "eng")

        new(
          raw: slug.to_s,
          kind: kind_letter,
          number: number_part,
          year: year.to_i,
          language: language,
          suffix: annotations.empty? ? nil : annotations.join("+"),
        )
      end

      def self.split_kind_number_year(body)
        m = body.match(/\A([a-z]+)(.+)\z/)
        unless m
          raise ArgumentError, "unparseable publication code: #{body.inspect}"
        end
        kind_letter = m[1].upcase
        rest = m[2]

        year_match = rest.match(/(\d{4})\z/)
        year_str = year_match && year_match[1]
        number_part = year_match ? rest[0...year_match.offset(1)[0]] : rest
        number_part = number_part.sub(/-+\z/, "")

        [kind_letter, number_part, year_str || "0"]
      end
      private_class_method :split_kind_number_year

      def oiml_ref
        base = "OIML #{kind} #{number}:#{year}"
        return base unless suffix
        "#{base} (#{suffix})"
      end

      def urn
        "urn:oiml:pub:#{kind.downcase}:#{number.downcase}:#{year}"
      end

      def dataset_id
        raw
      end

      def citation_clause(term_number)
        "#{oiml_ref}, #{term_number}"
      end
    end
  end
end
