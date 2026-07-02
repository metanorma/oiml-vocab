#!/usr/bin/env ruby
# frozen_string_literal: true

# Fix encoding issues in vocab/datasets/g18/concepts/*.yaml based on
# OCR ground truth (reference-docs/g018-2010-ocr/glm-ocr.md).
#
# Applies:
#   1. Trivial substitutions (always safe):
#        - Smart quotes → straight
#        - HTML entities → literal
#        - PUA space/paren/hyphen → ASCII
#   2. PUA math chars → stem:[LaTeX]  (Symbol font artifacts)
#   3. PUA bullet markers → "*" (AsciiDoc bullets)
#   4. Unicode Greek letters → stem:[LaTeX name]
#   5. Math notation: where OCR confirms $X$ LaTeX, replace YAML's plain-text
#      equivalent with stem:[LaTeX content].
#   6. Designation/definition corruption fixes (truncation, leaked refs,
#      mangled text) — restored from OCR.
#
# Idempotent: re-running is a no-op once everything is converted.
# Reports the change count per file.
#
# Usage:
#   ruby scripts/fix_g18_encoding.rb                # apply
#   ruby scripts/fix_g18_encoding.rb --dry-run      # show what would change

require "optparse"
require "yaml"
require "set"
require "fileutils"

repo_root = File.expand_path("..", __dir__)
options = {
  concepts_dir: File.join(repo_root, "datasets", "g18", "concepts"),
  ocr_path: File.join(repo_root, "reference-docs", "g018-2010-ocr", "glm-ocr.md"),
  dry_run: false,
}

OptionParser.new do |opts|
  opts.banner = "Usage: #{$PROGRAM_NAME} [options]"
  opts.on("--concepts PATH", String) { |v| options[:concepts_dir] = v }
  opts.on("--ocr PATH", String) { |v| options[:ocr_path] = v }
  opts.on("--dry-run") { options[:dry_run] = true }
  opts.on("-h", "--help") { puts opts; exit 0 }
end.parse!

# ── Translation tables ───────────────────────────────────────────────────────

SMART_QUOTES = {
  "‘" => "'",
  "’" => "'",
  "‚" => "'",
  "‛" => "'",
  "“" => '"',
  "”" => '"',
  "„" => '"',
  "‟" => '"',
  "′" => "'",
  "″" => '"',
}

# CJK fullwidth punctuation that OCR emits in place of ASCII equivalents.
FULLWIDTH_ASCII = {
  "，" => ",",
  "：" => ":",
  "；" => ";",
  "（" => "(",
  "）" => ")",
  "！" => "!",
  "？" => "?",
  "［" => "[",
  "］" => "]",
}

HTML_ENTITIES = {
  "&apos;"  => "'",
  "&#x27;"  => "'",
  "&#39;"   => "'",
  "&quot;"  => '"',
  "&amp;"   => "&",
  "&lt;"    => "<",
  "&gt;"    => ">",
  "&nbsp;"  => " ",
}

# Symbol-font PUA chars with unambiguous ASCII equivalents.
PUA_TO_ASCII = {
  "" => " ",   # blank glyph
  "" => "(",   # open paren
  "" => ")",   # close paren
  "" => "-",   # hyphen-minus
  "" => "]",   # close bracket
}

# Symbol-font PUA chars that represent math glyphs.
PUA_TO_STEM = {
  "" => "stem:[Delta]",   # Δ
  "" => "stem:[Sigma]",   # Σ
  "" => "stem:[chi]",     # χ
  "" => "stem:[delta]",   # δ
}

# PUA typographic marks (bullets, section marks) → AsciiDoc.
PUA_TO_MARK = {
  "" => "*",
  "" => "*",
}

# Unicode Greek letters → stem:[LaTeX name].
GREEK_TO_STEM = {
  "Α" => "stem:[Alpha]",   "Β" => "stem:[Beta]",    "Γ" => "stem:[Gamma]",
  "Δ" => "stem:[Delta]",   "Ε" => "stem:[Epsilon]", "Ζ" => "stem:[Zeta]",
  "Η" => "stem:[Eta]",     "Θ" => "stem:[Theta]",   "Ι" => "stem:[Iota]",
  "Κ" => "stem:[Kappa]",   "Λ" => "stem:[Lambda]",  "Μ" => "stem:[Mu]",
  "Ν" => "stem:[Nu]",      "Ξ" => "stem:[Xi]",      "Ο" => "stem:[Omicron]",
  "Π" => "stem:[Pi]",      "Ρ" => "stem:[Rho]",     "Σ" => "stem:[Sigma]",
  "Τ" => "stem:[Tau]",     "Υ" => "stem:[Upsilon]", "Φ" => "stem:[Phi]",
  "Χ" => "stem:[Chi]",     "Ψ" => "stem:[Psi]",     "Ω" => "stem:[Omega]",
  "α" => "stem:[alpha]",   "β" => "stem:[beta]",    "γ" => "stem:[gamma]",
  "δ" => "stem:[delta]",   "ε" => "stem:[epsilon]", "ζ" => "stem:[zeta]",
  "η" => "stem:[eta]",     "θ" => "stem:[theta]",   "ι" => "stem:[iota]",
  "κ" => "stem:[kappa]",   "λ" => "stem:[lambda]",  "μ" => "stem:[mu]",
  "ν" => "stem:[nu]",      "ξ" => "stem:[xi]",      "ο" => "stem:[omicron]",
  "π" => "stem:[pi]",      "ρ" => "stem:[rho]",     "σ" => "stem:[sigma]",
  "τ" => "stem:[tau]",     "υ" => "stem:[upsilon]", "φ" => "stem:[phi]",
  "χ" => "stem:[chi]",     "ψ" => "stem:[psi]",     "ω" => "stem:[omega]",
}

# Unicode subscript/superscript digits → stem-friendly form.
UNICODE_SUBSCRIPT = {
  "₀" => "0", "₁" => "1", "₂" => "2", "₃" => "3", "₄" => "4",
  "₅" => "5", "₆" => "6", "₇" => "7", "₈" => "8", "₉" => "9",
}

# Known designation/definition corruption to restore from OCR. Each entry
# is `id => { from: /regex/, to: "text" }`. Sourced from the OCR-confirmed
# audit findings (truncations, leaked refs, mangled text).
DESIGNATION_REPAIRS = {
  "00247" => { from: /non-automatic checking facility \(type\z/i,
               to:  "non-automatic checking facility (Type N)" },
  "00464" => { from: /non-automatic checking facility \(type\z/i,
               to:  "non-automatic checking facility (Type N)" },
  "01250" => { from: /non-automatic checking facility \(type\z/i,
               to:  "non-automatic checking facility (Type N)" },
  "01657" => { from: /nonautomatic checking facility \(Type\z/i,
               to:  "nonautomatic checking facility (Type N)" },
  "00517" => { from: /\s*\[applicable only to belt weighers.*\z/i,
               to:  "" },
  "01317" => { from: /\s*di\z/, to: "" },
  "00596" => { from: /data storage decvice/i, to: "data storage device" },
  "01701" => { from: /device device R136-1:2004,?\z/i, to: "device" },
  "01594" => { from: /\s*measur smalle intend minimu\z/i, to: "" },
  "01459" => { from: /\s*samp prof wavi\z/i,
               to:  " (stem:[R_a] or stem:[R_z])" },
  "00867" => { from: /\s*,\z/, to: ", RVM" },
  "01357" => { from: /\Ascale interval\z/i, to: "scale interval (d)" },
  "00945" => { from: /\Amaximum tare effect\z/i,
               to:  "maximum tare effect (T=+...,T=-...)" },
  "00144" => { from: /lot \(of measuring instruments\z/i,
               to:  "lot (of measuring instruments)" },
}

# Full-text replacements for definitions so corrupted that surgical regex
# fixes won't recover them. Each value is OCR's text with `$X$` math
# converted to `stem:[X]`.
DEFINITION_REPLACEMENTS = {
  "00647" => "For a given value of the measured mass, the quotient of the change " \
             "of the observed variable, stem:[l], and the corresponding change of " \
             "the measured mass, stem:[M]: stem:[k] = stem:[Delta l/Delta M]",
  "00711" => "all load cells within a family possessing identical metrological " \
             "characteristics (for example, class, stem:[n_max], temperature " \
             "rating, etc.)",
  "00982" => "fault greater than stem:[e]. The following are not considered to be " \
             "significant faults, even when they exceed stem:[e]: - faults arising " \
             "from simultaneous and mutually independent causes in the instrument; " \
             "- faults implying the impossibility to perform any measurement; - " \
             "faults being so serious that they are bound to be noticed by all " \
             "those interested in the result of measurement; or - transitory " \
             "faults, being momentary variations in the indication which cannot " \
             "be interpreted, memorized or transmitted as a measurement result",
  "01459" => "parameter that describes the assessed roughness profile of a sample. " \
             "The letter stem:[R] is indicative of the type of assessed profile, " \
             "in this case stem:[R] for roughness profile. The assessed profile " \
             "of a sample can be in terms of different profile types: a roughness " \
             "profile or R-parameter, primary profile or P-parameter, a waviness " \
             "profile or W-parameter",
  "01594" => "smallest quantity of liquid for which the measurement is " \
             "metrologically acceptable for that system or element. In measuring " \
             "systems intended for delivery operations, this smallest quantity " \
             "is referred to as the minimum delivery; in those intended for " \
             "receiving operations, it is referred to as the minimum receipt",
}

def apply_text_subs(s)
  return s unless s.is_a?(String)
  out = s
  SMART_QUOTES.each   { |k, v| out = out.gsub(k, v) }
  FULLWIDTH_ASCII.each { |k, v| out = out.gsub(k, v) }
  HTML_ENTITIES.each  { |k, v| out = out.gsub(k, v) }
  PUA_TO_ASCII.each   { |k, v| out = out.gsub(k, v) }
  PUA_TO_STEM.each    { |k, v| out = out.gsub(k, v) }
  PUA_TO_MARK.each    { |k, v| out = out.gsub(k, v) }
  GREEK_TO_STEM.each  { |k, v| out = out.gsub(k, v) }
  UNICODE_SUBSCRIPT.each { |k, v| out = out.gsub(k, v) }
  out
end
# Apply OCR-driven math conversion. For each `$X$` in OCR text, find the
# plain-text equivalent in YAML and replace with stem:[X].
def ocr_math_to_stem(ocr_text)
  return nil if ocr_text.nil?
  return nil unless ocr_text.include?("$")
  ocr_text.gsub(/\$([^$]+)\$/) do
    inner = Regexp.last_match(1).strip
    # Strip outer wrapping braces only when the whole expression is wrapped.
    if inner.start_with?("{") && inner.end_with?("}")
      inner = inner[1..-2]
    end
    "stem:[#{inner}]"
  end
end

# For each shared ID, if OCR term has $...$ and YAML term doesn't, replace
# YAML term with OCR-derived stem-wrapped version.
def apply_ocr_math_to_designation(yaml_term, ocr_term)
  return yaml_term unless ocr_term && ocr_term.include?("$")
  converted = ocr_math_to_stem(ocr_term)
  # Skeleton comparison: strip math markup so we compare only the underlying
  # letters. `\mathrm{X}` reduces to `X`; other LaTeX commands keep their
  # name (just drop the backslash); braces and `stem:[...]` wrappers drop out.
  norm = ->(s) do
    s.to_s
      .gsub(/\\mathrm\{([^}]*)\}/) { Regexp.last_match(1) }  # \mathrm{X} → X
      .gsub(/\\([a-zA-Z]+)/) { Regexp.last_match(1) }       # \Delta → Delta, \min → min
      .downcase
      .gsub(/stem:\[/, "")
      .gsub(/\]/, "")
      .gsub(/[^a-z0-9]/, "")
  end
  skel_yaml = norm.call(yaml_term)
  skel_ocr  = norm.call(converted)
  return yaml_term unless skel_yaml == skel_ocr && !skel_yaml.empty?
  apply_text_subs(converted)
end

# ── OCR loader (mirrors the audit script) ────────────────────────────────────

ROW_RE = /<td>(.*?)<\/td>/m

def clean_cell(s)
  out = s.to_s.gsub(/<[^>]+>/, "")
  HTML_ENTITIES.each { |k, v| out = out.gsub(k, v) }
  out = out.gsub(/\s+/, " ").strip
  out
end

def load_ocr(path)
  text = File.read(path)
  by_id = {}
  text.split(/<tr>/i).each do |row_text|
    cells = row_text.scan(ROW_RE).map { |m| clean_cell(m.first) }
    next unless cells.size == 5
    id = cells.last
    next unless id =~ /\A\d{5}\z/
    by_id[id] ||= { "term" => cells[0], "reference" => cells[1],
                    "definition" => cells[2], "notes" => cells[3] }
  end
  # Also pair a/b for duplicate IDs (sorted by term).
  counts = Hash.new(0)
  by_id.each_key { |k| counts[k] += 1 }
  text.split(/<tr>/i).each do |row_text|
    cells = row_text.scan(ROW_RE).map { |m| clean_cell(m.first) }
    next unless cells.size == 5
    id = cells.last
    next unless id =~ /\A\d{5}\z/
    next if by_id.key?(id) && by_id[id]["term"] == cells[0]
  end
  by_id
end

# ── Main ─────────────────────────────────────────────────────────────────────

ocr = load_ocr(options[:ocr_path])
puts "Loaded OCR: #{ocr.size} unique IDs"

files = Dir.glob(File.join(options[:concepts_dir], "*.yaml")).sort
stats = { files_changed: 0, designations_changed: 0, definitions_changed: 0,
          notes_changed: 0, total_subs: 0 }

files.each do |path|
  id = File.basename(path, ".yaml").sub(/a?\z/) { |m| m }
  raw_id = File.basename(path, ".yaml")
  original = File.read(path)
  docs = YAML.safe_load_stream(original, filename: path, aliases: true)

  changed = false
  docs.each do |doc|
    next unless doc.is_a?(Hash) && doc["data"].is_a?(Hash)
    data = doc["data"]

    # Designation
    if data["terms"].is_a?(Array)
      data["terms"].each do |t|
        next unless t.is_a?(Hash) && t["designation"].is_a?(String)
        before = t["designation"]
        after = apply_text_subs(before)
        # Apply targeted designation repairs
        if (repair = DESIGNATION_REPAIRS[raw_id] || DESIGNATION_REPAIRS[id])
          after = after.sub(repair[:from], repair[:to])
        end
        # OCR-driven math conversion
        ocr_row = ocr[raw_id] || ocr[id]
        if ocr_row
          after = apply_ocr_math_to_designation(after, ocr_row["term"])
        end
        after = after.strip
        if after != before
          t["designation"] = after
          changed = true
          stats[:designations_changed] += 1
        end
      end
    end

    # Definition
    if data["definition"].is_a?(Array)
      # Full replacement takes precedence over surgical subs.
      if (replacement = DEFINITION_REPLACEMENTS[raw_id] || DEFINITION_REPLACEMENTS[id])
        if data["definition"].size == 1 && data["definition"][0].is_a?(Hash)
          data["definition"][0]["content"] = replacement
          changed = true
          stats[:definitions_changed] += 1
        end
      else
        data["definition"].each do |d|
          next unless d.is_a?(Hash) && d["content"].is_a?(String)
          before = d["content"]
          after = apply_text_subs(before)
          if after != before
            d["content"] = after
            changed = true
            stats[:definitions_changed] += 1
          end
        end
      end
    end

    # Notes
    if data["notes"].is_a?(Array)
      data["notes"].each do |n|
        next unless n.is_a?(Hash) && n["content"].is_a?(String)
        before = n["content"]
        after = apply_text_subs(before)
        if after != before
          n["content"] = after
          changed = true
          stats[:notes_changed] += 1
        end
      end
    end
  end

  next unless changed
  stats[:files_changed] += 1
  next if options[:dry_run]

  # Re-emit YAML preserving the multi-document stream.
  output = docs.map { |d| d.nil? ? "---\n" : YAML.dump(d) }.join
  # Preserve the leading "---" stream start marker if the original had one.
  output = "---\n#{output}" unless output.start_with?("---\n")
  File.write(path, output)
end

puts
puts "Stats:"
puts "  Files changed:         #{stats[:files_changed]}"
puts "  Designations changed:  #{stats[:designations_changed]}"
puts "  Definitions changed:   #{stats[:definitions_changed]}"
puts "  Notes changed:         #{stats[:notes_changed]}"
puts "  Mode:                  #{options[:dry_run] ? 'DRY-RUN' : 'APPLIED'}"
