#!/usr/bin/env ruby
# frozen_string_literal: true

# Parse cached G 18 source data (scraped by scrape_g18_ptb.rb) into a structured
# JSON file keyed by 5-digit concept id, suitable for comparison against
# datasets/g18-2010/concepts/*.yaml.
#
# Inputs (all produced by scrape_g18_ptb.rb):
#   reference-docs/g018-2010-ptb/raw/manifest.json
#   reference-docs/g018-2010-ptb/raw/notes/<tid>.json
#   reference-docs/g018-2010-ptb/raw/terms/<tid>.json
#   reference-docs/g018-2010-ptb/raw/direct/<tid>.json
#   reference-docs/g018-2010-ptb/raw/html/<tid>.html   (optional)
#   datasets/g18-2010/bibliography.yaml                (canonical pub names)
#
# Output:
#   reference-docs/g018-2010-ptb/parsed.json
#
# READ-ONLY on datasets/. This script does not modify the canonical YAML.
#
# Usage:
#   ruby scripts/parse_g18_ptb.rb
#   ruby scripts/parse_g18_ptb.rb --raw PATH --out PATH

require "json"
require "yaml"
require "optparse"
require "fileutils"
require "set"

repo_root = File.expand_path("..", __dir__)
options = {
  raw_root: File.join(repo_root, "reference-docs", "g018-2010-ptb", "raw"),
  bib_path: File.join(repo_root, "datasets", "g18-2010", "bibliography.yaml"),
  out_path: File.join(repo_root, "reference-docs", "g018-2010-ptb", "parsed.json"),
}
OptionParser.new do |opts|
  opts.banner = "Usage: #{$PROGRAM_NAME} [options]"
  opts.on("--raw PATH", String) { |v| options[:raw_root] = v }
  opts.on("--bib PATH", String) { |v| options[:bib_path] = v }
  opts.on("--out PATH", String) { |v| options[:out_path] = v }
  opts.on("-h", "--help") { puts opts; exit 0 }
end.parse!

manifest_path = File.join(options[:raw_root], "manifest.json")
abort "manifest.json not found at #{manifest_path} — run scrape_g18_ptb.rb first." unless File.exist?(manifest_path)
manifest = JSON.parse(File.read(manifest_path))

bib = YAML.safe_load(File.read(options[:bib_path]))
bib_compact_to_canonical = bib.each_with_object({}) do |e, h|
  # "OIML R 111-1:2004" → compact "R111-1:2004" by stripping "OIML " and the
  # space between the letter prefix and the first digit.
  compact = e["id"].to_s.sub(/\AOIML\s+/, "").sub(/\A([A-Z])\s+/, '\1')
  h[compact] = e["id"]
end

# --- Helpers --------------------------------------------------------------

# Strip the trailing " #NNNNN" concept-id suffix from a TemaTres display
# string and collapse the heavy internal padding.
CONCEPT_SUFFIX_RE = /#\s*\d{1,5}\s*\z/
def clean_designation(str)
  str.to_s.sub(CONCEPT_SUFFIX_RE, "").gsub(/\s+/, " ").strip
end

# Parse one cataloger's "reference:" note into {raw, pub_compact,
# pub_canonical, clause}. Returns nil for non-reference notes.
REF_RE = /\Areference:\s+(\S+)(?:\s+(.+))?\z/m
def parse_reference_note(text, bib_map)
  m = text.to_s.match(REF_RE)
  return nil unless m
  pub_compact = m[1]
  clause = m[2] ? m[2].strip : nil
  {
    "raw" => text.strip,
    "pub_compact" => pub_compact,
    "pub_canonical" => bib_map[pub_compact] || pub_compact,
    "clause" => clause,
  }
end

# Quick check for HTML math indicators. The source site flattens math to plain
# text (no MathML), but we record whether any <math>, <sub>, <sup> elements
# exist — useful as a positive signal when they DO appear.
def html_math_indicators(html)
  return {} if html.nil? || html.empty?
  {
    "mathml" => html.include?("<math"),
    "sub"    => html.include?("<sub"),
    "sup"    => html.include?("<sup"),
  }
end

# Extract ARK URI from cached HTML. TemaTres exposes it as
# <a id="uri_ark" href="...">ark:/99152/...</a>.
ARK_RE = /id="uri_ark"\s+href="[^"]*">([^<]+)/
def extract_ark(html)
  return nil if html.nil? || html.empty?
  m = html.match(ARK_RE)
  m && m[1].strip
end

# --- Parse ----------------------------------------------------------------

puts "Parsing G 18 source data..."
puts "  manifest terms:     #{manifest.size}"
puts "  bibliography pubs:  #{bib.size}"

terms_with_concept = manifest.select { |_, v| v["concept_id"] }
puts "  terms w/ concept_id: #{terms_with_concept.size}"

# Some concept_ids appear multiple times (the same term in multiple
# publications, or duplicates from indexing). Collect all source records per
# concept_id so the comparator can see every instance.
parsed = Hash.new { |h, k| h[k] = [] }
skipped_no_cache = 0

terms_with_concept.each do |tid, meta|
  concept_id = meta["concept_id"]
  notes_path = File.join(options[:raw_root], "notes", "#{tid}.json")
  term_path  = File.join(options[:raw_root], "terms", "#{tid}.json")
  direct_path = File.join(options[:raw_root], "direct", "#{tid}.json")
  html_path  = File.join(options[:raw_root], "html", "#{tid}.html")

  unless File.exist?(notes_path)
    skipped_no_cache += 1
    next
  end

  notes_data = JSON.parse(File.read(notes_path))["result"] || {}
  notes = notes_data.is_a?(Hash) ? notes_data.values : notes_data

  definition = nil
  scope_notes = []
  cataloger_notes = []
  history_notes = []
  other_notes = []

  notes.each do |n|
    case n["note_type"]
    when "DF" then definition = n["note_text"].to_s.strip
    when "NA" then scope_notes << n["note_text"].to_s.strip
    when "NC" then cataloger_notes << n["note_text"].to_s.strip
    when "NH" then history_notes << n["note_text"].to_s.strip
    else           other_notes << { "type" => n["note_type"], "text" => n["note_text"].to_s.strip }
    end
  end

  references = cataloger_notes.map { |t| parse_reference_note(t, bib_compact_to_canonical) }.compact
  id_note    = cataloger_notes.find { |t| t =~ /\AID:\s*\d/ }
  other_cat  = cataloger_notes.reject { |t| t =~ /\A(reference|ID):/ }

  term_meta = nil
  if File.exist?(term_path)
    tdata = JSON.parse(File.read(term_path))["result"] || {}
    term_meta = tdata["term"] || tdata
  end

  direct_terms = []
  if File.exist?(direct_path)
    ddata = JSON.parse(File.read(direct_path))["result"] || {}
    ddata.each do |_, d|
      next unless d.is_a?(Hash) && d["string"]
      direct_terms << {
        "term_id" => d["term_id"],
        "string" => clean_designation(d["string"]),
        "relation" => d["relation_type"],   # BT / NT / RT / UF
        "relation_label" => d["relation_label"],
      }
    end
  end

  html = File.exist?(html_path) ? File.read(html_path) : nil

  record = {
    "term_id" => tid.to_i,
    "concept_id" => concept_id,
    "letter" => meta["letter"],
    "designation_raw" => meta["string"],
    "designation" => clean_designation(meta["string"]),
    "definition" => definition,
    "scope_notes" => scope_notes,
    "references" => references,
    "id_note" => id_note,
    "other_cataloger_notes" => other_cat,
    "history_notes" => history_notes,
    "other_notes" => other_notes,
    "direct_terms" => direct_terms,
    "broader_terms" => direct_terms.select { |d| d["relation"] == "3" },  # BT
    "narrower_terms" => direct_terms.select { |d| d["relation"] == "2" }, # NT
    "related_terms" => direct_terms.select { |d| d["relation"] == "4" },  # RT
    "alt_terms" => direct_terms.select { |d| d["relation"] == "5" },      # UF
    "ark_uri" => extract_ark(html),
    "html_math_indicators" => html_math_indicators(html),
    "date_created" => term_meta && term_meta["date_create"],
    "lang" => term_meta && term_meta["lang"],
    "code" => term_meta && term_meta["code"],
    "notes_path" => "raw/notes/#{tid}.json",
    "html_path" => html ? "raw/html/#{tid}.html" : nil,
  }
  parsed[concept_id] << record
end

puts "  skipped (no cache):  #{skipped_no_cache}"
puts "  unique concept_ids: #{parsed.size}"
multi = parsed.select { |_, v| v.size > 1 }
puts "  concept_ids w/ multiple source terms: #{multi.size}"

# Convert Hash-of-arrays to final shape: one entry per concept_id; if multiple
# source terms, keep them all under "source_terms".
final = parsed.each_with_object({}) do |(cid, records), h|
  h[cid] = {
    "concept_id" => cid,
    "source_term_count" => records.size,
    "source_terms" => records,
  }
end

FileUtils.mkdir_p(File.dirname(options[:out_path]))
tmp = options[:out_path] + ".tmp"
File.write(tmp, JSON.pretty_generate(final))
File.rename(tmp, options[:out_path])

puts
puts "Parsed #{final.size} concept_ids from #{terms_with_concept.size} source terms."
puts "Output: #{options[:out_path]}"
puts "Next: ruby scripts/compare_g18_ptb.rb"
