#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Verifies that VIM 1993's `supersedes` edges to V 2:1984/Cor.1:1987 point to
# concepts with matching (or closely related) preferred designations.
#
# Reports each pair with: match status, both designations.
#
#   ruby scripts/historical/verify_vim_1993_corrigendum_designations.rb

require "yaml"

REPO = File.expand_path("../..", __dir__)
VIM_1993 = File.join(REPO, "datasets", "vim-1993", "concepts")
COR_1987 = File.join(REPO, "datasets", "vim-1984-cor-1987", "concepts")
COR_URN = "urn:oiml:pub:v:2:1984:cor:1:1987"

def preferred_eng(path)
  docs = YAML.load_stream(File.read(path))
  eng = docs[1..].find { |d| d["language_code"] == "eng" || d.dig("data", "language_code") == "eng" }
  return nil unless eng
  terms = eng.dig("data", "terms") || []
  pref = terms.find { |t| t["normative_status"] == "preferred" }
  pref ? pref["designation"] : nil
end

def superseded_target(content)
  docs = YAML.load_stream(content)
  managed = docs.first
  return nil unless managed.is_a?(Hash)
  (managed["related"] || []).each do |r|
    next unless r.is_a?(Hash) && r["type"] == "supersedes"
    ref = r["ref"] || {}
    return ref["id"] if ref["source"] == COR_URN
  end
  nil
end

matches = 0
mismatches = 0
missing = 0
missing_targets = []

Dir.glob(File.join(VIM_1993, "*.yaml")).sort.each do |path|
  basename = File.basename(path)
  content = File.read(path)
  target_id = superseded_target(content)
  next unless target_id

  target_path = File.join(COR_1987, "#{target_id}.yaml")
  unless File.exist?(target_path)
    missing += 1
    missing_targets << "#{basename} -> #{target_id} (no file)"
    next
  end

  vim1993_desig = preferred_eng(path)
  cor1987_desig = preferred_eng(target_path)

  if vim1993_desig.nil? || cor1987_desig.nil?
    $stderr.puts "#{basename} -> #{target_id}: missing designation"
    next
  end

  # "Same/similar" check: case-insensitive substring match either way, OR
  # exact match. Loose comparison because VIM 1993 sometimes rephrased slightly.
  a = vim1993_desig.downcase
  b = cor1987_desig.downcase
  same = (a == b) || a.include?(b) || b.include?(a) ||
         a.split.first(2).join(" ") == b.split.first(2).join(" ")

  if same
    matches += 1
  else
    mismatches += 1
    puts "MISMATCH: vim-1993/#{basename} '#{vim1993_desig}' -> cor-1987/#{target_id} '#{cor1987_desig}'"
  end
end

puts ""
puts "Results:"
puts "  matches:    #{matches}"
puts "  mismatches: #{mismatches}"
puts "  missing target files: #{missing}"
missing_targets.each { |t| puts "    #{t}" }
