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

  test "browse totals follow the category filter" do
    get browse_path, params: { group: "plant" }
    assert_response :success
    assert_includes response.body, "1 species"
    assert_includes response.body, "2 images"
    assert_not_includes response.body, "3 images"
    assert_not_includes response.body, "2 species"
  end

  private

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
