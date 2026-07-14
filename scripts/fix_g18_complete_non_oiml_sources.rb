#!/usr/bin/env ruby
# frozen_string_literal: true

# Fix-up: move non-OIML source citations back to notes. The citation
# migration was too aggressive — ISO/IEC refs don't resolve in the
# bibliography and cause validator errors. Keep only OIML VIM/VIML/D
# citations as structured sources; put ISO/IEC back as notes.

require "yaml"
require "pathname"

CONCEPTS = Pathname.new(File.expand_path("../datasets/g18-complete/concepts", __dir__))

OIML_ONLY = /\A(OIML\s+[VDGRBEPS]|VIM|VIML)/i

def dump_multi_doc(docs)
  parts = docs.map { |d| YAML.dump(d).sub(/\A---\n/, "") }
  "---\n" + parts.join("---\n") + "\n"
end

files = Dir.glob(File.join(CONCEPTS, "*.yaml")).sort
moved = 0
files_changed = 0

files.each do |path|
  docs = YAML.load_stream(File.read(path))
  changed = false

  docs.each do |doc|
    next unless doc.is_a?(Hash) && doc["data"].is_a?(Hash)
    data = doc["data"]
    srcs = data["sources"]
    next unless srcs.is_a?(Array) && srcs.size > 1

    # Partition sources: keep OIML-internal, move non-OIML to notes
    kept = []
    moved_srcs = []
    srcs.each do |s|
      ref = s.is_a?(Hash) ? s.dig("origin", "ref", "source") : nil
      if ref && ref.match?(OIML_ONLY)
        kept << s
      elsif ref && !ref.match?(OIML_ONLY)
        clause = s.dig("locality", "reference_from")
        note_text = "Source citation: #{ref}"
        note_text += " #{clause}" if clause
        moved_srcs << note_text
      else
        kept << s
      end
    end

    next if moved_srcs.empty?

    data["sources"] = kept
    data["notes"] ||= []
    moved_srcs.each { |t| data["notes"] << { "content" => t } }
    moved += moved_srcs.size
    changed = true
  end

  next unless changed
  File.write(path, dump_multi_doc(docs))
  files_changed += 1
end

puts "Moved #{moved} non-OIML sources back to notes across #{files_changed} files"
