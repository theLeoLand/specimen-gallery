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
