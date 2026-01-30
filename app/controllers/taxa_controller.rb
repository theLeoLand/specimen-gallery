# app/controllers/taxa_controller.rb
class TaxaController < ApplicationController
  def index
    @taxa = Taxon.with_approved_assets
    @current_group = params[:group].presence
    @groups = TaxonGroupResolver.all_with_metadata

    # Store filter params
    @filters = {
      sex: params[:sex].presence,
      life_stage: params[:life_stage].presence,
      view: params[:view].presence,
      part: params[:part].presence
    }

    # Filter by group
    if @current_group.present? && @current_group != "all"
      @taxa = @taxa.where(group: @current_group)
    end

    # Search by name (specimen_name, scientific_name, or common_name)
    if params[:q].present?
      search_term = "%#{params[:q]}%"
      @taxa = @taxa
        .left_joins(:specimen_assets)
        .where("taxa.scientific_name ILIKE :q OR specimen_assets.specimen_name ILIKE :q OR specimen_assets.common_name ILIKE :q", q: search_term)
        .distinct
    end

    # Filter by specimen traits (only show taxa that have matching specimens)
    if @filters.values.any?(&:present?)
      @taxa = @taxa
        .joins(:specimen_assets)
        .where(specimen_assets: { status: "approved" })
        .then { |scope| @filters[:sex].present? ? scope.where(specimen_assets: { sex: @filters[:sex] }) : scope }
        .then { |scope| @filters[:life_stage].present? ? scope.where(specimen_assets: { life_stage: @filters[:life_stage] }) : scope }
        .then { |scope| @filters[:view].present? ? scope.where(specimen_assets: { view: @filters[:view] }) : scope }
        .then { |scope| @filters[:part].present? ? scope.where(specimen_assets: { part: @filters[:part] }) : scope }
        .distinct
    end

    @taxa = @taxa.order(:scientific_name)
  end

  def show
    @taxon = Taxon.find(params[:id])
    @specimen_assets = @taxon.approved_assets.includes(image_attachment: :blob)

    if @specimen_assets.empty?
      head :not_found
    end
  end

  # GET /taxa/suggest?q=...
  # Returns JSON array of GBIF suggestions for autocomplete
  def suggest
    query = params[:q].to_s.strip
    suggestions = GbifClient.suggest(query, limit: 8)

    render json: suggestions.map { |s|
      {
        key: s[:key],
        name: s[:scientific_name],
        canonical: s[:canonical_name],
        rank: s[:rank]
      }
    }
  end
end
