# app/controllers/specimen_assets_controller.rb
class SpecimenAssetsController < ApplicationController
  def new
    @specimen_asset = SpecimenAsset.new
  end

  def create
    scientific_name = params[:specimen_asset][:scientific_name].to_s.strip
    uploaded_file = params[:specimen_asset][:image]
    remove_background = params[:specimen_asset][:remove_background] == "1"

    # Match against GBIF
    gbif_match = GbifClient.match(scientific_name)
    is_good_match = GbifClient.good_match?(gbif_match)

    # Find or create taxon, enriching with GBIF data if available
    taxon = find_or_create_taxon_with_gbif(scientific_name, gbif_match, is_good_match)

    @specimen_asset = taxon.specimen_assets.build(specimen_asset_params_without_image)
    @specimen_asset.status = "pending"
    @specimen_asset.needs_review = !is_good_match

    # Check file size before attempting Cloudinary (10MB limit on free tier)
    if uploaded_file.present? && uploaded_file.size > 10.megabytes
      @specimen_asset.errors.add(:image, "is too large (#{(uploaded_file.size / 1.megabyte.to_f).round(1)}MB). Maximum is 10MB.")
      flash.now[:alert] = "Image too large. Please use a smaller file (under 10MB)."
      render :new, status: :unprocessable_entity
      return
    end

    # Handle image attachment with optional background removal
    bg_removal_failed = false
    bg_removal_total_fail = false
    
    if remove_background && uploaded_file.present?
      result = attach_with_background_removal(uploaded_file)
      if result == true
        # Success - bg removed
      elsif result == false
        # Partial fail - fell back to original PNG/WebP
        bg_removal_failed = true
      else
        # Total fail - couldn't process and can't fallback (e.g., JPG with no bg removal)
        bg_removal_total_fail = true
      end
    elsif uploaded_file.present?
      @specimen_asset.image.attach(uploaded_file)
    end

    # Flag for review if background removal failed but we have a fallback
    if bg_removal_failed
      @specimen_asset.needs_review = true
      flash[:alert] = "Background removal failed — submitted original image for review."
    end
    
    # If total failure, render form with errors (the specific error is already in @specimen_asset.errors)
    if bg_removal_total_fail
      render :new, status: :unprocessable_entity
      return
    end

    if @specimen_asset.save
      redirect_to root_path, notice: submission_notice(is_good_match, bg_removal_failed)
    else
      render :new, status: :unprocessable_entity
    end
  rescue ActiveRecord::RecordInvalid => e
    @specimen_asset = SpecimenAsset.new(specimen_asset_params_without_image)
    @specimen_asset.errors.add(:base, e.message)
    render :new, status: :unprocessable_entity
  end

  private

  def specimen_asset_params_without_image
    params.require(:specimen_asset).permit(
      :common_name,
      :license,
      :attribution_name,
      :attribution_url
    )
  end

  def attach_with_background_removal(uploaded_file)
    # Save original file to temp first (stream may close after Cloudinary upload)
    original_tempfile = Tempfile.new(["original", File.extname(uploaded_file.original_filename)])
    original_tempfile.binmode
    original_tempfile.write(uploaded_file.read)
    original_tempfile.rewind
    uploaded_file.rewind rescue nil

    remover = CloudinaryBackgroundRemover.new(uploaded_file)
    remover.call

    # Download the transformed image
    transformed_tempfile = remover.download_transformed

    # Read into memory to ensure we have the full file before attaching
    transformed_tempfile.rewind
    image_data = transformed_tempfile.read
    
    # Create a new StringIO for ActiveStorage (more reliable than tempfile)
    image_io = StringIO.new(image_data)
    image_io.set_encoding(Encoding::BINARY)

    # Attach the transformed PNG
    @specimen_asset.image.attach(
      io: image_io,
      filename: generate_png_filename(uploaded_file),
      content_type: "image/png"
    )

    # Store Cloudinary metadata
    @specimen_asset.bg_removed = true
    @specimen_asset.cloudinary_public_id = remover.public_id
    @specimen_asset.cloudinary_asset_url = remover.transformed_url

    # Cleanup tempfiles (safe to do now since we read into memory)
    transformed_tempfile.close rescue nil
    transformed_tempfile.unlink rescue nil
    original_tempfile.close rescue nil
    original_tempfile.unlink rescue nil

    true
  rescue CloudinaryBackgroundRemover::RemovalError => e
    Rails.logger.warn("Background removal failed: #{e.message}")
    cleanup_tempfile(original_tempfile)
    
    # Only fallback to original if it's PNG/WebP (otherwise it would fail validation anyway)
    # Extract a user-friendly error message
    error_msg = extract_cloudinary_error(e.message)
    
    if uploaded_file.content_type.in?(%w[image/png image/webp])
      original_tempfile = Tempfile.new(["original", File.extname(uploaded_file.original_filename)])
      original_tempfile.binmode
      uploaded_file.rewind rescue nil
      original_tempfile.write(uploaded_file.read)
      original_tempfile.rewind
      
      @specimen_asset.image.attach(
        io: StringIO.new(original_tempfile.read),
        filename: uploaded_file.original_filename,
        content_type: uploaded_file.content_type
      )
      @specimen_asset.bg_removed = false
      cleanup_tempfile(original_tempfile)
      false # indicates bg removal failed but we have a fallback
    else
      # Can't fallback - add specific error
      @specimen_asset.errors.add(:image, error_msg)
      nil
    end
  rescue => e
    Rails.logger.error("Unexpected error during background removal: #{e.class} - #{e.message}")
    cleanup_tempfile(original_tempfile)
    
    # Extract a user-friendly error message
    error_msg = extract_cloudinary_error(e.message)
    
    # Same logic: only fallback if original is PNG/WebP
    if uploaded_file.content_type.in?(%w[image/png image/webp])
      original_tempfile = Tempfile.new(["original", File.extname(uploaded_file.original_filename)])
      original_tempfile.binmode
      uploaded_file.rewind rescue nil
      original_tempfile.write(uploaded_file.read)
      original_tempfile.rewind
      
      @specimen_asset.image.attach(
        io: StringIO.new(original_tempfile.read),
        filename: uploaded_file.original_filename,
        content_type: uploaded_file.content_type
      )
      @specimen_asset.bg_removed = false
      cleanup_tempfile(original_tempfile)
      false
    else
      @specimen_asset.errors.add(:image, error_msg)
      nil
    end
  end
  
  def cleanup_tempfile(tempfile)
    return unless tempfile
    tempfile.close rescue nil
    tempfile.unlink rescue nil
  end

  def extract_cloudinary_error(message)
    if message.include?("File size too large")
      "is too large for background removal. Please use a smaller file (under 10MB) or upload a PNG/WebP directly."
    elsif message.include?("Invalid image")
      "could not be processed. Please try a different image."
    elsif message.include?("effect")
      "background removal service unavailable. Please upload a PNG/WebP with transparent background instead."
    else
      "background removal failed. Please try again or upload a PNG/WebP with transparent background."
    end
  end

  def generate_png_filename(uploaded_file)
    original_name = uploaded_file.original_filename || "image"
    base_name = File.basename(original_name, ".*")
    "#{base_name}_cutout.png"
  end

  def find_or_create_taxon_with_gbif(scientific_name, gbif_match, is_good_match)
    canonical = is_good_match && gbif_match ? gbif_match[:canonical_name] : nil
    lookup_name = canonical.presence || scientific_name

    taxon = Taxon.where("LOWER(scientific_name) = LOWER(?)", lookup_name).first

    if taxon
      if is_good_match && gbif_match && taxon.gbif_key.nil?
        taxon.update(gbif_attributes(gbif_match))
      end
      taxon
    else
      attrs = { scientific_name: lookup_name }
      if is_good_match && gbif_match
        attrs.merge!(gbif_attributes(gbif_match))
      end
      Taxon.create!(attrs)
    end
  end

  def gbif_attributes(match)
    {
      taxon_source: "gbif",
      taxon_id: match[:usage_key]&.to_s,
      gbif_key: match[:usage_key],
      gbif_rank: match[:rank],
      gbif_canonical_name: match[:canonical_name],
      gbif_confidence: match[:confidence],
      gbif_match_type: match[:match_type]
    }
  end

  def submission_notice(is_good_match, bg_removal_failed)
    base = if is_good_match
      "Thank you! Your specimen is pending review and will appear once approved."
    else
      "Thank you! Your specimen is pending review. The scientific name could not be verified."
    end

    if bg_removal_failed
      base + " (Background removal failed — original image submitted)"
    else
      base
    end
  end
end
