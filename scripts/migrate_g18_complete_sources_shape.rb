#!/usr/bin/env ruby
# frozen_string_literal: true

# One-shot migration: convert V 0 concept source entries from the flat
# `{ref, clause, version}` shape to the canonical glossarist v3 shape
# `{origin: {ref: {source:}}, locality: {type: clause, reference_from:}, type: authoritative}`.
#
# Also converts `{raw: <citation>}` entries into a second authored source
# entry whose `origin.ref.source` is the raw citation string, so the
# validator can see them and the concept-browser can render them.
#
# Idempotent: re-running on already-canonical files is a no-op.

require "yaml"
require "pathname"
require "fileutils"

module V0SourceMigration
  module_function

  def canonicalize(src)
    return src unless src.is_a?(Hash)
    return src if src["origin"] && src.dig("origin", "ref", "source")

    if src["ref"]
      out = {
        "origin" => { "ref" => { "source" => src["ref"] } },
        "type" => "authoritative",
      }
      out["locality"] = { "type" => "clause", "reference_from" => src["clause"].to_s } if src["clause"]
      out["origin"]["ref"]["version"] = src["version"].to_s if src["version"]
      return out
    end

    if src["raw"]
      return {
        "origin" => { "ref" => { "source" => src["raw"] } },
        "type" => "authored",
      }
    end

    src
  end

  def dump_multi_doc(docs)
    parts = docs.map { |d| YAML.dump(d).sub(/\A---\n/, "") }
    "---\n" + parts.join("---\n") + "\n"
  end
end

CONCEPTS_DIR = File.expand_path("../datasets/g18-complete/concepts", __dir__)
abort "Concepts dir not found: #{CONCEPTS_DIR}" unless File.directory?(CONCEPTS_DIR)

files = Dir.glob(File.join(CONCEPTS_DIR, "*.yaml")).sort
puts "Migrating #{files.size} files..."

migrated = 0
unchanged = 0
files.each do |path|
  docs = YAML.load_stream(File.read(path))
  changed = false
  docs.each do |doc|
    next unless doc.is_a?(Hash) && doc["data"].is_a?(Hash)
    srcs = doc["data"]["sources"]
    next unless srcs.is_a?(Array)

    new_srcs = srcs.map { |s| V0SourceMigration.canonicalize(s) }
    unless new_srcs == srcs
      doc["data"]["sources"] = new_srcs
      changed = true
    end
  end

  if changed
    File.write(path, V0SourceMigration.dump_multi_doc(docs))
    migrated += 1
  else
    unchanged += 1
  end
end

puts "Migrated: #{migrated}"
puts "Unchanged: #{unchanged}"
