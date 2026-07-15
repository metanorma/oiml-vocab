# frozen_string_literal: true

require "yaml"

module Oiml
  module OimlComplete
    # Emits a multi-document YAML string from an Array<Hash>.
    #
    # Glossarist v3 concept files are multi-document YAML:
    #
    #   ---
    #   <outer concept doc>
    #   ---
    #   <localized concept doc 1>
    #   ---
    #   <localized concept doc 2>
    #
    # Ruby's YAML.dump supports dumping an Array as a stream, but the
    # resulting output is not human-friendly (no leading `---` separator
    # between docs, awkward indentation). We dump each document
    # individually with a tuned emitter and join with explicit `---`
    # separators so the output is byte-identical to the hand-curated
    # glossarist datasets already in this repo (see
    # datasets/viml-2022/concepts/*.yaml for reference).
    class MultiDocYaml
      def emit(docs)
        # Each document is dumped individually and joined with explicit
        # `---` separators so the output is byte-identical to the
        # hand-curated glossarist datasets already in this repo (see
        # datasets/viml-2022/concepts/*.yaml for reference). A leading
        # `---` introduces the first document, as expected by glossarist
        # and the project validator (scripts/validate_datasets.rb).
        body = docs.map { |doc| dump_one(doc) }.join("---\n")
        "---\n#{body}\n"
      end

      private

      def dump_one(doc)
        YAML.dump(doc).sub(/\A---\n/, "")
      end
    end
  end
end
