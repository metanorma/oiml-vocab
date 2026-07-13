# frozen_string_literal: true

require "spec_helper"

RSpec.describe Oiml::G18Complete::LanguageSplitter do
  subject(:splitter) { described_class.new }

  describe "#split with no markers" do
    let(:text) { "Just a regular document with no Edition markers anywhere." }

    it "returns a single half with the default language" do
      halves = splitter.split(text, default_language: "spa")
      expect(halves.size).to eq(1)
      expect(halves.first.language).to eq("spa")
      expect(halves.first.text).to eq(text)
    end
  end

  describe "#split with one marker" do
    let(:text) { "Edition 2013 (E)\n\nEnglish body only." }

    it "returns one half with the marker's language" do
      halves = splitter.split(text)
      expect(halves.size).to eq(1)
      expect(halves.first.language).to eq("eng")
      expect(halves.first.text).to include("English body")
    end
  end

  describe "#split with EN and FR markers" do
    let(:text) do
      <<~OCR
        Edition 2013 (E)

        Water meters for cold potable water.

        ## 3 Terms and definitions

        water meter

        Edition 2013 (F)

        Compteurs d'eau pour l'eau potable froide.

        ## 3 Termes et définitions

        compteur d'eau
      OCR
    end

    it "returns one half per marker, in order, with the right languages" do
      halves = splitter.split(text)
      expect(halves.map(&:language)).to eq(%w[eng fra])
      expect(halves.first.text).to include("Water meters")
      expect(halves.last.text).to include("Compteurs d'eau")
    end
  end

  describe "#split with multiple parts each bilingual" do
    let(:text) do
      <<~OCR
        Edition 2013 (E)
        English part 1.
        Edition 2013 (F)
        French part 1.
        Edition 2013 (E)
        English part 2.
        Edition 2013 (F)
        French part 2.
      OCR
    end

    it "produces four halves in document order" do
      halves = splitter.split(text)
      expect(halves.map(&:language)).to eq(%w[eng fra eng fra])
      expect(halves.map(&:text).map(&:strip)).to eq(
        ["English part 1.", "French part 1.", "English part 2.", "French part 2."],
      )
    end
  end
end
