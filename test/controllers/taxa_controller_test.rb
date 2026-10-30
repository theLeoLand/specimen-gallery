require "test_helper"

class TaxaControllerTest < ActionDispatch::IntegrationTest
  def setup
    @plant = Taxon.create!(scientific_name: "Browse Plantus", group: "plant")
    @insect = Taxon.create!(scientific_name: "Browse Insectus", group: "insect")
    attach_approved(@plant, "Plant One")
    attach_approved(@plant, "Plant Two")
    attach_approved(@insect, "Bug One")
  end

  test "browse totals match the whole gallery when unfiltered" do
    get browse_path
    assert_response :success
    assert_includes response.body, "2 species"
    assert_includes response.body, "3 images"
    assert_not_includes response.body, "results"
  end

  test "browse search by a stored name returns that species" do
    get browse_path, params: { q: "Plant" }
    assert_response :success
    assert_includes response.body, "Browse Plantus"
    assert_includes response.body, "1 species"
    assert_not_includes response.body, "Browse Insectus"
  end

  test "browse search finds a specimen by meaning when the typed words are not stored" do
    near = Array.new(384, 0.0)
    near[0] = 1.0
    far = Array.new(384, 0.0)
    far[1] = 1.0
    @plant.specimen_assets.each { |asset| asset.update_column(:embedding, near) }
    @insect.specimen_assets.each { |asset| asset.update_column(:embedding, far) }

    with_query_vector(near) do
      get browse_path, params: { q: "ladybug" }
    end

    assert_response :success
    assert_includes response.body, "Browse Plantus"
    assert_not_includes response.body, "Browse Insectus"
  end

  test "taxon page includes the vernacular name, search title, and citation" do
    @plant.update!(gbif_key: 999_001)
    @plant.specimen_assets.first.update_columns(common_name: "Browse Plant")

    get taxon_path(@plant)

    assert_response :success
    assert_select "title", text: /Browse Plantus \(Browse Plant\) transparent PNG cutout/
    assert_match(/Cite:.*Browse Plantus \(Browse Plant\)/, response.body)
    assert_includes response.body, "CC0 1.0"
    assert_includes response.body, taxon_path(@plant)
    assert_includes response.body, "https://www.gbif.org/species/999001"
  end

  test "taxon citation is plain text" do
    get citation_taxon_path(@plant)

    assert_response :success
    assert_equal "text/plain", response.media_type
    assert_includes response.body, "Browse Plantus. CC0 1.0. Specimen Gallery."
    assert_includes response.body, taxon_path(@plant)
  end

  test "gbif key redirects to the taxon page" do
    @plant.update!(gbif_key: 999_001)

    get gbif_taxon_path(999_001)

    assert_response :moved_permanently
    assert_redirected_to taxon_path(@plant)
  end

  test "gbif image redirects to the verified cutout" do
    @plant.update!(gbif_key: 999_001)
    hero = @plant.specimen_assets.order(:created_at).last
    hero.update_columns(id_status: "verified")

    get gbif_taxon_image_path(999_001)

    assert_response :found
    assert_redirected_to rails_blob_path(hero.image, disposition: "inline")
  end

  test "unknown gbif key is not found" do
    get gbif_taxon_path(404_404)
    assert_response :not_found
  end

  test "specimen page cites the image next to the download" do
    asset = @plant.specimen_assets.order(:created_at).first
    asset.update_columns(common_name: "Browse Plant", view: "dorsal")

    get specimen_asset_path(asset)

    assert_response :success
    assert_select "title", text: /Transparent PNG Cutout/
    assert_includes response.body, "Browse Plantus (Browse Plant)"
    assert_includes response.body, "dorsal"
    assert_includes response.body, specimen_asset_path(asset)
  end

  test "specimen citation is plain text" do
    asset = @insect.specimen_assets.first

    get citation_specimen_asset_path(asset)

    assert_response :success
    assert_equal "text/plain", response.media_type
    assert_includes response.body, "Browse Insectus. CC0 1.0. Specimen Gallery."
    assert_includes response.body, specimen_asset_path(asset)
  end

  test "vernacular name stays blank when specimen labels disagree" do
    assert_nil @plant.vernacular_name
  end

  test "vernacular name uses one shared common name" do
    @plant.specimen_assets.update_all(common_name: "Browse Plant")
    assert_equal "Browse Plant", @plant.vernacular_name
  end

  test "a species with both licenses is not cited as CC0" do
    @plant.specimen_assets.first.update_columns(license: "CC_BY")
    assert_equal "mixed licenses", @plant.public_license_label
  end

  test "browse totals follow the category filter" do
    get browse_path, params: { group: "plant" }
    assert_response :success
    assert_includes response.body, "1 species"
    assert_includes response.body, "2 images"
    assert_not_includes response.body, "3 images"
    assert_not_includes response.body, "2 species"
  end

  private

  def with_query_vector(vector)
    original = SpecimenEmbedder.method(:embed_query)
    SpecimenEmbedder.define_singleton_method(:embed_query) { |_query| vector }
    yield
  ensure
    SpecimenEmbedder.define_singleton_method(:embed_query) { |query| original.call(query) }
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
  ensure
    file&.close!
  end
end
