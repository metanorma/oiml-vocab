#!/usr/bin/env ruby
# frozen_string_literal: true

# Compare the parsed G 18 source data (from parse_g18_ptb.rb) against the
# canonical YAML concepts in datasets/g18-2010/concepts/*.yaml.
#
# This is the read-only audit the user asked for: verify that our YAML is
# 100% consistent with the PTB-hosted TemaTres source. It flags:
#
#   - Coverage gaps (in source but not YAML, or vice versa)
#   - Designation mismatches (after normalization for math notation & whitespace)
#   - Definition mismatches (after normalization)
#   - Reference mismatches (source publication + clause)
#   - Math divergence (YAML has <math>/stem:[] but source is plain text, or vice versa)
#   - Missing definitions (source has DF note but YAML has empty definition, or vice versa)
#
# READ-ONLY on datasets/. Output goes to reference-docs/g018-2010-ptb/audit.json.
#
# Usage:
#   ruby scripts/compare_g18_ptb.rb
#   ruby scripts/compare_g18_ptb.rb --parsed PATH --concepts PATH --out PATH

require "json"
require "yaml"
require "optparse"
require "fileutils"
require "set"

repo_root = File.expand_path("..", __dir__)
options = {
  parsed_path: File.join(repo_root, "reference-docs", "g018-2010-ptb", "parsed.json"),
  concepts_dir: File.join(repo_root, "datasets", "g18-2010", "concepts"),
  out_path: File.join(repo_root, "reference-docs", "g018-2010-ptb", "audit.json"),
}
OptionParser.new do |opts|
  opts.banner = "Usage: #{$PROGRAM_NAME} [options]"
  opts.on("--parsed PATH", String) { |v| options[:parsed_path] = v }
  opts.on("--concepts PATH", String) { |v| options[:concepts_dir] = v }
  opts.on("--out PATH", String) { |v| options[:out_path] = v }
  opts.on("-h", "--help") { puts opts; exit 0 }
end.parse!

abort "parsed.json not found: #{options[:parsed_path]} — run parse_g18_ptb.rb first." unless File.exist?(options[:parsed_path])
abort "concepts dir not found: #{options[:concepts_dir]}" unless Dir.exist?(options[:concepts_dir])

parsed = JSON.parse(File.read(options[:parsed_path]))

# --- YAML loading ---------------------------------------------------------

# Load every YAML concept. Multi-doc: first doc holds metadata (identifier,
# sources, domains); second doc holds localized content (terms, definition,
# notes). Group by base identifier (strip a/b suffix) since the source has one
# entry per concept_id while YAML may split into a/b variants.
def load_yaml_concepts(dir)
  by_base = Hash.new { |h, k| h[k] = [] }
  Dir.glob(File.join(dir, "*.yaml")).each do |file|
    docs = YAML.safe_load_stream(File.read(file), filename: file, aliases: true)
    meta = docs.find { |d| d && d.is_a?(Hash) && d.dig("data", "identifier") }
    loc  = docs.find { |d| d && d.is_a?(Hash) && d.dig("data", "definition") || (d && d.is_a?(Hash) && d.dig("data", "terms")) }
    next unless meta
    raw_id = meta.dig("data", "identifier").to_s
    base = raw_id.sub(/[a-z]\z/, "")
    variant = raw_id[-1] =~ /[a-z]/ ? raw_id[-1] : nil
    sources = meta.dig("data", "sources") || []
    origin = sources.find { |s| s["type"] == "authoritative" } || sources.first
    terms = loc ? (loc.dig("data", "terms") || []) : []
    defs  = loc ? (loc.dig("data", "definition") || []) : []
    notes = loc ? (loc.dig("data", "notes") || []) : []
    pref = terms.find { |t| t["normative_status"] == "preferred" } || terms.first
    defn_text = defs.map { |d| d["content"] if d.is_a?(Hash) }.compact.join(" ")
    by_base[base] << {
      "id" => raw_id,
      "base" => base,
      "variant" => variant,
      "file" => file,
      "designation" => pref ? pref["designation"] : nil,
      "all_terms" => terms,
      "definition" => defn_text,
      "notes" => notes,
      "source_pub" => origin && origin.dig("origin", "ref", "source"),
      "clause" => origin && origin.dig("locality", "reference_from"),
      "domains" => meta.dig("data", "domains"),
    }
  end
  by_base
end

yaml_by_base = load_yaml_concepts(options[:concepts_dir])

# --- Normalization --------------------------------------------------------

# Private-use Unicode codepoints (U+F000–U+F8FF) appear in TemaTres display
# strings where math symbols (μ, π, etc.) were flattened from a Symbol font.
# Strip them so they don't pollute the text comparison.
PUA_RE = /[-﫿-]/

# PUA chars that are NOT math: the Symbol-font bullet (U+F0B7) and checkbox
# (U+F0A7) appear in multi-clause definitions as list markers. They are
# formatting artifacts, not lost math notation — exclude from math detection.
PUA_NON_MATH = ["\uF0B7", "\uF0A7"].freeze  # Symbol-font bullet, checkbox
def pua_math_chars(s)
  s.to_s.chars.select { |c| c =~ PUA_RE && !PUA_NON_MATH.include?(c) }.uniq
end

# Normalize for whitespace/punctuation/math-notation differences that are
# extraction variance, not real corruption. Mirrors the normalization in
# audit_g18_vs_ocr.rb, plus PUA stripping for the TemaTres source.
def normalize_for_compare(s)
  s.to_s
    .gsub(PUA_RE, "")
    .gsub(/&#x27;|&#39;|'|’/, "'")
    .gsub(/&quot;|"|“|”/, '"')
    .gsub(/\$([^$]+)\$/) { "stem:[#{$1}]" }
    .gsub(/\\([a-zA-Z]+)/) { $1 }
    .gsub(/<[^>]+>/, "")        # strip any residual HTML/MathML tags
    .gsub(/\s*\(\s*/, "(")
    .gsub(/\s*\)\s*/, ") ")
    .gsub(/\s+/, " ")
    .downcase
    .strip
end

# Normalize an OIML publication reference for comparison. Both sides use
# different forms:
#   - YAML:     "OIML B 3:2003", "OIML R 111-1:2004"
#   - Source:   "B003:2003" (compact, zero-padded, no OIML prefix)
# Normalized form is "B 3:2003" / "R 111-1:2004" — strip OIML prefix, strip
# leading zeros from the publication number, single space after letter.
def normalize_pub(s)
  s.to_s
    .strip
    .sub(/\AOIML\s+/, "")
    .sub(/\A([A-Z])\s*0*(\d+)/) { "#{$1} #{$2}" }
end

# Extract the clause from a normalized pub+clause string (everything after
# the "LETTER NUMBER:YEAR " prefix).
CLAUSE_PREFIX_RE = /\A[A-Z]\s*\d+(-\d+)?:\d{4}\s*/
def extract_clause(s)
  s.to_s.sub(CLAUSE_PREFIX_RE, "").strip
end

# --- Math divergence detection -------------------------------------------

def yaml_has_math?(yaml_entry)
  text = [yaml_entry["designation"], yaml_entry["definition"]].compact.join(" ")
  text.include?("<math") || text.include?("stem:[") || text.include?("$")
end

# The source site flattens math symbols (μ, π, subscripts) into plain text
# using private-use Unicode codepoints from the Symbol font. These are the
# unambiguous signal that the source has math notation our YAML may need.
# Excludes U+F0B7 (Symbol-font bullet) which is a list marker, not math.
def source_math_artifacts(source_record)
  desig_pua = pua_math_chars(source_record["designation_raw"].to_s)
  def_pua   = pua_math_chars(source_record["definition"].to_s)
  {
    "designation_pua" => desig_pua.map { |c| "U+%04X" % c.ord },
    "definition_pua"  => def_pua.map { |c| "U+%04X" % c.ord },
  }
end

# --- Severity scoring & multi-source best-match ---------------------------

# Word-level Jaccard similarity after normalization. Fast and good enough for
# deciding "is this the same text with minor edits" vs "completely different".
def word_similarity(a, b)
  aw = normalize_for_compare(a).split
  bw = normalize_for_compare(b).split
  return 1.0 if aw.empty? && bw.empty?
  return 0.0 if aw.empty? || bw.empty?
  ((aw & bw).size.to_f / (aw | bw).size).round(3)
end

def severity(a, b)
  na = normalize_for_compare(a)
  nb = normalize_for_compare(b)
  return "minor"    if na == nb
  # Substring relationship = one side lost/gained a qualifier or symbol only
  return "minor"    if na.include?(nb) || nb.include?(na)
  sim = word_similarity(a, b)
  return "minor"    if sim >= 0.8
  return "moderate" if sim >= 0.5
  "severe"
end

# When a concept_id has multiple source terms (G 18 reuses some IDs for two
# different terms), pair the YAML variant with its best-matching source term
# instead of blindly taking the first — avoids false "severe" mismatches.
def best_source_match(yaml_desig, source_terms)
  return source_terms.first if source_terms.size <= 1
  source_terms.max_by { |s| word_similarity(yaml_desig, s["designation"]) }
end

# --- Compare --------------------------------------------------------------

source_ids = parsed.keys.to_set
yaml_ids   = yaml_by_base.keys.to_set
both_ids   = source_ids & yaml_ids
in_source_only = source_ids - yaml_ids
in_yaml_only   = yaml_ids - source_ids

designation_mismatches = []
definition_mismatches = []
reference_mismatches = []
math_divergence = []
missing_definition_in_yaml = []
missing_definition_in_source = []
multi_source_review = []

both_ids.sort.each do |cid|
  src = parsed[cid]
  yamls = yaml_by_base[cid]

  # Prefer the bare YAML variant (no a/b suffix) for the primary comparison.
  primary = yamls.find { |y| y["variant"].nil? } || yamls.first

  # Use the first source term as the representative. If multiple source terms
  # exist for this concept_id, queue for multi-source review.
  if src["source_term_count"] > 1
    multi_source_review << {
      "id" => cid,
      "source_term_count" => src["source_term_count"],
      "yaml_variant_count" => yamls.size,
      "yaml_variants" => yamls.map { |y| { "id" => y["id"], "designation" => y["designation"] } },
      "source_terms" => src["source_terms"].map { |s| { "term_id" => s["term_id"], "designation" => s["designation"] } },
    }
  end
  src_term = best_source_match(primary["designation"], src["source_terms"])
  src_designation = src_term["designation"]
  src_definition = src_term["definition"]
  src_refs = src_term["references"] || []

  # --- Designation ---
  if normalize_for_compare(src_designation) != normalize_for_compare(primary["designation"])
    designation_mismatches << {
      "id" => cid,
      "severity" => severity(src_designation, primary["designation"]),
      "source_designation" => src_designation,
      "yaml_designation" => primary["designation"],
      "yaml_file" => File.basename(primary["file"]),
    }
  end

  # --- Definition ---
  if src_definition.nil? || src_definition.empty?
    if !primary["definition"].nil? && !primary["definition"].empty?
      missing_definition_in_source << { "id" => cid, "yaml_definition" => primary["definition"] }
    end
  elsif primary["definition"].nil? || primary["definition"].empty?
    missing_definition_in_yaml << { "id" => cid, "source_definition" => src_definition }
  elsif normalize_for_compare(src_definition) != normalize_for_compare(primary["definition"])
    definition_mismatches << {
      "id" => cid,
      "severity" => severity(src_definition, primary["definition"]),
      "source_definition" => src_definition,
      "yaml_definition" => primary["definition"],
      "yaml_file" => File.basename(primary["file"]),
    }
  end

  # --- Reference (source publication + clause) ---
  # Compare source's first reference against YAML's primary source. Both
  # sides use different pub formats (see normalize_pub); normalize before
  # comparing both the publication name and the clause.
  src_ref = src_refs.first
  if src_ref && primary["source_pub"]
    src_pub_n = normalize_pub(src_ref["pub_canonical"])
    yml_pub_n = normalize_pub(primary["source_pub"])
    # Build full normalized strings and compare clause separately
    src_full_n = "#{src_pub_n} #{src_ref['clause']}".strip
    yml_full_n = "#{yml_pub_n} #{primary['clause']}".strip
    src_clause_n = extract_clause(src_full_n)
    yml_clause_n = extract_clause(yml_full_n)
    if src_pub_n != yml_pub_n || src_clause_n != yml_clause_n
      reference_mismatches << {
        "id" => cid,
        "source_ref" => "#{src_ref['pub_canonical']} #{src_ref['clause']}".strip,
        "yaml_ref" => "#{primary['source_pub']} #{primary['clause']}".strip,
        "source_ref_normalized" => src_full_n,
        "yaml_ref_normalized" => yml_full_n,
        "yaml_file" => File.basename(primary["file"]),
      }
    end
  elsif src_ref && !primary["source_pub"]
    reference_mismatches << {
      "id" => cid,
      "source_ref" => "#{src_ref['pub_canonical']} #{src_ref['clause']}".strip,
      "yaml_ref" => nil,
      "yaml_file" => File.basename(primary["file"]),
    }
  end

  # --- Math divergence ---
  yaml_math = yaml_has_math?(primary)
  artifacts = source_math_artifacts(src_term)
  source_math = !artifacts["designation_pua"].empty? || !artifacts["definition_pua"].empty?
  if yaml_math && !source_math
    math_divergence << {
      "id" => cid,
      "kind" => "yaml_has_math_source_plain",
      "yaml_designation" => primary["designation"],
      "yaml_definition_excerpt" => primary["definition"]&.slice(0, 120),
      "source_designation" => src_designation,
    }
  elsif source_math && !yaml_math
    math_divergence << {
      "id" => cid,
      "kind" => "source_has_artifacts_yaml_plain",
      "yaml_designation" => primary["designation"],
      "source_designation" => src_term["designation_raw"],
      "source_definition_excerpt" => src_definition&.slice(0, 120),
      **artifacts,
    }
  end
end

# --- Report ---------------------------------------------------------------

report = {
  "summary" => {
    "source_concept_ids" => source_ids.size,
    "yaml_concept_ids" => yaml_ids.size,
    "shared_ids" => both_ids.size,
    "in_source_not_yaml" => in_source_only.size,
    "in_yaml_not_source" => in_yaml_only.size,
    "designation_mismatches" => designation_mismatches.size,
    "designation_severe" => designation_mismatches.count { |m| m["severity"] == "severe" },
    "designation_moderate" => designation_mismatches.count { |m| m["severity"] == "moderate" },
    "designation_minor" => designation_mismatches.count { |m| m["severity"] == "minor" },
    "definition_mismatches" => definition_mismatches.size,
    "definition_severe" => definition_mismatches.count { |m| m["severity"] == "severe" },
    "definition_moderate" => definition_mismatches.count { |m| m["severity"] == "moderate" },
    "definition_minor" => definition_mismatches.count { |m| m["severity"] == "minor" },
    "reference_mismatches" => reference_mismatches.size,
    "math_divergence" => math_divergence.size,
    "missing_definition_in_yaml" => missing_definition_in_yaml.size,
    "missing_definition_in_source" => missing_definition_in_source.size,
    "multi_source_concepts" => multi_source_review.size,
  },
  "in_source_not_yaml" => in_source_only.sort,
  "in_yaml_not_source" => in_yaml_only.sort,
  "designation_mismatches" => designation_mismatches,
  "definition_mismatches" => definition_mismatches,
  "reference_mismatches" => reference_mismatches,
  "math_divergence" => math_divergence,
  "missing_definition_in_yaml" => missing_definition_in_yaml,
  "missing_definition_in_source" => missing_definition_in_source,
  "multi_source_concepts" => multi_source_review,
}

FileUtils.mkdir_p(File.dirname(options[:out_path]))
File.write(options[:out_path], JSON.pretty_generate(report))

puts "G 18 PTB source vs YAML audit"
puts "  Source concept_ids:   #{source_ids.size}"
puts "  YAML concept_ids:     #{yaml_ids.size}"
puts "  Shared:               #{both_ids.size}"
puts
puts "Coverage:"
puts "  In source not YAML:   #{in_source_only.size}  (YAML missing entries)"
puts "  In YAML not source:   #{in_yaml_only.size}  (YAML has extra / source missed)"
puts
puts "Discrepancies on shared concepts:"
puts "  Designation mismatches:       #{designation_mismatches.size}  (severe: #{report['summary']['designation_severe']}, moderate: #{report['summary']['designation_moderate']}, minor: #{report['summary']['designation_minor']})"
puts "  Definition mismatches:        #{definition_mismatches.size}  (severe: #{report['summary']['definition_severe']}, moderate: #{report['summary']['definition_moderate']}, minor: #{report['summary']['definition_minor']})"
puts "  Reference mismatches:         #{reference_mismatches.size}"
puts "  Math divergence:              #{math_divergence.size}"
puts "    yaml_has_math_source_plain: #{math_divergence.count { |m| m['kind'] == 'yaml_has_math_source_plain' }}"
puts "    source_has_artifacts_yaml_plain: #{math_divergence.count { |m| m['kind'] == 'source_has_artifacts_yaml_plain' }}"
puts "  Missing definition in YAML:   #{missing_definition_in_yaml.size}  (source has DF, YAML empty)"
puts "  Missing definition in source: #{missing_definition_in_source.size}  (YAML has def, source empty)"
puts "  Multi-source concepts:        #{multi_source_review.size}  (review a/b splits)"
puts
puts "Full report: #{options[:out_path]}"
