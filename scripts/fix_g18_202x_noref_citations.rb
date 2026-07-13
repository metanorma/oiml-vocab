#!/usr/bin/env ruby
# frozen_string_literal: true

# One-shot: fix the 26 "no citation" G 18:202X entries by adding proper
# source citations extracted from the source HTML, and standardize all
# dedup-suffixed filenames to XXXX-{docslug}.yaml form.
#
# Citations were recovered from
#   reference-docs/TC1_P3_N008-2CD_revision_of_G18-clean.html
# by grepping each concept ID and matching "according to X of R Y:Z"
# patterns in the definition text.

require "yaml"
require "pathname"
require "fileutils"

G18_CONCEPTS = Pathname.new(File.expand_path("../datasets/g18-202X/concepts", __dir__))

# identifier (filename stem) → [ref, clause, version]
# docslug is computed from ref (kind + zero-padded number + part).
FIXES = {
  # Single-occurrence entries — just add citation, keep filename.
  "00594"     => ["OIML R 51:2006",    "T.2.7.8.3",  "2006"],
  "00632"     => ["OIML R 133:2002",   "3.2",        "2002"],
  "00659"     => ["OIML D 11:2013",    "3.24",       "2013"],
  "00687"     => ["OIML R 61-1:2017",  "3.4.6",      "2017"],
  "00924"     => ["OIML R 143:2009",   "2.8",        "2009"],
  "00973"     => ["OIML R 106-1:2011", "0.4.3",      "2011"],
  "01421"     => ["OIML R 112:1994",   "2.11",       "1994"],
  "02495"     => ["OIML R 87:2016",    "2.1.2.3",    "2016"],
  "02571"     => ["OIML R 106-1:2011", "0.1.9",      "2011"],
  "02696"     => ["OIML R 49-1:2024",  "3.4.6",      "2024"],
  "02722"     => ["OIML R 49-1:2024",  "3.1.4",      "2024"],
  "02949"     => ["OIML R 61-1:2017",  "3.3.11.8",   "2017"],
  "02950"     => ["OIML R 150-1:2020", "2.1.10",     "2020"],
  "02955"     => ["OIML R 110:1994",   "2.4.2",      "1994"],
  "03115"     => ["OIML R 106-1:2011", "0.5.1.1",    "2011"],
  "03199"     => ["OIML R 60-1:2021",  "2.1.2",      "2021"],
  "03425"     => ["OIML R 150-1:2020", "2.4.4",      "2020"],
  "03494"     => ["OIML R 91-1:2025",  "3.4.5",      "2025"],
  "03526"     => ["OIML R 82:2006",    "3.6",        "2006"],

  # Dedup-suffixed entries — add citation AND rename to XXXX-{docslug}.yaml
  "02281-1"   => ["OIML R 46-1:2012",  "2.1.2",      "2012"],
  "02289-1"   => ["OIML R 46-1:2012",  "2.2.1",      "2012"],
  "02301-1"   => ["OIML R 81:1998",    "3.9",        "1998"],
  "02302-2"   => ["OIML R 106-1:2011", "0.3.2.2",    "2011"],
  "02309-1"   => ["OIML R 85-1:2008",  "3.11",       "2008"],
  "02339-1"   => ["OIML R 46-1:2012",  "2.2.40",     "2012"],
  "02827-2"   => ["OIML R 147:2016",   "2.2.6",      "2016"],
}.freeze

# Compute the docslug from a ref string.
# "OIML R 49-1:2024" → "R049-1"
# "OIML D 11:2013"   → "D011"
# "OIML R 81:1998"   → "R081"
def docslug_for(ref)
  m = ref.match(/\AOIML\s+([A-Z])\s+(\d+)(?:-(\d+))?:\d{4}\z/)
  return nil unless m
  kind = m[1]
  num = m[2].rjust(3, "0")
  part = m[3]
  part ? "#{kind}#{num}-#{part}" : "#{kind}#{num}"
end

def dump_multi_doc(docs)
  parts = docs.map { |d| YAML.dump(d).sub(/\A---\n/, "") }
  "---\n" + parts.join("---\n") + "\n"
end

FIXES.each do |stem, (ref, clause, version)|
  src_path = G18_CONCEPTS + "#{stem}.yaml"
  unless src_path.exist?
    warn "skip #{stem}: file not found"
    next
  end

  docs = YAML.load_stream(src_path.read)
  changed = false
  docs.each do |doc|
    next unless doc.is_a?(Hash) && doc["data"].is_a?(Hash)
    srcs = doc["data"]["sources"] ||= []
    if srcs.empty?
      srcs << {
        "origin" => { "ref" => { "source" => ref, "version" => version } },
        "locality" => { "type" => "clause", "reference_from" => clause },
        "type" => "authoritative",
      }
      changed = true
    else
      # Update existing
      srcs.each do |s|
        next unless s.is_a?(Hash) && s["origin"] && s["origin"]["ref"]
        s["origin"]["ref"]["source"] = ref
        s["origin"]["ref"]["version"] = version
        s["locality"] ||= { "type" => "clause" }
        s["locality"]["type"] = "clause"
        s["locality"]["reference_from"] = clause
        s["type"] = "authoritative"
        changed = true
      end
    end
  end

  if changed
    # Determine new path: if stem has dedup suffix (-N), rename to XXXX-{docslug}
    if stem =~ /\A(\d+)-(\d+)\z/
      base_id = $1
      slug = docslug_for(ref)
      new_stem = slug ? "#{base_id}-#{slug}" : stem
      new_path = G18_CONCEPTS + "#{new_stem}.yaml"
      if new_path != src_path
        if new_path.exist?
          warn "skip rename #{stem} → #{new_stem}: target exists"
        else
          File.write(new_path, dump_multi_doc(docs))
          File.delete(src_path)
          puts "fixed+renamed #{stem} → #{new_stem}: #{ref} §#{clause}"
          next
        end
      end
      File.write(src_path, dump_multi_doc(docs))
      puts "fixed #{stem} (rename target existed): #{ref} §#{clause}"
    else
      File.write(src_path, dump_multi_doc(docs))
      puts "fixed #{stem}: #{ref} §#{clause}"
    end
  else
    puts "unchanged #{stem}"
  end
end
