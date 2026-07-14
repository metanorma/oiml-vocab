#!/usr/bin/env ruby
# frozen_string_literal: true

# Update g18-complete register.yaml sections list from concept files' domains.
# Also regenerate the register via the aggregator.

require "yaml"
require "pathname"
require "set"

CONCEPTS = Pathname.new(File.expand_path("../datasets/g18-complete/concepts", __dir__))
REGISTER = Pathname.new(File.expand_path("../datasets/g18-complete/register.yaml", __dir__))

# Collect all unique section_ids with their source refs
sections = {}
CONCEPTS.children.each do |f|
  docs = YAML.load_stream(f.read)
  outer = docs.first
  next unless outer.is_a?(Hash) && outer["data"].is_a?(Hash)
  domains = outer["data"]["domains"] || []
  domains.each do |d|
    next unless d.is_a?(Hash) && d["concept_id"]
    slug = d["concept_id"]
    source = d["source"]
    sections[slug] ||= source
  end
end

# Build section names from slugs (convert "b-3" → "B 3")
def human_name(slug)
  slug.split("-").map.with_index do |part, i|
    if i == 0
      part.upcase  # kind letter
    else
      part
    end
  end.join(" ")
end

section_list = sections.keys.sort.map do |slug|
  {
    "id" => slug,
    "names" => { "eng" => human_name(slug) },
  }
end

# Read current register, update sections
register = YAML.load_file(REGISTER)
register["sections"] = section_list
register["ordering"] = "systematic"

File.write(REGISTER, YAML.dump(register))

puts "Updated register with #{section_list.size} sections"
puts "Sample:"
section_list.first(10).each { |s| puts "  #{s['id']}: #{s['names']['eng']}" }
