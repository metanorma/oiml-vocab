#!/usr/bin/env ruby
# frozen_string_literal: true

# Audit vocab/datasets/g18/concepts/*.yaml against the OCR ground truth in
# reference-docs/g018-2010-ocr/glm-ocr.md.
#
# The OCR output is structured as HTML tables with columns:
#   Term | Reference | Definition | Notes | ID
#
# This script:
#   1. Parses every OCR row into a (id, term, reference, definition, notes) tuple
#   2. Loads every YAML concept file keyed by identifier
#   3. Reports discrepancies:
#        - IDs in OCR but missing from YAML
#        - IDs in YAML but missing from OCR
#        - Designation mismatches (OCR term vs YAML preferred designation)
#        - Definition text corruption (YAML has obvious extraction artifacts)
#   4. Saves a machine-readable report to reference-docs/g018-2010-ocr/audit.json
#      and prints a human-readable summary.
#
# Usage:
#   ruby scripts/audit_g18_vs_ocr.rb
#   ruby scripts/audit_g18_vs_ocr.rb --ocr PATH --concepts PATH --out PATH

require "optparse"
require "json"
require "yaml"
require "set"
require "fileutils"

repo_root = File.expand_path("..", __dir__)
options = {
  ocr_path: File.join(repo_root, "reference-docs", "g018-2010-ocr", "glm-ocr.md"),
  concepts_dir: File.join(repo_root, "datasets", "g18", "concepts"),
  out_path: File.join(repo_root, "reference-docs", "g018-2010-ocr", "audit.json"),
}

OptionParser.new do |opts|
  opts.banner = "Usage: #{$PROGRAM_NAME} [options]"
  opts.on("--ocr PATH", String) { |v| options[:ocr_path] = v }
  opts.on("--concepts PATH", String) { |v| options[:concepts_dir] = v }
  opts.on("--out PATH", String) { |v| options[:out_path] = v }
  opts.on("-h", "--help") { puts opts; exit 0 }
end.parse!

abort "OCR file not found: #{options[:ocr_path]}" unless File.exist?(options[:ocr_path])
abort "Concepts dir not found: #{options[:concepts_dir]}" unless Dir.exist?(options[:concepts_dir])

# Extract one OCR row's cells. Splits the document on `<tr>` boundaries
# first so cell content can safely contain `<` / `>` (math notation,
# comparisons) without risking cross-row matches.
ROW_RE = /<td>(.*?)<\/td>/m

def parse_ocr(path)
  text = File.read(path)
  rows = []
  text.split(/<tr>/i).each do |row_text|
    cells = row_text.scan(ROW_RE).map { |m| clean_html(m.first) }
    next unless cells.size == 5
    id = cells.last
    next unless id =~ /\A\d{5}\z/
    rows << {
      "id" => id,
      "term" => cells[0],
      "reference" => cells[1],
      "definition" => cells[2],
      "notes" => cells[3],
    }
  end
  rows
end

# Collapse whitespace, strip simple HTML escapes. Leave brackets/parens alone
# so the audit can spot editorial annotations baked into the designation.
def clean_html(s)
  s.to_s
    .gsub(/<[^>]+>/, "")           # drop any nested tags
    .gsub("&amp;", "&")
    .gsub("&lt;", "<")
    .gsub("&gt;", ">")
    .gsub("&quot;", '"')
    .gsub("&#39;", "'")
    .gsub(/\s+/, " ")
    .strip
end

# Obvious extraction-corruption signals in YAML definitions/designations.
# `[VIM ...]` / `[VIML ...]` in a definition is a *legitimate citation* the
# source publication embedded — NOT corruption. In a *designation* it IS
# corruption (the citation got attached to the wrong field).
CORRUPTION_PATTERNS = {
  "leading_lowercase_orphan" => /\A[a-z]{1,4}\s+[A-Z][a-z]/,        # "inte set of specified..."
  "trailing_punctuation_junk"=> /[\]\)]\s+[a-z]{1,3}\z/i,            # "] it" at end
  "broken_word_runon"        => /[a-z]{2}[A-Z][a-z]{2,}/,             # "resultsmeasurements"
  "mid_sentence_note_leak"   => /\b[of|the|to]\s+[A-Z][a-z]+ [a-z]+ [a-z]+ [a-z]+ [a-z]+ [a-z]+ [a-z]+\b/,
}

def detect_corruption(text)
  CORRUPTION_PATTERNS.each_with_object([]) do |(name, re), a|
    a << name if text =~ re
  end
end

# Normalize for whitespace/punctuation differences that are OCR variance,
# not real corruption. Specifically: OCR often drops the space before
# opening parens ("type(pattern)" vs "type (pattern)"), and OCR renders
# smart quotes / entities differently. Also: treat `$X$` (LaTeX) and
# `stem:[X]` (AsciiDoc) as equivalent — both are math markup.
def normalize_for_compare(s)
  s.to_s
    .gsub(/&#x27;|&#39;|'/, "'")        # smart apostrophe
    .gsub(/&quot;|"/, '"')              # smart quote
    .gsub(/\$([^$]+)\$/) { "stem:[#{$1}]" }   # $X$ → stem:[X]
    .gsub(/\\([a-zA-Z]+)/) { $1 }       # \Delta → Delta (drop backslash only)
    .gsub(/\s*\(\s*/, "(")              # collapse spaces around parens
    .gsub(/\s*\)\s*/, ") ")
    .gsub(/\s+/, " ")
    .downcase
    .strip
end

def load_yaml_concepts(dir)
  Dir.glob(File.join(dir, "*.yaml")).each_with_object({}) do |file, h|
    docs = YAML.safe_load_stream(File.read(file), filename: file, aliases: true)
    meta = docs.find { |d| d && d.is_a?(Hash) && d.dig("data", "identifier") }
    loc = docs.find { |d| d && d.is_a?(Hash) && d.dig("data", "definition") }
    next unless meta
    id = meta.dig("data", "identifier").to_s
    terms = loc ? loc.dig("data", "terms") : nil
    pref = Array(terms).find { |t| t["normative_status"] == "preferred" } || Array(terms).first
    defs = loc ? loc.dig("data", "definition") : nil
    defn_text = Array(defs).map { |d| d["content"] if d.is_a?(Hash) }.compact.join(" ")
    h[id] = {
      "id" => id,
      "designation" => pref ? pref["designation"] : nil,
      "definition" => defn_text,
      "source" => meta.dig("data", "sources", 0, "origin", "ref", "source"),
      "file" => file,
    }
  end
end

ocr_rows = parse_ocr(options[:ocr_path])
yaml = load_yaml_concepts(options[:concepts_dir])

# The source G 18 PDF reuses 7 IDs for two different terms each. YAML splits
# these as `<id>a` / `<id>b`. Pair duplicate-ID OCR rows with their suffixed
# counterparts by encounter order.
ocr_by_id = {}
ocr_rows.group_by { |r| r["id"] }.each do |id, rows|
  if rows.size == 1
    ocr_by_id[id] = rows.first
  else
    rows.sort_by { |r| r["term"].to_s.downcase }.each_with_index do |r, i|
      ocr_by_id["#{id}#{('a'.ord + i).chr}"] = r
    end
  end
end

ocr_ids = ocr_by_id.keys.to_set
yaml_ids = yaml.keys.to_set

in_ocr_not_yaml = ocr_ids - yaml_ids
in_yaml_not_ocr = yaml_ids - ocr_ids
both_ids = ocr_ids & yaml_ids

designation_mismatches = []
definition_corruption = []
designation_corruption = []

both_ids.sort.each do |id|
  ocr = ocr_by_id[id]
  y = yaml[id]

  # Designation comparison (normalized — OCR whitespace/parens differ)
  if normalize_for_compare(ocr["term"]) != normalize_for_compare(y["designation"])
    designation_mismatches << {
      "id" => id,
      "ocr_term" => ocr["term"],
      "yaml_term" => y["designation"],
    }
  end

  # Corruption detection on YAML fields (designation corruption is always
  # actionable; definition corruption here excludes legitimate citations).
  yaml_defn_issues = detect_corruption(y["definition"].to_s)
  yaml_desig_issues = detect_corruption(y["designation"].to_s)
  unless yaml_defn_issues.empty?
    definition_corruption << { "id" => id, "issues" => yaml_defn_issues, "yaml_definition" => y["definition"] }
  end
  unless yaml_desig_issues.empty?
    designation_corruption << { "id" => id, "issues" => yaml_desig_issues, "yaml_designation" => y["designation"] }
  end
end

# Detect redundant bare IDs: 7 IDs in the source PDF are reused for two
# different terms each. YAML represents each occurrence as `<id>a` /
# `<id>b` AND keeps a `<id>` bare version that duplicates one side. The
# bare versions are cruft and should be reviewed for removal.
redundant_bare_ids = yaml_ids.select do |id|
  next false unless id =~ /\A\d{5}\z/
  yaml_ids.include?("#{id}a") && yaml_ids.include?("#{id}b")
end.sort

report = {
  "summary" => {
    "ocr_rows_total"     => ocr_rows.size,
    "ocr_unique_ids"     => ocr_by_id.size,
    "yaml_concept_count" => yaml.size,
    "in_ocr_not_yaml"    => in_ocr_not_yaml.size,
    "in_yaml_not_ocr"    => in_yaml_not_ocr.size,
    "shared_ids"         => both_ids.size,
    "designation_mismatches" => designation_mismatches.size,
    "definition_corruption"  => definition_corruption.size,
    "designation_corruption" => designation_corruption.size,
    "redundant_bare_ids"     => redundant_bare_ids.size,
  },
  "in_ocr_not_yaml"  => in_ocr_not_yaml.sort,
  "in_yaml_not_ocr"  => in_yaml_not_ocr.sort,
  "redundant_bare_ids" => redundant_bare_ids,
  "designation_mismatches" => designation_mismatches,
  "definition_corruption"  => definition_corruption,
  "designation_corruption" => designation_corruption,
}

FileUtils.mkdir_p(File.dirname(options[:out_path]))
File.write(options[:out_path], JSON.pretty_generate(report))

puts "G 18 OCR vs YAML audit"
puts "  OCR rows parsed:        #{ocr_rows.size}"
puts "  OCR unique IDs:         #{ocr_by_id.size}"
puts "  YAML concept files:     #{yaml.size}"
puts
puts "Coverage:"
puts "  In OCR but not YAML:    #{in_ocr_not_yaml.size}  (YAML missing entries)"
puts "  In YAML but not OCR:    #{in_yaml_not_ocr.size}  (YAML has extra / OCR missed)"
puts "  Shared:                 #{both_ids.size}"
puts
puts "Discrepancies on shared entries:"
puts "  Designation mismatches: #{designation_mismatches.size}"
puts "  Definition corruption:  #{definition_corruption.size}"
puts "  Designation corruption: #{designation_corruption.size}"
puts
puts "Structural issues:"
puts "  Redundant bare IDs (duplicated by a/b split): #{redundant_bare_ids.size}"
puts
puts "Full report: #{options[:out_path]}"
