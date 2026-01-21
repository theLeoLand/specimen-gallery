require "test_helper"

class FlagsControllerTest < ActionDispatch::IntegrationTest
  def setup
    @taxon = Taxon.create!(scientific_name: "Test Species", group: "other")
    @specimen = @taxon.specimen_assets.create!(
      specimen_name: "Test Specimen",
      status: "approved",
      license: "CC0"
    )
    @specimen.image.attach(
      io: File.open(Rails.root.join("test/fixtures/files/test_image.png")),
      filename: "test.png",
      content_type: "image/png"
    )

    # Clear rate limit cache
    Rails.cache.clear
  end

  test "creates flag with valid params" do
    assert_difference("Flag.count", 1) do
      post specimen_asset_flags_path(@specimen),
        params: { flag: { reason: "wrong_name", details: "This is actually a different species" } },
        as: :json
    end

    assert_response :success
    json = JSON.parse(response.body)
    assert json["success"]

    flag = Flag.last
    assert_equal "wrong_name", flag.reason
    assert_equal "This is actually a different species", flag.details
    assert_equal "open", flag.status
  end

  test "returns error for invalid reason" do
    assert_no_difference("Flag.count") do
      post specimen_asset_flags_path(@specimen),
        params: { flag: { reason: "invalid", details: "" } },
        as: :json
    end

    assert_response :unprocessable_entity
  end

  test "rate limits after 5 flags" do
    5.times do
      post specimen_asset_flags_path(@specimen),
        params: { flag: { reason: "wrong_name" } },
        as: :json
      assert_response :success
    end

    # 6th flag should be rate limited
    post specimen_asset_flags_path(@specimen),
      params: { flag: { reason: "wrong_name" } },
      as: :json

    assert_response :too_many_requests
    json = JSON.parse(response.body)
    assert_match(/too many/i, json["error"])
  end
end
