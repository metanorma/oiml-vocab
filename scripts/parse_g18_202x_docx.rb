#!/usr/bin/env ruby
# frozen_string_literal: true

# Parse the OIML G 18 Edition 202X (2CD) DOCX to extract the complete vocabulary
# with math (OMML + inline sub/sup) converted to stem:[] notation.
#
# Uses Nokogiri for fast XML parsing of word/document.xml (extracted from the DOCX),
# and Plurimath for OMML -> LaTeX conversion (same engine as the uniword gem).
#
# Each cell is parsed independently (number, term, reference, definition, notes, ID).
# Paragraph structure is preserved (each <w:p> becomes a separate paragraph).
# Inline sub/sup runs are combined with their base into stem:[base_{sub}].
# OMML equations are converted to stem:[latex] via Plurimath.
#
# Output: reference-docs/g018-202x/parsed.json
#
# READ-ONLY on datasets/. This does not modify the canonical YAML.

require "nokogiri"
require "json"
require "fileutils"
require "optparse"

repo_root = File.expand_path("..", __dir__)
options = {
  xml_path: "/tmp/g18-202x/document.xml",
  out_path: File.join(repo_root, "reference-docs", "g018-202x", "parsed.json"),
}
OptionParser.new do |opts|
  opts.banner = "Usage: #{$PROGRAM_NAME} [options]"
  opts.on("--xml PATH", String) { |v| options[:xml_path] = v }
  opts.on("--out PATH", String) { |v| options[:out_path] = v }
  opts.on("-h", "--help") { puts opts; exit 0 }
end.parse!

abort "XML not found: #{options[:xml_path]}" unless File.exist?(options[:xml_path])

W = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
M = "http://schemas.openxmlformats.org/officeDocument/2006/math"

# Load Plurimath for OMML -> LaTeX conversion
require "plurimath"

# --- Cell content extraction ----------------------------------------------

# Extract all text from a run element, including <w:t> and <w:tab> elements.
# Returns the text content as a string with non-breaking spaces normalized.
def run_text(run_node)
  texts = run_node.xpath("./w:t", w: W)
  texts.map(&:content).join
end

# Normalize Word artifacts: non-breaking spaces, zero-width spaces.
def normalize_ws(s)
  s.to_s.tr("\u00A0\u2007\u202F\u2060", "   ").gsub(/\u200B/, "")
end

# Check if a run has subscript or superscript vertical alignment.
# Returns nil, "subscript", or "superscript".
# Uses local-name() for namespace-robust matching.
def run_vert_align(run_node)
  va = run_node.at_xpath(".//*[local-name()='vertAlign']")
  return nil unless va
  va["val"] || va.attribute_with_ns("val", W)&.value
end

# Check if a run is italic
def run_italic?(run_node)
  !run_node.at_xpath(".//*[local-name()='i' and namespace-uri()='#{W}']").nil?
end

# Convert an OMML element to stem:[asciimath] using Plurimath.
# Strips Word namespace elements (w:rPr, w:br, etc.) from the OMML first,
# because Plurimath cannot parse OMML containing mixed-namespace Word elements
# (a known Plurimath limitation — see bug report in plurimath repo).
# Returns nil if conversion fails.
def omml_to_stem(omml_node)
  # Strip all w:* elements from a copy of the node
  clean = omml_node.dup
  clean.xpath(".//w:*", w: W).each { |n| n.remove }
  omml_xml = clean.to_xml
  begin
    formula = Plurimath::Math.parse(omml_xml, :omml)
    asciimath = formula.to_asciimath.to_s.strip
    return nil if asciimath.empty?
    # Normalize to match the dataset's stem:[] convention:
    #   Remove quotes around short identifiers: "Q" -> Q
    asciimath = asciimath.gsub(/"([^"]{1,4})"/, '\1')
    #   Use curly braces for grouped sub/superscripts: _(max) -> _{max}
    asciimath = asciimath.gsub(/_\(([^)]+)\)/, '_{\1}')
    asciimath = asciimath.gsub(/\^\(([^)]+)\)/, '^{\1}')
    #   Clean up empty group artifacts
    asciimath = asciimath.gsub(/\{\s*\}/, "")
    "stem:[#{asciimath}]"
  rescue StandardError => e
    warn "  OMML conversion failed: #{e.class}: #{e.message[0..100]}"
    nil
  end
end

# Extract text from a paragraph, converting sub/sup to stem:[] and OMML to stem:[].
# Returns an array of "segments" — each is either a string (text) or a stem block.
# Adjacent segments are joined naturally.
def paragraph_to_asciidoc(para_node)
  segments = []

  # Iterate over all children: runs (w:r) and math (m:oMath) in document order
  para_node.children.each do |child|
    case child.name
    when "r"
      # Word run
      namespace = child.namespace&.href
      next unless namespace == W

      text = run_text(child)
      next if text.empty?

      vert = run_vert_align(child)

      if vert == "subscript"
        segments << { type: :sub, text: text }
      elsif vert == "superscript"
        segments << { type: :sup, text: text }
      else
        segments << { type: :text, text: text }
      end
    when "oMath"
      # OMML math element
      namespace = child.namespace&.href
      next unless namespace == M
      stem = omml_to_stem(child)
      segments << { type: :math, text: stem } if stem
    when "oMathPara"
      # Block-level math paragraph (contains one or more oMath)
      child.xpath("./m:oMath", m: M).each do |om|
        stem = omml_to_stem(om)
        segments << { type: :math, text: stem } if stem
      end
    end
  end

  # Now merge segments: combine text + sub/sup into stem:[] blocks
  # Strategy: collect consecutive segments. When we hit sub/sup, look back
  # for the last text segment as the "base" and produce stem:[base_{sub}].
  result = []
  buffer = [] # accumulates plain text

  i = 0
  while i < segments.size
    seg = segments[i]

    if seg[:type] == :text
      buffer << seg[:text]
      i += 1
    elsif seg[:type] == :sub || seg[:type] == :sup
      # Look back: merge buffer into result, keeping the last token as base
      if buffer.any?
        # Pop the last "token" (word/letter) from buffer as the base
        # Join buffer text, then split at the last boundary
        buf_text = buffer.join
        buffer = []

        # Find the last "base" — typically the last character or parenthesized group
        # For simplicity: take everything up to the last alphanumeric/paren group as text,
        # and the last group as the base for the subscript/superscript
        if buf_text =~ /(.*?)([\p{L}\p{N}\)]+)(\s*)\z/
          prefix = $1
          base = $2
          trailing = $3
          result << prefix if prefix && !prefix.empty?
          op = seg[:type] == :sub ? "_" : "^"
          result << "stem:[#{base}#{op}{#{seg[:text]}}]"
          result << trailing if trailing && !trailing.empty?
        else
          # No clear base; just append as-is
          op = seg[:type] == :sub ? "_" : "^"
          result << buf_text
          result << "stem:[#{op}{#{seg[:text]}}]"
        end
      else
        # No preceding text; standalone sub/sup
        op = seg[:type] == :sub ? "_" : "^"
        result << "stem:[#{op}{#{seg[:text]}}]"
      end
      i += 1

      # Check if the NEXT segment is also sub/sup (e.g., F1, F2, Fa, Fb sequence)
      # If so, we need to continue the pattern. For now, just process one at a time.
    elsif seg[:type] == :math
      # Flush buffer
      if buffer.any?
        result << buffer.join
        buffer = []
      end
      result << seg[:text]
      i += 1
    else
      i += 1
    end
  end

  # Flush remaining buffer
  result << buffer.join if buffer.any?

  joined = result.join
  # Remove empty stem blocks: stem:[], stem:[ ], stem:[_{}], stem:[{}]
  joined.gsub(/stem:\[\s*\]/, "")
        .gsub(/stem:\[\s*_\{\s*\}\s*\]/, "")
        .gsub(/stem:\[\s*\{\s*\}\s*\]/, "")
        .gsub(/\[\s*\]/, "")
end

# Extract paragraphs from a table cell, preserving paragraph breaks.
# Returns an array of paragraph strings (one per <w:p>).
def cell_paragraphs(cell_node)
  paras = cell_node.xpath("./w:p", w: W)
  paras.map { |p| normalize_ws(paragraph_to_asciidoc(p)).strip }.select { |s| !s.empty? }
end

# --- Reference parsing ----------------------------------------------------

# Match "according to CLAUSE of PUB" where PUB is like "R 137:2012" or "D 31:2023".
# Tolerates: missing "of", missing colon (R 76-1 2006), suffixes (Reconfirmed 2022,
# - Annexes), and extra trailing text.
REF_RE = /\Aaccording to\s+(.+?)\s+(?:of\s+)?([A-Z])\s*(\d+(?:-\d+)?)\s*[:]\s*(\d{4})(.*)\z/i
REF_RE_NOCOLON = /\Aaccording to\s+(.+?)\s+(?:of\s+)?([A-Z])\s*(\d+(?:-\d+)?)\s+(\d{4})(.*)\z/i

def parse_reference(text)
  text = text.strip
  m = text.match(REF_RE) || text.match(REF_RE_NOCOLON)
  return nil unless m
  clause = m[1].strip
  pub_type = m[2]
  pub_number = m[3]
  pub_year = m[4]
  suffix = m[5].to_s.strip.sub(/\A[-,]\s*/, "").strip
  {
    "clause" => clause,
    "pub_type" => pub_type,
    "pub_number" => pub_number,
    "pub_year" => pub_year,
    "pub_canonical" => "OIML #{pub_type} #{pub_number}:#{pub_year}",
    "suffix" => (suffix unless suffix.empty?),
    "raw" => text,
  }
end

# --- Main -----------------------------------------------------------------

puts "Parsing #{options[:xml_path]}..."
doc = Nokogiri::XML(File.read(options[:xml_path]))
puts "  XML loaded (#{File.size(options[:xml_path]) / 1024} KB)"

tables = doc.xpath("//w:tbl", w: W)
puts "  Tables: #{tables.size}"

# Find data tables: rows with 6 cells where the last cell has a 5-digit ID
all_records = []
total_rows = 0

tables.each_with_index do |tbl, ti|
  rows = tbl.xpath("./w:tr", w: W)
  rows.each do |row|
    cells = row.xpath("./w:tc", w: W)
    next unless cells.size >= 5

    # Cell 5 (or last cell) should have a 5-digit ID
    id_cell = cells[5] || cells.last
    id_paras = cell_paragraphs(id_cell)
    id_text = id_paras.first.to_s.strip
    next unless id_text =~ /\A\d{5}\z/

    total_rows += 1
    concept_id = id_text

    # Cell 0: sequence number
    number = cell_paragraphs(cells[0]).first.to_s.strip.sub(/\.\z/, "")

    # Cell 1: term/designation
    term_paras = cells[1] ? cell_paragraphs(cells[1]) : []
    designation = term_paras.join(" ")

    # Cell 2: reference
    ref_paras = cells[2] ? cell_paragraphs(cells[2]) : []
    ref_text = ref_paras.join(" ").gsub(/\s+/, " ").strip
    ref_parsed = parse_reference(ref_text)

    # Cell 3: definition
    def_paras = cells[3] ? cell_paragraphs(cells[3]) : []

    # Cell 4: notes
    notes_paras = cells[4] ? cell_paragraphs(cells[4]) : []

    # Detect math in any cell
    has_sub = row.xpath(".//*[local-name()='vertAlign' and @w:val='subscript']", w: W).any?
    has_sup = row.xpath(".//*[local-name()='vertAlign' and @w:val='superscript']", w: W).any?
    has_omml = row.xpath(".//*[local-name()='oMath']", m: M).any?
    math_types = []
    math_types << "subscript" if has_sub
    math_types << "superscript" if has_sup
    math_types << "omml" if has_omml

    all_records << {
      "concept_id" => concept_id,
      "number" => number,
      "designation" => designation,
      "designation_paragraphs" => term_paras,
      "reference_raw" => ref_text,
      "reference_parsed" => ref_parsed,
      "definition_paragraphs" => def_paras,
      "definition_full" => def_paras.join("\n\n"),
      "notes_paragraphs" => notes_paras,
      "has_math" => math_types.any?,
      "math_types" => math_types,
    }
  end
end

# --- Detect ID collisions: same 5-digit ID with different designations ---
# The G18 2CD reuses concept IDs for different terms from different publications.
# The YAML disambiguates these with composite IDs: "02327-R046-1", "02327-R085-1".
id_designations = {}
all_records.each do |rec|
  cid = rec["concept_id"]
  id_designations[cid] ||= {}
  id_designations[cid][rec["designation"].downcase.strip] = true
end
collision_ids = id_designations.select { |_, desigs| desigs.size > 1 }.keys

# Build publication code for composite IDs (e.g., "R 46-1" -> "R046-1", "D 11" -> "D011")
def build_pub_code(ref_parsed)
  return nil unless ref_parsed
  type = ref_parsed["pub_type"]
  number = ref_parsed["pub_number"]
  if number =~ /^(\d+)(-.*)?$/
    "#{type}#{$1.rjust(3, '0')}#{$2.to_s}"
  else
    "#{type}#{number}"
  end
end

# Assign composite IDs to collision entries
concepts = {}
all_records.each do |rec|
  cid = rec["concept_id"]
  if collision_ids.include?(cid)
    pub_code = build_pub_code(rec["reference_parsed"])
    if pub_code
      composite_id = "#{cid}-#{pub_code}"
      rec["base_concept_id"] = cid
      rec["is_collision_variant"] = true
      concepts[composite_id] = rec
    else
      concepts[cid] = rec
    end
  else
    concepts[cid] = rec
  end
end

puts "  Total data rows: #{total_rows}"
puts "  Unique concept IDs (after disambiguation): #{concepts.size}"
puts "  Collision IDs (same 5-digit, different terms): #{collision_ids.size}"
puts "  Composite-ID entries created: #{concepts.values.count { |r| r["is_collision_variant"] }}"
with_math = concepts.values.count { |v| v["has_math"] }
puts "  Concepts with math: #{with_math}"
with_refs = concepts.values.count { |v| v["reference_parsed"] }
puts "  Concepts with parsed reference: #{with_refs}"

FileUtils.mkdir_p(File.dirname(options[:out_path]))
File.write(options[:out_path], JSON.pretty_generate(concepts))
puts "  Output: #{options[:out_path]}"
