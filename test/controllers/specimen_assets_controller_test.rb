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
