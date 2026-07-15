# frozen_string_literal: true

require "spec_helper"

RSpec.describe Oiml::G18Complete::TerminologyMatcher do
  subject(:matcher) { described_class.new }

  describe "#find_sections" do
    it "finds an English 'Terms and definitions' section" do
      text = <<~MD
        ## 2 Scope
        Some scope text.
        ## 3 Terms and definitions
        water meter
        instrument intended to measure...
        ## 4 Metrological requirements
        First requirement.
      MD
      sections = matcher.find_sections(text, language: "eng")
      expect(sections.size).to eq(1)
      expect(sections.first.number).to eq("3")
      expect(sections.first.language).to eq("eng")
      expect(sections.first.body).to include("water meter")
      expect(sections.first.body).not_to include("First requirement")
    end

    it "finds French 'Termes et définitions'" do
      text = "## 3 Termes et définitions\ncompteur d'eau\ninstrument destiné à mesurer...\n## 4 Exigences"
      sections = matcher.find_sections(text, language: "fra")
      expect(sections.size).to eq(1)
      expect(sections.first.body).to include("compteur")
    end

    it "finds 'Terminology' sections" do
      text = "## 3 Terminology\nfoo\nbar\n## 4 Other"
      sections = matcher.find_sections(text, language: "eng")
      expect(sections.size).to eq(1)
    end

    it "handles trailing page numbers in title" do
      text = "## 3 Terms and definitions ... 5\nwater meter\n## 4 Other"
      sections = matcher.find_sections(text, language: "eng")
      expect(sections.size).to eq(1)
    end

    it "finds parenthesised alternates" do
      text = "## 3 Terminology (Terms and definitions)\nfoo\n## 4 Other"
      sections = matcher.find_sections(text, language: "eng")
      expect(sections.size).to eq(1)
    end

    it "returns nothing when no terminology section is present" do
      text = "## 2 Scope\n## 3 Something else\n## 4 Normative references"
      sections = matcher.find_sections(text, language: "eng")
      expect(sections).to be_empty
    end

    it "finds '0 Terms and definitions' for V 1 style numbering" do
      text = "## 0 Terms and definitions\nlegal metrology\n## 1 Scope"
      sections = matcher.find_sections(text, language: "eng")
      expect(sections.size).to eq(1)
      expect(sections.first.number).to eq("0")
    end
  end
end
