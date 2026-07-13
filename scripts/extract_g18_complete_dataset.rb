#!/usr/bin/env ruby
# frozen_string_literal: true

# Build the OIML G 18 complete cross-publication terminology dataset.
#
# Walks every directory under --source (default: the publications OCR output),
# extracts terminology sections, and writes glossarist v3 YAML to --out
# (default: datasets/g18-complete).
#
# Usage:
#   ruby scripts/extract_v0_dataset.rb
#   ruby scripts/extract_v0_dataset.rb --limit 20
#   ruby scripts/extract_v0_dataset.rb --only r49-1-2013-eng,d11-2013-e
#   ruby scripts/extract_v0_dataset.rb --source PATH --out PATH
#
# Idempotent: re-running overwrites datasets/g18-complete/ with byte-identical content
# (UUID v5 + sorted iteration).

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
require "oiml/g18_complete"

require "optparse"
require "pathname"

REPO_ROOT = File.expand_path("..", __dir__)
DEFAULT_SOURCE = "/Users/mulgogi/src/oimlsmart/publications/reference-docs/ocr-output"
DEFAULT_OUT = File.join(REPO_ROOT, "datasets", "g18-complete")

options = {
  source: DEFAULT_SOURCE,
  out: DEFAULT_OUT,
  limit: nil,
  only: nil,
  quiet: false,
}
OptionParser.new do |opts|
  opts.banner = "Usage: #{$PROGRAM_NAME} [options]"
  opts.on("--source PATH", String, "OCR output root (default: #{DEFAULT_SOURCE})") { |v| options[:source] = v }
  opts.on("--out PATH", String, "Output dataset dir (default: #{DEFAULT_OUT})") { |v| options[:out] = v }
  opts.on("--limit N", Integer, "Process only the first N publications") { |v| options[:limit] = v }
  opts.on("--only LIST", String, "Comma-separated publication directory names to process") { |v| options[:only] = v }
  opts.on("--quiet", "Suppress per-publication progress output") { options[:quiet] = true }
  opts.on("-h", "--help") { puts opts; exit 0 }
end.parse!

source_root = File.expand_path(options[:source])
out_dir = File.expand_path(options[:out])
abort "Source not found: #{source_root}" unless File.directory?(source_root)

extractor = Oiml::G18Complete::Extractor.new(source_root: source_root)
result = extractor.call(limit: options[:limit], only: options[:only]) do |pp|
  next if options[:quiet]
  status = pp.errors.empty? ? "ok" : "ERR"
  $stderr.puts(format("  %-32s %s  sections=%d entries=%d concepts=%d",
                      pp.publication.dataset_id, status,
                      pp.sections_found, pp.entries_found.size, pp.concepts.size))
  pp.errors.each { |e| $stderr.puts("      ! #{e}") }
end

writer = Oiml::G18Complete::DatasetWriter.new(out_dir: out_dir)
writer.write(concepts: result[:concepts],
             publications: result[:publications],
             languages: result[:languages])

total_errors = result[:per_publication].sum { |pp| pp.errors.size }
total_entries = result[:per_publication].sum { |pp| pp.entries_found.size }
$stderr.puts
$stderr.puts(format("Processed %d publications | %d sections | %d entries | %d concepts | %d errors",
                    result[:per_publication].size,
                    result[:per_publication].sum(&:sections_found),
                    total_entries,
                    result[:concepts].size,
                    total_errors))
$stderr.puts("Wrote: #{out_dir}")
