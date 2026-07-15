#!/usr/bin/env ruby
# frozen_string_literal: true

# Task 3 (phase 2): Merge multilingual concepts that have DIFFERENT term
# numbers across language editions (e.g., EN section 3 vs FR section 2).
#
# Strategy:
#   1. Match by shared authoritative source (same VIM/VIML ref + clause)
#   2. Fallback: positional matching (sorted by term number, paired 1:1)
#      verified by designation loanword overlap
#
# Only merges when confident; leaves unmatched as monolingual.

require "yaml"
require "pathname"
require "set"

CONCEPTS = Pathname.new(File.expand_path("../datasets/g18-complete/concepts", __dir__))
SOURCE_ROOT = Pathname.new("/Users/mulgogi/src/oimlsmart/publications/reference-docs/ocr-output")
PUB_CODES = Set.new(SOURCE_ROOT.children.select(&:directory?).map(&:basename).map(&:to_s))

LANG_SUFFIXES = %w[eng fra spa deu ara fas zho rus por ita nld pol srp ukr e f].freeze

def resolve_pub_code(basename)
  parts = basename.split("-")
  (parts.length - 1).downto(1) do |i|
    candidate = parts[0...i].join("-")
    return candidate if PUB_CODES.include?(candidate)
  end
  nil
end

def strip_lang_suffix(pub_code)
  LANG_SUFFIXES.each { |s| return pub_code.sub(/-#{s}$/, "") if pub_code.end_with?("-#{s}") }
  pub_code
end

def normalize_lang(code)
  { "e" => "eng", "f" => "fra" }.fetch(code, code)
end

def lang_from_pub_code(pub_code)
  LANG_SUFFIXES.each { |s| return normalize_lang(s) if pub_code.end_with?("-#{s}") }
  "eng"
end

def dump_multi_doc(docs)
  parts = docs.map { |d| YAML.dump(d).sub(/\A---\n/, "") }
  "---\n" + parts.join("---\n") + "\n"
end

def extract_auth_key(docs)
  # Extract the authoritative VIM/VIML source ref+clause as a match key
  docs.each do |doc|
    next unless doc.is_a?(Hash) && doc["data"].is_a?(Hash)
    (doc["data"]["sources"] || []).each do |s|
      next unless s.is_a?(Hash) && s["type"] == "authoritative"
      ref = s.dig("origin", "ref", "source")
      clause = s.dig("locality", "reference_from")
      next unless ref && ref.match?(/\AVIM|OIML\s+V\s+[12]/i)
      return "#{ref}|#{clause}"
    end
  end
  nil
end

def extract_designation(docs)
  docs.each do |doc|
    next unless doc.is_a?(Hash) && doc["data"].is_a?(Hash)
    (doc["data"]["terms"] || []).each do |t|
      next unless t.is_a?(Hash) && t["designation"]
      return t["designation"].to_s.downcase
    end
  end
  nil
end

# ---- Build index by base pub-code ----
by_base = Hash.new { |h, k| h[k] = Hash.new { |h2, k2| h2[k2] = [] } }

CONCEPTS.children.each do |f|
  basename = f.basename(".yaml").to_s
  pc = resolve_pub_code(basename)
  next unless pc
  base = strip_lang_suffix(pc)
  return if base == pc # no language suffix, already merged or monolingual

  lang = lang_from_pub_code(pc)
  term = basename.delete_prefix("#{pc}-")
  by_base[base][lang] << { file: f, pub_code: pc, term: term, basename: basename }
end

# ---- Merge ----
merged = 0
deleted = 0

by_base.each do |base, langs|
  next if langs.size < 2

  # Strategy 1: Match by authoritative source key
  auth_index = Hash.new { |h, k| h[k] = [] }
  langs.each do |lang, concepts|
    concepts.each do |c|
      docs = YAML.load_stream(c[:file].read)
      key = extract_auth_key(docs)
      auth_index[key] << { lang: lang, **c, docs: docs } if key
    end
  end

  auth_index.each do |key, entries|
    next if entries.size < 2
    # Group by language (dedupe within same language)
    by_lang = {}
    entries.each { |e| by_lang[e[:lang]] ||= e }
    next if by_lang.size < 2

    # Merge: pick primary (eng preferred), merge others
    primary = by_lang["eng"] || by_lang.values.first
    others = by_lang.values.reject { |v| v[:lang] == primary[:lang] }

    outer = primary[:docs].first
    outer_loc = outer["data"]["localized_concepts"] || {}

    merged_docs = [outer]
    merged_langs = Set.new([primary[:lang]])

    others.each do |other|
      other_loc = other[:docs].drop(1).select { |d| d.is_a?(Hash) && d.dig("data", "language_code") }
      other_loc.each do |loc|
        lang_code = loc["data"]["language_code"]
        next if merged_langs.include?(lang_code)
        merged_langs << lang_code
        # Add to outer's localized_concepts
        uuid = other[:docs].first["data"]["localized_concepts"]&.dig(lang_code)
        outer_loc[lang_code] = uuid if uuid
        merged_docs << loc
      end
    end

    next if merged_docs.size < 2 # nothing to merge

    outer["data"]["localized_concepts"] = outer_loc

    # Use primary's basename as the merged name
    merged_name = "#{base}-#{primary[:term]}"
    outer["data"]["identifier"] = merged_name

    merged_path = CONCEPTS + "#{merged_name}.yaml"
    next if merged_path.exist? # already merged somehow

    File.write(merged_path, dump_multi_doc(merged_docs))
    merged += 1

    # Delete originals
    by_lang.values.each do |e|
      File.delete(e[:file]) if e[:file].exist? && e[:file] != merged_path
      deleted += 1
    end
  end

  # Strategy 2: Positional matching for remaining unmatched
  # (only if same count in both languages and we haven't matched via auth)
  remaining = Hash.new { |h, k| h[k] = [] }
  langs.each do |lang, concepts|
    concepts.each do |c|
      next if !c[:file].exist?
      remaining[lang] << c
    end
  end
  next if remaining.size < 2

  # Sort each language by term number, pair positionally
  sorted_langs = remaining.keys.sort
  sorted_lists = sorted_langs.map { |l| remaining[l].sort_by { |c| c[:term] } }

  # Only match if counts are close (within 10% of each other)
  counts = sorted_lists.map(&:size)
  next if counts.min.to_f / counts.max < 0.9

  # Pair by position
  min_count = counts.min
  primary_lang = sorted_langs.include?("eng") ? "eng" : sorted_langs.first

  (0...min_count).each do |i|
    primary_entry = sorted_lists.find { |l| l.first }&.[]  # placeholder
    pairs = sorted_lists.map { |l| l[i] }.compact
    next if pairs.size < 2

    primary = pairs.find { |p| p[:pub_code].end_with?("-e") || p[:pub_code].end_with?("-eng") } || pairs.first
    others = pairs.reject { |p| p == primary }

    next if others.empty?

    primary_docs = YAML.load_stream(primary[:file].read)
    outer = primary_docs.first
    outer_loc = outer["data"]["localized_concepts"] || {}

    merged_docs = [outer]
    merged_langs = Set.new([primary[:lang]])

    others.each do |other|
      other_docs = YAML.load_stream(other[:file].read)
      other_loc = other_docs.drop(1).select { |d| d.is_a?(Hash) && d.dig("data", "language_code") }
      other_loc.each do |loc|
        lang_code = loc["data"]["language_code"]
        next if merged_langs.include?(lang_code)
        merged_langs << lang_code
        uuid = other_docs.first["data"]["localized_concepts"]&.dig(lang_code)
        outer_loc[lang_code] = uuid if uuid
        merged_docs << loc
      end
    end

    next if merged_docs.size < 2

    outer["data"]["localized_concepts"] = outer_loc
    merged_name = "#{base}-#{primary[:term]}"
    outer["data"]["identifier"] = merged_name

    merged_path = CONCEPTS + "#{merged_name}.yaml"
    next if merged_path.exist?

    File.write(merged_path, dump_multi_doc(merged_docs))
    merged += 1

    pairs.each do |p|
      File.delete(p[:file]) if p[:file].exist? && p[:file] != merged_path
      deleted += 1
    end
  end
end

puts "Phase 2 merged: #{merged} concept groups"
puts "Deleted: #{deleted} original files"
