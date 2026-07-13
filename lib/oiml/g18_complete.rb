# frozen_string_literal: true

module Oiml
  module G18Complete
    VERSION = "0.1.0"

    autoload :UuidNamespace, "oiml/g18_complete/uuid_namespace"
    autoload :UuidV5, "oiml/g18_complete/uuid_v5"
    autoload :PublicationCode, "oiml/g18_complete/publication_code"
    autoload :OcrDocument, "oiml/g18_complete/ocr_document"
    autoload :LanguageSplitter, "oiml/g18_complete/language_splitter"
    autoload :LanguageDetector, "oiml/g18_complete/language_detector"
    autoload :TerminologyMatcher, "oiml/g18_complete/terminology_matcher"
    autoload :TerminologySection, "oiml/g18_complete/terminology_section"
    autoload :TermEntry, "oiml/g18_complete/term_entry"
    autoload :TermEntryParser, "oiml/g18_complete/term_entry_parser"
    autoload :LocalizedConcept, "oiml/g18_complete/localized_concept"
    autoload :Concept, "oiml/g18_complete/concept"
    autoload :ConceptSerializer, "oiml/g18_complete/concept_serializer"
    autoload :MultiDocYaml, "oiml/g18_complete/multi_doc_yaml"
    autoload :RegisterBuilder, "oiml/g18_complete/register_builder"
    autoload :BibliographyBuilder, "oiml/g18_complete/bibliography_builder"
    autoload :DatasetWriter, "oiml/g18_complete/dataset_writer"
    autoload :Extractor, "oiml/g18_complete/extractor"
  end
end