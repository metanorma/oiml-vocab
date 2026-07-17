#!/usr/bin/env ruby
# frozen_string_literal: true

# Build datasets/oiml-complete/ from the glossarist data in the
# sibling publications repo (sources/<slug>/glossarist/).
#
# Walks every publication's glossarist concept files, merges multilingual
# editions (EN + FR with same identifier), converts to v3 format, sets
# sections by publication family, computes deterministic UUIDs, and
# writes the unified dataset.

require "yaml"
require "fileutils"
require "pathname"
require "set"

PUB_REPO = Pathname.new("/Users/mulgogi/src/oimlsmart/publications-private")
OUT_DIR = Pathname.new(__dir__) + ".." + "datasets" + "oiml-complete"
NS_UUID = "6b1d8e3a-8f9c-4c2b-bf5e-1a4d2c7b9e05"

# ── UUID v5 ──────────────────────────────────────────────────────────────
require "digest"

def uuid_v5(namespace_hex, name)
  hash = Digest::SHA1.digest([namespace_hex].pack("H*") + name.to_s)
  b = hash.bytes.first(16)
  b[6] = (b[6] & 0x0F) | 0x50
  b[8] = (b[8] & 0x3F) | 0x80
  hex = b.map { |x| format("%02x", x) }
  "#{hex[0..3].join}-#{hex[4..5].join}-#{hex[6..7].join}-#{hex[8..9].join}-#{hex[10..15].join}"
end

def uuid_for(*parts)
  uuid_v5(NS_UUID, parts.join("|"))
end

# ── Pub-code helpers ─────────────────────────────────────────────────────
LANG_SUFFIXES = %w[eng fra spa deu fas ara zho rus por ita nld pol srp ukr e f].freeze

def strip_lang_suffix(slug)
  LANG_SUFFIXES.each { |s| return slug.sub(/-#{s}$/, "") if slug.end_with?("-#{s}") }
  slug
end

def lang_of_slug(slug)
  LANG_SUFFIXES.each do |s|
    return canonical_lang(s) if slug.end_with?("-#{s}")
  end
  # No language suffix detected — default to eng
  "eng"
end

def canonical_lang(code)
  { "e" => "eng", "f" => "fra" }.fetch(code, code)
end

def section_of(slug)
  base = strip_lang_suffix(slug)
  kind = base[0]
  rest = base[1..]
  num = rest.split(/[-_]/).first
  "#{kind}-#{num}"
end

def pub_ref_of(slug)
  base = strip_lang_suffix(slug)
  kind = base[0].upcase
  rest = base[1..]
  num_part, year_part = rest.match(/\A(.+?)-(\d{4})/)&.captures || [rest, "0"]
  "OIML #{kind} #{num_part}:#{year_part}"
end

def pub_urn_of(slug)
  base = strip_lang_suffix(slug)
  kind = base[0].downcase
  rest = base[1..]
  num_part, year_part = rest.match(/\A(.+?)-(\d{4})/)&.captures || [rest, "0"]
  "urn:oiml:pub:#{kind}:#{num_part}:#{year_part}"
end

def term_seq(identifier)
  identifier.split("-").last.sub(/\A0+/, "")
end

# ── v2 → v3 conversion ──────────────────────────────────────────────────
def v3_text_array(arr)
  return [] unless arr.is_a?(Array)
  arr.map { |t| t.is_a?(String) ? { "content" => t } : t }
end

def v3_sources(raw, pub_ref)
  return [] unless raw.is_a?(Array) && raw.any?
  result = []
  raw.each do |s|
    entry = if s.is_a?(Hash) && s["origin"].is_a?(Hash)
      s
    elsif s.is_a?(String)
      { "type" => "authoritative", "origin" => { "ref" => { "source" => s } } }
    elsif s.is_a?(Hash) && s["origin"].is_a?(String)
      { "type" => "authoritative", "origin" => { "ref" => { "source" => s["origin"] } } }
    elsif s.is_a?(Hash) && s["ref"]
      { "type" => "authoritative", "origin" => { "ref" => { "source" => s["ref"].to_s } } }
    elsif s.is_a?(Hash)
      src = s["source"] || s["ref"]
      next nil unless src
      { "type" => "authoritative", "origin" => { "ref" => { "source" => src.to_s } } }
    else
      next nil
    end
    # Only keep OIML-prefixed sources (others are cross-refs, not provenance)
    ref_val = entry.dig("origin", "ref", "source") rescue nil
    ref_val ||= entry.dig("origin", "ref") rescue nil
    next nil unless ref_val.is_a?(String) && ref_val.match?(/\AOIML\b/)
    result << entry
  end
  result
end

# ── Main ────────────────────────────────────────────────────────────────

puts "Scanning publications repo..."

# Collect all concept files grouped by (base_slug, identifier)
groups = Hash.new { |h, k| h[k] = [] }

Dir.glob(PUB_REPO + "sources" + "*" + "glossarist" + "concepts" + "*.yaml").each do |path|
  slug = Pathname.new(path).parent.parent.parent.basename.to_s  # sources/<slug>/glossarist/...
  basename = File.basename(path, ".yaml")
  base_slug = strip_lang_suffix(slug)
  key = "#{base_slug}\t#{basename}"
  groups[key] << { path: path, slug: slug, lang: lang_of_slug(slug) }
end

puts "Found #{groups.size} unique (pub, identifier) groups"
multi_lang = groups.select { |_, files| files.map { |f| f[:lang] }.uniq.size > 1 }
puts "  Multilingual: #{multi_lang.size}"
puts "  Monolingual:  #{groups.size - multi_lang.size}"

# Prepare output
out_concepts = OUT_DIR + "concepts"
FileUtils.rm_rf(out_concepts)
FileUtils.mkdir_p(out_concepts)

bib_ids = Set.new
sections_map = {}  # section_id => eng name

processed = 0
groups.each do |key, files|
  base_slug, identifier = key.split("\t")
  seq = term_seq(identifier)
  out_name = "#{base_slug}-#{seq}.yaml"

  # Load all language variants
  by_lang = {}
  files.each do |f|
    begin
      docs = YAML.load_stream(File.read(f[:path]))
    rescue Psych::SyntaxError => e
      warn "  SKIP #{f[:slug]}/#{File.basename(f[:path])}: #{e.message[0..80]}"
      next
    end
    outer = docs.find { |d| d.is_a?(Hash) && d["data"] && d["data"]["identifier"] }

    # The publications repo splits localized concepts across two YAML docs:
    # - one doc has data.definition/data.terms (content)
    # - a separate doc has top-level language_code/id (metadata)
    # Match them by UUID (metadata.id == localized_concepts value).
    loc = nil
    if outer
      lc_map = outer["data"]["localized_concepts"] || {}
      # Find metadata docs (top-level language_code)
      meta_docs = docs.select { |d| d.is_a?(Hash) && d["language_code"] }
      # Find content docs (data.definition or data.terms)
      content_docs = docs.select { |d| d.is_a?(Hash) && d["data"] && (d["data"]["definition"] || d["data"]["terms"]) }

      # Try to match by UUID
      meta_docs.each do |meta|
        uuid = meta["id"]
        lang = meta["language_code"]
        # Find the content doc that belongs to this language
        content = content_docs.find { |c| c["data"]["id"]&.end_with?("-#{lang}") }
        content ||= content_docs.find { |c| c["data"]["id"] == "#{outer["data"]["identifier"]}-#{lang}" }
        if content
          # Merge content + metadata
          loc = content.dup
          loc["data"]["language_code"] = lang
          loc["data"]["entry_status"] = meta["entry_status"] || "valid"
          break
        end
      end

      # Fallback: single-doc format with language_code inside data
      loc ||= docs.find { |d| d.is_a?(Hash) && d["data"] && d["data"]["language_code"] }
    end

    next unless outer && loc
    by_lang[f[:lang]] = { outer: outer, loc: loc, docs: docs }
  end
  next if by_lang.empty?

  # Primary: eng, else first
  primary_lang = by_lang.key?("eng") ? "eng" : by_lang.keys.first
  primary = by_lang[primary_lang]

  # Build localized_concepts UUID map
  loc_map = {}
  by_lang.each_key { |lang| loc_map[lang] = uuid_for("oiml-complete", base_slug, seq, lang) }
  outer_uuid = uuid_for("oiml-complete", base_slug, seq)

  # Read register.yaml for the correct pub ref/urn (not parsed from slug)
  pub_ref = pub_ref_of(base_slug)
  pub_urn = pub_urn_of(base_slug)
  begin
    reg = YAML.load_file(PUB_REPO + "sources" + files.first[:slug] + "glossarist" + "register.yaml")
    pub_ref = reg["ref"].to_s if reg["ref"]
    pub_urn = reg["urn"].to_s if reg["urn"]
  rescue
  end

  # Section
  sec = section_of(base_slug)
  sections_map[sec] ||= pub_ref.sub(/:.*/, "").sub("OIML ", "").sub(/\s*\(.\)\s*/, "")

  # Build outer doc (v3)
  pdata = primary[:outer]["data"]
  outer_doc = {
    "data" => {
      "identifier" => "#{base_slug}-#{seq}",
      "localized_concepts" => loc_map,
      "domains" => [{ "concept_id" => sec, "source" => pub_urn, "ref_type" => "section" }],
      "sources" => [{
        "type" => "authoritative",
        "origin" => { "ref" => { "source" => pub_ref } },
      }],
    },
    "status" => "valid",
    "id" => outer_uuid,
    "schema_version" => "3",
  }

  # Track bibliography
  bib_ids.add(pub_ref)

  # Build localized docs (v3)
  out_docs = [outer_doc]
  by_lang.each do |lang, variant|
    next unless variant[:loc]
    ldata = variant[:loc]["data"]

    loc_doc = {
      "data" => {
        "dates" => ldata["dates"] || [{ "date" => "2026-07-16T00:00:00+00:00", "type" => "accepted" }],
        "definition" => v3_text_array(ldata["definition"]),
        "examples" => v3_text_array(ldata["examples"]),
        "id" => "#{base_slug}-#{seq}-#{lang}",
        "notes" => v3_text_array(ldata["notes"]),
        "sources" => [],
        "terms" => ldata["terms"] || [],
        "language_code" => lang,
        "entry_status" => "valid",
      },
      "date_accepted" => "2026-07-16T00:00:00+00:00",
      "id" => loc_map[lang],
    }

    out_docs << loc_doc
  end

  # Write multi-doc YAML
  parts = out_docs.map { |d| YAML.dump(d).sub(/\A---\n/, "") }
  File.write(out_concepts + "#{out_name.sub(/\.yaml$/, '')}.yaml", "---\n" + parts.join("---\n") + "\n")
  processed += 1
end

puts "Wrote #{processed} concept files"

# Build sections list
sections_list = sections_map.sort.map do |sec_id, name|
  { "id" => sec_id, "names" => { "eng" => "OIML #{name}" } }
end

# Build register.yaml
register = {
  "schema_type" => "glossarist",
  "schema_version" => "3",
  "id" => "oiml-complete",
  "ref" => "OIML Complete Vocabulary",
  "ref_aliases" => ["OIML Complete Vocabulary"],
  "year" => 2026,
  "urn" => "urn:oiml:dataset:oiml-complete",
  "urn_aliases" => ["urn:oiml:dataset:oiml-complete*"],
  "status" => "valid",
  "owner" => "OIML",
  "source_repo" => "https://github.com/oimlsmart/vocab",
  "tags" => %w[metrology oiml vocabulary derived],
  "languages" => %w[deu eng fra pol spa],
  "language_order" => %w[eng fra spa deu pol],
  "derived" => true,
  "derived_from" => "cross-publication terminology extraction across all OIML publications",
  "description" => {
    "eng" => 'Comprehensive terminology index derived from all OIML publications — every terminology entry from every OIML publication, with full provenance. ~7,000 concepts across ~300+ publications.',
    "fra" => 'Index terminologique exhaustif dérivé des publications OIML — chaque entrée terminologique de chaque publication OIML est enregistrée, avec provenance complète.',
  },
  "ordering" => "systematic",
  "sections" => sections_list,
  "concept_count" => processed,
}
File.write(OUT_DIR + "register.yaml", YAML.dump(register))

# Build bibliography.yaml
bib = bib_ids.to_a.map { |id| { "id" => id, "type" => "OIML publication" } }
File.write(OUT_DIR + "bibliography.yaml", YAML.dump(bib))
puts "Register: #{sections_list.size} sections"
puts "Bibliography: #{bib.size} entries"
puts "Done."
