require "test_helper"

class TaxonGroupResolverTest < ActiveSupport::TestCase
  test "non_living? returns true for mineral group" do
    assert TaxonGroupResolver.non_living?("mineral")
  end

  test "non_living? returns false for living groups" do
    %w[plant fungi insect arachnid mammal bird fish reptile_amphibian marine_invertebrate microbe other].each do |group|
      assert_not TaxonGroupResolver.non_living?(group), "#{group} should not be non-living"
    end
  end

  test "requires_gbif_verification? returns false for mineral" do
    assert_not TaxonGroupResolver.requires_gbif_verification?("mineral")
  end

  test "requires_gbif_verification? returns true for living groups" do
    %w[plant fungi insect mammal bird].each do |group|
      assert TaxonGroupResolver.requires_gbif_verification?(group), "#{group} should require GBIF verification"
    end
  end

  test "NON_LIVING_GROUPS contains mineral" do
    assert_includes TaxonGroupResolver::NON_LIVING_GROUPS, "mineral"
  end
end
