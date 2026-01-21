require "test_helper"

class ProfanityDetectorTest < ActiveSupport::TestCase
  test "detects profanity in specimen_name" do
    detector = ProfanityDetector.new(specimen_name: "This shit specimen")
    assert detector.flagged?
    assert_includes detector.flagged_fields, :specimen_name
  end

  test "detects profanity in common_name" do
    detector = ProfanityDetector.new(specimen_name: "Quartz", common_name: "damn crystal")
    assert detector.flagged?
    assert_includes detector.flagged_fields, :common_name
  end

  test "detects profanity in multiple fields" do
    detector = ProfanityDetector.new(specimen_name: "shit rock", common_name: "damn thing")
    assert detector.flagged?
    assert_equal 2, detector.flagged_fields.count
  end

  test "does not flag clean text" do
    detector = ProfanityDetector.new(specimen_name: "Beautiful Quartz Crystal", common_name: "Rose Quartz")
    assert_not detector.flagged?
    assert_empty detector.flagged_fields
  end

  test "case insensitive detection" do
    detector = ProfanityDetector.new(specimen_name: "DAMN Good Specimen")
    assert detector.flagged?
  end

  test "matches whole words only" do
    # "ass" should not match in "class" or "grass"
    detector = ProfanityDetector.new(specimen_name: "Grasshopper", common_name: "Classic bug")
    assert_not detector.flagged?
  end

  test "handles blank fields" do
    detector = ProfanityDetector.new(specimen_name: "", common_name: nil)
    assert_not detector.flagged?
  end

  test "ignores unknown fields" do
    detector = ProfanityDetector.new(specimen_name: "Quartz", unknown_field: "shit")
    assert_not detector.flagged?
  end

  test "to_qc_flags returns empty hash when clean" do
    detector = ProfanityDetector.new(specimen_name: "Quartz")
    assert_equal({}, detector.to_qc_flags)
  end

  test "to_qc_flags returns structured data when flagged" do
    detector = ProfanityDetector.new(specimen_name: "fuck this")
    flags = detector.to_qc_flags

    assert flags["profanity_flagged"]
    assert_includes flags["profanity_fields"], "specimen_name"
    assert flags["flagged_at"].present?
  end
end
