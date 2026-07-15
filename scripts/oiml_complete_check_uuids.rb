#!/usr/bin/env ruby
# frozen_string_literal: true

# Verify that every V 0 concept file's UUIDs match what the deterministic
# helper would produce. Invented UUIDs are a process violation that
# agents have admitted in past rounds — this check catches any that
# slipped through.

require "yaml"
require "pathname"
require "set"

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
require "oiml/oiml_complete"

CONCEPTS = Pathname.new(File.expand_path("../datasets/oiml-complete/concepts", __dir__))
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

def expected_outer(pub_code, term)
  Oiml::G18Complete::UuidV5.generate(
    Oiml::G18Complete::UuidNamespace::NAMESPACE_UUID,
    "oiml-complete|#{pub_code}|#{term}",
  )
end

def expected_localized(pub_code, term, lang)
  Oiml::G18Complete::UuidV5.generate(
    Oiml::G18Complete::UuidNamespace::NAMESPACE_UUID,
    "oiml-complete|#{pub_code}|#{term}|#{lang}",
  )
end

bad = []
total = 0
CONCEPTS.children.each do |f|
  basename = f.basename(".yaml").to_s
  pub_code = resolve_pub_code(basename)
  unless pub_code
    bad << [basename, "cannot resolve pub-code"]
    next
  end
  term = basename.delete_prefix("#{pub_code}-")
  total += 1

  docs = YAML.load_stream(f.read)
  outer = docs.first
  unless outer.is_a?(Hash) && outer["data"]
    bad << [basename, "missing outer doc"]
    next
  end

  expected_outer_id = expected_outer(pub_code, term)
  if outer["id"] != expected_outer_id
    bad << [basename, "outer.id mismatch: got #{outer['id']} expected #{expected_outer_id}"]
  end

  loc = outer["data"]["localized_concepts"] || {}
  loc.each do |lang, lid|
    expected = expected_localized(pub_code, term, lang)
    if lid != expected
      bad << [basename, "localized[#{lang}] mismatch: got #{lid} expected #{expected}"]
    end
  end
end

puts "Checked #{total} concept files."
if bad.empty?
  puts "All UUIDs match the deterministic helper. OK."
else
  puts "Found #{bad.size} UUID mismatches:"
  bad.first(20).each { |b| puts "  #{b[0]}: #{b[1]}" }
  puts "..." if bad.size > 20
end
