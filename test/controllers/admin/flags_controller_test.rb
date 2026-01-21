require "test_helper"

module Admin
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

      @flag = Flag.create!(
        specimen_asset: @specimen,
        reason: "wrong_name",
        details: "Test details",
        status: "open"
      )

      @auth_headers = {
        "HTTP_AUTHORIZATION" => ActionController::HttpAuthentication::Basic.encode_credentials("admin", "admin")
      }
    end

    test "index shows open flags" do
      get admin_flags_path, headers: @auth_headers
      assert_response :success
      assert_includes response.body, @specimen.display_name
      assert_includes response.body, "Wrong name"
    end

    test "resolve updates flag status" do
      patch resolve_admin_flag_path(@flag), headers: @auth_headers
      assert_redirected_to admin_flags_path

      @flag.reload
      assert_equal "resolved", @flag.status
    end

    test "dismiss updates flag status" do
      patch dismiss_admin_flag_path(@flag), headers: @auth_headers
      assert_redirected_to admin_flags_path

      @flag.reload
      assert_equal "dismissed", @flag.status
    end

    test "mark_needs_review sets specimen needs_review" do
      assert_not @specimen.needs_review?

      patch mark_needs_review_admin_flag_path(@flag), headers: @auth_headers
      assert_redirected_to admin_flags_path

      @specimen.reload
      assert @specimen.needs_review?
    end

    test "requires authentication" do
      get admin_flags_path
      assert_response :unauthorized
    end
  end
end
