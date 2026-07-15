# frozen_string_literal: true

require "spec_helper"

RSpec.describe Oiml::G18Complete::UuidV5 do
  describe ".generate" do
    it "returns a 36-character canonical UUID" do
      uuid = described_class.generate(Oiml::G18Complete::UuidNamespace::NAMESPACE_UUID, "oiml-complete|r49-1-2013-e|3.1.1|eng")
      expect(uuid).to match(/\A[0-9a-f]{8}-[0-9a-f]{4}-5[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/)
    end

    it "is deterministic for the same inputs" do
      a = described_class.generate(Oiml::G18Complete::UuidNamespace::NAMESPACE_UUID, "name-1")
      b = described_class.generate(Oiml::G18Complete::UuidNamespace::NAMESPACE_UUID, "name-1")
      expect(a).to eq(b)
    end

    it "differs for different names" do
      a = described_class.generate(Oiml::G18Complete::UuidNamespace::NAMESPACE_UUID, "name-1")
      b = described_class.generate(Oiml::G18Complete::UuidNamespace::NAMESPACE_UUID, "name-2")
      expect(a).not_to eq(b)
    end

    it "matches a known vector" do
      # RFC 4122 §4.3 test vector: DNS namespace + "python.org" → known UUID.
      dns_namespace = "6ba7b810-9dad-11d1-80b4-00c04fd430c8"
      uuid = described_class.generate(dns_namespace, "python.org")
      expect(uuid).to eq("886313e1-3b8a-5372-9b90-0c9aee199e5d")
    end

    it "rejects malformed namespace UUIDs" do
      expect { described_class.generate("not-a-uuid", "x") }.to raise_error(ArgumentError)
    end
  end
end
