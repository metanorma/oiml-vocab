# frozen_string_literal: true

require "spec_helper"
require "yaml"

RSpec.describe Oiml::G18Complete::ConceptSerializer do
  subject(:serializer) { described_class.new }

  let(:publication) { Oiml::G18Complete::PublicationCode.parse("r49-1-2013-eng") }

  let(:eng_entry) do
    Oiml::G18Complete::TermEntry.new(
      number: "3.1.1",
      language: "eng",
      designations: ["water meter"],
      preferred: "water meter",
      definition: "instrument intended to measure volume of water.",
      notes: ["Note 1: includes a transducer."],
      examples: [],
      source_citation: nil,
      raw_text: "",
    )
  end

  let(:fra_entry) do
    Oiml::G18Complete::TermEntry.new(
      number: "3.1.1",
      language: "fra",
      designations: ["compteur d'eau"],
      preferred: "compteur d'eau",
      definition: "instrument destiné à mesurer le volume d'eau.",
      notes: [],
      examples: [],
      source_citation: nil,
      raw_text: "",
    )
  end

  let(:concept) do
    localized = [eng_entry, fra_entry].map do |e|
      Oiml::G18Complete::LocalizedConcept.from_term_entry(e, publication: publication, date_accepted: "2026-07-13T00:00:00+00:00")
    end
    Oiml::G18Complete::Concept.new(
      publication: publication,
      number: "3.1.1",
      localized_concepts: localized,
      date_accepted: "2026-07-13T00:00:00+00:00",
    )
  end

  describe "#serialize" do
    subject(:docs) { serializer.serialize(concept) }

    it "emits one outer doc plus one per localized concept" do
      expect(docs.size).to eq(3)
    end

    describe "outer doc" do
      subject(:outer) { docs.first }

      it "includes the localized_concepts UUID map" do
        expect(outer["data"]["localized_concepts"]).to include("eng", "fra")
      end

      it "records the OIML publication source" do
        expect(outer["data"]["sources"]).to eq([{
          "ref" => "OIML R 49-1:2013",
          "clause" => "3.1.1",
          "version" => "2013",
        }])
      end

      it "uses schema_version 3" do
        expect(outer["schema_version"]).to eq("3")
      end

      it "uses status 'valid'" do
        expect(outer["status"]).to eq("valid")
      end

      it "has a stable UUID id" do
        expect(outer["id"]).to match(/\A[0-9a-f-]{36}\z/)
      end
    end

    describe "localized docs" do
      subject(:localized_docs) { docs.drop(1) }

      it "includes the designation as a preferred term" do
        eng = localized_docs.find { |d| d["data"]["language_code"] == "eng" }
        expect(eng["data"]["terms"]).to eq([{
          "type" => "expression",
          "normative_status" => "preferred",
          "designation" => "water meter",
        }])
      end

      it "captures notes" do
        eng = localized_docs.find { |d| d["data"]["language_code"] == "eng" }
        expect(eng["data"]["notes"].first["content"]).to include("transducer")
      end
    end

    it "is stable across multiple calls (deterministic UUIDs)" do
      expect(serializer.serialize(concept)).to eq(docs)
    end
  end

  describe "MultiDocYaml round-trip" do
    subject(:yaml_text) { Oiml::G18Complete::MultiDocYaml.new.emit(serializer.serialize(concept)) }

    it "round-trips through YAML.parse_stream" do
      loaded = YAML.load_stream(yaml_text)
      expect(loaded.size).to eq(3)
      expect(loaded.first["data"]["identifier"]).to eq("r49-1-2013-eng-3.1.1")
    end
  end
end
