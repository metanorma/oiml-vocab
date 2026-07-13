#!/usr/bin/env ruby
# frozen_string_literal: true

# Compare the parsed DOCX (parsed.json) against the current g18-202X YAML dataset.
# Handles two-level references:
#   (a) G18 source: the OIML publication where the term appears in G18 (e.g. OIML R 142-1:2025)
#       Stored in the concept metadata (first YAML doc) sources[0]
#   (b) Original source: where G18 adopted the concept from (e.g. OIML V 2-200:2007 / VIM)
#       Stored in the localized concept (second YAML doc) sources
#
# READ-ONLY on datasets/.

require "json"
require "yaml"
require "set"
require "optparse"
require "fileutils"

repo_root = File.expand_path("..", __dir__)
options = {
  parsed_path: File.join(repo_root, "reference-docs", "g018-202x", "parsed.json"),
  concepts_dir: File.join(repo_root, "datasets", "g18-202X", "concepts"),
  out_path: File.join(repo_root, "reference-docs", "g018-202x", "audit.json"),
}
OptionParser.new { |opts|
  opts.banner = "Usage: #{$PROGRAM_NAME} [options]"
  opts.on("--parsed PATH") { |v| options[:parsed_path] = v }
  opts.on("--concepts PATH") { |v| options[:concepts_dir] = v }
  opts.on("--out PATH") { |v| options[:out_path] = v }
}.parse!

parsed = JSON.parse(File.read(options[:parsed_path]))

# Publications that are "original sources" (VIM, VIML, ISO/IEC guides, etc.)
# These belong in the localized concept's sources, NOT the G18 metadata sources.
ORIGINAL_SOURCE_PREFIXES = %w[OIML V ISO IEC BIPM].freeze

def original_source?(pub)
  return false unless pub
  pub.start_with?("OIML V ", "OIML V1", "OIML V2", "ISO", "IEC", "BIPM")
end

# --- Load YAML concepts, merging sources from BOTH documents ---
def load_yaml(dir)
  by_id = {}
  Dir.glob(File.join(dir, "*.yaml")).each do |file|
    docs = YAML.safe_load_stream(File.read(file), filename: file, aliases: true)
    meta = docs.find { |d| d && d.is_a?(Hash) && d.dig("data", "identifier") }
    loc = docs.find { |d| d && d.is_a?(Hash) && (d.dig("data", "definition") || d.dig("data", "terms")) }
    next unless meta
    id = meta.dig("data", "identifier").to_s
    base = id.sub(/[a-z]\z/, "")

    # Sources from BOTH documents
    meta_sources = meta.dig("data", "sources") || []
    loc_sources = (loc && loc.dig("data", "sources")) || []
    all_sources = meta_sources + loc_sources

    # G18 source = first non-original source in metadata
    g18_source = meta_sources.find { |s| s["origin"] && s["origin"]["ref"] &&
      !original_source?(s["origin"]["ref"]["source"]) }
    # Original source = any source that's a VIM/VIML/ISO/IEC
    orig_source = all_sources.find { |s| s["origin"] && s["origin"]["ref"] &&
      original_source?(s["origin"]["ref"]["source"]) }

    terms = loc ? (loc.dig("data", "terms") || []) : []
    defs = loc ? (loc.dig("data", "definition") || []) : []
    pref = terms.find { |t| t["normative_status"] == "preferred" } || terms.first

    by_id[base] ||= []
    by_id[base] << {
      "id" => id,
      "file" => file,
      "designation" => pref ? pref["designation"] : nil,
      "all_terms" => terms,
      "definition" => defs.map { |d| d["content"] if d.is_a?(Hash) }.compact.join(" "),
      "definition_paragraphs" => defs.map { |d| d["content"] if d.is_a?(Hash) }.compact,
      "g18_source_pub" => g18_source && g18_source.dig("origin", "ref", "source"),
      "g18_source_clause" => g18_source && g18_source.dig("locality", "reference_from"),
      "orig_source_pub" => orig_source && orig_source.dig("origin", "ref", "source"),
      "orig_source_clause" => orig_source && orig_source.dig("locality", "reference_from"),
      "has_any_source" => !all_sources.empty?,
    }
  end
  by_id
end

yaml = load_yaml(options[:concepts_dir])
docx_ids = parsed.keys.to_set
yaml_ids = yaml.keys.to_set
both = docx_ids & yaml_ids

def normalize_pub(s)
  s.to_s.sub(/\AOIML\s+/, "").sub(/\A([A-Z])\s*0*(\d+)/, '\1 \2').sub(/V\s*2-200/, "V 2-200")
end

def yaml_has_math?(entry)
  entry["all_terms"].any? { |t| t["designation"].to_s.include?("stem:[") } ||
    entry["definition"].include?("stem:[") || entry["definition"].include?("<math")
end

# --- Compare ---
truly_missing_ref = []    # No source at all in YAML
g18_source_missing = []   # Has some source but missing the G18-level source
g18_source_differs = []   # Has G18 source but it differs from DOCX
two_level_correct = []    # YAML has original source, DOCX has G18 source (both OK)
missing_math = []
desig_diff = []

both.sort.each do |cid|
  docx_rec = parsed[cid]
  docx_rec = docx_rec.is_a?(Array) ? docx_rec.first : docx_rec
  yaml_entries = yaml[cid]
  yaml_entry = yaml_entries.find { |y| y["id"] !~ /[a-z]\z/ } || yaml_entries.first

  docx_ref = docx_rec["reference_parsed"]

  if docx_ref
    if !yaml_entry["has_any_source"]
      truly_missing_ref << { "id" => cid, "docx_ref" => "#{docx_ref['pub_canonical']} #{docx_ref['clause']}" }
    elsif !yaml_entry["g18_source_pub"]
      # Has some source but no G18 source — might have original source only
      g18_source_missing << {
        "id" => cid,
        "yaml_orig" => "#{yaml_entry['orig_source_pub']} #{yaml_entry['orig_source_clause']}",
        "docx_g18" => "#{docx_ref['pub_canonical']} #{docx_ref['clause']}",
      }
    else
      # Compare G18 source
      ypub = normalize_pub(yaml_entry["g18_source_pub"].to_s)
      dpub = normalize_pub(docx_ref["pub_canonical"])
      if ypub != dpub || yaml_entry["g18_source_clause"].to_s != docx_ref["clause"].to_s
        g18_source_differs << {
          "id" => cid,
          "yaml_g18" => "#{yaml_entry['g18_source_pub']} #{yaml_entry['g18_source_clause']}",
          "docx_g18" => "#{docx_ref['pub_canonical']} #{docx_ref['clause']}",
          "yaml_orig" => yaml_entry["orig_source_pub"] ? "#{yaml_entry['orig_source_pub']} #{yaml_entry['orig_source_clause']}" : nil,
        }
      end
    end
  end

  # Math
  docx_has_math = docx_rec["has_math"]
  yml_has_math = yaml_has_math?(yaml_entry)
  if docx_has_math && !yml_has_math
    missing_math << {
      "id" => cid,
      "math_types" => docx_rec["math_types"],
      "docx_designation" => docx_rec["designation"],
      "yaml_designation" => yaml_entry["designation"],
      "docx_def" => docx_rec["definition_paragraphs"]&.first&.[](0..120),
      "yaml_def" => yaml_entry["definition"][0..120],
    }
  end
end

# --- Report ---
report = {
  "summary" => {
    "docx_concept_ids" => docx_ids.size,
    "yaml_concept_ids" => yaml_ids.size,
    "shared" => both.size,
    "in_docx_not_yaml" => (docx_ids - yaml_ids).size,
    "in_yaml_not_docx" => (yaml_ids - docx_ids).size,
    "truly_missing_ref" => truly_missing_ref.size,
    "g18_source_missing" => g18_source_missing.size,
    "g18_source_differs" => g18_source_differs.size,
    "missing_math" => missing_math.size,
  },
  "in_docx_not_yaml" => (docx_ids - yaml_ids).sort,
  "in_yaml_not_docx" => (yaml_ids - docx_ids).sort,
  "truly_missing_ref" => truly_missing_ref,
  "g18_source_missing" => g18_source_missing,
  "g18_source_differs" => g18_source_differs,
  "missing_math" => missing_math,
}

FileUtils.mkdir_p(File.dirname(options[:out_path]))
File.write(options[:out_path], JSON.pretty_generate(report))

puts "G18 202X DOCX vs YAML audit (fixed: checks both YAML documents)"
puts "  DOCX concept IDs:     #{docx_ids.size}"
puts "  YAML concept IDs:     #{yaml_ids.size}"
puts "  Shared:               #{both.size}"
puts
puts "Coverage:"
puts "  In DOCX not YAML:     #{(docx_ids - yaml_ids).size}"
puts "  In YAML not DOCX:     #{(yaml_ids - docx_ids).size}"
puts
puts "References:"
puts "  Truly missing (no source at all):        #{truly_missing_ref.size}"
puts "  G18 source missing (has original only):  #{g18_source_missing.size}"
puts "  G18 source differs from DOCX:            #{g18_source_differs.size}"
puts
puts "Math:"
puts "  Missing math (DOCX has, YAML doesn't):   #{missing_math.size}"
puts
puts "Full report: #{options[:out_path]}"
