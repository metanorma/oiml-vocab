# frozen_string_literal: true

require "spec_helper"

RSpec.describe Oiml::G18Complete::PublicationCode do
  describe ".parse" do
    {
      "r49-1-2013-e" => ["R", "49-1", 2013, "eng", "OIML R 49-1:2013", "urn:oiml:pub:r:49-1:2013"],
      "d11-2013-e" => ["D", "11", 2013, "eng", "OIML D 11:2013", "urn:oiml:pub:d:11:2013"],
      "v2-200-2012-e" => ["V", "2-200", 2012, "eng", "OIML V 2-200:2012", "urn:oiml:pub:v:2-200:2012"],
      "v1-2000" => ["V", "1", 2000, "eng", "OIML V 1:2000", "urn:oiml:pub:v:1:2000"],
      "r137-1-2-2012-fra" => ["R", "137-1-2", 2012, "fra", "OIML R 137-1-2:2012", "urn:oiml:pub:r:137-1-2:2012"],
      "r49-1-2013-spa" => ["R", "49-1", 2013, "spa", "OIML R 49-1:2013", "urn:oiml:pub:r:49-1:2013"],
      "b10-1-2004amendment-2006-eng" => ["B", "10-1", 2004, "eng", "OIML B 10-1:2004 (amendment-2006)", "urn:oiml:pub:b:10-1:2004"],
      "r87-2008errata-eng" => ["R", "87", 2008, "eng", "OIML R 87:2008 (errata)", "urn:oiml:pub:r:87:2008"],
      "v2-200-2007errata-2010-eng" => ["V", "2-200", 2007, "eng", "OIML V 2-200:2007 (errata-2010)", "urn:oiml:pub:v:2-200:2007"],
      "r60-2017annexes-eng" => ["R", "60", 2017, "eng", "OIML R 60:2017 (annexes)", "urn:oiml:pub:r:60:2017"],
      "r35-1-2007amendment-2014-eng" => ["R", "35-1", 2007, "eng", "OIML R 35-1:2007 (amendment-2014)", "urn:oiml:pub:r:35-1:2007"],
      "r76-zho" => ["R", "76", 0, "zho", "OIML R 76:0", "urn:oiml:pub:r:76:0"],
    }.each do |input, (kind, number, year, lang, ref, urn)|
      context "with #{input.inspect}" do
        subject(:pub) { described_class.parse(input) }

        it("parses kind")          { expect(pub.kind).to eq(kind) }
        it("parses number")        { expect(pub.number).to eq(number) }
        it("parses year")          { expect(pub.year).to eq(year) }
        it("parses language")      { expect(pub.language).to eq(lang) }
        it("builds OIML reference") { expect(pub.oiml_ref).to eq(ref) }
        it("builds URN")            { expect(pub.urn).to eq(urn) }
        it("echoes dataset_id")     { expect(pub.dataset_id).to eq(input) }
      end
    end

    it "rejects empty input" do
      expect { described_class.parse("") }.to raise_error(ArgumentError)
    end
  end
end
