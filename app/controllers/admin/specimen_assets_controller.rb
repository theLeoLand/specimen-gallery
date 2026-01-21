# app/controllers/admin/specimen_assets_controller.rb
module Admin
  class SpecimenAssetsController < ApplicationController
    include AdminAuth

    ALLOWED_STATUSES = %w[approved rejected pending].freeze

    def index
      @filter = params[:filter] || "pending"

      @specimen_assets = case @filter
      when "approved"
        SpecimenAsset.where(status: "approved").order(created_at: :desc)
      when "all"
        SpecimenAsset.order(created_at: :desc)
      else
        SpecimenAsset.where(status: "pending").order(created_at: :desc)
      end

      @pending_count = SpecimenAsset.where(status: "pending").count
      @approved_count = SpecimenAsset.where(status: "approved").count
      @flags_count = Flag.open_flags.count
    end

    def edit
      @specimen_asset = SpecimenAsset.find(params[:id])
    end

    def update
      @specimen_asset = SpecimenAsset.find(params[:id])

      # Quick status-only update (from approve/reject buttons)
      if params[:status].present? && !params[:specimen_asset].present?
        handle_status_update
        return
      end

      # Full form update
      handle_form_update
    end

    def destroy
      @specimen_asset = SpecimenAsset.find(params[:id])
      @specimen_asset.destroy
      redirect_to admin_specimen_assets_path, notice: "Specimen deleted."
    end

    def unpublish
      @specimen_asset = SpecimenAsset.find(params[:id])

      unless @specimen_asset.status == "approved"
        redirect_back fallback_location: admin_specimen_assets_path,
                      alert: "Only approved specimens can be unpublished."
        return
      end

      @specimen_asset.update!(status: "pending", needs_review: true)
      redirect_to admin_specimen_assets_path(filter: "pending"),
                  notice: "Specimen moved back to pending queue for review."
    end

    private

    def handle_status_update
      new_status = params[:status]

      unless ALLOWED_STATUSES.include?(new_status)
        head :unprocessable_entity
        return
      end

      if @specimen_asset.update(status: new_status)
        redirect_back fallback_location: admin_specimen_assets_path,
                      notice: "Specimen #{new_status}."
      else
        redirect_back fallback_location: admin_specimen_assets_path,
                      alert: "Failed to update: #{@specimen_asset.errors.full_messages.join(', ')}"
      end
    end

    def handle_form_update
      specimen_name = params[:specimen_asset][:specimen_name].to_s.strip
      scientific_name = params[:specimen_asset][:scientific_name].to_s.strip
      taxon_group = params[:specimen_asset][:taxon_group].presence

      # Update or create taxon if scientific name changed
      if scientific_name.present? && scientific_name != @specimen_asset.taxon&.scientific_name
        taxon = find_or_create_taxon(scientific_name, taxon_group)
        @specimen_asset.taxon = taxon
      elsif taxon_group.present? && taxon_group != @specimen_asset.taxon&.group
        # Update group on existing taxon
        @specimen_asset.taxon&.update(group: taxon_group)
      end

      # Update specimen fields
      @specimen_asset.specimen_name = specimen_name if specimen_name.present?
      @specimen_asset.common_name = params[:specimen_asset][:common_name]
      @specimen_asset.license = params[:specimen_asset][:license]
      @specimen_asset.attribution_name = params[:specimen_asset][:attribution_name]
      @specimen_asset.attribution_url = params[:specimen_asset][:attribution_url]
      @specimen_asset.needs_review = params[:specimen_asset][:needs_review] == "1"

      # Update status if provided
      if params[:specimen_asset][:status].present? && ALLOWED_STATUSES.include?(params[:specimen_asset][:status])
        @specimen_asset.status = params[:specimen_asset][:status]
      end

      if @specimen_asset.save
        redirect_to admin_specimen_assets_path, notice: "Specimen updated successfully."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def find_or_create_taxon(scientific_name, user_group = nil)
      # Try GBIF lookup
      gbif_match = GbifClient.match(scientific_name)
      is_good_match = GbifClient.good_match?(gbif_match)

      canonical = is_good_match && gbif_match ? gbif_match[:canonical_name] : nil
      lookup_name = canonical.presence || scientific_name

      taxon = Taxon.where("LOWER(scientific_name) = LOWER(?)", lookup_name).first

      if taxon
        # Update with GBIF data if we have it and taxon doesn't
        if is_good_match && gbif_match && taxon.gbif_key.nil?
          attrs = gbif_attributes(gbif_match)
          attrs[:group] = TaxonGroupResolver.resolve(gbif_match) if taxon.group.blank?
          taxon.update(attrs)
        elsif user_group.present?
          taxon.update(group: user_group)
        end
        taxon
      else
        attrs = { scientific_name: lookup_name }
        if is_good_match && gbif_match
          attrs.merge!(gbif_attributes(gbif_match))
          attrs[:group] = TaxonGroupResolver.resolve(gbif_match)
        elsif user_group.present?
          attrs[:group] = user_group
        else
          attrs[:group] = "other"
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
  end
end
