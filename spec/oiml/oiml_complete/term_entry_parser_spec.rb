# frozen_string_literal: true

require "spec_helper"

RSpec.describe Oiml::G18Complete::TermEntryParser do
  subject(:parser) { described_class.new }

  def section_from(body, number: "3", language: "eng")
    Oiml::G18Complete::TerminologySection.new(title: "Terms and definitions", number: number, language: language, body: body)
  end

  describe "#parse" do
    it "parses a simple entry with number, designation, definition" do
      body = <<~MD
        ## 3.1

        water meter

        instrument intended to measure continuously the volume of water
      MD
      entries = parser.parse(section_from(body))
      expect(entries.size).to eq(1)
      e = entries.first
      expect(e.number).to eq("3.1")
      expect(e.preferred).to eq("water meter")
      expect(e.definition).to eq("instrument intended to measure continuously the volume of water")
    end

    it "captures notes and examples" do
      body = <<~MD
        ## 3.1

        water meter

        instrument intended to measure volume of water.

        Note 1: A water meter includes a transducer.

        Note 2: It can be a combination meter.

        Example: A domestic water meter.
      MD
      e = parser.parse(section_from(body)).first
      expect(e.notes.size).to eq(2)
      expect(e.notes.first).to include("transducer")
      expect(e.examples.size).to eq(1)
      expect(e.examples.first).to include("domestic")
    end

    it "captures [Source: ...] citations" do
      body = <<~MD
        ## 3.1

        sensor

        element of a meter that is directly affected by a quantity.

        [Source: OIML V 2-200:2012 (VIM) 3.8, modified]
      MD
      e = parser.parse(section_from(body)).first
      expect(e.source_citation).to include("OIML V 2-200")
      expect(e.source_citation).to include("3.8")
    end

    it "skips group headers like '## 3.1 Water meter and its constituents'" do
      body = <<~MD
        ## 3.1 Water meter and its constituents

        ## 3.1.1

        water meter

        instrument intended to measure...
      MD
      entries = parser.parse(section_from(body))
      expect(entries.size).to eq(1)
      expect(entries.first.number).to eq("3.1.1")
    end

    it "skips bare OCR-flattened numbers like '3. 7'" do
      body = <<~MD
        3. 7

        maximum permissible error

        extreme value of measurement error...
      MD
      entries = parser.parse(section_from(body))
      expect(entries.size).to eq(1)
      expect(entries.first.number).to eq("3.7")
    end

    it "emits one entry per number header" do
      body = <<~MD
        ## 3.1

        alpha

        definition of alpha.

        ## 3.2

        beta

        definition of beta.

        ## 3.3

        gamma

        definition of gamma.
      MD
      entries = parser.parse(section_from(body))
      expect(entries.map(&:number)).to eq(%w[3.1 3.2 3.3])
      expect(entries.map(&:preferred)).to eq(%w[alpha beta gamma])
    end

    it "ignores entries that have no designation" do
      body = <<~MD
        ## 3.1

        ## 3.2

        beta

        definition.
      MD
      entries = parser.parse(section_from(body))
      expect(entries.size).to eq(1)
      expect(entries.first.number).to eq("3.2")
    end
  end
end
