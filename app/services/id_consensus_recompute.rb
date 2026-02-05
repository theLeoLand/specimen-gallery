# app/services/id_consensus_recompute.rb
# Recomputes community ID consensus for a specimen asset
class IdConsensusRecompute
  # Thresholds for consensus determination (easily tweakable)
  THRESHOLDS = {
    verified_min_confirms: 3,        # Minimum confirms for "verified"
    mixed_min_suggests: 2,           # Top suggestion count to trigger "mixed"
    mixed_total_suggests: 3,         # Total suggest votes to trigger "mixed"
    mixed_margin: 1                  # If top_suggested is within this margin of confirms, mixed
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
    @id_status = if verified?
      "verified"
    elsif mixed?
      "mixed"
    else
      "unverified"
    end
  end

  def verified?
    # Verified: enough confirms AND suggestions don't challenge it
    @confirm_count >= THRESHOLDS[:verified_min_confirms] &&
      @top_count < (@confirm_count - THRESHOLDS[:mixed_margin])
  end

  def mixed?
    # Mixed: significant number of suggests OR close race
    return true if @top_count >= THRESHOLDS[:mixed_min_suggests]
    return true if @suggest_count >= THRESHOLDS[:mixed_total_suggests]
    return true if @top_count > 0 && (@confirm_count - @top_count).abs <= THRESHOLDS[:mixed_margin]
    false
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

