# frozen_string_literal: true

module Oiml
  module G18Complete
    # A parsed terminology section within one LanguageHalf.
    #
    # A terminology section runs from a header like
    #   ## 3 Terms and definitions
    #   ## 3 Terminology
    #   ## 2 Terminologie et symboles
    # until the next sibling/parent header (## 4, ## 5, ...) or end of file.
    # Sub-clauses that introduce term entries are expected to be
    #   ### 3.1 / ## 3.1 / ## 3.1.1 / 3. 7 / etc.
    TerminologySection = Data.define(:title, :number, :language, :body) do
      def term_entries(parser: TermEntryParser.new)
        parser.parse(self)
      end
    end
  end
end
