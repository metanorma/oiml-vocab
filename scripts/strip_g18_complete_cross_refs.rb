#!/usr/bin/env ruby
# frozen_string_literal: true

# One-shot fix: in V 0 concept files, the agents put BOTH the publication
# where the term appears AND cross-reference citations (VIM X.Y, VIML X.Y,
# ISO/IEC ..., OIML B 3 ...) into the same `sources[]` array. The project
# validator requires every `sources[].origin.ref.source` to resolve to a
# URN, register ref, or bibliography id — cross-reference citations don't.
#
# This script keeps the authoritative source (the OIML publication where
# the concept appears, derived from the filename) and drops cross-reference
# source entries. The dropped text is preserved in the localized concept's
# notes (appended as "Source citation: <text>") so no information is lost.
#
# Idempotent.

require "yaml"
require "pathname"
require "set"

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
require "oiml/g18_complete"

REPO_ROOT = File.expand_path("..", __dir__)
CONCEPTS_DIR = File.join(REPO_ROOT, "datasets", "g18-complete", "concepts")
SOURCE_ROOT = Pathname.new("/Users/mulgogi/src/oimlsmart/publications/reference-docs/ocr-output")

abort "Concepts dir not found: #{CONCEPTS_DIR}" unless File.directory?(CONCEPTS_DIR)

PUB_CODES = Set.new(SOURCE_ROOT.children.select(&:directory?).map(&:basename).map(&:to_s))

RESOLVABLE_REFS = Set.new
Dir.glob(File.join(REPO_ROOT, "datasets", "*/register.yaml")).each do |reg|
  begin
    yaml = YAML.load_file(reg)
    next unless yaml.is_a?(Hash)
    RESOLVABLE_REFS << yaml["ref"] if yaml["ref"]
    (yaml["ref_aliases"] || []).each { |a| RESOLVABLE_REFS << a }
  rescue StandardError
    next
  end
end
Dir.glob(File.join(REPO_ROOT, "datasets", "*/bibliography.yaml")).each do |bib|
  begin
    YAML.load_file(bib).each do |e|
      RESOLVABLE_REFS << e["id"] if e.is_a?(Hash) && e["id"]
    end
  rescue StandardError
    next
  end
end

def resolve_pub_code(basename)
  parts = basename.split("-")
  (parts.length - 1).downto(1) do |i|
    candidate = parts[0...i].join("-")
    return candidate if PUB_CODES.include?(candidate)
  end
  nil
end

def dump_multi_doc(docs)
  parts = docs.map { |d| YAML.dump(d).sub(/\A---\n/, "") }
  "---\n" + parts.join("---\n") + "\n"
end

files = Dir.glob(File.join(CONCEPTS_DIR, "*.yaml")).sort
puts "Processing #{files.size} files..."

dropped_count = 0
files_migrated = 0

files.each do |path|
  basename = File.basename(path, ".yaml")
  pub_code = resolve_pub_code(basename)
  pub_ref = pub_code ? Oiml::G18Complete::PublicationCode.parse(pub_code).oiml_ref : nil

  docs = YAML.load_stream(File.read(path))
  changed = false
  docs.each do |doc|
    next unless doc.is_a?(Hash) && doc["data"].is_a?(Hash)
    srcs = doc["data"]["sources"]
    next unless srcs.is_a?(Array) && srcs.size > 1

    kept = []
    dropped = []
    srcs.each do |s|
      ref = s.is_a?(Hash) ? s.dig("origin", "ref", "source") : nil
      if ref && (ref == pub_ref || RESOLVABLE_REFS.include?(ref) || ref =~ /\Aurn:/)
        kept << s
      else
        dropped << ref
      end
    end

    next if dropped.empty?

    doc["data"]["notes"] ||= []
    dropped.each do |ref|
      doc["data"]["notes"] << { "content" => "Source citation: #{ref}" }
    end

    if kept.empty? && pub_ref
      kept << {
        "origin" => { "ref" => { "source" => pub_ref } },
        "type" => "authoritative",
      }
    end

    doc["data"]["sources"] = kept
    dropped_count += dropped.size
    changed = true
  end

  next unless changed

  File.write(path, dump_multi_doc(docs))
  files_migrated += 1
end

puts "Files migrated: #{files_migrated}"
puts "Cross-ref sources dropped (preserved as notes): #{dropped_count}"
