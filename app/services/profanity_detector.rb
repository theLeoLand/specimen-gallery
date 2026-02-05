# app/services/profanity_detector.rb
# Lightweight profanity detection for text fields.
# Non-blocking: only flags for review, never prevents submission.
#
# Usage:
#   detector = ProfanityDetector.new(specimen_name: "test", common_name: "example")
#   detector.flagged?          # => true/false
#   detector.flagged_fields    # => ["specimen_name"] or []

class ProfanityDetector
  # Basic word list - add/remove as needed
  # Case-insensitive matching, checks for whole words
  PROFANITY_LIST = %w[
    fuck
    shit
    ass
    bitch
    damn
    crap
    piss
    dick
    cock
    pussy
    bastard
    slut
    whore
    fag
    nigger
    cunt
  ].freeze

  # Fields to check (pass as keyword args)
  CHECKABLE_FIELDS = %i[specimen_name common_name description].freeze

  def initialize(**fields)
    @fields = fields.slice(*CHECKABLE_FIELDS)
    @flagged_fields = []
    @checked = false
  end

  # Returns true if any field contains profanity
  def flagged?
    check_fields unless @checked
    @flagged_fields.any?
  end

  # Returns array of field names that contained profanity
  def flagged_fields
    check_fields unless @checked
    @flagged_fields
  end

  # Returns hash suitable for storing in qc_flags
  def to_qc_flags
    return {} unless flagged?

    {
      "profanity_flagged" => true,
      "profanity_fields" => flagged_fields.map(&:to_s),
      "flagged_at" => Time.current.iso8601
    }
  end

  private

  def check_fields
    @checked = true
    @flagged_fields = []

    @fields.each do |field_name, value|
      next if value.blank?

      if contains_profanity?(value)
        @flagged_fields << field_name
      end
    end
  end

  def contains_profanity?(text)
    normalized = text.to_s.downcase

    PROFANITY_LIST.any? do |word|
      # Match whole words only (word boundaries)
      normalized.match?(/\b#{Regexp.escape(word)}\b/i)
    end
  end
end
