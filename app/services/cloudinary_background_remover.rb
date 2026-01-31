# app/services/cloudinary_background_remover.rb
# Uploads an image to Cloudinary and returns a background-removed PNG
# Automatically upscales small images to ensure they display well in cards

require "open-uri"
require "tempfile"

class CloudinaryBackgroundRemover
  class RemovalError < StandardError; end

  # Minimum size for the longest edge (upscale if smaller)
  MIN_DIMENSION = 800

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
  rescue Cloudinary::Api::Error => e
    Rails.logger.error("CloudinaryBackgroundRemover: Cloudinary API error - #{e.class}: #{e.message}")
    raise RemovalError, "Cloudinary upload failed: #{e.message}"
  rescue => e
    Rails.logger.error("CloudinaryBackgroundRemover: Unexpected error - #{e.class}: #{e.message}")
    Rails.logger.error(e.backtrace.first(5).join("\n"))
    raise RemovalError, "Background removal failed: #{e.message}"
  end

  # Downloads the transformed image to a Tempfile
  # Automatically upscales if the image is too small
  # Returns the Tempfile (caller must close/unlink)
  def download_transformed
    raise RemovalError, "No transformed URL available" unless @transformed_url

    # First, get image info to check dimensions
    dimensions = fetch_image_dimensions

    # Determine if we need to upscale
    url_to_download = if needs_upscaling?(dimensions)
      Rails.logger.info("CloudinaryBackgroundRemover: Image too small (#{dimensions[:width]}x#{dimensions[:height]}), upscaling...")
      upscaled_url(dimensions)
    else
      @transformed_url
    end

    tempfile = Tempfile.new([ "bg_removed", ".png" ])
    tempfile.binmode

    URI.open(url_to_download) do |remote|
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
    Rails.logger.info("CloudinaryBackgroundRemover: Starting upload to Cloudinary...")

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

    Rails.logger.info("CloudinaryBackgroundRemover: Upload successful, public_id=#{result['public_id']}")

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

  # Fetch image dimensions from Cloudinary
  def fetch_image_dimensions
    info = Cloudinary::Api.resource(@public_id)
    { width: info["width"], height: info["height"] }
  rescue => e
    Rails.logger.warn("CloudinaryBackgroundRemover: Could not fetch dimensions: #{e.message}")
    { width: MIN_DIMENSION, height: MIN_DIMENSION } # Assume OK if can't check
  end

  # Check if the image needs upscaling
  def needs_upscaling?(dimensions)
    max_dim = [ dimensions[:width], dimensions[:height] ].max
    max_dim < MIN_DIMENSION
  end

  # Generate a Cloudinary URL with upscaling transformation
  def upscaled_url(dimensions)
    # Calculate scale factor to make longest edge = MIN_DIMENSION
    max_dim = [ dimensions[:width], dimensions[:height] ].max
    scale_factor = (MIN_DIMENSION.to_f / max_dim).ceil

    # Use Cloudinary's scale transformation
    # c_scale with w_ or h_ will maintain aspect ratio
    if dimensions[:width] >= dimensions[:height]
      Cloudinary::Utils.cloudinary_url(
        @public_id,
        format: "png",
        transformation: [
          { effect: "background_removal" },
          { width: MIN_DIMENSION, crop: "scale" },
          { quality: "auto:best" }
        ],
        secure: true
      )
    else
      Cloudinary::Utils.cloudinary_url(
        @public_id,
        format: "png",
        transformation: [
          { effect: "background_removal" },
          { height: MIN_DIMENSION, crop: "scale" },
          { quality: "auto:best" }
        ],
        secure: true
      )
    end
  end
end
