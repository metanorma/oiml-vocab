#!/usr/bin/env ruby
# frozen_string_literal: true
#
# One-shot: seed the 101 remaining vim-1984-cor-1987 concept files that are
# textually identical to vim-1984 and only differ in UUIDs, domains source URN,
# and the addition of an `equivalent` related edge back to vim-1984.
#
# Skips files that already exist (hand-authored: 1.01-2.14, 4.10, 5.23).
#
# Run once; do not re-run. Datasets are authoritative after this seeding —
# further edits are hand-curated. See scripts/historical/README.md.
#
#   ruby scripts/historical/seed_vim_1984_cor_1987.rb

require "securerandom"

REPO = File.expand_path("../..", __dir__)
SRC_DIR = File.join(REPO, "datasets", "vim-1984", "concepts")
DST_DIR = File.join(REPO, "datasets", "vim-1984-cor-1987", "concepts")

COR_URN = "urn:oiml:pub:v:2:1984:cor:1:1987"
BASE_URN = "urn:oiml:pub:v:2:1984"

count = 0
Dir.glob(File.join(SRC_DIR, "*.yaml")).sort.each do |src|
  basename = File.basename(src)
  dst = File.join(DST_DIR, basename)
  if File.exist?(dst)
    warn "skip #{basename} (already exists — hand-authored)"
    next
  end

  identifier = basename.sub(/\.yaml\z/, "")
  content = File.read(src)

  # Extract the 3 unique UUIDs in the file (managed, eng, fra).
  old_uuids = content.scan(/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/).uniq
  raise "#{basename}: expected 3 UUIDs, found #{old_uuids.size}" unless old_uuids.size == 3

  # Swap each old UUID for a fresh one (text replacement preserves formatting).
  old_uuids.each do |old|
    content.gsub!(old, SecureRandom.uuid)
  end

  # Change the domains source from V 2:1984 to the corrigendum URN.
  # Only the first occurrence (in domains) — localizations don't carry a source.
  changed = content.sub!("source: #{BASE_URN}\n", "source: #{COR_URN}\n")
  raise "#{basename}: domains source not found" unless changed

  # Insert related block (equivalent edge to vim-1984) before "status: valid".
  related_block = <<~YAML
    related:
    - type: equivalent
      ref:
        source: #{BASE_URN}
        id: '#{identifier}'
  YAML
  inserted = content.sub!("status: valid\n", "#{related_block}status: valid\n")
  raise "#{basename}: status marker not found" unless inserted

  File.write(dst, content)
  count += 1
  puts "wrote #{basename}"
end

warn ""
warn "Done. Seeded #{count} files in #{DST_DIR}"
