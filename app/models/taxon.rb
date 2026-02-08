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

  # Scopes for id_status filtering
  scope :with_verified_assets, -> {
    joins(:specimen_assets)
      .where(specimen_assets: { status: "approved", id_status: "verified" })
      .distinct
  }

  scope :with_unverified_assets, -> {
    joins(:specimen_assets)
      .where(specimen_assets: { status: "approved" })
      .where.not(specimen_assets: { id_status: "verified" })
      .distinct
  }

  scope :with_assets_by_id_status, ->(id_status) {
    case id_status
    when "verified" then with_verified_assets
    when "unverified" then with_unverified_assets
    else with_approved_assets
    end
  }

  # Order taxa by their most recently approved asset (newest first)
  scope :ordered_by_latest_approved, -> {
    joins(:specimen_assets)
      .where(specimen_assets: { status: "approved" })
      .group("taxa.id")
      .order(Arel.sql("MAX(specimen_assets.created_at) DESC"))
  }

  # Order taxa by their most recently verified asset (newest first) - for homepage
  scope :ordered_by_latest_verified, -> {
    joins(:specimen_assets)
      .where(specimen_assets: { status: "approved", id_status: "verified" })
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

  # Filter approved assets by id_status
  def assets_by_id_status(id_status = nil)
    base = specimen_assets.where(status: "approved")
    case id_status
    when "verified" then base.where(id_status: "verified")
    when "unverified" then base.where.not(id_status: "verified")
    else base
    end.order(created_at: :desc)
  end

  def verified_assets
    assets_by_id_status("verified")
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
