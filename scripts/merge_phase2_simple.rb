#!/usr/bin/env ruby
# frozen_string_literal: true

# Phase 2 multilingual merge — match by shared authoritative VIM/VIML source.
# Simpler than the previous attempt; just builds auth-key → files map and merges.

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
    c = parts[0...i].join("-")
    return c if PUB_CODES.include?(c)
  end
  nil
end

def strip_lang(pc)
  LANG_SUFFIXES.each { |s| return pc.sub(/-#{s}$/, "") if pc.end_with?("-#{s}") }
  pc
end

def lang_of(pc)
  return "eng" if pc.end_with?("-e") || pc.end_with?("-eng")
  return "fra" if pc.end_with?("-f") || pc.end_with?("-fra")
  return "spa" if pc.end_with?("-spa")
  return "deu" if pc.end_with?("-deu")
  "eng"
end

def dump(docs)
  parts = docs.map { |d| YAML.dump(d).sub(/\A---\n/, "") }
  "---\n" + parts.join("---\n") + "\n"
end

# Build auth-key → {lang => file_info}
auth_map = Hash.new { |h, k| h[k] = {} }

CONCEPTS.children.each do |f|
  basename = f.basename(".yaml").to_s
  pc = resolve_pub_code(basename)
  next unless pc
  base = strip_lang(pc)
  next if base == pc  # already merged, skip

  docs = begin
    YAML.load_stream(f.read)
  rescue StandardError
    next
  end

  outer = docs.first
  next unless outer.is_a?(Hash) && outer["data"].is_a?(Hash)

  # Find authoritative VIM/VIML source in outer doc
  (outer["data"]["sources"] || []).each do |s|
    next unless s.is_a?(Hash) && s["type"] == "authoritative"
    ref = s.dig("origin", "ref", "source")
    clause = s.dig("locality", "reference_from")
    next unless ref && clause
    next unless ref.match?(/OIML\s+V\s+[12]|VIM|VIML/i)

    key = "#{ref}|#{clause}"
    lang = lang_of(pc)
    auth_map[key][lang] ||= { file: f, pub_code: pc, basename: basename, docs: docs, base: base }
  end
end

puts "Auth keys with 2+ languages: #{auth_map.count { |_, v| v.size > 1 }}"

merged = 0
deleted = 0

auth_map.each do |key, langs|
  next if langs.size < 2

  primary = langs["eng"] || langs.values.first
  others = langs.values.reject { |v| v[:lang] == primary[:lang] || v == primary }
  # Re-check: others by different lang
  others = langs.reject { |l, _| l == (langs.key?(primary) ? langs.key(primary) : "") }
  others = langs.select { |l, _| l != langs.key(primary) }

  next if others.empty?

  outer = primary[:docs].first
  loc = outer["data"]["localized_concepts"] ||= {}

  merged_docs = [outer]
  primary_lang_code = outer["data"]["localized_concepts"]&.keys&.first || "eng"

  others.each_value do |other|
    other_outer = other[:docs].first
    other_loc = other_outer["data"]["localized_concepts"] || {}
    other_localized = other[:docs].drop(1).select { |d| d.is_a?(Hash) && d.dig("data", "language_code") }

    other_localized.each do |olc|
      lc = olc["data"]["language_code"]
      next if loc.key?(lc)
      loc[lc] = other_loc[lc]
      merged_docs << olc
    end
  end

  next if merged_docs.size < 2

  # Update identifier to use base pub-code
  term = primary[:basename].delete_prefix("#{primary[:pub_code]}-")
  new_id = "#{primary[:base]}-#{term}"
  outer["data"]["identifier"] = new_id

  out_path = CONCEPTS + "#{new_id}.yaml"
  next if out_path.exist? && out_path != primary[:file]

  File.write(out_path, dump(merged_docs))

  # Delete originals
  langs.each_value do |info|
    next if info[:file] == out_path
    File.delete(info[:file]) if info[:file].exist?
    deleted += 1
  end
  merged += 1
end

puts "Merged: #{merged}"
puts "Deleted: #{deleted}"
