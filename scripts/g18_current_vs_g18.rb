#!/usr/bin/env ruby
# frozen_string_literal: true

# G 18 current ↔ G 18:202X cross-reference + tip dataset builder.
#
# Outputs a permanent report directory at
#   reference-docs/g18-current-vs-g18/
# with one file per cross-reference category, plus a summary.
#
# Categories:
#   01-at-tip.txt                         G 18 entries citing current tip editions
#   02-below-tip-has-clause.txt           G 18 stale (older edition, clause exists at tip)
#   03-below-tip-no-clause.txt            G 18 stale (older edition, clause NOT at tip)
#   04-no-family-citation-missing.txt     G 18 entries with no source citation
#   05-no-family-pub-in-corpus.txt        G 18 cites a pub whose family IS in G 18 complete but
#                                         has no extracted concepts (skip — confirmed
#                                         no terminology by past agents, OR extraction gap)
#   06-no-family-pub-missing-from-corpus.txt  G 18 cites a pub family NOT in the OCR
#                                         corpus — needs to be obtained
#   07-tip-editions-missing-from-g18.txt  Per-family breakdown of tip concepts absent
#                                         from G 18 (which tip editions need to be added)
#   08-summary.txt                        Top-level numbers
#
# Usage:
#   ruby scripts/g18_current_vs_g18.rb                # report only
#   ruby scripts/g18_current_vs_g18.rb --build        # also build g18-current dataset

require "yaml"
require "pathname"
require "set"
require "optparse"
require "fileutils"

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
require "oiml/g18_complete"

REPO_ROOT = Pathname.new(File.expand_path("..", __dir__))
G18_COMPLETE_CONCEPTS = REPO_ROOT + "datasets" + "g18-complete" + "concepts"
G18_CONCEPTS = REPO_ROOT + "datasets" + "g18-202X" + "concepts"
SOURCE_ROOT = Pathname.new("/Users/mulgogi/src/oimlsmart/publications/reference-docs/ocr-output")
PUB_CODES = Set.new(SOURCE_ROOT.children.select(&:directory?).map(&:basename).map(&:to_s))
OUT_DIR = REPO_ROOT + "reference-docs" + "g18-current-vs-g18"

# Publications that have been formally withdrawn by OIML and are no
# longer obtainable. These should not be requested for OCR acquisition.
# G 18:202X entries that cite these need to be REMOVED, not updated.
WITHDRAWN_REFS = Set.new([
  "OIML R 38:2007",
  "OIML R 39:2006",
  "OIML D 15:1986",
]).freeze

module G18CurrentG18
  module_function

  LANG_SUFFIXES = %w[eng fra spa deu ara fas zho rus por ita nld pol srp ukr e f].freeze

  def resolve_pub_code(basename)
    parts = basename.split("-")
    (parts.length - 1).downto(1) do |i|
      candidate = parts[0...i].join("-")
      return candidate if PUB_CODES.include?(candidate)
      # Merged multilingual files use base pub-code without language suffix.
      # Try adding each known suffix to see if a real OCR directory exists.
      LANG_SUFFIXES.each do |sfx|
        return candidate if PUB_CODES.include?("#{candidate}-#{sfx}")
      end
    end
    nil
  end

  def family_of(pub_code)
    parsed = Oiml::G18Complete::PublicationCode.parse(pub_code)
    base = parsed.number.to_s.split("-").first
    "#{parsed.kind} #{base}"
  end

  # Match "OIML R 49-1:2024" → family "R 49", year 2024.
  REF_RE = /\AOIML\s+([A-Z])\s+(\d+)(?:-\d+)*:(\d{4})\z/.freeze
  # Also handle "OIML D 91-1:2025" etc.

  def parse_ref(ref)
    return nil unless ref
    m = ref.to_s.match(REF_RE)
    return nil unless m
    { kind: m[1], base_number: m[2], family: "#{m[1]} #{m[2]}", year: m[3].to_i }
  end

  # ------- G 18 current loading -------

  def load_g18_current_tip
    pub_info = Hash.new { |h, k| h[k] = { langs: Set.new, terms: Set.new, term_data: {} } }

    G18_COMPLETE_CONCEPTS.children.each do |f|
      basename = f.basename(".yaml").to_s
      pc = resolve_pub_code(basename)
      next unless pc
      term = basename.delete_prefix("#{pc}-")
      pub_info[pc][:terms] << term

      docs = YAML.load_stream(f.read)
      outer = docs.first
      next unless outer.is_a?(Hash) && outer["data"].is_a?(Hash)

      (outer.dig("data", "localized_concepts") || {}).each_key do |lang|
        pub_info[pc][:langs] << lang
      end
      pub_info[pc][:term_data][term] = docs

      next if pub_info[pc][:year]
      sources = outer.dig("data", "sources") || []
      src = sources.first || {}
      version = src.dig("origin", "ref", "version")
      year = version ? version.to_i : Oiml::G18Complete::PublicationCode.parse(pc).year
      pub_info[pc][:year] = year
    end

    pub_info.each_key { |pc| pub_info[pc][:family] = family_of(pc) }

    families = Hash.new { |h, k| h[k] = [] }
    pub_info.each_key { |pc| families[pub_info[pc][:family]] << pc }

    tip = {}
    families.each do |family, codes|
      max_year = codes.map { |c| pub_info[c][:year] }.max
      tip_pubs = codes.select { |c| pub_info[c][:year] == max_year }
      tip[family] = { year: max_year, pub_codes: tip_pubs }
    end

    tip_concepts = Hash.new do |h, k|
      h[k] = { langs: Set.new, pub_codes: Set.new, term_data_per_lang: {}, designations: Set.new,
               cited_refs: Set.new }
    end

    tip.each do |family, info|
      info[:pub_codes].each do |pc|
        pub_info[pc][:terms].each do |term|
          key = [family, term]
          docs = pub_info[pc][:term_data][term]
          outer = docs.first
          loc_concepts = outer.dig("data", "localized_concepts") || {}
          loc_concepts.each_key do |lang|
            tip_concepts[key][:langs] << lang
            tip_concepts[key][:term_data_per_lang][lang] ||= docs
          end
          tip_concepts[key][:pub_codes] << pc
          docs.each do |d|
            next unless d.is_a?(Hash) && d["data"] && d["data"]["terms"]
            (d["data"]["terms"] || []).each do |t|
              next unless t.is_a?(Hash) && t["designation"]
              tip_concepts[key][:designations] << t["designation"].to_s.downcase
            end
          end
          src_ref = outer.dig("data", "sources", 0, "origin", "ref", "source")
          tip_concepts[key][:cited_refs] << src_ref if src_ref
        end
      end
    end

    { pub_info: pub_info, families: families, tip: tip, tip_concepts: tip_concepts }
  end

  def load_g18
    entries = {}
    G18_CONCEPTS.children.each do |f|
      basename = f.basename(".yaml").to_s
      docs = YAML.load_stream(f.read)
      outer = docs.first
      next unless outer.is_a?(Hash) && outer["data"]
      identifier = outer["data"]["identifier"]
      sources = outer.dig("data", "sources") || []
      src = sources.first || {}
      ref = src.dig("origin", "ref", "source")
      clause = src.dig("locality", "reference_from") || src.dig("locality", "reference")
      designation = nil
      docs.each do |d|
        next unless d.is_a?(Hash) && d["data"] && d["data"]["terms"].is_a?(Array)
        t = d["data"]["terms"].first
        designation = t["designation"] if t
      end

      parsed = parse_ref(ref)
      entries[basename] = {
        identifier: identifier,
        ref: ref,
        clause: clause,
        family: parsed && parsed[:family],
        cited_year: parsed && parsed[:year],
        designation: designation,
        file: f,
        docs: docs,
      }
    end
    entries
  end

  # ------- Cross-reference -------

  def cross_reference(g18_dyn, g18)
    tip = g18_dyn[:tip]
    tip_concepts = g18_dyn[:tip_concepts]

    tip_by_clause = {}
    tip_by_designation = {}
    tip_concepts.each_key do |key|
      family, term = key
      tip_by_clause[[family, term]] = key
    end
    tip_concepts.each do |key, info|
      family, _term = key
      info[:designations].each do |desig|
        tip_by_designation[[family, desag_normalize(desig)]] ||= key
      end
    end

    result = {
      at_tip: [],
      below_tip_has_clause: [],
      below_tip_no_clause: [],
      no_citation: [],
      family_in_corpus_no_concepts: [],
      family_missing_from_corpus: [],
      family_withdrawn: [],
      g18_entries_total: g18.size,
    }

    # Index OCR corpus by family (kind+base_number) → list of dirs.
    corpus_by_family = Hash.new { |h, k| h[k] = [] }
    PUB_CODES.each do |pc|
      parsed = begin
        Oiml::G18Complete::PublicationCode.parse(pc)
      rescue StandardError
        next
      end
      base = parsed.number.to_s.split("-").first
      family = "#{parsed.kind} #{base}"
      corpus_by_family[family] << pc
    end

    g18.each_value do |entry|
      ref = entry[:ref]
      family = entry[:family]
      clause = entry[:clause]&.to_s
      cited_year = entry[:cited_year].to_i

      # Case 1: ref missing entirely
      if ref.nil? || ref.to_s.empty?
        result[:no_citation] << entry
        next
      end

      # Case 2: ref doesn't parse with our regex
      unless family
        result[:no_citation] << entry
        next
      end

      # Case 3: family not in G 18 current data
      unless tip[family]
        if WITHDRAWN_REFS.include?(ref)
          result[:family_withdrawn] << entry
        elsif corpus_by_family.key?(family)
          result[:family_in_corpus_no_concepts] << entry
        else
          result[:family_missing_from_corpus] << entry
        end
        next
      end

      # Family known. Compare years.
      tip_year = tip[family][:year]
      if cited_year == tip_year
        result[:at_tip] << entry
      elsif cited_year < tip_year
        tip_key = tip_by_clause[[family, clause]]
        if tip_key
          result[:below_tip_has_clause] << { entry: entry, tip_key: tip_key, tip_year: tip_year }
        else
          desig = desag_normalize(entry[:designation].to_s)
          tip_key = tip_by_designation[[family, desig]]
          if tip_key
            result[:below_tip_has_clause] << { entry: entry, tip_key: tip_key,
                                               tip_year: tip_year, matched_by: :designation }
          else
            result[:below_tip_no_clause] << { entry: entry, tip_year: tip_year }
          end
        end
      else
        # cited_year > tip_year (G 18 ahead of V 0)
        result[:below_tip_no_clause] << { entry: entry, tip_year: tip_year, ahead: true }
      end
    end

    # Tip concepts missing from G 18
    g18_clauses_per_family = Hash.new { |h, k| h[k] = Set.new }
    g18_designations_per_family = Hash.new { |h, k| h[k] = Set.new }
    g18.each_value do |entry|
      next unless entry[:family]
      g18_clauses_per_family[entry[:family]] << entry[:clause]&.to_s
      if entry[:designation]
        g18_designations_per_family[entry[:family]] << desag_normalize(entry[:designation].to_s)
      end
    end

    tip_missing = []
    tip_concepts.each do |key, info|
      family, term = key
      next unless g18_clauses_per_family.key?(family)
      clause_present = g18_clauses_per_family[family].include?(term)
      desig_present = info[:designations].any? { |d| g18_designations_per_family[family].include?(desag_normalize(d)) }
      next if clause_present || desig_present

      tip_missing << {
        tip_key: key,
        langs: info[:langs].to_a.sort,
        cited_refs: info[:cited_refs].to_a.sort,
        tip_year: tip[family][:year],
      }
    end

    result[:tip_missing_from_g18] = tip_missing
    result
  end

  def desag_normalize(s)
    s.to_s.downcase.gsub(/\s+/, " ").strip
  end

  # ------- Builder (unchanged from before) -------

  def build_g18_current_tip_dataset(g18_dyn)
    out_dir = REPO_ROOT + "datasets" + "g18-current"
    concepts_dir = out_dir + "concepts"
    concepts_dir.mkpath
    FileUtils.rm_rf(concepts_dir.children)

    namespace = Oiml::G18Complete::UuidNamespace::NAMESPACE_UUID
    dataset_id = "g18-current"
    tip_concepts = g18_dyn[:tip_concepts]
    pub_info = g18_dyn[:pub_info]

    written = 0
    langs_overall = Set.new
    pubs_cited = Set.new

    tip_concepts.keys.sort_by { |fam, term| [fam, term] }.each do |key|
      family, term = key
      info = tip_concepts[key]
      localized_docs = info[:term_data_per_lang]

      loc_map = {}
      localized_docs.each_key do |lang|
        loc_map[lang] = Oiml::G18Complete::UuidV5.generate(namespace, "#{dataset_id}|#{family}|#{term}|#{lang}")
      end
      outer_uuid = Oiml::G18Complete::UuidV5.generate(namespace, "#{dataset_id}|#{family}|#{term}")
      family_slug = family.downcase.tr(" ", "")
      identifier = "#{family_slug}-#{term}"

      sources = info[:pub_codes].sort.map do |pc|
        orig_outer = pub_info[pc][:term_data][term].first
        actual_ref = orig_outer.dig("data", "sources", 0, "origin", "ref", "source")
        actual_version = orig_outer.dig("data", "sources", 0, "origin", "ref", "version")
        parsed = Oiml::G18Complete::PublicationCode.parse(pc)
        {
          "origin" => { "ref" => { "source" => actual_ref || parsed.oiml_ref,
                                   "version" => actual_version || parsed.year.to_s } },
          "locality" => { "type" => "clause", "reference_from" => term },
          "type" => "authoritative",
        }
      end

      outer_doc = {
        "data" => {
          "identifier" => identifier,
          "localized_concepts" => loc_map,
          "domains" => [{
            "concept_id" => "section-terms",
            "source" => "urn:oiml:pub:#{family.downcase.tr(' ', ':')}:#{info[:pub_codes].sort.first ? Oiml::G18Complete::PublicationCode.parse(info[:pub_codes].sort.first).year : 0}",
            "ref_type" => "section",
          }],
          "sources" => sources,
        },
        "status" => "valid",
        "id" => outer_uuid,
        "schema_version" => "3",
      }

      docs = [outer_doc]
      localized_docs.each do |lang, orig_docs|
        loc = orig_docs.find do |d|
          d.is_a?(Hash) && d["data"] && d["data"]["language_code"] == lang
        end
        next unless loc
        new_loc = Marshal.load(Marshal.dump(loc))
        new_loc["data"]["id"] = "#{identifier}-#{lang}"
        new_loc["id"] = loc_map[lang]
        docs << new_loc
      end

      parts = docs.map { |d| YAML.dump(d).sub(/\A---\n/, "") }
      yaml_text = "---\n" + parts.join("---\n") + "\n"
      File.write(concepts_dir + "#{identifier}.yaml", yaml_text)

      written += 1
      langs_overall.merge(loc_map.keys)
      pubs_cited.merge(info[:pub_codes])
    end

    register = {
      "schema_type" => "glossarist",
      "schema_version" => "3",
      "id" => dataset_id,
      "ref" => "OIML G 18 current",
      "ref_aliases" => ["OIML G 18 current"],
      "year" => Time.now.utc.year,
      "urn" => "urn:oiml:dataset:g18-current",
      "urn_aliases" => ["urn:oiml:dataset:g18-current*"],
      "status" => "valid",
      "owner" => "OIML",
      "source_repo" => "https://github.com/oimlsmart/vocab",
      "tags" => %w[metrology oiml vocabulary derived tip],
      "languages" => langs_overall.to_a.sort,
      "language_order" => %w[eng fra spa deu ara fas zho rus pol] & langs_overall.to_a,
      "derived" => true,
      "derived_from" => "g18-complete tip concepts (correlated across languages)",
      "concept_count" => written,
    }
    File.write(out_dir + "register.yaml", YAML.dump(register))

    bib_entries = pubs_cited.sort.map do |pc|
      parsed = Oiml::G18Complete::PublicationCode.parse(pc)
      sample_doc = pub_info[pc][:term_data].values.first&.first
      actual_ref = sample_doc&.dig("data", "sources", 0, "origin", "ref", "source")
      ref = actual_ref || parsed.oiml_ref
      { "id" => ref, "urn" => parsed.urn, "type" => "OIML publication",
        "dataset_ids" => [pc] }
    end
    seen = {}
    deduped = bib_entries.each_with_object([]) do |e, acc|
      if seen[e["id"]]
        existing = acc.find { |a| a["id"] == e["id"] }
        existing["dataset_ids"].concat(e["dataset_ids"]).sort!
      else
        seen[e["id"]] = true
        acc << e
      end
    end
    File.write(out_dir + "bibliography.yaml", YAML.dump(deduped.sort_by { |e| e["id"] }))

    { written: written, out_dir: out_dir }
  end

  # ------- Report writers -------

  def write_reports(g18_dyn, g18, xref)
    OUT_DIR.mkpath
    OUT_DIR.children.each { |c| FileUtils.rm_f(c) }

    # 01 at-tip
    File.write(OUT_DIR + "01-at-tip.txt",
               xref[:at_tip].map { |e| "#{e[:identifier]}\t#{e[:ref]}\t#{e[:clause]}\t#{e[:designation]}" }.sort.join("\n") + "\n")

    # 02 below-tip has clause
    File.write(OUT_DIR + "02-below-tip-has-clause.txt",
               xref[:below_tip_has_clause].map { |e|
                 mb = e[:matched_by] ? " (matched_by #{e[:matched_by]})" : ""
                 "#{e[:entry][:identifier]}\t#{e[:entry][:ref]}\ttip_year=#{e[:tip_year]}\t#{e[:entry][:designation]}#{mb}"
               }.sort.join("\n") + "\n")

    # 03 below-tip no clause
    File.write(OUT_DIR + "03-below-tip-no-clause.txt",
               xref[:below_tip_no_clause].map { |e|
                 ahead = e[:ahead] ? " [AHEAD: G18 newer than G 18 complete tip]" : ""
                 "#{e[:entry][:identifier]}\t#{e[:entry][:ref]}\ttip_year=#{e[:tip_year]}\t#{e[:entry][:designation]}#{ahead}"
               }.sort.join("\n") + "\n")

    # 04 no citation
    File.write(OUT_DIR + "04-no-family-citation-missing.txt",
               xref[:no_citation].map { |e| "#{e[:identifier]}\t#{e[:ref] || '(no ref)'}\t#{e[:designation]}" }.sort.join("\n") + "\n")

    # 05 family in corpus but no concepts (V 0 extraction gap or correctly skipped)
    File.write(OUT_DIR + "05-no-family-pub-in-corpus.txt",
               xref[:family_in_corpus_no_concepts].map { |e|
                 "#{e[:identifier]}\t#{e[:ref]}\t#{e[:designation]}"
               }.sort.join("\n") + "\n")

    # 06 family missing from corpus entirely
    File.write(OUT_DIR + "06-no-family-pub-missing-from-corpus.txt",
               xref[:family_missing_from_corpus].map { |e|
                 "#{e[:identifier]}\t#{e[:ref]}\t#{e[:designation]}"
               }.sort.join("\n") + "\n")

    # 06b family withdrawn (OIML has formally withdrawn; do not pursue)
    File.write(OUT_DIR + "06b-no-family-withdrawn.txt",
               xref[:family_withdrawn].map { |e|
                 "#{e[:identifier]}\t#{e[:ref]}\t#{e[:designation]}"
               }.sort.join("\n") + "\n")

    # 07 tip editions missing from G 18 — grouped by family
    by_family = Hash.new { |h, k| h[k] = [] }
    xref[:tip_missing_from_g18].each do |t|
      family, term = t[:tip_key]
      by_family[family] << t.merge(term: term)
    end
    lines = []
    lines << "G 18 current concepts missing from G 18:202X — grouped by family"
    lines << "=" * 60
    lines << ""
    lines << "Format: <family> tip_year=<year> cited_refs=<refs> missing_count=<n>"
    lines << "  <term>  langs=<langs>"
    lines << ""
    by_family.sort.each do |family, items|
      tip_year = items.first[:tip_year]
      cited_refs = items.first[:cited_refs]
      lines << "#{family}  tip_year=#{tip_year}  cited_refs=#{cited_refs.join(',')}  missing_count=#{items.size}"
      items.sort_by { |i| i[:term] }.each do |t|
        lines << "  #{t[:term]}\tlangs=#{t[:langs].join(',')}"
      end
      lines << ""
    end
    File.write(OUT_DIR + "07-tip-editions-missing-from-g18.txt", lines.join("\n") + "\n")

    # 08 summary
    summary = []
    summary << "G 18 current ↔ G 18:202X cross-reference summary"
    summary << "=" * 60
    summary << ""
    summary << "G 18:202X entries:        #{xref[:g18_entries_total]}"
    summary << "G 18 complete unique tip concepts:  #{g18_dyn[:tip_concepts].size}"
    summary << ""
    summary << "G 18 entries — by status:"
    summary << "  At tip (cites current edition):           #{xref[:at_tip].size}"
    summary << "  Below tip, clause exists at tip:          #{xref[:below_tip_has_clause].size}  ← update G 18 ref to tip"
    summary << "  Below tip, clause NOT at tip:             #{xref[:below_tip_no_clause].size}  ← term removed/renamed"
    summary << "  No citation in G 18 entry:                #{xref[:no_citation].size}"
    summary << "  Family in OCR corpus, no G 18 complete concepts:     #{xref[:family_in_corpus_no_concepts].size}  ← confirmed no terms OR extraction gap"
    summary << "  Withdrawn (G 18 should REMOVE these):     #{xref[:family_withdrawn].size}"
    summary << "  Family NOT in OCR corpus:                 #{xref[:family_missing_from_corpus].size}  ← need to obtain OCR"
    summary << ""
    summary << "G 18 current concepts missing from G 18:        #{xref[:tip_missing_from_g18].size}"
    summary << ""
    summary << "Withdrawn publications — G 18 entries to REMOVE:"
    withdrawn_cited = xref[:family_withdrawn].map { |e| e[:ref] }.compact.uniq.sort
    if withdrawn_cited.empty?
      summary << "  (none)"
    else
      withdrawn_cited.each do |r|
        n = xref[:family_withdrawn].count { |e| e[:ref] == r }
        summary << "  #{r}  (#{n} entries)"
      end
    end
    summary << ""
    summary << "Publications needing OCR acquisition (unique refs in category 06):"
    refs_needed = xref[:family_missing_from_corpus].map { |e| e[:ref] }.compact.uniq.sort
    if refs_needed.empty?
      summary << "  (none)"
    else
      refs_needed.each { |r| summary << "  #{r}" }
    end
    File.write(OUT_DIR + "08-summary.txt", summary.join("\n") + "\n")
  end
end

options = { build: false }
OptionParser.new do |opts|
  opts.banner = "Usage: ruby scripts/g18_current_vs_g18.rb [--build]"
  opts.on("--build") { options[:build] = true }
end.parse!

g18_dyn = G18CurrentG18.load_g18_current_tip
g18 = G18CurrentG18.load_g18
xref = G18CurrentG18.cross_reference(g18_dyn, g18)
G18CurrentG18.write_reports(g18_dyn, g18, xref)

puts "G 18 current ↔ G 18:202X cross-reference"
puts "=" * 60
puts
puts "G 18:202X entries:        #{xref[:g18_entries_total]}"
puts "G 18 complete unique tip concepts:  #{g18_dyn[:tip_concepts].size}"
puts
puts "G 18 entries — by status:"
puts "  At tip (cites current edition):           #{xref[:at_tip].size}"
puts "  Below tip, clause exists at tip:          #{xref[:below_tip_has_clause].size}"
puts "  Below tip, clause NOT at tip:             #{xref[:below_tip_no_clause].size}"
puts "  No citation in G 18 entry:                #{xref[:no_citation].size}"
puts "  Family in OCR corpus, no G 18 complete concepts:     #{xref[:family_in_corpus_no_concepts].size}"
puts "  Withdrawn (G 18 should REMOVE these):     #{xref[:family_withdrawn].size}"
puts "  Family NOT in OCR corpus:                 #{xref[:family_missing_from_corpus].size}"
puts
puts "G 18 current concepts missing from G 18:        #{xref[:tip_missing_from_g18].size}"
puts
puts "Reports written to: #{OUT_DIR}"
OUT_DIR.children.sort.each do |f|
  puts "  #{f.basename}"
end

if options[:build]
  puts
  puts "Building g18-current dataset..."
  result = G18CurrentG18.build_g18_current_tip_dataset(g18_dyn)
  puts "  Wrote #{result[:written]} concepts to #{result[:out_dir]}"
  puts "  Validating..."
  system("ruby #{REPO_ROOT + 'scripts' + 'validate_datasets.rb'} --datasets g18-current")
end
