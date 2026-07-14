#!/usr/bin/env ruby
# frozen_string_literal: true

# Migrate g18-complete concepts:
# 1. Update domains to reflect the immediate source publication family
#    (e.g. "OIML B 3:2003" → section "B 3").
# 2. Convert "Source citation:" notes into proper sources[] entries
#    with lineage chains per concept-model v3.
#
# Idempotent: re-running is safe.

require "yaml"
require "pathname"
require "set"

CONCEPTS = Pathname.new(File.expand_path("../datasets/g18-complete/concepts", __dir__))

# ---- Citation parser -------------------------------------------------------

# Parse a "Source citation:" note text into structured source data.
# Returns {ref:, clause:, type:} or nil if unparseable.
#
# Handles patterns:
#   "VIML 2.5"                          → VIML §2.5
#   "VIM 3.8"                           → VIM §3.8
#   "OIML V 2-200:2012 (VIM) 3.8"       → VIM 2012 §3.8
#   "adapted from VIM 5.20"             → VIM §5.20
#   "ISO/IEC Guide 2, 13.1"             → ISO/IEC Guide 2 §13.1
#   "D 11:2004, 3.2"                    → D 11:2004 §3.2
#   "OIML D 11:2013, 3.5"               → D 11:2013 §3.5
#   "adapted from OIML B 3:2003, 2.3"   → B 3:2003 §2.3
def parse_citation(text)
  text = text.to_s.sub(/\ASource citation:\s*/i, "").strip

  # Try OIML full form: "OIML V 2-200:2012 (VIM) 3.8"
  if (m = text.match(/\AOIML\s+([VDGRBEPS])\s+([0-9\-]+):(\d{4})\s*(?:\([^)]+\))?\s*,?\s*([0-9][0-9A-Za-z.]*)/i))
    ref = "OIML #{$1.upcase} #{$2}:#{$3}"
    clause = normalize_clause($4)
    return { ref: ref, clause: clause, type: "authoritative" }
  end

  # Try "adapted from OIML X N:YYYY, clause"
  if (m = text.match(/adapted\s+from\s+OIML\s+([VDGRBEPS])\s+([0-9\-]+):(\d{4})\s*,?\s*([0-9][0-9A-Za-z.]*)?/i))
    ref = "OIML #{$1.upcase} #{$2}:#{$3}"
    clause = normalize_clause($4) if $4
    return { ref: ref, clause: clause, type: "lineage", status: "modified" }
  end

  # Try "VIM X.Y" / "VIML X.Y"
  if (m = text.match(/\A(?:adapted\s+from\s+)?VIML\s+([0-9][0-9A-Za-z.]*)/i))
    return { ref: "OIML V 1:2013", clause: normalize_clause($1), type: "authoritative" }
  end
  if (m = text.match(/\A(?:adapted\s+from\s+)?VIM\s+([0-9][0-9A-Za-z.]*)/i))
    return { ref: "OIML V 2-200:2012", clause: normalize_clause($1), type: "authoritative" }
  end
  if (m = text.match(/\A(?:adapted\s+from\s+)?VIM:1993[,\s]+([0-9][0-9A-Za-z.]*)/i))
    return { ref: "OIML V 2:1993", clause: normalize_clause($1), type: "authoritative" }
  end
  if (m = text.match(/\A(?:adapted\s+from\s+)?VIM:2013[,\s]+([0-9][0-9A-Za-z.]*)/i))
    return { ref: "OIML V 2-200:2012", clause: normalize_clause($1), type: "authoritative" }
  end

  # Try "ISO/IEC ... clause"
  if (m = text.match(%r{\A(?:adapted\s+from\s+)?(ISO(?:/IEC)?\s+[\w\-]+)\s*,?\s*([0-9][0-9A-Za-z.]*)}i))
    return { ref: $1, clause: normalize_clause($2), type: "authoritative" }
  end

  # Try "D 11:2004, 3.2" or "D 11 3.2" (OIML D-series shorthand)
  if (m = text.match(/\A(?:adapted\s+from\s+)?D\s+(\d+):(\d{4})\s*,?\s*([0-9][0-9A-Za-z.]*)/i))
    return { ref: "OIML D #{$1}:#{$2}", clause: normalize_clause($3), type: "authoritative" }
  end

  # Try "OIML B 3:2003, 2.3" (explicit OIML prefix)
  if (m = text.match(/\A(?:adapted\s+from\s+)?OIML\s+([A-Z])\s+(\d+):(\d{4})\s*,?\s*([0-9][0-9A-Za-z.]*)/i))
    return { ref: "OIML #{$1} #{$2}:#{$3}", clause: normalize_clause($4), type: "authoritative" }
  end

  # Fallback: just store raw
  { ref: nil, clause: nil, type: "lineage", raw: text }
end

def normalize_clause(s)
  s&.gsub(/\s+/, "")&.sub(/\.$/, "")
end

# ---- Section extraction ----------------------------------------------------

# Extract publication family from a source ref like "OIML B 3:2003" → "B 3"
def section_from_ref(ref)
  return nil unless ref
  if (m = ref.match(/\AOIML\s+([A-Z])\s+(\d+(?:-\d+)*)/))
    "#{$1} #{$2}"
  elsif (m = ref.match(/\AVIML\b/))
    "V 1"
  elsif (m = ref.match(/\AVIM\b/))
    "V 2-200"
  else
    nil
  end
end

def section_slug(section_name)
  return "misc" unless section_name
  section_name.downcase.tr(" ", "-").tr("/", "-")
end

# ---- Migration -------------------------------------------------------------

def dump_multi_doc(docs)
  parts = docs.map { |d| YAML.dump(d).sub(/\A---\n/, "") }
  "---\n" + parts.join("---\n") + "\n"
end

files = Dir.glob(File.join(CONCEPTS, "*.yaml")).sort
puts "Processing #{files.size} files..."

sections_found = Hash.new { |h, k| h[k] = 0 }
citations_converted = 0
files_changed = 0

files.each do |path|
  docs = YAML.load_stream(File.read(path))
  changed = false

  docs.each do |doc|
    next unless doc.is_a?(Hash) && doc["data"].is_a?(Hash)
    data = doc["data"]

    # --- Task 2: Update domains to reflect source publication ---
    sources = data["sources"] || []
    primary_source = sources.find { |s| s.is_a?(Hash) && s["origin"] && s["origin"]["ref"] }
    if primary_source
      ref = primary_source.dig("origin", "ref", "source")
      section_name = section_from_ref(ref)
      if section_name
        slug = section_slug(section_name)
        data["domains"] = [{
          "concept_id" => slug,
          "source" => primary_source.dig("origin", "ref", "source"),
          "ref_type" => "section",
        }]
        sections_found[section_name] += 1
        changed = true
      end
    end

    # --- Task 3: Convert "Source citation:" notes to proper sources ---
    notes = data["notes"]
    if notes.is_a?(Array)
      citation_notes = notes.select { |n| n.is_a?(Hash) && n["content"].to_s.start_with?("Source citation:") }
      next if citation_notes.empty?

      # Parse each citation
      citations = citation_notes.map { |n| parse_citation(n["content"]) }.compact

      # Remove citation notes from the notes array
      data["notes"] = notes.reject { |n| n.is_a?(Hash) && n["content"].to_s.start_with?("Source citation:") }
      data["notes"] = nil if data["notes"].empty?

      # Get the current authoritative source (the publication where the term appears)
      current_auth = sources.find { |s| s["type"] == "authoritative" }
      current_ref = current_auth&.dig("origin", "ref", "source")
      current_version = current_auth&.dig("origin", "ref", "version")
      current_clause = current_auth&.dig("locality", "reference_from")

      # Build new sources array
      new_sources = []

      citations.each do |cit|
        next unless cit[:ref] # skip unparseable

        # The citation is the AUTHENTIC upstream source
        new_sources << {
          "type" => cit[:type] || "authoritative",
          "origin" => { "ref" => { "source" => cit[:ref] } },
          "locality" => cit[:clause] ? { "type" => "clause", "reference_from" => cit[:clause] } : nil,
        }.compact

        # Add lineage source for the current publication pointing upstream
        if current_ref && current_ref != cit[:ref]
          lineage = {
            "type" => "lineage",
            "status" => cit[:status] || "identical",
            "origin" => { "ref" => { "source" => current_ref,
                                     "version" => current_version } },
            "locality" => current_clause ? { "type" => "clause", "reference_from" => current_clause } : nil,
            "sourced_from" => [{ "ref" => { "source" => cit[:ref] } }],
          }.compact
          new_sources << lineage
        end
      end

      if new_sources.any?
        # Keep existing authoritative source if no citation replaced it
        if current_auth && new_sources.none? { |s| s["type"] == "authoritative" }
          new_sources.unshift(current_auth)
        end
        data["sources"] = new_sources
        citations_converted += citations.size
        changed = true
      end
    end
  end

  next unless changed

  File.write(path, dump_multi_doc(docs))
  files_changed += 1
end

puts "Files changed: #{files_changed}"
puts "Citations converted: #{citations_converted}"
puts "Sections found:"
sections_found.sort_by { |_, c| -c }.each { |s, c| puts "  #{s}: #{c}" }
