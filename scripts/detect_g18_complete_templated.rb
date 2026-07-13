#!/usr/bin/env ruby
# frozen_string_literal: true

# Detect mechanically-templated concept files: pairs of pubs whose
# YAML bodies are identical modulo pub-code/UUID/identifier strings.

require "yaml"
require "pathname"
require "set"

CONCEPTS = Pathname.new("/Users/mulgogi/src/oimlsmart/vocab/datasets/g18-complete/concepts")
SOURCE_ROOT = Pathname.new("/Users/mulgogi/src/oimlsmart/publications/reference-docs/ocr-output")
PUB_CODES = Set.new(SOURCE_ROOT.children.select(&:directory?).map(&:basename).map(&:to_s))

def resolve_pub_code(basename)
  parts = basename.split("-")
  (parts.length - 1).downto(1) do |i|
    candidate = parts[0...i].join("-")
    return candidate if PUB_CODES.include?(candidate)
  end
  nil
end

def structurally_identical?(file_a, file_b)
  docs_a = YAML.load_stream(file_a.read)
  docs_b = YAML.load_stream(file_b.read)
  return false unless docs_a.size == docs_b.size

  docs_a.zip(docs_b).all? do |da, db|
    next false unless da.is_a?(Hash) && db.is_a?(Hash)
    next false unless da["data"].is_a?(Hash) && db["data"].is_a?(Hash)

    %w[definition notes examples terms].all? do |key|
      da["data"][key] == db["data"][key]
    end
  end
end

by_term = Hash.new { |h, k| h[k] = {} }
CONCEPTS.children.each do |f|
  basename = f.basename(".yaml").to_s
  pub = resolve_pub_code(basename)
  next unless pub
  term = basename.delete_prefix("#{pub}-")
  by_term[term][pub] = f
end

suspect_pairs = Hash.new { |h, k| h[k] = 0 }

by_term.each do |term, pubs|
  next if pubs.size < 2
  pubs.to_a.combination(2).each do |(pub_a, file_a), (pub_b, file_b)|
    if structurally_identical?(file_a, file_b)
      key = [pub_a, pub_b].sort
      suspect_pairs[key] += 1
    end
  end
end

puts "Suspect templated pub pairs (file counts):"
suspect_pairs.sort_by { |_, c| -c }.each do |(a, b), count|
  puts "  #{a} <-> #{b}: #{count} identical term files"
end
