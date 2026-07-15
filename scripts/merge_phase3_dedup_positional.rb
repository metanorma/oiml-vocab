#!/usr/bin/env ruby
# frozen_string_literal: true

# Phase 3: Handle remaining unmerged multilingual concepts.
#
# Step 1: Deduplicate same-language OCR variants (e.g., -e + -eng → keep one).
# Step 2: Positional matching for cross-language pairs with close counts.

require "yaml"
require "pathname"
require "set"

CONCEPTS = Pathname.new(File.expand_path("../datasets/g18-complete/concepts", __dir__))
SOURCE_ROOT = Pathname.new("/Users/mulgogi/src/oimlsmart/publications/reference-docs/ocr-output")
PUB_CODES = Set.new(SOURCE_ROOT.children.select(&:directory?).map(&:basename).map(&:to_s))

LANG_MAP = { "e" => "eng", "f" => "fra", "eng" => "eng", "fra" => "fra",
             "spa" => "spa", "deu" => "deu" }.freeze

def resolve_pub_code(basename)
  parts = basename.split("-")
  (parts.length - 1).downto(1) do |i|
    c = parts[0...i].join("-")
    return c if PUB_CODES.include?(c)
  end
  nil
end

def suffix_of(pub_code)
  %w[eng fra spa deu ara fas zho rus por ita nld pol srp ukr e f].each do |s|
    return s if pub_code.end_with?("-#{s}")
  end
  nil
end

def lang_of(suffix)
  LANG_MAP[suffix] || "eng"
end

def strip_suffix(pub_code)
  s = suffix_of(pub_code)
  s ? pub_code.sub(/-#{s}$/, "") : pub_code
end

def dump(docs)
  parts = docs.map { |d| YAML.dump(d).sub(/\A---\n/, "") }
  "---\n" + parts.join("---\n") + "\n"
end

# ---- Build index ----
by_base = Hash.new { |h, k| h[k] = [] }

CONCEPTS.children.each do |f|
  basename = f.basename(".yaml").to_s
  pc = resolve_pub_code(basename)
  next unless pc
  base = strip_suffix(pc)
  next if base == pc  # already merged

  suffix = suffix_of(pc)
  lang = lang_of(suffix)
  term = basename.delete_prefix("#{pc}-")

  by_base[base] << { file: f, pub_code: pc, basename: basename, base: base,
                      suffix: suffix, lang: lang, term: term }
end

deduped = 0
positionally_merged = 0
deleted = 0

by_base.each do |base, entries|
  # Group by language
  by_lang = entries.group_by { |e| e[:lang] }

  # Step 1: Within each language, deduplicate (multiple suffixes for same lang)
  by_lang.each do |lang, lang_entries|
    # Group by term number within language
    by_term = lang_entries.group_by { |e| e[:term] }
    by_term.each do |term, dupes|
      next if dupes.size < 2
      # Keep the one with more localized docs (more content), delete others
      sorted = dupes.sort_by { |e| -File.size(e[:file]) }
      keeper = sorted.first
      sorted.drop(1).each do |d|
        File.delete(d[:file]) if d[:file].exist?
        deleted += 1
      end
      deduped += 1
    end
  end

  # Rebuild after dedup
  remaining = entries.select { |e| e[:file].exist? }
  by_lang = remaining.group_by { |e| e[:lang] }
  next if by_lang.size < 2

  # Step 2: Positional matching across languages
  # Sort each language by term number
  sorted_langs = by_lang.transform_values { |es| es.sort_by { |e| e[:term] } }
  counts = sorted_langs.map { |_, es| es.size }

  # Only match if counts are close (within 20%)
  min_count = counts.min
  max_count = counts.max
  next if min_count.to_f / max_count < 0.8
  next if min_count < 3  # too few to be reliable

  # Pair by position (first with first, second with second, etc.)
  primary_lang = by_lang.key?("eng") ? "eng" : sorted_langs.keys.first
  primary_list = sorted_langs[primary_lang]

  other_langs = sorted_langs.reject { |l, _| l == primary_lang }

  (0...min_count).each do |i|
    primary = primary_list[i]
    next unless primary && primary[:file].exist?

    primary_docs = YAML.load_stream(primary[:file].read)
    outer = primary_docs.first
    loc = outer["data"]["localized_concepts"] ||= {}
    merged_docs = [primary_docs.first]
    merged_langs_seen = Set.new(loc.keys)

    other_langs.each do |_, other_list|
      other = other_list[i]
      next unless other && other[:file].exist?
      other_docs = YAML.load_stream(other[:file].read)
      other_localized = other_docs.drop(1).select do |d|
        d.is_a?(Hash) && d.dig("data", "language_code")
      end

      other_localized.each do |olc|
        lc = olc["data"]["language_code"]
        next if merged_langs_seen.include?(lc)
        merged_langs_seen << lc
        other_loc = other_docs.first["data"]["localized_concepts"] || {}
        loc[lc] = other_loc[lc]
        merged_docs << olc
      end
    end

    next if merged_docs.size < 2

    # Write merged file with base pub-code
    new_id = "#{base}-#{primary[:term]}"
    outer["data"]["identifier"] = new_id
    out_path = CONCEPTS + "#{new_id}.yaml"

    unless out_path.exist?
      File.write(out_path, dump(merged_docs))
      positionally_merged += 1

      # Delete originals
      [primary, *other_langs.flat_map { |_, l| [l[i]] }.compact].each do |e|
        next unless e && e[:file].exist? && e[:file] != out_path
        File.delete(e[:file])
        deleted += 1
      end
    end
  end
end

puts "Same-language deduped: #{deduped} groups"
puts "Positionally merged: #{positionally_merged} groups"
puts "Deleted: #{deleted} files"
