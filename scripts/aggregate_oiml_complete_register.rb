#!/usr/bin/env ruby
# frozen_string_literal: true

# Aggregate `datasets/oiml-complete/concepts/*.yaml` (already extracted by the manual
# agent pass) into `datasets/oiml-complete/register.yaml` and `datasets/oiml-complete/bibliography.yaml`.
#
# This script does NOT extract terminology. It only reads the metadata
# already present in each concept YAML (sources, language_code) and rolls
# it up into the dataset-level files. Extraction is done manually by
# agents per TODO.consolidate/01-oiml-complete-extraction-spec.md.

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
require "oiml/oiml_complete"

require "yaml"
require "pathname"
require "set"

REPO_ROOT = File.expand_path("..", __dir__)
V0_DIR = File.join(REPO_ROOT, "datasets", "oiml-complete")
CONCEPTS_DIR = File.join(V0_DIR, "concepts")
SOURCE_ROOT = Pathname.new("/Users/mulgogi/src/oimlsmart/publications/reference-docs/ocr-output")

abort "Concepts dir not found: #{CONCEPTS_DIR}" unless File.directory?(CONCEPTS_DIR)

# Build the set of known pub-codes from the source directory. Filenames
# are `<pub-code>-<term-number>.yaml` and both halves can contain dashes,
# so we resolve the pub-code by longest-prefix match against this set.
known_pub_codes = SOURCE_ROOT.children.select(&:directory?).map(&:basename).map(&:to_s)
pub_code_set = Set.new(known_pub_codes)

def resolve_pub_code(basename, pub_code_set)
  # Try the longest possible prefix that is a real pub-code.
  parts = basename.split("-")
  (parts.length - 1).downto(1) do |i|
    candidate = parts[0...i].join("-")
    return candidate if pub_code_set.include?(candidate)
  end
  nil
end

concept_files = Dir.glob(File.join(CONCEPTS_DIR, "*.yaml")).sort
concept_count = concept_files.size

languages = Set.new
seen_pub_codes = Set.new
seen_pub_refs = {}

concept_files.each do |path|
  basename = File.basename(path, ".yaml")
  pub_code = resolve_pub_code(basename, pub_code_set)
  next unless pub_code

  seen_pub_codes << pub_code

  docs = YAML.load_stream(File.read(path))
  outer = docs.first
  next unless outer.is_a?(Hash) && outer["data"]

  (outer.dig("data", "localized_concepts") || {}).keys.each { |l| languages << l }

  # Capture the source ref as the agent actually wrote it (e.g. for
  # r46-1-spa the agent used year=2012 from OCR content, even though the
  # filename has no year). The bibliography should reflect the agent's
  # ref, not a filename-derived one.
  sources = outer.dig("data", "sources") || []
  sources.each do |s|
    ref = s.is_a?(Hash) ? s.dig("origin", "ref", "source") : nil
    seen_pub_refs[pub_code] = ref if ref
  end
end

# Build publication list. For most pubs, parse the pub-code from the
# filename. For pubs whose filename lacks a year (e.g. r46-1-spa), the
# agent extracted the year from OCR content and wrote it in the concept's
# source ref — use that ref directly to avoid a year=0 mismatch.
pub_codes = seen_pub_codes.sort.map do |c|
  Oiml::G18Complete::PublicationCode.parse(c)
end

# Override bibliography entries for pubs whose agent-emitted source ref
# disagrees with the filename-derived one. Build a parallel
# `pub_ref_overrides` map and let the bibliography builder consume it.
pub_ref_overrides = {}
seen_pub_refs.each do |pub_code, ref|
  parsed = Oiml::G18Complete::PublicationCode.parse(pub_code)
  if parsed.oiml_ref != ref
    pub_ref_overrides[pub_code] = ref
  end
end

# Register
register = Oiml::G18Complete::RegisterBuilder.new.build(
  concept_count: concept_count,
  languages: languages.to_a.sort,
)
File.write(File.join(V0_DIR, "register.yaml"), YAML.dump(register))

# Bibliography
bib = Oiml::G18Complete::BibliographyBuilder.new.build(pub_codes)
# Apply ref overrides in-place so the bibliography id matches what
# agents actually cited.
bib.each { |e| e["id"] = pub_ref_overrides[e["dataset_ids"].first] if pub_ref_overrides[e["dataset_ids"].first] }
File.write(File.join(V0_DIR, "bibliography.yaml"), YAML.dump(bib))

$stderr.puts "Concepts: #{concept_count}"
$stderr.puts "Languages: #{languages.to_a.sort.inspect}"
$stderr.puts "Publications cited: #{pub_codes.size}"
$stderr.puts "Wrote: #{File.join(V0_DIR, 'register.yaml')}"
$stderr.puts "Wrote: #{File.join(V0_DIR, 'bibliography.yaml')}"
