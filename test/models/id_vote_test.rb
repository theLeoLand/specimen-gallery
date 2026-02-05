require "test_helper"

class IdVoteTest < ActiveSupport::TestCase
  def setup
    @taxon = Taxon.create!(scientific_name: "Test Species", group: "other")
    @specimen = @taxon.specimen_assets.build(
      specimen_name: "Test Specimen",
      status: "approved",
      license: "CC0"
    )
    @specimen.image.attach(
      io: File.open(Rails.root.join("test/fixtures/files/test_image.png")),
      filename: "test.png",
      content_type: "image/png"
    )
    @specimen.save!
  end

  test "valid confirm vote" do
    vote = IdVote.new(
      specimen_asset: @specimen,
      vote_kind: "confirm",
      voter_fingerprint: SecureRandom.hex(16),
      voter_ip_hash: Digest::SHA256.hexdigest("test-ip")
    )
    assert vote.valid?
  end

  test "valid suggest vote with taxon" do
    other_taxon = Taxon.create!(scientific_name: "Other Species", group: "other")
    vote = IdVote.new(
      specimen_asset: @specimen,
      vote_kind: "suggest",
      suggested_taxon: other_taxon,
      voter_fingerprint: SecureRandom.hex(16),
      voter_ip_hash: Digest::SHA256.hexdigest("test-ip")
    )
    assert vote.valid?
  end

  test "suggest vote requires taxon" do
    vote = IdVote.new(
      specimen_asset: @specimen,
      vote_kind: "suggest",
      voter_fingerprint: SecureRandom.hex(16),
      voter_ip_hash: Digest::SHA256.hexdigest("test-ip")
    )
    assert_not vote.valid?
    assert_includes vote.errors[:suggested_taxon], "is required when suggesting a different ID"
  end

  test "requires valid vote_kind" do
    vote = IdVote.new(
      specimen_asset: @specimen,
      vote_kind: "invalid",
      voter_fingerprint: SecureRandom.hex(16),
      voter_ip_hash: Digest::SHA256.hexdigest("test-ip")
    )
    assert_not vote.valid?
  end

  test "one vote per fingerprint per specimen" do
    fingerprint = SecureRandom.hex(16)
    IdVote.create!(
      specimen_asset: @specimen,
      vote_kind: "confirm",
      voter_fingerprint: fingerprint,
      voter_ip_hash: Digest::SHA256.hexdigest("test-ip")
    )

    duplicate = IdVote.new(
      specimen_asset: @specimen,
      vote_kind: "confirm",
      voter_fingerprint: fingerprint,
      voter_ip_hash: Digest::SHA256.hexdigest("test-ip-2")
    )
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:voter_fingerprint], "has already voted on this specimen"
  end
end



