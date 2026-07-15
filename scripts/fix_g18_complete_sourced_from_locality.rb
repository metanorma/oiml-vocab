#!/usr/bin/env ruby
# frozen_string_literal: true

# Fix g18-complete sourced_from entries to include locality (clause).
# The locality is available from the authoritative source's locality.

require "yaml"
require "pathname"

CONCEPTS = Pathname.new(File.expand_path("../datasets/g18-complete/concepts", __dir__))

def dump_multi_doc(docs)
  parts = docs.map { |d| YAML.dump(d).sub(/\A---\n/, "") }
  "---\n" + parts.join("---\n") + "\n"
end

files = Dir.glob(File.join(CONCEPTS, "*.yaml")).sort
fixed = 0

files.each do |path|
  docs = YAML.load_stream(File.read(path))
  outer = docs.first
  next unless outer.is_a?(Hash) && outer["data"].is_a?(Hash)

  sources = outer["data"]["sources"]
  next unless sources.is_a?(Array)

  # Build a ref→locality map from authoritative sources
  auth_localities = {}
  sources.each do |s|
    next unless s.is_a?(Hash) && s["type"] == "authoritative"
    ref = s.dig("origin", "ref", "source")
    loc = s["locality"]
    auth_localities[ref] = loc if ref && loc
  end

  changed = false
  sources.each do |s|
    next unless s.is_a?(Hash) && s["sourced_from"].is_a?(Array)
    s["sourced_from"].each do |sf|
      next unless sf.is_a?(Hash)
      next if sf["locality"] # already has locality
      sf_ref = sf.dig("ref", "source")
      next unless sf_ref
      loc = auth_localities[sf_ref]
      next unless loc
      sf["locality"] = loc
      changed = true
    end
  end

  next unless changed
  File.write(path, dump_multi_doc(docs))
  fixed += 1
end

puts "Fixed sourced_from locality in #{fixed} files"
