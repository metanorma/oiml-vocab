#!/usr/bin/env ruby
# frozen_string_literal: true

# Task 3b: Restructure g18-complete sources into proper lineage chains.
#
# For concepts where a localized doc has an authoritative VIM/VIML source
# (from the citation conversion), move it to the OUTER doc and build the
# full provenance chain per concept-model v3:
#
#   sources:
#   - type: authoritative          # VIML/VIM (original definition)
#     origin: { ref: { source: "OIML V 1:2013" } }
#     locality: { type: clause, reference_from: "2.5" }
#   - type: lineage                # B 3:2003 (the publication reproducing it)
#     status: identical
#     origin: { ref: { source: "OIML B 3:2003", version: "2003" } }
#     locality: { type: clause, reference_from: "2.7" }
#     sourced_from:
#     - ref: { source: "OIML V 1:2013" }
#
# Localized docs have their sources[] cleared (they inherit from outer).
#
# Idempotent.

require "yaml"
require "pathname"

CONCEPTS = Pathname.new(File.expand_path("../datasets/g18-complete/concepts", __dir__))

VIM_PATTERN = /\A(?:OIML\s+V\s+[12]|VIM|VIML)\b/i

def dump_multi_doc(docs)
  parts = docs.map { |d| YAML.dump(d).sub(/\A---\n/, "") }
  "---\n" + parts.join("---\n") + "\n"
end

files = Dir.glob(File.join(CONCEPTS, "*.yaml")).sort
puts "Processing #{files.size} files..."

restructured = 0
unchanged = 0

files.each do |path|
  docs = YAML.load_stream(File.read(path))
  outer = docs.first
  next unless outer.is_a?(Hash) && outer["data"].is_a?(Hash)

  outer_sources = outer["data"]["sources"] || []
  localized = docs.drop(1)

  # Find VIM/VIML authoritative sources in localized docs
  vim_sources = []
  localized.each do |loc|
    next unless loc.is_a?(Hash) && loc["data"].is_a?(Hash)
    loc_sources = loc["data"]["sources"] || []
    loc_sources.each do |s|
      next unless s.is_a?(Hash)
      ref = s.dig("origin", "ref", "source")
      next unless ref && ref.match?(VIM_PATTERN)
      vim_sources << s
    end
  end

  if vim_sources.empty?
    unchanged += 1
    next
  end

  # Deduplicate VIM sources (same ref may appear in multiple localized docs)
  seen_refs = {}
  unique_vim = []
  vim_sources.each do |s|
    ref = s.dig("origin", "ref", "source")
    clause = s.dig("locality", "reference_from")
    key = "#{ref}|#{clause}"
    next if seen_refs[key]
    seen_refs[key] = true
    unique_vim << s
  end

  # Get the publication source from the outer doc (the immediate source)
  pub_source = outer_sources.find { |s| s["type"] == "authoritative" }
  pub_ref = pub_source&.dig("origin", "ref", "source")
  pub_version = pub_source&.dig("origin", "ref", "version")
  pub_clause = pub_source&.dig("locality", "reference_from")

  # Build new outer sources array
  new_sources = []

  # 1. Add VIM/VIML as authoritative sources (original definitions)
  unique_vim.each do |vs|
    vim_ref = vs.dig("origin", "ref", "source")
    vim_clause = vs.dig("locality", "reference_from")
    new_sources << {
      "type" => "authoritative",
      "origin" => { "ref" => { "source" => vim_ref } },
      "locality" => vim_clause ? { "type" => "clause", "reference_from" => vim_clause } : nil,
    }.compact
  end

  # 2. Add the publication as lineage (reproduction) with sourced_from
  if pub_source
    lineage = {
      "type" => "lineage",
      "status" => "identical",
      "origin" => { "ref" => { "source" => pub_ref,
                               "version" => pub_version } },
      "locality" => pub_clause ? { "type" => "clause", "reference_from" => pub_clause } : nil,
      "sourced_from" => unique_vim.map do |vs|
        { "ref" => { "source" => vs.dig("origin", "ref", "source") } }
      end,
    }.compact
    new_sources << lineage
  end

  # 3. Keep any other non-authoritative sources from outer
  outer_sources.each do |s|
    next if s == pub_source
    next if s["type"] == "authoritative"  # replaced by VIM authoritative
    new_sources << s
  end

  outer["data"]["sources"] = new_sources

  # Clear sources from localized docs (they inherit from outer)
  localized.each do |loc|
    next unless loc.is_a?(Hash) && loc["data"].is_a?(Hash)
    loc["data"]["sources"] = []
  end

  File.write(path, dump_multi_doc(docs))
  restructured += 1
end

puts "Restructured: #{restructured}"
puts "Unchanged:    #{unchanged}"
