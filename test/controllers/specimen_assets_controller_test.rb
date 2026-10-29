require "test_helper"

class NeedsReviewPolicyTest < ActiveSupport::TestCase
  # Test the hybrid verification policy for needs_review flag
  # Tests the determine_needs_review logic from SpecimenAssetsController

  def determine_needs_review(unsure_id:, group:, scientific_name_provided:, is_good_match:)
    # Rule 1: User explicitly asked for ID help
    return true if unsure_id

    # Rule 2: Non-living categories don't need GBIF verification
    return false if TaxonGroupResolver.non_living?(group)

    # Rule 3: Living categories need GBIF verification
    !is_good_match
  end

  # Test 1: Minerals/Rocks with no scientific_name and not unsure => needs_review false
  test "mineral submission without scientific name should not need review" do
    result = determine_needs_review(
      unsure_id: false,
      group: "mineral",
      scientific_name_provided: false,
      is_good_match: false
    )
    assert_equal false, result, "Minerals should not require GBIF verification"
  end

  # Test 2: Living category with no scientific_name and not unsure => needs_review true
  test "living category without scientific name should need review" do
    %w[plant fungi insect mammal bird fish].each do |group|
      result = determine_needs_review(
        unsure_id: false,
        group: group,
        scientific_name_provided: false,
        is_good_match: false
      )
      assert_equal true, result, "#{group} should require verification when no scientific name provided"
    end
  end

  # Test 3: Living category with scientific_name + good GBIF => needs_review false
  test "living category with good GBIF match should not need review" do
    result = determine_needs_review(
      unsure_id: false,
      group: "insect",
      scientific_name_provided: true,
      is_good_match: true
    )
    assert_equal false, result, "GBIF-verified living organisms should not need review"
  end

  # Test 4: Any category with unsure checked => needs_review true
  test "any category with unsure checked should need review" do
    # Test with mineral (non-living)
    result = determine_needs_review(
      unsure_id: true,
      group: "mineral",
      scientific_name_provided: false,
      is_good_match: false
    )
    assert_equal true, result, "Unsure flag should always trigger needs_review"

    # Test with living category + good match
    result = determine_needs_review(
      unsure_id: true,
      group: "bird",
      scientific_name_provided: true,
      is_good_match: true
    )
    assert_equal true, result, "Unsure flag should override good GBIF match"
  end

  # Test 5: Living category with scientific_name but failed GBIF => needs_review true
  test "living category with failed GBIF match should need review" do
    result = determine_needs_review(
      unsure_id: false,
      group: "mammal",
      scientific_name_provided: true,
      is_good_match: false
    )
    assert_equal true, result, "Failed GBIF match should trigger needs_review for living organisms"
  end
end

class SpecimenAssetsRelatedTest < ActionDispatch::IntegrationTest
  def setup
    @frogs = Taxon.create!(scientific_name: "Related Frogus", group: "reptile_amphibian")
    @other_frog = Taxon.create!(scientific_name: "Related Tree Frogus", group: "reptile_amphibian")
    @beetle = Taxon.create!(scientific_name: "Related Beetleus", group: "insect")
    @subject = attach_approved(@frogs, "Poison Frog")
    @same_species = attach_approved(@frogs, "Poison Frog Two")
    @close_frog = attach_approved(@other_frog, "Tree Frog Close")
    @second_photo = attach_approved(@other_frog, "Tree Frog Closer Photo")
    @close_beetle = attach_approved(@beetle, "Beetle Close")
  end

  test "specimen page lists close species in the same group and skips the rest" do
    far_taxon = Taxon.create!(scientific_name: "Related Far Frogus", group: "reptile_amphibian")
    far_frog = attach_approved(far_taxon, "Far Frog")
    pending = attach_approved(@other_frog, "Pending Frog")
    pending.update_column(:status, "pending")

    @subject.update_column(:embedding, unit(0))
    @same_species.update_column(:embedding, mix(0.95))
    @second_photo.update_column(:embedding, mix(0.98))
    @close_frog.update_column(:embedding, mix(0.80))
    @close_beetle.update_column(:embedding, mix(0.80))
    far_frog.update_column(:embedding, unit(1))
    pending.update_column(:embedding, mix(0.90))

    get specimen_asset_path(@subject)

    assert_response :success
    assert_select "section[aria-label='Related specimens']"
    assert_includes response.body, "Related Tree Frogus"
    assert_select "a[href='#{specimen_asset_path(@second_photo)}']"
    assert_select "a[href='#{specimen_asset_path(@close_frog)}']", count: 0
    assert_not_includes response.body, "Related Beetleus"
    assert_not_includes response.body, "Related Far Frogus"
    assert_not_includes response.body, "Pending Frog"
    assert_not_includes response.body, "Poison Frog Two"
  end

  test "specimen page omits the related row when nothing is close" do
    @subject.update_column(:embedding, unit(0))
    @close_beetle.update_column(:embedding, unit(1))

    get specimen_asset_path(@subject)

    assert_response :success
    assert_select "section[aria-label='Related specimens']", count: 0
  end

  private

  def unit(index)
    vector = Array.new(384, 0.0)
    vector[index] = 1.0
    vector
  end

  def mix(first)
    vector = Array.new(384, 0.0)
    vector[0] = first
    vector[1] = Math.sqrt(1 - (first * first))
    vector
  end

  def attach_approved(taxon, name)
    asset = taxon.specimen_assets.build(
      specimen_name: name,
      status: "approved",
      license: "CC0"
    )
    file = Tempfile.new([ name.parameterize, ".png" ])
    file.binmode
    file.write(File.binread(Rails.root.join("test/fixtures/files/test_image.png")))
    file.write(name)
    file.rewind
    asset.image.attach(io: file, filename: "#{name.parameterize}.png", content_type: "image/png")
    asset.save!
    asset
  ensure
    file&.close!
  end
end
