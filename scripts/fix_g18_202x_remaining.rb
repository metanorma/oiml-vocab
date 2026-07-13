#!/usr/bin/env ruby
# frozen_string_literal: true

# Complete the g18-202X YAML fixes:
#   1. Add missing references (27 concepts)
#   2. Fix remaining designation math (abbreviations, inline, qualifiers)
#   3. Update definitions with stem:[] math and paragraph preservation (|- block scalar)
#
# Uses surgical text editing (NOT YAML.dump) to preserve formatting.

require "json"

repo_root = File.expand_path("..", __dir__)
parsed = JSON.parse(File.read(File.join(repo_root, "reference-docs", "g018-202x", "parsed.json")))
audit = JSON.parse(File.read(File.join(repo_root, "reference-docs", "g018-202x", "audit.json")))
concepts_dir = File.join(repo_root, "datasets", "g18-202X", "concepts")

stats = { ref_added: 0, abbrev_added: 0, desig_inline: 0, desig_qualifier: 0,
          def_updated: 0, skipped: 0 }

def find_yaml(concepts_dir, cid)
  path = File.join(concepts_dir, "#{cid}.yaml")
  File.exist?(path) ? path : nil
end

def quote_if_needed(s)
  s =~ /[:#{}\[\],&*?|<>=%!@]/ ? "'#{s.gsub("'", "''")}'" : s
end

# Parse the DOCX reference string, handling common artifacts:
# "OIML R 51-1:2006 T.1.7of" -> pub=OIML R 51-1:2006, clause=T.1.7
# "OIML R 76-1:2006 of" -> pub only, no clause
# "OIML R 21:2007 of" -> pub only
def parse_docx_ref(raw)
  return nil unless raw
  # Extract pub: "OIML TYPE NUM:YEAR"
  if raw =~ /(OIML\s+([A-Z])\s*(\d+(?:-\d+)?):(\d{4}))/
    pub = $1
    type = $2
    num = $3
    year = $4
    # Extract clause: everything after the year, cleaned up
    remainder = raw.sub(/.*#{Regexp.escape(pub)}/, "").strip
    # Remove leading/trailing "of", "o0f", commas, spaces
    remainder = remainder.sub(/\A[of,\s]+/i, "").sub(/[of,\s]+\z/i, "").strip
    clause = remainder.empty? ? nil : remainder
    { pub: pub, clause: clause }
  end
end

# Convert an array of paragraph strings into a |- block scalar content
# Each paragraph on its own line, separated by blank lines
def make_block_content(paragraphs)
  lines = paragraphs.map do |para|
    # Each paragraph may be multi-word; indent continuation lines
    # For now, put each paragraph on one line (wrapping handled by YAML)
    para
  end
  lines.join("\n\n")
end

# --- Task 1: Add missing references ---
puts "=== Task 1: Adding missing references ==="
audit["truly_missing_ref"].each do |m|
  cid = m["id"]
  path = find_yaml(concepts_dir, cid)
  unless path
    stats[:skipped] += 1
    next
  end

  ref = parse_docx_ref(m["docx_ref"])
  unless ref
    stats[:skipped] += 1
    next
  end

  content = File.read(path)

  # Check if the first document already has sources
  # The first document ends at the first "---" separator
  first_doc = content.split(/^---/, 3)[1] || ""

  if first_doc =~ /^\s*sources:/
    stats[:skipped] += 1
    next
  end

  # Build the sources block
  source_lines = [
    "  sources:",
    "  - origin:",
    "      ref:",
    "        source: #{ref[:pub]}",
  ]
  if ref[:clause]
    source_lines += [
      "    locality:",
      "      type: clause",
      "      reference_from: '#{ref[:clause]}'",
    ]
  end
  source_lines << "    type: authoritative"
  source_yaml = source_lines.join("\n")

  # Insert before "status:" in the first document
  if content =~ /^status:/
    content.sub!(/^status:/, "#{source_yaml}\nstatus:")
    File.write(path, content)
    stats[:ref_added] += 1
  else
    stats[:skipped] += 1
  end
end
puts "  References added: #{stats[:ref_added]}, skipped: #{stats[:skipped]}"

# --- Task 2: Fix remaining designation math ---
puts "\n=== Task 2: Fixing remaining designation math ==="
stats2 = { abbrev: 0, inline: 0, qualifier: 0, skipped: 0 }

audit["missing_math"].each do |m|
  cid = m["id"]
  docx_desig = m["docx_designation"]
  yaml_desig = m["yaml_designation"]

  next if docx_desig == yaml_desig  # definition-only math, handled in task 3
  next if docx_desig =~ /\b(\w+)\s+\1\b/ && docx_desig !~ /stem:\[/  # DOCX artifact

  path = find_yaml(concepts_dir, cid)
  unless path
    stats2[:skipped] += 1
    next
  end

  content = File.read(path)
  modified = false

  # Case: Missing abbreviation (WME, CGM, STS, SCF)
  if docx_desig =~ /\(([A-Z]{2,5})\)/ && yaml_desig !~ /\([A-Z]{2,5}\)/
    abbrev = docx_desig.match(/\(([A-Z]{2,5})\)/)[1]
    # Check not already present
    unless content =~ /^  - type: abbreviation/
      abbrev_yml = "  - type: abbreviation\n    normative_status: preferred\n    designation: #{abbrev}"
      content.sub!(/^language_code: /, "#{abbrev_yml}\nlanguage_code: ")
      # Update designation to include abbreviation
      new_desig = "#{yaml_desig} (#{abbrev})"
      content.sub!(/designation:\s+#{Regexp.escape(yaml_desig)}/) do
        "designation: #{quote_if_needed(new_desig)}"
      end
      modified = true
      stats2[:abbrev] += 1
    end
  # Case: Missing qualifier in parentheses (e.g., "indicated value (of a quantity)")
  elsif docx_desig =~ /^(.+?)\s+\(([^)]+)\)/ && yaml_desig == $1
    # Update designation to include the qualifier
    content.sub!(/designation:\s+#{Regexp.escape(yaml_desig)}/) do
      "designation: #{quote_if_needed(docx_desig)}"
    end
    modified = true
    stats2[:qualifier] += 1
  # Case: Inline math in designation (stem:[] already in docx_desig)
  elsif docx_desig =~ /stem:\[/
    content.sub!(/designation:\s+#{Regexp.escape(yaml_desig)}/) do
      "designation: '#{docx_desig}'"
    end
    modified = true
    stats2[:inline] += 1
  else
    stats2[:skipped] += 1
  end

  File.write(path, content) if modified
end
stats[:abbrev_added] = stats2[:abbrev]
stats[:desig_inline] = stats2[:inline]
stats[:desig_qualifier] = stats2[:qualifier]
stats[:skipped] += stats2[:skipped]
puts "  Abbreviations: #{stats2[:abbrev]}, Qualifiers: #{stats2[:qualifier]}, Inline: #{stats2[:inline]}, Skipped: #{stats2[:skipped]}"

# --- Task 3: Update definitions with math and paragraph preservation ---
puts "\n=== Task 3: Updating definitions with stem:[] and paragraph structure ==="

audit["missing_math"].each do |m|
  cid = m["id"]
  path = find_yaml(concepts_dir, cid)
  unless path
    next
  end

  rec = parsed[cid]
  next unless rec && rec["definition_paragraphs"]&.any?

  # Only update if the DOCX definition has stem:[] math
  docx_def_has_stem = rec["definition_paragraphs"].any? { |p| p.include?("stem:[") }
  next unless docx_def_has_stem

  content = File.read(path)

  # Find the definition content in the second YAML document
  # Pattern: "  definition:\n  - content: '...'" (possibly multi-line quoted)
  # We need to replace the old content with a |- block scalar

  # Find the definition block in the localized concept (second document)
  # Look for "  definition:\n  - content:" pattern
  def_pattern = /  definition:\n  - content: /

  if content =~ def_pattern
    # Find the start and end of the content value
    match = $~
    start_pos = match.end(0) # position right after "content: "

    # Determine the end of the content value
    # It could be:
    # 1. A single-quoted string ending with ' on the same or next line
    # 2. A plain scalar ending at the next key
    rest = content[start_pos..]

    # Find the end: next line starting with "  " + a key name (like "  examples:", "  id:", etc.)
    # or end of quoted string
    end_pos = nil
    if rest.start_with?("'")
      # Single-quoted: find closing ' (may span lines)
      # This is tricky with multi-line quotes; use a heuristic:
      # find the next "  examples:" or "  id:" line
      if rest =~ /\n  (examples|id|notes|sources|terms|language_code|entry_status):/
        content_end = $~.begin(0)
        end_pos = start_pos + content_end
      end
    else
      # Plain or double-quoted
      if rest =~ /\n  (examples|id|notes|sources|terms|language_code|entry_status):/
        content_end = $~.begin(0)
        end_pos = start_pos + content_end
      end
    end

    next unless end_pos

    # Build new content using |- block scalar (preserve 2-space indent under data:)
    new_def_text = "  definition:\n  - content: |-"
    docx_paragraphs = rec["definition_paragraphs"]
    docx_paragraphs.each do |para|
      new_def_text += "\n      #{para}"
      new_def_text += "\n" unless para == docx_paragraphs.last
    end

    # Replace the old definition content
    old_block = content[match.begin(0)...end_pos]
    content[match.begin(0)...end_pos] = new_def_text

    File.write(path, content)
    stats[:def_updated] += 1
  end
end
puts "  Definitions updated: #{stats[:def_updated]}"

puts "\n=== Total stats ==="
puts "  References added:     #{stats[:ref_added]}"
puts "  Abbreviations added:  #{stats[:abbrev_added]}"
puts "  Qualifiers added:     #{stats[:desig_qualifier]}"
puts "  Inline math fixed:    #{stats[:desig_inline]}"
puts "  Definitions updated:  #{stats[:def_updated]}"
puts "  Skipped:              #{stats[:skipped]}"
