# app/models/taxon.rb
class Taxon < ApplicationRecord
  self.table_name = "taxa"

  has_many :specimen_assets, dependent: :destroy

  validates :scientific_name, presence: true,
    uniqueness: { case_sensitive: false, message: "already exists" }
  validates :group, inclusion: { in: TaxonGroupResolver::GROUPS, allow_blank: true }

  scope :with_approved_assets, -> {
    joins(:specimen_assets).where(specimen_assets: { status: "approved" }).distinct
  }

  # Order taxa by their most recently approved asset (newest first)
  scope :ordered_by_latest_approved, -> {
    joins(:specimen_assets)
      .where(specimen_assets: { status: "approved" })
      .group("taxa.id")
      .order(Arel.sql("MAX(specimen_assets.created_at) DESC"))
  }

  scope :by_group, ->(group) {
    where(group: group) if group.present? && group != "all"
  }

  # Find or create taxon by scientific name (case-insensitive)
  def self.find_or_create_by_name(name, source: nil, external_id: nil)
    normalized = name.to_s.strip
    taxon = where("LOWER(scientific_name) = LOWER(?)", normalized).first
    taxon || create!(
      scientific_name: normalized,
      taxon_source: source.presence,
      taxon_id: external_id.presence
    )
  end

  def approved_assets
    specimen_assets.where(status: "approved").order(created_at: :desc)
  end

  def approved_assets_count
    specimen_assets.where(status: "approved").count
  end

  # Display name for the group
  def group_display_name
    TaxonGroupResolver.display_name(group)
  end

  # Icon for the group
  def group_icon
    TaxonGroupResolver.icon(group)
  end

  # Assign group from GBIF match data
  def assign_group_from_gbif(gbif_match)
    self.group = TaxonGroupResolver.resolve(gbif_match)
  end
end
