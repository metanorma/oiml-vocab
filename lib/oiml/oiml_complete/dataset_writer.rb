# frozen_string_literal: true

require "fileutils"
require "yaml"

module Oiml
  module OimlComplete
    # Writes the V 0 dataset to disk under `<out_dir>/`.
    #
    #   <out_dir>/
    #     register.yaml
    #     bibliography.yaml
    #     concepts/
    #       <pub-code>-<term-number>.yaml
    #
    # Re-running the writer overwrites files in place — output is
    # deterministic given the same input (UUID v5 + sorted iteration).
    class DatasetWriter
      attr_reader :out_dir

      def initialize(out_dir:)
        @out_dir = out_dir
      end

      def write(concepts:, publications:, languages:, concept_count: nil)
        FileUtils.mkdir_p(File.join(out_dir, "concepts"))

        write_register(concepts.size, languages)
        write_bibliography(publications)
        write_concepts(concepts)
      end

      private

      def write_register(count, languages)
        register = RegisterBuilder.new.build(concept_count: count, languages: languages)
        File.write(File.join(out_dir, "register.yaml"), yaml_dump(register))
      end

      def write_bibliography(publications)
        bib = BibliographyBuilder.new.build(publications)
        File.write(File.join(out_dir, "bibliography.yaml"), yaml_dump(bib))
      end

      def write_concepts(concepts)
        serializer = ConceptSerializer.new
        emitter = MultiDocYaml.new
        concepts.each do |concept|
          docs = serializer.serialize(concept)
          path = File.join(out_dir, "concepts", concept.file_basename)
          File.write(path, emitter.emit(docs))
        end
      end

      def yaml_dump(obj)
        YAML.dump(obj)
      end
    end
  end
end
