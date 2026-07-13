#!/usr/bin/env ruby
# frozen_string_literal: true

# One-shot: apply 6 surgical citation corrections to G 18:202X entries
# per editor instruction. Each correction updates the source ref (and
# nothing else) so the entry points to the correct OIML publication.

require "yaml"
require "pathname"

G18_CONCEPTS = Pathname.new(File.expand_path("../datasets/g18-202X/concepts", __dir__))

# identifier -> new ref
CORRECTIONS = {
  "03790" => ["OIML R 91-1:2025", "2025"],
  "01981" => ["OIML R 138:2007", "2007"],
  "01695" => ["OIML R 128:2000", "2000"],
  "03278" => ["OIML D 10:2022", "2022"],
  "00115" => ["OIML B 10-1:2004", "2004"],
  "03108" => ["OIML R 139-1:2018", "2018"],
}.freeze

def dump_multi_doc(docs)
  parts = docs.map { |d| YAML.dump(d).sub(/\A---\n/, "") }
  "---\n" + parts.join("---\n") + "\n"
end

CORRECTIONS.each do |id, (new_ref, new_version)|
  path = G18_CONCEPTS + "#{id}.yaml"
  unless path.exist?
    warn "skip #{id}: file not found"
    next
  end
  docs = YAML.load_stream(path.read)
  changed = false
  docs.each do |doc|
    next unless doc.is_a?(Hash) && doc["data"].is_a?(Hash)
    srcs = doc["data"]["sources"]
    next unless srcs.is_a?(Array)
    srcs.each do |s|
      next unless s.is_a?(Hash) && s["origin"] && s["origin"]["ref"]
      old_ref = s["origin"]["ref"]["source"]
      old_version = s["origin"]["ref"]["version"]
      if old_ref != new_ref || old_version != new_version
        s["origin"]["ref"]["source"] = new_ref
        s["origin"]["ref"]["version"] = new_version
        changed = true
      end
    end
  end
  if changed
    File.write(path, dump_multi_doc(docs))
    puts "fixed #{id}: → #{new_ref}"
  else
    puts "unchanged #{id}"
  end
end
