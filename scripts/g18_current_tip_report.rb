#!/usr/bin/env ruby
# frozen_string_literal: true

# V 0 tip-edition report with **cross-language correlation**.
#
# A "concept" is identified by (family, term_number). Multiple language
# editions of the same family with the same term_number count as ONE
# concept, not N. So:
#   r49-1-2013-eng-3.1.1 + r49-1-2013-fra-3.1.1 + r49-1-2013-spa-3.1.1
#   = 1 unique concept ("water meter" in R 49:2013 § 3.1.1)
#
# Tip concepts are unique (family, term_number) pairs that appear in at
# least one pub-code at the family's max year.
#
# Off-tip concepts are unique (family, term_number) pairs that appear
# ONLY in pub-codes below the max year (i.e. superseded).

require "yaml"
require "pathname"
require "set"

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
require "oiml/g18_complete"

module V0TipReport2
  module_function

  def pct(num, total)
    return "0.0" if total.zero?
    (100.0 * num / total).round(1)
  end
end

CONCEPTS = Pathname.new(File.expand_path("../datasets/g18-complete/concepts", __dir__))
SOURCE_ROOT = Pathname.new("/Users/mulgogi/src/oimlsmart/publications/reference-docs/ocr-output")
PUB_CODES = Set.new(SOURCE_ROOT.children.select(&:directory?).map(&:basename).map(&:to_s))

def resolve_pub_code(basename)
  parts = basename.split("-")
  (parts.length - 1).downto(1) do |i|
    candidate = parts[0...i].join("-")
    return candidate if PUB_CODES.include?(candidate)
  end
  nil
end

# Build per-pub info: pub_code -> {year, kind, base_number, langs, term_numbers}
pub_info = Hash.new { |h, k| h[k] = { langs: Set.new, term_numbers: Set.new } }

CONCEPTS.children.each do |f|
  basename = f.basename(".yaml").to_s
  pc = resolve_pub_code(basename)
  next unless pc

  term = basename.delete_prefix("#{pc}-")
  pub_info[pc][:term_numbers] << term

  docs = YAML.load_stream(f.read)
  outer = docs.first
  next unless outer.is_a?(Hash) && outer["data"].is_a?(Hash)

  (outer.dig("data", "localized_concepts") || {}).each_key do |lang|
    pub_info[pc][:langs] << lang
  end

  next if pub_info[pc][:year]

  sources = outer.dig("data", "sources") || []
  src = sources.first || {}
  version = src.dig("origin", "ref", "version")
  year = version ? version.to_i : 0
  pub_info[pc][:year] = year
end

pub_info.each_key do |pc|
  parsed = Oiml::G18Complete::PublicationCode.parse(pc)
  pub_info[pc][:year] = parsed.year if pub_info[pc][:year].to_i.zero?
  base = parsed.number.to_s.split("-").first
  pub_info[pc][:kind] = parsed.kind
  pub_info[pc][:base_number] = base
  pub_info[pc][:family] = "#{parsed.kind} #{base}"
end

# Group pub_codes by family
families = Hash.new { |h, k| h[k] = [] }
pub_info.each_key { |pc| families[pub_info[pc][:family]] << pc }

# Per family, find max year (tip year) and partition pub_codes
tips = {}
families.each do |family, codes|
  max_year = codes.map { |c| pub_info[c][:year] }.max
  tip_codes = codes.select { |c| pub_info[c][:year] == max_year }
  tips[family] = { year: max_year, pub_codes: tip_codes }
end

# For each family, build set of (term_number) at tip vs off-tip
# A concept is "tip" if its term_number appears in any tip pub-code.
# A concept is "off-tip" if its term_number appears ONLY in non-tip pub-codes.
family_tip_terms = {}      # family -> Set of term_numbers at tip
family_offtip_only_terms = {} # family -> Set of term_numbers only off-tip

families.each do |family, codes|
  tip_set = Set.new
  offtip_set = Set.new
  codes.each do |c|
    if pub_info[c][:year] == tips[family][:year]
      pub_info[c][:term_numbers].each { |t| tip_set << t }
    else
      pub_info[c][:term_numbers].each { |t| offtip_set << t }
    end
  end
  family_tip_terms[family] = tip_set
  # off-tip ONLY = appears in offtip_set but NOT in tip_set
  family_offtip_only_terms[family] = offtip_set - tip_set
end

# Aggregate
total_unique = 0
tip_unique = 0
offtip_unique = 0
families.each do |family, _|
  tip_count = family_tip_terms[family].size
  offtip_count = family_offtip_only_terms[family].size
  tip_unique += tip_count
  offtip_unique += offtip_count
  total_unique += tip_count + offtip_count
end

# Also count "files" for comparison
total_files = CONCEPTS.children.select { |f| f.to_s.end_with?(".yaml") }.size

puts "V 0 tip-edition report — cross-language correlated"
puts "=" * 60
puts
puts "Counting method: (family, term_number) is ONE concept."
puts "Multiple language editions of the same term collapse to 1."
puts
puts "Raw YAML files in dataset:        #{total_files}"
puts "Unique concepts (family + term):  #{total_unique}"
puts
puts "Unique tip concepts:    #{tip_unique} (#{V0TipReport2.pct(tip_unique, total_unique)}%)"
puts "Unique off-tip concepts: #{offtip_unique} (#{V0TipReport2.pct(offtip_unique, total_unique)}%)"
puts
puts "Tip concepts also carry language coverage. Counting bilingual+ coverage:"
tip_with_2plus_langs = 0
tip_with_3plus_langs = 0
families.each do |family, codes|
  tip_pubs = tips[family][:pub_codes]
  tip_langs_per_term = Hash.new { |h, k| h[k] = Set.new }
  tip_pubs.each do |pc|
    pub_info[pc][:term_numbers].each do |term|
      # Need to read the file again to get langs per term. Skip for speed —
      # use the union of all langs the pub exposes (approximation).
      tip_langs_per_term[term].merge(pub_info[pc][:langs])
    end
  end
  tip_langs_per_term.each_value do |langs|
    tip_with_2plus_langs += 1 if langs.size >= 2
    tip_with_3plus_langs += 1 if langs.size >= 3
  end
end
puts "  Tip concepts with ≥2 languages: #{tip_with_2plus_langs}"
puts "  Tip concepts with ≥3 languages: #{tip_with_3plus_langs}"
puts
puts "Per-family breakdown (families with off-tip concepts):"
puts "-" * 60
printf "%-10s %-8s %-12s %-12s %-12s\n", "Family", "TipYear", "TipUnique", "OffTipUnique", "TipDirs"

families.sort.each do |family, codes|
  tip = tips[family]
  next if tip[:year].to_i.zero?
  tip_count = family_tip_terms[family].size
  offtip_count = family_offtip_only_terms[family].size
  next if offtip_count.zero? && tip_count.zero?

  tip_dirs = tip[:pub_codes].size
  printf "%-10s %-8d %-12d %-12d %-12d\n", family, tip[:year], tip_count, offtip_count, tip_dirs
end
