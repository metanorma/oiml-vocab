#!/usr/bin/env ruby
# frozen_string_literal: true

# Scrape the OIML G 18 controlled vocabulary from digilab.ptb.de (TemaTres 3.6).
#
# The site exposes a JSON web service at services.php and HTML term pages at
# index.php?tema=N. This scraper pulls both:
#
#   1. services.php?task=fetchVocabularyData    — overall stats (sanity check)
#   2. services.php?task=letter&arg=X           — one list per letter A-Z
#   3. services.php?task=fetchTerm&arg=N        — basic term metadata
#   4. services.php?task=fetchNotes&arg=N       — DF (definition) + NC (cataloger's) notes
#   5. services.php?task=fetchDirectTerms&arg=N — broader / narrower / related terms
#   6. index.php?tema=N                         — the human-readable HTML page
#
# Everything is cached under reference-docs/g018-2010-ptb/raw/ so that subsequent
# runs are idempotent (skips files that already exist). Parse + compare against
# datasets/g18-2010/ is done by parse_g18_ptb.rb and compare_g18_ptb.rb.
#
# READ-ONLY on datasets/. Does not modify the canonical YAML.
#
# Usage:
#   ruby scripts/scrape_g18_ptb.rb                    # full scrape, 4 threads
#   ruby scripts/scrape_g18_ptb.rb --threads 8        # more parallelism
#   ruby scripts/scrape_g18_ptb.rb --delay 0.05       # less polite
#   ruby scripts/scrape_g18_ptb.rb --no-html          # skip HTML cache
#   ruby scripts/scrape_g18_ptb.rb --refresh          # re-fetch even if cached
#   ruby scripts/scrape_g18_ptb.rb --letters A,M,P    # only given letters
#   ruby scripts/scrape_g18_ptb.rb --max-terms 50     # stop early (smoke test)

require "net/http"
require "uri"
require "json"
require "optparse"
require "fileutils"
require "time"
require "set"
require "thread"

BASE = "https://digilab.ptb.de/oiml-g-18/vocab"
BASE_URI = URI(BASE)
repo_root = File.expand_path("..", __dir__)
OUT_ROOT  = File.join(repo_root, "reference-docs", "g018-2010-ptb")
RAW_ROOT  = File.join(OUT_ROOT, "raw")
MANIFEST  = File.join(RAW_ROOT, "manifest.json")

# Letters shown on the site's A-Z pager (no K, X, Y in this vocabulary). The
# non-letter terms (e.g. "(permanent) magnetization") are found via gap-fill
# below, not via a "?" letter — services.php returns 0 for that.
LETTERS = %w[A B C D E F G H I J L M N O P Q R S T U V W Z].freeze

options = {
  delay: 0.1,
  threads: 4,
  html: true,
  refresh: false,
  letters: nil,
  max_terms: nil,
  timeout: 60,
}
OptionParser.new do |opts|
  opts.banner = "Usage: #{$PROGRAM_NAME} [options]"
  opts.on("--delay SEC", Float, "Polite delay between HTTP requests per thread") { |v| options[:delay] = v }
  opts.on("--threads N", Integer, "Concurrent workers (each with its own keep-alive HTTP)") { |v| options[:threads] = v }
  opts.on("--[no-]html", "Cache HTML term pages (default: yes)") { |v| options[:html] = v }
  opts.on("--refresh", "Re-fetch even if a cached file exists") { options[:refresh] = true }
  opts.on("--letters LIST", String, "Comma-separated letters to scrape (default: all)") do |v|
    options[:letters] = v.split(",").map(&:strip)
  end
  opts.on("--max-terms N", Integer, "Stop after N term fetches (smoke test)") { |v| options[:max_terms] = v }
  opts.on("--timeout SEC", Integer, "Per-request HTTP timeout") { |v| options[:timeout] = v }
  opts.on("-h", "--help") { puts opts; exit 0 }
end.parse!

letters = options[:letters] || LETTERS
bad = letters - LETTERS
abort "Unknown letters: #{bad.inspect}. Valid: #{LETTERS.inspect}" unless bad.empty?

FileUtils.mkdir_p(File.join(RAW_ROOT, "letters"))
FileUtils.mkdir_p(File.join(RAW_ROOT, "terms"))
FileUtils.mkdir_p(File.join(RAW_ROOT, "notes"))
FileUtils.mkdir_p(File.join(RAW_ROOT, "direct"))
FileUtils.mkdir_p(File.join(RAW_ROOT, "html")) if options[:html]

# One persistent Net::HTTP per caller. Keep-alive avoids a TLS handshake on
# every request — the difference between ~7s/term and ~0.5s/term to this host.
def open_http(uri, timeout:)
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = uri.scheme == "https"
  http.read_timeout = timeout
  http.open_timeout = timeout
  http.keep_alive_timeout = 60
  http.max_retries = 0
  http.start
  http
end

# GET with retries on transient errors. 5xx and network errors retry with
# linear backoff; 4xx is a real "not found" and is not retried.
def http_get(http, url, timeout:, retries: 3)
  uri = URI(url)
  attempts = 0
  loop do
    attempts += 1
    begin
      req = Net::HTTP::Get.new(uri.request_uri, "User-Agent" => "oimlsmart-vocab-scrape/1.0")
      res = http.request(req)
      return [res.code.to_i, res.body] if res.code.to_i < 500
      raise "HTTP #{res.code}"
    rescue StandardError => e
      raise e if attempts > retries
      sleep(attempts * 2)
      # If the keep-alive connection died, the next request on this http will
      # transparently reconnect (Net::HTTP handles EOFError on retry).
    end
  end
end

# Cache one URL response. Returns parsed JSON (as_json) or raw String.
# Skips when the file already exists and --refresh is not set.
def cache(http, url, path, as_json:, delay:, timeout:, refresh:)
  if File.exist?(path) && !refresh && File.size(path) > 0
    return as_json ? JSON.parse(File.read(path)) : File.read(path)
  end
  sleep(delay) if delay > 0
  code, body = http_get(http, url, timeout: timeout)
  if code != 200
    File.write(path + ".failed", "#{code}\n#{body.to_s.slice(0, 500)}\n") unless File.exist?(path + ".failed")
    return nil
  end
  File.delete(path + ".failed") if File.exist?(path + ".failed")
  File.write(path, body)
  as_json ? JSON.parse(body) : body
end

MANIFEST_MUTEX = Mutex.new
PRINT_MUTEX = Mutex.new

def update_manifest(manifest, term_id, fields)
  MANIFEST_MUTEX.synchronize do
    manifest[term_id] ||= {}
    manifest[term_id].merge!(fields)
  end
end

# Extract the G18 concept id from a TemaTres display string. TemaTres appends
# " #NNNNN" to every term string, but the source data is inconsistent: some
# strings pad to 5 digits (#01457), some don't (#1876 → 01876), some put a
# space after the hash (# 01069). Tolerate all; zero-pad to match YAML.
CONCEPT_ID_RE = /#\s*(\d{1,5})\s*\z/
def extract_concept_id(str)
  m = str.to_s.match(CONCEPT_ID_RE)
  m && m[1].rjust(5, "0")
end

puts "G 18 PTB scraper"
puts "  base: #{BASE}"
puts "  out:  #{OUT_ROOT}"
puts "  threads: #{options[:threads]}, delay: #{options[:delay]}s, html: #{options[:html]}, refresh: #{options[:refresh]}"
puts

# --- 1. Vocabulary data (sanity check) ------------------------------------
http_main = open_http(BASE_URI, timeout: options[:timeout])
vocab_path = File.join(RAW_ROOT, "vocabulary.json")
vocab = cache(http_main, "#{BASE}/services.php?task=fetchVocabularyData&output=json",
              vocab_path, as_json: true, delay: 0, timeout: options[:timeout], refresh: options[:refresh])
if vocab
  cant = vocab.dig("result", "cant_terms")
  puts "  Vocabulary reports #{cant} terms"
end

# --- 2. Letter indexes ----------------------------------------------------
manifest = if File.exist?(MANIFEST) && !options[:refresh]
             JSON.parse(File.read(MANIFEST))
           else
             {}
           end

puts "  Fetching #{letters.size} letter indexes..."
letters.each do |letter|
  path = File.join(RAW_ROOT, "letters", "#{letter}.json")
  data = cache(http_main, "#{BASE}/services.php?task=letter&arg=#{letter}&output=json",
               path, as_json: true, delay: options[:delay], timeout: options[:timeout], refresh: options[:refresh])
  next unless data
  items = data["result"] || {}
  items.each do |tid, v|
    s = v["string"].to_s
    update_manifest(manifest, tid, "string" => s, "concept_id" => extract_concept_id(s), "letter" => letter)
  end
  puts "    letter #{letter}: #{items.size} terms"
end

# --- Gap fill: non-alphabetic terms ---------------------------------------
# services.php?task=letter does not return non-alpha terms for this vocabulary.
# Discover gaps in 1..max_seen by fetching them individually.
existing = manifest.keys.map(&:to_i).to_set
max_seen = existing.max || 0
gap_terms = (1..max_seen).reject { |i| existing.include?(i) }
gap_terms.each do |tid|
  path = File.join(RAW_ROOT, "terms", "#{tid}.json")
  term = cache(http_main, "#{BASE}/services.php?task=fetchTerm&arg=#{tid}&output=json",
               path, as_json: true, delay: options[:delay], timeout: options[:timeout], refresh: options[:refresh])
  next unless term && term["result"] && term["result"]["term"]
  tm = term["result"]["term"]
  s = tm["string"].to_s
  update_manifest(manifest, tid.to_s, "string" => s, "concept_id" => extract_concept_id(s),
                  "letter" => "(gap)", "date_create" => tm["date_create"],
                  "code" => tm["code"], "lang" => tm["lang"])
  puts "    gap term_id=#{tid}: #{s.slice(0, 80).inspect} → concept_id=#{extract_concept_id(s)}"
end

term_ids = manifest.keys
puts "  Discovered #{term_ids.size} unique term_ids across all letters + gaps"

if vocab
  expected = vocab.dig("result", "cant_terms").to_i
  if expected > 0 && term_ids.size != expected
    warn "  WARNING: vocabulary reports #{expected} terms but we found #{term_ids.size}"
  end
end

http_main.finish

# --- 3-6. Per-term fetches (parallel) -------------------------------------
limit = options[:max_terms]
work = term_ids.sort_by(&:to_i)
work = work.first(limit) if limit
puts "  Fetching per-term data for #{work.size} terms with #{options[:threads]} threads..."

queue = Queue.new
work.each { |tid| queue << tid }
options[:threads].times.each { queue << nil }  # one sentinel per worker

fetched = 0
fetched_mutex = Mutex.new
start_time = Time.now

threads = options[:threads].times.map do |worker_id|
  Thread.new do
    http = open_http(BASE_URI, timeout: options[:timeout])
    while (tid = queue.pop)
      break if tid.nil?

      # term metadata
      tpath = File.join(RAW_ROOT, "terms", "#{tid}.json")
      term = cache(http, "#{BASE}/services.php?task=fetchTerm&arg=#{tid}&output=json",
                   tpath, as_json: true, delay: options[:delay], timeout: options[:timeout], refresh: options[:refresh])
      if term && term["result"] && term["result"]["term"]
        tm = term["result"]["term"]
        update_manifest(manifest, tid, "date_create" => tm["date_create"], "code" => tm["code"], "lang" => tm["lang"])
      end

      # notes (definition + cataloger's notes)
      npath = File.join(RAW_ROOT, "notes", "#{tid}.json")
      notes = cache(http, "#{BASE}/services.php?task=fetchNotes&arg=#{tid}&output=json",
                    npath, as_json: true, delay: options[:delay], timeout: options[:timeout], refresh: options[:refresh])
      if notes && notes["result"]
        by_type = notes["result"].each_with_object(Hash.new { |h, k| h[k] = 0 }) do |(_, n), h|
          h[n["note_type"]] += 1
        end
        update_manifest(manifest, tid, "note_counts" => by_type)
      end

      # direct terms (broader / narrower / related)
      dpath = File.join(RAW_ROOT, "direct", "#{tid}.json")
      direct = cache(http, "#{BASE}/services.php?task=fetchDirectTerms&arg=#{tid}&output=json",
                     dpath, as_json: true, delay: options[:delay], timeout: options[:timeout], refresh: options[:refresh])
      if direct && direct["result"]
        update_manifest(manifest, tid, "direct_term_count" => direct["result"].size)
      end

      # HTML page
      html_cached = false
      if options[:html]
        hpath = File.join(RAW_ROOT, "html", "#{tid}.html")
        html = cache(http, "#{BASE}/index.php?tema=#{tid}", hpath, as_json: false,
                     delay: options[:delay], timeout: options[:timeout], refresh: options[:refresh])
        html_cached = !html.nil?
      end
      update_manifest(manifest, tid, "cached_html" => html_cached)

      n = fetched_mutex.synchronize { fetched += 1 }
      if n % 50 == 0 || n == work.size
        elapsed = Time.now - start_time
        rate = n / elapsed
        eta = (work.size - n) / [rate, 0.01].max
        PRINT_MUTEX.synchronize do
          printf "\r    %d/%d fetched  (%.1f/s, ETA %ds)    ", n, work.size, rate, eta
          $stdout.flush
        end
      end
    end
    http.finish
  rescue StandardError => e
    PRINT_MUTEX.synchronize { warn "  worker #{worker_id} died: #{e.class}: #{e.message}" }
  end
end
threads.each(&:join)
puts

# --- Persist manifest -----------------------------------------------------
tmp = MANIFEST + ".tmp"
File.write(tmp, JSON.pretty_generate(manifest))
File.rename(tmp, MANIFEST)

with_cid = manifest.values.count { |v| v["concept_id"] }
without_cid = manifest.values.count { |v| v["concept_id"].nil? }
notes_cached = Dir[File.join(RAW_ROOT, "notes", "*.json")].size
html_cached  = Dir[File.join(RAW_ROOT, "html", "*.html")].size
puts "Manifest:"
puts "  total term_ids:    #{manifest.size}"
puts "  with concept_id:   #{with_cid}"
puts "  without concept_id: #{without_cid}  (meta terms like 'OIML')"
puts "  notes files:       #{notes_cached}"
puts "  html files:        #{html_cached}"
puts
puts "Manifest written: #{MANIFEST}"
puts "Next: ruby scripts/parse_g18_ptb.rb"
