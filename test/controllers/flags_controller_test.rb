require "test_helper"

class FlagsControllerTest < ActionDispatch::IntegrationTest
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

  test "rate limits when limit reached" do
    # Set cache to the limit (30/hr) - use the exact key format the controller uses
    # Integration tests use 127.0.0.1 as remote_ip
    Rails.cache.write("flag_rate:127.0.0.1", 30, expires_in: 1.hour)

    # This should be rate limited (already at 30)
    post specimen_asset_flags_path(@specimen),
      params: { flag: { reason: "wrong_name" } },
      as: :json

    assert_response :too_many_requests
    json = JSON.parse(response.body)
    assert_match(/too many/i, json["error"])
  end
end
