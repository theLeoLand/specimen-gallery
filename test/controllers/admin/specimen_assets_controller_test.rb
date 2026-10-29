require "test_helper"

module Admin
  class SpecimenAssetsControllerTest < ActionDispatch::IntegrationTest
    def setup
      @taxon = Taxon.create!(scientific_name: "Paginated Species", group: "other")
      @auth_headers = {
        "HTTP_AUTHORIZATION" => ActionController::HttpAuthentication::Basic.encode_credentials(
          ENV.fetch("ADMIN_USERNAME", "admin"),
          ENV.fetch("ADMIN_PASSWORD", "admin")
        )
      }
    end

    test "live tab pages a hundred specimens at a time" do
      insert_approved(101)

      get admin_specimen_assets_path(filter: "approved"), headers: @auth_headers
      assert_response :success
      assert_includes response.body, "Paged Specimen 000"
      assert_not_includes response.body, "Paged Specimen 100"
      assert_includes response.body, "1–100"
      assert_select "a[rel=next][href=?]", admin_specimen_assets_path(filter: "approved", queue: "all", page: 2)

      get admin_specimen_assets_path(filter: "approved", page: 2), headers: @auth_headers
      assert_response :success
      assert_includes response.body, "Paged Specimen 100"
      assert_not_includes response.body, "Paged Specimen 000"
      assert_includes response.body, "101–101"
      assert_select "a[rel=prev][href=?]", admin_specimen_assets_path(filter: "approved", queue: "all")
    end

    test "a page past the end clamps to the last page" do
      insert_approved(101)

      get admin_specimen_assets_path(filter: "approved", page: 99), headers: @auth_headers
      assert_response :success
      assert_includes response.body, "Paged Specimen 100"
      assert_not_includes response.body, "Paged Specimen 000"
    end

    test "search stays on the filtered page" do
      insert_approved(101)

      get admin_specimen_assets_path(filter: "approved", q: "Specimen 100"), headers: @auth_headers
      assert_response :success
      assert_includes response.body, "Paged Specimen 100"
      assert_not_includes response.body, "Paged Specimen 000"
      assert_match(/1\s+result/, response.body)
    end

    test "admin search finds a specimen by embedding when the name does not match" do
      asset = @taxon.specimen_assets.build(
        specimen_name: "Zzxylophone",
        status: "pending",
        license: "CC0"
      )
      asset.image.attach(
        io: File.open(Rails.root.join("test/fixtures/files/test_image.png")),
        filename: "semantic.png",
        content_type: "image/png"
      )
      asset.save!
      vector = Array.new(384, 0.0)
      vector[0] = 1.0
      asset.update_column(:embedding, vector)

      original = SpecimenEmbedder.method(:embed_query)
      SpecimenEmbedder.define_singleton_method(:embed_query) { |_query| vector }
      get admin_specimen_assets_path(filter: "pending", q: "ladybug"), headers: @auth_headers
    ensure
      SpecimenEmbedder.define_singleton_method(:embed_query) { |query| original.call(query) } if original

      assert_response :success
      assert_includes response.body, "Zzxylophone"
    end

    test "rejecting an imported specimen keeps a rejected tombstone and purges its image" do
      asset = @taxon.specimen_assets.build(
        specimen_name: "Imported Iguana",
        status: "pending",
        license: "CC0",
        qc_flags: {
          "import_source" => "inaturalist",
          "inat_photo_id" => "999888",
          "inat_observation_id" => "777666"
        }
      )
      asset.image.attach(
        io: File.open(Rails.root.join("test/fixtures/files/test_image.png")),
        filename: "iguana.png",
        content_type: "image/png"
      )
      asset.save!
      assert asset.sha256_hash.present?

      assert_no_difference -> { SpecimenAsset.count } do
        delete admin_specimen_asset_path(asset), headers: @auth_headers
      end

      asset.reload
      assert_equal "rejected", asset.status
      assert_not asset.image.attached?
      assert SpecimenAsset.where("qc_flags ->> 'inat_photo_id' = ?", "999888").exists?
    end

    test "rejecting a manual upload deletes the record" do
      asset = @taxon.specimen_assets.build(
        specimen_name: "Manual Upload",
        status: "pending",
        license: "CC0"
      )
      asset.image.attach(
        io: File.open(Rails.root.join("test/fixtures/files/test_image.png")),
        filename: "manual.png",
        content_type: "image/png"
      )
      asset.save!

      assert_difference -> { SpecimenAsset.count }, -1 do
        delete admin_specimen_asset_path(asset), headers: @auth_headers
      end
    end

    private

    def insert_approved(count)
      now = Time.current
      rows = count.times.map do |i|
        {
          taxon_id: @taxon.id,
          specimen_name: format("Paged Specimen %03d", i),
          status: "approved",
          license: "CC0",
          created_at: now - i.seconds,
          updated_at: now,
          submission_token: SecureRandom.hex(16)
        }
      end
      SpecimenAsset.insert_all!(rows)
    end
  end
end
