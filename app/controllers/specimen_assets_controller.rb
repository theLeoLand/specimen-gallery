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

    # Handle image attachment with optional background removal
    bg_removal_failed = false
    if remove_background && uploaded_file.present?
      bg_removal_failed = !attach_with_background_removal(uploaded_file)
    elsif uploaded_file.present?
      @specimen_asset.image.attach(uploaded_file)
    end

    # Flag for review if background removal failed
    if bg_removal_failed
      @specimen_asset.needs_review = true
      flash[:alert] = "Background removal failed — submitted original image for review."
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

    # Fallback: attach original file from our saved copy
    original_tempfile.rewind
    original_data = original_tempfile.read
    @specimen_asset.image.attach(
      io: StringIO.new(original_data),
      filename: uploaded_file.original_filename,
      content_type: uploaded_file.content_type
    )
    @specimen_asset.bg_removed = false
    original_tempfile.close rescue nil
    original_tempfile.unlink rescue nil

    false
  rescue => e
    Rails.logger.error("Unexpected error during background removal: #{e.class} - #{e.message}")

    # Fallback: attach original file from our saved copy
    if original_tempfile && !original_tempfile.closed?
      original_tempfile.rewind
      original_data = original_tempfile.read
      @specimen_asset.image.attach(
        io: StringIO.new(original_data),
        filename: uploaded_file.original_filename,
        content_type: uploaded_file.content_type
      )
      original_tempfile.close rescue nil
      original_tempfile.unlink rescue nil
    end
    @specimen_asset.bg_removed = false

    false
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
