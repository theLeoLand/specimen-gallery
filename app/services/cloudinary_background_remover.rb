# app/services/cloudinary_background_remover.rb
# Uploads an image to Cloudinary and returns a background-removed PNG

require "open-uri"
require "tempfile"

class CloudinaryBackgroundRemover
  class RemovalError < StandardError; end

  attr_reader :public_id, :transformed_url, :original_url

  def initialize(uploaded_file)
    @uploaded_file = uploaded_file
    @public_id = nil
    @transformed_url = nil
    @original_url = nil
  end

  # Uploads to Cloudinary with background removal transformation
  # Returns self on success, raises RemovalError on failure
  def call
    validate_file!
    upload_and_transform!
    self
  rescue Cloudinary::Api::Error, Cloudinary::CarrierWave::UploadError => e
    raise RemovalError, "Cloudinary upload failed: #{e.message}"
  rescue => e
    raise RemovalError, "Background removal failed: #{e.message}"
  end

  # Downloads the transformed image to a Tempfile
  # Returns the Tempfile (caller must close/unlink)
  def download_transformed
    raise RemovalError, "No transformed URL available" unless @transformed_url

    tempfile = Tempfile.new(["bg_removed", ".png"])
    tempfile.binmode

    URI.open(@transformed_url) do |remote|
      tempfile.write(remote.read)
    end

    tempfile.rewind
    tempfile
  rescue => e
    tempfile&.close
    tempfile&.unlink
    raise RemovalError, "Failed to download transformed image: #{e.message}"
  end

  private

  def validate_file!
    unless @uploaded_file.respond_to?(:tempfile) || @uploaded_file.respond_to?(:path)
      raise RemovalError, "Invalid file object"
    end
  end

  def upload_and_transform!
    # Upload to Cloudinary with background removal
    # Using the 'background_removal' effect which requires Cloudinary AI add-on
    # Fallback: use 'e_background_removal' transformation
    result = Cloudinary::Uploader.upload(
      file_path,
      folder: "specimen_gallery/uploads",
      resource_type: "image",
      format: "png",
      transformation: [
        { effect: "background_removal" },
        { quality: "auto:best" }
      ]
    )

    @public_id = result["public_id"]
    @original_url = result["secure_url"]

    # Build the transformed URL with background removal
    # The upload with transformation should already apply it,
    # but we can also explicitly request it
    @transformed_url = Cloudinary::Utils.cloudinary_url(
      @public_id,
      format: "png",
      effect: "background_removal",
      quality: "auto:best",
      secure: true
    )

    # Verify we got valid URLs
    raise RemovalError, "Missing public_id from Cloudinary" unless @public_id
    raise RemovalError, "Missing URL from Cloudinary" unless @transformed_url
  end

  def file_path
    if @uploaded_file.respond_to?(:tempfile)
      @uploaded_file.tempfile.path
    else
      @uploaded_file.path
    end
  end
end


