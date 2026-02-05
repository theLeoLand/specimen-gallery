# app/models/flag.rb
# Community flags for specimen assets (no accounts required)
class Flag < ApplicationRecord
  belongs_to :specimen_asset

  REASONS = %w[wrong_name wrong_license inappropriate duplicate low_quality bad_cutout other].freeze
  STATUSES = %w[open resolved dismissed].freeze

  validates :reason, presence: true, inclusion: { in: REASONS }
  validates :status, presence: true, inclusion: { in: STATUSES }

  scope :open_flags, -> { where(status: "open") }
  scope :newest_first, -> { order(created_at: :desc) }

  # Human-readable reason labels
  def self.reason_label(reason)
    {
      "wrong_name" => "Wrong name/identification",
      "wrong_license" => "Copyright issue",
      "inappropriate" => "Inappropriate content",
      "duplicate" => "Duplicate submission",
      "low_quality" => "Low quality image",
      "bad_cutout" => "Background removal failed",
      "other" => "Other issue"
    }[reason] || reason.humanize
  end

  def reason_label
    self.class.reason_label(reason)
  end

  def open?
    status == "open"
  end

  def resolved?
    status == "resolved"
  end

  def dismissed?
    status == "dismissed"
  end
end
