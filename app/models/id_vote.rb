# app/models/id_vote.rb
# Community ID votes for specimen identification verification
class IdVote < ApplicationRecord
  VOTE_KINDS = %w[confirm suggest].freeze

  belongs_to :specimen_asset
  belongs_to :suggested_taxon, class_name: "Taxon", optional: true

  validates :vote_kind, presence: true, inclusion: { in: VOTE_KINDS }
  validates :voter_fingerprint, presence: true
  validates :voter_ip_hash, presence: true
  validates :voter_fingerprint, uniqueness: {
    scope: :specimen_asset_id,
    message: "has already voted on this specimen"
  }

  # Suggested taxon required for "suggest" votes
  validate :suggested_taxon_required_for_suggest

  # Scopes
  scope :confirms, -> { where(vote_kind: "confirm") }
  scope :suggests, -> { where(vote_kind: "suggest") }

  # Callbacks
  after_create :recompute_consensus
  after_destroy :recompute_consensus

  def confirm?
    vote_kind == "confirm"
  end

  def suggest?
    vote_kind == "suggest"
  end

  private

  def suggested_taxon_required_for_suggest
    if vote_kind == "suggest" && suggested_taxon_id.blank?
      errors.add(:suggested_taxon, "is required when suggesting a different ID")
    end
  end

  def recompute_consensus
    IdConsensusRecompute.call(specimen_asset)
  end
end
