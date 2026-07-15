# frozen_string_literal: true

require "spec_helper"
require "yaml"

RSpec.describe Oiml::G18Complete::MultiDocYaml do
  subject(:emitter) { described_class.new }

  it "joins each document with a --- separator" do
    docs = [{ "a" => 1 }, { "b" => 2 }, { "c" => 3 }]
    out = emitter.emit(docs)
    expect(out.scan(/^---$/).size).to eq(3)
  end

  it "round-trips through YAML.load_stream" do
    docs = [{ "a" => 1, "list" => [1, 2] }, { "b" => "two" }]
    out = emitter.emit(docs)
    expect(YAML.load_stream(out)).to eq(docs)
  end

  it "preserves unicode and special characters" do
    docs = [{ "text" => "compteur d'eau — élève" }]
    out = emitter.emit(docs)
    expect(YAML.load_stream(out).first["text"]).to eq("compteur d'eau — élève")
  end
end
