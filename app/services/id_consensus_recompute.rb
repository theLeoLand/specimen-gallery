# app/services/id_consensus_recompute.rb
# Recomputes community ID consensus for a specimen asset
class IdConsensusRecompute
  # Thresholds for consensus determination (easily tweakable)
  THRESHOLDS = {
    verified_min_confirms: 3,        # Minimum confirms for "verified"
    challenge_margin: 1              # If suggestions are within this margin of confirms, stay unverified
  }.freeze

  def self.call(specimen_asset)
    new(specimen_asset).call
  end

  def initialize(specimen_asset)
    @asset = specimen_asset
  end

  def call
    compute_counts
    determine_top_suggestion
    determine_status
    persist_changes
    @asset
  end

  private

  def compute_counts
    @confirm_count = @asset.id_votes.confirms.count
    @suggest_count = @asset.id_votes.suggests.count
  end

  def determine_top_suggestion
    # Group suggestions by taxon and find the one with most votes
    suggestion_counts = @asset.id_votes.suggests
      .group(:suggested_taxon_id)
      .count

    if suggestion_counts.any?
      @top_taxon_id, @top_count = suggestion_counts.max_by { |_, count| count }
    else
      @top_taxon_id = nil
      @top_count = 0
    end
  end

  def determine_status
    @id_status = verified? ? "verified" : "unverified"
  end

  def verified?
    # Verified: enough confirms AND suggestions don't significantly challenge it
    @confirm_count >= THRESHOLDS[:verified_min_confirms] &&
      @top_count < (@confirm_count - THRESHOLDS[:challenge_margin])
  end

  def persist_changes
    @asset.update_columns(
      confirm_count: @confirm_count,
      suggest_count: @suggest_count,
      top_suggested_taxon_id: @top_taxon_id,
      top_suggested_count: @top_count,
      id_status: @id_status
    )
  end
end

