#!/usr/bin/env ruby
# frozen_string_literal: true
#
# One-shot: re-target VIM 1993 supersedes edges from V 2:1984 (original) to
# V 2:1984/Cor.1:1987 (canonical corrected form). The corrigendum is what
# VIM 1993 authors would have referenced; the original 1984 print had known
# errors corrected in 1987.
#
# Text-only replacement — no YAML parsing or generation. Preserves formatting.
#
#   ruby scripts/historical/retarget_vim_1993_to_corrigendum.rb

REPO = File.expand_path("../..", __dir__)
VIM_1993 = File.join(REPO, "datasets", "vim-1993", "concepts")

OLD_URN = "urn:oiml:pub:v:2:1984"
NEW_URN = "urn:oiml:pub:v:2:1984:cor:1:1987"

# Match `source: urn:oiml:pub:v:2:1984` at end-of-line (so we don't accidentally
# match the longer corrigendum URN if this script is run twice).
PATTERN = /source: #{Regexp.escape(OLD_URN)}$/

count = 0
Dir.glob(File.join(VIM_1993, "*.yaml")).sort.each do |path|
  content = File.read(path)
  if content.match?(PATTERN)
    content.gsub!(PATTERN, "source: #{NEW_URN}")
    File.write(path, content)
    count += 1
  end
end

warn "Updated #{count} VIM 1993 files: #{OLD_URN} -> #{NEW_URN}"
