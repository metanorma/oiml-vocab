# frozen_string_literal: true

module Oiml
  module OimlComplete
    # Heuristic language identification for an OCR text block.
    #
    # We only need coarse detection because each LanguageHalf has usually been
    # pre-segmented by LanguageSplitter, which uses textual hints
    # ("Edition (E)" / "Edition (F)" markers, document titles). This class
    # only confirms the language when the splitter is uncertain.
    #
    # The detector is open for extension: add a language by adding an entry
    # to SCORE_HINTS with a few high-signal function words.
    LanguageDetector = Data.define(:text) do
      SCORE_HINTS = {
        "fra" => { words: %w[le la les des du d'un pour dans avec par qui sur],
                   accents: %w[é è ê à ô î û ç].freeze }.freeze,
        "eng" => { words: %w[the of and to in for is a with by on that as],
                   accents: [].freeze }.freeze,
        "deu" => { words: %w[der die das und von zu mit für auf ist im den],
                   accents: %w[ä ö ü ß].freeze }.freeze,
        "spa" => { words: %w[el la los las de para por con que en un una se],
                   accents: %w[á é í ó ú ñ ¿ ¡].freeze }.freeze,
        "ita" => { words: %w[il la le di per con che un una e da in],
                   accents: %w[à è é ì ò ù].freeze }.freeze,
        "por" => { words: %w[o a os as de para por com que em um uma],
                   accents: %w[á ã ç ó ê].freeze }.freeze,
        "nld" => { words: %w[de het een en van naar met voor op te die],
                   accents: [].freeze }.freeze,
      }.freeze

      def detect
        down = text.downcase
        chars = text.chars
        SCORE_HINTS.transform_values do |h|
          word_hits = h[:words].count { |w| down.match?(/\b#{Regexp.escape(w)}\b/) }
          accent_hits = h[:accents].count { |c| chars.include?(c) }
          word_hits + (accent_hits * 2)
        end.max_by { |_, s| s }&.first || "eng"
      end
    end
  end
end
