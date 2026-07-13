#!/usr/bin/env ruby
# frozen_string_literal: true

# Fix g18-202X YAML concepts based on the DOCX parse:
#   1. Extract trailing symbols from designations -> add as type: symbol terms
#   2. Add missing abbreviations -> type: abbreviation terms
#   3. Fix inline math in designations
#
# Uses surgical text editing (NOT YAML.dump) to preserve formatting.
# Symbol terms are inserted AFTER the last term entry, BEFORE the top-level
# language_code (0-space indent) in the second YAML document.

require "json"

repo_root = File.expand_path("..", __dir__)
parsed = JSON.parse(File.read(File.join(repo_root, "reference-docs", "g018-202x", "parsed.json")))
audit = JSON.parse(File.read(File.join(repo_root, "reference-docs", "g018-202x", "audit.json")))
concepts_dir = File.join(repo_root, "datasets", "g18-202X", "concepts")

stats = { symbol_extracted: 0, abbreviation_added: 0, inline_math: 0, skipped: 0 }

def find_yaml(concepts_dir, cid)
  path = File.join(concepts_dir, "#{cid}.yaml")
  return path if File.exist?(path)
  nil
end

def extract_trailing_symbol(docx_desig)
  m = docx_desig.match(/(.+?)\s*[(,]?\s*(stem:\[[^\]]+\](?:\s*(?:and|or)\s*stem:\[[^\]]+\])*)\s*\)?\s*\z/)
  return nil unless m
  clean = m[1].strip
  symbols_str = m[2]
  symbols = symbols_str.split(/\s+(?:and|or)\s+/).map(&:strip)
  { clean_designation: clean, symbols: symbols }
end

def quote_if_needed(s)
  # Quote if contains YAML-special chars
  s =~ /[:#{}\[\],&*?|<>=%!@]/ ? "'#{s.gsub("'", "''")}'" : s
end

audit["missing_math"].each do |m|
  cid = m["id"]
  docx_desig = m["docx_designation"]
  yaml_desig = m["yaml_designation"]

  next if docx_desig == yaml_desig  # math only in definition, not designation

  # Skip DOCX artifacts (duplicated words, garbled text)
  if docx_desig =~ /\b(\w+)\s+\1\b/ && docx_desig !~ /stem:\[/
    stats[:skipped] += 1
    next
  end

  path = find_yaml(concepts_dir, cid)
  unless path
    stats[:skipped] += 1
    next
  end

  content = File.read(path)
  modified = false

  # Case 1: Trailing symbol (e.g., ", stem:[d_{t}]" or " (stem:[p_{LC}])")
  if docx_desig =~ /stem:\[/ && docx_desig =~ /[,(\s]\s*stem:\[/
    extracted = extract_trailing_symbol(docx_desig)
    if extracted && extracted[:clean_designation] != yaml_desig
      clean_desig = extracted[:clean_designation]

      # Update designation: replace yaml_desig with clean_desig
      # The YAML designation might be quoted or unquoted
      desig_re = /designation:\s+['"]?#{Regexp.escape(yaml_desig)}['"]?/
      if content =~ desig_re
        content.sub!(desig_re, "designation: #{quote_if_needed(clean_desig)}")
        modified = true
      end

      # Insert symbol terms AFTER the last term entry, BEFORE top-level language_code
      symbol_yml_lines = extracted[:symbols].map do |sym|
        "  - type: symbol\n    normative_status: preferred\n    designation: #{sym}\n    international: true"
      end

      # Insert before the top-level language_code (0-space indent, in 2nd doc)
      insert_before = /^language_code: /
      if content =~ insert_before
        symbol_yml_lines.each do |sym_yml|
          content.sub!(insert_before, "#{sym_yml}\nlanguage_code: ")
        end
        modified = true
      end

      stats[:symbol_extracted] += 1 if modified
    end

  # Case 2: Missing abbreviation (e.g., "(WME)", "(CGM)")
  elsif docx_desig =~ /\(([A-Z]{2,5})\)/ && yaml_desig !~ /\([A-Z]{2,5}\)/
    abbrev = docx_desig.match(/\(([A-Z]{2,5})\)/)[1]
    unless content =~ /designation: ['"]?#{abbrev}['"]?/
      abbrev_yml = "  - type: abbreviation\n    normative_status: preferred\n    designation: #{abbrev}"
      insert_before = /^language_code: /
      if content =~ insert_before
        content.sub!(insert_before, "#{abbrev_yml}\nlanguage_code: ")
        # Also update the designation to include the abbreviation
        desig_re = /designation:\s+(['"]?)#{Regexp.escape(yaml_desig)}(['"]?)/
        new_desig = "#{yaml_desig} (#{abbrev})"
        content.sub!(desig_re, "designation: #{quote_if_needed(new_desig)}")
        modified = true
        stats[:abbreviation_added] += 1
      end
    end

  # Case 3: Inline math at start (e.g., "stem:[T_{1}] error")
  elsif docx_desig =~ /^stem:\[/
    desig_re = /designation:\s+['"]?#{Regexp.escape(yaml_desig)}['"]?/
    if content =~ desig_re
      content.sub!(desig_re, "designation: '#{docx_desig}'")
      modified = true
      stats[:inline_math] += 1
    end
  else
    stats[:skipped] += 1
  end

  File.write(path, content) if modified
end

puts "Designation math fixes:"
puts "  Symbols extracted:   #{stats[:symbol_extracted]}"
puts "  Abbreviations added: #{stats[:abbreviation_added]}"
puts "  Inline math fixed:   #{stats[:inline_math]}"
puts "  Skipped:             #{stats[:skipped]}"
