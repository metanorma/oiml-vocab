#!/usr/bin/env ruby
# frozen_string_literal: true

# Dataset validation for the oimlsmart/vocab deployment repo.
#
# Runs as a CI gate before the concept-browser build. Exits non-zero on any
# invariant violation so broken data cannot ship to production.
#
# Coverage:
#   1. Parse     — every concept YAML loads cleanly as multi-doc v3
#   2. Schema    — required keys present on each document
#   3. IDs       — concept identifiers are unique within a dataset
#   4. Counts    — register.yaml concepts match files on disk
#   5. i18n      — every concept has localized_concepts for all declared langs
#   6. Sources   — every concept source resolves (URN, register ref/alias,
#                  or bibliography id in the citing dataset)
#   7. Related   — every related ref points to an existing concept
#                  (within the same dataset; cross-dataset refs skipped)
#   8. Bibliography — entries are arrays, ids unique within each file,
#                  every id is actually cited by some concept

require "yaml"
require "set"
require "pathname"
require "optparse"

ROOT = File.expand_path("..", __dir__)
DATASETS_DIR = File.join(ROOT, "datasets")

class DatasetValidator
  attr_reader :errors, :warnings, :collected_uuids

  def initialize(dataset_path)
    @dataset_path = dataset_path
    @id = File.basename(dataset_path)
    @errors = []
    @warnings = []
    @collected_uuids = {} # uuid -> "concepts/X.yaml"
    @concepts_dir = File.join(@dataset_path, "concepts")
    @register = load_register
    @bib_ids = load_bibliography_ids
  end

  def validate
    # Stub datasets (register.yaml only, no concepts yet) — skip gracefully.
    if @register.is_a?(Hash) && @register["status"] == "stub"
      return self
    end

    return error("missing concepts/ directory") unless Dir.exist?(@concepts_dir)

    concept_files = Dir.glob(File.join(@concepts_dir, "*.yaml")).sort
    return error("no concept files found") if concept_files.empty?

    identifiers = {}        # identifier -> file (for dup detection)
    sources_per_file = {}   # file -> [source strings]
    related_per_file = {}   # file -> [{type, source, id}]

    concept_files.each do |path|
      docs = parse_multidoc(path)
      next if docs.nil? # parse error already recorded

      managed = docs.first
      localized = docs[1..]

      schema_check(path, managed, localized)
      collect_identifiers(path, managed, identifiers)
      collect_uuids(path, managed, localized)
      sources_per_file[path] = collect_sources(managed, localized)
      related_per_file[path] = collect_related(managed)
    end

    check_identifier_uniqueness(identifiers)
    check_concept_count(concept_files.size)
    check_i18n_paritity(concept_files.size)
    check_sources_resolve(sources_per_file)
    check_related_resolve(related_per_file)
    check_supersedes_cross_dataset(related_per_file)
    check_bibliography_coverage(sources_per_file)

    self
  end

  private

  def load_register
    path = File.join(@dataset_path, "register.yaml")
    return {} unless File.exist?(path)
    YAML.load_file(path) || {}
  rescue Psych::SyntaxError => e
    error("register.yaml: parse error: #{e.message}")
    {}
  end

  def load_bibliography_ids
    path = File.join(@dataset_path, "bibliography.yaml")
    return Set.new unless File.exist?(path)

    data = YAML.load_file(path)
    unless data.is_a?(Array)
      error("bibliography.yaml: must be a top-level array of entries, got #{data.class}")
      return Set.new
    end

    ids = []
    data.each_with_index do |entry, idx|
      unless entry.is_a?(Hash) && entry["id"]
        error("bibliography.yaml[##{idx}]: missing required `id` field")
        next
      end
      ids << entry["id"]
    end

    dups = ids.group_by { |x| x }.select { |_, v| v.size > 1 }.keys
    dups.each { |d| error("bibliography.yaml: duplicate id #{d.inspect}") }

    Set.new(ids)
  rescue Psych::SyntaxError => e
    error("bibliography.yaml: parse error: #{e.message}")
    Set.new
  end

  def parse_multidoc(path)
    docs = YAML.load_stream(File.read(path))
    docs
  rescue Psych::SyntaxError => e
    error("#{File.basename(path)}: parse error: #{e.message}")
    nil
  end

  def schema_check(path, managed, localized)
    basename = File.basename(path)

    unless managed.is_a?(Hash) && managed["data"].is_a?(Hash)
      return error("#{basename}: first doc must be a managed concept with `data`")
    end

    md = managed["data"]
    %w[identifier localized_concepts domains].each do |key|
      error("#{basename}: managed concept missing data.#{key}") unless md.key?(key)
    end

    %w[status id schema_version].each do |key|
      error("#{basename}: managed concept missing top-level #{key}") unless managed.key?(key)
    end

    langs = (@register["languages"] || [])
    declared = managed["data"]["localized_concepts"] || {}
    missing = langs - declared.keys
    unless missing.empty?
      # Some datasets are intentionally single-language (e.g. viml-1968 French only).
      # Only error if register declares a language the concept doesn't have.
      #
      # Derived / cross-source aggregate datasets (V 0) get a permissive
      # mode: each concept comes from a specific source publication and
      # may be monolingual in any of the dataset's languages. The register
      # still lists every language that appears SOMEWHERE in the dataset,
      # but no single concept is required to be bilingual.
      derived = @register["derived"] == true || @register["i18n_mode"] == "permissive"
      if langs.any? && !derived
        error("#{basename}: missing localized_concepts for #{missing.inspect}")
      end
    end

    if localized.empty?
      error("#{basename}: no localized concept documents found")
    end

    localized.each do |loc|
      next unless loc.is_a?(Hash)
      lang = loc["language_code"] || loc.dig("data", "language_code")
      unless loc["data"].is_a?(Hash) && lang
        error("#{basename}: localized concept missing data or language_code")
      end
    end
  end

  def collect_identifiers(path, managed, identifiers)
    id = managed.dig("data", "identifier")
    return unless id
    if identifiers.key?(id)
      error("#{File.basename(path)}: duplicate identifier #{id.inspect} (also in #{File.basename(identifiers[id])})")
    else
      identifiers[id] = path
    end
  end

  # Collect top-level UUIDs from managed + localized docs for cross-dataset uniqueness check.
  def collect_uuids(path, managed, localized)
    rel = Pathname.new(path).relative_path_from(@dataset_path).to_s
    mid = managed.is_a?(Hash) ? managed["id"] : nil
    @collected_uuids[mid] = rel if mid.is_a?(String)
    localized.each do |loc|
      next unless loc.is_a?(Hash)
      lid = loc["id"]
      @collected_uuids[lid] = rel if lid.is_a?(String)
    end
  end

  def collect_sources(managed, localized)
    sources = Set.new
    collect_from = lambda do |data|
      next unless data.is_a?(Hash)
      (data["sources"] || []).each do |s|
        src = s.dig("origin", "ref", "source")
        sources << src if src
      end
    end
    collect_from.call(managed.is_a?(Hash) ? managed["data"] : nil)
    localized.each { |loc| collect_from.call(loc.is_a?(Hash) ? loc["data"] : nil) }
    sources
  end

  def collect_related(managed)
    related = []
    (managed["related"] || []).each do |r|
      next unless r.is_a?(Hash) && r["ref"].is_a?(Hash)
      related << {
        type: r["type"],
        source: r["ref"]["source"],
        id: r["ref"]["id"],
      }
    end
    related
  end

  def check_identifier_uniqueness(identifiers)
    # Already checked per-file in collect_identifiers; nothing more to do.
  end

  def check_concept_count(file_count)
    return unless @register["concept_count"]
    expected = @register["concept_count"].to_i
    if expected != file_count
      error("register.yaml concept_count=#{expected} but #{file_count} files on disk")
    end
  end

  def check_i18n_paritity(file_count)
    # Per-concept i18n checked in schema_check. This could verify the dataset-level
    # language counts but currently no invariant beyond per-concept.
  end

  def check_sources_resolve(sources_per_file)
    urn_pattern = /\Aurn:/o
    internal_refs = internal_source_refs

    sources_per_file.each do |path, sources|
      basename = File.basename(path)
      sources.each do |src|
        if src =~ urn_pattern
          next # URNs resolve via dataset URN routing; cross-dataset
        elsif internal_refs.include?(src)
          next # ref/refAlias in some register.yaml
        elsif @bib_ids.include?(src)
          next # explicit bibliography entry
        else
          error("#{basename}: source #{src.inspect} resolves to no URN, register ref, or bibliography id")
        end
      end
    end
  end

  def check_related_resolve(related_per_file)
    # Build identifier set for this dataset
    all_ids = Set.new
    Dir.glob(File.join(@concepts_dir, "*.yaml")).each do |path|
      docs = YAML.load_stream(File.read(path)) rescue next
      managed = docs.first
      next unless managed.is_a?(Hash) && managed["data"].is_a?(Hash)
      all_ids << managed["data"]["identifier"].to_s if managed["data"]["identifier"]
    end

    related_per_file.each do |path, related|
      basename = File.basename(path)
      related.each do |r|
        next if r[:source] =~ /\Aurn:/ # cross-dataset URN ref
        next if r[:source].nil? # malformed; skip
        next if all_ids.include?(r[:id].to_s)
        error("#{basename}: related #{r[:type]} ref id=#{r[:id].inspect} source=#{r[:source].inspect} not found in this dataset")
      end
    end
  end

  # For `related[].supersedes` entries with a URN source like
  # `urn:oiml:pub:v:2:YEAR`, verify the target concept exists in
  # `datasets/vim-YEAR/concepts/`. If the target edition isn't in the repo
  # at all (e.g., VIM 1984 not yet populated), warn but don't fail — we
  # can't validate what we don't have.
  def check_supersedes_cross_dataset(related_per_file)
    urn_year = /\Aurn:oiml:pub:v:2:(\d{4})\z/
    related_per_file.each do |path, related|
      basename = File.basename(path)
      related.each do |r|
        next unless r[:type] == "supersedes"
        m = urn_year.match(r[:source].to_s)
        next unless m
        year = m[1]
        target_dir = File.join(DATASETS_DIR, "vim-#{year}", "concepts")
        target_repo_root = File.join(DATASETS_DIR, "vim-#{year}")
        unless Dir.exist?(target_repo_root)
          # Edition not in repo: warn but don't fail
          next
        end
        unless Dir.exist?(target_dir)
          # If target is a stub (register only, no concepts yet), skip silently.
          target_reg = File.join(DATASETS_DIR, "vim-#{year}", "register.yaml")
          if File.exist?(target_reg)
            reg_data = YAML.load_file(target_reg) rescue {}
            if reg_data.is_a?(Hash) && reg_data["status"] == "stub"
              next
            end
          end
          warning("#{basename}: supersedes target edition vim-#{year} has no concepts/ directory")
          next
        end
        target_file = File.join(target_dir, "#{r[:id]}.yaml")
        unless File.exist?(target_file)
          error("#{basename}: supersedes ref id=#{r[:id].inspect} (vim-#{year}) resolves to no concept file")
        end
      end
    end
  end

  def check_bibliography_coverage(sources_per_file)
    return if @bib_ids.empty?

    cited = Set.new
    sources_per_file.each_value { |sources| sources.each { |s| cited << s } }
    cited_non_urn = cited.reject { |s| s =~ /\Aurn:/ }

    orphans = @bib_ids - cited_non_urn
    orphans.each { |o| warning("bibliography id #{o.inspect} is never cited by any concept") }
  end

  def internal_source_refs
    refs = Set.new
    Dir.glob(File.join(DATASETS_DIR, "*/register.yaml")).each do |reg_path|
      begin
        reg = YAML.load_file(reg_path) || {}
      rescue Psych::SyntaxError
        next
      end
      refs << reg["ref"] if reg["ref"]
      (reg["refAliases"] || []).each { |a| refs << a }
    end
    refs
  end

  def error(msg)
    @errors << "[#{@id}] #{msg}"
  end

  def warning(msg)
    @warnings << "[#{@id}] #{msg}"
  end
end

# CLI
options = { datasets: nil }
OptionParser.new do |opts|
  opts.banner = "Usage: ruby scripts/validate_datasets.rb [options]"
  opts.on("--datasets LIST", "Comma-separated dataset ids (default: all)") { |v| options[:datasets] = v.split(",") }
  opts.on("-h", "--help", "Show this help") { puts opts; exit 0 }
end.parse!

dataset_filter = options[:datasets]

datasets = Dir.children(DATASETS_DIR).select do |name|
  File.directory?(File.join(DATASETS_DIR, name)) &&
    File.exist?(File.join(DATASETS_DIR, name, "register.yaml"))
end.sort

datasets = datasets & dataset_filter if dataset_filter

if datasets.empty?
  abort("No datasets found to validate (looked in #{DATASETS_DIR})")
end

total_errors = 0
total_warnings = 0
uuids_global = {} # uuid -> "dataset/concept.yaml" (first occurrence)
datasets.each do |ds|
  validator = DatasetValidator.new(File.join(DATASETS_DIR, ds)).validate
  total_errors += validator.errors.size
  total_warnings += validator.warnings.size

  status = validator.errors.empty? ? (validator.warnings.empty? ? "OK" : "WARN") : "FAIL"
  puts "== #{ds}: #{status} (#{validator.errors.size} errors, #{validator.warnings.size} warnings)"
  validator.errors.each { |e| puts "  ERROR: #{e}" }
  validator.warnings.each { |w| puts "  warn:  #{w}" }

  validator.collected_uuids.each do |uuid, location|
    if uuids_global.key?(uuid)
      total_errors += 1
      puts "  ERROR: [cross-dataset] duplicate UUID #{uuid} in #{ds}/#{location} (also in #{uuids_global[uuid]})"
    else
      uuids_global[uuid] = "#{ds}/#{location}"
    end
  end
end

puts ""
puts "Total: #{total_errors} errors, #{total_warnings} warnings across #{datasets.size} datasets"

exit(total_errors.zero? ? 0 : 1)
