require "test_helper"

class FlagTest < ActiveSupport::TestCase
  def setup
    # Create a minimal taxon and specimen for testing
    @taxon = Taxon.create!(scientific_name: "Test Species", group: "other")
    @specimen = @taxon.specimen_assets.build(
      specimen_name: "Test Specimen",
      status: "approved",
      license: "CC0"
    )
    # Attach image before saving (required by model validation)
    @specimen.image.attach(
      io: File.open(Rails.root.join("test/fixtures/files/test_image.png")),
      filename: "test.png",
      content_type: "image/png"
    )
    @specimen.save!
  end

  test "valid flag with required fields" do
    flag = Flag.new(
      specimen_asset: @specimen,
      reason: "wrong_name",
      status: "open"
    )
    assert flag.valid?
  end

  test "requires reason" do
    flag = Flag.new(specimen_asset: @specimen, status: "open")
    assert_not flag.valid?
    assert_includes flag.errors[:reason], "can't be blank"
  end

  test "requires valid reason" do
    flag = Flag.new(specimen_asset: @specimen, reason: "invalid_reason", status: "open")
    assert_not flag.valid?
    assert_includes flag.errors[:reason], "is not included in the list"
  end

  test "requires status" do
    flag = Flag.new(specimen_asset: @specimen, reason: "wrong_name", status: nil)
    assert_not flag.valid?
  end

  test "requires valid status" do
    flag = Flag.new(specimen_asset: @specimen, reason: "wrong_name", status: "invalid")
    assert_not flag.valid?
    assert_includes flag.errors[:status], "is not included in the list"
  end

  test "defaults to open status" do
    flag = Flag.new(specimen_asset: @specimen, reason: "wrong_name")
    assert_equal "open", flag.status
  end

  test "reason_label returns human-readable label" do
    flag = Flag.new(reason: "wrong_name")
    assert_equal "Wrong name/identification", flag.reason_label
  end

  test "open scope returns only open flags" do
    Flag.create!(specimen_asset: @specimen, reason: "wrong_name", status: "open")
    Flag.create!(specimen_asset: @specimen, reason: "duplicate", status: "resolved")

    assert_equal 1, Flag.open_flags.count
    assert_equal "open", Flag.open_flags.first.status
  end

  test "status helper methods" do
    flag = Flag.new(status: "open")
    assert flag.open?
    assert_not flag.resolved?
    assert_not flag.dismissed?

    flag.status = "resolved"
    assert_not flag.open?
    assert flag.resolved?
  end
end
