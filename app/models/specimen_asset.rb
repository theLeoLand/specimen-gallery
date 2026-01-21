# app/models/specimen_asset.rb
class SpecimenAsset < ApplicationRecord
  belongs_to :taxon
  has_one_attached :image
  has_many :flags, dependent: :destroy

  STATUSES = %w[pending approved rejected].freeze
  LICENSES = %w[CC0 CC_BY].freeze

  validates :specimen_name, presence: { message: "is required" }
  validates :status, inclusion: { in: STATUSES }
  validates :license, inclusion: { in: LICENSES }
  validate :image_attached
  validate :image_not_duplicate
  validate :cc_by_requires_attribution
  validate :image_content_type
  validate :image_file_size

  before_validation :default_status
  before_validation :compute_sha256_hash

  # Delegate scientific_name for convenience (from taxon)
  delegate :scientific_name, to: :taxon, allow_nil: true

  # Display name: specimen_name is the primary label
  def display_name
    specimen_name.presence || scientific_name || "Unknown"
  end

  # Whether this specimen has a verified scientific/taxonomic name
  def has_verified_taxonomy?
    taxon&.gbif_key.present?
  end

  # Whether this specimen was flagged for profanity
  def profanity_flagged?
    qc_flags&.dig("profanity_flagged") == true
  end

  # Fields that contained profanity (if any)
  def profanity_flagged_fields
    qc_flags&.dig("profanity_fields") || []
  end

  # Count of open community flags
  def open_flags_count
    flags.open_flags.count
  end

  private

  def default_status
    self.status ||= "pending"
    self.license ||= "CC0"
  end

  def image_attached
    errors.add(:image, "must be attached") unless image.attached?
  end

  def cc_by_requires_attribution
    return unless license == "CC_BY"
    errors.add(:attribution_name, "required for CC-BY") if attribution_name.blank?
    errors.add(:attribution_url, "required for CC-BY") if attribution_url.blank?
  end

  def image_content_type
    return unless image.attached?

    unless image.blob.content_type.in?(%w[image/png image/webp])
      errors.add(:image, "must be PNG or WebP")
    end
  end

  def image_file_size
    return unless image.attached?

    max_size = 10.megabytes
    if image.blob.byte_size > max_size
      errors.add(:image, "is too large (#{(image.blob.byte_size / 1.megabyte.to_f).round(1)}MB). Maximum is 10MB.")
    end
  end

  def compute_sha256_hash
    return unless image.attached?
    return if sha256_hash.present?

    image.blob.open do |file|
      self.sha256_hash = Digest::SHA256.file(file.path).hexdigest
    end
  rescue => e
    Rails.logger.warn("Could not compute SHA256: #{e.message}")
  end

  def image_not_duplicate
    return unless sha256_hash.present?

    existing = SpecimenAsset.where(sha256_hash: sha256_hash).where.not(id: id).exists?
    if existing
      errors.add(:image, "has already been uploaded (duplicate file detected)")
    end
  end
end
