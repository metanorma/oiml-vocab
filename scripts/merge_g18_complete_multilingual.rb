#!/usr/bin/env ruby
# frozen_string_literal: true

# Task 4: Merge multilingual concept pairs.
#
# For pub-codes that share a base (e.g. b3-2003-e + b3-2003-f),
# merge concepts with matching term numbers into single bilingual files.
# The merged file uses the base pub-code (without language suffix).
#
# Matching strategy:
#   Phase A: Same term number across language variants → merge directly.
#   Phase B (future): Unmatched concepts matched by designation.
#
# Idempotent: running twice is safe (merged files don't re-merge).

require "yaml"
require "pathname"
require "set"

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
require "oiml/g18_complete"

CONCEPTS = Pathname.new(File.expand_path("../datasets/g18-complete/concepts", __dir__))
SOURCE_ROOT = Pathname.new("/Users/mulgogi/src/oimlsmart/publications/reference-docs/ocr-output")
PUB_CODES = Set.new(SOURCE_ROOT.children.select(&:directory?).map(&:basename).map(&:to_s))

# Known language suffixes (longest first to avoid partial matches)
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
  LANG_SUFFIXES.each do |suffix|
    stripped = pub_code.sub(/-#{suffix}$/, "")
    return stripped if stripped != pub_code
  end
  pub_code
end

def lang_from_suffix(pub_code)
  LANG_SUFFIXES.each do |suffix|
    return suffix if pub_code.end_with?("-#{suffix}")
  end
  # Try PublicationCode parser
  parsed = Oiml::G18Complete::PublicationCode.parse(pub_code)
  parsed.language
end

def normalize_lang(code)
  case code
  when "e" then "eng"
  when "f" then "fra"
  else code
  end
end

def dump_multi_doc(docs)
  parts = docs.map { |d| YAML.dump(d).sub(/\A---\n/, "") }
  "---\n" + parts.join("---\n") + "\n"
end

# ---- Build index: (base_pub_code, term_number) → {lang => file_path} ----
index = Hash.new { |h, k| h[k] = {} }

CONCEPTS.children.each do |f|
  basename = f.basename(".yaml").to_s
  pc = resolve_pub_code(basename)
  next unless pc

  term = basename.delete_prefix("#{pc}-")
  base = strip_lang_suffix(pc)
  lang = normalize_lang(lang_from_suffix(pc))

  index[[base, term]][lang] = { file: f, pub_code: pc, basename: basename }
end

# ---- Find mergeable groups (2+ languages for same base+term) ----
mergeable = index.select { |_, langs| langs.size > 1 }
puts "Found #{mergeable.size} mergeable concept groups (2+ languages)"

merged = 0
skipped = 0
deleted = 0

mergeable.each do |(base, term), langs|
  # Collect all docs from all language files
  all_docs = {}
  langs.each do |lang, info|
    docs = YAML.load_stream(info[:file].read)
    all_docs[lang] = docs
  end

  # Pick the primary language for the outer doc (prefer eng, then fra)
  primary_lang = %w[eng fra spa deu pol] & langs.keys
  primary_lang = langs.keys.first if primary_lang.empty?
  primary = primary_lang.first

  primary_docs = all_docs[primary]
  outer = primary_docs.first

  # Build merged localized_concepts map
  merged_loc = {}
  all_docs.each do |lang, docs|
    docs.drop(1).each do |loc_doc|
      next unless loc_doc.is_a?(Hash) && loc_doc["data"].is_a?(Hash)
      loc_lang = loc_doc["data"]["language_code"]
      next unless loc_lang
      merged_loc[loc_lang] = loc_doc["data"]["id"] # placeholder, will use UUID later
    end
  end

  # Get UUIDs from the primary file (they should already match the deterministic pattern)
  # The primary outer doc's localized_concepts already has UUIDs for its language.
  # We need to add UUIDs for the other languages from their files.
  outer_loc = outer["data"]["localized_concepts"] || {}
  all_docs.each do |lang, docs|
    loc_outer = docs.first
    next unless loc_outer.is_a?(Hash) && loc_outer["data"].is_a?(Hash)
    loc_map = loc_outer["data"]["localized_concepts"] || {}
    loc_map.each do |l, uuid|
      outer_loc[l] ||= uuid
    end
  end
  outer["data"]["localized_concepts"] = outer_loc

  # Collect all localized docs from all files
  merged_localized_docs = []
  all_docs.each do |lang, docs|
    docs.drop(1).each do |loc|
      next unless loc.is_a?(Hash) && loc["data"].is_a?(Hash)
      merged_localized_docs << loc
    end
  end

  # Deduplicate localized docs by language_code
  seen = {}
  deduped = []
  merged_localized_docs.each do |loc|
    lc = loc.dig("data", "language_code")
    next if seen[lc]
    seen[lc] = true
    deduped << loc
  end

  # Build the new outer identifier
  outer["data"]["identifier"] = "#{base}-#{term}"

  # Build the merged file
  merged_docs = [outer] + deduped

  # Write merged file
  merged_path = CONCEPTS + "#{base}-#{term}.yaml"
  if merged_path.exist? && langs.keys.size == 1
    skipped += 1
    next
  end

  File.write(merged_path, dump_multi_doc(merged_docs))
  merged += 1

  # Delete the original language-specific files
  langs.each do |lang, info|
    next if info[:file] == merged_path
    File.delete(info[:file]) if info[:file].exist?
    deleted += 1
  end
end

puts "Merged: #{merged} concept groups"
puts "Deleted: #{deleted} original files"
puts "Skipped: #{skipped}"
