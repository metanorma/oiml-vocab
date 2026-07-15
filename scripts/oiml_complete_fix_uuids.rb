#!/usr/bin/env ruby
# frozen_string_literal: true

# Fix invented UUIDs in V 0 concept files. Multiple agents across
# rounds admitted hand-entering UUIDs incorrectly (e.g. round 6 agent B,
# round 7 agent B, round 9 agent E). The extracted terminology content
# is fine; only the UUIDs are wrong. This script rewrites each file with
# the deterministic UUIDv5 values from the helper.
#
# Idempotent.

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

def dump_multi_doc(docs)
  parts = docs.map { |d| YAML.dump(d).sub(/\A---\n/, "") }
  "---\n" + parts.join("---\n") + "\n"
end

fixed = 0
unchanged = 0
CONCEPTS.children.each do |f|
  basename = f.basename(".yaml").to_s
  pub_code = resolve_pub_code(basename)
  unless pub_code
    unchanged += 1
    next
  end
  term = basename.delete_prefix("#{pub_code}-")

  docs = YAML.load_stream(f.read)
  outer = docs.first
  unless outer.is_a?(Hash) && outer["data"]
    unchanged += 1
    next
  end

  changed = false
  expected_outer_id = expected_outer(pub_code, term)
  if outer["id"] != expected_outer_id
    outer["id"] = expected_outer_id
    changed = true
  end

  loc = outer["data"]["localized_concepts"] || {}
  loc.each do |lang, _|
    expected = expected_localized(pub_code, term, lang)
    unless loc[lang] == expected
      loc[lang] = expected
      changed = true
    end
  end

  # Also fix localized docs' id + data.id
  docs.each do |doc|
    next unless doc.is_a?(Hash) && doc["data"]
    lid = doc["data"]["id"]
    # lid like "<pub-code>-<term>-<lang>"; match against localized_concepts to find which lang
    next unless lid.is_a?(String) && lid.start_with?("#{pub_code}-#{term}-")
    lang = lid.delete_prefix("#{pub_code}-#{term}-")
    expected = expected_localized(pub_code, term, lang)
    if doc["id"] != expected
      doc["id"] = expected
      changed = true
    end
  end

  if changed
    File.write(f, dump_multi_doc(docs))
    fixed += 1
  else
    unchanged += 1
  end
end

puts "Fixed UUIDs in: #{fixed} files"
puts "Unchanged:      #{unchanged} files"
