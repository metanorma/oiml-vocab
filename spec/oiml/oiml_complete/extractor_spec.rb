# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe Oiml::G18Complete::Extractor do
  let(:fixture_root) do
    Pathname.new(Dir.mktmpdir("oiml-complete-extractor-spec")).tap do |dir|
      %w[r49-1-2013-eng d11-2013-e].each do |pub|
        pub_dir = dir + pub
        pub_dir.mkpath
        FileUtils.cp(
          SPEC_FIXTURES_ROOT + "#{pub}.ocr.md",
          pub_dir + "ocr.md",
        )
      end
      # Publication without ocr.md to verify graceful handling.
      (dir + "r1-0001-e").mkpath
    end
  end

  after { FileUtils.rm_rf(fixture_root) }

  subject(:result) do
    described_class.new(source_root: fixture_root.to_s).call
  end

  it "processes every directory that has ocr.md" do
    expect(result[:per_publication].map { |pp| pp.publication.dataset_id }).to contain_exactly(
      "r49-1-2013-eng", "d11-2013-e", "r1-0001-e",
    )
  end

  it "records an error for directories missing ocr.md" do
    missing = result[:per_publication].find { |pp| pp.publication.dataset_id == "r1-0001-e" }
    expect(missing.errors).not_to be_empty
    expect(missing.concepts).to be_empty
  end

  it "produces deterministic concept IDs" do
    first_run = described_class.new(source_root: fixture_root.to_s).call
    second_run = described_class.new(source_root: fixture_root.to_s).call
    expect(second_run[:concepts].map(&:outer_uuid)).to eq(first_run[:concepts].map(&:outer_uuid))
  end

  it "extracts at least one concept from each fixture" do
    expect(result[:concepts]).not_to be_empty
    expect(result[:concepts].group_by { |c| c.publication.dataset_id }.keys).to contain_exactly(
      "r49-1-2013-eng", "d11-2013-e",
    )
  end
end
