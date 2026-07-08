#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Extract concept-relationship data from VIM 2012 (OIML V 2:2012 / v002-e12)
# diagram images using the Z.AI GLM vision model.
#
# Inputs:  reference-docs/v002-200-e12-relationships-images/image-NN.png
# Outputs: reference-docs/v002-200-e12-relationships/image-NN.yaml     (v2 schema)
#          reference-docs/v002-200-e12-relationships/image-NN.run-K.raw.json
#            (per-run raw GLM JSON; only with --save-raw)
#
# Schema:  reference-docs/v002-200-e12-relationships/schema.yaml
#
# Usage:
#   ruby scripts/extract_vim_2012_relationships.rb                       # all images, 1 run
#   ruby scripts/extract_vim_2012_relationships.rb --runs=2              # all images, 2 runs merged
#   ruby scripts/extract_vim_2012_relationships.rb --image=01 --runs=2   # one image
#   ruby scripts/extract_vim_2012_relationships.rb --dry-run
#   ruby scripts/extract_vim_2012_relationships.rb --skip-existing
#   ruby scripts/extract_vim_2012_relationships.rb --model=glm-5v-turbo
#
# Auth:    reads API key from $Z_AI_API_KEY or ~/.zai-api-key
#          (file may be plain key or `export Z_AI_API_KEY=...` form)
#
# Multi-run: with --runs=N, each image's N GLM calls run in N parallel
# threads (concurrency = N). Per-edge `runs:` annotations in the output
# show which runs caught each edge. Edges with conflicting type across
# runs are flagged via `type_conflict: true` and `alternatives:`.

require "base64"
require "fileutils"
require "json"
require "net/http"
require "optparse"
require "pathname"
require "set"
require "stringio"
require "thread"
require "time"
require "yaml"

REPO_ROOT      = Pathname.new(File.expand_path("..", __dir__))
IMAGES_DIR     = REPO_ROOT + "reference-docs/v002-200-e12-relationships-images"
OUT_DIR        = REPO_ROOT + "reference-docs/v002-200-e12-relationships"
SOURCE_PDF     = "reference-docs/v002-200-e12-relationships.pdf"
SOURCE_DOC_URN = "urn:oiml:pub:v:2:2012"
API_ENDPOINT   = URI("https://api.z.ai/api/paas/v4/chat/completions")
DEFAULT_MODEL  = ENV.fetch("GLM_VISION_MODEL", "glm-5v-turbo")
VALID_TYPES    = %w[associative hierarchical partitive partitive_plural].freeze
PROMPT_VERSION = "2026-07-07-v2"

# GLM is asked to return v1-shape JSON; we transform to v2 in Ruby.
PROMPT = <<~PROMPT
  You are analyzing a concept-relationship diagram from the VIM 2012
  (OIML V 2:2012 — International Vocabulary of Metrology).

  Identify every node (concept) and every relationship edge shown in the
  attached image and return them as STRICT JSON.

  ## NODES

  Each in-dataset node displays a term number (e.g. "1.1") and a
  designation (e.g. "quantity"). Some nodes appear in parentheses, like
  "(property)" — those are EXTERNAL concepts that are NOT in the VIM 2012
  dataset.

  - In-dataset node:
      {"id": "1.1", "designation": "quantity", "external": false}
  - External node:
      {"id": "ext_property", "designation": "property", "external": true}

  External node id = "ext_" + slug(designation), where slug = lowercase +
  non-alphanumerics replaced with "_". Example: "Kind of Property" →
  "ext_kind_of_property". The same external concept referenced across
  diagrams MUST get the same id.

  ## RELATIONSHIP TYPES — distinguished by LINE GEOMETRY

  (a) ASSOCIATIVE — arrowed lines (have visible arrowheads). Bidirectional
      "related to".
      {"type": "associative", "members": [<id1>, <id2>]}

  (b) HIERARCHICAL — plain straight lines (no arrowhead, no 90-degree
      bracket). The end where multiple lines converge into a single point
      is the BROADER (parent) concept; the other ends are NARROWER
      (children).
      {"type": "hierarchical",
       "broader": <id>,
       "narrower": {"listed": [<id>, ...], "has_unlisted_others": <bool>}}
      Set has_unlisted_others=true when the diagram shows "{...}", "etc.",
      or a continued line indicating additional unnamed narrower concepts.

  (c) PARTITIVE — bracket lines: lines that turn 90 degrees, forming a
      rake shape. The rake HEAD (the backline / spine) is the
      COMPREHENSIVE concept (the whole); the teeth are the PARTS.
      {"type": "partitive",
       "comprehensive": <id>,
       "parts": {"listed": [<id>, ...], "has_unlisted_others": <bool>}}
      Set has_unlisted_others=true if a continued backline without a tooth
      is shown (one or more partitive concepts not discussed).

  (d) PARTITIVE_PLURAL — same bracket/rake geometry as (c) BUT with at
      least one of these visual markers:
        - close-set double line at the receiver end → indicates that
          several partitive concepts of a given type are involved
        - dashed/broken line → indicates that such plurality is uncertain
      {"type": "partitive_plural",
       "comprehensive": <id>,
       "parts": {"listed": [<id>, ...], "has_unlisted_others": <bool>},
       "markers": {"double_line": <bool>, "dashed": <bool>}}

  ## OUTPUT FORMAT

  Return STRICT JSON ONLY. No markdown fences, no prose. Shape:

  {
    "nodes": [
      {"id": "1.1", "designation": "quantity", "external": false},
      {"id": "ext_property", "designation": "property", "external": true}
    ],
    "relationships": [
      {"id": "rel-001", "type": "associative", "members": ["ext_kind_of_property", "ext_property"]},
      {"id": "rel-002", "type": "hierarchical",
       "broader": "ext_property",
       "narrower": {"listed": ["1.30", "1.1"], "has_unlisted_others": false}}
    ]
  }

  ## RULES

  - node.id MUST be unique within the file.
  - In-dataset node.id MUST be the VIM 2012 concept id verbatim ("1.1",
    "2.11", "5.13", etc.) — quoted as a string.
  - Every id referenced inside a relationship MUST match a node.id.
  - Use "rel-001", "rel-002", ... sequentially for relationship ids.
  - Capture EVERY node and EVERY edge visible in the image. Be exhaustive.
  - Do NOT invent relationships that are not present in the diagram.
  - If the attached image is not a concept-relationship diagram, return:
    {"nodes": [], "relationships": []}
PROMPT

# ============================================================================
# API + helpers
# ============================================================================

def read_api_key
  env = ENV["Z_AI_API_KEY"].to_s.strip
  return env unless env.empty? || env.include?("=")
  raw = Pathname.new("~/.zai-api-key").expand_path.read.strip
  m = raw.match(/\A(?:export\s+)?(?:Z_AI_API_KEY|ZAI_API_KEY)\s*=\s*["']?([^"'\s]+)["']?\z/)
  m ? m[1] : raw
end

def page_number_for(image_path)
  m = image_path.basename.to_s.match(/\Aimage-(\d+)\.png\z/i)
  m ? m[1].to_i : nil
end

def build_request_body(image_path, model)
  b64 = Base64.strict_encode64(image_path.binread)
  {
    "model" => model,
    "messages" => [{
      "role" => "user",
      "content" => [
        { "type" => "text",      "text" => PROMPT },
        { "type" => "image_url",
          "image_url" => { "url" => "data:image/png;base64,#{b64}" } }
      ]
    }],
    "response_format" => { "type" => "json_object" },
    "temperature"     => 0.0
  }
end

def extract_json(content)
  cleaned = content.to_s.dup
  cleaned.gsub!(/\A\s*```(?:json)?\s*\n?/i, "")
  cleaned.gsub!(/\n?\s*```\s*\z/, "")
  JSON.parse(cleaned)
rescue JSON::ParserError => e
  raise "GLM returned non-JSON content (#{e.message}): #{content[0, 500]}"
end

def call_glm_vision(api_key, image_path, model)
  http = Net::HTTP.new(API_ENDPOINT.host, API_ENDPOINT.port).tap do |h|
    h.use_ssl     = true
    h.read_timeout = 600
    h.write_timeout = 120
  end
  req = Net::HTTP::Post.new(API_ENDPOINT.request_uri,
    "Authorization" => "Bearer #{api_key}",
    "Content-Type"  => "application/json")
  req.body = JSON.generate(build_request_body(image_path, model))
  res = http.request(req)
  unless res.is_a?(Net::HTTPSuccess)
    raise "HTTP #{res.code}: #{res.body[0, 500]}"
  end
  json = JSON.parse(res.body)
  raise "API error: #{json.inspect}" if json["error"] || json["code"]
  content = json.dig("choices", 0, "message", "content")
  raise "No content in response: #{json.inspect}" unless content
  extract_json(content)
end

# ============================================================================
# Per-run validation (v1 shape from GLM)
# ============================================================================

def validate!(data)
  raise "Top-level JSON must be an object" unless data.is_a?(Hash)
  nodes = data["nodes"]
  rels  = data["relationships"]
  raise "Missing or non-array `nodes`"        unless nodes.is_a?(Array)
  raise "Missing or non-array `relationships`" unless rels.is_a?(Array)

  node_ids = Set.new
  nodes.each do |n|
    raise "Node must be an object: #{n.inspect}"    unless n.is_a?(Hash)
    raise "Node missing id: #{n.inspect}"           unless n["id"]
    raise "Node missing designation: #{n.inspect}"  unless n["designation"]
    raise "Duplicate node id: #{n['id']}"           if node_ids.include?(n["id"])
    node_ids << n["id"]
  end

  rels.each_with_index do |r, i|
    raise "Relationship must be an object: #{r.inspect}" unless r.is_a?(Hash)
    type = r["type"]
    raise "Relationship #{i} has unknown type #{type.inspect}" unless VALID_TYPES.include?(type)

    case type
    when "associative"
      members = r["members"]
      raise "associative rel #{i} missing members[]" unless members.is_a?(Array)
      (members - node_ids.to_a).each { |bad| raise "associative rel #{i} references unknown node #{bad.inspect}" }
    when "hierarchical"
      check_ref!(r, "broader", node_ids, i)
      sub = r["narrower"]
      raise "hierarchical rel #{i} missing narrower{}" unless sub.is_a?(Hash)
      listed = sub["listed"]
      raise "hierarchical rel #{i} narrower.listed must be an array" unless listed.is_a?(Array)
      (listed - node_ids.to_a).each { |bad| raise "hierarchical rel #{i} references unknown narrower #{bad.inspect}" }
    when "partitive", "partitive_plural"
      check_ref!(r, "comprehensive", node_ids, i)
      sub = r["parts"]
      raise "#{type} rel #{i} missing parts{}" unless sub.is_a?(Hash)
      listed = sub["listed"]
      raise "#{type} rel #{i} parts.listed must be an array" unless listed.is_a?(Array)
      (listed - node_ids.to_a).each { |bad| raise "#{type} rel #{i} references unknown part #{bad.inspect}" }
      if type == "partitive_plural"
        markers = r["markers"] || {}
        raise "partitive_plural rel #{i} needs at least one marker" unless markers["double_line"] || markers["dashed"]
      end
    end
  end
end

def check_ref!(rel, key, node_ids, i)
  ref = rel[key]
  return if node_ids.include?(ref)
  raise "rel #{i} (#{rel['type']}) #{key} references unknown node #{ref.inspect}"
end

# ============================================================================
# Multi-run execution (N parallel threads)
# ============================================================================

def extract_runs_parallel(api_key, image_path, model, n_runs, raw_basename_dir)
  runs = Array.new(n_runs)
  threads = n_runs.times.map do |i|
    run_num = i + 1
    Thread.new do
      Thread.current.abort_on_exception = false
      begin
        data = call_glm_vision(api_key, image_path, model)
        validate!(data)
        runs[i] = data
        if raw_basename_dir
          raw_path = raw_basename_dir + "#{image_path.basename('.png')}.run-#{run_num}.raw.json"
          raw_path.write(JSON.pretty_generate(data))
        end
        warn "    run #{run_num}: ok (#{data['nodes'].size} nodes, #{data['relationships'].size} rels)"
      rescue => e
        warn "    run #{run_num}: FAIL #{e.message}"
        runs[i] = nil
      end
    end
  end
  threads.each(&:join)
  runs
end

# ============================================================================
# Merge logic
# ============================================================================

def canonical_key(rel)
  case rel["type"]
  when "associative"
    "assoc|#{rel["members"].sort.join(",")}"
  when "hierarchical"
    narrow = (rel["narrower"] || {})["listed"].to_a.sort
    "hier|#{rel["broader"]}|#{narrow.join(",")}"
  when "partitive", "partitive_plural"
    parts = (rel["parts"] || {})["listed"].to_a.sort
    "#{rel["type"]}|#{rel["comprehensive"]}|#{parts.join(",")}"
  end
end

# Returns merged structure:
#   { nodes: {id => designation}, by_type: {type => [edge, ...]},
#     n_runs:, n_valid: }
def merge_runs(runs)
  valid = runs.each_with_index.filter_map { |r, i| r ? [i + 1, r] : nil }
  raise "All runs failed" if valid.empty?

  # Union nodes (id → designation). Strip parens from external designations.
  nodes = {}
  valid.each do |_, run|
    run["nodes"].each do |n|
      designation = n["designation"].to_s.gsub(/\A\(|\)\z/, "")
      nodes[n["id"]] ||= designation
    end
  end

  # Group by canonical key
  groups = {}
  valid.each do |run_num, run|
    run["relationships"].each do |rel|
      key = canonical_key(rel)
      groups[key] ||= { runs: [], by_type: {} }
      groups[key][:runs] << run_num
      groups[key][:by_type][rel["type"]] ||= []
      groups[key][:by_type][rel["type"]] << rel
    end
  end

  by_type = { "associative" => [], "hierarchical" => [],
              "partitive" => [], "partitive_plural" => [] }
  groups.each_value do |info|
    runs_for_edge = info[:runs].uniq.sort
    sorted_types = info[:by_type].sort_by { |_, v| -v.size }
    primary_type, primary_variants = sorted_types.first
    edge = build_merged_edge(primary_type, primary_variants, runs_for_edge)
    if sorted_types.size > 1
      edge["type_conflict"] = true
      edge["alternatives"] = sorted_types[1..].map do |t, v|
        build_merged_edge(t, v, runs_for_edge)
      end
    end
    by_type[primary_type] << edge
  end

  { nodes: nodes, by_type: by_type, n_runs: runs.size, n_valid: valid.size }
end

def build_merged_edge(type, variants, runs)
  base = variants.first
  edge = case type
  when "associative"
    { "members" => base["members"].dup }
  when "hierarchical"
    narrow = base["narrower"] || {}
    {
      "broader"  => base["broader"],
      "narrower" => narrow["listed"].to_a.dup,
      "others"   => !!narrow["has_unlisted_others"],
    }
  when "partitive", "partitive_plural"
    parts = base["parts"] || {}
    e = {
      "comprehensive" => base["comprehensive"],
      "parts"         => parts["listed"].to_a.dup,
      "others"        => !!parts["has_unlisted_others"],
    }
    if type == "partitive_plural"
      markers = base["markers"] || {}
      m = []
      m << "double" if markers["double_line"]
      m << "dashed" if markers["dashed"]
      e["markers"] = m
    end
    e
  end
  edge["runs"] = runs
  edge["status"] = "draft"
  edge
end

# ============================================================================
# YAML emission (v2) — custom for editor-friendly formatting
# ============================================================================

def yaml_quote_id(id)
  id.to_s.match?(/\A\d/) ? "'#{id}'" : id.to_s
end

def yaml_quote_string(s)
  # Use single quotes for simple strings; escape only if needed.
  if s.match?(/[:#{}\[\],&*?|\-<>=!%@`"'\n]/)
    s.inspect
  else
    "\"#{s}\""
  end
end

def emit_flow_list(items, with_others: false)
  parts = items.map { |x| yaml_quote_id(x) }
  parts << "..." if with_others
  "[" + parts.join(", ") + "]"
end

def emit_extras(edge, indent: "    ", always_runs: false)
  extras = []
  if edge["markers"] && !edge["markers"].empty?
    extras << "markers: [#{edge['markers'].join(', ')}]"
  end
  if edge["runs"].is_a?(Array) && (always_runs || edge["runs"].size > 1)
    extras << "runs: [#{edge['runs'].join(', ')}]"
  end
  if edge["status"] && edge["status"] != "draft"
    extras << "status: #{edge['status']}"
  end
  if edge["note"]
    extras << "note: #{yaml_quote_string(edge['note'])}"
  end
  if edge["type_conflict"]
    extras << "type_conflict: true"
  end
  if edge["alternatives"]
    extras << "alternatives:"
    edge["alternatives"].each do |alt|
      extras << "  - type: #{alt['type'] || 'associative'}"
      case alt["type"]
      when "hierarchical"
        extras << "    broader: #{yaml_quote_id(alt['broader'])}"
        extras << "    narrower: #{emit_flow_list(alt['narrower'], with_others: alt['others'])}"
      when "partitive", "partitive_plural"
        extras << "    comprehensive: #{yaml_quote_id(alt['comprehensive'])}"
        extras << "    parts: #{emit_flow_list(alt['parts'], with_others: alt['others'])}"
      when "associative"
        extras << "    members: #{emit_flow_list(alt['members'])}"
      end
    end
  end
  extras.map { |e| "#{indent}#{e}" }
end

def emit_associative(edge, always_runs: false)
  members = emit_flow_list(edge["members"])
  extras = emit_extras(edge, always_runs: always_runs)
  if extras.empty?
    "  - #{members}"
  else
    (["  - members: #{members}"] + extras).join("\n")
  end
end

def emit_hierarchical(edge, always_runs: false)
  broader = yaml_quote_id(edge["broader"])
  narrower = emit_flow_list(edge["narrower"], with_others: edge["others"])
  extras = emit_extras(edge, always_runs: always_runs)
  lines = ["  - broader: #{broader}", "    narrower: #{narrower}"] + extras
  lines.join("\n")
end

def emit_partitive(edge, always_runs: false)
  comp = yaml_quote_id(edge["comprehensive"])
  parts = emit_flow_list(edge["parts"], with_others: edge["others"])
  extras = emit_extras(edge, always_runs: always_runs)
  lines = ["  - comprehensive: #{comp}", "    parts: #{parts}"] + extras
  lines.join("\n")
end

def emit_partitive_plural(edge, always_runs: false)
  emit_partitive(edge, always_runs: always_runs)
end

def emit_v2(io, merged, image_path, page, model, n_runs)
  basename = image_path.basename
  rel_path = "reference-docs/v002-200-e12-relationships-images/#{basename}"
  always_runs = merged[:n_runs] > 1

  io.puts "---"
  io.puts "# Concept-relationship diagram — VIM 2012 (OIML V 2:2012)"
  io.puts "# Source: #{rel_path}"
  io.puts "# Extracted by #{model} (#{merged[:n_valid]}/#{merged[:n_runs]} runs succeeded)"
  io.puts "# Review: set `status` per edge (draft → confirmed | corrected | rejected)."
  io.puts "# Schema: reference-docs/v002-200-e12-relationships/schema.yaml"
  io.puts ""
  io.puts "schema_version:  '2'"
  io.puts "diagram_type:    concept_relationship_diagram"
  io.puts "dataset_urn:     #{SOURCE_DOC_URN}"
  io.puts "source_image:    #{rel_path}"
  io.puts "source_page:     #{page}"
  io.puts "source_pdf:      #{SOURCE_PDF}"
  io.puts ""
  io.puts "extracted_by:    #{model}"
  io.puts "extracted_at:    \"#{Time.now.utc.iso8601}\""
  io.puts "extraction_runs: #{merged[:n_runs]}   # #{merged[:n_valid]} succeeded"
  io.puts "editor_status:   draft   # draft | in_review | reviewed | confirmed"
  io.puts "reviewers:       []"
  io.puts ""

  # Nodes — externals first (sorted), then in-dataset (sorted)
  io.puts "# Nodes (id → designation). 'ext_' prefix = external (in parens on diagram)."
  io.puts "nodes:"
  external, dataset = merged[:nodes].partition { |id, _| id.to_s.start_with?("ext_") }
  external.sort.each { |id, d| io.puts "  #{id}: #{d}" }
  dataset.sort.each { |id, d| io.puts "  #{yaml_quote_id(id)}: #{d}" }
  io.puts ""

  io.puts "relationships:"
  by_type = merged[:by_type]

  io.puts "  # (a) Associative — arrowed line, bidirectional."
  io.puts "  #     Compact form: [a, b]."
  io.puts "  associative:"
  sort_edges(by_type["associative"] || [], "associative").each { |e| io.puts emit_associative(e, always_runs: always_runs) }
  io.puts ""

  io.puts "  # (b) Hierarchical — straight line: broader → narrower."
  io.puts "  #     Trailing `...` in narrower = unlisted others on diagram."
  io.puts "  hierarchical:"
  sort_edges(by_type["hierarchical"] || [], "hierarchical").each { |e| io.puts emit_hierarchical(e, always_runs: always_runs) }
  io.puts ""

  io.puts "  # (c) Partitive — bracket rake: comprehensive → parts."
  io.puts "  partitive:"
  sort_edges(by_type["partitive"] || [], "partitive").each { |e| io.puts emit_partitive(e, always_runs: always_runs) }
  io.puts ""

  io.puts "  # (d) Partitive-plural — bracket rake with [double] and/or [dashed] markers."
  io.puts "  #     INDEPENDENT HYPEREDGE — see schema."
  io.puts "  partitive_plural:"
  sort_edges(by_type["partitive_plural"] || [], "partitive_plural").each { |e| io.puts emit_partitive_plural(e, always_runs: always_runs) }
end

# Deterministic sort within each type so output is reproducible regardless
# of which GLM run returns first. Multi-run-agreed edges first (more runs
# = higher confidence), then alphabetical by canonical key.
def sort_edges(edges, type)
  edges.sort_by do |e|
    runs_count = -(e["runs"] || []).size   # more runs sorts earlier
    key = case type
    when "associative"      then (e["members"] || []).sort.join(",")
    when "hierarchical"     then [(e["broader"] || "").to_s, (e["narrower"] || []).sort.join(",")]
    when "partitive", "partitive_plural"
      [(e["comprehensive"] || "").to_s, (e["parts"] || []).sort.join(",")]
    end
    [runs_count, key]
  end
end

# ============================================================================
# CLI + main
# ============================================================================

options = {
  model:         DEFAULT_MODEL,
  dry_run:       false,
  only:          nil,
  skip_existing: false,
  save_raw:      false,
  out_dir:       OUT_DIR,
  runs:          1
}
OptionParser.new do |opts|
  opts.banner = "Usage: extract_vim_2012_relationships.rb [options]"
  opts.on("--image=N",        "Process only image N (e.g. --image=01)")   { |v| options[:only] = v }
  opts.on("--model=NAME",     "GLM vision model name")                    { |v| options[:model] = v }
  opts.on("--runs=N",         "Run N times per image (parallel) and merge") { |v| options[:runs] = v.to_i }
  opts.on("--dry-run",        "Don't write output files")                 { options[:dry_run] = true }
  opts.on("--skip-existing",  "Skip images that already have output")     { options[:skip_existing] = true }
  opts.on("--save-raw",       "Save per-run raw GLM JSON")                { options[:save_raw] = true }
  opts.on("--out-dir=PATH",   "Output directory")                         { |v| options[:out_dir] = Pathname.new(v) }
end.parse!

options[:runs] = 1 if options[:runs] < 1

images = Pathname.glob((IMAGES_DIR + "image-*.png").to_s).sort
images.select! { |p| p.basename.to_s == "image-#{options[:only]}.png" } if options[:only]
abort "No matching images found in #{IMAGES_DIR}" if images.empty?

api_key = read_api_key
FileUtils.mkdir_p(options[:out_dir]) unless options[:dry_run]

ok_count = 0
err_count = 0
images.each do |image_path|
  page = page_number_for(image_path)
  out_yaml = options[:out_dir] + "#{image_path.basename('.png')}.yaml"
  if options[:skip_existing] && out_yaml.exist?
    warn "SKIP #{image_path.basename} (#{out_yaml} exists)"
    next
  end

  warn "Processing #{image_path.basename} (page #{page}) model=#{options[:model]} runs=#{options[:runs]}"
  begin
    raw_dir = options[:save_raw] && !options[:dry_run] ? options[:out_dir] : nil
    runs = extract_runs_parallel(api_key, image_path, options[:model], options[:runs], raw_dir)
    merged = merge_runs(runs)

    if options[:dry_run]
      warn "  (dry-run) nodes=#{merged[:nodes].size} " \
           "assoc=#{merged[:by_type]['associative'].size} " \
           "hier=#{merged[:by_type]['hierarchical'].size} " \
           "part=#{merged[:by_type]['partitive'].size} " \
           "pp=#{merged[:by_type]['partitive_plural'].size}"
    else
      io = StringIO.new
      emit_v2(io, merged, image_path, page, options[:model], options[:runs])
      out_yaml.write(io.string)
      warn "  Wrote #{out_yaml} (nodes=#{merged[:nodes].size}, " \
           "total rels=#{merged[:by_type].values.sum(&:size)})"
    end
    ok_count += 1
  rescue => e
    warn "  ERROR on #{image_path.basename}: #{e.message}"
    err_count += 1
  end
end

warn "Done. ok=#{ok_count} err=#{err_count}"
exit 1 if err_count.positive?
