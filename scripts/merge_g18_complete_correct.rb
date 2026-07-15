#!/usr/bin/env ruby
# frozen_string_literal: true

# Corrected multilingual merge for g18-complete.
# Fixes the bug where primary language localized docs were dropped.
#
# Three strategies, in order:
#   1. Same-language dedup: -e + -eng → keep one
#   2. Auth-source matching: same VIM/VIML ref+clause across languages
#   3. Positional matching: sorted by term number, paired 1:1

require "yaml"
require "pathname"
require "set"

CONCEPTS = Pathname.new(File.expand_path("../datasets/g18-complete/concepts", __dir__))
SOURCE_ROOT = Pathname.new("/Users/mulgogi/src/oimlsmart/publications/reference-docs/ocr-output")
PUB_CODES = Set.new(SOURCE_ROOT.children.select(&:directory?).map(&:basename).map(&:to_s))
SUFFIXES = %w[eng fra spa deu ara fas zho rus por ita nld pol srp ukr e f].freeze
LANG_MAP = { "e" => "eng", "f" => "fra" }.freeze

def resolve(basename)
  parts = basename.split("-")
  (parts.length - 1).downto(1) { |i| c = parts[0...i].join("-"); return c if PUB_CODES.include?(c) }
  nil
end

def suffix_of(pc)
  SUFFIXES.each { |s| return s if pc.end_with?("-#{s}") }
  nil
end

def lang_of(pc)
  s = suffix_of(pc)
  LANG_MAP.fetch(s, s) || "eng"
end

def strip_suffix(pc)
  s = suffix_of(pc)
  s ? pc.sub(/-#{s}$/, "") : pc
end

def dump(docs)
  parts = docs.map { |d| YAML.dump(d).sub(/\A---\n/, "") }
  "---\n" + parts.join("---\n") + "\n"
end

# Merge two concept files into one bilingual file.
# Takes ALL docs from primary (outer + localized), adds unique localized docs from other.
def merge_pair(primary_file, other_file, new_identifier)
  primary_docs = YAML.load_stream(primary_file.read)
  other_docs = YAML.load_stream(other_file.read)

  outer = primary_docs.first
  loc_map = outer["data"]["localized_concepts"] ||= {}

  # Start with ALL primary docs (outer + primary localized)
  merged = primary_docs.dup
  seen_langs = Set.new
  primary_docs.drop(1).each do |d|
    lc = d.is_a?(Hash) && d.dig("data", "language_code")
    seen_langs << lc if lc
  end

  # Add localized docs from other that we haven't seen
  other_docs.drop(1).each do |d|
    next unless d.is_a?(Hash) && d["data"].is_a?(Hash)
    lc = d["data"]["language_code"]
    next unless lc
    next if seen_langs.include?(lc)
    seen_langs << lc
    # Get UUID from other's outer localized_concepts
    other_loc = other_docs.first&.dig("data", "localized_concepts") || {}
    loc_map[lc] = other_loc[lc] if other_loc[lc]
    merged << d
  end

  outer["data"]["identifier"] = new_identifier
  outer["data"]["localized_concepts"] = loc_map

  merged
end

# ---- Build index ----
by_base = Hash.new { |h, k| h[k] = Hash.new { |h2, k2| h2[k2] = [] } }

CONCEPTS.children.each do |f|
  basename = f.basename(".yaml").to_s
  pc = resolve(basename)
  next unless pc
  base = strip_suffix(pc)
  next if base == pc

  lang = lang_of(pc)
  term = basename.delete_prefix("#{pc}-")
  by_base[base][lang] << { file: f, pub_code: pc, basename: basename, term: term }
end

# ---- Step 1: Same-language dedup ----
deduped = 0
by_base.each do |base, langs|
  langs.each do |lang, entries|
    by_term = entries.group_by { |e| e[:term] }
    by_term.each do |term, dupes|
      next if dupes.size < 2
      keeper = dupes.max_by { |e| File.size(e[:file]) }
      dupes.each { |d| File.delete(d[:file]) if d != keeper && d[:file].exist? }
      deduped += 1
    end
  end
end

# Rebuild index after dedup
by_base = Hash.new { |h, k| h[k] = Hash.new { |h2, k2| h2[k2] = [] } }
CONCEPTS.children.each do |f|
  basename = f.basename(".yaml").to_s
  pc = resolve(basename)
  next unless pc
  base = strip_suffix(pc)
  next if base == pc
  lang = lang_of(pc)
  term = basename.delete_prefix("#{pc}-")
  by_base[base][lang] << { file: f, pub_code: pc, basename: basename, term: term }
end

# ---- Step 2: Auth-source matching ----
auth_merged = 0
auth_deleted = 0

by_base.each do |base, langs|
  next if langs.size < 2

  # Build auth-key index
  auth_index = Hash.new { |h, k| h[k] = {} }
  langs.each do |lang, entries|
    entries.each do |e|
      docs = YAML.load_stream(e[:file].read)
      docs.each do |d|
        next unless d.is_a?(Hash) && d["data"].is_a?(Hash)
        (d["data"]["sources"] || []).each do |s|
          next unless s.is_a?(Hash) && s["type"] == "authoritative"
          ref = s.dig("origin", "ref", "source")
          clause = s.dig("locality", "reference_from")
          next unless ref && clause && ref.match?(/OIML\s+V\s+[12]|VIM/i)
          auth_index["#{ref}|#{clause}"][lang] ||= e
        end
      end
    end
  end

  auth_index.each do |key, lang_entries|
    next if lang_entries.size < 2
    primary = lang_entries["eng"] || lang_entries.values.first
    others = lang_entries.reject { |l, _| l == lang_entries.key(primary) }

    new_id = "#{base}-#{primary[:term]}"
    merged = merge_pair(primary[:file], others.values.first[:file], new_id)

    out = CONCEPTS + "#{new_id}.yaml"
    File.write(out, dump(merged))
    auth_merged += 1

    lang_entries.each_value do |e|
      File.delete(e[:file]) if e[:file].exist? && e[:file] != out
      auth_deleted += 1
    end
  end
end

# Rebuild index
by_base = Hash.new { |h, k| h[k] = Hash.new { |h2, k2| h2[k2] = [] } }
CONCEPTS.children.each do |f|
  basename = f.basename(".yaml").to_s
  pc = resolve(basename)
  next unless pc
  base = strip_suffix(pc)
  next if base == pc
  lang = lang_of(pc)
  term = basename.delete_prefix("#{pc}-")
  by_base[base][lang] << { file: f, pub_code: pc, basename: basename, term: term }
end

# ---- Step 3: Positional matching ----
pos_merged = 0
pos_deleted = 0

by_base.each do |base, langs|
  next if langs.size < 2

  sorted_langs = langs.transform_values { |es| es.sort_by { |e| e[:term] } }
  counts = sorted_langs.map { |_, es| es.size }
  min_count = counts.min
  max_count = counts.max

  next if min_count.to_f / max_count < 0.8
  next if min_count < 3

  primary_lang = langs.key?("eng") ? "eng" : sorted_langs.keys.first
  primary_list = sorted_langs[primary_lang]
  other_langs = sorted_langs.reject { |l, _| l == primary_lang }

  (0...min_count).each do |i|
    primary = primary_list[i]
    next unless primary && primary[:file].exist?

    new_id = "#{base}-#{primary[:term]}"
    next if (CONCEPTS + "#{new_id}.yaml").exist?

    other = other_langs.values.map { |l| l[i] }.compact.first
    next unless other && other[:file].exist?

    merged = merge_pair(primary[:file], other[:file], new_id)

    out = CONCEPTS + "#{new_id}.yaml"
    File.write(out, dump(merged))
    pos_merged += 1

    [primary, other].each do |e|
      File.delete(e[:file]) if e[:file].exist? && e[:file] != out
      pos_deleted += 1
    end
  end
end

puts "Same-language dedup: #{deduped} groups"
puts "Auth-source merged:  #{auth_merged} (deleted #{auth_deleted})"
puts "Positional merged:   #{pos_merged} (deleted #{pos_deleted})"
puts "Total files: #{CONCEPTS.children.size}"
